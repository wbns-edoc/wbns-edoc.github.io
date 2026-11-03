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
