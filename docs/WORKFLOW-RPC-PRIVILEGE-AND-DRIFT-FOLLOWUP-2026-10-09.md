# Workflow RPC privilege and source-drift follow-up — 2026-10-09

## Scope and safety

Read-only inspection of the live Supabase catalog and the repository migration `supabase/migrations/20261007205500_harden_workflow_rpc.sql` on `security/release-gate-review-2026-10-09`. No SQL changes, migration application, role changes, or user-data changes were performed. This report is not an integration-test result.

## Expected state in repository migration

The migration moves five workflow implementations to `private`, exposes SQL `SECURITY INVOKER` wrappers in `public`, revokes public/anon execution on the public wrappers, and grants execution to `authenticated`.

## Live state observed

Catalog query results show:

- `public.assign_document`, `public.update_document_status`, and `public.set_document_deadline` remain `SECURITY DEFINER` PL/pgSQL implementations rather than the migration's SQL `SECURITY INVOKER` wrappers.
- `public.create_approval` and `public.decide_approval` are SQL invoker wrappers as expected.
- All five `private.*` implementations exist and are `SECURITY DEFINER`.
- The `private` schema has USAGE for `authenticated` and not for `anon`. Each of the five private functions has an explicit ACL granting EXECUTE to `authenticated` and `service_role`.
- The five public functions' observed ACLs include `authenticated` and `service_role`, not `anon`; however `public` schema USAGE is available to anon, so function exposure should be judged from function EXECUTE privileges and API configuration together, not schema USAGE alone.
- The live public `assign_document` includes checks absent from the repository's private implementation excerpt, including a registered-status transition guard and a future-deadline check. Live public `set_document_deadline` includes document existence, active-assignee, future deadline, and reminder ordering checks absent from the private implementation. Live public `update_document_status` has transition and permission checks not present in the private implementation excerpt. Therefore, blindly rerunning the migration could change behavior, not merely function security mode.

## Risk and interpretation

1. **Migration/live drift is confirmed.** At least three public workflow functions differ materially from the intended wrapper state. Migration names alone do not explain the drift.
2. **Private implementation access is a separate privilege question.** The `private` schema is not USAGE-accessible to `anon`, but is USAGE-accessible to `authenticated`, and the private SECURITY DEFINER functions grant authenticated EXECUTE. This may be reachable through SQL/API surfaces depending on Supabase exposed-schema configuration and should be verified against live API configuration. Do not assume that a schema named `private` is automatically inaccessible.
3. **A simple wrapper rewrite is unsafe.** Existing live public implementations contain validations not visible in the private implementations. Replacing them without reconciling semantics could regress workflow safety.
4. **No privilege change is recommended in this report.** Do not blanket-revoke authenticated EXECUTE or change schema USAGE until function-by-function call paths, exposed schemas, dependencies, and UI expectations are confirmed.

## Required next steps before a corrective migration

- Retrieve the complete migration history and compare SQL content/provenance for each workflow RPC; record exact definitions and grants for every overloaded signature.
- Confirm Supabase API exposed schemas and whether `private` is exposed to PostgREST. If available, inspect configuration read-only.
- Reconcile behavior of each live public implementation with the private implementation, preserving all current validation and mandatory side effects.
- Draft a forward-only migration in the security branch only, with narrow grants and rollback notes; do not apply to Production.
- Test through an isolated environment after cost is disclosed and the owner explicitly approves branch creation. Test positive and negative cases for every role, transition, and RPC; verify the System Admin remains able to operate.
- Run CI/build and migration tests, conduct a backup/restore drill, and obtain explicit release approval before any Production change.

## Release status

**Release blocked.** No integration tests, isolated-environment tests, backup/restore drill, or release approval are evidenced by this inspection. Production was not changed.
