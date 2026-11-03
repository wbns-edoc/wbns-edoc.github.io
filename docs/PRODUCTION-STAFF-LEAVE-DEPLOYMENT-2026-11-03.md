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
