# Staff leave source-tree discovery — 2026-10-21

Status: repository inspection only. No application behavior, Production schema, or user data changed.

## Confirmed repository facts

- The active application entry point is `src/main.tsx`; the repository tree does not contain `src/App.tsx`.
- `src/main.tsx` creates the Supabase client and currently defines the React application, authentication, page type, and UI components in one large file.
- Existing top-level page keys include dashboard, incoming/outgoing documents, reports, senders, tasks, assigned, approvals, audit, admin, departments, permissions, deleted, settings, and about. No leave page key is currently declared in the inspected entry point.
- `package.json` has `build` = `tsc -b && vite build`; it currently declares no test script.
- Existing Supabase functions have `verify_jwt = true` in `supabase/config.toml`. A leave function must follow the same authenticated baseline, then enforce authorization server-side; JWT validation alone is not authorization.
- The tree contains `supabase/migrations/20261020230000_staff_leave_workflow_foundation_draft.sql`, but it remains a draft and must not be applied as-is.

## Implementation map (confirmed before coding)

1. **UI integration:** add the leave page/navigation and leave-specific components in the real entry point `src/main.tsx`, or first extract a small, typed leave module. Do not create an assumed `src/App.tsx`.
2. **Database:** build a new additive migration only after reading exact production role codes, helper definitions, grants, and existing RLS. No Production SQL has been run for this feature.
3. **Workflow:** use atomic, authorization-checked database RPCs for submit, deputy review, director decision, director-absence exception, cancellation, and return/overdue handling. Never trust client-supplied actor IDs or status transitions.
4. **Notifications:** use a durable idempotent outbox and existing notification integration only after its schema, RLS, and insertion contract are verified.
5. **Tests:** add a dedicated test command and reproducible isolated database fixture. Tests must cover RLS ownership, role scope, self-approval, transition ordering, cancellation boundary in Asia/Bangkok, immutable action history, policy-version snapshotting, outbox retries, and dashboard reconciliation.
6. **Policy:** one school-wide policy version as requested; personnel category is reporting metadata only. Numeric entitlements/day-count rules remain disabled until source verification and school approval.

## Release gates

- [ ] Read-only RBAC/helper/RLS/grant evidence recorded.
- [ ] Applicable official leave rules and school-approved interpretation verified.
- [ ] Additive migration replay passes in a disposable database.
- [ ] Workflow, RLS, privacy, notification, and aggregate tests pass.
- [ ] Frontend build and CI pass.
- [ ] Synthetic-account pilot, rollback plan, and explicit release approval completed.

**Current decision: NO-GO for Production.** This document records verified repository paths and sequencing; it is not an implementation or deployment claim.
