# Live RPC Privilege and Drive Upload Recheck — 2026-10-09

## Scope and safety

Read-only inspection of Supabase project `wbns-edoc` (`iigzzwyfxxtqbgjawyom`) and deployed Edge Function metadata/source. No SQL DDL/DML, grants, function deployments, uploads, branch creation, or Production changes were performed. This report is evidence from catalog/source inspection, not an integration-test report.

## Confirmed live findings

### 1. Workflow RPC definitions and privileges

Catalog inspection confirmed the following live public functions are `SECURITY DEFINER` PL/pgSQL implementations rather than the intended SQL `SECURITY INVOKER` forwarding wrappers in the repository's `harden_workflow_rpc` migration:

- `public.assign_document(uuid, uuid, text, timestamptz)`
- `public.update_document_status(uuid, document_status, text)`
- `public.set_document_deadline(uuid, uuid, timestamptz, timestamptz)`

`public.create_approval` and `public.decide_approval` are SQL invoker wrappers. All five `private.*` implementation functions exist and are `SECURITY DEFINER`.

Observed function-level ACLs for the five private functions explicitly include EXECUTE for `authenticated` and `service_role`; the `private` schema's authenticated USAGE was also previously observed as enabled. This means authenticated callers may invoke these private definer functions directly if the API/schema exposure and grants permit it. The live exposed-schema configuration was not independently established in this review, so external reachability must not be asserted as confirmed.

Behavior differences observed:
- Live `public.assign_document` requires a `registered` document state and rejects non-future deadlines; `private.assign_document` does not enforce those same checks.
- Live `public.update_document_status` enforces dedicated-RPC transition restrictions, per-target permissions, and `private.is_valid_document_transition`; `private.update_document_status` lacks those guards.
- Live `public.set_document_deadline` checks document existence, active assignee, future due date, and reminder ordering; `private.set_document_deadline` only checks permission and future due date.

Do not replace these public implementations with simple wrappers until the additional guards are preserved and tested. Do not blanket-revoke EXECUTE: build a function-by-function call graph and test UI/server callers first.

The following functions also remain worth targeted hardening and tests:
- `public.admin_remove_user_role`: no visible last-System-Admin or self-removal guard.
- `public.admin_create_department` / `public.admin_update_department`: no visible self-parent or indirect-cycle prevention.
- `public.attach_document_file_version`: checks authentication, `document.update`, and existence of the document/file, and serializes version allocation with an advisory lock; it does not visibly establish that the referenced Drive file is authorized for this document/department scope.

### 2. Deployed Drive upload Edge Function

The deployed `drive-upload` Edge Function is ACTIVE, version 2, and platform `verify_jwt=true`. Source inspection confirms it:
- requires a Bearer token and calls `auth.getUser()`;
- checks `document.update` via `get_my_permissions`;
- queries the target document through the caller-scoped Supabase client;
- caps files at 25 MiB and rejects empty files;
- uploads to Google Drive using server-side service-account configuration;
- returns Drive metadata to the browser.

The function does not visibly enforce a MIME-type allowlist or content-signature validation. Its CORS origin is `*`; review the actual frontend origin and deployment needs before changing it. The function does not create the `google_drive_files` metadata row or attach the file version; the frontend does those steps after upload.

### 3. RLS confirms a likely upload-flow failure

Live `pg_policies` inspection shows only SELECT policies on both `public.google_drive_files` and `public.document_files`:
- `google_drive_files_authorized`: SELECT for authenticated users with `document.view`.
- `document_files_authorized`: SELECT for authenticated users when the related document exists.

No INSERT policy was returned for either table. Although grants include table-level privileges, RLS still applies. Therefore, the frontend's browser-side INSERT into `google_drive_files` is likely to be rejected by RLS, leaving an orphaned Drive file after the external upload succeeds. This is a source/catalog-based risk assessment; no real upload integration test was run, so runtime failure is not claimed as proven.

## Recommended corrective direction (not executed)

1. Prefer a single authenticated server-side operation that validates caller permission and document scope, uploads the file, writes metadata through a narrowly privileged server path, and attaches the version. Add compensating cleanup/retry/idempotency so partial failures do not leave orphaned Drive objects.
2. If metadata writes remain browser-side, design a narrow RLS INSERT policy only after checking every required column and authorization predicate. Do not add a broad INSERT policy. Ensure `document_files` writes are handled by the trusted attachment RPC and that file/document/department ownership is verified.
3. Add MIME allowlisting and, where practical, file signature validation. Confirm filename sanitization and duplicate/idempotency behavior.
4. Preserve live workflow guard behavior when designing forward-only migrations. Reconcile live function bodies against repository migrations and migration history before any apply.
5. Test positive and negative cases in an isolated environment: permitted/forbidden users, cross-department access, missing document, invalid file type, oversize file, failed Drive upload, successful metadata write, failed attachment, retry, and cleanup.
6. Add a last-System-Admin invariant and department hierarchy cycle checks with tests. Do not run destructive tests against the only live administrator.
7. Verify the actual PostgREST exposed schemas through supported project/API configuration rather than inferring exposure from schema USAGE alone.

## Release gate

**BLOCKED — no Production change authorized or performed.** Still missing: isolated integration tests, migration/source reconciliation, full authorization regression suite, verified backup/restore drill, and owner approval. Supabase reports no development branches. No branch was created because organization-specific branch cost must be checked and explicitly approved first.
