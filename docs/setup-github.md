# Quick Start: GitHub

[日本語](setup-github.ja.md)

## Prerequisites

- Node.js >= 24 and pnpm 10
- If you use [mise](https://mise.jdx.dev/), run `mise install`
- Or use [Dev Containers / Codespaces](#dev-container--codespaces) for zero local setup

## One-Time: Organization Setup

Create a dedicated Google account for CI/CD (e.g., `gas-deploy@yourcompany.com`), run `clasp login`, and add `~/.clasprc.json` as an **Organization Secret** named `CLASPRC_JSON`.

> Every repository created from this template will use this secret — no per-repo auth setup needed.

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

| Environment   | Secret / Variable         | Value                                                              |
| ------------- | ------------------------- | ------------------------------------------------------------------ |
| `development` | Secret: `CLASP_JSON`      | `{"scriptId":"DEV_ID","projectId":"GCP_NUM","rootDir":"dist"}`     |
| `development` | Variable: `DEPLOYMENT_ID` | Your dev deployment ID                                             |
| `production`  | Secret: `CLASP_JSON`      | `{"scriptId":"PROD_ID","projectId":"GCP_NUM","rootDir":"dist"}`    |
| `production`  | Variable: `DEPLOYMENT_ID` | Your prod deployment ID                                            |

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
