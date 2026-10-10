# Production Readiness Gate — WBNS e-Document
**Project:** ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส  
**Checked:** 2026-10-10  
**Status:** BLOCKED — review plan only; no Production schema/data changed by this document.

## Verified live snapshot (read-only)

- Supabase project `wbns-edoc`, PostgreSQL 17, status ACTIVE_HEALTHY.
- 26 migrations are recorded in the live migration history.
- The inspected public business tables have RLS enabled.
- Current counts: 1 profile, 1 active profile, 0 departments, 0 documents, 1 assignment to the exact `System Admin` role.
- The current `documents_select_authorized` policy permits `document.view` users to read documents without a department predicate; creator/current-owner clauses also independently grant visibility.
- The public workflow functions `assign_document`, `set_document_deadline`, and `update_document_status` are SECURITY DEFINER and EXECUTE-granted to `authenticated`. Matching private implementations also exist and are SECURITY DEFINER. `create_approval` and `decide_approval` are SECURITY INVOKER.
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
- The school has explicitly approved automatic read-all access for **System Admin** and **ผู้อำนวยการโรงเรียน** only.
- Do not infer read-all, approval, or mutation rights for รองผู้อำนวยการโรงเรียน, เจ้าหน้าที่สารบรรณ, or เจ้าหน้าที่ธุรการ from their unit membership alone. Their access must follow explicitly assigned permissions and workflow rules.
- Read-all is a read capability only; it does not automatically grant approval, assignment, status-transition, role-management, or other mutation rights.
- Do not remove, demote, deactivate, or replace the final active System Admin.
- No staff profile-to-department mapping has been approved in the live database yet; do not infer it from the current empty department table.

## Owner-approved access requirement

- System Admin and ผู้อำนวยการโรงเรียน must automatically be able to read every document across ฝ่ายบริหาร and all four กลุ่มบริหาร.
- Department-based restrictions for ordinary users must not override this read-all rule.
- Users in the other roles and groups must be restricted to their approved department scope, active assignments, ownership, or designated workflow access, subject to the final reviewed policy.
- Read access to a document must govern access to its file metadata, file versions, and Drive download path as well; knowing a URL must not bypass authorization.

## Required remediation work

### 1. Authorization model and document/file scope

- Seed the five confirmed organizational units using stable identifiers and unique constraints; ensure migrations are repeatable and safe for an existing database.
- Approve and record the initial assignment of each staff profile to the correct unit before enforcing ordinary-user scope.
- Add document scope in a forward-only migration after that mapping is approved; update both trusted incoming and outgoing registration paths.
- Define an explicit authorization helper/policy that grants read-all to System Admin and ผู้อำนวยการโรงเรียน, and limits other users to approved department scope, active assignments, ownership, or designated workflow access.
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

- Identify the canonical role using a verified stable identifier or exact approved role mapping.
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

- [ ] Five organizational units match the school-approved structure above.
- [ ] Initial staff-to-unit mapping is approved and recorded.
- [ ] System Admin and ผู้อำนวยการโรงเรียน read-all tests pass across all document types and files.
- [ ] Other roles do not gain read-all or mutation privileges merely from belonging to ฝ่ายบริหาร.
- [ ] Ordinary cross-department read and mutation attempts are denied unless explicitly authorized.
- [ ] Sensitive public RPC wrappers and ACL regression tests pass.
- [ ] Last-active-System-Admin protection passes sequential and concurrency tests.
- [ ] Full migration replay and upgrade-from-snapshot pass.
- [ ] CI is green on the exact release commit.
- [ ] Google Drive integration tests pass in non-Production.
- [ ] Backup and restore are demonstrated.
- [ ] Security Advisor blockers are resolved or explicitly risk-accepted by the owner.
- [ ] Release owner approves the deployment plan and rollback procedure.

## Safety decision

Do not deploy this remediation directly to Production until it has been generated and tested in an isolated local/test environment, reviewed, backed up, and explicitly approved. No additional paid Supabase project or branch should be created solely for this gate. No Production mutation is performed by this document.
