# Quick Start: GitLab (GitLab.com / Self-Managed)

[日本語](setup-gitlab.ja.md)

## Prerequisites

- Node.js >= 24 and pnpm 10
- If you use [mise](https://mise.jdx.dev/), run `mise install`
- GitLab Runner with Docker executor (for Self-Managed)

## One-Time: Group Setup

### 1. Add CLASPRC_JSON

Create a dedicated Google account for CI/CD (e.g., `gas-deploy@yourcompany.com`), run `clasp login`, and add the contents of `~/.clasprc.json` as a **Group CI/CD Variable** named `CLASPRC_JSON` (masked, protected).

> Every project created from this template within the group will use this variable — no per-project auth setup needed.

### 2. Create the Template Project

Import the upstream template into your GitLab Group. This project serves as the source for all GAS projects in your organization.

**Option A — Import from GitHub (requires network access to github.com):**

GitLab → New project → Import project → GitHub → select `apps-script-fleet`

**Option B — Clone and push (required for air-gapped environments):**

```
git clone https://github.com/h13/apps-script-fleet.git apps-script-fleet
cd apps-script-fleet
git remote set-url origin https://gitlab.yourcompany.com/<your-group>/apps-script-fleet.git
git push -u origin main
```

Then register it as a **[Group project template](https://docs.gitlab.com/user/group/custom_project_templates/)** (Settings → General → Custom project templates). This enables "Create from template" for all group members.

> Instance-level templates require admin privileges and are not available on GitLab.com. Group templates are recommended for all environments.

### 3. Configure Template Sync on the Template Project

The Template Project syncs from GitHub to stay up to date. Configure this on the **Template Project only** — individual GAS projects do not need this.

1. Create a **Project Access Token** (Settings → Access Tokens) with `write_repository` scope
2. Add it as a CI/CD Variable named `GITLAB_PUSH_TOKEN`
3. Set `TEMPLATE_PROJECT_PATH` as a CI/CD Variable with the value matching the Template Project's path (e.g., `your-group/apps-script-fleet`). This prevents the CD pipeline from running on the Template Project itself.
4. Create a **Pipeline Schedule** (CI/CD → Schedules) — e.g., weekly on Sunday

**Self-Managed runners that cannot reach `github.com`:**

Override `TEMPLATE_REPO_URL` as a **project-level** CI/CD Variable on the Template Project, pointing to an internal mirror (e.g., `https://gitlab.internal/infra/apps-script-fleet.git`). Keep the mirror up to date — either manually or via a scheduled job on a runner that can reach `github.com`.

### 4. Set TEMPLATE_REPO_URL as a Group Variable

Add `TEMPLATE_REPO_URL` as a **Group CI/CD Variable** pointing to the Template Project's git URL:

```
https://gitlab.yourcompany.com/<your-group>/apps-script-fleet.git
```

All GAS projects within the group inherit this variable automatically, so they sync from the Template Project instead of GitHub.

> **How precedence works:** The Template Project's project-level `TEMPLATE_REPO_URL` (pointing to GitHub or an internal mirror) takes precedence over the Group Variable. This means the Template Project syncs from GitHub, while User Projects sync from the Template Project.

## Per Project: Create a New GAS Repository

### 1. Create the project

GitLab → New project → **Create from template** → select `apps-script-fleet`

After creation, clone locally and install dependencies:

```
git clone https://gitlab.yourcompany.com/<your-group>/<your-project>.git
cd <your-project>
pnpm install
```

### 2. Set your script IDs

Create `.clasp-dev.json` and `.clasp-prod.json` (gitignored):

```json
{
  "scriptId": "YOUR_SCRIPT_ID",
  "rootDir": "dist"
}
```

### 3. Configure CI/CD Variables

Go to Settings → CI/CD → Variables and add:

| Variable        | Environment scope | Value                                     | Options |
| --------------- | ----------------- | ----------------------------------------- | ------- |
| `CLASP_JSON`    | `development`     | `{"scriptId":"DEV_ID","rootDir":"dist"}`  | Masked  |
| `CLASP_JSON`    | `production`      | `{"scriptId":"PROD_ID","rootDir":"dist"}` | Masked  |
| `DEPLOYMENT_ID` | `development`     | Your dev deployment ID                    |         |
| `DEPLOYMENT_ID` | `production`      | Your prod deployment ID                   |         |

### 4. Set up Template Sync

1. Create a **Project Access Token** (Settings → Access Tokens) with `write_repository` scope
2. Add it as a CI/CD Variable named `GITLAB_PUSH_TOKEN`
3. Create a **Pipeline Schedule** (CI/CD → Schedules) — e.g., weekly on Sunday

`TEMPLATE_REPO_URL` is already set at the Group level — no per-project configuration needed.

### 5. Verify and deploy

```
pnpm run check    # lint + typecheck + test
```

Push to `dev` triggers dev deployment, push to `main` triggers production deployment — both automatically via GitLab CI.

## Network Requirements (Self-Managed)

**User Projects:**

| Job             | Outbound network access required                       |
| --------------- | ------------------------------------------------------ |
| `check`         | npm registry only (for `pnpm install`)                 |
| `deploy_*`      | `script.google.com` (HTTPS)                            |
| `template_sync` | Template Project (internal GitLab, via Group Variable)  |

**Template Project:**

| Job             | Outbound network access required                                              |
| --------------- | ----------------------------------------------------------------------------- |
| `template_sync` | `github.com` (default) or internal mirror (if `TEMPLATE_REPO_URL` overridden) |

User Project runners never need to reach `github.com`. Only the Template Project's runner needs external access (or an internal mirror).

## Migration from Existing Setup

Existing projects created via the old import/clone method are unaffected. Their per-project Template Sync configuration continues to work independently. Migration to the new model is optional:

1. Set `TEMPLATE_REPO_URL` as a Group Variable pointing to the Template Project
2. Remove per-project `TEMPLATE_REPO_URL` overrides (if any) to inherit the Group Variable
3. Per-project `GITLAB_PUSH_TOKEN` and Pipeline Schedule remain as-is
