# Quick Start: GitHub

[日本語](setup-github.ja.md)

## Prerequisites

- Node.js >= 24 and pnpm 10
- If you use [mise](https://mise.jdx.dev/), run `mise install`
- Or use [Dev Containers / Codespaces](#dev-container--codespaces) for zero local setup

## One-Time: Organization Setup

Store the shared clasp credentials in Google Cloud Secret Manager and let CI fetch them keylessly via Workload Identity Federation — full guide: [secret-manager.md](secret-manager.md). In short:

1. Create a dedicated Google account for CI/CD (e.g., `gas-deploy@yourcompany.com`), run `clasp login`, and store `~/.clasprc.json` in the `clasp-credentials` secret.
2. Create the WIF pool `gas-fleet` with a `github` provider, attribute-restricted to your org (`assertion.repository_owner == '<org>'` — required, the GitHub issuer is multi-tenant).
3. Grant `roles/secretmanager.secretAccessor` to `principalSet://…/attribute.repository_owner/<org>`.
4. Set **Organization variables** `GCP_WIF_PROVIDER` and `CLASPRC_SECRET`.

> Every repository created from this template authenticates via WIF automatically — no per-repo auth setup needed. For per-repo hardening you can bind IAM to `attribute.repository/<org>/<repo>` instead, or pin tokens to a deployment environment (`sub = repo:ORG/REPO:environment:ENV`). Note: CD runs on a `workflow_run` trigger, where `ref`-based OIDC conditions are unreliable — prefer `repository` / `environment` claims.

<details>
<summary>Legacy fallback: <code>CLASPRC_JSON</code> Organization Secret</summary>

Used automatically when `GCP_WIF_PROVIDER` is not set: add the contents of `~/.clasprc.json` as an **Organization Secret** named `CLASPRC_JSON`.

</details>

## Per Project: Create a New Apps Script Repository

### 1. Create from template

Click **"Use this template"** on GitHub, then clone:

```
git clone https://github.com/<your-org>/<your-project>.git
cd <your-project>
pnpm install
```

### 2. Set your script IDs

Create `.clasp-dev.json` and `.clasp-prod.json` (gitignored):

```json
{
  "scriptId": "YOUR_SCRIPT_ID",
  "projectId": "YOUR_GCP_PROJECT_ID",
  "rootDir": "dist"
}
```

> **`projectId`** is the GCP project **number** associated with your Apps Script (a numeric string like `"123456789"`, not the alphanumeric project ID like `my-project-abc`). Find it in Apps Script editor → Project Settings → Google Cloud Platform (GCP) Project. Including it makes the GCP project association declarative and reproducible. If omitted, clasp uses the script's existing GCP project.

### 3. Configure GitHub environments

| Environment   | Secret / Variable         | Value                                                           |
| ------------- | ------------------------- | --------------------------------------------------------------- |
| `development` | Secret: `CLASP_JSON`      | `{"scriptId":"DEV_ID","projectId":"GCP_NUM","rootDir":"dist"}`  |
| `development` | Variable: `DEPLOYMENT_ID` | Your dev deployment ID                                          |
| `production`  | Secret: `CLASP_JSON`      | `{"scriptId":"PROD_ID","projectId":"GCP_NUM","rootDir":"dist"}` |
| `production`  | Variable: `DEPLOYMENT_ID` | Your prod deployment ID                                         |

> **With GCP project**: Add `"projectId":"YOUR_PROJECT_NUMBER"` to `CLASP_JSON` (e.g., `{"scriptId":"...","rootDir":"dist","projectId":"123456789"}`). This is set automatically when using `init.sh --gcp-project`.

### 4. Verify and deploy

```
pnpm run check    # lint + typecheck + test
pnpm run deploy   # check → build → push to dev
```

That's it. Push to `main` triggers production deployment automatically.

## Dev Container / Codespaces

No local setup needed. Everything is pre-configured in `.devcontainer/`.

- **VS Code**: "Reopen in Container"
- **GitHub Codespaces**: Code → Codespaces → Create codespace on main

For `clasp login` inside a container, use `pnpm exec clasp login --no-localhost`.
