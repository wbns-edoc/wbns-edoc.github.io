# Staff Leave Notification Worker — Draft Runbook

Status: draft only. The function is not deployed and no schedule is configured.

## What it does
- Requires the `x-staff-leave-worker-secret` header and checks it against `STAFF_LEAVE_WORKER_SECRET`.
- Uses `SUPABASE_SERVICE_ROLE_KEY` only inside the Edge Function to claim due outbox rows and process them.
- Writes only `in_app` notifications. Email and push events are marked as permanent `CHANNEL_NOT_IMPLEMENTED` failures; they are never represented as delivered.
- Returns counts only. It does not return recipient IDs, event payloads, leave reasons, or secrets.

## Required server-side secrets
Configure these in the Supabase project's function secrets store, never in GitHub source, frontend env variables, or browser requests:
- `STAFF_LEAVE_WORKER_SECRET`: a long, randomly generated secret shared only with the trusted scheduler/invoker.
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Do not paste secret values into issues, PRs, chat, or logs. If the worker secret is exposed, rotate it immediately.

## Invocation
POST JSON such as `{"limit":20}` to the deployed function and include the `x-staff-leave-worker-secret` header. Limits are 1–50. The worker claims up to the requested number of due rows with a 90-second lease.

No scheduled trigger is configured by this change. Until a trusted scheduler is separately configured, rows will remain queued unless an authorized operator invokes the worker.

## Important delivery semantics
- `sent` means an in-app row was inserted (or an idempotent duplicate was confirmed by the unique key) in the database. It does not mean the user viewed the notification.
- A stale lease cannot complete delivery.
- Provider channels are deliberately unsupported. Add email/push adapters only after reviewing consent, provider configuration, retries, privacy, and duplicate semantics.
- A worker crash after claiming is recovered when the lease expires and another worker claims the row.
- Do not send notifications for blocked approver resolution to a guessed administrator. Recipient mapping must be verified separately.

## Release gates
1. Pass isolated migration and SQL tests.
2. Run Edge Function type/lint checks.
3. Add concurrency and lease-expiry recovery tests.
4. Verify service-role grants, secret rotation, invocation logs, and scheduler authentication.
5. Add UI read-state behavior and end-to-end tests.
6. Keep draft until school approval authority and policy are verified. Never deploy or apply the migration to Production without explicit release approval.
