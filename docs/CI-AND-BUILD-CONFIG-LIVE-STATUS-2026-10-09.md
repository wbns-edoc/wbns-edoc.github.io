# CI and Build Configuration Live Status — 2026-10-09

## Scope and safety

Read-only review of GitHub Actions and the existing draft pull request. No workflow was triggered manually, no branch was created, no pull request was merged, and no Supabase or Production settings were changed. Incremental spend target remains 0 THB.

## Verified evidence

- Draft PR #5, `Fail closed on missing Supabase build configuration`, is open and not merged:
  https://github.com/wbns-edoc/wbns-edoc.github.io/pull/5
- PR head branch: `safety/ci-build-config-validation`; observed head SHA: `5a2e5e0e8b4e0261a6a52ce68b3394ddcfea1b32`.
- Latest observed Pull Request CI run succeeded:
  https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37908909036
- The job steps show success for dependency installation, `npm ci`, build with a non-production placeholder Supabase URL/key, build-env tests, and a negative test that expects missing configuration to fail.
- The PR workflow `.github/workflows/pr-ci.yml` runs on pull requests and non-main branch pushes, uses read-only `contents: read`, and does not deploy GitHub Pages.
- The PR's intended application change removes silent Production Supabase configuration fallbacks and fails closed when required build variables are absent. Review custom Supabase-domain compatibility before merging.
- The separate `.github/workflows/commit-lockfile.yml` run succeeded:
  https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37908902265

## Important unresolved finding

Despite the lockfile workflow run reporting success, the currently observed PR head tree at SHA `5a2e5e0e8b4e0261a6a52ce68b3394ddcfea1b32` contains no `package-lock.json`. A direct repository tree listing and root contents listing both omit it. Therefore a committed lockfile is **not verified** on the current branch head; do not mark reproducible dependency locking complete based only on the workflow's green status. Investigate the workflow's commit/push outcome and re-run CI after the lockfile is present.

## Scope limitation

The security branch `security/release-gate-review-2026-10-09` currently contains only `.github/workflows/deploy.yml` under `.github/workflows`; it does not contain the PR CI workflow. The passing CI result belongs to PR #5's separate head branch, not to the security branch or `main`. It proves the tested frontend/build configuration path for that SHA only; it does not validate database authorization, migration parity, file upload integration, backup/restore, or Production release readiness.

## Next safe actions

1. Keep PR #5 draft until a reviewer checks the source diff and custom-domain assumptions.
2. Resolve and verify the absent lockfile at the actual branch head; require `npm ci` to run against a committed lockfile in future CI.
3. Confirm the negative configuration test and review the deployment workflow behavior before merging.
4. Continue database review read-only; do not apply corrective DDL until behavior parity, backup/restore, and admin lockout protections have verified tests.

## Status

Frontend/build-config CI on PR #5's observed SHA: **passed**.
Committed lockfile at current PR head: **not verified / appears absent**.
Production release: **blocked** pending independent database and operational gates.
