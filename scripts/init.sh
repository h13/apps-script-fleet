#!/usr/bin/env bash
set -euo pipefail

# Apps Script Fleet — Project Init
#
# Prerequisites:
#   - ~/.clasprc.json exists (shared via org password manager)
#   - GitHub: gh CLI authenticated | GitLab: GITLAB_TOKEN env var set
#   - Node.js + pnpm installed
#
# Usage:
#   ./scripts/init.sh [--title "Project Name"] [--type standalone|sheets|docs|slides|forms]

TITLE=""
GAS_TYPE="standalone"

while [[ $# -gt 0 ]]; do
  case $1 in
    --title)
      TITLE="$2"
      shift 2
      ;;
    --type)
      GAS_TYPE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
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

extract_script_id() {
  local file="$1"
  python3 -c "import sys,json; print(json.load(open('$file'))['scriptId'])"
}

# Extract host from git remote URL
extract_host() {
  local url="$1"
  if [[ "$url" == git@* ]]; then
    # git@host:path → host
    local without_prefix="${url#git@}"
    echo "${without_prefix%%:*}"
  else
    # https://host/path → host
    local without_scheme="${url#*://}"
    echo "${without_scheme%%/*}"
  fi
}

# Extract path from git remote URL (without .git suffix)
extract_path() {
  local url="$1"
  local path
  if [[ "$url" == git@* ]]; then
    path="${url#*:}"
  else
    local without_scheme="${url#*://}"
    path="${without_scheme#*/}"
  fi
  # Remove .git suffix
  echo "${path%.git}"
}

# ---------------------------------------------------------------------------
# Detect platform from git remote
# ---------------------------------------------------------------------------

detect_platform() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null) || die "No git remote 'origin' found."

  if echo "$remote_url" | grep -q "github"; then
    echo "github"
  elif echo "$remote_url" | grep -q "gitlab"; then
    echo "gitlab"
  else
    die "Cannot detect platform from remote URL: $remote_url"
  fi
}

# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------

gh_set_secret() {
  local name="$1" value="$2"
  echo "$value" | gh secret set "$name"
  echo "  Set secret: $name"
}

gh_set_variable() {
  local name="$1" value="$2"
  # gh variable set fails if already exists; delete first (ignore error)
  gh variable delete "$name" 2>/dev/null || true
  gh variable set "$name" --body "$value"
  echo "  Set variable: $name"
}

setup_github() {
  require_cmd gh

  local script_id="$1" deployment_id="$2"
  local clasp_json="{\"scriptId\":\"${script_id}\",\"rootDir\":\"dist\"}"

  echo "Setting GitHub secrets/variables..."
  gh_set_secret "CLASP_JSON" "$clasp_json"
  gh_set_variable "DEPLOYMENT_ID" "$deployment_id"
}

# ---------------------------------------------------------------------------
# GitLab helpers
# ---------------------------------------------------------------------------

gl_project_id() {
  local remote_url
  remote_url=$(git remote get-url origin)
  local host path encoded_path project_id
  host=$(extract_host "$remote_url")
  path=$(extract_path "$remote_url")
  encoded_path="${path//\//%2F}"
  project_id=$(curl -sf --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "https://${host}/api/v4/projects/${encoded_path}" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo "$project_id"
}

gl_api_host() {
  local remote_url
  remote_url=$(git remote get-url origin)
  extract_host "$remote_url"
}

gl_set_variable() {
  local project_id="$1" key="$2" value="$3" env_scope="$4" protected="$5"
  local host
  host=$(gl_api_host)

  # Try create, if exists then update
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --request POST \
    --form "key=${key}" \
    --form "value=${value}" \
    --form "environment_scope=${env_scope}" \
    --form "protected=${protected}" \
    --form "masked=false" \
    "https://${host}/api/v4/projects/${project_id}/variables")

  if [[ "$http_code" == "400" ]]; then
    curl -sf \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --request PUT \
      --form "value=${value}" \
      --form "protected=${protected}" \
      "https://${host}/api/v4/projects/${project_id}/variables/${key}?filter[environment_scope]=${env_scope}" >/dev/null
  fi
  echo "  Set ${key} (${env_scope}, protected=${protected})"
}

setup_gitlab() {
  [[ -n "${GITLAB_TOKEN:-}" ]] || die "GITLAB_TOKEN environment variable is required for GitLab."

  local dev_script_id="$1" dev_deployment_id="$2"
  local prod_script_id="$3" prod_deployment_id="$4"
  local project_id
  project_id=$(gl_project_id)

  echo "Setting GitLab CI/CD variables (project ID: ${project_id})..."

  local dev_clasp="{\"scriptId\":\"${dev_script_id}\",\"rootDir\":\"dist\"}"
  local prod_clasp="{\"scriptId\":\"${prod_script_id}\",\"rootDir\":\"dist\"}"

  # dev: protected=false (dev branch is typically not protected)
  gl_set_variable "$project_id" "CLASP_JSON" "$dev_clasp" "development" "false"
  gl_set_variable "$project_id" "DEPLOYMENT_ID" "$dev_deployment_id" "development" "false"
  # prod: protected=true
  gl_set_variable "$project_id" "CLASP_JSON" "$prod_clasp" "production" "true"
  gl_set_variable "$project_id" "DEPLOYMENT_ID" "$prod_deployment_id" "production" "true"
}

# ---------------------------------------------------------------------------
# clasp operations
# ---------------------------------------------------------------------------

# Global variables set by clasp_create_and_deploy
DEV_SCRIPT_ID=""
DEV_DEPLOYMENT_ID=""
PROD_SCRIPT_ID=""
PROD_DEPLOYMENT_ID=""

clasp_create_and_deploy() {
  local title="$1" env_label="$2"
  local full_title="${title} (${env_label})"

  echo "Creating GAS project: ${full_title}..."
  rm -f .clasp.json
  pnpm exec clasp create --title "$full_title" --type "$GAS_TYPE" --rootDir dist 2>&1

  [[ -f .clasp.json ]] || die "clasp create failed — .clasp.json not generated."

  local script_id
  script_id=$(extract_script_id .clasp.json)
  echo "  Script ID: ${script_id}"

  # Ensure dist/ has appsscript.json for push
  mkdir -p dist
  cp appsscript.json dist/appsscript.json

  echo "  Pushing and deploying..."
  pnpm exec clasp push -f 2>&1
  local deploy_output
  deploy_output=$(pnpm exec clasp deploy 2>&1)
  echo "$deploy_output"

  local deployment_id
  deployment_id=$(echo "$deploy_output" | grep -oE 'AKfycb[A-Za-z0-9_-]+')
  [[ -n "$deployment_id" ]] || die "Could not extract deployment ID from clasp deploy output."

  echo "  Deployment ID: ${deployment_id}"

  # Set global variables for the caller
  local upper_label="${env_label^^}"
  declare -g "${upper_label}_SCRIPT_ID=${script_id}"
  declare -g "${upper_label}_DEPLOYMENT_ID=${deployment_id}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== Apps Script Fleet — Project Init ==="
echo ""

# Checks
[[ -f "$HOME/.clasprc.json" ]] || die "$HOME/.clasprc.json not found. Copy it from your organization's password manager."
require_cmd pnpm
require_cmd python3

# Default title from directory name
if [[ -z "$TITLE" ]]; then
  TITLE=$(basename "$(pwd)")
fi

PLATFORM=$(detect_platform)
echo "Platform: ${PLATFORM}"
echo "Title: ${TITLE}"
echo "Type: ${GAS_TYPE}"
echo ""

# Create dev and prod projects
clasp_create_and_deploy "$TITLE" "dev"
echo ""
clasp_create_and_deploy "$TITLE" "prod"
echo ""

# Set CI/CD variables
if [[ "$PLATFORM" == "github" ]]; then
  setup_github "$DEV_SCRIPT_ID" "$DEV_DEPLOYMENT_ID"
  echo ""
  echo "Note: GitHub CD uses a single CLASP_JSON secret (no environment scope)."
  echo "If you need separate dev/prod, configure GitHub Environments manually."
elif [[ "$PLATFORM" == "gitlab" ]]; then
  setup_gitlab "$DEV_SCRIPT_ID" "$DEV_DEPLOYMENT_ID" "$PROD_SCRIPT_ID" "$PROD_DEPLOYMENT_ID"
fi

# Cleanup
rm -f .clasp.json

echo ""
echo "Done! CI/CD variables are configured."
echo ""
echo "  dev  script: https://script.google.com/d/${DEV_SCRIPT_ID}/edit"
echo "  prod script: https://script.google.com/d/${PROD_SCRIPT_ID}/edit"
