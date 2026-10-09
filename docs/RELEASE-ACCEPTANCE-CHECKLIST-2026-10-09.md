# WBNS e-Document — Release Acceptance Checklist
Updated: 2026-10-09

Purpose: provide a repeatable, evidence-based acceptance checklist before the school treats the system as production-ready. This document is a test plan, not evidence that unchecked tests have passed.

## Safety and test prerequisites

- [ ] School owner approves the test window, test accounts, test cases, and expected role/department policy.
- [ ] Confirm the target is an isolated non-production project with no production data or credentials.
- [ ] Record the deployed commit, browser/device, test account role, date/time, result, and evidence for each test.
- [ ] Confirm an approved backup and a documented recovery procedure before any test that changes persistent data.
- [ ] Use synthetic test users/documents only in non-production. Do not place sensitive files or credentials in GitHub issues or commits.
- [ ] Never test last-admin protection by removing, demoting, or deactivating the existing Production `system_admin` assignment.

## A. Hosting and startup

- [x] User confirmed the site rendered again after the blank-screen incident and cache invalidation.
- [ ] Load the deployed site in a clean browser profile and verify there is no blank screen or uncaught startup error.
- [ ] Verify the React error boundary shows a recoverable Thai error screen for a controlled non-production render failure.
- [ ] Verify the service worker installs/updates and a new deployment does not leave the app stuck on stale assets.
- [ ] Verify refresh and direct navigation to each protected route behave as expected.

## B. Authentication and session

- [x] User confirmed sign-in works normally.
- [x] User confirmed password recovery was tested successfully.
- [ ] Test invalid credentials and ensure the UI shows a safe, understandable error.
- [ ] Test sign-out, session refresh, expired session, and protected-route redirect.
- [ ] Verify a user cannot access protected data after sign-out or session expiry.
- [ ] After an authorized operator enables leaked-password protection in Supabase Auth settings, verify the setting is enabled and record evidence. This setting is currently a known open security gate.

## C. Authorization and administration

- [ ] In non-production, test each role against an explicit permission matrix for allowed and denied actions.
- [ ] Verify a user with `user.manage` but without `role.manage` cannot call role-changing RPCs or assign roles.
- [ ] Verify only an authorized administrator can grant/revoke roles, activate/deactivate users, or import role assignments.
- [ ] Verify the system prevents removing or deactivating the final active `system_admin`, including concurrent requests.
- [ ] Verify every role, department, activation, and import change creates the intended audit event.
- [ ] Verify self-service profile updates cannot modify privileged fields or another user's profile.
- [ ] Confirm intended visibility for departments and other reference tables; document the approved policy.

**Production protection:** do not run negative/destructive role tests against Production. Never alter the existing Production `system_admin` assignment. The current production role-RPC and deployed `user-import` findings are source-review findings, not proof of an exploit; test only in an isolated target.

## D. Document lifecycle and scope

- [ ] Create an approved synthetic incoming document and verify register/numbering, required fields, creator, and timestamps.
- [ ] Create an outgoing document and verify the intended numbering and workflow.
- [ ] Test assignment, review/approval, status transitions, and invalid transitions.
- [ ] Verify users can view/update only documents allowed by their role and row-level scope.
- [ ] Verify due dates, reminders, and deadline updates enforce ownership/permission and status rules.
- [ ] Verify audit/history entries record the important lifecycle transitions.
- [ ] Verify list/search/filter/pagination and exports show only authorized records.

## E. Files and Google Drive

- [ ] Upload a non-sensitive test file and verify the stored Drive object is associated with the correct document.
- [ ] Download/open the file as an authorized user and verify unauthorized users are denied.
- [ ] Create a new file version and verify the correct document/version association.
- [ ] Test invalid file types/size limits and upload failures.
- [ ] Verify a file cannot be attached to an unrelated document by changing an identifier.
- [ ] Perform an isolated restore of a test file and document the result, retention, and ownership.

## F. Backup, recovery, and operations

- [ ] Reconcile repository migration files against authoritative applied-production migration records; do not replay historical migrations.
- [ ] Create a school-controlled database backup and restore it into an isolated target; record validation evidence.
- [ ] Confirm Google Drive retention, service-account ownership, and recovery procedure.
- [ ] Review Security Advisor findings and resolve each accepted risk through a reviewed, tested, approved change.
- [ ] Review Performance Advisor findings individually; do not drop unused indexes or rewrite RLS policies automatically.
- [ ] Confirm operational ownership for account recovery, staff onboarding/offboarding, incident response, and backups.

## G. Release decision

- [ ] All applicable tests above have recorded pass/fail results and evidence.
- [ ] No unresolved critical/high security issue remains without explicit written risk acceptance by the school owner.
- [ ] Migration parity, backup/restore, access-control tests, and operational ownership are verified.
- [ ] School owner signs off on the release.

Release status remains **NOT YET PRODUCTION READY** until the required gates above are evidenced and approved. A successful GitHub Actions build or deployment alone is not end-to-end acceptance.
