# Google Apps Script Drive bridge (WBNS e-Document)

This is a server-side bridge prototype for writing files to the school-owned Google Drive as the Apps Script owner. It is not production-ready until the Supabase Edge Functions are integrated and an end-to-end test succeeds.

## Setup

1. Create a standalone Apps Script project while signed in to the school-owned Google account.
2. Copy `Code.gs` into the project.
3. In **Project Settings → Script properties**, set:
   - `WBNS_BRIDGE_SECRET`: generate a unique random secret of at least 32 bytes.
   - `WBNS_DRIVE_FOLDER_ID`: ID of the school’s destination folder.
4. Deploy → New deployment → Web app. Execute as **Me**. Restrict access as much as the deployment settings permit; signed requests are still required by the script.
5. Save the deployment URL as a Supabase Edge Function secret named `GOOGLE_APPS_SCRIPT_BRIDGE_URL`; save the same secret value as `GOOGLE_APPS_SCRIPT_BRIDGE_SECRET`. Never expose either to the frontend.
6. The Edge Function must sign the exact JSON object (excluding `signature`) with HMAC-SHA256, base64url-encode the result without padding, and include a Unix `timestamp` within five minutes of server time.

## Supported operations

- `health`: verifies that the configured folder can be opened.
- `upload`: creates a file in the configured folder.
- `delete`: trashes a file only if it is a child of that configured folder.

## Limits and safety

- This prototype intentionally caps raw file bytes at 10 MiB because JSON/base64 transport increases payload size and Apps Script web-app request limits vary. It is not compatible with the current 25 MiB Edge Function limit until a different transport is designed and tested.
- Google Apps Script execution quotas and Drive quotas still apply.
- HMAC authentication does not replace Supabase user JWT validation and document permission checks. Those must remain in the Edge Function before any bridge call.
- Do not deploy to Production until the Edge Function integration, upload, read, delete, replay rejection, invalid-signature rejection, and cross-folder deletion tests pass.
- The bridge currently returns only generic errors to callers; detailed errors should remain in Apps Script execution logs, not expose secrets.
