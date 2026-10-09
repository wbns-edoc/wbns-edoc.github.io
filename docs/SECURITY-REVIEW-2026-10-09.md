# WBNS e-Document — Static Security Review
Date: 2026-10-09
Scope: source review of repository migrations only. This is not a substitute for verifying live grants/function definitions in Production.

## Findings

### 1. Authenticated SECURITY DEFINER advisor findings need per-function triage
Do not revoke EXECUTE from authenticated as a blanket fix: the frontend intentionally calls these RPCs. Review the live function body, grants, search_path, ownership, and permission gates, then test both allowed and denied callers.

### 2. Functions with positive source evidence

- `public.admin_set_user_role(uuid,uuid)` checks `private.has_permission('user.manage')` OR `private.has_permission('role.manage')`, validates target profile and role, uses `auth.uid()` for `assigned_by`, and is granted to authenticated. Review whether `role.manage` should independently permit role assignment according to the school’s policy.
- `public.admin_remove_user_role(uuid,uuid)` checks the same permission alternatives. Additional policy test required: prevent removing the last active `system_admin` and prevent self-lockout if not already enforced elsewhere.
- `public.get_my_permissions()` is SECURITY DEFINER, has a fixed `search_path = pg_catalog, public`, filters on `ur.user_id = auth.uid()` and active profile, revokes PUBLIC and grants authenticated. Its role is to return the caller’s permissions.
- Workflow RPCs have separate hardening migrations. `public.update_document_status` enforces actor identity, transition guards, and dedicated permissions for completion/archive; `private.create_approval` checks actor permission and requires an active approver with `document.approve`. Validate these against live definitions because later migrations replace earlier function bodies.
- The repository includes explicit revokes from `anon` for admin, workflow, file-version, and permission RPCs. Live grants should still be checked in Production.

### 3. Items not yet verified

- The current live definitions and grants for all 10 Security Advisor findings.
- Whether every department RPC checks permission and validates parent/target department constraints.
- Whether `public.attach_document_file_version` verifies document visibility and `document.update` inside the database function itself, not only in the Edge Function.
- Protection against removing/demoting the last system administrator.
- Supabase Auth leaked-password protection setting.
- RLS negative tests with a normal staff account and an anonymous client.
- Migration history parity between Production and repository.

## Safe remediation order

1. Export/read live function definitions and grants without modifying Production.
2. Map each function to expected permission codes and caller roles.
3. Add isolated tests for authorized and unauthorized callers.
4. Prepare reviewed migration(s) only for demonstrated gaps; do not apply until backup, migration history, and school approval are confirmed.
5. Enable leaked-password protection in Supabase Auth settings and test the password-reset flow.
6. Run the Production smoke-test checklist with real school accounts.

## Acceptance rule
No finding is considered resolved based only on source inspection or a successful frontend build. Record the live verification evidence and smoke-test result.
