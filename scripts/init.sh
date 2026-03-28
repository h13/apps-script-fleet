#!/usr/bin/env bash
set -euo pipefail

# Apps Script Fleet — Project Init
#
# Prerequisites:
#   - ~/.clasprc.json exists (shared via org password manager)
#   - GitHub: gh CLI authenticated | GitLab: glab CLI authenticated
#   - Node.js + pnpm installed
#
# Usage:
#   ./scripts/init.sh [--title "Project Name"] [--type standalone|sheets|docs|slides|forms] [--gcp-project <PROJECT_NUMBER>]

TITLE=""
GAS_TYPE="standalone"
GCP_PROJECT=""
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
    --gcp-project)
      GCP_PROJECT="$2"
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
  node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))[process.argv[2]]))" "$1" "$2"
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
  local host="$REMOTE_HOST"
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname "$host" >/dev/null 2>&1; then
    echo "github"
  elif command -v glab >/dev/null 2>&1 && glab auth status --hostname "$host" >/dev/null 2>&1; then
    echo "gitlab"
  else
    die "No authenticated CLI found for ${host}. Run 'gh auth login' or 'glab auth login --hostname ${host}'."
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

gh_ensure_environment() {
  local env="$1"
  local repo
  repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
  # Create environment if it doesn't exist (idempotent PUT)
  gh api -X PUT "repos/${repo}/environments/${env}" --silent 2>/dev/null || true
}

setup_github() {
  require_cmd gh

  local dev_script_id="$1" dev_deployment_id="$2"
  local prod_script_id="$3" prod_deployment_id="$4"

  local project_id_field=""
  if [[ -n "$GCP_PROJECT" ]]; then
    project_id_field=",\"projectId\":\"${GCP_PROJECT}\""
  fi
  local dev_clasp="{\"scriptId\":\"${dev_script_id}\",\"rootDir\":\"dist\"${project_id_field}}"
  local prod_clasp="{\"scriptId\":\"${prod_script_id}\",\"rootDir\":\"dist\"${project_id_field}}"

  echo "Setting GitHub secrets/variables..."
  gh_ensure_environment "development"
  gh_ensure_environment "production"
  gh_set_secret "CLASP_JSON" "$dev_clasp" "development"
  gh_set_variable "DEPLOYMENT_ID" "$dev_deployment_id" "development"
  gh_set_secret "CLASP_JSON" "$prod_clasp" "production"
  gh_set_variable "DEPLOYMENT_ID" "$prod_deployment_id" "production"

  if [[ -n "$GCP_PROJECT" ]]; then
    gh_set_variable "GCP_PROJECT_NUMBER" "$GCP_PROJECT" "development"
    gh_set_variable "GCP_PROJECT_NUMBER" "$GCP_PROJECT" "production"
  fi
}

# ---------------------------------------------------------------------------
# GitLab helpers (via glab CLI)
# ---------------------------------------------------------------------------

gl_encoded_path() {
  local path
  path=$(extract_path "$REMOTE_URL")
  echo "${path//\//%2F}"
}

gl_set_variable() {
  local encoded_path="$1" key="$2" value="$3" env_scope="$4" protected="$5"

  # Try to create; if it already exists (409), update instead
  local result
  if result=$(glab api "projects/${encoded_path}/variables" \
    --hostname "$REMOTE_HOST" \
    --method POST \
    --raw-field "key=${key}" \
    --raw-field "value=${value}" \
    --raw-field "environment_scope=${env_scope}" \
    --raw-field "protected=${protected}" \
    --raw-field "masked=false" 2>&1); then
    : # created
  else
    if echo "$result" | grep -q "409\|already been taken"; then
      glab api "projects/${encoded_path}/variables/${key}?filter%5Benvironment_scope%5D=${env_scope}" \
        --hostname "$REMOTE_HOST" \
        --method PUT \
        --raw-field "value=${value}" \
        --raw-field "environment_scope=${env_scope}" \
        --raw-field "protected=${protected}" >/dev/null 2>&1 \
        || die "Failed to update ${key} (${env_scope})"
    else
      die "Failed to create ${key} (${env_scope}): ${result}"
    fi
  fi
  echo "  Set ${key} (${env_scope}, protected=${protected})"
}

setup_gitlab() {
  require_cmd glab

  local dev_script_id="$1" dev_deployment_id="$2"
  local prod_script_id="$3" prod_deployment_id="$4"
  local encoded_path
  encoded_path=$(gl_encoded_path)

  echo "Setting GitLab CI/CD variables..."

  local project_id_field=""
  if [[ -n "$GCP_PROJECT" ]]; then
    project_id_field=",\"projectId\":\"${GCP_PROJECT}\""
  fi
  local dev_clasp="{\"scriptId\":\"${dev_script_id}\",\"rootDir\":\"dist\"${project_id_field}}"
  local prod_clasp="{\"scriptId\":\"${prod_script_id}\",\"rootDir\":\"dist\"${project_id_field}}"

  # dev: protected=false (dev branch is typically not protected)
  gl_set_variable "$encoded_path" "CLASP_JSON" "$dev_clasp" "development" "false"
  gl_set_variable "$encoded_path" "DEPLOYMENT_ID" "$dev_deployment_id" "development" "false"
  # prod: protected=true
  gl_set_variable "$encoded_path" "CLASP_JSON" "$prod_clasp" "production" "true"
  gl_set_variable "$encoded_path" "DEPLOYMENT_ID" "$prod_deployment_id" "production" "true"

  if [[ -n "$GCP_PROJECT" ]]; then
    gl_set_variable "$encoded_path" "GCP_PROJECT_NUMBER" "$GCP_PROJECT" "development" "false"
    gl_set_variable "$encoded_path" "GCP_PROJECT_NUMBER" "$GCP_PROJECT" "production" "true"
  fi
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
  local clasp_args=(create --title "$full_title" --type "$GAS_TYPE" --rootDir dist)
  if [[ -n "$GCP_PROJECT" ]]; then
    clasp_args+=(--parentId "$GCP_PROJECT")
  fi
  pnpm exec clasp "${clasp_args[@]}" 2>&1

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
require_cmd node
validate_type "$GAS_TYPE"
if [[ -n "$GCP_PROJECT" ]] && ! [[ "$GCP_PROJECT" =~ ^[0-9]+$ ]]; then
  die "--gcp-project must be a numeric project number (not project ID). Got: ${GCP_PROJECT}"
fi

# Default title from directory name
if [[ -z "$TITLE" ]]; then
  TITLE=$(basename "$(pwd)")
fi

init_remote
PLATFORM=$(detect_platform)
echo "Platform: ${PLATFORM}"
echo "Title: ${TITLE}"
echo "Type: ${GAS_TYPE}"
if [[ -n "$GCP_PROJECT" ]]; then
  echo "GCP Project: ${GCP_PROJECT}"
fi
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
if [[ -n "$GCP_PROJECT" ]]; then
  echo ""
  echo "  GCP project: https://console.cloud.google.com/home/dashboard?project=${GCP_PROJECT}"
  echo ""
  echo "  clasp run is enabled. To set script properties:"
  echo "    ./scripts/set-properties.sh --json '{\"KEY\":\"value\"}'"
fi
