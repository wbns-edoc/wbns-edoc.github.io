# Follow-up: Drive Upload Authorization and RLS Evidence — 2026-10-09

## Scope
Reviewed `supabase/functions/drive-upload/index.ts` on branch `security/release-gate-review-2026-10-09`. Queried live `information_schema.role_table_grants` and `pg_policies` for `public.google_drive_files`. Read-only review only.

No production settings, database objects, credentials, or files were changed. No upload was attempted and no tests were run.

## Confirmed source flow
The Edge Function:
1. Requires a Bearer token and validates the caller with `sb.auth.getUser()`.
2. Requires `document.update` via `get_my_permissions`.
3. Looks up the document through the caller-scoped Supabase client.
4. Uploads a multipart file to Google Drive using server-side service-account configuration.
5. Returns Drive metadata to the browser. It does not insert `google_drive_files` metadata or attach a document-file version itself.

The frontend then inserts the returned metadata into `google_drive_files` directly from the browser and calls `attach_document_file_version`.

## Live database evidence
- RLS is enabled on `public.google_drive_files`.
- The returned policy inventory contains a SELECT policy, `google_drive_files_authorized`, requiring `private.has_permission('document.view')`; no INSERT policy appeared in that inventory.
- `information_schema.role_table_grants` reports INSERT and other table privileges for `anon` and `authenticated`, among other roles. SQL table grants do not override RLS, so the presence of INSERT privilege does not make the browser insert pass RLS.
- The policy/grant queries were read-only. No attempt was made to bypass or experimentally test policy enforcement.

## Risk assessment
**High-priority functional/integrity risk:** if the returned policy inventory is complete, the browser's metadata INSERT is expected to be rejected by RLS. Since the Edge Function has already uploaded the binary and has no compensation/cleanup step, a failed metadata insert can leave an orphaned Drive file. This is strongly indicated by source plus catalog evidence, but remains unconfirmed by an integration test.

**Authorization design:** the Edge Function checks a general `document.update` permission and uses the caller-scoped client to look up the document, which lets RLS participate in document visibility. Still verify whether the intended policy should also require explicit document-level ownership/scope, whether inactive profiles are rejected by `get_my_permissions`, and whether the upload action should be allowed for every user holding `document.update`.

**File validation:** source enforces a 25 MiB maximum and rejects empty files, but does not visibly enforce a MIME allowlist. Decide the school's allowed formats and validate file type/content server-side if policy requires it.

## Recommended safe fix
Prefer moving the full workflow into an authenticated server-side function:
- validate caller identity, active status, permission, and document-level authorization;
- enforce allowed size/type and generate a safe storage name;
- upload to Drive;
- write the metadata and attach the version through a narrow server-controlled path;
- on any later-stage failure, delete the newly created Drive object or enqueue a reliable cleanup task;
- make retries idempotent and log safe correlation IDs without logging secrets.

Do not solve this by adding a broad `INSERT` policy for `anon` or all authenticated users. Keep service-account credentials server-side. Test only in isolated non-production with synthetic documents/files.

## Release checklist
- [ ] Confirm full policy set and whether any policy is conditional or role-specific beyond the query results.
- [ ] Add isolated integration tests for successful upload, denied user, inaccessible document, unsupported type, size boundary, metadata failure, attach failure, retry, and cleanup.
- [ ] Verify upload permission behavior for inactive profiles and users with `document.update` but no document-level scope.
- [ ] Reconcile the implementation and migration source before production rollout.
- [ ] Obtain review/approval and a backup/rollback plan before any production change.

**Status:** code and catalog reviewed; finding documented; no tests executed; no production changes made.
