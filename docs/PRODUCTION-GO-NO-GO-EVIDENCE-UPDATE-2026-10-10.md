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


## Follow-up evidence — 2026-10-10

- Recovered Catalog Fixture CI run 26: schema lint and all 6 catalog smoke checks **PASS** on the disposable local Supabase database. The workflow was still completing service cleanup at the time this note was recorded; treat the job's final conclusion as authoritative.
  - Run: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031167633
  - This validates the reconstructed test fixture only. It does **not** prove the incomplete historical migration chain can recreate Production from zero and does not authorize deployment.
- Drive Upload CI run 111: **PASS**.
  - Run: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031167475
- Workflow RPC Security CI run 42: **FAIL/CORRECTLY BLOCKED** by the migration-order security guard. Do not merge/deploy until the latest definitions are corrected and database tests can run against an authoritative migration source.
  - Run: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031167470
- Read-only Production count check reconfirmed: 1 profile, 0 departments, 0 documents, 0 document-file links, and 0 Drive-file metadata rows. No Production data or schema was changed by this check.
- Owner-approved access requirement recorded: System Admin and the director receive automatic read access to all school documents, across all four departments. This is read-only visibility and does not grant System Admin workflow mutation/approval powers. Registrar and deputy director do not receive blanket access by implication. This policy is documented but **not yet implemented in Production**.

## Updated release decision

**NO-GO for merge/deployment to Production remains in force.** Fixture lint/smoke success is useful evidence, but the Workflow RPC security gate and authoritative migration-source gap remain unresolved. Department-scoped access still cannot be enforced reliably while Production's `documents` table has no `department_id`. Continue only with isolated tests and reviewed, forward-only changes until migration source recovery, authorization tests, backup/restore verification, and explicit deployment approval are complete.

No Production schema, data, RLS, grants, roles, or Edge Function deployment was changed in this follow-up.


## Fresh read-only Supabase Advisor check — 2026-10-10 06:37 UTC

Security Advisor returned the same release-critical categories in a fresh live snapshot:
- **10** `authenticated_security_definer_function_executable` warnings: `admin_create_department`, `admin_remove_user_role`, `admin_set_user_department`, `admin_set_user_role`, `admin_update_department`, `assign_document`, `attach_document_file_version`, `get_my_permissions`, `set_document_deadline`, and `update_document_status`.
- **1** `auth_leaked_password_protection` warning: leaked-password protection is disabled.

Performance Advisor returned **35 unused-index INFO findings** and **8 multiple-permissive-SELECT-policy WARN findings**. Do not remove indexes or consolidate policies blindly: this is a new/empty application data footprint, and policy consolidation can change access semantics. Address security authorization before performance cleanup.

Remediation links:
- [Supabase Security Advisor: SECURITY DEFINER functions callable by authenticated users](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- [Supabase Auth: leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- [Supabase Performance Advisor: multiple permissive policies](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies)

These are read-only advisor observations, not remediation. No Production changes were made. The release remains NO-GO.


## CI re-run on evidence update commit — 2026-10-10

The three workflows triggered by evidence commit `a29554a83d01542168174285529f879e5c954018` have completed:
- [Drive Upload CI run 38031625655](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031625655): **PASS**.
- [Recovered Catalog Fixture CI run 38031625794](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031625794): **PASS**.
- [Workflow RPC Security CI run 38031625679](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031625679): **FAIL**, as expected from the current migration-order guard. The repository still has later SECURITY DEFINER definitions for public workflow RPCs, and the guard must not be weakened to manufacture a pass.

This re-run changes no release decision: **NO-GO**. Do not merge PR #6 or deploy Edge Functions until authoritative migration history/source, scope enforcement, RPC authorization tests, and backup/restore evidence are complete.


## Production Edge Function drift check — 2026-10-10

A read-only retrieval of the currently deployed `drive-upload` Edge Function (Production version **2**, `verify_jwt=true`) was compared with the repository branch source:
- Deployed source validates the user and permission, selects the document under the caller JWT, uploads the bytes to Google Drive, and returns the Drive response.
- Deployed source does **not** contain the repository branch's `google_drive_files` metadata insertion, `attach_document_file_version` RPC call, or compensation cleanup path.
- Branch source includes those additional steps and uses `SUPABASE_SERVICE_ROLE_KEY` server-side; it is not deployed.
- Both sources currently contain wildcard CORS (`Access-Control-Allow-Origin: *`). Tightening CORS requires confirming the actual frontend origin(s), but should be included in release hardening.
- This was a source inspection only. No live upload request was sent and no Edge Function version was deployed.

**Impact:** A successful Google Drive upload from the deployed function does not establish that the file metadata was persisted or attached to the corresponding document. Production upload/attachment end-to-end behavior is therefore unverified and the deployed implementation is behind the current branch. Do not deploy the branch until department/document scope authorization and workflow RPC risks are resolved and the runtime integration test passes.

Evidence:
- [Production function listing / deployment history is available in Supabase Dashboard](https://supabase.com/dashboard/project/iigzzwyfxxtqbgjawyom/functions)
- [Repository branch implementation](https://github.com/wbns-edoc/wbns-edoc.github.io/blob/fix/drive-upload-metadata-atomicity-2026-10-09/supabase/functions/drive-upload/index.ts)
- [Drive Upload CI run 38031625655](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38031625655)

This finding is an additional release blocker; **NO-GO remains in force**.
