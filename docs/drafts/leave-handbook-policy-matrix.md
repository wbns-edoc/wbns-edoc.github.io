# Staff leave handbook policy matrix (draft, source-derived)

Source file supplied by the school: `คู่มือการลาของเจ้าหน้าที่-ศทก_page-0001(1).pdf` (33 scanned pages). This is a transcription work product, not an assertion that all rules have been verified. The source describes civil servants and cites the Prime Minister's Regulation on Civil Servant Leave B.E. 2555. Per the school owner's explicit instruction, the application will use one shared policy set for all school personnel; this is a local implementation choice and is not a claim that the source legally governs every employment category.

## Rules legible in the current OCR pass

| Leave type | Source-derived rule | Source page | Implementation status |
|---|---|---:|---|
| Sick leave (ลาป่วย) | OCR confirms the section exists. Exact entitlement and medical-certificate thresholds must be transcribed from the source page before configuring validation. | 5–7 (contents indicates p.5; scanned page mapping needs final verification) | Not configured |
| Maternity leave (ลาคลอดบุตร) | Leave may begin before, on, or after childbirth; total leave must not exceed 50 days including public holidays. Source says salary during maternity leave for 50 days. If childbirth does not occur as scheduled, cancellation may be requested; days already taken count as personal business leave. If maternity leave overlaps another leave type, the other leave ends and maternity leave applies from its start date. | 8 | Draft rule; confirm page numbering |
| Leave to assist lawful wife after childbirth (ลาไปช่วยเหลือภริยาที่คลอดบุตร) | 15 working days, in periods/segments. | 8 | Draft rule; confirm full conditions |
| Personal business leave (ลากิจส่วนตัว) | For other personal reasons: source says salary during leave up to 55 working days per year; in the year of first appointment, up to 15 working days. A separate child-care personal leave category exists; its full entitlement must be transcribed before implementation. | 8–9 | Partial; do not enforce limits yet |
| Annual rest leave (ลาพักผ่อน) | 10 working days per fiscal year, with source-described exceptions for newly appointed staff. Unused days may accumulate: total accumulated plus current-year leave capped at 20 working days; for 10+ consecutive years of service, capped at 30 working days. Source mentions an additional 10 working days for qualifying continuous service in specified southern border provinces. | 9 | Draft rule; eligibility/exception details require exact transcription |
| Ordination / Hajj leave (ลาอุปสมบทหรือไปประกอบพิธีฮัจย์) | Application must be submitted at least 20 days before leave/departure. Ordination or Hajj travel must begin within 10 days of leave start. After Hajj, report back within 5 days of returning to Thailand. If unable to perform the purpose after leave has begun, report back and cancel; days already taken count as personal business leave. Source indicates a maximum of 120 days and a condition about not having used the entitlement before; exact shared details need transcription. | 10 | Partial; distinguish subtype-specific conditions |
| Military selection / preparation (ลาเข้ารับการตรวจเลือกหรือเข้ารับการเตรียมพล) | Source says leave requires an official call-up notice and contains reporting deadlines; OCR of the exact number of hours is uncertain, so no deadline is configured from OCR alone. | 11 | Not configured |
| Study / training / research / observation (ลาไปศึกษา ฝึกอบรม ปฏิบัติการวิจัย หรือดูงาน) | Source lists eligibility and approval conditions, including service-duration and relevance to the job; OCR text is incomplete and exact conditions are not configured. | 11 | Not configured |
| International organization duty (ลาไปปฏิบัติงานในองค์การระหว่างประเทศ) | Listed in contents; conditions not yet transcribed reliably. | Contents p.3; section later in document | Not configured |
| Spouse-following leave (ลาติดตามคู่สมรส) | Listed in contents; conditions not yet transcribed reliably. | Contents p.3; section later in document | Not configured |
| Occupational rehabilitation leave (ลาไปฟื้นฟูสมรรถภาพด้านอาชีพ) | Listed in contents; conditions not yet transcribed reliably. | Contents p.3; section later in document | Not configured |

## Workflow extracted from the source

The process diagram on scanned page 6 shows: employee writes/submits leave request (in advance or on the day they return to work) → administration/leave-control staff check leave days and record them in the leave register → submit through the supervisory chain to the authorized decision maker → authorized person considers/approves at their discretion → administration notifies the employee of the decision.

## Engineering rules

1. Do not hard-code entitlements until the complete source transcription is verified page by page. OCR is error-prone on this scanned PDF, especially Thai numerals and tables.
2. Keep the policy version and the exact rule snapshot used for every request so later rule edits do not rewrite past decisions.
3. Perform day-counting and entitlement validation server-side. Distinguish calendar days from working days, and make holiday calendars explicit.
4. Treat over-limit leave as a visible exception requiring a documented authorized decision; do not silently reject or silently allow it.
5. All personnel categories use the same school-configured rule set as explicitly requested by the school owner; retain this as a school policy decision in the audit trail.
6. Approval routing remains: verified active Vice Director review then Director final decision; Director-only only when the school's authorized configuration explicitly confirms no Vice Director. Snapshot approver identities at submission.
7. Keep implementation in draft/test until all 11 categories are transcribed, automated tests pass on a clean isolated database, and the owner explicitly approves a production release.

## Remaining source transcription checklist

- [ ] Verify page numbers printed in the manual against PDF page indexes.
- [ ] Complete the sick leave threshold/certificate details.
- [ ] Complete personal leave for child care.
- [ ] Complete ordination and Hajj eligibility, one-time conditions, and exact limits.
- [ ] Verify military report deadlines (OCR output was ambiguous).
- [ ] Transcribe study/training/research/observation conditions.
- [ ] Transcribe international organization, spouse-following, and occupational rehabilitation leave.
- [ ] Verify forms and required supporting documents.
- [ ] Have the resulting matrix reflected in policy seed/migration tests before enabling enforcement.
