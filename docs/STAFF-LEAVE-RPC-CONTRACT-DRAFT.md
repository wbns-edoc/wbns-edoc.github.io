# Staff Leave RPC Contract Draft

Status: design contract only. This document does not implement functions and does not authorize a Production migration.

## Security invariants

1. Derive the actor exclusively from auth.uid(); never accept an actor ID from browser input.
2. Require an authenticated, active public.profiles row for every workflow operation.
3. Deny by default. A role name, profile field, client-supplied route, or personnel category is not by itself proof of authority.
4. Reject self-approval even when the requester also has an approver role.
5. Every successful state transition updates the request, appends one immutable action, and inserts notification outbox events in one database transaction.
6. Repeated requests must be idempotent where a request/event key is supplied. Unique conflicts must not duplicate action/outbox events.
7. Do not allow clients to write directly to workflow tables. Expose only reviewed RPCs with narrowly scoped EXECUTE grants.
8. Never expose outbox contents to authenticated clients. A trusted worker processes outbox rows using server-side credentials and bounded retries.
9. Do not use personnel category as an entitlement or approval-routing rule. It is historical/reporting metadata only.
10. Store minimal safe notification payloads. Never place the leave reason, attachments, or other sensitive details in push/email preview payloads.

## Proposed RPC surface

All functions are proposals. Names/signatures may change after review against the actual application and Supabase migration conventions.

### staff_leave_create_draft(p_leave_type_id uuid, p_starts_on date, p_ends_on date, p_reason text)

- Actor: active authenticated staff member.
- Validate active leave type, nonblank bounded reason, date ordering, and school timezone assumptions.
- Do not accept applicant ID, personnel category, day count, policy version, status, or approver from the client.
- Capture the currently applicable approved school-wide policy version and an immutable policy snapshot on submission, not from client-supplied JSON.
- Do not calculate final day count until the approved policy's working-day/holiday rules have been verified and implemented.

### staff_leave_submit(p_request_id uuid, p_idempotency_key text)

- Only the applicant may submit their own draft.
- Lock the request row with FOR UPDATE and validate current state before transition.
- Resolve approver using a server-controlled authority/delegation configuration.
- The Deputy Director position may exist as a role but must not be assumed occupied. Never assign an inactive, vacant, or unverified approver.
- If no lawful approver can be resolved, transition to blocked_approver_resolution and append a blocked action. Enqueue an alert only after an explicitly authorized administrator recipient mapping is verified; until then, do not guess a recipient or claim that an alert was delivered. Do not silently route to Director without verified authority.
- On successful route, set submitted_at, state, and current approver; append submitted and routed actions as applicable; enqueue idempotent submitted and approver_assigned notifications.
- Enforce a unique event key based on request, transition, recipient, and channel or equivalent deterministic deduplication scheme.

### staff_leave_decide(p_request_id uuid, p_decision text, p_reason text, p_idempotency_key text)

- Only the active, explicitly assigned current approver may decide; reject any decision other than the approved enum (approve, reject, or an explicitly supported return).
- Reject if actor equals applicant.
- Lock the request row and re-check current state and assignment inside the transaction.
- Require a reason for rejection/return according to the approved school policy.
- Update status and timestamps; append immutable action; enqueue applicant notification in the same transaction.
- Do not permit a browser-supplied role, authority flag, approver ID, or arbitrary next state.

### staff_leave_cancel(p_request_id uuid, p_reason text, p_exception_authority text, p_idempotency_key text)

- Applicant may cancel only their own request and only within the verified cancellation rules.
- Default cutoff: at least one calendar day before leave starts, evaluated in Asia/Bangkok; the precise comparison must be unit-tested at midnight boundaries.
- Late cancellation requires a separately verified authority check, a nonblank reason, and an audit event. A caller-supplied string is not evidence of authority.
- Lock and re-check request state before changing it; append action and enqueue notifications transactionally.

### staff_leave_get_my_summary(p_from date, p_to date)

- Read-only server-side aggregate limited to the active actor's own requests by default.
- If management dashboards are required, implement a separate RPC with a separately reviewed authorization predicate and a documented minimum-data result.
- Clearly distinguish request count, calendar days, working days, and person-days. Do not label one measure as another.
- Apply date-range limits and do not return sensitive leave reasons or attachment data in aggregate results.

## Policy versioning and day counting

- Policy versions are school-wide and must be reviewed/approved by an explicitly authorized role before use.
- Never invent entitlement limits, holidays, or day-count rules. Load only from verified official policy and school-approved interpretation.
- A submitted request records the policy version and relevant rules snapshot used at the time of submission.
- Changes to future policy versions must not rewrite historical request snapshots.
- Tests must cover weekends, official holidays, partial days if supported, cross-year ranges, invalid ranges, and effective-date boundaries using Asia/Bangkok.

## Notifications and transactional outbox

- Insert outbox rows in the same transaction as the state change.
- Use deterministic unique event_key values to prevent duplicate notifications on retries.
- A trusted worker must claim rows safely, increment attempts, back off transient failures, and move permanently failing items to dead_letter.
- Persist sanitized error codes only; never store secrets or full sensitive provider responses.
- In-app notification delivery must be recipient-scoped. Email/push are optional channels and must not block the core workflow.
- Notifications should state that an action occurred and provide a secure in-app link; avoid leave reasons and sensitive attachments in previews.

## EXECUTE grants and function hardening

Before enabling any RPC:
- Use SECURITY DEFINER only when necessary; prefer invoker rights when practical.
- If SECURITY DEFINER is required, set a fixed safe search_path, schema-qualify objects, revoke default PUBLIC execute, and grant EXECUTE only to authenticated or the dedicated worker role as appropriate.
- Derive identity via auth.uid() and test behavior for missing/invalid identity.
- Ensure direct table writes remain denied for anon and authenticated.
- Confirm trigger-enforced append-only history remains effective for the actual function owner and worker paths.
- Add negative tests for inactive actors, missing assignments, stale state, forged actor IDs, self-approval, duplicate idempotency keys, and unauthorized late cancellation.

## Release gates

Do not merge this design into a production release or apply the draft migration until all of the following are true:

1. Official approval authority and school delegation are verified, including the current vacant Deputy Director position.
2. RPC implementations, grants, and transactional outbox worker are reviewed.
3. Isolated PostgreSQL migration replay, RLS, effective-privilege, and RPC security tests pass on the exact candidate commit.
4. Application UI integration, attachment access, and notification flows are tested end-to-end.
5. A rollback plan and a separately approved Production change window exist.

Current status: contract plus draft-only RPC prototypes in the separate leave-schema branch; this document itself adds no functions. Submission currently fails closed when approver authority is unverified, and administrator alert delivery is intentionally deferred until a verified recipient mapping exists. No Production migration applied, and no Production data or permissions changed.
