#!/usr/bin/env bash
set -euo pipefail

# Apps Script Fleet — GitLab CI: fetch a secret from Google Cloud Secret Manager
# via Workload Identity Federation (keyless, no service-account impersonation).
#
# Usage:
#   ./scripts/gcp-get-secret.sh "projects/<PROJECT_ID>/secrets/<NAME>" > payload
#
# Requires (set by .gitlab/cd.yml):
#   GCP_OIDC_TOKEN    GitLab CI id_token (JWT). Its `aud` must match the WIF
#                     provider's --allowed-audiences ($CI_SERVER_URL).
#   GCP_WIF_PROVIDER  projects/<NUM>/locations/global/workloadIdentityPools/<pool>/providers/<provider>
#
# Designed for the node:24 image: curl + node only (no gcloud, no jq).
# SECURITY: never enable `set -x` in this script — the exchanged access token
# and the secret payload must not appear in the job log. The payload goes to
# stdout only; everything else goes to stderr.

die() {
  echo "Error: $*" >&2
  exit 1
}

SECRET_RESOURCE="${1:-}"
[[ -n "$SECRET_RESOURCE" ]] || die "usage: $0 projects/<PROJECT_ID>/secrets/<NAME>"
[[ -n "${GCP_OIDC_TOKEN:-}" ]] || die "GCP_OIDC_TOKEN is not set. Add 'id_tokens: GCP_OIDC_TOKEN: aud: \$CI_SERVER_URL' to the job (GitLab >= 16.1)."
[[ -n "${GCP_WIF_PROVIDER:-}" ]] || die "GCP_WIF_PROVIDER is not set."

# 1. Exchange the GitLab OIDC token for a federated access token via STS.
#    Note the audience format: //iam.googleapis.com/<provider> (no https:).
#    JSON is assembled by node from env so the JWT never hits a command line.
# shellcheck disable=SC2016  # ${} below is a JS template literal, not shell
sts_request=$(node -e '
  process.stdout.write(JSON.stringify({
    audience: `//iam.googleapis.com/${process.env.GCP_WIF_PROVIDER}`,
    grantType: "urn:ietf:params:oauth:grant-type:token-exchange",
    requestedTokenType: "urn:ietf:params:oauth:token-type:access_token",
    scope: "https://www.googleapis.com/auth/cloud-platform",
    subjectToken: process.env.GCP_OIDC_TOKEN,
    subjectTokenType: "urn:ietf:params:oauth:token-type:jwt",
  }));
')

if ! sts_response=$(curl -sS --fail-with-body -X POST "https://sts.googleapis.com/v1/token" \
  -H "Content-Type: application/json" --data-binary "$sts_request"); then
  # STS error bodies contain no secrets — safe and useful to show.
  echo "$sts_response" >&2
  die "STS token exchange failed. Check the WIF provider's attribute condition and allowed audiences (JWT aud = \$CI_SERVER_URL)."
fi

access_token=$(printf '%s' "$sts_response" | node -e '
  let d = "";
  process.stdin.on("data", (c) => (d += c)).on("end", () => {
    const t = JSON.parse(d).access_token;
    if (!t) { console.error("No access_token in STS response."); process.exit(1); }
    process.stdout.write(t);
  });
')

# 2. Access the secret payload. The Authorization header is passed via a curl
#    config on stdin so the token never appears in argv.
if ! secret_response=$(curl -sS --fail-with-body --config - <<CURLCFG
url = "https://secretmanager.googleapis.com/v1/${SECRET_RESOURCE}/versions/latest:access"
header = "Authorization: Bearer ${access_token}"
CURLCFG
); then
  echo "$secret_response" >&2
  die "Secret Manager access failed for ${SECRET_RESOURCE}. Check the principalSet IAM binding (roles/secretmanager.secretAccessor)."
fi

# 3. Decode payload.data (base64) and emit to stdout.
printf '%s' "$secret_response" | node -e '
  let d = "";
  process.stdin.on("data", (c) => (d += c)).on("end", () => {
    const p = JSON.parse(d).payload;
    if (!p || !p.data) { console.error("No payload in Secret Manager response."); process.exit(1); }
    process.stdout.write(Buffer.from(p.data, "base64").toString("utf8"));
  });
'
