import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@6";

const DRIVE_API = "https://www.googleapis.com/drive/v3/files";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive";
type SA = { client_email: string; private_key: string; token_uri?: string };

function out(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  }});
}
async function driveToken(sa: SA) {
  const now = Math.floor(Date.now() / 1000);
  const key = await importPKCS8(sa.private_key, "RS256");
  const jwt = await new SignJWT({ iss: sa.client_email, scope: DRIVE_SCOPE, aud: sa.token_uri || TOKEN_URL })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" }).setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const response = await fetch(sa.token_uri || TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt })
  });
  if (!response.ok) throw new Error("GOOGLE_TOKEN_EXCHANGE_FAILED");
  const payload = await response.json();
  if (!payload.access_token) throw new Error("GOOGLE_ACCESS_TOKEN_MISSING");
  return payload.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({ ok: true });
  if (req.method !== "POST") return out({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return out({ ok: false, code: "AUTH_REQUIRED" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const saRaw = Deno.env.get("GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON");
  if (!url || !anonKey || !serviceKey || !saRaw) return out({ ok: false, code: "SERVER_CONFIGURATION_MISSING" }, 500);

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

  let sa: SA;
  try { sa = JSON.parse(saRaw); } catch { return out({ ok: false, code: "GOOGLE_DRIVE_CONFIGURATION_INVALID" }, 500); }
  let accessToken: string;
  try { accessToken = await driveToken(sa); } catch (error) {
    console.error("Google Drive token failed", error);
    return out({ ok: false, code: "GOOGLE_DRIVE_AUTH_FAILED" }, 502);
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
      const response = await fetch(`${DRIVE_API}/${encodeURIComponent(file.drive_file_id)}`, {
        method: "DELETE", headers: { Authorization: `Bearer ${accessToken}` }
      });
      if (response.ok) deleted.push(file.drive_file_id);
      else if (response.status === 404) alreadyMissing.push(file.drive_file_id);
      else {
        const detail = (await response.text()).slice(0, 250);
        console.error("Google Drive permanent delete failed", response.status, detail);
        failed.push({ name: String(file.name || "unknown"), code: `DRIVE_DELETE_HTTP_${response.status}` });
      }
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
