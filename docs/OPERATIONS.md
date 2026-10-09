# WBNS e-Document — Production Readiness Checklist

อัปเดต: 2026-10-09

เอกสารนี้ใช้ติดตามงานก่อนประกาศ Production Ready โดยแยกสิ่งที่ตรวจพบจากเครื่องมือออกจากสิ่งที่ต้องยืนยันโดยผู้ดูแลระบบโรงเรียน

## Verified from current tooling
- [x] Latest checked GitHub Pages workflow completed successfully (commit `15588bf6fca53b0bd1906b88562a16f50cbfab9c`).
- [x] Supabase Security Advisor was checked on 2026-10-09.
- [x] Operations/recovery procedure exists.
- [x] Production smoke-test checklist exists.
- [x] A read-only review found the production migration history and repository migration filenames cannot be reconciled by filename prefix alone.

## Open release gates — do not mark complete without evidence
- [ ] Map each production migration version/name to authoritative SQL and a repository file or document why it cannot be recovered.
- [ ] Verify live definitions, grants, search_path and permission checks for all 10 authenticated SECURITY DEFINER findings.
- [ ] Test RPC authorization using an admin account and a normal staff account, including denied cases.
- [ ] Confirm protection against removing/demoting the last active system administrator.
- [ ] Enable Supabase Auth leaked-password protection in project settings and verify password recovery with a school-controlled mailbox.
- [ ] Run login, user/role, incoming/outgoing workflow, Google Drive upload/versioning, audit, notification and PWA smoke tests.
- [ ] Create a school-controlled database backup and record the backup date, operator and secure storage location (never commit backup files or credentials).
- [ ] Restore the backup into an isolated non-production target and record the test result.
- [ ] Verify Google Drive backup/retention and restore procedure.
- [ ] Obtain school owner acceptance before declaring production ready.


- [x] Read-only role-admin review documented; no administrator role was removed. See [Role Administration Remediation Plan](ROLE-ADMIN-REMEDIATION-PLAN-2026-10-09.md).
- [ ] Obtain school owner confirmation of role delegation policy and establish a safe recovery path; live inspection found only one active `system_admin`.

## Security Advisor triage
The 10 authenticated SECURITY DEFINER findings are not automatically vulnerabilities. They require a function-by-function review because authenticated application clients use some of these RPCs. Do not revoke all authenticated EXECUTE grants indiscriminately.

Review at minimum:
- `admin_create_department`
- `admin_remove_user_role`
- `admin_set_user_department`
- `admin_set_user_role`
- `admin_update_department`
- `assign_document`
- `attach_document_file_version`
- `get_my_permissions`
- `set_document_deadline`
- `update_document_status`

For each function, record: live definition hash or reviewed SQL, owner, SECURITY DEFINER/INVOKER mode, fixed search_path, EXECUTE grants, permission gate, object-level authorization, allowed/denied test evidence and reviewer.

## Safe migration reconciliation
1. Export the exact production migration history and retrieve authoritative SQL for each entry.
2. Compare SQL semantics and live schema; version-prefix matching alone is insufficient.
3. Do not rename migrations to force a match, mark unknown migrations as applied, reset production, or replay historical SQL.
4. Resolve missing migration source from trusted deployment records; if unrecoverable, record the gap and design a forward-only baseline after review.
5. Any production schema change requires a verified backup, reviewed migration, school approval and post-change smoke tests.

## Backup and recovery
- Database backups must be created by a school-controlled operator using secure Supabase/PostgreSQL connection details.
- Store backup files in approved school-controlled secure storage, separate from GitHub.
- Restore only to an isolated recovery target during a drill.
- Validate profiles/roles, RLS, document metadata, workflow RPCs, audit records and Google Drive references before considering a restore successful.

## Release decision
Current status: **NOT YET PRODUCTION READY** until the open release gates above are evidenced and accepted by the school.
- [x] Added an end-to-end phase tracker with evidence and explicit blockers: [END-TO-END-PHASE-TRACKER-2026-10-09.md](END-TO-END-PHASE-TRACKER-2026-10-09.md). Documentation deployment for prior migration inventory commit succeeded; the phase tracker commit itself still needs its own workflow result checked.
