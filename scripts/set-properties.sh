#!/usr/bin/env bash
set -euo pipefail

# Set Script Properties via clasp run
#
# Prerequisites:
#   - ~/.clasprc.json exists
#   - .clasp.json exists (with projectId for clasp run)
#   - The GAS project is bound to a standard GCP project
#   - Apps Script API is enabled on the GCP project
#
# Usage:
#   # From a JSON file
#   ./scripts/set-properties.sh --file properties.json
#
#   # From an environment variable (JSON string)
#   ./scripts/set-properties.sh --env SCRIPT_PROPERTIES
#
#   # From inline JSON
#   ./scripts/set-properties.sh --json '{"API_KEY":"xxx","ENV":"production"}'

PROPS_JSON=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --file)
      [[ -f "$2" ]] || { echo "Error: File not found: $2" >&2; exit 1; }
      PROPS_JSON=$(cat "$2")
      shift 2
      ;;
    --env)
      PROPS_JSON="${!2:-}"
      [[ -n "$PROPS_JSON" ]] || { echo "Error: Environment variable $2 is empty or not set." >&2; exit 1; }
      shift 2
      ;;
    --json)
      PROPS_JSON="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 --file <path> | --env <VAR_NAME> | --json '<json>'" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROPS_JSON" ]]; then
  echo "Error: No properties provided. Use --file, --env, or --json." >&2
  exit 1
fi

# Validate JSON
node -e "JSON.parse(process.argv[1])" "$PROPS_JSON" 2>/dev/null \
  || { echo "Error: Invalid JSON: ${PROPS_JSON}" >&2; exit 1; }

echo "Setting script properties via clasp run..."
pnpm exec clasp run setScriptProperties --params "[${PROPS_JSON}]"
echo "Done."
