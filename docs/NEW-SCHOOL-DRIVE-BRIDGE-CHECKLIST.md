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

## Upload size contract — 20 MiB per file

The configured maximum individual file size is exactly **20 MiB = 20 × 1024 × 1024 = 20,971,520 bytes**. Keep every application-level check aligned to that value:

- Frontend/file validation and the `drive-upload` Edge Function: `20 * 1024 * 1024` bytes.
- Apps Script `MAX_FILE_BYTES`: `20 * 1024 * 1024` bytes.
- Apps Script `MAX_REQUEST_BODY_CHARS`: at least `32 * 1024 * 1024` characters, because base64 expands a 20 MiB file to about 26.7 MiB before JSON overhead.
- Any request-body, proxy, gateway, or deployment limit in the path must accept the encoded request (not merely a 20 MiB raw file). Verify this with an end-to-end 20 MiB test; a lower upstream cap means the requirement is not yet met.

The Edge Function bridge request sends the file as base64 JSON, so request size is larger than the raw file. Do not set a request-body cap to 20 MiB and assume it can carry a 20 MiB file.

Google's published Apps Script quotas list a 50 MB POST size for **UrlFetch outbound requests** and a six-minute execution runtime, but those figures do not establish the maximum inbound POST body accepted by a deployed Web App. Do not treat the UrlFetch POST quota as proof that the incoming Web App request will accept a 26.7+ MiB JSON payload. Confirm with a real test against the exact deployed Web App version and inspect Apps Script Executions for failures:
- [Apps Script quotas](https://developers.google.com/apps-script/guides/services/quotas)
- [Apps Script Web Apps request event fields](https://developers.google.com/apps-script/guides/web)

For large files, also measure execution duration and memory-related failures. The Edge Function currently creates a Base64 string and JSON body, while the bridge parses JSON, holds the Base64 string, and decodes a byte array; peak memory use can be materially larger than the raw file size.

## Contract and security checks

- Signed payload uses HMAC-SHA256 over JSON.stringify(payload without signature), encoded base64url without padding.
- Payload fields and insertion order must match the Apps Script verifier.
- Requests require a recent integer timestamp and a UUID requestId.
- Bridge supports `health`, `upload`, and `delete`.
- `delete` checks that the Drive file has the configured folder as a parent, then calls `setTrashed(true)`. This moves the file to Drive Trash; it is not a hard-delete operation.
- CacheService replay prevention is best-effort and is not a durable idempotency store.

## Pre-production tests (use test documents and files only)

- [ ] Health action returns the expected school Drive folder.
- [ ] Upload a small test PDF and verify metadata and attachment records.
- [ ] Upload a supported image and office document; verify the UI can open them.
- [ ] Upload a file of exactly 20,971,520 bytes successfully.
- [ ] Reject a file of 20,971,521 bytes and confirm the error reports `max_bytes: 20971520`.
- [ ] Verify a 20 MiB file succeeds through the complete browser → Edge Function → Apps Script → Drive path, including encoded request-body limits.
- [ ] Reject an invalid signature, expired timestamp, malformed request ID, and replayed request.
- [ ] Reject invalid filenames.
- [ ] Reject deletion of a file outside the configured folder.
- [ ] Verify a file shared by multiple document records is retained when one document is deleted.
- [ ] Simulate Bridge failure and database finalization failure; confirm reconciliation instructions and retry behavior.
- [ ] Verify the database never removes attachment metadata while Drive cleanup is uncertain.
- [ ] Confirm deletion audit records and role/department authorization.
- [ ] Confirm CI passes and review the deployed function versions before enabling production use.

## Release gate

Do not merge or deploy solely because the code compiles. Require an isolated end-to-end test report, verified per-school secrets, a rollback plan, and explicit approval before any production deployment.
