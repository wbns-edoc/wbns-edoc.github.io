# Staff leave module — Production gate review

Review date: 2026-11-02  
Integration branch: `integration/staff-leave-production-readiness-20261030`  
Related PR: https://github.com/wbns-edoc/wbns-edoc.github.io/pull/55  
Disposition: **NO-GO for Production; continue Integration only.**

## Verified state

- PR #55 is Draft, open, and unmerged. Its head is `31d6352e76695dfcd33a864423710446d23ef05d`.
- Eight required CI workflows are reported successful on that exact PR head. CI success is necessary but does not establish Production readiness.
- Wat Bueng Nam Sai Production Supabase project `iigzzwyfxxtqbgjawyom` is `ACTIVE_HEALTHY`.
- A fresh read-only Production probe found 76 migration-ledger entries, zero public `staff_leave%` tables, and zero Storage buckets whose IDs contain `leave`. No Production writes were performed.
- The separate test project `wbns-edoc-test` is currently `INACTIVE`; it is not an available live staging target.
- Integration includes draft migrations/tests for the school-wide leave schema, RPC workflow, two-stage approval, immutable route snapshot, notifications, Director-absence evidence, Realtime publication, notification least-privilege grants, and confirmed rule enforcement.
- The base draft schema creates attachment metadata in `public.staff_leave_attachments`, but no corresponding private Storage bucket or complete verified upload/download flow is evidenced by the current changed-file set.

## Non-negotiable policy decisions

- All personnel at Wat Bueng Nam Sai use one school-wide leave policy. Personnel category is reporting metadata only and must not alter entitlements or calculations.
- Sick leave from 3 working days requires a medical certificate.
- Leave to assist a wife after childbirth is limited to 15 consecutive working days for each childbirth event and cannot be split into multiple periods.
- Normal approval is Vice Director review followed by Director final approval. Direct Vice approval is permitted only while a System Admin-recorded, date-bounded, non-revoked Director-absence evidence record is active.
- Cancellation must be requested at least one day before the leave date.
- Do not infer other entitlements or counting rules where the approved handbook/policy and school calendar do not establish them.

## Release blockers

1. **Production parity and migration reconciliation:** 76 Production ledger entries and Integration migration files still require exact SQL/effect and catalog/ACL/managed-object reconciliation. Name matching alone is not parity. Never replay already-applied historical migrations or use migration repair as a shortcut.
2. **Private evidence storage:** implement a private-only Storage bucket, narrowly scoped Storage object policies, server-verified attachment metadata, and authorized upload/preview/download paths. A metadata row or plausible object key must never count as proof of a medical certificate. No public object URLs.
3. **Policy completeness:** verify the full school-wide handbook implementation, calendar, service history, annual accumulators/carry-over, leave subtypes and event linkage, and evidence/eligibility rules. Keep automatic calculation disabled for unverified rules.
4. **Operational authority:** verify real Director/Vice identities and authority evidence, including the school's process for recording Director absence. Current synthetic fixtures do not configure real approvers.
5. **End-to-end acceptance:** execute browser workflows with school test accounts, including file upload and access denial, submit/cancel/approve/reject, realtime delivery/reconnect, notification fan-out, and role/row-level authorization.
6. **Security and operations:** review Production Advisor findings, Auth recovery/leaked-password protection plan, backup/restore rehearsal, rollback procedure, and billing/hosting evidence confirming 0-baht operation.
7. **Staging availability:** the previously provisioned test project is inactive. Do not reactivate, create, or upgrade a Supabase project without confirming that it remains free; use disposable CI PostgreSQL for what it can prove, while clearly recording the limits of that fixture.

## Required next sequence

1. Complete the private Storage and attachment workflow in Integration, with deny-by-default tests for cross-user and cross-request access.
2. Complete and review every handbook rule and school-calendar dependency; preserve the school-wide policy model.
3. Run isolated database replay, RLS/RPC tests, frontend build, and browser E2E using non-production identities.
4. Reconcile the full Production catalog and migration history read-only; prepare a separately reviewed, additive release migration only after parity is established.
5. Rehearse backup and rollback and verify every hosting/service cost is zero.
6. Only after every gate is evidenced should a production release be proposed. Production changes require a separate explicit release authorization.

## Production safety statement

No Production migration, migration repair, schema/data write, Storage bucket creation, Edge Function deployment, PR merge, or GitHub Pages deployment is authorized by this review. Preserve the existing Wat Bueng Nam Sai Production identity and data. No shared database with other schools. Keep PR #55 Draft until all blockers above are closed.
