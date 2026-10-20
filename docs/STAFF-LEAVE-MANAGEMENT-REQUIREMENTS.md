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
The supplied 33-page PDF is titled **คู่มือการปฏิบัติงาน เกี่ยวกับการลาประเภทต่าง ๆ ของข้าราชการ**, published by ศูนย์เทคโนโลยีสารสนเทศและการสื่อสาร สำนักงานปลัดกระทรวงศึกษาธิการ (cover text). It is a scanned/image PDF and its text was not machine-readable in the initial extraction. Therefore:
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
