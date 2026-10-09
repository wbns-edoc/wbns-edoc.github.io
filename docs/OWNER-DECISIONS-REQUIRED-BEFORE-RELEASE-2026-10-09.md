# Owner decisions required before Production release — 2026-10-09

Status: release blocked; documentation only. This file does not authorize Production changes.

## Verified release blockers

- The linked Supabase project is the Production project. No Supabase development branch was available during the latest review.
- Read-only snapshot showed 1 profile, 0 departments, 0 documents, and 1 System Admin role assignment.
- The school owner has supplied these four department names as the authoritative starting list:
  1. กลุ่มบริหารงานวิชาการ
  2. กลุ่มบริการงบประมาณ
  3. กลุ่มบริหารงานบุคคล
  4. กลุ่มบริหารงานทั่วไป
- The current Production database still has 0 departments; receiving the names does not mean they have been inserted into Production.
- `documents` currently has no `department_id`; current document policies include creator/current-owner access and broad permission-based access without department isolation.
- Production migration history and repository migration files do not match one-to-one. Live function implementations differ from some repository migration expectations.
- The Drive upload CI validates frontend compilation, helper tests, input validation, JWT configuration, secret-reference guard, and Edge Function types. It does not validate live Drive uploads, cross-department authorization, or backup/restore.
- No Production schema, policy, role, or data changes are authorized by this checklist.

## Decisions needed from the school owner

1. **Initial profile assignments, especially the current System Admin**
   - Confirm which of the four departments the current System Admin belongs to, or explicitly confirm that the System Admin is intentionally unassigned.
   - Provide the department assignment for each existing profile before any backfill. Do not infer department membership from names, email addresses, or job titles.
   - The current read-only snapshot shows one profile and one System Admin assignment, but does not establish the correct department for that account.

2. **Unassigned users and registry visibility**
   - Decide whether a user without a department must be denied document access, or whether a specific, separately granted school-wide registry role exists.
   - School-wide visibility must be an explicit permission, not an automatic consequence of being authenticated or being System Admin unless the school explicitly approves that policy.

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
