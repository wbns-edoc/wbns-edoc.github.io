# Drive Upload Security Configuration and RLS Verification — 2026-10-09

## Scope and safety

This is a read-only follow-up against the existing security review branch and live Supabase catalog. No Production schema, data, Auth settings, secrets, file objects, or role assignments were changed. No upload or authorization integration test was run.

## Evidence checked

- Repository: `wbns-edoc/wbns-edoc.github.io`
- Branch: `security/release-gate-review-2026-10-09`
- Supabase project: `iigzzwyfxxtqbgjawyom`
- `supabase/functions/drive-upload/index.ts`
- `supabase/config.toml`
- Live `pg_policies`, `information_schema.role_table_grants`, `information_schema.columns`, and `pg_class` catalog views.

## Findings

### 1. The Edge Function performs some important caller checks

The current `drive-upload` source:
- requires a Bearer token and calls `auth.getUser()`;
- checks `get_my_permissions` for `document.update`;
- queries the target document through the caller-scoped Supabase client;
- rejects empty files and files larger than 25 MiB;
- uploads the binary to Google Drive using server-side service-account configuration;
- returns Google Drive metadata to the browser.

It does **not** insert the row into `google_drive_files`, call `attach_document_file_version`, delete the uploaded Drive object if later steps fail, or visibly enforce a MIME/type allowlist. These are source observations; no runtime upload test was performed.

### 2. Live RLS policy inventory has no INSERT policy for the metadata tables

The live catalog reports RLS enabled on both `public.google_drive_files` and `public.document_files`.

The returned policy inventory contains:
- `google_drive_files_authorized`: SELECT only, gated by `private.has_permission('document.view')`;
- `document_files_authorized`: SELECT only, checking that a matching document exists.

No INSERT policy was returned for either table. The browser workflow previously inspected attempts to insert the Google Drive metadata row directly. Despite INSERT appearing in the table grants for `anon` and `authenticated`, table grants do not bypass RLS; a direct browser INSERT is expected to be rejected when no applicable INSERT policy exists. This expectation still needs a controlled integration test to confirm the exact observed error.

### 3. File attachment RPC checks broad permission, not all object-level rules

The live definition of `public.attach_document_file_version(uuid, uuid, text)` is SECURITY DEFINER and checks authentication, `document.update`, document existence, and Google Drive metadata-row existence. It serializes version assignment using an advisory transaction lock.

The function body does not visibly validate:
- that the caller is allowed to update this specific document under the intended ownership/department rules;
- that the Google Drive metadata row was created by a trusted upload flow or belongs to the expected school folder;
- that MIME type and file size satisfy a centrally enforced policy.

These are review gaps to resolve against the intended authorization model, not proof that every path is exploitable. Do not fix this by adding a broad INSERT policy or granting broader access.

### 4. Function JWT configuration is not explicit in the repository config

`supabase/config.toml` has explicit entries for `drive-health` and `user-import`, but no explicit `[functions.drive-upload]` entry. The function source performs its own caller-token validation. The effective deployed platform JWT-verification setting was not independently inspected in this read-only pass; do not infer its live value from the file alone.

## Recommended safe remediation design

1. Move the entire upload transaction orchestration into a server-side trusted flow: validate caller and active account, permission, document-specific scope, file type/size, then upload to Drive, persist metadata, and attach the version.
2. If metadata persistence or attachment fails after Drive upload, perform compensating deletion of the newly uploaded Drive object; log a correlation ID and cleanup outcome without logging credentials or sensitive document content.
3. Make retries idempotent with an upload/request identifier and a defined duplicate policy. Avoid creating duplicate Drive objects or version rows on network retries.
4. Validate file type using an allowlist and content/signature checks where appropriate; do not trust the browser-supplied MIME type or filename.
5. Review RPC EXECUTE grants and the intended object/department authorization model. Add tests for unauthorized users, cross-document access, missing metadata, duplicate retries, failed DB writes, and cleanup failure.
6. Test only in a separately approved isolated environment. Do not create a Supabase branch until the branch cost is obtained, reported to the owner, and explicitly approved. The project cost constraint is $0/month.

## Status

- Read-only source/catalog review: completed for this note.
- Actual upload integration test: not run.
- Failure-compensation/retry behavior: not implemented or verified.
- Production changes: none.
- Release gate: remains blocked until the upload flow, migration parity, backup/restore, and authorization tests are reconciled and verified.
