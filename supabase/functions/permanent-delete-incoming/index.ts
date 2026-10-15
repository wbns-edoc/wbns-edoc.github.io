import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function out(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  }});
}
function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
async function signedBridgeDelete(fileId: string) {
  const url = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_URL");
  const secret = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_SECRET");
  if (!url || !secret || !/^https:\/\//i.test(url)) throw new Error("APPS_SCRIPT_BRIDGE_CONFIGURATION_INVALID");
  const payload = { action:"delete", timestamp:Math.floor(Date.now()/1000), requestId:crypto.randomUUID(), fileId };
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), {name:"HMAC",hash:"SHA-256"}, false, ["sign"]);
  const signature = base64Url(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(JSON.stringify(payload)))));
  const response = await fetch(url, {method:"POST",headers:{"Content-Type":"application/json; charset=utf-8"},body:JSON.stringify({...payload,signature}),signal:AbortSignal.timeout(45000)});
  if (!response.ok) throw new Error("APPS_SCRIPT_BRIDGE_HTTP_FAILED");
  const result = await response.json().catch(()=>null);
  if (!result || result.ok !== true) {
    const code = result && typeof result.code === "string" ? result.code : "INVALID_RESPONSE";
    console.error("Apps Script permanent delete failed", code);
    throw new Error("APPS_SCRIPT_BRIDGE_OPERATION_FAILED");
  }
  return "deleted";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({ ok: true });
  if (req.method !== "POST") return out({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return out({ ok: false, code: "AUTH_REQUIRED" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const bridgeUrl = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_URL");
  const bridgeSecret = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_SECRET");
  if (!url || !anonKey || !serviceKey || !bridgeUrl || !bridgeSecret) return out({ ok: false, code: "SERVER_CONFIGURATION_MISSING" }, 500);

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return out({ ok: false, code: "AUTH_INVALID" }, 401);

  let body: { document_id?: unknown; reason?: unknown; confirmation?: unknown };
  try { body = await req.json(); } catch { return out({ ok: false, code: "INVALID_JSON" }, 400); }
  const documentId = typeof body.document_id === "string" ? body.document_id : "";
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(documentId)) {
    return out({ ok: false, code: "INVALID_DOCUMENT_ID" }, 400);
  }
  if (reason.length < 5 || reason.length > 1000) return out({ ok: false, code: "DELETION_REASON_REQUIRED" }, 400);
  if (body.confirmation !== "ลบถาวร") return out({ ok: false, code: "PERMANENT_DELETE_CONFIRMATION_REQUIRED" }, 400);

  const { data: prepared, error: prepareError } = await userClient.rpc("prepare_permanent_delete_incoming_document", {
    p_document_id: documentId, p_reason: reason
  });
  if (prepareError || !prepared || typeof prepared !== "object") {
    console.error("Permanent delete preparation denied", prepareError?.message || "NO_PREPARED_RESULT");
    return out({ ok: false, code: "PERMANENT_DELETE_PREPARATION_FAILED" }, 409);
  }



  const files = Array.isArray((prepared as { files?: unknown }).files)
    ? (prepared as { files: Array<{ metadata_id?: string; drive_file_id?: string; name?: string; delete_drive?: boolean }> }).files
    : [];
  const deleted: string[] = [];
  const alreadyMissing: string[] = [];
  const failed: Array<{ name: string; code: string }> = [];

  // Delete only Drive objects exclusively attached to this document. If a file is shared
  // by another document, retain it and its metadata.
  for (const file of files) {
    if (!file.delete_drive) continue;
    if (!file.drive_file_id) {
      failed.push({ name: String(file.name || "unknown"), code: "DRIVE_FILE_ID_MISSING" });
      continue;
    }
    try {
      const outcome = await signedBridgeDelete(file.drive_file_id);
      if (outcome === "deleted") deleted.push(file.drive_file_id);
      else alreadyMissing.push(file.drive_file_id);
    } catch (error) {
      console.error("Google Drive permanent delete request failed", error);
      failed.push({ name: String(file.name || "unknown"), code: "DRIVE_DELETE_REQUEST_FAILED" });
    }
  }

  if (failed.length) {
    // Do not remove any database records while Drive cleanup is incomplete.
    return out({ ok: false, code: "GOOGLE_DRIVE_DELETE_INCOMPLETE", failed, deleted_drive_file_count: deleted.length,
      already_missing_drive_file_count: alreadyMissing.length, retryable: true }, 502);
  }

  const { data: finalized, error: finalizeError } = await userClient.rpc("finalize_permanent_delete_incoming_document", {
    p_document_id: documentId, p_reason: reason
  });
  if (finalizeError || finalized !== true) {
    console.error("Database permanent delete finalization failed after Drive cleanup", finalizeError?.message || "FINALIZE_FALSE");
    return out({ ok: false, code: "DATABASE_FINALIZATION_FAILED", retryable: true,
      deleted_drive_file_count: deleted.length, already_missing_drive_file_count: alreadyMissing.length }, 500);
  }

  return out({ ok: true, document_id: documentId, permanently_deleted: true,
    deleted_drive_file_count: deleted.length, already_missing_drive_file_count: alreadyMissing.length,
    shared_drive_file_count: files.filter(file => !file.delete_drive).length });
});
