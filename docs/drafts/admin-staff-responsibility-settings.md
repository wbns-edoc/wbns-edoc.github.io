# Draft: Admin-managed school responsibility assignments

Status: design/implementation draft only. Do not deploy or apply to Production.

## Responsibilities shown in System Settings

1. Director / ผู้อำนวยการโรงเรียน — required.
2. Vice Director / รองผู้อำนวยการโรงเรียน — optional only when the school explicitly sets that the position does not exist.
3. Personnel work-group head / หัวหน้ากลุ่มงานบุคคล.
4. Budget work-group head / หัวหน้ากลุ่มงานบริหารงบประมาณ.
5. Academic work-group head / หัวหน้ากลุ่มงานบริหารวิชาการ.
6. General Administration work-group head / หัวหน้ากลุ่มงานบริหารทั่วไป.

The last item resolves the duplicated "หัวหน้ากลุ่มงานบริหารวิชาการ" in the original request, based on the existing GENERAL department shown in the school UI.

## UI acceptance criteria

- Display a dedicated "ผู้รับผิดชอบและผู้บริหาร" section in System Settings.
- Only System Admin may view/edit assignment controls; authorization must also be enforced server-side.
- Each selector lists only existing, active user profiles. This screen must not create user accounts.
- Show the assigned person's full name and active status; allow clearing optional work-group assignments.
- Require an active Director. Never infer/substitute the Director from another role.
- Include an explicit setting "โรงเรียนมีรองผู้อำนวยการ" yes/no. If yes, a valid active Vice Director is required for the two-stage leave route; if no, new leave requests go directly to the Director.
- Every change is audited with role key, previous user, new user, actor, and timestamp.
- Prevent accidental conflicting assignments where the same person is selected for both Director and Vice Director.
- Assignment changes must not silently change the route of leave requests already submitted. A request must retain an immutable route snapshot.
- Show clear error messages when no eligible users exist or an assigned account becomes inactive.

## Verification required before release

- Migration replay on an isolated database.
- SQL/RPC tests for System Admin-only write access, non-admin denial, unknown/inactive profiles, required Director, optional Vice Director, assignment audit records, and route snapshot stability.
- UI build and tests.
- Confirm that existing production departments (ACADEMIC, BUDGET, GENERAL, PERSONNEL) are reused; do not create duplicates.
- Integrate the configured Director/Vice Director with leave submission/decision and notification recipients.
- Verify all leave entitlement and day-count rules against the official handbook; do not guess.
- No merge, deploy, Production migration, or cost-incurring service without explicit approval.
