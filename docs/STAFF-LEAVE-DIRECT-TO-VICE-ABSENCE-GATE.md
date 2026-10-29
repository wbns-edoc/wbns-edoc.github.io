# Staff leave direct-to-Vice approval: fail-closed design gate

Status: design requirement only. This document does not authorize Production changes or enable direct approval.

## Why this gate exists

The current draft route configuration has a trusted `direct_to_vice_enabled` boolean. A boolean says that a route is configured, but does not by itself establish that the Director is absent for a particular leave request. Do not treat the flag alone as evidence of absence.

## Required behavior before implementation can be approved

1. Default behavior remains Deputy Director review followed by Director final approval.
2. Direct-to-Vice final approval is allowed only when a trusted, auditable absence record applies to the specific request and relevant decision time.
3. The absence record must identify the Director, the applicable time interval or request, who recorded/verified it, when it was recorded, and a non-empty reason/reference. The recorder must be authorized by a server-side rule; ordinary staff must not be able to set or alter the record.
4. The decision RPC must verify the absence record server-side in the same transaction as the approval, not rely on client input or a client-readable flag.
5. The audit log must capture that the exceptional route was used and reference the absence record. The notification must avoid exposing unnecessary sensitive leave details.
6. If the absence record is missing, expired, unverified, inconsistent with the configured Director, or unauthorized, the RPC must fail closed and leave the request unchanged.
7. Keep the exception disabled until the school confirms who is authorized to record/verify the Director's absence and what authoritative record is acceptable.

## Required isolated tests

- No absence record: Vice cannot final-approve; request and audit history remain unchanged.
- Unverified absence record: denied.
- Absence record for another Director or outside the relevant interval: denied.
- Unauthorized actor attempts to create/update an absence record: denied.
- Valid verified record for the configured Director: Vice can final-approve only the assigned request.
- Exact retry with the same idempotency key: one approval action and one notification event.
- Reusing the key with a different payload: denied.
- Director route remains two-stage by default when no qualifying absence record exists.
- Missing/inactive configured approver or invalid authority configuration: denied.
- All tests run only in an isolated disposable database.

## Release gate

Do not merge this design into Production or apply any migration until the trusted absence-recording authority and evidence source are confirmed, the implementation and tests pass in isolation, complete core-schema replay/parity is resolved, the shared handbook's day-counting/cancellation rules are verified, UI/notification integration is tested, and a rollback plan is reviewed. The Production document-office system must remain unchanged and the project must stay within the zero-baht constraint.
