import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { mayDeleteDriveObject, mayDeleteUploadResources } from "./cleanup-policy.ts";
import { MAX_UPLOAD_BYTES, validateUploadInput, isValidFileRole } from "./file-validation.ts";


function out(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  }});
}
const BRIDGE_MAX_FILE_BYTES = 10 * 1024 * 1024;
function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
async function signedBridgeRequest(action: "health" | "upload" | "delete", extra: Record<string, string> = {}) {
  const url = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_URL");
  const secret = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_SECRET");
  if (!url || !secret || !/^https:\/\//i.test(url)) throw new Error("APPS_SCRIPT_BRIDGE_CONFIGURATION_INVALID");
  const payload: Record<string, string | number> = { action, timestamp: Math.floor(Date.now()/1000), requestId: crypto.randomUUID() };
  for (const [key, value] of Object.entries(extra)) payload[key] = value;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), {name:"HMAC", hash:"SHA-256"}, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(JSON.stringify(payload))));
  const response = await fetch(url, { method:"POST", headers:{"Content-Type":"application/json; charset=utf-8"}, body:JSON.stringify({...payload, signature:base64Url(sig)}), signal:AbortSignal.timeout(45000) });
  if (!response.ok) throw new Error("APPS_SCRIPT_BRIDGE_HTTP_FAILED");
  const result = await response.json().catch(()=>null);
  if (!result || result.ok !== true) {
    console.error("Apps Script bridge failure", result && typeof result.code === "string" ? result.code : "INVALID_RESPONSE");
    throw new Error("APPS_SCRIPT_BRIDGE_OPERATION_FAILED");
  }
  return result as Record<string, unknown>;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({ ok: true });
  if (req.method !== "POST") return out({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return out({ ok: false, code: "AUTH_REQUIRED" }, 401);

  // Platform JWT verification plus caller identity and permission checks.
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return out({ ok: false, code: "SUPABASE_CONFIGURATION_MISSING" }, 500);
  const sb = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await sb.auth.getUser();
  if (userError || !userData.user) return out({ ok: false, code: "AUTH_INVALID" }, 401);

  let form: FormData;
  try { form = await req.formData(); } catch { return out({ ok: false, code: "INVALID_MULTIPART_FORM" }, 400); }
  const file = form.get("file");
  const documentId = String(form.get("document_id") || "");
  const fileRole = String(form.get("file_role") || "main");
  if (!(file instanceof File) || !documentId) return out({ ok: false, code: "FILE_AND_DOCUMENT_REQUIRED" }, 400);
  if (!isValidFileRole(fileRole)) return out({ ok: false, code: "INVALID_FILE_ROLE" }, 400);
  const validationError = validateUploadInput(file);
  if (validationError) {
    const status = validationError === "FILE_TOO_LARGE" ? 413 : 400;
    return out({
      ok: false,
      code: validationError,
      ...(validationError === "FILE_TOO_LARGE" ? { max_bytes: MAX_UPLOAD_BYTES } : {}),
    }, status);
  }

  if (file.size > BRIDGE_MAX_FILE_BYTES) return out({ ok:false, code:"FILE_TOO_LARGE_FOR_DRIVE_BRIDGE", max_bytes:BRIDGE_MAX_FILE_BYTES }, 413);

  const { data: permissions, error: permissionError } = await sb.rpc("get_my_permissions");
  if (permissionError) return out({ ok: false, code: "PERMISSION_CHECK_FAILED" }, 403);
  if (!Array.isArray(permissions) || !permissions.some((p: { permission_code?: string }) => p.permission_code === "document.update")) {
    return out({ ok: false, code: "INSUFFICIENT_PERMISSION" }, 403);
  }
  const { data: document, error: documentError } = await sb.from("documents").select("id").eq("id", documentId).maybeSingle();
  if (documentError || !document) return out({ ok: false, code: "DOCUMENT_NOT_FOUND_OR_NOT_ACCESSIBLE" }, 404);

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) return out({ ok: false, code: "SERVER_DATABASE_CONFIGURATION_MISSING" }, 500);
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const bridgeUrl = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_URL");
  const bridgeSecret = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_SECRET");
  if (!bridgeUrl || !bridgeSecret) return out({ ok:false, code:"APPS_SCRIPT_BRIDGE_CONFIGURATION_MISSING" }, 500);
  const folder = Deno.env.get("GOOGLE_DRIVE_ROOT_FOLDER_ID") || "";

  let driveFileId: string | null = null;
  let metadataRowId: string | null = null;
  async function cleanupCreatedResources() {
    if (metadataRowId) {
      // A timed-out RPC can commit the attachment even when the caller receives an error.
      // Never delete the Drive object until we have confirmed it is not referenced.
      const { data: attachedRows, error: attachmentLookupError } = await admin
        .from("document_files")
        .select("id")
        .eq("google_drive_file_id", metadataRowId)
        .limit(1);
      const attachmentState = attachmentLookupError
        ? "lookup-failed"
        : attachedRows?.length
        ? "already-attached"
        : "unattached";
      if (!mayDeleteUploadResources(attachmentState)) {
        if (attachmentLookupError) {
          console.error("Attachment state lookup failed; preserving upload for reconciliation", attachmentLookupError.message);
          return;
        }
        console.error("Cleanup skipped because upload metadata is already attached; reconcile client result");
        metadataRowId = null;
        driveFileId = null;
        return;
      }

      const { error } = await admin.from("google_drive_files").delete().eq("id", metadataRowId);
      if (!mayDeleteDriveObject(Boolean(error))) {
        console.error("Drive metadata cleanup failed; preserving Drive object for reconciliation", error?.message);
        return;
      }
      metadataRowId = null;
    }
    if (driveFileId) {
      try { await signedBridgeRequest("delete", { fileId: driveFileId }); driveFileId = null; }
      catch (error) { console.error("Apps Script cleanup failed; reconcile manually if needed", error); }
    }
  }

  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + 0x8000, bytes.length)));
    const uploaded = await signedBridgeRequest("upload", { filename:file.name, mimeType:file.type || "application/octet-stream", contentBase64:btoa(binary) });
    if (typeof uploaded.file_id !== "string" || !uploaded.file_id) return out({ ok:false, code:"GOOGLE_DRIVE_RESPONSE_INVALID" }, 502);
    driveFileId = uploaded.file_id;
    const d = { id:uploaded.file_id, name:typeof uploaded.name==="string"?uploaded.name:file.name,
      mimeType:typeof uploaded.mime_type==="string"?uploaded.mime_type:(file.type || "application/octet-stream"),
      size:typeof uploaded.size_bytes==="number"?uploaded.size_bytes:file.size,
      webViewLink:typeof uploaded.url==="string"?uploaded.url:`https://drive.google.com/open?id=${uploaded.file_id}`, md5Checksum:null };
    const metadata = {
      drive_file_id: String(d.id),
      drive_url: driveUrl,
      name: String(d.name || file.name),
      mime_type: String(d.mimeType || file.type || "application/octet-stream"),
      size_bytes: Number(d.size || file.size),
      checksum: d.md5Checksum || null,
      folder_id: folder,
      created_by: userData.user.id
    };

    // Persist Drive metadata server-side; browser clients intentionally have no table INSERT policy.
    const { data: fileRow, error: metadataError } = await admin
      .from("google_drive_files")
      .insert(metadata)
      .select("id")
      .single();
    if (metadataError || !fileRow) {
      console.error("Drive metadata insert failed", metadataError?.message || "NO_ROW");
      await cleanupCreatedResources();
      return out({ ok: false, code: "FILE_METADATA_SAVE_FAILED" }, 500);
    }
    metadataRowId = fileRow.id;

    // Call with the original user's JWT so auth.uid() and permission checks remain meaningful.
    const { data: attachment, error: attachmentError } = await sb.rpc("attach_document_file_version", {
      p_document_id: documentId,
      p_google_drive_file_id: fileRow.id,
      p_file_role: fileRole
    });
    if (attachmentError || !Array.isArray(attachment) || attachment.length === 0) {
      console.error("Document file attachment failed", attachmentError?.message || "NO_ATTACHMENT_ROW");
      await cleanupCreatedResources();
      return out({ ok: false, code: "DOCUMENT_FILE_ATTACH_FAILED" }, 500);
    }
    // Attachment succeeded; resources now belong to the document and must not be compensated.
    metadataRowId = null;
    driveFileId = null;

    return out({ ok: true, document_id: documentId, file: {
      id: fileRow.id, drive_file_id: metadata.drive_file_id, name: metadata.name,
      mime_type: metadata.mime_type, size_bytes: metadata.size_bytes,
      checksum: metadata.checksum, drive_url: driveUrl, folder_id: folder
    }, attachment });
  } catch (e) {
    console.error("Drive upload error", e);
    await cleanupCreatedResources();
    return out({ ok: false, code: "GOOGLE_DRIVE_UPLOAD_ERROR" }, 500);
  }
});