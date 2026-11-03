# Staff leave — spouse-childbirth deadline research (2026-11-03)

Status: source reconciliation only. This note does not approve the school-wide policy and does not authorize changing Production.

## Finding

The two different numbers in the earlier draft were incorrectly described as competing filing deadlines.

- **90 calendar days** is the deadline to submit the leave request: under Regulation of the Office of the Prime Minister on Civil Servant Leave B.E. 2555, clause 20, the request must be submitted before or on the leave date and within 90 days from the childbirth date. Official government corroboration is available from the Office of the Civil Service Commission (OCSC) FAQ and the Office of the Permanent Secretary, Ministry of Commerce FAQ.
- **30 calendar days** appears in official guidance as a separate salary/compensation condition for some employment categories, not as a universal filing deadline. OCSC's Government Employee Benefits FAQ says the leave can be taken within 90 days, but where the leave is taken after 30 days the employee is not paid during leave unless the specified higher authority approves payment. That is a remuneration rule, not a reason to reject the filing itself.
- The school has independently confirmed the leave duration: no more than 15 consecutive working days per childbirth event, in one continuous period, not split into multiple periods.

## Sources checked

1. Regulation of the Office of the Prime Minister on Civil Servant Leave B.E. 2555, clause 20. Searchable copy reproduces the clause: https://pubhtml5.com/jmhbm/pnso/basic/ (official regulation text; verify against the Royal Gazette copy before final legal sign-off).
2. OCSC — Government Employee Benefits FAQ: https://www.ocsc.go.th/faq/government-or-permanent-employee/ge-benefits/ . It states a 90-day childbirth window, up to 15 consecutive working days, and distinguishes the 30-day compensation condition.
3. OCSC FAQ: https://www.ocsc.go.th/bpcc/faq/ . It confirms the 90-day window and 15 consecutive working days for government employees.
4. Ministry of Commerce personnel office FAQ: https://personnel.office.cpd.go.th/service/faq.html . It confirms submission before/on leave and within 90 days, up to 15 consecutive working days.
5. OTEPC circular ว14/2568 (3 April 2025): https://circular.otepc.go.th/v1_t_circualr_book_view.php?editid1=657 . This is relevant to approval authority for teacher civil servants/educational personnel; it does not define a different entitlement or extend civil-service rules to all school employment categories.

## Engineering interpretation

- Replace the draft's ambiguous `use_within_calendar_days_after_childbirth=60` and `file_within_calendar_days_after_childbirth=30` fields with a single clearly named `request_submission_deadline_calendar_days=90` only after the school approves this as the common school-wide rule.
- Keep any 30-day compensation/pay treatment in a separate policy field, and do not apply it to every personnel category unless the school explicitly adopts that as its uniform internal policy.
- Do not infer the 90-day/30-day pay distinction from personnel category at runtime: the school's stated requirement is one shared policy. Personnel category remains reporting metadata.
- Keep the policy version `draft`, `verification_status=pending`, and `calculation_ready=false` until the school authority approves the common policy, confirms how remuneration is treated for all personnel, and verifies the remaining leave types/calendar/service-history requirements.
- Do not update the live Production policy JSON or mark it approved based only on this research note. The current Production policy remains fail-closed.

## Still unresolved

1. Formal school approval that the common 90-day submission window applies to all personnel.
2. Whether the 30-day remuneration distinction is adopted, omitted, or replaced by a common school benefit; this must not be guessed.
3. Evidence and eligibility rules for legally married spouse, childbirth event identity, and one-time use.
4. All other policy gaps: school work calendar, service start/history, annual accumulators/carry-over, leave subtypes, one-time entitlements, and authority evidence.
