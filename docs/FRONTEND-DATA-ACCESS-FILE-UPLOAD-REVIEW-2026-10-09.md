# Frontend Data-Access and File-Upload Review — 2026-10-09

## Scope and evidence

Reviewed `src/main.tsx` on `security/release-gate-review-2026-10-09` and read the live Supabase catalog in read-only mode for RLS policies on `google_drive_files`, `document_files`, `documents`, `profiles`, and `user_roles`, plus whether RLS is enabled on the two file metadata tables.

No source code, schema, policy, grant, storage object, or production data was changed. No upload was attempted and no authorization tests were executed.

## High-priority finding: file upload flow appears inconsistent with live RLS policy

### Evidence
- In `src/main.tsx`, `DocumentDetail.uploadFile()` first calls the `drive-upload` Edge Function, then performs a direct browser-client insert into `public.google_drive_files`, then calls `public.attach_document_file_version(...)`.
- The live catalog confirms row-level security is enabled on `public.google_drive_files`.
- The inspected live policy inventory shows only a SELECT policy for `google_drive_files` (`google_drive_files_authorized`, requiring `private.has_permission('document.view')`). No INSERT policy was present in the returned policy inventory.

### Impact / confidence
If this is the complete policy set and the request uses the normal authenticated browser client, the direct metadata INSERT is expected to be rejected by RLS after the Edge Function may already have uploaded the binary to Google Drive. That can make uploads appear to fail while leaving an unlinked Drive object. This is a catalog/code-derived risk; it was not verified by attempting an upload.

### Safe remediation direction
- Prefer a server-side, authenticated workflow that validates document-level authorization, uploads the file, writes metadata, and attaches the version with clear cleanup/compensation on failure.
- Alternatively, add a narrowly scoped database write path only after defining the exact policy and verifying the caller cannot forge Drive IDs/URLs, attach a file to an unauthorized document, or bypass file-role/version invariants.
- Do not simply add a broad authenticated INSERT policy on `google_drive_files`.
- Add a non-production integration test for success, RLS denial, Edge Function failure, metadata failure, attach failure, and cleanup of orphaned files.
- Review idempotency/retry behavior and avoid exposing Google Drive credentials in browser code.

## Other authorization observations

- The UI hides navigation and actions based on the `get_my_permissions` response, but this is only presentation logic. Security must be enforced by RLS, RPCs, and Edge Functions for direct REST/RPC calls.
- The browser source uses a Supabase publishable key and project URL fallback. A publishable key is intended for client use; it is not a substitute for authorization. Verify production environment variables are configured correctly so the hardcoded fallback cannot silently target an unintended project.
- The inspected UI invokes several SECURITY DEFINER RPCs directly. Continue auditing their grants, fixed search paths, permission checks, and resource-level authorization.

## Release gate

- [ ] Verify the full policy set and INSERT grants on `google_drive_files` using the intended authenticated role.
- [ ] Reproduce the upload path only in isolated non-production, with synthetic files.
- [ ] Implement a server-side transactional/compensating flow or a narrowly scoped safe write path.
- [ ] Test that failed upload stages clean up orphaned binary/metadata artifacts.
- [ ] Test direct unauthorized REST/RPC calls, not only hidden UI controls.
- [ ] Preserve production unchanged until a reviewed fix is tested and approved.

**Status:** review finding documented; no upload or tests executed; no production changes made.
