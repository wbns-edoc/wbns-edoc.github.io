# Secure school-wide leave implementation — draft only

**Status: NOT PRODUCTION-READY. Do not execute as SQL or deploy.**

## Decisions
- All school personnel use one school-wide leave policy. Personnel category is reporting metadata only and never selects entitlements or day-count rules.
- The existing leave migration draft is unsafe to apply as-is: it has category-specific policy structure and overly broad approver read access.
- Production RBAC role codes must be inspected and explicitly mapped; never guess director/deputy role codes.
- The Deputy Director role remains defined in the system, but the school currently has no person holding that position. A role definition is not proof of an active approver.
- Default-deny direct client writes. Workflow transitions must use narrow, server-side authorization-checked functions.
- Do not activate automatic day calculations until the school-approved authoritative policy and day-counting details are verified.

## Proposed schema contracts
1. `leave_policy_versions`: one school-wide version, effective dates, status, official source/version, approval metadata, and verified rules. No personnel-category foreign key.
2. `leave_types`: code, label, active flag, attachment requirement; no guessed day limits.
3. `leave_requests`: requester, type, immutable policy version snapshot, start/end, calculation result/basis, status, private reason, timestamps.
4. `leave_approval_actions`: append-only actor/action/reason/from-status/to-status/time. No client UPDATE/DELETE.
5. `leave_attachments`: private storage object key, uploader, MIME type, byte size, checksum. No public bucket; use short-lived signed URLs after request-level authorization.
6. `leave_notification_outbox`: unique idempotency key, event, recipient, minimal safe payload, retry state and timestamps.

## Workflow contracts
- Staff submits their own request.
- Do not route a request to the vacant Deputy Director role or leave it waiting indefinitely for that role.
- Proposed current-school route: staff submits -> Director reviews/decides directly, **only after verifying the applicable official authority and any required school delegation**. Until then, do not enable this route in Production.
- Never grant Deputy Director permissions to the Director or another employee as a shortcut. If an acting approver is formally appointed, record explicit authority, scope, effective dates, reason, actor and audit trail.
- If no authorized approver can be resolved, preserve the request and history in a visible blocked state and alert an authorized administrator; the alert itself must not grant approval rights.
- Prevent self-approval.
- Cancellation must enforce the approved cutoff in Asia/Bangkok. Late cancellation cannot use the ordinary path; route it to a reasoned, authorized exception.
- Every decision and exception is auditable; no unguarded client-side status updates.

## Privacy and dashboard
- Do not grant every director/deputy account unrestricted access to all private reasons and attachments.
- Provide separate narrow server-side endpoints for own-request details, approval queues, authorized request detail, and aggregates.
- Dashboard counts must distinguish request counts, calendar days, working days and person-days; use Asia/Bangkok reporting boundaries.
- Push/email previews must not contain medical details or private leave reasons.

## Required tests before release
- Default-deny direct writes and RLS isolation.
- Role mapping and unauthorized approver rejection.
- Vacant Deputy Director role does not create a dangling task, trigger a silent role grant, or silently substitute another person.
- Direct-to-Director workflow is enabled only after documented authority verification.
- No authorized approver yields a visible blocked state and safe alert, not a dropped request or an unbounded pending task.
- Self-approval blocked.
- Cancellation cutoff tested immediately before/at/after boundary in Asia/Bangkok.
- Identical policy version and dates yield identical calculation regardless of personnel category.
- Policy changes do not rewrite historical requests.
- Unverified day rules block automatic calculation.
- Notification retries are idempotent and recipients match the resolved authorized route.
- Dashboard aggregates reconcile with authorized records.
- Append-only audit; reproducible migration replay in a disposable database.
- Synthetic-account pilot, backup/rollback plan and explicit release approval.

## Release gate
**NO-GO** until role mapping, official policy verification, non-production implementation, automated tests, security review and rollout checks pass. This is a design specification, not a runnable migration.
