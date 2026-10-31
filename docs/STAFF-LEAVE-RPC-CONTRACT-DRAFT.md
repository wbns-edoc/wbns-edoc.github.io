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

## Required approval state machine — implementation blocker

The school's stated normal workflow is Vice Director review first, then Director final approval. The current prototype is not sufficient: `staff_leave_decide` currently changes `pending_approval` directly to `approved` when any explicitly assigned current approver approves. Do not treat that as a valid implementation of the two-stage workflow.

The future server-side state machine must represent the approval stage explicitly (for example, a stage field or a constrained route state), not infer it from UI labels:

1. Submission resolves to an active, verified Vice Director approver and enters the first review stage. If the position is vacant or authority cannot be verified, fail closed and keep the request blocked.
2. A valid Vice Director approval records an immutable action, advances the request to the Director final-review stage, assigns the verified active Director, and enqueues an idempotent notification to the next approver and applicant as appropriate. It must not mark the request finally approved.
3. A valid Director approval at the final stage marks the request `approved` and records the final decision. A Director action at the wrong stage must be denied.
4. Rejection follows the verified policy, records the required reason, and ends the request. If returning a request is supported, it must be a distinct explicitly tested transition.
5. The “Director absent; Vice Director may approve directly” exception is disabled until the applicable authority/delegation is verified. The exception must be recorded in a trusted server-side configuration or authorized audit event; a client-supplied flag or free-text reason is not proof of authority.
6. Every transition locks the request row, checks actor identity/active status/current assignment/stage and request status in the same transaction, appends exactly one immutable action, and creates deterministic idempotent outbox events.
7. The school currently has no Vice Director in post. Do not assign to a vacant role, auto-route to Director, or enable direct approval merely to make the workflow usable.

Minimum regression tests before enabling routing:
- Vice Director approval advances to Director review and does not set final status to `approved`.
- Director approval completes only a request currently in the Director stage.
- An attempt by the Director to skip the first stage is denied absent the separately verified exception.
- Direct-to-Vice final approval is denied unless the Director-absent authority is configured and audited.
- Vacant, inactive, unrelated, self, stale-stage, and unassigned actors are denied.
- Replaying the same idempotency key and same payload adds no duplicate action/outbox event; reusing the key with a different payload is rejected.
- Applicant, first approver, final approver, and unrelated staff see only the records allowed by the reviewed RLS contract.

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

### Draft implementation: staff_leave_decide(p_request_id uuid, p_decision text, p_reason text, p_idempotency_key text)

A draft-only SQL prototype now exists at `supabase/migrations/20261021180000_staff_leave_decide_rpc_draft.sql`.

- Accepts only `approve` or `reject`; rejection requires a nonblank reason.
- Requires an active actor from `auth.uid()`, locks the request row, and verifies the actor is the explicitly assigned current approver.
- Rejects self-approval, unassigned actors, and stale/non-pending requests.
- Updates the request, appends an immutable action, and enqueues one minimal in-app notification in the same transaction.
- Retries with the same key and same decision return the existing result without duplicating the action/outbox event.
- Important: the current prototype immediately marks an approved decision as final. It does not implement the required Vice Director → Director stages and must not be used as the production workflow until replaced and tested against the state machine above.
- This function does not establish that the assignment itself is legally authorized. Routing and the vacant Deputy Director / Director delegation must be verified before real use.

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

Current status: contract plus draft-only create, cancel, submit, and decision RPC prototypes in the separate leave-schema branch. Submission currently fails closed when approver authority is unverified; decision requires an explicitly assigned approver but currently skips the required two-stage approval transition. Administrator alert delivery is intentionally deferred until a verified recipient mapping exists. These prototypes are not yet integrated into the application UI or notification worker. No Production migration applied, and no Production data or permissions changed.
