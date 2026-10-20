# School-wide leave policy — owner decision

Status: decision recorded; exact legal rules and day-counting details still require verification against the school's approved source.

## Decision from school owner
The school owner has explicitly confirmed that **all personnel at Wat Bueng Nam Sai School use the same leave rules**. Do not create separate leave entitlements or different day-counting rules by personnel category in the application.

## Implementation requirements
- Maintain one school-wide leave policy catalogue, with one authoritative version effective for the relevant dates.
- All personnel use the same approved leave types, eligibility, day-counting basis, weekend/holiday treatment, partial-day handling, cancellation rules, and approval workflow, as specified in that policy.
- Personnel category may remain as profile/reporting metadata only if needed; it must not silently change leave entitlement or calculation.
- The policy must still cite the actual official regulation/order/manual and record the approved effective date and version. The owner's statement establishes the intended school-wide application, but does not itself establish specific entitlement numbers or override any legally binding rule.
- If the source materials do not support a specific day limit or counting detail, mark it for authorized school confirmation instead of guessing.
- Dashboard reports should use the same shared rule set for all school personnel and may still filter statistics by personnel category for analysis, without applying different policy rules.

## Required test coverage
- Verify that equivalent leave requests for staff in different personnel categories calculate the same number of days under the same policy version and dates.
- Verify that category changes do not rewrite previously submitted or approved leave requests.
- Verify that every request stores the shared policy version used at submission/decision time.
- Verify that missing/unverified rules block unsupported automatic calculations.
