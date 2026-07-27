# Clasp Credentials via Secret Manager + Workload Identity Federation

[日本語](secret-manager.ja.md)

This is the single source of truth for the fleet's credential architecture. It
replaces the legacy "org secret + password manager" distribution of
`CLASPRC_JSON`.

## Architecture

**clasp authentication itself does not change.** clasp keeps using a
`~/.clasprc.json` produced by `clasp login` (a user OAuth refresh token) —
the Apps Script API does not support service accounts for script push/deploy,
so this cannot be replaced with GCP-native auth. What changes is where that
token is **stored** (Secret Manager) and how it is **delivered** (WIF for CI,
personal gcloud for developers).

Authentication is two-tier:

1. **Getting `.clasprc.json` out of Secret Manager** — WIF (CI) or personal
   gcloud (developers). This tier is where IAM gives you scoping, audit logs,
   and rotation.
2. **clasp deploying to GAS** — the fetched `.clasprc.json`, exactly as before.

Everything is centralized — **zero per-repo setup**:

| Resource | Count | Scope |
| --- | --- | --- |
| Secret `clasp-credentials` | 1 | Central GCP project; CI always reads `latest` |
| WIF pool `gas-fleet` | 1 | Providers `github` + `gitlab` under it |
| IAM binding | org/group-wide | `principalSet://…/attribute.repository_owner/<org>` (GitHub) / `attribute.namespace_path/<group>` (GitLab) |
| CI variables `GCP_WIF_PROVIDER`, `CLASPRC_SECRET` | org/group-level | Inherited by every repo |

Direct WIF is used — **no service-account impersonation**. Secret Manager
accepts federated tokens directly, so the pool's `principalSet://` gets
`roles/secretmanager.secretAccessor` with no intermediate service account, and
audit logs record `attribute.repository` / `project_path` per access.

### Dual-mode rule (both CI platforms)

- `GCP_WIF_PROVIDER` set → Secret Manager path. A fetch failure **fails the
  job** — there is no silent fallback to the legacy secret.
- `GCP_WIF_PROVIDER` unset → legacy `CLASPRC_JSON` (kept for air-gapped GitLab).
- Neither → explicit error.

## One-Time Organization Setup

All commands run against the central GCP project (the same one used for Cloud
Logging / `clasp run`). Billing must be enabled.

```bash
PROJECT_ID=your-central-project        # alphanumeric project ID
ORG=your-github-org                    # GitHub organization
GROUP=your-gitlab-group                # GitLab top-level group
GITLAB_URL=https://gitlab.example.com  # or https://gitlab.com
gcloud config set project "$PROJECT_ID"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# 0. Enable APIs (cloudresourcemanager is used by the GitHub Action to
#    resolve the project — without it the secret fetch fails at run time)
gcloud services enable secretmanager.googleapis.com sts.googleapis.com \
  iam.googleapis.com cloudresourcemanager.googleapis.com
```

### 1. Create the secret

With the dedicated deploy Google account (e.g. `gas-deploy@yourcompany.com`):

First enable the **Apps Script API** for that account at
[script.google.com/home/usersettings](https://script.google.com/home/usersettings)
— it is a per-account setting, and `clasp create`/`push` fails with
`User has not enabled the Apps Script API` without it (propagation can take
a few minutes).

```bash
npx @google/clasp login            # writes ~/.clasprc.json

# VERIFY the account before storing it — this file defines the fleet-wide
# deploy identity, and a stale ~/.clasprc.json left over from earlier work
# is easy to store by accident:
node -e 'const rc=JSON.parse(require("fs").readFileSync(process.env.HOME+"/.clasprc.json","utf8"));const t=rc.tokens?.default??{client_id:rc.oauth2ClientSettings?.clientId,client_secret:rc.oauth2ClientSettings?.clientSecret,refresh_token:rc.token?.refresh_token};fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({client_id:t.client_id,client_secret:t.client_secret,refresh_token:t.refresh_token,grant_type:"refresh_token"})}).then(r=>r.json()).then(x=>fetch("https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)",{headers:{Authorization:"Bearer "+x.access_token}})).then(r=>r.json()).then(w=>console.log("deploy account:",w.user?.emailAddress))'

gcloud secrets create clasp-credentials --replication-policy=automatic
gcloud secrets versions add clasp-credentials --data-file="$HOME/.clasprc.json"
```

> If your organization enforces `constraints/gcp.resourceLocations`, the
> `automatic` (global) replication is rejected with `FAILED_PRECONDITION`.
> Pin the replica to an allowed region instead — resource name, access path,
> and IAM are unchanged:
>
> ```bash
> gcloud secrets create clasp-credentials \
>   --replication-policy=user-managed --locations=asia-northeast1
> ```

### 2. Create the WIF pool

```bash
gcloud iam workload-identity-pools create gas-fleet \
  --location=global --display-name="GAS Fleet CI"
```

### 3a. GitHub provider

The attribute condition is **required**: `token.actions.githubusercontent.com`
is a multi-tenant issuer shared by every GitHub org.

```bash
gcloud iam workload-identity-pools providers create-oidc github \
  --location=global --workload-identity-pool=gas-fleet \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${ORG}'"
```

### 3b. GitLab provider

```bash
gcloud iam workload-identity-pools providers create-oidc gitlab \
  --location=global --workload-identity-pool=gas-fleet \
  --issuer-uri="${GITLAB_URL}" \
  --allowed-audiences="${GITLAB_URL}" \
  --attribute-mapping="google.subject=assertion.sub,attribute.project_path=assertion.project_path,attribute.namespace_path=assertion.namespace_path" \
  --attribute-condition="assertion.namespace_path == '${GROUP}' || assertion.namespace_path.startsWith('${GROUP}/')"
```

`--allowed-audiences` must equal the `aud` of the CI JWT, which the template
sets to `$CI_SERVER_URL` (scheme included, no trailing slash).

### 4. Grant CI access (org/group-wide)

Grant at the **project level**, not on the secret resource:

```bash
POOL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/gas-fleet"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --role=roles/secretmanager.secretAccessor --condition=None \
  --member="principalSet://iam.googleapis.com/${POOL}/attribute.repository_owner/${ORG}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --role=roles/secretmanager.secretAccessor --condition=None \
  --member="principalSet://iam.googleapis.com/${POOL}/attribute.namespace_path/${GROUP}"
```

> **Field note — why project level:** granting `secretAccessor` to the
> `principalSet://` on the secret alone (`gcloud secrets
> add-iam-policy-binding`) was observed to keep returning `PERMISSION_DENIED`
> for federated CI principals even 30+ minutes after binding, while the same
> member granted at project level became effective within minutes. The central
> project holds only fleet secrets, so the project-level grant does not widen
> access in practice — but if you later add unrelated secrets to this project,
> revisit this and re-test the secret-scoped grant.
>
> Also note: `principalSet://` IAM changes can take a few minutes to
> propagate. A `PERMISSION_DENIED` on the very first CI run right after this
> step usually just means "wait and retry".

### 5. Grant developer access

```bash
gcloud secrets add-iam-policy-binding clasp-credentials \
  --role=roles/secretmanager.secretAccessor \
  --member="group:gas-developers@yourcompany.com"
```

### 6. Enable Data Access audit logs

**Off by default and billed** — required if you want per-access audit trails.
In [IAM → Audit Logs](https://console.cloud.google.com/iam-admin/audit), enable
**Data Read** for **Secret Manager API**, or scriptably (merges `DATA_READ`
into the project IAM policy without clobbering existing audit configs):

```bash
gcloud projects get-iam-policy "$PROJECT_ID" --format=json > /tmp/policy.json
python3 - <<'EOF'
import json
p = json.load(open("/tmp/policy.json"))
a = p.setdefault("auditConfigs", [])
e = next((x for x in a if x.get("service") == "secretmanager.googleapis.com"), None)
if e is None:
    a.append({"service": "secretmanager.googleapis.com", "auditLogConfigs": [{"logType": "DATA_READ"}]})
elif not any(c.get("logType") == "DATA_READ" for c in e.setdefault("auditLogConfigs", [])):
    e["auditLogConfigs"].append({"logType": "DATA_READ"})
json.dump(p, open("/tmp/policy.json", "w"), indent=2)
EOF
gcloud projects set-iam-policy "$PROJECT_ID" /tmp/policy.json
```

Afterwards every `AccessSecretVersion` appears in Cloud Logging with the
federated principal — including `attribute.repository` (GitHub) /
`project_path` (GitLab), so access is traceable per repo even with the
org-wide grant.

### 7. Set CI variables (org/group-level, same names on both platforms)

| Variable | Value |
| --- | --- |
| `GCP_WIF_PROVIDER` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/gas-fleet/providers/github` (GitHub) / `…/providers/gitlab` (GitLab) |
| `CLASPRC_SECRET` | `projects/<PROJECT_ID>/secrets/clasp-credentials` |

- **GitHub**: Organization → Settings → Actions → Variables (not secrets —
  these values are not sensitive), or via CLI — note the `admin:org` scope
  (`gh auth refresh -h github.com -s admin:org` first if you get a 403):

  ```bash
  gh variable set GCP_WIF_PROVIDER --org "$ORG" --visibility all \
    --body "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/gas-fleet/providers/github"
  gh variable set CLASPRC_SECRET --org "$ORG" --visibility all \
    --body "projects/${PROJECT_ID}/secrets/clasp-credentials"
  ```

  On a personal account (no org), set them as repository variables instead.
- **GitLab**: Group → Settings → CI/CD → Variables. Set them **unprotected**:
  protected variables are invisible on `dev` pipelines, which would silently
  drop dev deploys into legacy mode.

## Developer Access

```bash
gcloud auth login          # personal account, once per machine
./scripts/fetch-clasp-credentials.sh
```

- `~/.clasprc.json` lives in `$HOME`, so one fetch covers **every repo on the
  machine**.
- The script is idempotent: if the file exists it does nothing without
  `--force` (use `--force` after a rotation).
- The GCP project is resolved from `--project` → `$CLASP_SECRET_PROJECT` →
  `projectId` in `.clasp-dev.json` / `.clasp.json`.
- Offboarding = remove the person from the Google group. After the next
  rotation their local copy stops working too.

## Rotation

Impossible under the legacy model; now routine:

1. `clasp login` again with the deploy account, then
   `gcloud secrets versions add clasp-credentials --data-file="$HOME/.clasprc.json"`.
   CI reads `latest`, so this takes effect immediately — zero repo-side work.
   Run the account-verification one-liner from §1 first — the same rotation
   flow is also how you *replace* the deploy account, and storing the wrong
   machine-local `~/.clasprc.json` silently changes the fleet's identity.
2. Verify with any repo's dev deploy.
3. `gcloud secrets versions disable <old>` → after a grace period
   `gcloud secrets versions destroy <old>`.
4. Developers re-fetch with `./scripts/fetch-clasp-credentials.sh --force`.

## Migrating an Existing Fleet off CLASPRC_JSON

1. Complete the one-time setup above, including the CI variables. Old `cd.yml`
   revisions ignore unknown variables, so setting them early is harmless.
2. Wait for template-sync PRs/MRs to deliver the new `cd.yml` + scripts (or
   sync manually).
3. Confirm a few repos deploy via WIF — check Audit Logs for
   `AccessSecretVersion` with a federated principal.
4. Delete the org secret / group variable `CLASPRC_JSON` and the password
   manager entry. The `secrets: inherit` exposure in `publish.yml` disappears
   with it.

## Hardening: Per-Repo Grants (Optional)

Instead of the org/group-wide `principalSet`, grant per repo (still at
project level — see the field note in §4):

```bash
# GitHub — one repo only
--member="principalSet://iam.googleapis.com/${POOL}/attribute.repository/${ORG}/critical-repo"
# GitLab — one project only
--member="principalSet://iam.googleapis.com/${POOL}/attribute.project_path/${GROUP}/critical-repo"
```

Trade-off: every new repo needs an explicit IAM grant. You can also pin GitHub
tokens to a deployment environment via
`sub = repo:ORG/REPO:environment:production` — but note this template deploys
from a `workflow_run` trigger, where `ref`-based conditions are unreliable;
prefer `repository` / `environment` claims.

## Scope Boundary (Known Limitation)

The fetched `.clasprc.json` is still a user OAuth token that can operate on
**every** GAS project in the fleet. This migration improves distribution,
storage, revocation, and audit — not the blast radius of the token itself,
which the Apps Script API makes unavoidable.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| STS 403 `unable to acquire impersonated credentials` / `The given credential is rejected by the attribute condition` | Provider `--attribute-condition` does not match (wrong org/group), or the JWT `aud` differs from `--allowed-audiences`. JWT `aud` = `$CI_SERVER_URL` with scheme, no trailing slash. |
| STS 400 `Invalid value for "audience"` | STS request `audience` must be `//iam.googleapis.com/projects/<NUM>/…/providers/<name>` — **no `https:` prefix**, and it uses the project **number**. |
| STS 400 `mapped attribute google.subject exceeds the 127 bytes limit` | The JWT `sub` is too long (deeply nested GitLab groups; long GitHub repo/environment names). Remap `google.subject` to a shorter claim, e.g. `assertion.project_path` (GitLab) — IAM here binds on attributes, not subject, so nothing else changes. |
| `secrets create` fails with `FAILED_PRECONDITION` on `constraints/gcp.resourceLocations` | Org policy forbids global replication. Create with `--replication-policy=user-managed --locations=<allowed-region>` (check `gcloud org-policies describe gcp.resourceLocations --project=… --effective`). |
| `cloud Resource Manager API has not been used in project …` during the CI secret fetch | Enable `cloudresourcemanager.googleapis.com` on the central project — `get-secretmanager-secrets` uses it to resolve the project. |
| Secret Manager 403 `PERMISSION_DENIED` (CI) — right after setup | `principalSet` IAM bindings take a few minutes to propagate. Wait 2–5 minutes and retry before changing anything. |
| Secret Manager 403 `PERMISSION_DENIED` (CI) — persistent | Either the `principalSet` binding is missing/wrong (check the attribute name — `repository_owner` vs `namespace_path` — and value), **or the grant is on the secret resource only — move it to project level** (field-verified, see §4). |
| `PERMISSION_DENIED` (developer) | Not in the developer Google group, or the group lacks `secretAccessor`. |
| GAS scripts are owned by the wrong account | The secret was seeded from a stale machine-local `~/.clasprc.json`. Scripts cannot change owners across domains and the clasp token cannot even trash them (`drive.file` scope; scripts are created via the Apps Script API, so they are not "app files"). Fix: `clasp login` with the right account → rotate the secret → re-run `init.sh` per repo → the old owner deletes the orphaned scripts manually. |
| GitLab job fails before script with `id_tokens` error | GitLab < 16.1 (variable expansion in `aud`) or < 15.7 (`id_tokens` itself). Upgrade or stay on legacy mode with an older template revision. |
| WIF works on `main` but not `dev` (GitLab) | `GCP_WIF_PROVIDER` / `CLASPRC_SECRET` set as **protected** variables. Make them unprotected. |
| Air-gapped GitLab | WIF needs egress to `sts.googleapis.com` + `secretmanager.googleapis.com`. Keep using legacy `CLASPRC_JSON`. |
