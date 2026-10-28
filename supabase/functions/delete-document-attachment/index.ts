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

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({ ok: true });
  if (req.method !== "POST") return out({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return out({ ok: false, code: "AUTH_REQUIRED" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) {
    return out({ ok: false, code: "SERVER_CONFIGURATION_MISSING" }, 500);
  }

  const user = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: authData, error: authError } = await user.auth.getUser();
  if (authError || !authData.user) {
    return out({ ok: false, code: "AUTH_INVALID" }, 401);
  }

  let body: { document_file_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return out({ ok: false, code: "INVALID_JSON" }, 400);
  }
  const attachmentId = typeof body.document_file_id === "string" ? body.document_file_id : "";
  if (!UUID_RE.test(attachmentId)) {
    return out({ ok: false, code: "INVALID_ATTACHMENT_ID" }, 400);
  }

  // The database RPC checks the active profile, document.update permission,
  // document scope, and performs the audited detach in one transaction.
  // This endpoint never uses the service-role key or calls Google Drive.
  const { data, error } = await user.rpc("detach_document_file", {
    p_document_file_id: attachmentId
  });

  if (error) {
    const message = error.message ?? "";
    if (message.includes("authentication_required") || message.includes("active_profile_required")) {
      return out({ ok: false, code: "AUTH_REQUIRED" }, 401);
    }
    if (message.includes("attachment_not_found")) {
      return out({ ok: false, code: "ATTACHMENT_NOT_FOUND_OR_ALREADY_DETACHED" }, 404);
    }
    if (message.includes("attachment_detach_permission_denied") || message.includes("document_scope_denied")) {
      return out({ ok: false, code: "INSUFFICIENT_PERMISSION_OR_DOCUMENT_SCOPE" }, 403);
    }
    console.error("Attachment detach RPC failed", error.code ?? "unknown", message);
    return out({ ok: false, code: "ATTACHMENT_DETACH_FAILED" }, 500);
  }

  return out({ ok: true, ...(typeof data === "object" && data !== null ? data : {}) });
});
