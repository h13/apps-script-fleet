# Contributing to Apps Script Fleet

## Adding or Removing Template Files

When you add or remove a file that should be synced to downstream repos:

1. Update `.templatesyncignore` — add a `:!path/to/file` entry (or remove one)
2. Run CI — the `templatesyncignore_check` job will catch missing entries
3. Note the 2-cycle delay — new files require two sync cycles to propagate:
   - Cycle 1: the updated `.templatesyncignore` is synced to downstream repos
   - Cycle 2: the new file is now in the whitelist and gets synced

## Pre/Post-Deploy Extension Points

Users can customize the deploy pipeline without modifying template-managed files:

- **GitHub Actions**: create `.github/hooks/pre-deploy.sh` or `.github/hooks/post-deploy.sh`
- **GitLab CI**: create `.gitlab/pre-deploy.yml` or `.gitlab/post-deploy.yml`

These files are not template-managed and will not be overwritten by template sync.

## CI/CD Structure

- `.github/workflows/` — GitHub Actions (ci.yml, cd.yml, sync-template.yml)
- `.gitlab-ci.yml` — Root include file for GitLab CI
- `.gitlab/` — Split GitLab CI configs (ci.yml, cd.yml, sync-template.yml)

## Template Repository Variables

The `templatesyncignore_check` CI job only runs on the template repository itself:

- **GitHub**: Automatically detected via the repository's "Template repository" setting — no variables needed
- **GitLab**: Set `TEMPLATE_PROJECT_PATH` as a project-level CI/CD variable (this is already part of the [Template Project setup](docs/setup-gitlab.md#3-configure-template-sync-on-the-template-project))
