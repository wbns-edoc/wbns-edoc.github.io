# Leave approval route snapshot — implementation gate

**Status: draft / not production-ready. Do not merge or deploy.**

## Defect being closed

The current `staff_leave_submit` resolves an approver from the singleton route configuration, while `staff_leave_decide` resolves authority again from that live configuration. Updating responsibility settings after a request is submitted can therefore change the authority used for an in-flight request. Current CI coverage does not prove immutable routing.

## Required data contract

Each successfully submitted request must carry an immutable snapshot written in the same transaction as the submission and initial outbox event. At minimum:

- `approval_route_snapshot` JSONB with a versioned schema;
- route kind: `vice_director_then_director` or `director_only_confirmed_no_vice`;
- verified Vice Director profile ID (null only for the confirmed no-Vice route);
- verified Director profile ID;
- authority reference and configuration version / verification timestamp;
- snapshot creation timestamp.

The stored snapshot must not be client-writable. It is populated only by the SECURITY DEFINER submit RPC after checking the configured approver accounts are active and the authority configuration is verified. The request and its snapshot must be committed atomically.

## Decision RPC contract

`staff_leave_decide` must lock the request and authorize the actor against the request's snapshot and current stage, not against the current singleton configuration. Keep the fail-closed active-profile check for the actor. The snapshot's named approver must still be active when acting; if an assigned approver becomes inactive, fail closed and require an explicitly audited administrative resolution rather than silently rerouting the existing request.

- Vice Director route: Vice Director can advance only from `vice_director_review`; Director alone can approve/reject at `director_final_review`.
- Confirmed no-Vice route: Director alone can approve/reject at `director_final_review`.
- A change to route configuration affects new submissions only.
- Idempotent retries must preserve current semantics and must not duplicate action-history rows or notification-outbox events.
- Notification recipients for stage transitions come from the request snapshot.

## Required isolated SQL regression tests

1. Submit request A under Vice A + Director A; change singleton configuration to Vice B + Director B; assert A still routes to A's original approver and only that original approver can act.
2. Submit request B after the configuration change; assert B captures and uses the new route.
3. Confirmed no-Vice submission captures a null Vice ID and Director-only route; Director can decide; unrelated users and stale Vice identities cannot.
4. Inactive configured/snapshotted approver fails closed without changing request stage or adding misleading notification events.
5. Missing/unverified config and inactive Director block submission.
6. Snapshot cannot be changed by `anon` or `authenticated` direct table writes; only the narrow RPC can set it.
7. Re-run exact idempotency retry tests and verify exactly one action/outbox event per key.
8. Verify recipient IDs for initial submission, stage advancement, final approval/rejection, and cancellation are consistent with the immutable request route.
9. Verify schema replay from a clean local database and run the existing RLS, RPC-security, cancellation, and no-Vice tests.

## Release gate

Do not merge or apply to Production until the migration order is verified from a clean replay, all required CI checks pass, the school handbook has been reattached and its day-count/entitlement rules separately approved, and the user explicitly approves the Production change. Do not guess leave limits from generic public guidance: the school's supplied handbook is the governing input for this implementation.
