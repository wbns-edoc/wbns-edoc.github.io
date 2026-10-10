# Document Department Scope and File Authorization Design

Date: 2026-10-09  
Status: Design only — not applied to Production  
Related: PR #6 (Drive upload metadata persistence)

## Authoritative department names received

The school owner supplied the following four department names for the proposed department master list:

1. กลุ่มบริหารงานวิชาการ
2. กลุ่มบริการงบประมาณ
3. กลุ่มบริหารงานบุคคล
4. กลุ่มบริหารงานทั่วไป

These names are accepted as the source list for design and test fixtures. They have **not** been inserted into Production. The school owner clarified that System Admin, เจ้าหน้าที่ธุรการ, ผู้อำนวยการสถานศึกษา, and รองผู้อำนวยการสถานศึกษา are central roles, not members of these four departments, and sit above/across them. These central-role profiles should not be forced into a department merely to satisfy a schema assumption; their individual permissions must still be defined by role.

## Why this design is required

A read-only Production schema review confirmed:
- `profiles.department_id` exists.
- `documents` has no department scope column.
- `documents_select_authorized` currently allows a row when the user is the current owner, creator, **or** has `document.view`; the permission branch has no department predicate.
- `public.attach_document_file_version(uuid, uuid, text)` is SECURITY DEFINER and checks authentication, `document.update`, and existence, but does not enforce department scope itself.
- `google_drive_files` and `document_files` have SELECT policies only; upload metadata must not be written directly from the browser.

Therefore cross-department isolation is not verified. Do not represent PR #6 as fixing this issue.

## Owner-approved visibility rule — 2026-10-10

The owner confirmed that **System Admin and ผู้อำนวยการสถานศึกษา must be able to read all school documents automatically**, across all four departments. Implement this as an explicit role-based school-wide read grant, consistently enforced in RLS and trusted read paths and covered by allow/deny tests. Do not implement it as an unrestricted admin bypass.

This is a read-only visibility decision. It does not automatically grant System Admin permission to register, assign, approve, issue commands, void records, or bypass workflow. The director's workflow mutations remain subject to the specific permissions and state transitions approved for those actions. เจ้าหน้าที่ธุรการ and รองผู้อำนวยการสถานศึกษา do not receive blanket all-document read access from this decision. All four roles remain central and must not be assigned to a department just to satisfy a schema assumption.

## Target authorization model (proposal)

1. Add a nullable `documents.department_id` FK to `departments.id` in a reviewed migration. Keep it nullable during rollout to avoid inventing ownership for historical documents.
2. New document creation must assign the department from the authenticated user's trusted `profiles.department_id` inside a server-side database function/policy. Never accept a department from editable user metadata or trust a browser-supplied department as authority.
3. Existing documents with no department require a reviewed backfill mapping based on authoritative records. Do not blindly set all historical rows to the current user's department.
4. Define explicit global-scope permissions separately from ordinary `document.view`. Add an auditable all-document **read** grant for System Admin and the director as approved by the owner. Keep their mutation/workflow permissions separate. Model central roles independently from `profiles.department_id`: System Admin (technical administration plus approved global read), เจ้าหน้าที่ธุรการ (registry operations subject to approved scope), ผู้อำนวยการสถานศึกษา (global read plus separately authorized director workflow actions), and รองผู้อำนวยการสถานศึกษา (delegated actions and visibility subject to explicit approval). Never remove or modify the sole existing System Admin assignment as part of testing.
5. Within-department access should be enforced consistently for SELECT, UPDATE, RPC operations, file metadata, and attachment. Assignment/approval workflows may grant explicit document-level access, but the exact rules must be specified and tested; creator/owner status alone must not accidentally bypass department restrictions.
6. The file-attachment RPC must independently verify that the authenticated user may update the target document's scope, and that the file metadata row is eligible for attachment. A generic `document.update` permission alone is not sufficient.
7. Use a single trusted authorization predicate/helper only after its semantics are reviewed. Any SECURITY DEFINER helper must have a fixed safe search_path, narrow EXECUTE grants, explicit auth checks, and tests for both allowed and denied paths.
8. Upload metadata insertion stays server-side. Service-role credentials must never reach the browser. Cleanup after failure is best-effort and must be observable; an orphan-reconciliation procedure is required.

## Rollout sequence

1. Add tests and a schema-only migration proposal on a non-production local/test database if one is available at zero additional cost. Do not create a paid Supabase branch/project.
2. Review the current `private.has_permission`, `private.is_admin`, assignment/approval semantics, all relevant RLS policies, and all call sites before choosing exact SQL.
3. Add nullable department linkage and scope-aware policies/functions without changing current production data.
4. Backfill only from verified source-of-truth mappings; quantify unresolved legacy rows.
5. Run authorization regression tests and Supabase Security Advisor. Compare advisor output with the baseline and explain any new warnings.
6. Take/verify a restorable backup and obtain explicit deployment approval before applying any Production migration.
7. Deploy the Edge Function only after schema compatibility and upload integration tests pass. Test cleanup failure and audit logs.

## Required authorization tests

| Actor / condition | Operation | Expected result |
|---|---|---|
| Unauthenticated | Read document / call attachment RPC | Denied |
| Authenticated user in department A | Read document in department A with normal access | Allowed |
| Authenticated user in department A | Read document in department B without explicit grant | Denied |
| Authenticated user in department A with only `document.view` | Attach file to document in department B | Denied |
| User assigned to a document in department B | Read/act on that document | Only the explicitly approved assignment actions allowed |
| User with reviewed global-scope permission | Cross-department read | Allowed, audited |
| User with `document.update` but no target-document scope | Attach a valid file | Denied |
| User with scope but file metadata owned/created by another unrelated upload | Attach file | Denied unless explicitly authorized by design |
| Two simultaneous uploads to same document/role | Attach versions | One unique current version; no duplicate version numbers |
| Metadata insert failure | Upload | Drive object cleanup attempted; no attachment row |
| Attachment RPC returns error/zero rows | Upload | Metadata and Drive cleanup attempted; no success response |
| Cleanup API fails | Upload | Failure response, safe logs, orphan is discoverable for remediation |
| Legacy document with unresolved department | Read/write/attach | Follows explicitly approved migration policy; never silently broad-access |
| Sole existing System Admin | Admin access regression | Remains able to sign in and administer; no role mutation in tests |

## Acceptance gates

- [x] School owner supplied the four department names for the design/test master list.
- [x] Owner confirmed the four central roles are above/across the four departments and are not department members.
- [ ] Confirm the initial role assignments for each existing profile and the remaining action/visibility rules for เจ้าหน้าที่ธุรการ and รองผู้อำนวยการสถานศึกษา.
- [ ] Department transfer/reassignment and cross-department delegation semantics approved.
- [ ] Migration tested against a schema/data fixture matching Production.
- [ ] All expected and denied authorization tests pass.
- [ ] Existing document and workflow behavior has regression coverage.
- [ ] Upload MIME/type policy is explicitly chosen; extension alone is not trusted.
- [ ] CI passes on the final PR head.
- [ ] Backup/restore is tested and deployment approved.
- [ ] No Production deployment until every gate above is satisfied.

## Current state

This document is design-only. No SQL migration has been applied, no Production policy/role/data has been changed, and no live upload was attempted. Additional paid infrastructure spend remains 0 THB.

## Follow-up verification — 2026-10-09

A read-only recheck after the upload-flow change confirmed the same scope blocker remains:
- Production still has 1 profile, 0 departments, 0 documents, and exactly 1 System Admin assignment. These counts are a snapshot, not a substitute for backup or restore testing.
- The live `documents_select_authorized` policy still includes `private.has_permission('document.view')` without a department predicate.
- The live `document_files` and `google_drive_files` policies remain SELECT-only. No broad browser INSERT policy was added.
- The Edge Function currently checks the global `document.update` permission and reads the target document through the user's JWT, but the schema has no document department column. This cannot establish department-level authorization; the attachment RPC must enforce scope independently once the model is implemented.
- Security Advisor still reports 10 `authenticated_security_definer_function_executable` warnings and 1 `auth_leaked_password_protection` warning. These remain separate release gates; do not bulk-revoke EXECUTE without function-by-function dependency and regression tests.
- GitHub Actions run [37951788240](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37951788240) completed successfully for the latest PR head checked at the time: frontend build with placeholder configuration and Deno type-check. This does **not** constitute an authorization integration test or a live Drive upload test.

No Production schema, policy, user role, or document data was changed during this recheck. No Supabase branch/project was created; additional infrastructure spend remains 0 THB.

## Creation-path and authorization-function inspection — 2026-10-09

Read-only inspection of the live function definitions identified the creation paths that a future scope migration must update:
- `private.register_incoming_document(...)` inserts into `public.documents` without a department value.
- `private.register_outgoing_document(...)` also inserts without a department value.
- The public `register_incoming_document` and `register_outgoing_document` functions are invoker wrappers that delegate to those private implementations.
- The live `public.attach_document_file_version(...)` checks authentication and the global `document.update` permission, and checks that both rows exist. It does not verify document department, file uploader/creator eligibility, or a document-specific grant.
- The live `public.assign_document(...)` checks `document.assign`, document existence, and active assignee, but does not check department membership or explicit cross-department delegation.
- The current document SELECT policy also permits the creator or current owner independently of the global `document.view` branch. A future policy must define whether those relationships remain valid across a department transfer; it must not accidentally preserve access to the former department.

Production currently has zero department rows. Central-role users are intentionally outside the four department groups, so the authorization model must allow profiles with no department while granting explicitly assigned central-role permissions. A migration that requires every profile to have a non-null department is not safe. Use the four supplied names and role-specific central fixtures to build a zero-cost test fixture. Since Production has zero documents at this snapshot, no historical-document backfill is currently indicated, but this must be rechecked immediately before any migration.

### Additional tests required for creation and delegation

| Scenario | Expected result |
|---|---|
| Incoming registration by active user with an approved department | Document receives that trusted department ID from the server-side profile |
| Outgoing registration by active user with an approved department | Document receives that trusted department ID from the server-side profile |
| Registration by user with no department | Explicitly denied or routed through a documented school-wide registry policy; never silently assigned a fabricated department |
| Browser submits a different department ID | Ignored or rejected; server-side profile is authoritative |
| User in department A assigns document to user in department B | Denied unless a separately approved delegation/cross-department rule permits it |
| Creator or previous owner changes department | Access follows explicit transfer policy; old department access is not retained by accident |
| Department is deactivated | Registration/assignment behavior follows an explicit policy; existing records remain auditable |
| File metadata was created for another document/upload | Attachment denied unless a verified ownership/linking rule explicitly allows it |

### Implementation constraint

Do not implement the scope rules as a frontend-only filter. The same trusted predicate must be enforced in database RLS and every SECURITY DEFINER RPC that reads or mutates documents or file links. Before replacing live functions, compare the complete current function definitions and dependencies against repository migrations; migration-name parity is known to be incomplete. Test the exact SQL against a safe fixture before any Production approval.

## Owner-approved read scope recorded — 2026-10-10

The owner approved automatic all-document read access for System Admin and the director. This document records the intended design only. Production RLS, grants, RPCs, and application behavior have not been changed by this approval. Release gates, migration-source reconciliation, tests, backup/restore, and explicit deployment approval remain mandatory.

## Upload compensation race review — 2026-10-09

A code review of `drive-upload` identified a failure mode worth guarding: an attachment RPC can commit in the database while the caller receives an error or loses the response. Deleting the Google Drive object solely because the client saw an RPC error could then leave a valid attachment row pointing at a deleted file.

The upload branch was updated to query `document_files` through the server-side client before compensating an upload. It now preserves the Drive object and metadata if the attachment state cannot be determined, or if the metadata is already referenced. It also preserves the Drive object if metadata deletion fails. This deliberately prefers a reconcilable orphan/uncertain result over destroying a potentially attached document file.

This is a defensive code-path change, not proof that the race has been reproduced or that cleanup works against the live Google Drive account. CI must pass, and tests should cover: attachment committed but response lost; attachment lookup failure; metadata deletion failure; Drive delete failure; and normal cleanup after a confirmed no-attachment result.
