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


### Follow-up live Edge Function review (2026-10-09)

Read-only source inspection of the deployed `user-import` Edge Function (active version 3, JWT verification enabled) identified additional high-impact authorization concerns:

9. **Bulk import can assign privileged roles.** The live function resolves the supplied role name/code and upserts it into `user_roles` using the service/admin client. It does not visibly reject `system_admin` or require a distinct `role.manage` permission for privileged-role assignment. Its entry gate accepts either `user.manage` or `role.manage`. A user manager may therefore be able to grant a role beyond their intended authority through bulk import.
10. **Bulk import can deactivate profiles without a last-admin guard.** The live `set_active` action updates `profiles.is_active` using the admin client after the same broad `user.manage OR role.manage` permission gate. The inspected body does not check whether the target is the only active `system_admin`. The bulk-import path also writes `profiles.is_active` from each row and does not visibly guard the last active administrator.
11. **Live and repository sources differ.** The deployed version 3 contains `set_active` and `resend_invitation` actions not present in the repository's `supabase/functions/user-import/index.ts` (which appears to be an older source variant). Do not deploy the repository file over Production until source parity is reconciled; doing so could remove live functionality.

These are source-review findings, not exploit tests. No Edge Function was changed or invoked for writes during this review. The Production `system_admin` assignment was not altered.

### Edge Function remediation acceptance tests

- `user.manage` alone cannot grant `system_admin` or any role outside an explicitly approved allowlist.
- `role.manage` authority is checked separately for role assignments; policy is consistent with the reviewed RPCs and RLS.
- Deactivating a system administrator follows a reviewed recovery policy and cannot leave zero active administrators; never test this against the sole Production admin.
- Both per-row role assignment and profile activation/deactivation are audited with actor, target, previous state and result.
- The repository source and deployed function version are reconciled before deploying any new version.


### Second-pass RPC body review (2026-10-09)

A fresh read-only retrieval of the live SQL function definitions confirms the following implementation details:

12. **Role RPC authorization mismatch is present in live SQL.** Both `admin_set_user_role` and `admin_remove_user_role` accept `user.manage OR role.manage`, while the inspected table RLS policy only allows `role.manage` for direct `user_roles` management. Because the RPCs are SECURITY DEFINER, their own checks govern the RPC path. Decide the separation-of-duties policy, then align the RPC and Edge Function gates.
13. **Department RPCs also use broad permission gates.** `admin_set_user_department` and `admin_update_department` accept either `user.manage` or `role.manage`. The department update body checks that the target exists, names are nonblank, and code is unique, but does not visibly validate parent existence/active status or prevent hierarchy cycles. Confirm foreign keys and any other invariant before proposing a migration.
14. **Document assignment and deadline RPCs have limited visible scope checks.** `assign_document` verifies `document.assign`, document existence, active assignee, future deadline and locks the document before requiring status `registered`; it does not visibly verify caller scope for that specific document. `set_document_deadline` checks `document.assign`, existence, active assignee and date ordering, but does not visibly lock/check document status or verify caller scope before inserting a deadline. Confirm whether intended document scope is global or department/assignment-scoped.
15. **File-version attachment lacks a visible file/document association check.** `attach_document_file_version` verifies that both document and Drive-file rows exist, then creates a version for the supplied pair. The function body does not visibly reject a Drive-file row already associated with another document or enforce caller scope to that document. Verify schema constraints and business rules before remediation.
16. **Role and department audit coverage remains uncertain.** The inspected role assignment/removal and department update bodies do not write audit rows directly. Confirm whether database triggers cover these operations; do not count audit as complete until verified.

No live function was modified and no write-path was invoked. Recommended next step remains a policy decision and isolated tests before a forward-only migration; Production has one active system administrator, and that assignment must not be altered for testing.


## Additional live grant and RLS confirmation (2026-10-09)

A fresh read-only catalog query confirmed the current database grants and policies:

- The reviewed public RPCs are executable by `authenticated` and not executable by `anon`; the inspected functions use fixed `search_path` settings. This is positive baseline evidence, but it does not by itself establish correct authorization within the function bodies.
- `public.user_roles` has a direct table-management RLS policy requiring `private.has_permission('role.manage')`. The live SECURITY DEFINER role RPCs `admin_set_user_role` and `admin_remove_user_role` instead accept `user.manage OR role.manage`. Because SECURITY DEFINER functions can bypass ordinary RLS, the broader RPC authorization is a confirmed policy mismatch requiring an explicit decision and isolated tests. Do not assume the table policy constrains these RPCs.
- The live Security Advisor continues to report 10 authenticated-callable SECURITY DEFINER functions and leaked-password protection disabled. These findings remain open; no production grant, function, Auth setting, schema, data, or role assignment was changed in this review.
- The existing Production `system_admin` assignment must never be removed, demoted, deactivated, or altered as a test. Do not deploy a speculative migration or change grants until the app's actual call paths and expected roles are reconciled, a non-production target is available, and rollback/restore are verified.


### Additional RLS policy inventory (2026-10-09)

A further read-only query inspected policies on `user_roles`, `profiles`, `departments`, `documents`, `document_assignments`, and `google_drive_files`:

- `user_roles_manage_admin` permits direct table management only when `private.has_permission('role.manage')`; this reinforces the RPC-vs-RLS mismatch described above.
- `profiles_update_self_or_admin` allows a user to update their own profile row or an actor with `user.manage`. Review which profile columns are writable by a normal user and whether column-level grants or a narrow RPC are needed to prevent self-editing privileged fields such as `is_active` or department assignment. The policy alone does not show which columns are grantable.
- `departments_select_authenticated` has `qual = true`, so every authenticated user can read department rows. This may be intentional for routing and staff UI; confirm whether inactive departments or hierarchy metadata should be visible to all signed-in users.
- `document_assignments_select_authorized` allows an assignee, assigner, or actor with `document.view` to read assignment rows. Confirm whether `document.view` is intentionally global or should be constrained by document/department scope.
- `google_drive_files_authorized` permits reads to users with `document.view`; verify that Drive metadata exposed through this table is consistent with document-level visibility.
- Direct document SELECT/UPDATE policies retain owner/creator or permission-based predicates, but they do not establish that SECURITY DEFINER RPCs apply the same object-level checks.

These are policy observations, not proof of an exploitable path. The query did not modify policies or data. Before changing profile policies or column grants, inspect the frontend's update paths and table grants to avoid breaking normal profile editing; then validate both allowed and denied cases in a non-production environment.
