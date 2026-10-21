# Staff leave secure schema draft

Status: **draft only — not deployed and not Production-ready**.

The proposed additive schema must be reviewed and tested in an isolated database before any deployment.

## Security decisions

- Leave policy versions must be school-wide and must not be keyed by personnel category.
- Personnel category is historical/reporting metadata only.
- Every new table must enable RLS.
- Authenticated reads must be limited to active leave types, approved policy versions, the applicant or explicitly assigned current approver, and authorized parties to request history/attachment metadata.
- Browser clients must not directly insert, update, or delete workflow records.
- Notification outbox delivery state and internal payloads must not be readable by browser clients.
- Approval history must be append-only and written atomically with each state transition. The draft schema now blocks `UPDATE`, `DELETE`, and `TRUNCATE` of action history with database triggers; RPC integration must still insert actions atomically with state changes.

## Required before considering merge/release

1. Add narrow RPCs for draft creation/editing, submission, approver resolution, approve/reject/return, cancellation and authorized exception handling.
2. Every RPC must derive actor identity from `auth.uid()`, check active profile and server-side authority, prevent self-approval, validate state transitions, and write action history and outbox rows atomically.
3. Never accept an authority boolean, actor ID, status, policy snapshot, approver ID, audit row, or notification delivery state from the browser as authoritative input.
4. Establish the approved routing/delegation rule from the applicable official circular and school-level documentation. Deputy Director vacancy must create a visible blocked state and alert an authorized administrator; it must not implicitly grant or substitute a role.
5. Implement an outbox worker with idempotent delivery, bounded retries, dead-letter visibility, and safe notification previews.
6. Add isolated Supabase/Postgres migration replay and RLS tests for unauthenticated, applicant, unrelated staff, assigned approver, self-approval, disabled profile, and service role.
7. Confirm storage bucket privacy, file size/type rules, signed URL handling, retention and access checks.
8. Add policy-effective-date and day-counting tests based on an approved, versioned school policy; do not infer legal entitlements.
9. Verify existing grants/default privileges and authorization helpers before integrating the frontend.
10. Do not apply any candidate migration to Production until all tests, rollback review, and explicit release approval are complete.

## Known limitations

A schema draft alone does not implement workflow transitions, notification delivery, dashboard aggregates, attachment upload/download, holiday/partial-day calculation, or official approver resolution. RLS is necessary but not sufficient for a live feature. No Production data/schema was changed while authoring this document.
