# Production Readiness Gate — WBNS e-Document
**Project:** ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส  
**Checked:** 2026-10-10  
**Status:** BLOCKED for general rollout — partial remediation is live; full operational acceptance is still pending.

## Verified live snapshot (read-only)

- Supabase project `wbns-edoc`, PostgreSQL 17, status ACTIVE_HEALTHY.
- 26 migrations are recorded in the live migration history.
- The inspected public business tables have RLS enabled.
- Current counts (2026-10-10): 1 active profile, 1 active System Admin assignment, 4 active document-scope departments, 2 active registers, 0 documents, and 0 active sender-directory entries. The public frontend deploy workflow completed successfully for commit `a821e640cca72811ce7406e67060161997dec881`.
- Read-only role catalogue: canonical codes `system_admin` and `director` exist; `system_admin` has 1 assigned user and `director` has 0 assigned users in this snapshot. Other seeded codes are `deputy_director`, `registry_officer`, `school_admin`, `staff`, and `teacher`. Do not auto-map or grant permissions to the other codes based on name similarity.
- The current `documents_select_authorized` policy delegates visibility to `private.can_access_document(id)`; department-scope and automatic System Admin/director read access have been added and passed isolated regression tests.
- The public workflow entry points `assign_document`, `set_document_deadline`, and `update_document_status` are now SECURITY INVOKER wrappers; the isolated Workflow RPC Security CI passes. `create_approval` and `decide_approval` remain SECURITY INVOKER.
- `attach_document_file_version` is SECURITY DEFINER and callable by `authenticated`; its implementation must be reviewed for document scope and attachment ownership.
- The Security Advisor also reports public SECURITY DEFINER functions for role/department administration and permission lookup. Do not broadly revoke grants without validating application dependencies.

These facts are blockers, not evidence that the system is ready for general use. Counts do not establish the approved organizational structure or user-to-department mapping.

## Owner-approved organizational structure

The school has confirmed the following structure; use these exact names in the implementation and UI:

1. **ฝ่ายบริหาร**
   - System Admin
   - ผู้อำนวยการโรงเรียน
   - รองผู้อำนวยการโรงเรียน
   - เจ้าหน้าที่สารบรรณ
   - เจ้าหน้าที่ธุรการ
2. **กลุ่มบริหารงบประมาณ**
3. **กลุ่มบริหารงานวิชาการ**
4. **กลุ่มบริหารงานบุคคล**
5. **กลุ่มบริหารงานทั่วไป**

Important modeling rules:
- Treat ฝ่ายบริหาร as the central administrative unit and the four named กลุ่มบริหาร as separate document-scope units.
- The school has explicitly approved automatic cross-department document read access for **System Admin** and **ผู้อำนวยการโรงเรียน**.
- The school has now also explicitly approved automatic **document approval and document editing** permissions for these two roles. Grant these through the stable role codes `system_admin` and `director`; do not require per-user permission assignment for those capabilities.
- This approval/editing grant is limited to document approval and editing. Do not infer assignment, archive, completion, role-management, user-management, or other mutation rights for the director unless separately assigned.
- Do not infer read-all or mutation rights for รองผู้อำนวยการโรงเรียน, เจ้าหน้าที่สารบรรณ, or เจ้าหน้าที่ธุรการ from their unit membership alone. Their access must follow explicitly assigned permissions and workflow rules.
- Do not remove, demote, deactivate, or replace the final active System Admin.
- No staff profile-to-department mapping has been approved in the live database yet; do not infer it from the current empty department table.

## Owner-approved access requirement

- System Admin and ผู้อำนวยการโรงเรียน must automatically be able to read, approve, and edit every document across ฝ่ายบริหาร and all four กลุ่มบริหาร, through role-level permissions.
- Department-based restrictions for ordinary users must not override these approved capabilities for these two roles.
- Production now grants `document.view`, `document.approve`, and `document.update` to both role codes `system_admin` and `director`; the director role has not been assigned to any user.
- This is a role permission change only; do not assign the `director` role to any user automatically.
- Users in the other roles and groups must be restricted to their approved department scope, active assignments, ownership, or designated workflow access, subject to the final reviewed policy.
- Read access to a document must govern access to its file metadata, file versions, and Drive download path as well; knowing a URL must not bypass authorization.

## Required remediation work

### 1. Authorization model and document/file scope

- Seed the four confirmed document-scope groups using stable identifiers and unique constraints. Represent ฝ่ายบริหาร as a central administrative unit/organizational grouping, not as an ordinary document-scope department unless a distinct scope requirement is approved. Ensure migrations are repeatable and safe for an existing database.
- Approve and record the initial assignment of each staff profile to the correct unit before enforcing ordinary-user scope.
- Add document scope in a forward-only migration after that mapping is approved; update both trusted incoming and outgoing registration paths.
- Define an explicit authorization helper/policy that grants read-all, approval, and document editing to System Admin and ผู้อำนวยการโรงเรียน, and limits other users to approved department scope, active assignments, ownership, or designated workflow access. Approval/editing must still respect valid workflow transitions and audit logging.
- Ensure file metadata, file-version attachment RPCs, Drive upload/download paths, assignment RPCs, and related history use the same document authorization rule.
- Explicitly test that creator/current-owner visibility does not retain access after an authorized transfer.
- Keep Drive URLs and metadata inaccessible to users who cannot read the parent document.

### 2. Public workflow RPC hardening

Before changing function signatures or grants, verify exact live signatures, defaults, dependencies, and ACLs. Create the migration with the Supabase CLI in a local checkout, replay it against a disposable local database, and review the resulting SQL.

- Convert public workflow entry points to SECURITY INVOKER wrappers that delegate only to their corresponding private implementation, if the local test proves the wrapper can safely invoke the private function.
- Verify private implementations independently check `auth.uid()`, permission, document scope, active target user, and valid state transition.
- Verify `anon` and PUBLIC cannot execute sensitive entry points, and intended authenticated callers can.
- Keep `create_approval` and `decide_approval` SECURITY INVOKER and assert this invariant in CI.
- Review each remaining public SECURITY DEFINER function individually; do not treat all such functions as equivalent.

### 3. Protect the last System Admin

- Use the verified stable role codes `system_admin` and `director` for the two approved read-all roles, after validating exact live function/policy semantics. The live catalogue currently shows zero users assigned to `director`; do not assign any user automatically.
- Serialize concurrent role-removal/deactivation operations with a transaction-scoped lock or equivalent.
- Reject any change that would leave no active System Admin; test sequential and concurrent attempts in a disposable database.
- Never test destructive last-admin cases against the live Production account.

### 4. Reconcile migrations and release evidence

- Reconcile the 26 live migration records with committed migration files and confirm a clean replay from an empty local database.
- Add repeatable catalog/ACL/RLS regression checks to CI and verify they fail against known-bad states.
- Run frontend build, Edge Function tests, workflow/RPC tests, role-based RLS tests, and file authorization tests.
- Test real Drive upload, attachment, failed-upload cleanup, and unauthorized access with test accounts in a non-Production environment.
- Verify a recoverable backup and a successful restore drill; record timestamps and evidence.
- Confirm Auth leaked-password protection and review password/session policies before general rollout.

## Release gate (all required)

- [x] Four document-scope groups match the school-approved names; ฝ่ายบริหาร remains separate from the four document-scope groups.
- [ ] Initial staff-to-unit mapping is approved and recorded.
- [x] `system_admin` and `director` role-level `document.view`, `document.approve`, and `document.update` grants pass isolated catalogue regression tests; no user is assigned the director role automatically. Full real-file cross-role testing remains pending.
- [ ] Other roles do not gain read-all or mutation privileges merely from belonging to ฝ่ายบริหาร.
- [ ] Ordinary cross-department read and mutation attempts are denied unless explicitly authorized.
- [x] Sensitive public workflow RPC wrapper and ACL regression tests pass in isolated CI.
- [ ] Last-active-System-Admin role-removal guard passes the isolated sequential regression test; concurrency and account-deactivation paths still require verification.
- [ ] Full migration replay and upgrade-from-snapshot pass.
- [ ] CI is green on the exact release commit.
- [ ] Google Drive integration tests pass in non-Production.
- [ ] Backup and restore are demonstrated.
- [ ] Security Advisor blockers are resolved or explicitly risk-accepted by the owner.
- [ ] Release owner approves the deployment plan and rollback procedure.

## Safety decision

Do not deploy this remediation directly to Production until it has been generated and tested in an isolated local/test environment, reviewed, backed up, and explicitly approved. No additional paid Supabase project or branch should be created solely for this gate. No Production mutation is performed by this document.

## Owner decision update — 2026-10-10

The owner has superseded the earlier read-only-only interpretation: **System Admin and the director role automatically receive document read, approval, and editing permissions.** This grants `document.approve` and `document.update` at the role-permission layer, not by assigning the director role to any individual account. `system_admin` already has these permissions in the live role-permission snapshot; `director` already has `document.view` and `document.approve`, and requires the additive `document.update` mapping.

The role-permission migration is applied in Production and the isolated regression test passes. Production hardening also now scopes document visibility by department and protects removal of the final active System Admin role. Remaining release blockers include complete migration-source reconciliation, real Google Drive integration/authorization tests, backup/restore evidence, Security Advisor review, and last-admin deactivation/concurrency checks.