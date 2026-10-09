# Production Security Remediation Plan — Role Administration
Date: 2026-10-09
Status: design only; **no Production schema/data changes made**

## Explicit safety constraint
Do not remove, demote, deactivate, or otherwise change the existing `system_admin` assignment as part of review or testing. Live read-only inspection found one active system administrator. No destructive test was run.

## Verified live facts
- `public.admin_set_user_role(uuid, uuid)` and `public.admin_remove_user_role(uuid, uuid)` are SECURITY DEFINER functions with fixed search paths.
- Both RPCs currently allow either `user.manage` OR `role.manage`.
- The RLS policy `user_roles_manage_admin` permits direct table management only when `role.manage` is present. Thus the RPC authorization is broader than the table policy for a `user.manage`-only actor.
- `user_roles` has primary/foreign-key constraints but the read-only trigger query found no user-defined trigger on this table and no minimum-active-system-admin constraint.
- Current aggregate check: one active profile holds `system_admin`. This count is time-specific and must be rechecked before any approved change.

## Proposed policy decisions (school owner must confirm)
1. Only `role.manage` may grant/revoke roles, or explicitly define a narrower approved split; `user.manage` alone must not grant/revoke privileged roles.
2. Granting/revoking `system_admin` must require an explicitly designated high-trust permission and auditable operator identity.
3. The last active system administrator must never be removable/demotable/deactivatable through any supported path.
4. The protection must be concurrency-safe. A simple count followed by DELETE without serialization is insufficient.
5. Record successful role changes in the audit log. Decide whether denied high-risk attempts should also be recorded without leaking sensitive data.
6. Provide a school-controlled recovery procedure before making any role-policy change.

## Required implementation/test design
- Prepare a forward-only migration only after migration-history reconciliation and verified backup.
- Serialize privileged-role changes (for example, a transaction-scoped advisory lock on a stable key, consistently used by every code path that can change administrator assignments) before counting active admins and mutating assignments. Review lock ordering and transaction behavior.
- Check the target role and target user's active profile explicitly. Reject removing the actor's own last-admin assignment.
- Ensure the same invariant covers every supported path that can revoke admin capability, including role removal, role changes, profile deactivation, and any administrative import path. Inspect all writers before claiming complete protection.
- Ensure RPC permission checks agree with the intended RLS policy and least-privilege model.
- Test in isolated non-production first:
  - only admin cannot be removed/demoted/deactivated;
  - an admin can grant/revoke ordinary roles only with approved permissions;
  - `user.manage` without `role.manage` cannot alter role assignments unless explicitly approved;
  - role-only manager cannot grant/revoke `system_admin` unless explicitly approved;
  - concurrent revocation attempts cannot leave zero active admins;
  - audit records reflect successful changes and any required security events;
  - normal staff remains denied.
- Production deployment requires a verified backup, migration SQL review, school owner approval, post-deployment read-only checks, and smoke tests.

## Still blocked on prerequisites
- Production migration history contains 26 entries; repository migration files cannot be matched by filename prefix alone. Obtain authoritative SQL and map semantics before drafting/applying a Production migration.
- No isolated restore drill has been evidenced.
- The leaked-password protection project setting remains open.
- Do not mark Production Ready until the operations checklist gates are evidenced and accepted.

## Follow-up verification (read-only, 2026-10-09)
- `public.admin_set_user_department` also uses the `user.manage OR role.manage` permission gate. This should be reviewed against the intended separation of duties, but it does not mutate the `user_roles` table.
- The live definitions of `admin_set_user_role` and `admin_remove_user_role` still have no explicit audit insert or last-active-admin guard in their function bodies. The earlier trigger query found no user-defined trigger on `user_roles`, so successful assignment changes do not have visible table-trigger audit coverage from that inspection.
- `admin_set_user_department` explicitly inserts a `user_department_changed` audit event.
- These findings are based on live read-only SQL inspection. No function was invoked to change a role and no Production schema/data was changed.
