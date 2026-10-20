# Staff Leave Management — Requirements and Safe Implementation Plan

## Status
Design/requirements only. This document does not deploy leave functionality, alter the production database, or change staff permissions.

## Scope approved by school owner
Support all school personnel categories, including:
- Civil servants (ข้าราชการ)
- Contract teachers (ครูอัตราจ้าง)
- Government employees (พนักงานราชการ)
- Additional categories configurable by the school, rather than hard-coded.

Rules and entitlements must be separated by personnel category. The same leave type must not imply identical entitlement across categories unless HR explicitly confirms that policy.

## Source document and evidence boundary
The supplied 33-page PDF is titled **คู่มือการปฏิบัติงาน เกี่ยวกับการลาประเภทต่าง ๆ ของข้าราชการ**, published by ศูนย์เทคโนโลยีสารสนเทศและการสื่อสาร สำนักงานปลัดกระทรวงศึกษาธิการ (cover text). The table of contents on printed page 1 (PDF page 3) lists these topics:
1. การลาป่วย
2. การลาคลอดบุตร
3. การลาไปช่วยเหลือภริยาที่คลอดบุตร
4. การลากิจส่วนตัว
5. การลาพักผ่อน
6. การลาอุปสมบทหรือลาไปประกอบพิธีฮัจย์
7. การลาเข้ารับการตรวจเลือกหรือเข้ารับการเตรียมพล
8. การลาไปศึกษา ฝึกอบรม ปฏิบัติการวิจัย หรือดูงาน
9. การลาไปปฏิบัติงานในองค์การระหว่างประเทศ
10. การลาติดตามคู่สมรส
11. การลาไปฟื้นฟูสมรรถภาพด้านอาชีพ

The table of contents also lists corresponding forms in the appendix, including leave forms and a cancellation-of-leave form. These titles are transcribed from the visible table of contents; they are not yet a complete transcription of eligibility rules or day limits.

The PDF is a scanned/image document and its text was not machine-readable in the initial extraction. Therefore:
- Treat it as a reference for civil-servant leave only after page-by-page review.
- Do not silently apply civil-servant rules to contract teachers or government employees.
- Do not encode day limits, eligibility, documents, approval routes, or legal citations until verified from the source and/or an explicitly approved school HR policy.
- Capture page number and source/policy version for each rule in the eventual rule catalogue.
- If a rule cannot be verified, mark it as pending HR confirmation; do not guess.

## Functional requirements

### 1. Personnel profile and policy assignment
- Use the existing authenticated school account and profile; do not create a separate login system.
- Add an effective-dated personnel category and, if needed, employment type/status. Only authorized HR/admin roles may change it.
- Each leave application must snapshot the applicable category and policy version at submission so later profile changes do not rewrite historical decisions.
- Prevent a category from silently falling back to another category's policy. Missing policy must show a clear configuration error and block submission.

### 2. Leave application
- Select leave type from the policy assigned to the applicant's personnel category.
- Capture start/end date, full-day or partial-day if policy supports it, reason, contact/coverage information if required, and supporting attachments where applicable.
- Show a preview of requested days and any known balance before submission.
- Validate date order, overlapping requests, required fields, and policy-specific limits server-side.
- Support save draft, submit, withdraw/cancel according to status and policy, and view own application history.
- Do not expose sensitive reasons or attachments to colleagues who lack permission.

### 3. Approval workflow
- Configurable approval route by personnel category, leave type, organizational unit, and delegation/acting approver where school policy requires.
- States: draft, submitted, under review, approved, rejected, withdrawn/cancelled; HR may need an additional recorded/closed state, subject to policy confirmation.
- Record each action, actor, timestamp, decision, and reason in an append-only audit trail.
- Enforce transitions and authorization on the server/database, not only in the UI.
- Prevent applicants from approving their own request unless a formally approved exception exists.
- Preserve the submitted request and decision history; corrections should be audited rather than silently overwriting records.

### 4. HR administration
- Manage personnel categories, leave types, policy versions, entitlements, required evidence, approval routes, holidays/calendar rules, and effective dates.
- Require a second-person review or explicit publish confirmation for policy changes; retain prior versions.
- Report by period, personnel category, leave type, organizational unit, and status, with access controls and export audit.
- Provide a reconciliation view for HR to review leave balance calculations before balances are relied on for payroll or official reporting.

### 5. Notifications and privacy
- Notify applicant and approvers when submitted, assigned, decided, or returned for correction.
- Notifications should avoid including detailed medical/family reasons or sensitive attachments.
- Apply least-privilege access; sensitive leave documents should not inherit broad document-office access by default.
- Log administrative access, exports, policy changes, and decisions.

## Policy catalogue required before production rules
For each personnel category and leave type, HR must confirm:
1. Eligibility and applicable legal/policy source.
2. Entitlement/maximum days and whether days are calendar or working days.
3. Counting rules for weekends, holidays, partial days, and cross-year leave.
4. Required notice, evidence, and submission timing.
5. Approval route and delegation.
6. Balance carryover, accrual, proration, and reset rules.
7. Effective date and transition treatment for existing/pending requests.
8. Source document title, version/date, and page/article reference.

The civil-servant guide alone is not sufficient evidence for the entitlements of contract teachers and government employees. Obtain the applicable rules/contract/official HR policy for each category or have school HR explicitly approve the configured policy.

## Suggested implementation sequence
1. Read and transcribe the scanned guide page by page; validate extracted rules and page references with HR.
2. Create a rule matrix per personnel category; mark unresolved entries as pending.
3. Inspect the existing production schema, profile/role model, and workflow RPCs read-only; design migrations against the actual catalog rather than assuming tables.
4. Implement schema and server-side authorization with automated database tests, including cross-category isolation, self-approval prevention, overlap/date validation, audit immutability, and unauthorized attachment access.
5. Build applicant, approver, and HR screens with accessible Thai labels and mobile-friendly layout.
6. Run CI and review; deploy schema and frontend only after migration reproducibility and security checks pass.
7. Pilot using explicitly synthetic test accounts and test requests; do not submit real staff leave or delete/modify existing production records during tests.
8. Obtain HR owner acceptance of policy rules, balance calculations, reports, and access controls before general release.

## Acceptance criteria
- No production entitlement is guessed or copied across personnel categories without approval.
- Every active rule has an effective date, source/policy reference, and approving owner.
- Server/database tests prove only authorized people can read, decide, or administer each request.
- Every decision and policy change is auditable.
- Leave attachments and reasons are private by default.
- Test results cover all categories and key workflow transitions before release.
- Production rollout has a tested rollback/recovery plan.


## 6. Required event notifications (confirmed by school owner)
The system must generate notifications for:
- A new leave application being submitted.
- Approval/rejection and each workflow handoff (including when the deputy director's review reaches the director for final decision).
- A leave cancellation request and its accepted/rejected outcome.
- A leave period that has ended without a recorded return or approved extension; label this as an overdue-return review alert, not an automatic misconduct finding.

Notify the applicant and the authorized people responsible for the next action. Use in-app notifications as the baseline, with email/web push as optional channels. Notification delivery must be retryable and idempotent; record delivery status and failures. Keep medical, family, and other sensitive details out of push/email previews. Opening a notification must re-check authorization on the server.

Ordinary cancellation must meet the previously confirmed cutoff of at least one calendar day before the leave start date in Asia/Bangkok. Late cancellation must be routed through an authorized exception process with a recorded reason and audit trail; do not silently bypass the cutoff.

## 7. Director and deputy-director dashboards (confirmed by school owner)
Provide role-authorized dashboards for the school director and deputy director with:
- Counts by workflow status, including awaiting deputy review, awaiting director decision, approved, rejected, cancelled, and late-cancellation exceptions.
- Leave usage trends by month/term/year, leave type, personnel category, and organizational group.
- Staff currently on leave, expected returns, overdue-return alerts, and approved extensions.
- Review/approval turnaround times and data-quality alerts for missing or unverified policy mappings.
- Filters for period, status, leave type, personnel category, and organizational group.

Every chart must define whether it counts requests, calendar days, working days, or person-days. Aggregates and drill-downs must enforce the same authorization and privacy rules as the underlying requests. A dashboard role does not grant unrestricted access to sensitive reasons or attachments. An overdue-return alert is a prompt for authorized review, not a disciplinary conclusion.

## 8. Policy-based day counting (mandatory)
Calculate leave days only from the verified, effective policy version for the applicant's personnel category, leave type, and relevant dates. The policy catalogue must explicitly state the counting basis and treatment of weekends, official holidays, partial days, date boundaries, and policy-version transitions. Store the calculated result with the policy version and calculation details used at decision time.

Use a single server-side calculation path and Asia/Bangkok date semantics. Do not infer entitlement days from a chart, an old request, or a different personnel category. If the governing policy is missing, ambiguous, or not verified, stop automatic calculation and route the request for authorized HR review. Keep approved leave-day totals distinct from elapsed absence/overdue-return days.

The supplied BICT/MOE manual concerns civil-servant leave; do not automatically apply its rules to contract teachers or government employees. For civil-servant teachers, verify applicable authority against current official circulars, including OTEPC ว 14/2568 dated 3 April 2025, and retain source/page/version references for every configured rule.
