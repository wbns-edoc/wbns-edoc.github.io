# Staff Leave RPC Security Test Matrix

Status: draft-only test specification. These cases are acceptance criteria for future RPC implementations; this file does not implement workflow functions and does not authorize a Production migration.

## Test harness requirements

- Run against a disposable PostgreSQL 17/Supabase-compatible database after applying the exact candidate migration.
- Use synthetic identities only. Set the JWT subject with the same mechanism used by the existing repository's RPC security tests.
- Execute RPC calls as `authenticated`; separately test unauthenticated/anonymous invocation and effective EXECUTE grants.
- Assert both the returned result/error and the database state after each call. A rejected call must leave request state, approval history, and notification outbox unchanged.
- Keep test fixtures independent of real school accounts, leave records, and Production data.

## Authorization and identity

| Case | Setup / attempt | Expected result |
|---|---|---|
| Missing identity | Call each RPC without `auth.uid()` | Denied; no writes |
| Inactive profile | Call create/submit/decide/cancel as inactive profile | Denied; no writes |
| Forged applicant | Supply another person's request ID to applicant-only action | Denied unless the caller is the actual applicant and the transition permits it |
| Forged actor | Attempt to pass an actor/user ID not equal to `auth.uid()` | RPC must not accept caller-selected actor identity |
| Self-approval | Applicant is also configured/assigned approver and tries to decide own request | Denied; no state/action/outbox change |
| Unassigned approver | Active staff member with no current assignment attempts decision | Denied; no writes |
| Stale assignment | Assignment changes after page load; former approver attempts decision | Denied after row lock and in-transaction recheck |
| Vacant Deputy Director | No active, verified deputy assignment exists | Request becomes explicitly blocked; no implicit Director routing |
| Unverified delegation | Client attempts to submit a route or authority flag | Ignored/rejected; only server-controlled, reviewed authority configuration can route |

## State transitions and concurrency

| Case | Attempt | Expected result |
|---|---|---|
| Invalid transition | Submit an already decided/cancelled request | Denied; no duplicate events |
| Concurrent decisions | Two approver transactions decide the same request | Exactly one valid transition; second sees stale state and fails |
| Duplicate submit | Retry submit with the same idempotency key | Same logical result; one submission action and one event per recipient/channel |
| Reused key, different intent | Reuse a key for a different operation or request | Reject as key conflict; do not silently alias operations |
| Duplicate decision | Retry same decision with same key after network timeout | No duplicate action/outbox rows |
| Rejection without required reason | Reject with blank/whitespace reason | Denied if policy requires a reason |
| Direct table mutation | Authenticated browser inserts/updates/deletes workflow rows | Denied by table ACL/RLS |
| History mutation | Try UPDATE, DELETE, TRUNCATE on approval history | Trigger rejects mutation, including privileged accidental paths |

## Cancellation rules (Asia/Bangkok)

Test fixed instants around local midnight, not the test runner's timezone:

- Start date minus two calendar days: cancellation allowed for an otherwise eligible request.
- Start date minus one calendar day: test exact boundary against the explicitly approved comparison rule.
- Start date itself and any later time: ordinary cancellation denied.
- Invalid date/state: fail closed.
- Late exception without verified authority: denied.
- Late exception with verified authority but missing reason: denied.
- Late exception with verified authority and reason: permitted only if the approved policy explicitly authorizes it; append actor, reason, authority basis, timestamp, and notification event.

## Transactional outbox and privacy

- Every successful transition and its action history/outbox rows commit together.
- Force an outbox insert failure in a disposable test; the state transition must roll back too.
- Deterministic event keys prevent duplicate rows on retry.
- Applicant and approver browser roles cannot SELECT outbox rows or payloads.
- Safe notification payload excludes leave reason, attachment names/content, medical details, and other sensitive fields.
- Worker retry/backoff and dead-letter behavior must be tested independently; provider errors must not include secrets or raw sensitive response bodies.

## Policy snapshot and reporting

- Applicant cannot supply `day_count`, policy version, policy snapshot, status, approver ID, or personnel-category entitlement.
- Submitted request snapshots the applicable approved school-wide policy version and rules; personnel category is reporting metadata only.
- No approved effective policy: submission is blocked/rejected safely; do not invent entitlement or day count.
- Effective-date boundaries, cross-year ranges, weekends, official holidays, and partial-day rules are covered once the official school policy is verified.
- Summary RPC limits rows to the caller by default and separates request count, calendar days, working days, and person-days.
- Management aggregates use a separate reviewed authorization predicate and return minimum necessary data.

## Release gate

RPC implementation is not ready until every applicable case above has an executable automated test, CI runs on the exact candidate commit, the application integration is exercised end-to-end, and the approval authority/delegation for the currently vacant Deputy Director position is verified. No Production migration is authorized by this test matrix.
