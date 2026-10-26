# Google Apps Script Drive bridge (WBNS e-Document)

This is a server-side bridge prototype for writing files to the school-owned Google Drive as the Apps Script owner. It is **not production-ready** until live end-to-end security and size-limit tests succeed.

## Setup

1. Create a standalone Apps Script project while signed in to the school-owned Google account.
2. Copy `Code.gs` into the project.
3. In **Project Settings → Script properties**, set:
   - `WBNS_BRIDGE_SECRET`: generate a unique random secret of at least 32 bytes.
   - `WBNS_DRIVE_FOLDER_ID`: ID of the school’s destination folder.
4. The matching Supabase Edge Function signing protocol is implemented in this repository branch. Deploying the Apps Script web app is needed for live integration testing; it does **not** switch Production to the bridge by itself.
5. For testing, deploy as a Web app executing as **Me**. Restrict access as deployment settings permit; signed requests are still required. Use a new deployment version whenever you change `Code.gs`.
6. Save the deployment URL as Supabase Edge Function secret `GOOGLE_APPS_SCRIPT_BRIDGE_URL`; save the same secret value as `GOOGLE_APPS_SCRIPT_BRIDGE_SECRET`. Never expose either to the frontend or commit them.
7. Do not deploy the bridge Edge Functions to Production or merge this PR until the live security and end-to-end checklist below passes.

## Request signing protocol

- Each request must include `action`, integer Unix `timestamp`, unique UUID `requestId`, and action-specific fields.
- The Edge Function must calculate HMAC-SHA256 over the exact JSON serialization of the request object **excluding** `signature`, base64url-encode it without padding, then add `signature`.
- Keep the signed field insertion order consistent between Edge Function and Apps Script. Do not sign a different serialization than the one sent.
- Timestamp must be within five minutes of Apps Script server time.
- A request ID already seen by the script is rejected as `REQUEST_REPLAYED`. Apps Script CacheService plus LockService provides best-effort duplicate suppression for the cache retention window; it is **not** a durable transactional replay database and must not be represented as one.

## Supported operations

- `health`: verifies that the configured folder can be opened.
- `upload`: creates a file in the configured folder.
- `delete`: moves a file to Google Drive Trash only if it is a child of that configured folder. This is **not permanent deletion from Drive**; a Drive owner or administrator may be able to restore it or empty Trash later.

## Limits and safety

- The current branch configures a **20 MiB (20,971,520 byte) per-file limit** in both the Edge Function and `Code.gs`. This is a source-level limit only; it does **not** prove that Apps Script or its web-app transport accepts the Base64-encoded request at this size. A 20 MiB file becomes roughly 26.67 MiB before JSON overhead.
- The Apps Script handler checks `MAX_REQUEST_BODY_CHARS` only after the request reaches `doPost`; it cannot raise a Google platform request-size limit. Do not advertise 20 MiB as supported until a real 20 MiB upload succeeds through the complete browser → Edge Function → Apps Script → Drive path in an isolated test destination.
- Required boundary test: 20 MiB must upload and verify byte size, Drive object, metadata row, and document attachment; 20 MiB + 1 byte must be rejected with `max_bytes: 20971520` before a Drive object is created.
- Google Apps Script execution quotas and Drive quotas still apply.
- HMAC authentication does not replace Supabase user JWT validation and document permission checks. Those must remain in the Edge Function before any bridge call.
- The `permanent-delete-incoming` Edge Function may permanently remove database records only after all required Drive files are confirmed moved to Trash. Its response must say `drive_files_moved_to_trash`, not claim that the Drive files were permanently erased. Partial failures must preserve database records for reconciliation.
- Before Production deployment, test signed health, upload, reading the uploaded file, trashing the test file, replay rejection, invalid-signature rejection, cross-folder deletion rejection, and partial-failure retries. Verify Google Apps Script web-app redirect behavior and missing-file errors with actual requests.
- Do not log secrets, signatures, file contents, or tokens.
