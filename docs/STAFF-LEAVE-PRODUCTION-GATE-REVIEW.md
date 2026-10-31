# Staff leave module — Production gate review

Review date: 2026-10-20  
Branch: `feat/staff-leave-management-design`  
Related PR: https://github.com/wbns-edoc/wbns-edoc.github.io/pull/33

## Current verified state
- PR #33 is open and unmerged; it is a documentation/design PR.
- Read-only Supabase catalog inspection shows the current Production public schema has no leave-management tables among the listed tables.
- The recorded Production migration list contains the existing e-document migrations; the leave draft migration has not been applied.
- The branch includes a draft migration `20261020230000_staff_leave_workflow_foundation_draft.sql`. It is not safe to apply as-is.

## Blocking issues before Production
1. **Policy model conflicts with owner's latest decision.** The draft creates leave policy versions keyed by personnel category. The school owner has explicitly confirmed that all staff use one uniform leave policy. Replace the model with one school-wide policy/version; personnel category may be reporting metadata only.
2. **Over-broad approver read policy.** The draft's SELECT policy grants director/deputy role-code users access to all leave requests. Production role codes were not verified, and unrestricted access to sensitive reasons/attachments is not yet justified. Use narrow, reviewed server-side functions and field-level/data-minimization design; do not apply the current policy.
3. **Workflow RPCs are missing.** Submit, deputy review, director final approval, director-absent direct deputy approval, cancellation cutoff enforcement, decision, and audited overdue-return correction need server/database-side authorization and transition guards.
4. **Notifications are not implemented by the draft.** Need an outbox/event table or equivalent, idempotency, recipient authorization, retry state, in-app notification records, and optional delivery adapters.
5. **Dashboard data source is missing.** Need authorized, privacy-aware aggregates with definitions for requests versus days/person-days and an Asia/Bangkok reporting boundary.
6. **Day counting is not implemented.** No verified school-wide policy catalogue with the exact counting basis and exceptions has been encoded. The provided BICT guide is a reference, not proof that any unverified day limit may be guessed. Record source/version/effective date and validate the applicable school-wide policy before enabling calculations.
7. **Tests have not been executed.** Implement and pass database/RLS, workflow, cancellation boundary, shared-policy day-count, notification retry, privacy, and dashboard reconciliation tests in non-production.
8. **Operational rollout is missing.** Need reviewed migration reproducibility, backup/rollback plan, synthetic-account pilot, and explicit release approval.

## Safe next steps
1. Replace the draft schema with a single school-wide policy model and default-deny access until narrowly scoped RPCs are ready.
2. Inspect the real production role/permission catalog read-only and map the confirmed director/deputy authority to existing RBAC without assuming role codes.
3. Implement schema and RPCs in a non-production/test database, not Production.
4. Add notification outbox/dispatch and executive dashboards, then automate the listed tests.
5. Verify policy rules against the source and school-authorized policy, obtain review, and only then propose a separately reviewed Production migration.

## Release decision
**NO-GO for Production at this time.** This is a safety finding, not a claim that the feature is complete. Do not apply the current draft migration to Production. Existing Production data and schema were not changed by this review.
