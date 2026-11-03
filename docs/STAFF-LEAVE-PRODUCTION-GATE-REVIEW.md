# Staff leave module — Production gate review

Review date: 2026-11-02  
Integration branch: `integration/staff-leave-production-readiness-20261030`  
Related PR: https://github.com/wbns-edoc/wbns-edoc.github.io/pull/55  
Disposition: **NO-GO for Production; continue Integration only.**

## Verified state

- PR #55 is Draft, open, and unmerged. Its head was refreshed on 2026-11-03 by the CI evidence update; the documentation-only follow-up commit is `706ca4d7e13a65c7fc489ea94c49bbfa15abe181`.
- Eight required CI workflows are reported successful on that exact PR head. CI success is necessary but does not establish Production readiness.
- Wat Bueng Nam Sai Production Supabase project `iigzzwyfxxtqbgjawyom` is `ACTIVE_HEALTHY`.
- A fresh read-only Production probe found 76 migration-ledger entries, zero public `staff_leave%` tables, and zero Storage buckets whose IDs contain `leave`. No Production writes were performed.
- The separate test project `wbns-edoc-test` is currently `INACTIVE`; it is not an available live staging target.
- Integration includes draft migrations/tests for the school-wide leave schema, RPC workflow, two-stage approval, immutable route snapshot, notifications, Director-absence evidence, Realtime publication, notification least-privilege grants, and confirmed rule enforcement.
- The Integration branch now includes draft migration `20261102130000_staff_leave_private_storage_draft.sql`, a private `staff-leave-private` bucket (20 MiB; PDF/JPEG/PNG), request-owner/current-approver object policies, a server-side attachment-registration RPC, a browser upload/temporary-Signed-URL UI, and isolated SQL/Local Supabase tests. These additions are awaiting CI results and are not yet accepted as release-ready or applied to Production.

## Non-negotiable policy decisions

- All personnel at Wat Bueng Nam Sai use one school-wide leave policy. Personnel category is reporting metadata only and must not alter entitlements or calculations.
- Sick leave from 3 working days requires a medical certificate.
- Leave to assist a wife after childbirth is limited to 15 consecutive working days for each childbirth event and cannot be split into multiple periods.
- Normal approval is Vice Director review followed by Director final approval. Direct Vice approval is permitted only while a System Admin-recorded, date-bounded, non-revoked Director-absence evidence record is active.
- Cancellation must be requested at least one day before the leave date.
- Do not infer other entitlements or counting rules where the approved handbook/policy and school calendar do not establish them.

## Release blockers

1. **Production parity and migration reconciliation:** 76 Production ledger entries and Integration migration files still require exact SQL/effect and catalog/ACL/managed-object reconciliation. Name matching alone is not parity. Never replay already-applied historical migrations or use migration repair as a shortcut.
2. **Private evidence storage:** the first Integration implementation is now present and CI is running. Review the private bucket policy, owner/current-approver isolation, object metadata registration, browser upload, and 60-second signed download path. Confirm no public object URLs, orphan cleanup behavior, file-content validation limits, and medical-certificate enforcement before release. A client-supplied MIME type/metadata is not proof that a document is authentic or medically valid.
3. **Policy completeness:** verify the full school-wide handbook implementation, calendar, service history, annual accumulators/carry-over, leave subtypes and event linkage, and evidence/eligibility rules. Keep automatic calculation disabled for unverified rules.
4. **Operational authority:** verify real Director/Vice identities and authority evidence, including the school's process for recording Director absence. Current synthetic fixtures do not configure real approvers.
5. **End-to-end acceptance:** execute browser workflows with school test accounts, including file upload and access denial, submit/cancel/approve/reject, realtime delivery/reconnect, notification fan-out, and role/row-level authorization.
6. **Security and operations:** review Production Advisor findings, Auth recovery/leaked-password protection plan, backup/restore rehearsal, rollback procedure, and billing/hosting evidence confirming 0-baht operation.
7. **Staging availability:** the previously provisioned test project is inactive. Do not reactivate, create, or upgrade a Supabase project without confirming that it remains free; use disposable CI PostgreSQL for what it can prove, while clearly recording the limits of that fixture.

## Required next sequence

1. Complete CI and security review for the new private Storage and attachment workflow in Integration; fix every failure and add cross-user/cross-request and invalid-object tests.
2. Complete and review every handbook rule and school-calendar dependency; preserve the school-wide policy model.
3. Run isolated database replay, RLS/RPC tests, frontend build, and browser E2E using non-production identities.
4. Reconcile the full Production catalog and migration history read-only; prepare a separately reviewed, additive release migration only after parity is established.
5. Rehearse backup and rollback and verify every hosting/service cost is zero.
6. Only after every gate is evidenced should a production release be proposed. Production changes require a separate explicit release authorization.

## Production safety statement

No Production migration, migration repair, schema/data write, Storage bucket creation, Edge Function deployment, PR merge, or GitHub Pages deployment is authorized by this review. Preserve the existing Wat Bueng Nam Sai Production identity and data. No shared database with other schools. Keep PR #55 Draft until all blockers above are closed.


## 2026-11-02 private Storage Integration follow-up

- Added `20261102130000_staff_leave_private_storage_draft.sql`: private-only bucket `staff-leave-private`, 20 MiB maximum, PDF/JPEG/PNG allowlist, draft-owner upload policy, applicant/current-approver read policy, and `staff_leave_register_private_attachment` which validates the real Storage object row and metadata before recording a verified attachment row.
- Added `tests/leave-private-storage.test.sql` and `tests/staff-leave-storage-bootstrap.sql`; wired both the disposable PostgreSQL RLS workflow and Local Supabase replay workflow to apply and test the migration.
- Added the browser-side upload and temporary 60-second signed-open flow to `StaffLeave`. The UI permits adding files only to the applicant's draft request and does not create public URLs.
- CI runs were triggered on code commit `8ac8b50dc011439a9aec4809222d90039bc51c7d`; results must be reviewed before this work is considered passed. The test Supabase project remains inactive, so no live staging deployment was performed.
- MIME/size metadata is validated, but this does not establish file-content authenticity or prove that a medical certificate is genuine. The feature must not claim such verification.
- No Production changes, PR merge, or GitHub Pages deployment were made.


## 2026-11-03 CI and release-gate refresh

- Integration commit `e50d63378e3b40dc3449c8168966a727d5f3b896` completed all eight required PR workflows successfully: Frontend Build, Staff Leave Schema RLS, Schema Recovery PostgreSQL Replay, Drive Upload, School Responsibility Settings, Supabase Snapshot and Staff Leave Replay, Recovered Catalog Fixture, and Workflow RPC Security.
- The CI run proves the configured automated checks on the Integration fixture; it does not prove real-account browser acceptance, live notification delivery, school calendar correctness, policy approval, Production migration parity, backup/restore, or zero-cost service operation.
- Production remains read-only. The last verified Production probe found the project active/healthy with 76 migration-ledger entries and no staff-leave tables or private leave bucket. No Production migration, Storage write, Edge Function deployment, PR merge, or Pages deployment was performed.
- The test Supabase project was last reported inactive. No project reactivation, project creation, or paid upgrade was attempted.
- Release disposition remains **NO-GO** until the blockers in this review are evidenced and separately authorized. PR #55 remains Draft and unmerged.


## 2026-11-03 follow-up — verified current PR head and CI

- Current PR #55 head at time of review: `6c0800535d28e57e315df51d72ce8b75608928b7` (documentation follow-up commit). PR remains open, Draft, unmerged; base main SHA `f88b165e5f8c4ef3c564389d003f4029122c3eb5`.
- Re-fetched the eight PR-triggered workflow runs associated with this exact head and inspected each run's jobs. **All 8/8 workflows and all reported jobs completed with conclusion `success`**:
  1. Schema Recovery PostgreSQL Replay
  2. Frontend Build CI
  3. Staff Leave Schema RLS CI
  4. School Responsibility Settings CI
  5. Drive Upload CI
  6. Supabase Snapshot and Staff Leave Replay CI
  7. Workflow RPC Security CI
  8. Recovered Catalog Fixture CI (both jobs successful)
- The Supabase Snapshot and Staff Leave Replay workflow includes a successful step asserting that `notifications` is in the Realtime publication. Staff Leave Schema RLS CI also passed.
- Read-only Supabase project lookup still reports Production `ACTIVE_HEALTHY` on PostgreSQL 17.11.0.003 in Singapore. Migration listing confirms exactly 76 applied entries; newest listed version is `20261030094941` (`require_active_department_for_scoped_permissions`). The staff-leave migrations remain Integration-only and have not been applied to Production.
- The official BICT/MOE handbook PDF remains the source already supplied by the school. The handbook extraction and policy register identify unresolved prerequisites: the source scope is civil servants while the school wants one school-wide rule for all personnel; a competent school authority must approve that internal policy application, current regulations must be checked, and the school calendar/service history/accumulators/one-time entitlements must be verified. The BICT PDF endpoint timed out during this follow-up fetch; the already-recorded extraction was not silently treated as a new verification.
- Realtime publication assertion passing in disposable/local CI proves the draft migration behavior on the test fixture only. Production publication remains unchanged and still has no published `public.notifications` table.
- Release decision remains **NO-GO**. CI 8/8 is closed as a gate; the following are not: exact migration/catalog/ACL parity, real authenticated multi-role and two-user Realtime E2E, real school approver identity/authority, handbook/current-regulation and calendar sign-off, browser E2E for leave and private attachments, backup/restore/rollback rehearsal, and auditable zero-baht cost verification.
- No Production DDL/DML, migration repair, Storage bucket creation, publication/grant/Auth change, Edge Function deployment, PR merge, or Pages deployment was performed.


## 2026-11-03 urgent follow-up — no-policy ACL regression and source cross-check

- Refreshed Production migration/catalog/ACL inventory on 2026-11-03: 76 migration-ledger entries; 88 Integration migration files; 47 normalized filename/name matches; 29 Production ledger names without exact normalized suffix match; 41 repository migration files without an exact Production history name. Name matches are not SQL-equivalence proof.
- Read-only Production catalog: 27/27 public tables have RLS enabled; 50 policies; four RLS-enabled tables intentionally have no policies; 19 public SECURITY DEFINER functions, all with fixed search_path. The four closed tables remain `department_role_permissions`, `system_settings`, `user_department_roles`, and `user_departments`.
- Added `tests/production-no-policy-table-acl.test.sql` and wired it into Schema Recovery PostgreSQL Replay CI. The new test passed on code-bearing commit `01eec2a1ee5f2bf184382d0f2e9ea03a43195ba9`, verifying the four-table no-policy boundary and the live authenticated SELECT grant shape in a rollback-protected disposable fixture. The fixture adds minimal shells for later objects absent from the October 15 catalog; this test is explicitly an ACL/RLS behavior guard, not historical schema parity.
- Re-ran all eight required PR workflows on code-bearing commit `01eec2a1ee5f2bf184382d0f2e9ea03a43195ba9`; all 8/8 completed successfully, including the new no-policy ACL guard. The subsequent commit `3b6f5e523d96069c84b63dda50a7d7d3935d8178` changes only the policy verification documentation; no code changed after the green CI head.
- Rechecked official OTEPC circular ว14/2568: registry marks it active and says circular 42/2555 is repealed. It addresses approval authority for teacher civil servants/educational personnel and does not resolve the school's requested extension of one policy to every contract/personnel category. The policy register now records this distinction and keeps entitlement calculation fail-closed pending school authority approval.
- PR #55 remains Draft/unmerged. Production remains untouched: no staff-leave tables, no private leave bucket, and no notifications publication. No migration, ACL, Auth, Storage, Realtime, Edge Function, Pages, or billing-setting changes were made.

### Current disposition

CI 8/8 is closed for the code-bearing Integration head. Remaining non-CI gates are still material: original Foundation source and 29 Production history names remain unreconciled; real authenticated school-account and two-user Realtime/browser E2E are not available in the inactive test project; school authority must approve school-wide leave-policy scope and resolve the spouse-childbirth application deadline; school calendar/service history/one-time entitlement evidence, real approver authority, backup/restore/rollback, and auditable zero-baht operation remain unverified. Keep automatic leave calculation and Production release disabled.
