# Workflow RPC corrective design — draft, not executable — 2026-10-09

## Status

Design-only artifact for `security/release-gate-review-2026-10-09`. It is deliberately **not** a SQL migration and must not be applied to Production. Live catalog checks are read-only. No application tests have been run.

## Verified inputs

- Production migration history has 26 entries and does not include a migration named `harden_workflow_rpc`.
- The repository has `supabase/migrations/20261007205500_harden_workflow_rpc.sql`, which intends to move five implementations to `private` and create public invoker wrappers.
- In the live catalog, `public.assign_document`, `public.update_document_status`, and `public.set_document_deadline` remain `SECURITY DEFINER` PL/pgSQL implementations; `public.create_approval` and `public.decide_approval` are invoker wrappers.
- All five private implementations exist and are SECURITY DEFINER. The live ACL query showed authenticated EXECUTE on those private functions and authenticated USAGE on the private schema; anon did not have private schema USAGE.
- Live public implementations for assignment, status changes, and deadlines contain validations not visible in their private counterparts. Exact behavior must be reconciled before changing public function definitions.

## Design principles

1. Preserve all currently enforced business validations and side effects unless a deliberate, reviewed change is approved.
2. Prefer narrow, explicit privileges. Do not assume a schema named `private` is unreachable; verify API exposed-schema configuration and direct grants.
3. Do not blanket revoke EXECUTE from `authenticated`. The UI and other callers may depend on current RPC signatures.
4. Do not change the only System Admin's assignments or role membership as part of tests.
5. Make any future correction forward-only and additive where feasible; capture pre-change definitions, ACLs, dependent callers, and rollback/restore plan first.

## Per-function reconciliation matrix

| RPC | Live public state | Required parity before a fix | Minimum negative/positive tests |
|---|---|---|---|
| `assign_document` | SECURITY DEFINER implementation | Preserve registered-status guard, future-deadline check, row locking, assignment/history/notification/deadline side effects; compare all validation with private body | allowed registered document; wrong status; missing document; inactive assignee; past due date; caller without permission |
| `update_document_status` | SECURITY DEFINER implementation | Preserve dedicated-RPC transition blocks, permission-specific complete/archive checks, transition validator, history and deadline side effects | allowed transition; invalid transition; unauthorized complete/archive; direct pending-approval/assigned transition; nonexistent document |
| `set_document_deadline` | SECURITY DEFINER implementation | Preserve document existence, active assignee, future due date, reminder-before-deadline, and insertion behavior | valid deadline; missing document; inactive assignee; past due date; reminder after due date; caller without permission |
| `create_approval` | SQL invoker wrapper | Confirm private body and grants remain compatible with UI/API call path; preserve approver permission, draft-only state, locking and notification behavior | valid approver; unauthorized approver; non-draft document; invalid step; caller without permission |
| `decide_approval` | SQL invoker wrapper | Confirm private body and grants; preserve ownership/pending checks, decision validation, status updates and notification | assigned approver; other user; already decided; invalid decision; caller without permission |

## Required evidence before implementation

- Full `pg_get_functiondef` and ACL snapshots for each exact signature and all overloads.
- Complete source migration and migration history provenance reconciliation; do not infer equivalence from migration names.
- Supabase/PostgREST exposed schema configuration and deployed API behavior. Repository `supabase/config.toml` currently only declares `drive-health` and `user-import` function JWT settings; that file alone does not establish the live API exposed-schema configuration.
- Caller inventory from frontend, Edge Functions, triggers, scheduled jobs, and any external clients.
- A tested isolated environment with representative schema and non-production identities. No branch should be created until its exact cost is retrieved and disclosed and the owner explicitly confirms it.
- CI build/typecheck, RPC integration tests, authorization matrix, upload integration test, and a successful backup/restore drill.

## Decision

**Do not write or apply a corrective SQL migration yet.** The private implementations and live public implementations differ in behavior, and exposed-schema configuration remains unverified. The next safe engineering step is to collect full function bodies and caller/configuration evidence, then produce a reviewed forward-only patch plus executable tests. Production release remains blocked.
