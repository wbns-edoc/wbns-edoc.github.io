# CI Implementation Plan — Safe Pull Request Validation

Date: 2026-10-09
Branch: `security/release-gate-review-2026-10-09`

## Current verified baseline

- `package.json` defines `dev`, `build`, and `preview`; no test or lint scripts were present in the inspected manifest.
- `.github/workflows/deploy.yml` deploys on pushes to `main` and manual dispatch; it does not define a pull-request test job.
- A request for `package-lock.json` at the reviewed branch returned GitHub API 404. Treat this as evidence that the file is not available at that path/ref, and re-check repository root before changing install commands.
- Existing authorization test matrix is a specification only; it has not been executed.

## Proposed first CI milestone (no deployment)

Create a separate workflow triggered by `pull_request` targeting `main`. It should:
1. Check out the proposed branch.
2. Set up the Node version consistently with deployment.
3. Install dependencies reproducibly. First add and review a committed lockfile; then use `npm ci`. Do not switch to `npm ci` while the lockfile is absent.
4. Run `npm run build`.
5. Add dedicated test scripts in a later reviewed change, and run unit tests plus authorization/integration tests against a disposable non-production Supabase environment.
6. Upload only sanitized diagnostics; never print environment variables, tokens, private keys, school personal data, or service-role credentials.
7. Never deploy Pages, apply migrations, or connect to Production from this PR validation workflow.

## Proposed rollout order

### Stage A — Repository hygiene
- Confirm package manager and lockfile strategy.
- Add lockfile in a separate change and verify a clean install from scratch.
- Review dependency updates and workflow action permissions.

### Stage B — Build gate
- Add PR-only workflow running the existing build command.
- Verify the workflow with a non-production test PR.
- Have an authorized repository owner configure branch protection/rulesets to require successful checks.

### Stage C — Functional/security gate
- Add test harness and test scripts after identifying current auth, RPC and data-access architecture.
- Use synthetic fixtures and a disposable isolated database.
- Run the existing role/document matrix; include negative tests and concurrent role-removal tests.
- Do not mark tests passed based on code review alone.

### Stage D — Release gate
- Keep production deployment separate from database migration deployment.
- Require migration-source parity, verified backup/restore, authorization test results, Security Advisor review, and explicit owner approval before any production rollout.

## Non-goals and safety constraints

- This plan does not authorize production changes or deployment.
- Do not change or revoke the current System Admin's role.
- Do not run destructive role tests against Production.
- Do not create a Supabase branch/project without presenting the quoted cost and obtaining explicit confirmation.
- Do not put privileged credentials in frontend `VITE_*` variables or browser bundles.

## Exit criteria

- [ ] Lockfile committed and clean install verified.
- [ ] PR workflow passes on a non-production test PR.
- [ ] Branch protection requires the CI check.
- [ ] Security/authorization tests run against isolated non-production data.
- [ ] Production remains untouched until all release gates and owner approval are documented.

**Status:** implementation plan only. No workflow changes, CI runs, tests, migrations, or production changes were performed in this step.
