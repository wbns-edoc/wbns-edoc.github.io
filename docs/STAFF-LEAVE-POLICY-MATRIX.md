# Staff Leave Policy Matrix (Draft — HR Validation Required)

## Purpose and guardrails
This matrix is a data-entry and review template, not an approved legal policy. Do not enable leave submission or calculate official balances from this draft. The supplied guide is specifically about civil servants; it does not establish entitlements for contract teachers or government employees.

## Leave types transcribed from the supplied guide's table of contents
| ID | Leave type | Civil servant guide reference | Rule verification |
|---|---|---|---|
| sick_leave | การลาป่วย | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| maternity_leave | การลาคลอดบุตร | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| assist_spouse_childbirth | การลาไปช่วยเหลือภริยาที่คลอดบุตร | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| personal_leave | การลากิจส่วนตัว | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| annual_leave | การลาพักผ่อน | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| ordination_hajj | การลาอุปสมบทหรือลาไปประกอบพิธีฮัจย์ | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| military_selection_training | การลาเข้ารับการตรวจเลือกหรือเข้ารับการเตรียมพล | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| study_training_research | การลาไปศึกษา ฝึกอบรม ปฏิบัติการวิจัย หรือดูงาน | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| international_organization | การลาไปปฏิบัติงานในองค์การระหว่างประเทศ | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| spouse_following | การลาติดตามคู่สมรส | Table of contents; exact page/rule references pending | Pending page-by-page transcription |
| vocational_rehabilitation | การลาไปฟื้นฟูสมรรถภาพด้านอาชีพ | Table of contents; exact page/rule references pending | Pending page-by-page transcription |

## Personnel categories
For each leave type above, HR must complete a separate row for each category:
- ข้าราชการ
- ครูอัตราจ้าง
- พนักงานราชการ
- Other category (configured by school, if applicable)

## Required fields per category + leave type
| Field | Required value |
|---|---|
| Eligibility | Allowed / not allowed / conditional; define condition |
| Entitlement | Numeric value and unit, or not applicable |
| Counting method | Working days / calendar days / hours / policy-defined |
| Annual period | Calendar year / fiscal year / employment anniversary / other |
| Accrual and carryover | Rule or not applicable |
| Minimum notice | Rule or not applicable |
| Required evidence | Evidence type, when required, and privacy classification |
| Partial-day support | Yes/no and counting method |
| Overlap and holidays | Explicit calculation rule |
| Approval route | Role/position sequence, delegation, and conflict-of-interest rule |
| Cancellation/withdrawal | Allowed states, cutoff, and required reason |
| Effective from/to | Dates |
| Source | Official regulation/contract/policy title, version/date, article/page |
| Approved by | HR owner and approving authority |
| Verification status | Pending / reviewed / approved / retired |

## Implementation rules
1. Missing or unapproved category-specific rules must block submission for that leave type; never fall back to another category's policy.
2. No balance calculation is authoritative until the source, counting method, annual period, carryover, and effective dates are approved.
3. Sensitive evidence (for example, medical documents) must have stricter access controls than ordinary office documents.
4. Policy edits are versioned and auditable. Historical requests retain the policy version used at submission.
5. Changes require automated tests for authorization, date ranges, overlap, status transitions, self-approval prevention, and privacy boundaries.

## Approval checklist before enabling a category
- [ ] Applicable official rule or signed/approved employment policy attached
- [ ] Eligibility and entitlements verified
- [ ] Working-day/calendar-day calculations verified with examples
- [ ] Approval route confirmed by school leadership
- [ ] Evidence and privacy requirements reviewed
- [ ] HR signs off and effective date assigned
- [ ] Synthetic end-to-end test passes
