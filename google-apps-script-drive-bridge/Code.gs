/**
 * WBNS e-Document Google Drive bridge.
 *
 * Deploy as a Web App executing as the script owner. Store these in
 * Project Settings > Script properties:
 *   WBNS_BRIDGE_SECRET  - random shared secret (32+ bytes)
 *   WBNS_DRIVE_FOLDER_ID - destination folder ID owned/accessible by school
 *
 * Requests must be signed by the Supabase Edge Function. Never put the
 * shared secret in browser code or return it from this endpoint.
 */
const MAX_CLOCK_SKEW_SECONDS = 300;
const MAX_FILE_BYTES = 10 * 1024 * 1024; // conservative Apps Script web-app payload bound

function doPost(e) {
  try {
    const raw = e && e.postData && e.postData.contents;
    if (!raw || raw.length > 15 * 1024 * 1024) return json_({ok:false, code:"PAYLOAD_TOO_LARGE"});
    const req = JSON.parse(raw);
    const props = PropertiesService.getScriptProperties();
    const secret = props.getProperty("WBNS_BRIDGE_SECRET");
    const folderId = props.getProperty("WBNS_DRIVE_FOLDER_ID");
    if (!secret || !folderId) return json_({ok:false, code:"BRIDGE_NOT_CONFIGURED"});
    if (!Number.isInteger(req.timestamp) || Math.abs(Math.floor(Date.now()/1000) - req.timestamp) > MAX_CLOCK_SKEW_SECONDS) {
      return json_({ok:false, code:"REQUEST_EXPIRED"});
    }
    if (typeof req.signature !== "string" || !verify_(req, secret)) return json_({ok:false, code:"SIGNATURE_INVALID"});

    if (req.action === "health") {
      const folder = DriveApp.getFolderById(folderId);
      return json_({ok:true, folder_name:folder.getName()});
    }
    if (req.action === "upload") {
      if (typeof req.filename !== "string" || !req.filename.trim() || req.filename.length > 255 ||
          /[\u0000-\u001f\u007f/\\]/.test(req.filename)) return json_({ok:false, code:"INVALID_FILENAME"});
      if (typeof req.contentBase64 !== "string" || typeof req.mimeType !== "string") return json_({ok:false, code:"INVALID_FILE"});
      const bytes = Utilities.base64Decode(req.contentBase64);
      if (!bytes.length || bytes.length > MAX_FILE_BYTES) return json_({ok:false, code:"FILE_SIZE_LIMIT"});
      const folder = DriveApp.getFolderById(folderId);
      const blob = Utilities.newBlob(bytes, req.mimeType || "application/octet-stream", req.filename);
      const file = folder.createFile(blob);
      return json_({ok:true, file_id:file.getId(), name:file.getName(), mime_type:file.getMimeType(), size_bytes:file.getSize(), url:file.getUrl()});
    }
    if (req.action === "delete") {
      if (typeof req.fileId !== "string" || !/^[A-Za-z0-9_-]{10,}$/.test(req.fileId)) return json_({ok:false, code:"INVALID_FILE_ID"});
      const folder = DriveApp.getFolderById(folderId);
      const file = DriveApp.getFileById(req.fileId);
      // Only permit deleting files in the configured destination folder.
      let inFolder = false;
      const parents = file.getParents();
      while (parents.hasNext()) if (parents.next().getId() === folder.getId()) inFolder = true;
      if (!inFolder) return json_({ok:false, code:"FILE_OUTSIDE_CONFIGURED_FOLDER"});
      file.setTrashed(true);
      return json_({ok:true, file_id:req.fileId, trashed:true});
    }
    return json_({ok:false, code:"UNKNOWN_ACTION"});
  } catch (err) {
    console.error("WBNS Drive bridge failure", err && err.message ? err.message : String(err));
    return json_({ok:false, code:"BRIDGE_OPERATION_FAILED"});
  }
}

function verify_(req, secret) {
  const signature = req.signature;
  const unsigned = Object.assign({}, req);
  delete unsigned.signature;
  const canonical = JSON.stringify(unsigned);
  const expected = Utilities.base64EncodeWebSafe(Utilities.computeHmacSha256Signature(canonical, secret)).replace(/=+$/, "");
  return constantTimeEqual_(signature, expected);
}

function constantTimeEqual_(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
