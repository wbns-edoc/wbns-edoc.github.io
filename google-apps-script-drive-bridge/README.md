# Google Apps Script Drive bridge (WBNS e-Document)

This is a server-side bridge prototype for writing files to the school-owned Google Drive as the Apps Script owner. It is **not production-ready** until the Supabase Edge Functions are integrated and end-to-end security tests succeed.

## Setup

1. Create a standalone Apps Script project while signed in to the school-owned Google account.
2. Copy `Code.gs` into the project.
3. In **Project Settings → Script properties**, set:
   - `WBNS_BRIDGE_SECRET`: generate a unique random secret of at least 32 bytes.
   - `WBNS_DRIVE_FOLDER_ID`: ID of the school’s destination folder.
4. Do not deploy yet. First implement and test the matching Supabase Edge Function signing protocol.
5. After security review, deploy as a Web app executing as **Me**. Restrict access as much as deployment settings permit; signed requests are still required.
6. Save the deployment URL as Supabase Edge Function secret `GOOGLE_APPS_SCRIPT_BRIDGE_URL`; save the same secret value as `GOOGLE_APPS_SCRIPT_BRIDGE_SECRET`. Never expose either to the frontend.

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

- This prototype caps raw file bytes at 10 MiB because JSON/base64 transport increases payload size and Apps Script web-app request limits vary. It is not compatible with a 25 MiB Edge Function limit until a different transport is designed and tested.
- Google Apps Script execution quotas and Drive quotas still apply.
- HMAC authentication does not replace Supabase user JWT validation and document permission checks. Those must remain in the Edge Function before any bridge call.
- The `permanent-delete-incoming` Edge Function may permanently remove database records only after all required Drive files are confirmed moved to Trash. Its response must say `drive_files_moved_to_trash`, not claim that the Drive files were permanently erased. Partial failures must preserve database records for reconciliation.
- Do not deploy to Production until the Edge Function integration, upload, read, trash, replay rejection, invalid-signature rejection, and cross-folder deletion tests pass.
- The bridge returns generic errors to callers. Do not log secrets, signatures, file contents, or tokens.
