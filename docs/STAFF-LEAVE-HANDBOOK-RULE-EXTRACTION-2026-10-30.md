# Staff leave handbook rule extraction — 2026-10-30

Status: **source recovered and visually checked; policy implementation still requires a verified school working-day calendar and a reviewed policy version.**

## Source identity

- Source: `คู่มือการปฏิบัติงานเกี่ยวกับการลาประเภทต่าง ๆ ของข้าราชการ`
- Issuer shown on cover: ศูนย์เทคโนโลยีสารสนเทศและการสื่อสาร สำนักงานปลัดกระทรวงศึกษาธิการ
- 33 scanned pages; substantive rules appear on printed pages 1–11, followed by application forms.
- The PDF is retained in the private ChatGPT Library and is not copied into this public repository.
- SHA-256 of the recovered PDF: `fb5e8939663af60abcc18f1b1b0ba724b8c011061447eb7d5e9d2cf98a4cf1f7`
- OCR was checked against page images for the numerical entitlements below.

School instruction for this implementation: **one common handbook policy applies to all school personnel**; do not branch entitlements by civil-servant / contract-teacher / government-employee category.

## Extracted leave types and limits

| Type | Counting / limit in the handbook | Additional conditions |
|---|---|---|
| Sick leave (`sick_leave`) | Up to 60 working days per year; in necessary cases an additional 60 working days may be authorized | Certificate normally required from 3 days when seeking treatment; the authority may request a certificate even for shorter leave; 30+ days requires a registered medical practitioner certificate; more than 60 days requires higher-level approval |
| Maternity (`maternity_leave`) | Up to 90 calendar days, including public holidays | No medical certificate required; salary during the 90-day period |
| Assistance to spouse after childbirth (`assist_spouse_childbirth`) | 15 working days; may be split into non-consecutive periods | Must be used within 90 days after childbirth; the procedure section says the application may be filed within 30 days after childbirth |
| Personal business leave (`personal_leave`) | Up to 45 working days per year; in the first year of service, paid leave is limited to 15 working days | May be recalled for official necessity; exceptional inability to apply in advance must be explained on the first day back |
| Childcare after maternity (`personal_leave` subtype) | Up to 150 working days immediately following maternity leave | Unpaid; handbook says the employee cannot be recalled for official necessity during this leave |
| Annual/vacation leave (`annual_leave`) | 10 working days per fiscal year; carry-over plus current-year entitlement capped at 20 working days, or 30 working days after 10+ consecutive years of service | Certain first-year appointees have no annual leave if service is under 2 months; approval is required before absence |
| Ordination / Hajj (`ordination_hajj`) | Up to 120 days; salary entitlement up to 120 days | Only once during service; at least 12 months' service; apply at least 20 days before; ordain/travel within 10 days after leave starts and report back within 5 days after disrobing / return to Thailand |
| Military selection / reserve training (`military_selection_training`) | Duration stated in the official summons; salary during leave | Notify supervisor within 48 hours of receiving summons; report back within 7 days after release; necessary extension may be granted but total return window must not exceed 15 days |
| Study / training / research / site visit (`study_training_research`) | Course-dependent: below bachelor's degree = course duration; master's = 2 years; doctorate = 4 years; salary during leave up to 4 years; extension may make total study time up to 5 years | Must pass probation and generally have at least 1 year of service; extension up to 2 semesters / 1 academic year; course must benefit the position and requires a service-return agreement |
| Work in an international organization (`international_organization`) | Type 1 up to 5 years; Type 2 up to 1 year | Normally unpaid, subject to a salary top-up rule; service-return obligation generally 1x the leave period; prior-service, age and repeat-leave conditions apply |
| Follow spouse abroad (`spouse_following`) | Initially up to 2 years; may extend by another 2 years; absolute total not over 5 years | Unpaid; spouse must be assigned / working abroad under the conditions in the handbook |
| Occupational rehabilitation (`vocational_rehabilitation`) | Course duration, capped at 12 months | Requires qualifying disability / injury circumstances and a course recognized by a government agency or accredited institution |

## School workflow overlay

The handbook's general process is: employee submits leave → office checks dates and records the leave register → supervisor chain forwards to the authorized approver → approver decides → office notifies the employee and records the result.

The school's confirmed workflow overlays that general process:

1. Normal approval: Vice Director first, then Director.
2. If the Director is absent, the Vice Director may approve directly only when the absence is supported by recorded evidence and the authority record is active for the leave date.
3. Director and Vice Director roles remain supported even when the school currently has no Vice Director.
4. Cancellation must be requested at least 1 day before the leave start date.
5. Submit / decision / cancellation / over-limit events must notify the relevant staff and approvers; dashboards show aggregate counts without exposing request reasons.

## Calculation requirements and fail-closed items

- Working-day leave must exclude weekends **and** verified school/public holidays. The current SQL calculation supports an explicit `calendar.non_working_dates` list; it must not be marked ready until the school's calendar is loaded and verified.
- Calendar-day leave includes weekends and holidays.
- Annual leave requires service-start date and carry-over balance to enforce the 20/30-day cap.
- Sick/personal leave requires a per-year accumulator; the exact period boundary must be set consistently with the governing service-year rule.
- Childcare leave needs a subtype distinct from ordinary personal leave so it can be unpaid, follow maternity, and apply its non-recall condition.
- Ordination/Hajj is a once-per-service entitlement and needs historical-use evidence.
- Military, study, international-organization, spouse-following, and rehabilitation leave require eligibility / evidence fields beyond a simple day-count maximum.
- Over-limit requests may be flagged and routed for review; the system must not silently approve or invent an exception.

The current `staff_leave_shared_policy_calculation_gate` intentionally fails closed when a reviewed school-wide policy and explicit calendar are absent. Do not set `calculation_ready=true` until the missing calendar, service history, subtype, and evidence rules are implemented and tested.

## Evidence / review notes

The rules above are an extraction of the supplied handbook, not a replacement for the legal instrument cited by the handbook. The school has expressly adopted one shared policy for all personnel. Any rule that depends on service history, prior use, official evidence, or a school-specific holiday calendar must be represented in the system rather than approximated with a generic date count.
