# Owner decisions required before Production release — 2026-10-09

Status: release blocked; documentation only. This file records the owner's approved visibility rule; it does not authorize Production changes.

## Verified release blockers

- The linked Supabase project is the Production project. No Supabase development branch was available during the latest review.
- Read-only snapshot showed 1 profile, 0 departments, 0 documents, and 1 System Admin role assignment.
- The school owner has supplied these four department names as the authoritative starting list:
  1. กลุ่มบริหารงานวิชาการ
  2. กลุ่มบริการงบประมาณ
  3. กลุ่มบริหารงานบุคคล
  4. กลุ่มบริหารงานทั่วไป
- The owner clarified that System Admin, เจ้าหน้าที่ธุรการ, ผู้อำนวยการสถานศึกษา, and รองผู้อำนวยการสถานศึกษา are central roles: they are not members of the four departments and sit above/across them in the organizational structure.
- The current Production database still has 0 departments; receiving the names does not mean they have been inserted into Production.
- `documents` currently has no `department_id`; current document policies include creator/current-owner access and broad permission-based access without department isolation.
- Production migration history and repository migration files do not match one-to-one. Live function implementations differ from some repository migration expectations.
- The Drive upload CI validates frontend compilation, helper tests, input validation, JWT configuration, secret-reference guard, and Edge Function types. It does not validate live Drive uploads, cross-department authorization, or backup/restore.
- No Production schema, policy, role, or data changes are authorized by this checklist.

## Owner decisions confirmed — 2026-10-10

The owner approved the following central-role visibility rule:
- **System Admin** and **ผู้อำนวยการสถานศึกษา** may read all school documents automatically, across all four departments.
- This is a **read-visibility grant only**. It does not automatically grant the System Admin business workflow authority to register, assign, approve, issue commands, void records, or bypass workflow. Those actions still require separate explicit permissions and audit controls.
- The director's authority to read all documents is confirmed; approval/command and mutation actions remain governed by the school's approved workflow and any separately configured permissions.
- **เจ้าหน้าที่ธุรการ** and **รองผู้อำนวยการสถานศึกษา** do not receive blanket all-document visibility from this decision. Their access remains limited to specifically approved registry duties or delegated scope.
- These central roles remain independent of department membership; do not populate their `profiles.department_id` merely to enable access.

This approval records the intended policy, but it has **not** been implemented in Production. Existing broad grants and policies must be reviewed and reconciled safely before deployment.

## Decisions still needed from the school owner

1. **Separate central roles from department membership**
   - Treat System Admin, เจ้าหน้าที่ธุรการ, ผู้อำนวยการสถานศึกษา, and รองผู้อำนวยการสถานศึกษา as central roles with no `department_id` assignment to the four department groups.
   - Keep role-based capabilities separate: System Admin manages system configuration and accounts; the registrar handles registry work; the director and deputy director receive document review/approval/command permissions according to the school's approved workflow. Do not assume all four roles have identical powers merely because they are central.
   - Confirm the initial role assignments for all existing profiles and whether the current single System Admin account also holds any other central role. Do not infer role assignments from names, email addresses, or job titles.

2. **Remaining central-role access and registry visibility**
   - System Admin and the director have approved automatic school-wide document read access. Implement this as explicit, auditable role-based read scope, not as a generic admin bypass.
   - Define the registrar's and deputy director's document visibility and registry/workflow permissions separately; do not infer blanket access from their central position.
   - Keep System Admin technical administration separate from business workflow authority.
   - A profile with no department and no approved central role must not automatically receive school-wide document access.

3. **Cross-department assignment and transfer**
   - Confirm whether cross-department delegation is allowed and which role may authorize it.
   - Confirm whether a creator or former owner retains access after transfer. Default recommendation: transfer must not silently preserve broad access.

4. **Accepted file formats**
   - Confirm the allowed school document formats (for example, PDF, DOCX, XLSX, JPG/PNG) and whether any other formats are required.
   - Until confirmed, do not deploy an invented MIME/extension allowlist.

5. **Approved frontend origins**
   - Provide the actual production web origin(s) before replacing the upload function's wildcard CORS origin.
   - Do not guess the GitHub Pages/custom domain origin or break school access.

6. **Backup and test approval**
   - Confirm the approved backup/restore test window and who verifies recovery.
   - Provide or approve a zero-extra-cost non-Production test environment. Do not create paid resources or test by changing Production.

## Required release gates

- Reconcile Production migration history with repository migration SQL and provenance before applying any migration.
- Build a department-scope migration and tests against a non-Production database seeded with explicitly approved fixtures.
- Test read, update, assignment, registration, file metadata, and attachment paths as users in different departments; include no-department, inactive-department, transfer, and explicit school-wide roles.
- Preserve the existing System Admin and prove that administrative changes cannot remove the last active System Admin.
- Test upload success, failed attachment, timeout/ambiguous RPC result, cleanup failure, and retry behavior with test documents.
- Complete backup/restore verification, review Supabase security advisors, and obtain owner approval.
- Only then schedule a controlled deployment and post-deploy verification.

## Cost and safety constraints

- Target additional infrastructure cost: 0 THB.
- No Production schema/policy/role/data changes before all gates and owner approval.
- Never solve missing test coverage by using real school documents or weakening RLS.
