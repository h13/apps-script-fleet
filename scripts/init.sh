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
VALID_TYPES="standalone sheets docs slides forms"

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

json_value() {
  local file="$1" key="$2"
  node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('$file','utf8'))['$key'])"
}

# Extract host from git remote URL
extract_host() {
  local url="$1"
  if [[ "$url" == git@* ]]; then
    local without_prefix="${url#git@}"
    echo "${without_prefix%%:*}"
  else
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
  echo "${path%.git}"
}

validate_type() {
  local type="$1"
  for valid in $VALID_TYPES; do
    [[ "$type" == "$valid" ]] && return 0
  done
  die "Invalid --type '${type}'. Must be one of: ${VALID_TYPES}"
}

# ---------------------------------------------------------------------------
# Detect platform from git remote
# ---------------------------------------------------------------------------

REMOTE_URL=""
REMOTE_HOST=""

init_remote() {
  REMOTE_URL=$(git remote get-url origin 2>/dev/null) || die "No git remote 'origin' found."
  REMOTE_HOST=$(extract_host "$REMOTE_URL")
}

detect_platform() {
  if echo "$REMOTE_URL" | grep -q "github"; then
    echo "github"
  elif echo "$REMOTE_URL" | grep -q "gitlab"; then
    echo "gitlab"
  else
    die "Cannot detect platform from remote URL: $REMOTE_URL"
  fi
}

# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------

gh_set_secret() {
  local name="$1" value="$2" env="$3"
  echo "$value" | gh secret set "$name" -e "$env"
  echo "  Set secret: $name (env=$env)"
}

gh_set_variable() {
  local name="$1" value="$2" env="$3"
  gh variable delete "$name" -e "$env" 2>/dev/null || true
  gh variable set "$name" --body "$value" -e "$env"
  echo "  Set variable: $name (env=$env)"
}

setup_github() {
  require_cmd gh

  local dev_script_id="$1" dev_deployment_id="$2"
  local prod_script_id="$3" prod_deployment_id="$4"

  local dev_clasp="{\"scriptId\":\"${dev_script_id}\",\"rootDir\":\"dist\"}"
  local prod_clasp="{\"scriptId\":\"${prod_script_id}\",\"rootDir\":\"dist\"}"

  echo "Setting GitHub secrets/variables..."
  gh_set_secret "CLASP_JSON" "$dev_clasp" "development"
  gh_set_variable "DEPLOYMENT_ID" "$dev_deployment_id" "development"
  gh_set_secret "CLASP_JSON" "$prod_clasp" "production"
  gh_set_variable "DEPLOYMENT_ID" "$prod_deployment_id" "production"
}

# ---------------------------------------------------------------------------
# GitLab helpers
# ---------------------------------------------------------------------------

gl_project_id() {
  local path encoded_path project_id
  path=$(extract_path "$REMOTE_URL")
  encoded_path="${path//\//%2F}"
  project_id=$(curl -sf --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "https://${REMOTE_HOST}/api/v4/projects/${encoded_path}" |
    node -e "process.stdin.on('data',d=>process.stdout.write(String(JSON.parse(d).id)))")
  echo "$project_id"
}

gl_set_variable() {
  local project_id="$1" key="$2" value="$3" env_scope="$4" protected="$5"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --request POST \
    --form "key=${key}" \
    --form "value=${value}" \
    --form "environment_scope=${env_scope}" \
    --form "protected=${protected}" \
    --form "masked=false" \
    "https://${REMOTE_HOST}/api/v4/projects/${project_id}/variables")

  if [[ "$http_code" == "201" ]]; then
    : # created successfully
  elif [[ "$http_code" == "400" ]]; then
    # Already exists — update
    local update_code
    update_code=$(curl -s -o /dev/null -w "%{http_code}" \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --request PUT \
      --form "value=${value}" \
      --form "protected=${protected}" \
      "https://${REMOTE_HOST}/api/v4/projects/${project_id}/variables/${key}?filter[environment_scope]=${env_scope}")
    [[ "$update_code" == "200" ]] || die "Failed to update ${key} (${env_scope}): HTTP ${update_code}"
  else
    die "Failed to create ${key} (${env_scope}): HTTP ${http_code}"
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

# Results from clasp_create_and_deploy (set via global variables)
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
  script_id=$(json_value .clasp.json scriptId)
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
  local upper_label
  upper_label=$(echo "$env_label" | tr '[:lower:]' '[:upper:]')
  eval "${upper_label}_SCRIPT_ID='${script_id}'"
  eval "${upper_label}_DEPLOYMENT_ID='${deployment_id}'"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== Apps Script Fleet — Project Init ==="
echo ""

# Checks
[[ -f "$HOME/.clasprc.json" ]] || die "$HOME/.clasprc.json not found. Copy it from your organization's password manager."
require_cmd pnpm
require_cmd node
validate_type "$GAS_TYPE"

# Default title from directory name
if [[ -z "$TITLE" ]]; then
  TITLE=$(basename "$(pwd)")
fi

init_remote
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
  setup_github "$DEV_SCRIPT_ID" "$DEV_DEPLOYMENT_ID" "$PROD_SCRIPT_ID" "$PROD_DEPLOYMENT_ID"
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
