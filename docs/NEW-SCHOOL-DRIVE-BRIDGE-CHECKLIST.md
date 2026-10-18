# Google Apps Script Drive Bridge — New School Checklist

This checklist is for preparing an independent installation for each school. It is not evidence that a new school's environment has been deployed or tested.

## Isolation requirements

- [ ] Create a separate GitHub repository or controlled deployment target for the school.
- [ ] Create a separate Supabase project for the school. Never reuse the WBNS production project URL, project ref, database, Auth users, or keys.
- [ ] Create a separate Google Apps Script project and school-owned Drive destination folder.
- [ ] Deploy the Apps Script as a Web App that executes as the script owner.
- [ ] Store secrets in Script Properties and Supabase Edge Function secrets only. Never commit or put them in browser code.
- [ ] Keep school-specific credentials, user data, and Drive files out of shared template files and pull requests.

## Apps Script Script Properties

Set these in Apps Script > Project Settings > Script properties:

- `WBNS_BRIDGE_SECRET`: a randomly generated shared secret with at least 32 bytes of entropy.
- `WBNS_DRIVE_FOLDER_ID`: the destination folder ID owned by or explicitly accessible to that school.

Do not paste either value into issues, pull requests, source files, or chat messages.

## Supabase Edge Function secrets

For the school's own Supabase project, configure:

- `GOOGLE_APPS_SCRIPT_BRIDGE_URL`: the deployed Web App URL for that school's Apps Script.
- `GOOGLE_APPS_SCRIPT_BRIDGE_SECRET`: the same shared secret as `WBNS_BRIDGE_SECRET`, stored as a secret.

Also verify the Supabase URL and required public/server keys are supplied by the project's deployment environment. Do not copy keys from another school's project.

## Contract and limits to verify

- Signed payload uses HMAC-SHA256 over JSON.stringify(payload without signature), encoded base64url without padding.
- Payload fields and insertion order must match the Apps Script verifier.
- Requests require a recent integer timestamp and a UUID requestId.
- Bridge currently supports `health`, `upload`, and `delete`.
- Upload limit in the provided Apps Script code is 20 MiB, but the request-body limit is 15 MiB and the current Edge Function enforces a 10 MiB bridge limit. Treat 10 MiB as the effective application limit until the limits are intentionally reconciled and tested.
- `delete` checks that the Drive file has the configured folder as a parent, then calls `setTrashed(true)`. This moves the file to Drive Trash; it is not a hard-delete operation.
- CacheService replay prevention is best-effort and is not a durable idempotency store.

## Pre-production tests (use test documents and files only)

- [ ] Health action returns the expected school Drive folder.
- [ ] Upload a small test PDF and verify metadata and attachment records.
- [ ] Upload a supported image and office document; verify the UI can open them.
- [ ] Reject an invalid signature, expired timestamp, malformed request ID, and replayed request.
- [ ] Reject files over the effective size limit and invalid filenames.
- [ ] Reject deletion of a file outside the configured folder.
- [ ] Verify a file shared by multiple document records is retained when one document is deleted.
- [ ] Simulate Bridge failure and database finalization failure; confirm reconciliation instructions and retry behavior.
- [ ] Verify the database never removes attachment metadata while Drive cleanup is uncertain.
- [ ] Confirm deletion audit records and role/department authorization.
- [ ] Confirm CI passes and review the deployed function versions before enabling production use.

## Release gate

Do not merge or deploy solely because the code compiles. Require an isolated end-to-end test report, verified per-school secrets, a rollback plan, and explicit approval before any production deployment.
