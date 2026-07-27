#!/usr/bin/env bash
set -euo pipefail

# Apps Script Fleet — fetch shared clasp credentials from Secret Manager.
#
# Writes the fleet's shared ~/.clasprc.json (clasp OAuth token) from Google
# Cloud Secret Manager using your personal gcloud credentials. Replaces the
# legacy "copy from the org password manager" flow.
#
# ~/.clasprc.json lives in $HOME, so one fetch covers every repo on this
# machine. Access is governed by IAM (roles/secretmanager.secretAccessor).
#
# Usage:
#   ./scripts/fetch-clasp-credentials.sh [--project <PROJECT_ID>] [--secret <NAME>] [--force]
#
# Project resolution order:
#   --project → $CLASP_SECRET_PROJECT → projectId in .clasp-dev.json / .clasp.json

SECRET_NAME="clasp-credentials"
PROJECT="${CLASP_SECRET_PROJECT:-}"
FORCE=0
CLASPRC="$HOME/.clasprc.json"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed."
}

json_value() {
  node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))[process.argv[2]] ?? ''))" "$1" "$2"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --secret)
      SECRET_NAME="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    *)
      die "Unknown option: $1 (usage: $0 [--project <PROJECT_ID>] [--secret <NAME>] [--force])"
      ;;
  esac
done

# Idempotent: an existing ~/.clasprc.json covers every repo on this machine.
if [[ -f "$CLASPRC" && "$FORCE" -ne 1 ]]; then
  echo "$CLASPRC already exists — nothing to do (it is shared across all repos on this machine)."
  echo "Use --force to re-fetch, e.g. after a credential rotation."
  exit 0
fi

require_cmd gcloud
require_cmd node

active_account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)
[[ -n "$active_account" ]] || die "No active gcloud account. Run: gcloud auth login"

# Resolve the GCP project holding the secret.
if [[ -z "$PROJECT" ]]; then
  for f in .clasp-dev.json .clasp.json; do
    if [[ -f "$f" ]]; then
      PROJECT=$(json_value "$f" projectId)
      [[ -n "$PROJECT" ]] && break
    fi
  done
fi
[[ -n "$PROJECT" ]] || die "Cannot resolve the GCP project. Pass --project <PROJECT_ID>, set \$CLASP_SECRET_PROJECT, or run from a repo whose .clasp-dev.json has a projectId."

echo "Fetching secret '${SECRET_NAME}' from project '${PROJECT}' as ${active_account}..."
umask 077
tmp=$(mktemp "${CLASPRC}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

if ! gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" > "$tmp"; then
  die "Failed to access the secret. If you see PERMISSION_DENIED, ask an admin to add you to the developer group that has roles/secretmanager.secretAccessor on '${SECRET_NAME}'."
fi

node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (typeof data !== "object" || data === null || Object.keys(data).length === 0) {
    throw new Error("empty JSON object");
  }
' "$tmp" || die "Fetched payload is not valid clasp credentials JSON — not installing it."

mv "$tmp" "$CLASPRC"
trap - EXIT
echo "Wrote $CLASPRC (mode 600). All repos on this machine now share it."
