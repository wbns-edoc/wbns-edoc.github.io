# Staff leave implementation checklist — evidence-driven gate

Status: engineering checklist; no Production changes.

## Verified from current Production catalog
- Existing identity and RBAC tables include `profiles`, `roles`, `user_roles`, `permissions`, `role_permissions`, `departments`, `user_departments`, `user_department_roles`, and `department_role_permissions`.
- Existing notification table: `notifications`; existing audit table: `audit_logs`.
- Existing migrations include document workflow, notification/deadline, audit hardening, department-scoped authorization, and incoming-document operations.
- No leave-management migration appears in the currently returned Production migration list.
- This catalog inventory alone does not prove exact RLS policies, helper-function semantics, role codes, or all grants.

## Blockers before a runnable migration
- [ ] Obtain authoritative read-only definitions for relevant role rows/codes and active status.
- [ ] Inspect definitions of `private.has_permission(text)`, `private.has_department_permission(text, uuid)`, and `private.user_has_department(uuid, uuid)`; verify their execution grants and behavior for authenticated users.
- [ ] Inspect current RLS policies and grants for `profiles`, `notifications`, and `audit_logs`; do not assume these tables can safely store leave events.
- [ ] Confirm the school-wide policy against the applicable official regulations for all staff categories. Do not encode unverified numeric leave entitlements.
- [ ] Identify the actual application source tree and routing before implementing UI; do not guess paths from failed repository lookups.
- [ ] Establish disposable PostgreSQL/Supabase test environment and reproducible migration replay.

## Required implementation acceptance tests
1. Unauthenticated users cannot read or mutate leave records.
2. A staff member can read only their own leave requests and permitted attachment metadata.
3. No direct client mutation can set status, approval actor/time, policy snapshot, audit history, or notification delivery state.
4. An approver can see only the authorized queue and the minimum request detail needed to decide.
5. Self-approval is rejected even if the requester has an approver role.
6. Deputy review precedes director final approval unless a separately authorized director-absence path records actor, timestamp, absence reason, and decision reason.
7. Ordinary cancellation is rejected when the verified Asia/Bangkok cutoff has passed; exception cancellation requires authorization and reason and produces immutable audit history.
8. A single school-wide policy version applies regardless of personnel category; category remains reporting metadata only.
9. Unverified policy rules block automatic day calculation; approved historical snapshots are not rewritten when policy changes.
10. Notification outbox retries are idempotent; previews contain no private reasons or medical details.
11. Dashboard aggregates reconcile with authorized records and clearly label requests, calendar days, working days, and person-days.
12. Migration replay, RLS tests, workflow tests, and build/CI pass in isolation before release review.

## Release decision
NO-GO for Production until all blockers and acceptance tests have evidence. This checklist does not authorize or execute any migration.