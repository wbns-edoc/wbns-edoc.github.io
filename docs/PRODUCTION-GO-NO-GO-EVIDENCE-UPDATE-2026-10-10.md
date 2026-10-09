# Production Go/No-Go Evidence Update — 2026-10-10

## Latest automated checks

- Drive Upload CI run 90: **PASS** — https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37968830732
  - Frontend build with placeholder non-production config passed.
  - JWT verification configuration check passed.
  - No server secrets found in frontend source.
  - Localized upload error tests, cleanup policy tests, input validation tests, and Edge Function type-check passed.
  - These checks do not verify a live Drive upload, production environment secrets, department-level authorization, or deployment behavior.

- Workflow RPC Security CI run 20: **FAIL/CORRECTLY BLOCKED** — https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37968830755
  - Static guard detected SECURITY DEFINER latest definitions for `public.assign_document`, `public.update_document_status`, and `public.set_document_deadline`.
  - Database replay and pgTAP checks were skipped because the guard failed before startup. Full local replay remains blocked by the placeholder foundation migration.

## Latest Supabase Security Advisor snapshot

Observed 2026-10-09:
- 10 warnings: authenticated roles can execute public SECURITY DEFINER functions. Findings include `admin_create_department`, `admin_remove_user_role`, `admin_set_user_department`, `admin_set_user_role`, `admin_update_department`, `assign_document`, `attach_document_file_version`, `get_my_permissions`, `set_document_deadline`, and `update_document_status`.
- 1 warning: leaked-password protection disabled.

Do not bulk-revoke EXECUTE privileges: that could break application flows and is not a substitute for checking each function's authorization. The `admin_remove_user_role` path especially needs a last-System-Admin invariant before any change.

## Current release decision

**NO-GO for merge/deployment to Production.** A green Drive Upload CI alone does not make the whole system production-ready. The authorization CI is blocked and the repository cannot recreate the current database from zero. Department-level document scope is also not represented by `documents.department_id` in the current Production schema.

## Concrete next action

Recover an authoritative schema/migration source. The preferred input is a schema-only export created by the owner in a trusted environment, or the complete original migration set. Do not share credentials or data dumps. After recovery, build a disposable local database, implement and test a forward-only authorization fix, then take/verify backup and request explicit owner approval before Production changes.

No Production schema, data, RLS, grants, roles, or Edge Function deployment was changed in this update.
