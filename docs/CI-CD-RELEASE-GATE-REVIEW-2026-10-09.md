# CI/CD and Release-Gate Review — 2026-10-09

## Scope

Read-only review of `package.json`, `.github/workflows/deploy.yml`, and repository README on branch `security/release-gate-review-2026-10-09`.

No workflow, source code, repository settings, production database, or deployment configuration was changed. CI runs were not triggered as part of this review.

## Verified observations

### 1. No test or lint scripts are defined in package.json

The scripts currently define `dev`, `build`, and `preview`. The production build runs `tsc -b && vite build`, so it performs TypeScript project builds and a Vite bundle build, but no unit, integration, authorization, or lint command is defined in the inspected package manifest.

**Risk:** a successful build alone does not demonstrate correct authorization, data isolation, or workflow behavior.

### 2. The deployment workflow builds and deploys on pushes to main

The inspected `.github/workflows/deploy.yml` triggers on `push` to `main` and `workflow_dispatch`. Its job runs `npm install`, `npm run build`, packages `dist`, and deploys to GitHub Pages. No separate pull-request validation job or test job is defined in this workflow.

**Risk:** build failures can block a deploy, but functional/security regressions are not gated by tests in this workflow. Manual dispatch also warrants careful production-release controls.

### 3. Dependency installation is not lockfile-enforced in the workflow

The workflow uses `npm install`, not `npm ci`. For reproducible CI builds, use a committed lockfile and `npm ci`; first verify a valid package lock is present on the intended branch and that it matches `package.json`.

**Risk:** dependency resolution can differ from the tested local environment if the lockfile is missing, stale, or not enforced.

### 4. Public frontend configuration

The workflow injects `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` from GitHub Actions variables. This is consistent with the README's statement that only the project URL and publishable key belong in these variables. Because Vite-exposed variables are bundled into browser code, no service-role key, OAuth client secret, Google credential, or VAPID private key may be exposed through a `VITE_*` variable.

## Recommended non-production hardening

1. Add a pull-request CI workflow that runs a deterministic install, TypeScript build, lint (if adopted), unit tests, and policy/RPC regression tests. It should not deploy.
2. Require that CI checks pass before merging to `main`, using repository branch protection/rulesets configured by an authorized owner.
3. Confirm a package lock is tracked and consistent, then switch the workflow to `npm ci`.
4. Keep deployment limited to reviewed `main` changes and review who may invoke `workflow_dispatch` in the GitHub Pages environment.
5. Add explicit release gates for migration parity, backup/restore evidence, authorization tests, and owner approval. Do not automatically apply database migrations from the frontend deployment workflow.
6. Review third-party GitHub Actions version pinning and deployment permissions under the repository's threat model.

## Release gate

- [ ] Confirm lockfile status and reproducible install.
- [ ] Add PR-only CI checks and run them successfully.
- [ ] Add authorization/integration tests in an isolated non-production environment.
- [ ] Configure merge protection and deployment approvers.
- [ ] Verify secrets are not present in frontend environment variables or built assets.
- [ ] Keep production deployment blocked until database/security release gates are independently satisfied.

**Status:** observations documented; no tests or CI runs executed; no production or deployment changes made.
