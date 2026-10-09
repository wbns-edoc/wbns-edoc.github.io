# WBNS e-Document — Live Security Review
Date: 2026-10-09
Scope: read-only inspection of live Production function definitions, function configuration and EXECUTE grants, plus Supabase Security Advisor. No Production data or schema was changed by this review.

## Live observations

All 10 functions listed by Security Advisor are live as `SECURITY DEFINER`. Their `search_path` is explicitly set:
- `pg_catalog, public, private` for the admin, assignment, file-version, deadline and status functions.
- `pg_catalog, public` for `get_my_permissions()`.

The inspected EXECUTE grant listing includes `authenticated`, `postgres`, and `service_role` for each of these functions. This confirms why a blanket revoke from `authenticated` would risk breaking legitimate application operations. This read-only review did not independently establish ownership or run positive/negative caller tests.

### Findings requiring remediation design and further checks

1. **Last system administrator protection is not visible in `admin_remove_user_role`.** The live body checks `user.manage` OR `role.manage`, then directly deletes the selected `user_roles` row. It contains no explicit last-active-admin or self-lockout guard. Inspect triggers/constraints and test the last-admin case before concluding the invariant is absent. Do not test by removing a real admin in Production.
2. **File-version RPC relies on a broad permission check.** `attach_document_file_version` checks authentication, `document.update`, document existence and Drive-file existence, but its body does not check object-level visibility/ownership or that the referenced Drive file belongs to the same document. Because it is SECURITY DEFINER, do not assume caller RLS alone protects the body. Review the table relationships and add explicit checks in a forward-only migration if the invariant is not enforced elsewhere.
3. **Deadline RPC has no visible document status/object-scope check.** `set_document_deadline` checks `document.assign`, document existence, active assignee and future due date; it inserts a deadline without locking/checking document status or proving the caller may assign that specific document. Confirm intended policy and other constraints before remediation.
4. **Role removal/assignment policy.** `admin_set_user_role` and `admin_remove_user_role` accept either `user.manage` or `role.manage`. Confirm that school policy intentionally allows role-only managers to grant/remove every role, including `system_admin`.
5. **Department hierarchy constraints.** Create/update department functions check permission, required values and duplicate code, but no explicit validation of parent existence, active state, or cycles is visible in their bodies. Check foreign keys/triggers and add validation if needed.
6. **Audit coverage.** `admin_set_user_department` records an audit event. The inspected role assignment/removal and department create/update bodies do not visibly write audit rows. Verify triggers/audit coverage before concluding these actions are unlogged.
7. **Document status RPC.** The live `update_document_status` checks actor identity, uses a row lock, blocks dedicated workflow transitions, checks destination permissions and records history. Keep testing transition edge cases and verify the underlying transition helper.
8. **Permission introspection.** `get_my_permissions()` filters by `auth.uid()` and active profile, and has a restricted search path; it appears appropriately scoped from the inspected body.

## Security Advisor
The current live Advisor reports 10 `authenticated_security_definer_function_executable` warnings and one `auth_leaked_password_protection` warning. The latter remains an open project setting; it was not changed in this review. Advisor warnings are triage signals, not proof that every RPC is exploitable.

## Safe next steps
1. Inspect relevant table constraints, triggers, RLS policies and audit triggers read-only.
2. Define expected authorization policy with the school owner, especially role delegation, document visibility, and last-admin protection.
3. Prepare narrowly scoped forward-only SQL and tests; do not modify Production until authoritative migration history, backup and approval are confirmed.
4. Test denied callers in a non-production environment; never probe destructive cases using the only real administrator.
5. Enable leaked-password protection in Supabase Auth settings, then test sign-in and password recovery with a school-controlled account.
6. Run the full smoke test and an isolated backup-restore drill.

## Acceptance rule
This review is not a production security sign-off. No finding is resolved until a safe test and live evidence are recorded. Current release decision remains **NOT YET PRODUCTION READY**.
