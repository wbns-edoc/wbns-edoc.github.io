# Staff Leave Notifications, Executive Dashboard, and Day Counting

Status: requirements/design only. This document does not deploy code, change Production, or establish unverified leave entitlements.

## 1. Notifications

Notifications are required for these events:

1. **Leave request submitted** — notify the deputy director as the first reviewer and the authorized leave administrator/HR role where configured. The director should be notified according to the school's workflow configuration; do not imply that notification itself grants approval authority.
2. **Deputy director review completed** — notify the director when the request advances to final approval, including the request reference, applicant, leave type, requested dates, and current status. Do not include sensitive medical details in push/email previews.
3. **Leave approved or rejected** — notify the applicant and relevant authorized reviewers. Record who acted, action time, decision, and any required reason in the audit trail.
4. **Leave cancelled** — notify the applicant, assigned approvers, and HR/authorized official. Record cancellation request time, effective status, actor, and reason. Enforce the previously specified rule: ordinary cancellation must be submitted at least one calendar day before the leave start date in Asia/Bangkok; late requests must go through an authorized exception process rather than silently bypassing the rule.
5. **Leave exceeds its approved period / overstay** — notify the employee and authorized HR/management recipients when a leave period has passed and no return/extension/updated status is recorded. This is a review alert, not an automatic finding of misconduct. Provide a way for an authorized officer to record a corrected return date, approved extension, or explanatory note, with audit history.
6. **Operational failures** — retain retryable delivery failures for administrators to monitor; never mark an undelivered notification as delivered.

### Delivery and privacy requirements
- Support in-app notifications first; email and web push are optional channels based on configured, consented, and available credentials. The system must remain usable if a channel is unavailable.
- Use an outbox/queue pattern so notification delivery is retried safely and duplicate deliveries are avoided with a stable event/idempotency key.
- Create the business event and its audit record transactionally; dispatch external notifications asynchronously.
- Store recipient, event type, request ID, channel, created/sent/delivered/failed timestamps, retry count, and sanitized error details.
- Keep an in-app read/unread state per recipient.
- Never expose leave reason, medical attachments, or other sensitive details in push notification text. Link to the authenticated request page, where server-side authorization is rechecked.
- Notifications are informational; every decision and permission check must be enforced server-side/database-side, not by the notification link or UI alone.

## 2. Executive dashboard

Provide separate dashboard views for the **school director** and **deputy director**, with metrics derived from authorized records and a consistent Asia/Bangkok reporting timezone.

### Core statistics
- Requests submitted, pending deputy review, pending director decision, approved, rejected, cancelled, and late-cancellation exceptions.
- Leave days by month/term/year, leave type, personnel category, and organizational group, subject to authorization and privacy thresholds.
- Staff currently on approved leave, expected return today, overdue return/possible overstay alerts, and approved extensions.
- Average elapsed time from submission to deputy review and from deputy review to final decision.
- Trends over time and comparison with a prior equivalent period where the data supports it.
- Data-quality indicators: missing personnel category, missing/expired policy mapping, incomplete decision trail, or unresolved return status.

### Dashboard behavior and access
- Filters: date range, personnel category, leave type, organizational group, status, and reporting period.
- Show the metric definition, data freshness/last refresh time, and whether the count represents requests, calendar days, working days, or person-days.
- A click-through to individual requests must recheck authorization. Aggregated statistics must not become a route to read another person's confidential leave reason or attachment.
- The director and deputy director see only records they are authorized to review under the approved authority matrix. Do not assume that a dashboard role alone grants unrestricted access to every sensitive field.
- No entitlement, “excess leave,” or misconduct conclusion may be inferred solely from a chart. Compare usage against the applicable, verified policy version for that school-wide policy version and leave type.

## 3. Policy-based leave-day counting

**Use the single school-wide policy confirmed by the school owner.** Day counting must be derived from the applicable approved school-wide policy version, leave type, and official source in force for the relevant dates. Personnel category is reporting metadata only and must never select a different entitlement or formula.

Each policy version should record:
- school-wide policy version and leave type; personnel category is retained only as optional reporting metadata;
- official source name, circular/order number, issue/effective dates, and source URL or retained reference;
- whether counting uses calendar days, working days, or another explicitly authorized basis;
- treatment of weekends, public holidays, half-days, start/end dates, and cross-year/cross-policy periods;
- required documents and any category-specific eligibility/limits, only after verification;
- reviewer, verification date, approval status, and policy version identifier.

Calculation rules:
1. Resolve the single school-wide policy version by leave type and leave start date (and apply any legally required transition rule for periods crossing an effective-date boundary).
2. Calculate days through one tested server-side function; use Asia/Bangkok for date-only business rules and avoid UTC date shifts.
3. Store the submitted date range and the calculated result separately, together with the policy version and calculation details, so later policy changes do not silently rewrite historical decisions.
4. Recalculate only through an explicit audited action when a correction is required.
5. If the applicable policy is missing, ambiguous, or not verified, flag the request for authorized human review; do not guess the number of days or silently use a generic default.
6. Distinguish approved leave days from elapsed absence days. A past approved end date without a recorded return/extension should create an “overdue return—needs review” alert, not an automatic disciplinary judgment.

### Source and verification note
The project reference supplied for civil-servant teachers is OTEPC circular **ว 14/2568 dated 3 April 2025**, concerning persons authorized to consider/approve leave for teachers and educational personnel; it supersedes ว 42/2555. Official listing: https://circular.otepc.go.th/v1_t_circualr_book_view.php?editid1=657 ; circular PDF: https://circular.otepc.go.th/files/w14-2568.pdf

The supplied BICT/MOE manual, **คู่มือการปฏิบัติงานเกี่ยวกับการลาประเภทต่าง ๆ ของข้าราชการ**, is a reference for civil-servant leave types and procedures. It must be read alongside applicable current circulars/orders. It does not by itself justify applying civil-servant rules to contract teachers or government employees. Those personnel categories require their own verified authority/policy mapping before calculations or entitlements are activated.

## 4. Acceptance criteria

- Submitting, advancing, deciding, cancelling, and overdue-return events generate the correct notification event and audit record.
- Retried delivery does not create duplicate business actions or duplicate notification records for the same idempotency key.
- Sensitive leave details do not appear in push/email previews or in unauthorized dashboard drill-downs.
- Dashboard totals reconcile with authorized underlying records and label their counting basis.
- Test cases cover weekends/holidays, half-day policy if applicable, timezone boundaries, policy-version changes, personnel categories, cancellation cutoff, approved extension, and overdue-return correction.
- Tests demonstrate that missing/unverified policy data blocks automatic day calculation instead of inventing a result.
- This feature is not Production-ready until database authorization, policy verification, notification delivery, dashboard aggregation, and automated tests have been reviewed and passed.
