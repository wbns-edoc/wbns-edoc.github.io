# Leave notifications, executive dashboard, and shared-policy acceptance tests

Status: test specification only; no tests have been executed and no Production changes are made by this document.

## A. Notification event tests

| ID | Scenario | Expected result |
|---|---|---|
| NOTIF-001 | Staff submits a valid request | One in-app notification is queued for the deputy director/assigned first reviewer; request and audit event are committed together. |
| NOTIF-002 | Deputy director completes review and request moves to director | Director receives a notification identifying the request and next action, without sensitive leave details. |
| NOTIF-003 | Director approves or rejects | Applicant and relevant authorized reviewers are notified; decision actor, timestamp, outcome, and reason are auditable. |
| NOTIF-004 | Authorized cancellation is requested | Applicant and authorized approvers/HR receive the appropriate event; cancellation cutoff is checked in Asia/Bangkok. |
| NOTIF-005 | Cancellation is attempted too late | Ordinary cancellation is blocked; the user is directed to an authorized exception process; any exception has actor, reason, timestamp, and audit record. |
| NOTIF-006 | Approved leave end date passes with no return or extension | A review alert is generated for the employee and authorized HR/management recipients; it is not labelled misconduct automatically. |
| NOTIF-007 | Notification provider fails temporarily | Delivery is marked failed/retryable, error is sanitized, and retry does not duplicate the business action or notification event. |
| NOTIF-008 | User opens a notification for a request they cannot access | Server denies access; no sensitive request data is disclosed. |
| NOTIF-009 | Push/email preview is generated for a medical or family leave | Preview excludes reason, diagnosis, and attachment details. |
| NOTIF-010 | Same event is delivered more than once by a retry | Stable idempotency key prevents duplicate notification records/business transitions. |

## B. Dashboard tests

| ID | Scenario | Expected result |
|---|---|---|
| DASH-001 | Director opens dashboard | Sees authorized school-wide leave metrics and the director decision queue. |
| DASH-002 | Deputy director opens dashboard | Sees authorized school-wide leave metrics and the deputy first-review queue. |
| DASH-003 | Dashboard status counts are compared with request records | Counts reconcile; the definition and last refresh time are visible. |
| DASH-004 | Leave usage is grouped by month/type/group/personnel category | Every metric labels whether it counts requests, calendar days, working days, or person-days. |
| DASH-005 | User changes personnel-category filter | Filter changes reporting only; it does not change policy rules or computed days. |
| DASH-006 | User drills into an individual request | Authorization is rechecked; unauthorized reasons and attachments remain inaccessible. |
| DASH-007 | Overdue-return list contains a request | Label says “overdue return—needs review”; approved extension and corrected return date are reflected after authorized update. |
| DASH-008 | Data has an unverified or missing policy rule | Dashboard displays a data-quality warning; it does not report a guessed entitlement or balance. |

## C. Single school-wide policy and day-count tests

| ID | Scenario | Expected result |
|---|---|---|
| POLICY-001 | Two personnel categories submit the same leave type and dates under the same policy version | Same day-count result and same counting basis. |
| POLICY-002 | Applicable policy version is missing or not approved | Automatic calculation is blocked and the request is flagged for authorized review. |
| POLICY-003 | A policy version changes after an application is submitted | Historical request retains the policy version and calculation details originally used. |
| POLICY-004 | A date range touches weekends or public holidays | Result follows the explicitly verified shared policy; no implicit weekday/calendar-day assumption. |
| POLICY-005 | Partial-day leave is requested | Apply only if the shared policy explicitly defines partial-day behavior; otherwise block or route to review. |
| POLICY-006 | Date/time is near UTC/Bangkok midnight | Date-only cutoff and day counting remain correct in Asia/Bangkok. |
| POLICY-007 | Approved end date has passed but staff has an approved extension | No stale overdue-return alert remains after reconciliation; history stays auditable. |
| POLICY-008 | Staff profile category is changed after submission | Existing request's policy version and computed result do not change. |

## D. Release gate
These tests must be implemented and pass in a non-production environment before rollout. Also require database/RLS tests for self-approval prevention, unauthorized reads/writes, immutable audit history, and notification recipient authorization. This document is not evidence that implementation or tests already exist.
