# Zero-Cost Engineering Plan — 2026-10-09

## Non-negotiable constraint

Project requirement: incremental infrastructure and testing spend must be **0 THB**. Do not create Supabase branches, projects, paid runners, storage, or other billable resources. Do not enable paid features or change plans. If a necessary validation cannot be completed at zero incremental cost, record it as blocked and request an owner-approved alternative rather than incurring cost.

## Cost check evidence

Supabase `get_cost(type=branch)` returned `amount=0.01344` with hourly recurrence; the response did not specify currency. Since the currency is unclear and the rate is non-zero, a new Supabase branch fails the 0-THB requirement and must not be created. No branch has been created.

## Current repository preflight

Read-only inspection of `package.json` on `security/release-gate-review-2026-10-09` found scripts only for `dev`, `build` (`tsc -b && vite build`), and `preview`. No test script is defined. Checks for `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, and `bun.lock` returned not found. The path `.github/workflows/ci.yml` was also not found. These checks do not establish that no other workflow exists under a different filename.

Consequences:
- A reproducible `npm ci` pipeline cannot currently be assumed.
- No test runner or automated authorization suite is declared by `package.json`.
- No build or test command was executed during this read-only preflight.

## Zero-cost work that can proceed

1. Continue source/catalog review and migration parity analysis using existing GitHub and Supabase connections, without provisioning infrastructure.
2. Add test specifications and SQL static checks to the existing security branch; distinguish static checks from executed integration tests.
3. Prepare local-only test instructions using tools already available to the school/team. Local Docker/database tests may be used only if already available and they incur no new paid service or subscription.
4. Add a lockfile and deterministic CI only after generating it through the project's normal package manager and reviewing the dependency graph; do not fabricate a lockfile.
5. Keep corrective SQL forward-only and un-applied until source parity and the full function behavior are reviewed.
6. Use existing project resources for read-only checks only. Do not run test data writes, file uploads, privilege changes, or destructive tests against Production.
7. If the only safe way to prove a release gate requires billable isolation, leave that gate blocked. Zero-cost policy takes precedence over declaring release readiness.

## Current release gates

| Gate | State | Evidence required |
|---|---|---|
| Migration/source parity | BLOCKED | Reconcile all live definitions and migration provenance |
| Workflow authorization | BLOCKED | Automated positive/negative tests in an isolated environment |
| Drive upload | BLOCKED | End-to-end test for success, RLS denial, cleanup and idempotency |
| System Admin survivability | BLOCKED | Test last-admin/self-removal protections without touching the only live admin |
| Reproducible CI | BLOCKED | Lockfile, CI definition, and successful recorded build |
| Backup/restore | BLOCKED | Successful restore drill and integrity verification |
| Cost compliance | PASS for branch avoidance | No billable branch/resource created; continue zero-cost policy |
| Production approval | NOT GRANTED | Owner approval after all gates pass |

## Safety statement

This plan makes no Production changes and does not claim the system is release-ready. Zero-cost requirements do not justify skipping security, integration, restore, or authorization tests.
