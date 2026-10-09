# Document Department Scope and File Authorization Design

Date: 2026-10-09  
Status: Design only — not applied to Production  
Related: PR #6 (Drive upload metadata persistence)

## Why this design is required

A read-only Production schema review confirmed:
- `profiles.department_id` exists.
- `documents` has no department scope column.
- `documents_select_authorized` currently allows a row when the user is the current owner, creator, **or** has `document.view`; the permission branch has no department predicate.
- `public.attach_document_file_version(uuid, uuid, text)` is SECURITY DEFINER and checks authentication, `document.update`, and existence, but does not enforce department scope itself.
- `google_drive_files` and `document_files` have SELECT policies only; upload metadata must not be written directly from the browser.

Therefore cross-department isolation is not verified. Do not represent PR #6 as fixing this issue.

## Target authorization model (proposal)

1. Add a nullable `documents.department_id` FK to `departments.id` in a reviewed migration. Keep it nullable during rollout to avoid inventing ownership for historical documents.
2. New document creation must assign the department from the authenticated user's trusted `profiles.department_id` inside a server-side database function/policy. Never accept a department from editable user metadata or trust a browser-supplied department as authority.
3. Existing documents with no department require a reviewed backfill mapping based on authoritative records. Do not blindly set all historical rows to the current user's department.
4. Define an explicit global-scope permission (proposal: `document.view_all_departments`) separately from ordinary `document.view`. Do not silently grant it to existing roles. System-admin treatment must follow the project's verified server-side admin predicate and must never remove or modify the sole existing System Admin assignment as part of testing.
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

- [ ] Department source-of-truth and transfer/reassignment semantics approved.
- [ ] Migration tested against a schema/data fixture matching Production.
- [ ] All expected and denied authorization tests pass.
- [ ] Existing document and workflow behavior has regression coverage.
- [ ] Upload MIME/type policy is explicitly chosen; extension alone is not trusted.
- [ ] CI passes on the final PR head.
- [ ] Backup/restore is tested and deployment approved.
- [ ] No Production deployment until every gate above is satisfied.

## Current state

This document is design-only. No SQL migration has been applied, no Production policy/role/data has been changed, and no live upload was attempted. Additional paid infrastructure spend remains 0 THB.
