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

### Follow-up read-only checks (2026-10-09)

- Queried PostgreSQL constraints and non-internal triggers for `user_roles`, `profiles`, `roles`, and `departments`. `user_roles` has its primary key and foreign keys, but the query found **no user-defined trigger on `user_roles`** and no constraint that enforces a minimum count of active `system_admin` users. The visible `profiles` trigger only maintains `updated_at`; department triggers maintain `updated_at`. This strengthens the concern in finding 1: last-admin protection is not evident in the inspected table constraints/triggers or RPC body.
- A read-only aggregate query found **1 active profile with the `system_admin` role (1 assignment)** at the time checked. This is a high-impact single-admin configuration: do not test by removing/demoting this account, and do not attempt a Production change until a second school-controlled administrator and a tested recovery path exist.
- The live `private.has_permission(text)` helper checks permissions through role mappings for `auth.uid()` and requires an active profile. It is SECURITY DEFINER with a fixed `pg_catalog, public` search path. This does not mitigate the missing last-admin invariant inside role removal.
- These checks were read-only; no Production data or schema was changed.

### Recommended remediation acceptance tests

Before applying any forward-only Production migration, reproduce in a non-production environment:
1. Removing the only active `system_admin` assignment is rejected with a stable error and leaves the assignment unchanged.
2. Demoting or deactivating the last active system administrator is rejected if deactivation/demotion paths exist.
3. Removing another user's non-admin role remains possible only for the explicitly approved permission set.
4. A `role.manage`-only actor cannot grant or remove `system_admin` unless the school owner explicitly approves that policy.
5. Concurrent attempts to remove/demote the last two administrators cannot leave zero active administrators (the guard must be concurrency-safe, not just a count check without serialization).
6. Audit history records both successful role changes and rejected sensitive attempts where policy requires it.

A single-admin Production state is not a reason to run a destructive test; establish a second administrator through a reviewed, auditable process first.

- RLS policy inspection found `user_roles_manage_admin` grants table-level management only to actors with `role.manage`, while the SECURITY DEFINER RPCs `admin_set_user_role` and `admin_remove_user_role` accept `user.manage` **or** `role.manage`. Because these RPCs execute with definer privileges, their explicit permission logic can allow a `user.manage`-only actor to bypass the narrower table policy. Confirm the intended separation of duties and make RPC authorization match approved policy; do not rely on RLS to constrain SECURITY DEFINER function bodies.
