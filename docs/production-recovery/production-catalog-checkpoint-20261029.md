# Read-only Production catalog checkpoint — 2026-10-29

## Scope and safety

Collected from the Supabase Production project `iigzzwyfxxtqbgjawyom` using read-only catalog queries on 2026-10-29. This report is evidence only; it contains no row-level user/document data and no secret values. No Production writes were performed.

## Enum types observed in Production

The `public` schema currently contains these enum types and labels:

- `approval_decision`: `pending`, `approved`, `rejected`, `returned`
- `assignment_status`: `assigned`, `accepted`, `in_progress`, `completed`, `cancelled`
- `document_status`: `draft`, `pending_approval`, `approved`, `received`, `registered`, `assigned`, `in_progress`, `completed`, `archived`, `sent`, `cancelled`
- `document_type`: `incoming`, `outgoing`
- `urgency_level`: `normal`, `urgent`, `very_urgent`, `critical`

This confirms the `document_status` enum exists in live Production. It does not recover the original Foundation SQL or prove a clean migration replay.

## Public schema inventory

The read-only table inventory returned 27 public base tables:

`approvals`, `audit_logs`, `comments`, `deadlines`, `department_role_permissions`, `departments`, `document_assignment_reports`, `document_assignments`, `document_files`, `document_registers`, `document_status_history`, `documents`, `google_drive_files`, `incoming_document_details`, `notifications`, `number_sequences`, `outgoing_document_details`, `permissions`, `profiles`, `push_subscriptions`, `role_permissions`, `roles`, `senders`, `system_settings`, `user_department_roles`, `user_departments`, `user_roles`.

A read-only `information_schema.tables` query found no `public` table whose name contains `leave`. The `public.notifications` table exists. This means staff-leave work tracked in draft PRs #46/#47 has not been deployed as public leave tables at this checkpoint. Do not describe the leave module as Production-ready or enable submissions until schema, approval routing, notifications, UI, and policy rules have been validated and deployed through an approved release.

## RPC catalog observations

The following expected document workflow RPCs exist and are executable by `authenticated`, not by `anon`, according to `has_function_privilege`:

- `assign_document(uuid, uuid, text, timestamptz)` — SECURITY INVOKER
- `create_approval(uuid, uuid, integer)` — SECURITY INVOKER
- `decide_approval(uuid, approval_decision, text)` — SECURITY INVOKER
- `register_incoming_document(...)` — SECURITY INVOKER, two overloads currently exist (one with seven parameters and one with an additional `p_department_id uuid`)
- `set_document_deadline(uuid, uuid, timestamptz, timestamptz)` — SECURITY INVOKER
- `update_document_status(uuid, document_status, text)` — SECURITY INVOKER
- `get_my_permissions()` — SECURITY DEFINER; executable by `authenticated`, not by `anon`

The two `register_incoming_document` overloads are a source-reconciliation and frontend-call compatibility point: confirm the intended signature and grants before changing callers or removing an overload. This inventory does not prove that every RPC succeeds for each intended role.

## RLS tables without policies

Four public tables had RLS enabled but no rows in `pg_policies` at the time of this check:

- `department_role_permissions`: authenticated has SELECT privilege, but no policy means ordinary RLS-filtered reads return no rows.
- `user_department_roles`: authenticated has SELECT privilege, but no policy means ordinary RLS-filtered reads return no rows.
- `system_settings`: authenticated has no SELECT/INSERT/UPDATE/DELETE table privilege in this check.
- `user_departments`: authenticated has no SELECT/INSERT/UPDATE/DELETE table privilege in this check.

This is not, by itself, proof of a security vulnerability. It is a compatibility concern to test against the current frontend and permission-resolution flow. Do not add broad policies or grants to “fix” it without tracing callers and testing least-privilege behavior in isolation.

## Migration state and release interpretation

The Production migration history currently contains 75 entries. The repository Foundation migration remains a placeholder, and the generated `supabase/tests/fixtures/recovered-production-catalog.sql` remains test-only and includes test-specific patches. The SQL dump `wbns-production-schema.sql` is a useful catalog snapshot, not the original Foundation migration source and not proof of a clean restore.

Do not apply the fixture or guessed DDL to Production. Required next gate: recover trusted source SQL, reconcile every recorded migration, replay in an isolated Supabase environment with fail-fast settings, compare catalog/security state, run end-to-end tests, verify backup/rollback, and obtain explicit release approval.

**Status: Production remains unchanged. Clean replay and staff-leave release are not yet verified.**


## Supabase Advisor follow-up (read-only, 2026-10-29)

The Supabase Security Advisor returned these findings:

- 4 `rls_enabled_no_policy` INFO findings: `department_role_permissions`, `system_settings`, `user_department_roles`, and `user_departments`. These align with the catalog query above; do not treat them alone as proof of unauthorized data exposure.
- 1 WARN finding: `public.get_public_school_name()` is a SECURITY DEFINER function executable by `anon`. The function is intended to expose the public school name, but its full definition and output scope should be reviewed before deciding whether the grant is intentional.
- 18 WARN findings for SECURITY DEFINER functions executable by `authenticated`, including administrative RPCs. These warnings do not prove a bypass: each function's internal authorization checks, fixed `search_path`, and grants need review. In particular, verify that admin RPCs enforce `user.manage` / `role.manage` or the corresponding least-privilege permission.
- 1 WARN finding: leaked-password protection is disabled in Supabase Auth. Enabling it changes Auth configuration and is not included in this read-only audit.

The Performance Advisor returned 10 INFO findings for foreign keys without covering indexes and 25 INFO findings for indexes marked unused. Do not drop indexes based on the unused-index report alone; usage statistics may reflect a short observation period. Review foreign-key indexes and query plans in an isolated environment before proposing changes.

No Advisor remediation was applied. The next safe action is to inspect the exact definitions and grants for flagged SECURITY DEFINER functions, create role-based regression tests, and prepare narrowly scoped candidate changes only after isolated validation.
