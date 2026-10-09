# File Metadata Access and Upload Remediation Design — 2026-10-09

## Status

Design artifact only. No migration or application code was applied. Based on read-only inspection of live columns, constraints, RLS policies, deployed `drive-upload` source, and the existing attachment RPC.

## Live schema facts

### `public.google_drive_files`

Columns include:
- `id uuid` primary key, default `gen_random_uuid()`
- `drive_file_id text NOT NULL`, unique
- `name text NOT NULL`
- optional `drive_url`, `mime_type`, `size_bytes`, `checksum`, `folder_id`, `created_by`
- `created_at timestamptz NOT NULL`, default `now()`

Foreign key: `created_by -> profiles(id)` with DELETE RESTRICT.

### `public.document_files`

Columns include:
- `id uuid` primary key
- `document_id uuid NOT NULL`
- `google_drive_file_id uuid NOT NULL`
- `file_role text NOT NULL`, default `attachment`
- `version_no integer NOT NULL`, default 1, CHECK `version_no > 0`
- `is_current boolean NOT NULL`, default true
- optional `uploaded_by uuid`; `uploaded_at timestamptz NOT NULL`, default `now()`

Foreign keys reference `documents(id)`, `google_drive_files(id)`, and `profiles(id)`; the pair `(document_id, google_drive_file_id)` is unique. These constraints do not by themselves prove the caller may attach an arbitrary Drive file to a particular document.

## Access-control evidence

The only live RLS policies returned for these two tables are SELECT policies. There is no observed INSERT policy on either table. Function-level grants also show authenticated EXECUTE on the private SECURITY DEFINER workflow functions. These are separate risks and must be handled with separate tests and least-privilege changes.

## Proposed safe upload contract

Prefer an orchestration endpoint or narrowly scoped server-side RPC flow with the following contract:

1. Authenticate the caller and derive the actor only from the verified token; never accept a caller-supplied actor ID.
2. Check `document.update` and the caller's effective access to the exact document and its department/scope.
3. Validate document ID, file size, allowed MIME type, extension consistency, and (where practical) file signature. Sanitize the display filename.
4. Upload to the configured school Drive folder using server-side credentials; do not expose the service-account JSON, private key, service-role key, or bearer token to the browser.
5. Persist the Drive metadata using a trusted server-side operation with a narrowly scoped privilege path; verify the Drive file belongs to the configured folder and was created by this operation.
6. Attach the returned metadata ID to the document through a single transaction that checks document scope and allocates the next version under the existing advisory lock strategy.
7. On metadata/attachment failure after Drive upload, attempt compensating deletion and record enough safe diagnostic information to retry or reconcile. Do not log secrets or file contents.
8. Use an idempotency key or stable upload request identifier so retries cannot create duplicate metadata or duplicate versions.
9. Return success to the client only after the metadata and document-version association have succeeded. If a multi-system transaction cannot be atomic, return a clear partial-failure state and provide reconciliation.

## Avoid these unsafe shortcuts

- Do not add a broad `INSERT WITH CHECK (true)` policy to either table.
- Do not trust the browser to set `created_by`, `uploaded_by`, `folder_id`, or a Drive file ID without server-side validation.
- Do not make `document_files` directly insertable by all authenticated users.
- Do not use `document.update` alone as proof of cross-department/document scope.
- Do not deploy a cleanup process that deletes arbitrary Drive files based only on client-supplied IDs.
- Do not claim the upload bug is reproduced until an integration test proves the exact failure mode.

## Required tests before implementation approval

- Authorized uploader can complete upload and see exactly one current version.
- Unauthorized user and cross-scope user cannot upload or attach.
- Missing document, malformed ID, disallowed MIME, extension mismatch, empty file, and file >25 MiB are rejected.
- Drive upload failure leaves no metadata/version record.
- Metadata insert failure triggers cleanup/reconciliation.
- Attachment failure triggers cleanup/reconciliation and leaves prior current version intact.
- Duplicate request/retry is idempotent.
- Two concurrent uploads allocate distinct versions and only the highest successful version is current according to product rules.
- Client cannot spoof creator/uploader identity or link an unrelated Drive object.
- Existing authorized download/view path still works after the change.

## Next implementation gate

First create a reproducible isolated test environment after obtaining exact organization-specific Supabase branch cost and explicit approval. Do not create a branch until both steps are complete. Then implement the narrowest forward-only migration plus server-side upload orchestration on the security branch, run automated authorization/integration tests, review the diff, and request approval before any Production rollout.
