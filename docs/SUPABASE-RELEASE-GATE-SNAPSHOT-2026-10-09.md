# Supabase Release-Gate Snapshot — 2026-10-09

## Scope

Read-only snapshot from Supabase project `wbns-edoc` (`iigzzwyfxxtqbgjawyom`) in `ap-southeast-1`. No schema changes, data writes, grants, function deployments, or branches were created.

## Project and migration state

- Project status: `ACTIVE_HEALTHY`.
- PostgreSQL engine: 17; reported database version 17.11.0.003.
- Live migration history: 26 entries.
- Repository main migration files previously counted: 21. The histories are not one-to-one; exact-name mismatches were documented earlier. Migration names alone are not proof of SQL equivalence.
- Supabase development branches: none returned by `list_branches`.

## Current Security Advisor snapshot

Observed 2026-10-09 at approximately 14:42:58 UTC:
- 10 warnings: `authenticated_security_definer_function_executable`.
- 1 warning: `auth_leaked_password_protection`.

The 10 SECURITY DEFINER warnings include the public RPCs:
`admin_create_department`, `admin_remove_user_role`, `admin_set_user_department`, `admin_set_user_role`, `admin_update_department`, `assign_document`, `attach_document_file_version`, `get_my_permissions`, `set_document_deadline`, and `update_document_status`.

These warnings require function-by-function review; they do not by themselves prove every function is exploitable or should have EXECUTE revoked. The workflow RPC drift and missing last-admin/cycle/scope guards documented in the previous reports remain relevant. Do not apply a blanket revoke.

Remediation reference for SECURITY DEFINER EXECUTE warning:
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

Remediation reference for leaked-password protection:
https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Current Performance Advisor snapshot

- 35 INFO findings for unused indexes.
- 8 WARN findings for multiple permissive SELECT policies.

Unused-index notices are not authorization findings and do not prove an index is safe to drop. Check workload, query plans, and retention window before any removal. Multiple permissive policy notices should be reviewed for logical overlap and query cost; do not combine or remove policies without equivalence tests.

References:
- Unused index: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index
- Multiple permissive policies: https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies

## Branch cost check

Supabase `get_cost(type=branch)` returned:
- recurrence: hourly
- amount: 0.01344
- currency was not explicitly included in the tool response.

A 730-hour month at that returned rate is 9.8112 in the same unspecified currency. This is a simple estimate, not a quote or a guarantee of the final bill; verify currency, compute/usage charges, and any applicable minimums with the billing UI before approval.

No branch was created. Branch creation remains blocked until the project owner explicitly confirms understanding and approval of the recurring cost and its currency is clarified.

## Release gate

**BLOCKED.** No integration tests were run in this snapshot. Migration/source reconciliation, authorization regression tests, Drive upload end-to-end tests, backup/restore drill, and explicit owner release approval remain outstanding. No Production changes were made.
