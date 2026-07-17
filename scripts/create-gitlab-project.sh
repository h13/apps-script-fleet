#!/usr/bin/env bash
set -euo pipefail

# Apps Script Fleet — Create GitLab Project (Free Tier)
#
# Creates a new GitLab repository from this template.
# Use this instead of "Create from template" on GitLab Free tier.
#
# Prerequisites:
#   - glab CLI authenticated for the target GitLab host
#   - Run from the root of the apps-script-fleet template repo
#
# Usage:
#   ./scripts/create-gitlab-project.sh --group <namespace> --name <project-name> [options]
#
# After creation, cd into the new project and run init.sh:
#   cd ../<project-name>
#   ./scripts/init.sh --title "My Script" [--gcp-project <NUMBER>]

GROUP=""
PROJECT_NAME=""
HOSTNAME=""
VISIBILITY="private"
DESCRIPTION=""

usage() {
  cat <<EOF
Usage: $0 --group <namespace> --name <project-name> [options]

Create a new GitLab repository from the Apps Script Fleet template.

Required:
  --group <namespace>       GitLab group or namespace (e.g., my-org, my-org/sub-group)
  --name <project-name>     Repository name (e.g., slack-notifier)

Options:
  --hostname <host>         GitLab hostname (default: auto-detect from glab auth)
  --visibility <level>      private (default), internal, or public
  --description <text>      Project description
  --help                    Show this help

Example:
  $0 --group my-org --name slack-notifier
  $0 --group my-org --name form-mailer --visibility internal --description "Contact form mailer"

After creation:
  cd ../<project-name>
  ./scripts/init.sh --title "My Script" --gcp-project 123456789
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case $1 in
    --group)
      GROUP="$2"
      shift 2
      ;;
    --name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --visibility)
      VISIBILITY="$2"
      shift 2
      ;;
    --description)
      DESCRIPTION="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed."
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

[[ -n "$GROUP" ]] || die "--group is required. Run '$0 --help' for usage."
[[ -n "$PROJECT_NAME" ]] || die "--name is required. Run '$0 --help' for usage."

case "$VISIBILITY" in
  private|internal|public) ;;
  *) die "Invalid --visibility '$VISIBILITY'. Must be: private, internal, or public." ;;
esac

# Must be run from the template repo root
[[ -f ".templatesyncignore" ]] || die "Must be run from the apps-script-fleet template repository root."

require_cmd glab
require_cmd git
require_cmd node

# Detect hostname from glab auth if not specified
if [[ -z "$HOSTNAME" ]]; then
  HOSTNAME=$(glab auth status 2>&1 | grep -m1 "Logged in to" | sed 's/.*Logged in to //' | sed 's/ .*//' | tr -d '[:space:]') || true
  [[ -n "$HOSTNAME" ]] || die "Could not detect GitLab hostname. Specify --hostname or run 'glab auth login'."
fi

# Verify glab is authenticated for the target host
if ! glab auth status --hostname "$HOSTNAME" >/dev/null 2>&1; then
  die "glab is not authenticated for $HOSTNAME. Run 'glab auth login --hostname $HOSTNAME'."
fi

# Check destination directory doesn't already exist
DEST_DIR="../${PROJECT_NAME}"
if [[ -d "$DEST_DIR" ]]; then
  die "Directory '$DEST_DIR' already exists. Remove it or choose a different --name."
fi

echo "=== Apps Script Fleet — Create GitLab Project ==="
echo ""
echo "  Host:       ${HOSTNAME}"
echo "  Group:      ${GROUP}"
echo "  Name:       ${PROJECT_NAME}"
echo "  Visibility: ${VISIBILITY}"
[[ -n "$DESCRIPTION" ]] && echo "  Description: ${DESCRIPTION}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Create GitLab project
# ---------------------------------------------------------------------------

echo "Creating GitLab project..."

# Resolve namespace path to numeric ID (GitLab API requires namespace_id)
ENCODED_GROUP=$(echo "$GROUP" | sed 's|/|%2F|g')
NAMESPACE_ID=$(glab api "namespaces/${ENCODED_GROUP}" --hostname "$HOSTNAME" 2>/dev/null \
  | node -e "
    const data = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
    process.stdout.write(String(data.id || ''));
  ") || true
[[ -n "$NAMESPACE_ID" ]] || die "Could not find namespace '${GROUP}' on ${HOSTNAME}. Check the group path."

CREATE_ARGS=(api -X POST "projects"
  --hostname "$HOSTNAME"
  --raw-field "name=${PROJECT_NAME}"
  --raw-field "path=${PROJECT_NAME}"
  --raw-field "namespace_id=${NAMESPACE_ID}"
  --raw-field "visibility=${VISIBILITY}"
  --raw-field "initialize_with_readme=false"
)

if [[ -n "$DESCRIPTION" ]]; then
  CREATE_ARGS+=(--raw-field "description=${DESCRIPTION}")
fi

CREATE_RESULT=$(glab "${CREATE_ARGS[@]}" 2>&1) || die "Failed to create project: ${CREATE_RESULT}"

# Extract clone URL
CLONE_URL=$(echo "$CREATE_RESULT" | node -e "
  const data = JSON.parse(require('fs').readFileSync('/dev/stdin', 'utf8'));
  process.stdout.write(data.http_url_to_clone || '');
")

[[ -n "$CLONE_URL" ]] || die "Could not extract clone URL from API response."

echo "  Created: ${CLONE_URL}"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Copy template files to new project
# ---------------------------------------------------------------------------

echo "Scaffolding project files..."

mkdir -p "$DEST_DIR"

# Files to copy: everything tracked in git EXCEPT template-repo-only files
# Exclude: docs/ (images, setup guides — will be available via template sync),
#          README.md/README.ja.md (user should write their own),
#          CONTRIBUTING.md (template-repo-only),
#          .github/workflows/publish.yml (template-repo-only),
#          docs/superpowers/ (design docs),
#          scripts/create-gitlab-project.sh (this script, template-repo-only)
EXCLUDE_PATTERNS=(
  "^docs/"
  "^README\\.md$"
  "^README\\.ja\\.md$"
  "^CONTRIBUTING\\.md$"
  "^\\.github/workflows/publish\\.yml$"
  "^\\.claude/"
  "^scripts/create-gitlab-project\\.sh$"
)

# Build grep exclude pattern
EXCLUDE_REGEX=$(printf "%s\n" "${EXCLUDE_PATTERNS[@]}" | paste -sd'|' -)

# Get list of files to copy
FILES=$(git ls-files | grep -Ev "$EXCLUDE_REGEX")

# Copy files preserving directory structure
while IFS= read -r file; do
  dest_file="${DEST_DIR}/${file}"
  dest_subdir=$(dirname "$dest_file")
  mkdir -p "$dest_subdir"
  cp "$file" "$dest_file"
done <<< "$FILES"

# Create a minimal README for the new project
cat > "${DEST_DIR}/README.md" <<EOF
# ${PROJECT_NAME}

Built with [Apps Script Fleet](https://github.com/h13/apps-script-fleet).

## Development

\`\`\`bash
pnpm install
pnpm run check    # lint + typecheck + test
pnpm run deploy   # deploy to dev
\`\`\`

## Setup

See the [setup guide](https://github.com/h13/apps-script-fleet/blob/main/docs/setup-gitlab.md) for CI/CD configuration.
EOF

echo "  Copied $(echo "$FILES" | wc -l | tr -d ' ') files"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Initialize git and push
# ---------------------------------------------------------------------------

echo "Pushing to GitLab..."

cd "$DEST_DIR"
git init -b main
git remote add origin "$CLONE_URL"
git add -A
git commit -m "Initial commit from apps-script-fleet template" --quiet

# Use glab-compatible auth for push
PUSH_URL=$(echo "$CLONE_URL" | sed "s|https://|https://oauth2:$(glab auth token --hostname "$HOSTNAME")@|")
git push -u "$PUSH_URL" main --quiet 2>/dev/null || die "Failed to push to GitLab. Check your glab authentication."

# Replace remote URL with clean version (no token)
git remote set-url origin "$CLONE_URL"

echo "  Pushed to: ${CLONE_URL}"
echo ""

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo "Done!"
echo ""
echo "  cd ../${PROJECT_NAME}"
echo "  pnpm install"
echo "  ./scripts/init.sh --title \"${PROJECT_NAME}\" [--gcp-project <NUMBER>]"
echo ""
echo "  Project URL: https://${HOSTNAME}/${GROUP}/${PROJECT_NAME}"
