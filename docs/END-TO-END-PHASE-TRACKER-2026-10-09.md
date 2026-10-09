# WBNS e-Document — End-to-End Phase Tracker
Updated: 2026-10-09
Current release status: **NOT YET PRODUCTION READY**

This tracker separates tasks completed by direct evidence from tasks that require school-owned access, missing source artifacts, a non-production database, or a human acceptance test. “Complete” is never inferred from a plan or a successful documentation deployment.

## Safety invariant
**Do not remove, demote, deactivate, or alter the existing Production `system_admin` assignment during any phase.** The latest read-only query observed 1 active profile and 1 assignment for `system_admin`. No role assignment or Production schema was changed by this phase review.

## Phase status

| Phase | State | Evidence / exit condition |
|---|---|---|
| 1. Repository and hosting baseline | Partially verified | GitHub Actions deploy of docs commit `e087758444c688a3185a022fbe534e7e90136e74` completed successfully: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37892609349. This proves the workflow completed, not that browser-level app flows pass. |
| 2. Application/auth smoke tests | Pending human browser test | Login, password reset email, recovery link, reset completion, session refresh and route protection must be tested using a school-controlled mailbox/browser. Do not reuse any previously exposed access/refresh token. |
| 3. Authorization/RPC security | Open security gate | Security Advisor still reports 10 authenticated SECURITY DEFINER functions and leaked-password protection disabled. Live role RPCs are SECURITY DEFINER with fixed search_path; role policy/RPC mismatch and last-admin protection remain unresolved. See SECURITY-REVIEW-2026-10-09.md. |
| 4. Role-admin safe remediation | Design documented; implementation pending | Latest read-only count: 1 active system_admin profile / 1 assignment. Need second school-controlled recovery administrator and an isolated test target before implementing/testing a concurrency-safe guard. Never test by removing the existing assignment. |
| 5. Migration source/parity | Partial inventory only | Production reports 26 migration entries; repo has 21 SQL files. Some names map as candidates only; source for several base migrations is missing from current repo. Need authoritative applied SQL/deployment records before claiming parity. See MIGRATION-RECONCILIATION-INITIAL-INVENTORY-2026-10-09.md. |
| 6. Database backup and restore drill | Not evidenced | School-controlled operator must create a secure backup and restore it to an isolated target, recording validation evidence. Do not put backups or connection secrets in GitHub. |
| 7. Google Drive backup/recovery | Configuration partly verified; recovery pending | Service-account/root-folder configuration and functions are present. Need documented retention/ownership and an isolated file restore test using a non-sensitive test file. |
| 8. Workflow end-to-end acceptance | Pending | Test incoming/outgoing documents, approval/assignment/status transitions, due dates/reminders, file upload/versioning, audit trail, notification delivery and PWA cache behavior using approved test records only. |
| 9. School data and owner acceptance | Pending | Populate actual departments/staff only from school-approved source data; owner must sign off on role policy, records retention, backup, restore, and operational ownership. No synthetic real-world staff/document data should be inserted into Production. |
| 10. Production readiness decision | Blocked | Do not declare Production Ready until each release gate has evidence and school owner acceptance. |

## Current safe actions performed in this review
- Read current deployment workflow state and verified the documentation deployment completed successfully.
- Re-read Supabase Security Advisor and migration metadata.
- Re-queried active system administrator count read-only.
- Recorded live function-definition fingerprints and fixed search_path for role administration RPCs for review evidence.
- Confirmed no Supabase development branches currently exist. Creating one may incur cost and requires a cost-confirmation workflow; no branch was created.
- No Production role assignment, application data, schema, Auth settings, or migration history was modified.

## Blockers that cannot be truthfully marked complete by documentation
1. **Leaked-password protection** must be enabled in Supabase Auth project settings by an authorized operator and then verified.
2. **Migration reconciliation** needs authoritative SQL for applied Production migrations; the metadata listing alone does not contain migration bodies.
3. **Isolated testing** needs a non-production target. No branch currently exists; do not merge a branch to Production as a test.
4. **Backup/restore** needs a school-controlled backup artifact and isolated target.
5. **Browser/mail/Drive acceptance** requires actual school-controlled browser/mailbox/Drive interaction; deployment success is not a substitute.

## Release gate rule
Any remediation migration must be forward-only, reviewed against authoritative source, tested off Production, protected by a verified backup and recovery plan, and approved by the school owner. Never reset Production, replay historical migrations, fabricate migration history, or test by removing the last administrator.
