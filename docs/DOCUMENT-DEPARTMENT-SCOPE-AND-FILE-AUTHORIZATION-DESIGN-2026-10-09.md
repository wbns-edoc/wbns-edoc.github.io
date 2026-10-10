# Document Department Scope and File Authorization Design

Date: 2026-10-10  
Status: Design only — not applied to Production  
Related: PR #6 (Drive upload metadata persistence)

## Authoritative school structure confirmed by owner

The school owner confirmed the exact organizational structure:

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

Use these names as the source of truth in design, UI, seed fixtures, and future migrations. In particular, use **กลุ่มบริหารงบประมาณ** (not กลุ่มบริการงบประมาณ).

The four groups above are document-scope units. ฝ่ายบริหาร is the central administrative unit and must not be silently treated as a fifth ordinary document department. Central-role profiles may have a null `profiles.department_id`; do not force them into one of the four workgroups to satisfy a schema assumption.

## Owner-approved visibility rule — 2026-10-10

The owner explicitly approved automatic read-all access across all documents for these two roles:
- System Admin
- ผู้อำนวยการโรงเรียน

This is **read access only**. It does not automatically grant approval, assignment, status transitions, document registration, role management, or other mutation rights.

Membership in ฝ่ายบริหาร alone does not grant read-all. In particular, รองผู้อำนวยการโรงเรียน, เจ้าหน้าที่สารบรรณ, and เจ้าหน้าที่ธุรการ must receive only the permissions and document scope explicitly approved for their work. Do not infer their access from a similar English role label or from central-unit membership. Map the existing database role labels to these Thai roles only through an explicitly reviewed mapping.

## Why this design is required

A read-only Production schema review confirmed:
- `profiles.department_id` exists.
- `documents` has no department scope column.
- `documents_select_authorized` currently allows creator, current owner, or anyone with `document.view`; the permission branch has no department predicate.
- `documents_update_authorized` allows creator/current owner or broad `document.update`, `document.assign`, or `document.approve` permissions without a department predicate.
- `document_files_authorized` checks whether a document row exists; whether that row is visible depends on document RLS, but the policy does not itself express file-specific scope.
- `google_drive_files_authorized` allows SELECT based on `document.view` without linking file metadata to a document scope.
- `public.attach_document_file_version(uuid, uuid, text)` is SECURITY DEFINER and checks authentication, `document.update`, and row existence, but does not enforce document scope itself or establish that the file metadata was uploaded by an authorized caller.
- `google_drive_files` and `document_files` have SELECT policies only; upload metadata must not be written directly from the browser.

Therefore cross-department isolation is not verified. Do not represent PR #6 as fixing this issue.

## Target authorization model (proposal)

1. Add a nullable `documents.department_id` FK to `departments.id` in a reviewed forward-only migration. Keep it nullable during rollout to avoid inventing ownership for historical documents or central workflows.
2. Seed the four document-scope groups with stable unique codes, and represent ฝ่ายบริหาร separately if the application needs it as an organizational grouping. Do not seed a fifth ordinary document department unless its data semantics are explicitly approved.
3. New document creation must assign scope from the authenticated user's trusted `profiles.department_id` inside a server-side database function. Never accept a department from editable user metadata or trust a browser-supplied department as authority.
4. For an authenticated central registry user with no department, registration must be explicitly denied or routed through a reviewed central-registry policy; never fabricate a department. The school has not yet approved all role-to-registration mappings.
5. Existing documents with no department require a reviewed backfill mapping based on authoritative records. Do not blindly set all historical rows to the current user's department.
6. Implement an explicit read-all predicate for the canonical System Admin and director role mappings. Test it in RLS and trusted read paths. Keep all mutation/workflow permissions separate. Role-name mapping must be reviewed against the live roles and user-role assignments before applying.
7. Within-department access must be enforced consistently for SELECT, UPDATE, RPC operations, file metadata, and attachment. Assignment/approval workflows may grant explicit document-level access only according to a separately reviewed rule; creator/owner status alone must not accidentally bypass department restrictions.
8. The file-attachment RPC must independently verify that the authenticated user may update the target document's scope, and that the file metadata row is eligible for attachment. A generic `document.update` permission alone is insufficient.
9. Use a single trusted authorization predicate/helper only after its semantics are reviewed. Any SECURITY DEFINER helper must have a fixed safe search_path, narrow EXECUTE grants, explicit auth checks, and allow/deny tests.
10. Upload metadata insertion stays server-side. Service-role credentials must never reach the browser. Cleanup after failure is best-effort and must be observable; an orphan-reconciliation procedure is required.

## Rollout sequence

1. Reconcile all 26 Production migration-history entries with committed SQL files. The current repository has a placeholder foundation migration and is not a reproducible clean migration set.
2. Recover the authoritative migration/schema source; do not reconstruct missing foundation DDL by guesswork.
3. Add tests and a schema-only migration proposal on a zero-cost disposable local/test database. Do not create a paid Supabase branch/project.
4. Review current `private.has_permission`, `private.is_admin`, role assignment semantics, all relevant RLS policies, and call sites before choosing exact SQL.
5. Add nullable department linkage and scope-aware policies/functions without changing Production data.
6. Backfill only from verified source-of-truth mappings; quantify unresolved legacy rows.
7. Run authorization regression tests and Supabase Security Advisor. Compare advisor output with baseline and explain new warnings.
8. Take/verify a restorable backup and obtain explicit deployment approval before applying any Production migration.
9. Deploy the Edge Function only after schema compatibility and upload integration tests pass. Test cleanup failure and audit logs.

## Required authorization tests

| Actor / condition | Operation | Expected result |
|---|---|---|
| Unauthenticated | Read document / call attachment RPC | Denied |
| User in workgroup A | Read document in workgroup A with normal access | Allowed |
| User in workgroup A | Read document in workgroup B without explicit grant | Denied |
| System Admin | Read documents from all four workgroups | Allowed |
| ผู้อำนวยการโรงเรียน | Read documents from all four workgroups | Allowed |
| รองผู้อำนวยการโรงเรียน | Cross-workgroup read without an approved grant | Denied |
| เจ้าหน้าที่สารบรรณ or เจ้าหน้าที่ธุรการ | Cross-workgroup read without an approved grant | Denied |
| System Admin or director with read-all only | Approve/change status/update document | Denied unless separately granted and workflow permits |
| User with only `document.view` | Attach a file to a document in another workgroup | Denied |
| User assigned to a document in another workgroup | Read/act on that document | Only explicitly approved assignment actions allowed |
| User with `document.update` but no target-document scope | Attach a valid file | Denied |
| User with scope but unrelated file metadata | Attach file | Denied unless explicitly authorized by the reviewed design |
| Two simultaneous uploads to same document/role | Attach versions | One unique current version; no duplicate version numbers |
| Metadata insert failure | Upload | Drive object cleanup attempted; no attachment row |
| Attachment RPC returns error/zero rows | Upload | Cleanup attempted; no false success response |
| Cleanup API fails | Upload | Failure response, safe logs, orphan discoverable for remediation |
| Legacy document with unresolved department | Read/write/attach | Follows explicitly approved migration policy; never silently broad-access |
| Sole existing System Admin | Admin access regression | Remains able to sign in and administer; no role mutation in tests |

## Acceptance gates

- [x] Owner supplied the exact organizational structure above.
- [x] Owner confirmed System Admin and ผู้อำนวยการโรงเรียน must automatically read all documents.
- [ ] Canonical live role IDs/codes mapped to the Thai role names and reviewed.
- [ ] Initial staff-to-workgroup mapping is approved.
- [ ] Remaining permissions for เจ้าหน้าที่สารบรรณ, เจ้าหน้าที่ธุรการ, and รองผู้อำนวยการโรงเรียน are explicitly mapped; no blanket read-all is inferred.
- [ ] Department transfer/reassignment and cross-workgroup delegation semantics approved.
- [ ] Migration source reconciled and migration tested against a schema fixture matching Production.
- [ ] All expected and denied authorization tests pass.
- [ ] Existing document and workflow behavior has regression coverage.
- [ ] Upload MIME/type policy is explicitly chosen; extension alone is not trusted.
- [ ] CI passes on the final PR head.
- [ ] Backup/restore is tested and deployment approved.
- [ ] No Production deployment until every required gate above is satisfied.

## Current state

This document is design-only. No SQL migration has been applied, no Production policy/role/data has been changed, and no live upload was attempted. Additional paid infrastructure spend remains 0 THB.

## Follow-up verification — 2026-10-09 and 2026-10-10

Read-only rechecks confirmed the scope blocker remains:
- Production snapshot: 1 profile, 0 departments, 0 documents, and exactly 1 System Admin assignment. These counts are a snapshot, not a substitute for backup or restore testing.
- The live `documents_select_authorized` policy includes `private.has_permission('document.view')` without a department predicate.
- The live `document_files` and `google_drive_files` policies remain SELECT-only. No broad browser INSERT policy was added.
- The Edge Function checks global `document.update` permission and reads the target document through the user's JWT, but the schema has no document department column. This cannot establish department-level authorization; the attachment RPC must enforce scope independently once the model is implemented.
- Security Advisor reports 10 `authenticated_security_definer_function_executable` warnings and 1 `auth_leaked_password_protection` warning. These remain separate release gates; do not bulk-revoke EXECUTE without function-by-function dependency and regression tests.
- Both `private.register_incoming_document(...)` and `private.register_outgoing_document(...)` insert into `public.documents` without a department scope field.
- `public.assign_document(...)` checks global `document.assign`, document existence, and active assignee but does not check workgroup membership or explicit cross-workgroup delegation.
- The current document SELECT policy also permits creator/current-owner access independently of the global `document.view` branch. A future policy must define whether those relationships remain valid across a workgroup transfer; it must not accidentally preserve access to the former workgroup.
- Production currently has zero department rows. Central-role users may have no department, so a migration requiring every profile to have a non-null department is unsafe.
- CI for the upload branch has passed frontend build and Deno type checks, but this is not an authorization integration test or live Drive upload test.

## Creation-path and delegation tests

| Scenario | Expected result |
|---|---|
| Incoming registration by active user with an approved workgroup | Server assigns that trusted workgroup ID |
| Outgoing registration by active user with an approved workgroup | Server assigns that trusted workgroup ID |
| Registration by user with no workgroup | Denied or handled by an explicitly approved central-registry policy |
| Browser submits a different workgroup ID | Ignored or rejected; trusted profile is authoritative |
| User in workgroup A assigns a document to a user in workgroup B | Denied unless separately approved delegation allows it |
| Creator or current owner changes workgroup | Access follows explicit transfer policy; old workgroup access is not retained accidentally |
| Workgroup is deactivated | Registration/assignment follows explicit policy; existing records remain auditable |
| File metadata was created for another document/upload | Attachment denied unless a verified ownership/linking rule allows it |

## Upload compensation race review

An attachment RPC can commit in the database while the caller receives an error or loses the response. Deleting the Google Drive object solely because the client saw an RPC error could leave a valid attachment row pointing at a deleted file.

The upload branch was updated to query `document_files` through the server-side client before compensating an upload. It preserves the Drive object and metadata if attachment state cannot be determined, or if metadata is already referenced. It also preserves the Drive object if metadata deletion fails. This deliberately prefers a reconcilable orphan/uncertain result over destroying a potentially attached document file.

This is a defensive code-path change, not proof that the race has been reproduced or that cleanup works against the live Google Drive account. Tests should cover attachment committed but response lost; attachment lookup failure; metadata deletion failure; Drive delete failure; and normal cleanup after a confirmed no-attachment result.
