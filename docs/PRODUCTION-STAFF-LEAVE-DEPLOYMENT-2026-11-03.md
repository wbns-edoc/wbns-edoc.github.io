# Production deployment record — staff leave backend
Date: 2026-11-03
Project: `wbns-edoc` (`iigzzwyfxxtqbgjawyom`), Singapore
Status: backend foundation deployed; leave feature remains fail-closed pending policy and real-account E2E approval.

## Production migrations applied

| Version | Migration | Purpose |
|---|---|---|
| `20261103070904` | `notifications_least_privilege_grants` | Remove broad anon/public table rights; authenticated can SELECT and update only `read_at`. |
| `20261103070916` | `notifications_realtime_publication` | Add `public.notifications` to `supabase_realtime`. |
| `20261103071019` | `staff_leave_production_schema_and_workflows` | Install staff-leave schema, RPCs, two-stage route, audit/outbox, verified-policy gate, confirmed school rules, and private Storage bucket/policies. |

Production migration ledger: **79 entries** (was 76 before this release).

## Verified Production state after apply

- 8 `public.staff_leave_*` tables exist; all 8 have RLS enabled.
- 5 explicit RLS policies exist on the applicant/approver-readable tables. Internal route config, Director-absence evidence, and notification outbox have RLS enabled and no direct authenticated/anon table grants; access is through guarded RPCs.
- 3 `school_responsibility_*` tables exist with RLS enabled and no direct authenticated/anon SELECT or INSERT grants.
- Private bucket `staff-leave-private` exists with `public=false`, maximum 20 MiB, MIME allowlist PDF/JPEG/PNG.
- Two Storage object policies exist: applicant upload to own draft request and applicant/current approver read.
- `public.notifications` is present in `supabase_realtime`.
- `anon` has no SELECT/INSERT/UPDATE/DELETE on `public.notifications`; authenticated has SELECT and UPDATE only on `read_at`.
- Production project remains `ACTIVE_HEALTHY`.

## Smoke checks

- Before applying the leave bundle, all 17 constituent SQL migrations were rehearsed together in a transaction against the live Production catalog and rolled back successfully.
- After apply, a rollback-only authenticated database smoke test created a draft leave request successfully. The test transaction was rolled back; Production retains zero leave requests from the smoke test.
- A submit attempt in a rollback-only transaction was rejected by `staff_leave_enforce_confirmed_rules` with `leave_policy_not_verified_or_day_count_missing`. This confirms that submission cannot bypass the unapproved school-wide policy gate.
- There is one school-wide policy record in `draft` status and zero approved/calculation-ready policy records.

## Important operational boundary

This release resolves the requested backend existence/configuration gaps. It does **not** mean staff leave is ready for normal use:
- Entitlement calculation and submission remain fail-closed until the school formally approves a complete single school-wide policy and verifies the school calendar, service history, carry-over, and evidence requirements.
- The 30/60-day filing deadline for spouse-childbirth assistance remains unresolved and is not approved for automatic enforcement.
- Real school-account browser upload/download and two-user Realtime delivery/reconnect tests remain outstanding.
- No frontend Pages deployment was performed. Do not invite staff to submit leave requests until those release gates pass.

No existing document data, profile rows, or production user accounts were modified. Only the requested notifications ACL/publication and new leave/responsibility schema, functions, policies, seeds, and private bucket were added.


## Read-only release-gate re-audit — 2026-11-03

A fresh read-only SQL audit after the Integration policy/authority changes confirms:

- Migration ledger remains **79**; the audit performed no writes.
- 8/8 leave tables have RLS enabled; 5 leave-table policies exist. The route-config, Director-absence-evidence, and notification-outbox tables have no direct anon or authenticated SELECT/INSERT/UPDATE/DELETE privileges.
- staff-leave-private remains private, 20 MiB, PDF/JPEG/PNG; two Storage object policies exist.
- public.notifications remains in supabase_realtime. This proves publication membership only, not delivery/reconnect E2E.
- School-wide leave policy remains draft, verification_status=pending, calculation_ready=false; there are no approved school-wide policies.
- **Production still has annual_leave active.** The school-confirmed exclusion is Integration-only and has not been applied to Production.
- school_responsibility_settings.has_vice_director=false, but there are zero Director assignments, zero Vice Director assignments, and no row in staff_leave_approval_route_config; there is no verified approver route.
- Security Advisor still reports 10 RLS-enabled/no-policy tables (INFO), 30 authenticated-callable SECURITY DEFINER functions (WARN), one anon-callable SECURITY DEFINER school-name reader (WARN), and leaked-password protection disabled (WARN). These findings need function-by-function ACL/role tests and an Auth recovery plan; do not mass-revoke privileges.

## Reversible rollout plan (not authorization to deploy)

1. **Preflight / freeze:** keep PR Draft and the leave UI unavailable to staff. Capture a fresh schema/ledger/ACL/Storage/publication snapshot; verify a restorable backup in an isolated free environment and record current frontend deployment ID.
2. **Release candidate validation:** require all 8 PR workflows green on the exact head; run the leave positive/negative regression suite, including sick leave certificate threshold, 15 consecutive working days per childbirth event, inactive legacy annual-leave catalog/RPC denial, route-attestation invalidation, and no-Vice/director-only route.
3. **School sign-off:** obtain and inspect the actual Director appointment/delegation instrument; assign the responsible Director through the authorized settings flow; confirm no Vice Director; have an active System Admin attest using the real document reference. Approver identity or an audit-row ID alone is not authority evidence. Obtain signed approval of the school-wide leave policy and verified calendar/service-history rules before calculation is enabled.
4. **Controlled release:** after separate release approval, apply only reviewed forward migrations in order, verify ledger/effects, then enable the leave UI for a small pilot. Keep the existing e-Document Production identity and data unchanged.
5. **Post-release verification:** test real staff accounts for submit/cancel/approve/reject, private upload/download, RLS denial across users, notifications and two-user Realtime reconnect; monitor errors and confirm zero-baht service operation.

**Rollback/stop rules:** if any migration, ACL, RLS, Storage, route, or E2E check fails, stop before opening the feature and keep submissions fail-closed. Prefer a reviewed forward-fix migration; do not delete migration-ledger rows or drop leave data. If the UI has been opened, disable new submissions and revert the frontend to the prior known-good deployment while preserving existing requests, attachments, and audit history. Restore the database only from the verified backup after assessing post-backup writes and obtaining release-owner approval. Never delete the private bucket or its objects as a rollback shortcut.

**Current decision: NO-GO.** This plan is preparatory only. It does not authorize Production migration changes, authority assignment, feature enablement, PR merge, or Pages deployment.


## Latest verified status — 2026-11-03 (read-only)

- Exact Integration head `b47d6ba3adbcaa235ecd133007e8944cdf89776b`: all eight required PR workflows completed with conclusion `success`.
- Production read-only recheck: project `ACTIVE_HEALTHY`; migration ledger 79; `staff_leave_requests` 0; `staff_leave_approval_route_config` 0; approved/calculation-ready school-wide policy 0; draft policy 1; `annual_leave` remains active; private bucket exists; `public.notifications` remains in `supabase_realtime`.
- The two Integration-only follow-up migrations `20261103130000_school_leave_scope_excludes_annual_leave_draft.sql` and `20261103140000_staff_leave_childbirth_deadline_fail_closed.sql` are not applied to Production. The former disables the annual-leave workflow catalog entry while preserving historical references; the latter removes conflicting 30/60-day deadline values from draft/review policy JSON only.
- Supabase Security Advisor read-only results: 10 RLS-enabled/no-policy tables (INFO), one anon-callable SECURITY DEFINER function and 30 authenticated-callable SECURITY DEFINER functions (WARN), plus leaked-password protection disabled (WARN). Function-level guards and direct table ACLs must be reviewed; do not mass-revoke EXECUTE. Performance Advisor: 27 unindexed foreign keys, 33 unused-index observations, and 7 multiple-permissive-policy observations. No advisor finding was modified in Production.
- No Production write, PR merge, Pages deployment, Auth setting change, or paid resource creation occurred during this recheck. PR #55 remains Draft/open/unmerged. Release disposition remains NO-GO until school policy/calendar and authority evidence, migration/catalog/ACL parity, real-account browser/Realtime E2E, backup/restore, and 0-baht operation are evidenced and separately authorized.
