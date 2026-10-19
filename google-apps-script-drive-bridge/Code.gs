/**
 * WBNS e-Document Google Drive bridge.
 *
 * Deploy as a Web App executing as the script owner. Store these in
 * Project Settings > Script properties:
 *   WBNS_BRIDGE_SECRET   - random shared secret (32+ bytes)
 *   WBNS_DRIVE_FOLDER_ID - destination folder ID owned/accessible by school
 *
 * Every request must be signed by the Supabase Edge Function. Never put the
 * shared secret in browser code or return it from this endpoint.
 *
 * Signed payload fields (in insertion order) must include:
 *   action, timestamp, requestId, then action-specific fields.
 * The signature is HMAC-SHA256 over JSON.stringify(payload without signature),
 * encoded as base64url without padding.
 */
const MAX_CLOCK_SKEW_SECONDS = 300;
const MAX_FILE_BYTES = 20 * 1024 * 1024;
const MAX_REQUEST_BODY_CHARS = 32 * 1024 * 1024;
const REPLAY_TTL_SECONDS = 600;

function doPost(e) {
  try {
    const raw = e && e.postData && e.postData.contents;
    if (!raw) return json_({ok:false, code:"INVALID_REQUEST"});
    if (raw.length > MAX_REQUEST_BODY_CHARS) return json_({ok:false, code:"PAYLOAD_TOO_LARGE"});

    const req = JSON.parse(raw);
    const props = PropertiesService.getScriptProperties();
    const secret = props.getProperty("WBNS_BRIDGE_SECRET");
    const folderId = props.getProperty("WBNS_DRIVE_FOLDER_ID");
    if (!secret || !folderId) return json_({ok:false, code:"BRIDGE_NOT_CONFIGURED"});

    if (!Number.isInteger(req.timestamp) ||
        Math.abs(Math.floor(Date.now() / 1000) - req.timestamp) > MAX_CLOCK_SKEW_SECONDS) {
      return json_({ok:false, code:"REQUEST_EXPIRED"});
    }
    if (typeof req.requestId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(req.requestId)) {
      return json_({ok:false, code:"INVALID_REQUEST_ID"});
    }
    if (typeof req.signature !== "string" || !verify_(req, secret)) {
      return json_({ok:false, code:"SIGNATURE_INVALID"});
    }

    // Cache and lock reduce concurrent duplicate execution. CacheService is
    // best-effort, not a durable transactional replay database.
    if (!claimRequestId_(req.requestId)) {
      return json_({ok:false, code:"REQUEST_REPLAYED"});
    }

    if (req.action === "health") {
      const folder = DriveApp.getFolderById(folderId);
      return json_({ok:true, folder_name:folder.getName(), folder_id:folder.getId()});
    }

    if (req.action === "upload") {
      if (typeof req.filename !== "string" || !req.filename.trim() ||
          req.filename.length > 255 || /[\u0000-\u001f\u007f/\\]/.test(req.filename)) {
        return json_({ok:false, code:"INVALID_FILENAME"});
      }
      if (typeof req.contentBase64 !== "string" || typeof req.mimeType !== "string") {
        return json_({ok:false, code:"INVALID_FILE"});
      }
      // Reject oversized encoded data before decoding to reduce memory pressure.
      if (req.contentBase64.length > Math.ceil(MAX_FILE_BYTES * 4 / 3) + 8) {
        return json_({ok:false, code:"FILE_SIZE_LIMIT"});
      }
      const bytes = Utilities.base64Decode(req.contentBase64);
      if (!bytes.length || bytes.length > MAX_FILE_BYTES) {
        return json_({ok:false, code:"FILE_SIZE_LIMIT"});
      }
      const folder = DriveApp.getFolderById(folderId);
      const blob = Utilities.newBlob(bytes, req.mimeType || "application/octet-stream", req.filename);
      const file = folder.createFile(blob);
      return json_({ok:true, file_id:file.getId(), name:file.getName(),
        mime_type:file.getMimeType(), size_bytes:file.getSize(), url:file.getUrl(), folder_id:folder.getId()});
    }

    if (req.action === "delete") {
      if (typeof req.fileId !== "string" || !/^[A-Za-z0-9_-]{10,}$/.test(req.fileId)) {
        return json_({ok:false, code:"INVALID_FILE_ID"});
      }
      const folder = DriveApp.getFolderById(folderId);
      const file = DriveApp.getFileById(req.fileId);
      let inFolder = false;
      const parents = file.getParents();
      while (parents.hasNext()) {
        if (parents.next().getId() === folder.getId()) inFolder = true;
      }
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

function claimRequestId_(requestId) {
  const cache = CacheService.getScriptCache();
  const key = "wbns_req_" + requestId;
  const lock = LockService.getScriptLock();
  lock.waitLock(5000);
  try {
    if (cache.get(key) !== null) return false;
    cache.put(key, "1", REPLAY_TTL_SECONDS);
    return true;
  } finally {
    lock.releaseLock();
  }
}

function verify_(req, secret) {
  const signature = req.signature;
  const unsigned = Object.assign({}, req);
  delete unsigned.signature;
  const canonical = JSON.stringify(unsigned);
  const expected = Utilities.base64EncodeWebSafe(
    Utilities.computeHmacSha256Signature(canonical, secret)
  ).replace(/=+$/, "");
  return constantTimeEqual_(signature, expected);
}

function constantTimeEqual_(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
