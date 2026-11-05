# Staff Leave Notification Outbox — Implementation Draft

Status: **isolated Integration draft; not Production-enabled**. The current candidate implements synchronous in-app delivery through a PostgreSQL trigger. It does not implement a background worker, email, Web Push, or guaranteed delivery outside the transaction.

## Current implementation candidate

- Workflow RPC prototypes insert private outbox rows transactionally.
- `staff_leave_deliver_in_app_notification()` is an AFTER INSERT trigger for `channel='in_app'`.
- The trigger writes a minimal, non-sensitive row to `public.notifications` and marks the outbox row `sent` in the same database transaction.
- A failed trigger aborts the originating transaction; this candidate therefore provides atomic database delivery, not asynchronous retry.
- Unique `event_key` prevents duplicate outbox events. The regression test verifies that re-inserting the same event key does not create a second notification.
- The notification feed is intended to be recipient-scoped by RLS. Authenticated clients should have SELECT and column-only UPDATE(read_at); they must not directly INSERT, DELETE, or update notification content.
- Notification Realtime publication and least-privilege grants remain draft-only migrations. They have passed isolated CI on commit `bc0e0b861c10ca632c92eb852f28c8938679bf3e`; this is not evidence of live Production delivery.

## Important limitations

1. **No asynchronous worker:** there is no `SKIP LOCKED` claim loop, lease, background retry, dead-letter queue, or worker observability. Do not describe this implementation as a worker or promise retries.
2. **Transaction coupling:** if notification insertion fails, the triggering outbox insert and parent workflow transaction may fail too. Confirm this behavior is acceptable before release; otherwise implement a durable asynchronous worker.
3. **Recipient mapping:** resolve recipients only from trusted workflow state. Do not accept arbitrary recipient IDs from the browser. Until the school's authorized escalation recipient is verified, blocked-approver requests must not alert a guessed administrator.
4. **Privacy:** in-app content contains only a safe event label and generic next-action text. Never include leave reason, diagnosis, attachment names/content, tokens, or sensitive provider responses in notification previews or logs.
5. **Channels:** only in-app database delivery is implemented in this candidate. Email and Web Push are not configured and must not be reported as delivered.
6. **Access:** worker-only credentials must remain server-side; no service-role key in browser bundles. Revoke PUBLIC/anon/authenticated execution of privileged routines and verify effective grants/RLS.
7. **Realtime:** database publication is only transport configuration. Validate authenticated recipient visibility, reconnect behavior, duplicate events, and polling/fallback in a real school-account browser test before claiming live delivery.

## Minimum isolated tests

- Outbox insert and notification insert commit or roll back together.
- Duplicate `event_key` cannot create duplicate recipient notifications.
- Safe notification text excludes leave reason and attachment data.
- Recipient RLS prevents another staff member from reading the notification.
- Authenticated users can mark only `read_at`; they cannot forge notification content or recipients.
- An unauthorized/anon caller cannot write notification rows.
- Realtime publication exists in the Supabase fixture and recipient visibility remains governed by RLS.
- If an asynchronous worker is added later: test concurrent claims, expired-lease recovery, bounded retry, dead-letter behavior, and forged-recipient rejection.

## Release gate

Before rollout: reconcile the trigger's transaction-failure behavior with school operations; implement recipient-isolation tests; verify official approver/escalation mapping; test browser notifications and Realtime reconnect using school accounts; inspect effective grants/RLS; and complete backup/rollback plus zero-cost verification. Production remains unchanged until a separate reviewed release and rollback plan is approved.
