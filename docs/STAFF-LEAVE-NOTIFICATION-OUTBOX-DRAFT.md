# Staff Leave Notification Outbox — Implementation Draft

Status: design only. This document does not enable delivery, add a worker, create a user-facing notification feed, or authorize Production changes.

## Current state

The schema candidate defines `public.staff_leave_notification_outbox` with unique `event_key`, recipient, event type, safe payload, channel, status, attempt count, next eligible time, sent timestamp, and a sanitized error code. Workflow RPC prototypes insert some in-app outbox rows transactionally. The outbox is private to clients.

**No trusted delivery worker exists yet.** An outbox row means “delivery work was recorded,” not “the recipient was notified.” Do not show a successful notification badge or claim email/push/in-app delivery until a delivery receipt is recorded and queried.

## Required design before implementation

1. **Atomic claim:** use a narrowly granted server-side RPC or equivalent database transaction with `FOR UPDATE SKIP LOCKED`. Claim only due `pending`/`retry` rows; transition to `processing` and record a lease token/expiry. Never select then update in separate unprotected operations.
2. **Lease recovery:** a worker crash must not strand `processing` rows. Expired leases become eligible again under a bounded retry policy.
3. **Idempotency:** `event_key` is stable across retries. The in-app delivery sink must enforce a unique delivery key such as `(recipient_id, event_key)`; email/push providers may not guarantee exactly-once delivery, so document their duplicate semantics.
4. **Recipient authorization:** resolve recipients only from trusted workflow state. Do not accept arbitrary recipient IDs from the browser. Until the school's authorized escalation recipient is verified, blocked-approver requests must not alert a guessed administrator.
5. **Privacy:** in-app content contains event type, a safe label, timestamp, and authenticated deep link only. Never include leave reason, attachment names/content, tokens, or sensitive provider responses in email/push previews or logs.
6. **Retry policy:** classify transient/permanent failures; exponential backoff with a cap and jitter; cap attempts; move exhausted events to `dead_letter`; store only sanitized error codes. Do not retry permanent validation/authorization failures.
7. **Channels:** implement in-app first. Email and Web Push are optional adapters and must not block the leave workflow. Missing provider credentials must produce an explicit disabled-channel outcome, not false success.
8. **Observability:** counters for pending, processing, retry, sent, dead-letter, oldest pending age, and last successful run. Never log secrets or raw payloads.
9. **Access:** service credentials stay server-side; no service-role key in browser bundles. Revoke `PUBLIC`/anon/authenticated execution of worker-only RPCs; grant only to the dedicated worker/service role. Verify effective grants and run security advisors.
10. **Auditability:** delivery attempts and state transitions need a safe, queryable audit trail without modifying the append-only leave decision history.

## Minimum isolated tests

- Two workers cannot claim the same event concurrently.
- Expired processing lease is recovered exactly once.
- Retry increments attempt count and advances `available_at`; capped failures reach `dead_letter`.
- Duplicate `event_key` cannot create duplicate in-app recipient notifications.
- A forged recipient, anon caller, authenticated user, or missing worker credential cannot claim or deliver events.
- Safe payload excludes leave reason and attachment data.
- A successful database state transition and outbox insert commit together; a failed transaction leaves neither half committed.
- Missing email/push configuration cannot be reported as delivered.
- Blocked approver resolution does not notify an unverified escalation recipient.

## Release gate

Before any worker deployment: implement the claim/lease and recipient delivery schema, add the in-app notification table/feed, implement the worker and tests, inspect effective grants/RLS, verify official approval authority and recipient mapping, and pass isolated end-to-end tests. Production remains unchanged until a separate reviewed release and rollback plan is approved.
