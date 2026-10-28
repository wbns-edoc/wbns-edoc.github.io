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
const ALLOWED_ROLE_NAMES = new Set([
  "System Admin", "system_admin",
  "ผู้อำนวยการโรงเรียน", "Director", "director",
  "เจ้าหน้าที่สารบรรณ", "Registry Officer", "registry_officer"
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({ ok: true });
  if (req.method !== "POST") return out({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return out({ ok: false, code: "AUTH_REQUIRED" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return out({ ok: false, code: "SERVER_CONFIGURATION_MISSING" }, 500);

  const user = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: authData, error: authError } = await user.auth.getUser();
  if (authError || !authData.user) return out({ ok: false, code: "AUTH_INVALID" }, 401);

  // Destructive actions are restricted to explicitly authorized school roles.
  const { data: userRoles, error: roleError } = await user.from("user_roles")
    .select("roles(name,code)").eq("user_id", authData.user.id);
  if (roleError) return out({ ok: false, code: "ROLE_CHECK_FAILED" }, 403);
  const hasDeleteRole = (userRoles ?? []).some((row: { roles: unknown }) => {
    const related = row.roles;
    const role = Array.isArray(related) ? related[0] : related;
    if (!role || typeof role !== "object") return false;
    const candidate = role as { name?: unknown; code?: unknown };
    return (typeof candidate.name === "string" && ALLOWED_ROLE_NAMES.has(candidate.name)) ||
      (typeof candidate.code === "string" && ALLOWED_ROLE_NAMES.has(candidate.code));
  });
  if (!hasDeleteRole) return out({ ok: false, code: "INSUFFICIENT_ROLE" }, 403);

  let body: { document_file_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return out({ ok: false, code: "INVALID_JSON" }, 400);
  }
  const attachmentId = typeof body.document_file_id === "string" ? body.document_file_id : "";
  if (!UUID_RE.test(attachmentId)) return out({ ok: false, code: "INVALID_ATTACHMENT_ID" }, 400);

  // Read via caller RLS first so inaccessible attachments cannot be targeted.
  const { data: attachment, error: attachmentError } = await user.from("document_files")
    .select("id,document_id,google_drive_file_id,file_role,version_no")
    .eq("id", attachmentId).maybeSingle();
  if (attachmentError || !attachment) {
    return out({ ok: false, code: "ATTACHMENT_NOT_FOUND_OR_NOT_ACCESSIBLE" }, 404);
  }

  // SAFETY: this endpoint only detaches the relationship from this document.
  // It deliberately does not call Google Drive, trash the source file, or
  // delete google_drive_files metadata. Orphan cleanup is a separate workflow.
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: detachedRows, error: detachError } = await admin.from("document_files")
    .delete()
    .eq("id", attachment.id)
    .eq("document_id", attachment.document_id)
    .eq("google_drive_file_id", attachment.google_drive_file_id)
    .select("id");

  if (detachError) {
    console.error("Attachment detach failed; source Drive file and metadata were preserved", detachError.message);
    return out({ ok: false, code: "ATTACHMENT_DETACH_FAILED" }, 500);
  }
  if (!detachedRows || detachedRows.length !== 1) {
    return out({ ok: false, code: "ATTACHMENT_CHANGED_OR_ALREADY_DETACHED" }, 409);
  }

  return out({
    ok: true,
    attachment_id: attachment.id,
    attachment_detached: true,
    drive_file_trashed: false,
    drive_file_preserved: true,
    metadata_preserved: true
  });
});
