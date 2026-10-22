# Staff leave implementation checklist — evidence-driven gate

Status: engineering checklist; no Production changes.

## Current verified state
- The actual frontend entry point is `src/main.tsx`; it currently has no staff-leave page or route.
- The repository has no dedicated leave-management implementation or automated leave workflow tests on the inspected branch.
- Existing identity/RBAC tables include `profiles`, `roles`, `user_roles`, `permissions`, `role_permissions`, `departments`, `user_departments`, `user_department_roles`, and `department_role_permissions`.
- Existing notification and audit tables are `notifications` and `audit_logs`; their suitability for private leave data and reliable delivery has not been established.
- No leave-management migration appears in the Production migration inventory previously inspected.
- The existing migration draft is unsafe to apply as-is: policy is keyed by personnel category and approver reads are overly broad.
- No CI run is associated with the current design-only PR head; no build or test pass is claimed.

## Blockers before implementing a runnable feature
- [ ] Obtain authoritative read-only definitions for role codes, active state, role assignments, RLS, grants, and authorization helper functions.
- [ ] Verify the applicable official approval authority for every personnel category and any school-level delegation. The Deputy Director position is currently vacant; never route to a vacant role or grant the role to someone by implication.
- [ ] Until approval authority is verified, direct-to-Director approval must remain disabled. If no authorized approver resolves, preserve the request in a visible blocked state and alert an authorized administrator without granting approval rights.
- [ ] Confirm the school-wide uniform-policy requirement against applicable official rules. Personnel category is reporting metadata only and must not select entitlements.
- [ ] Establish an isolated, reproducible PostgreSQL/Supabase test environment. Do not apply the draft migration to Production or use Production as a test environment.
- [ ] Design additive schema and narrow server/database transition functions, with default-deny writes and append-only action history.
- [ ] Implement the UI in the verified application entry/routing structure only after backend contracts and access scopes are agreed.
- [ ] Add notification outbox with idempotency and safe payloads; inspect existing notification semantics before reuse.
- [ ] Define day-counting, holidays, partial days, cancellation cutoff, policy snapshots, and dashboard metrics from verified school-approved rules.

## Required implementation acceptance tests
1. Unauthenticated users cannot read or mutate leave records.
2. A staff member can read only their own request and authorized attachment metadata.
3. Direct client writes cannot set status, approval actor/time, policy snapshot, audit history, or delivery state.
4. An approver can see only requests assigned to a verified authority and only the minimum detail needed.
5. Self-approval is rejected even when the requester also has an approver role.
6. The vacant Deputy Director role never receives a task; no silent substitution or implicit role grant occurs.
7. Direct-to-Director routing remains disabled until the applicable authority and delegation are documented and reviewed.
8. If no authorized approver resolves, the request remains visible in a blocked state and is not dropped or silently approved.
9. Ordinary cancellation is rejected after the verified Asia/Bangkok cutoff; any exception requires explicit authority, reason, and immutable audit history.
10. One approved school-wide policy version applies regardless of personnel category; unverified entitlements and automatic calculations remain disabled.
11. Policy changes do not rewrite historical request snapshots.
12. Notification retries are idempotent and previews exclude private reasons and medical details.
13. Dashboard aggregates reconcile with authorized records and distinguish request counts, calendar days, working days, and person-days.
14. Clean migration replay, RLS/workflow tests, build, CI, isolated synthetic-account pilot, and rollback review all pass before release.

## Release decision
**NO-GO for Production** until every blocker and acceptance test has evidence, applicable approval authority is verified, and release is explicitly approved. This checklist does not authorize or execute any migration.
