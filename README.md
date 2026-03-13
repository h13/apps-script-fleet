# Apps Script Fleet

[![CI](https://github.com/h13/apps-script-fleet/actions/workflows/ci.yml/badge.svg)](https://github.com/h13/apps-script-fleet/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/h13/apps-script-fleet/blob/main/LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D24-green.svg)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-blue.svg)](https://www.typescriptlang.org/)
[![Google Apps Script](https://img.shields.io/badge/Google%20Apps%20Script-Template-4285F4.svg)](https://developers.google.com/apps-script)

[日本語](README.ja.md)

**Infrastructure for scaling Google Apps Script across your organization.**

Most Apps Script templates help you set up _one_ project with modern tooling. This one is designed so you never have to set up tooling again — create a repo from this template, set a script ID, and your CI/CD pipeline is already running. Works with GitHub and GitLab — cloud and self-managed.

**[→ Quick Start](#quick-start)** · [What's Included](#whats-included) · [How This Differs](#how-this-differs) · [FAQ](#faq)

## The Problem

Apps Script projects start small, but they multiply. Slack notifications, report generation, form processing, Drive automation — before long, your organization has a dozen scripts. Each one needs:

- TypeScript configuration
- A bundler (Rollup, Webpack, Vite)
- Linting and formatting
- Test setup with coverage
- CI/CD workflows for dev and production
- clasp authentication management
- Ongoing dependency updates

Setting this up takes 2–4 hours per project. At 10 projects, that's a week of pure boilerplate — plus 10 different configurations to maintain going forward.

## The Solution: 1 Repo = 1 Function

![Architecture — 1 repo per function with shared org infrastructure](docs/architecture.png)

Apps Script Fleet treats each function as an independent repository, backed by shared organizational infrastructure:

- **One-time setup**: Add `CLASPRC_JSON` to your org/group-level secrets ([GitHub](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-an-organization) or [GitLab](https://docs.gitlab.com/ci/variables/#for-a-group)). Every repo created from this template uses it automatically.
- **Per-project setup (~5 min)**: Create a repo from this template → set your script ID → done. CI runs on PRs/MRs, CD deploys on merge.
- **Fleet maintenance**: [Renovate](https://docs.renovatebot.com/) auto-updates dependencies across all repos. [Template sync](.github/workflows/sync-template.yml) propagates tooling improvements from the upstream template.

The difference at a glance:

![Before and after comparison](docs/before-after.png)

## What's Included

| Category     | Tools                                                              |
| ------------ | ------------------------------------------------------------------ |
| Language     | TypeScript (strict mode)                                           |
| Bundler      | Rollup (Apps Script–compatible output)                             |
| Deployment   | clasp (dev / prod environments)                                    |
| Testing      | Jest (80% coverage threshold)                                      |
| Linting      | ESLint, Prettier, Stylelint, HTMLHint                              |
| Git hooks    | husky + lint-staged                                                |
| CI/CD        | GitHub Actions + GitLab CI (CI on PR, CD on merge to `dev`/`main`) |
| Dependencies | Renovate (auto-update with automerge)                              |
| Sync         | Template sync workflow (upstream config updates)                   |

The result — your day looks like this:

![A developer's day: without vs with Apps Script Fleet](docs/before-after-human.png)

## How This Differs

|                | [Apps Script Engine](https://github.com/WildH0g/apps-script-engine-template) | Apps Script Fleet                            |
| -------------- | ---------------------------------------------------------------------------- | -------------------------------------------- |
| Philosophy     | Feature-rich DX                                                              | Minimal constraints                          |
| Best for       | Single complex project                                                       | Many small automations                       |
| Frontend dev   | Vite + Alpine.js + Tailwind                                                  | Basic HTML (Apps Script built-in)            |
| Testing        | Vitest (optional)                                                            | Jest (80% coverage enforced)                 |
| Template sync  | —                                                                            | Weekly (auto-PR)                             |
| Org-level auth | —                                                                            | CLASPRC_JSON shared secret (GitHub + GitLab) |

> Building a rich UI with client-side frameworks? [Apps Script Engine](https://github.com/WildH0g/apps-script-engine-template) is the better fit.
> Managing 5+ small Apps Script automations across your org? That's what Apps Script Fleet is for.

## Quick Start

- **GitHub / GitHub Enterprise Server**: [docs/setup-github.md](docs/setup-github.md)
- **GitLab.com / GitLab Self-Managed**: [docs/setup-gitlab.md](docs/setup-gitlab.md)

## CI/CD Pipeline

Both GitHub Actions and GitLab CI configurations are included. The same pipeline runs on whichever platform you push to — no additional setup needed beyond CI/CD variables.

### GitHub Actions

```
Push / PR  →  CI (ci.yml)  →  CD (cd.yml)
               ├── Lint          └── Build
               ├── Typecheck         └── clasp push
               ├── Test                  └── clasp deploy
               └── Build
```

| Trigger        | Pipeline       | Behavior                           |
| -------------- | -------------- | ---------------------------------- |
| PR to `main`   | CI only        | lint → typecheck → test → build    |
| Push to `dev`  | CI → CD (dev)  | cancel-in-progress                 |
| Push to `main` | CI → CD (prod) | queued (sequential, never skipped) |

### GitLab CI

`.gitlab-ci.yml` includes split configs from `.gitlab/` (ci.yml, cd.yml, sync-template.yml). See [docs/setup-gitlab.md](docs/setup-gitlab.md) for variable configuration and Self-Managed runner requirements.

| Job             | Stage  | Trigger           |
| --------------- | ------ | ----------------- |
| `check`         | check  | push / MR         |
| `deploy_dev`    | deploy | push to `dev`     |
| `deploy_prod`   | deploy | push to `main`    |
| `template_sync` | sync   | schedule / manual |

### Pre/Post-Deploy Hooks

Customize the deploy pipeline without modifying template-managed files:

- **GitHub Actions**: create `.github/hooks/pre-deploy.sh` or `.github/hooks/post-deploy.sh`
- **GitLab CI**: create `.gitlab/pre-deploy.yml` or `.gitlab/post-deploy.yml`

These files are not synced from the template.

## Project Structure

```
your-project/
├── src/
│   ├── index.ts           # Apps Script entry points (doGet, etc.)
│   ├── greeting.ts        # Business logic (example)
│   └── index.html         # Web UI (example)
├── test/
│   └── greeting.test.ts
├── .github/workflows/
│   ├── ci.yml             # CI: lint → typecheck → test → build
│   ├── cd.yml             # CD: deploy on CI success
│   └── sync-template.yml  # Sync from upstream template
├── .gitlab-ci.yml         # GitLab CI/CD root (includes .gitlab/*.yml)
├── .gitlab/
│   ├── ci.yml             # CI: lint → typecheck → test → build
│   ├── cd.yml             # CD: clasp push + deploy
│   └── sync-template.yml  # Template sync (scheduled)
├── rollup.config.mjs
├── tsconfig.json
├── jest.config.json
├── eslint.config.mjs
├── renovate.json          # Auto-update config
└── .templatesyncignore    # Your code won't be overwritten
```

## Development Workflow

### Daily

```
# Edit src/ → check → deploy to dev → verify
pnpm run check
pnpm run deploy
```

### PR Flow

1. Create a feature branch
2. Commit — husky auto-runs lint-staged
3. Push and create PR — CI runs automatically
4. Merge to `main` — CD deploys to production

### Available Commands

| Command                    | Description                                |
| -------------------------- | ------------------------------------------ |
| `pnpm run check`           | lint + typecheck + test (all-in-one)       |
| `pnpm run build`           | Bundle TypeScript + copy assets to `dist/` |
| `pnpm run deploy`          | check → build → deploy to dev              |
| `pnpm run deploy:prod`     | check → build → deploy to production       |
| `pnpm run test -- --watch` | Jest in watch mode                         |

## Keeping Repos in Sync

### Template Sync

- **GitHub**: The `sync-template.yml` workflow checks for upstream template updates weekly. When updates are found, a PR with the `template-sync` label is created.
- **GitLab**: Create a Template Project in your Group, then use "Create from template" for each GAS project. User Projects sync from the Template Project via `TEMPLATE_REPO_URL` (Group Variable). See [docs/setup-gitlab.md](docs/setup-gitlab.md) for details.

`.templatesyncignore` uses a whitelist format — only files with `:!` prefix are synced. Your project-specific files (`src/`, `test/`, `README.md`, etc.) are automatically excluded.

### Renovate

Configured via [`h13/renovate-config:node`](https://github.com/h13/renovate-config):

- Minor/patch: automerged
- Major: PR for manual review (labeled `breaking`)
- DevDependencies: grouped and automerged
- 7-day stability buffer before updating
- Runs weekly on Sunday after 9pm

## Customization

### Adding OAuth Scopes

Edit `oauthScopes` in `appsscript.json`:

```json
{
  "oauthScopes": [
    "https://www.googleapis.com/auth/script.external_request",
    "https://www.googleapis.com/auth/spreadsheets"
  ]
}
```

### Adding Source Files

1. Create a module in `src/` (e.g., `src/utils.ts`)
2. Import it in `src/index.ts` — Rollup bundles everything
3. Add tests in `test/`

> Apps Script only sees functions defined at the top level of `src/index.ts`.

### Adjusting Coverage Threshold

Edit `coverageThreshold` in `jest.config.json`. Default is 80% for all metrics. For small projects (5–10 functions), consider raising it to 100%.

## Testing

Tests live in `test/` and run with Jest. `src/index.ts` is excluded from coverage (Apps Script globals like `HtmlService` can't run in Node.js).

```
pnpm run test              # Run with coverage
pnpm run test -- --watch   # Watch mode
```

## FAQ

### Why 1 repo per function instead of a monorepo?

Apps Script projects are typically small, self-contained automations. A monorepo adds complexity (workspace tooling, selective deploys) that doesn't pay off at this scale. Separate repos give you independent CI/CD, clear ownership, and simpler mental models — while template sync and Renovate handle the maintenance overhead.

### Why 80% test coverage by default?

For small, focused Apps Script functions, high coverage is achievable and catches subtle bugs before they hit production. 80% provides a meaningful quality gate without being a barrier to adoption. For projects with a tiny scope (5–10 functions), consider raising it to 100% in `jest.config.json`.

## License

[MIT](LICENSE)
