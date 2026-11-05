# Leave approval route snapshot — implementation gate

**Status: draft / not production-ready. Do not merge or deploy.**

## Confirmed route contract
- Normal route: applicant → Director directly.
- If the Director cannot perform duties, System Admin explicitly designates an active eligible staff account as acting approver for a defined validity period.
- The acting approver is not restricted to Vice Director. System Admin is not automatically an approver.
- Delegation requires start/end timestamps, reason, authority/document reference, creator, audit history, and revocation/expiry.
- New submissions snapshot the active approver and delegation evidence atomically. Existing requests retain their immutable route snapshot.
- No valid Director or acting delegation means submission is blocked (fail closed).

## Required data contract
Each submitted request must contain a server-written, immutable, versioned approval route snapshot including:
- route kind: `director_direct` or `admin_delegated_acting_approver`;
- approver profile ID and role/eligibility facts checked at submission;
- delegation ID, designated-by profile ID, validity start/end, reason, authority reference, and configuration version where delegated;
- snapshot timestamp and schema version.

Snapshot is written only by the SECURITY DEFINER submit RPC in the same transaction as submission and initial notification event. Clients cannot write or alter it.

## Decision RPC contract
- Lock request and authorize against its immutable snapshot, not the current mutable route configuration.
- Verify actor equals the snapshotted approver and remains active/eligible.
- Enforce delegation validity at the legally relevant decision timestamp and reject revoked/expired delegations according to the approved school rule; do not silently reroute.
- Reject self-approval.
- Preserve idempotency; retries must not duplicate action or outbox events.
- Changes to delegation apply to future submissions and must not rewrite an existing snapshot.

## Required isolated SQL regression tests
1. Direct Director submission captures Director-only route.
2. Valid delegation captures the selected non-Director staff approver and delegation evidence.
3. Admin cannot approve unless explicitly designated as acting approver.
4. Non-designated staff, inactive staff, and self-approvers are denied.
5. Expired, not-yet-effective, and revoked delegation cannot authorize new submissions or decisions outside the permitted interval.
6. Overlapping active delegations for the same Director are rejected or resolved by a deterministic, audited rule.
7. Changing/revoking delegation after submission does not silently mutate the request snapshot.
8. Missing/inactive Director and missing valid delegation fail closed.
9. Snapshot cannot be changed by anon/authenticated direct writes.
10. Exact idempotency retries create one action/outbox event.
11. Notification recipients follow the snapshotted route.
12. Clean database replay plus existing RLS, RPC security, cancellation, and notification tests pass.

## Release gate
Do not merge, deploy, or enable submissions until migration order is verified from a clean replay, UI/RLS/RPC and regression coverage are complete, all CI passes, handbook policy/calendar verification is complete, and Production backup/restore and rollback checks pass.
