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
async function trashDriveFile(fileId: string) {
  const url = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_URL");
  const secret = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_SECRET");
  if (!url || !secret || !/^https:\/\//i.test(url)) throw new Error("BRIDGE_CONFIGURATION_INVALID");
  const payload = { action: "delete", timestamp: Math.floor(Date.now() / 1000), requestId: crypto.randomUUID(), fileId };
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = base64Url(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(JSON.stringify(payload)))));
  const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...payload, signature }), signal: AbortSignal.timeout(90000) });
  if (!response.ok) throw new Error("BRIDGE_HTTP_FAILED");
  const result = await response.json().catch(() => null);
  if (!result || result.ok !== true || result.trashed !== true || result.file_id !== fileId) throw new Error("BRIDGE_TRASH_FAILED");
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({ ok: true });
  if (req.method !== "POST") return out({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return out({ ok: false, code: "AUTH_REQUIRED" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return out({ ok: false, code: "SERVER_CONFIGURATION_MISSING" }, 500);
  const user = createClient(url, anon, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await user.auth.getUser();
  if (authError || !authData.user) return out({ ok: false, code: "AUTH_INVALID" }, 401);
  // Deletion is restricted to the three explicitly authorized school roles.
  // Do not rely on a broad document.update permission for this destructive action.
  const { data: userRoles, error: roleError } = await user.from("user_roles")
    .select("roles(name,code)").eq("user_id", authData.user.id);
  if (roleError) return out({ ok: false, code: "ROLE_CHECK_FAILED" }, 403);
  const allowedRoleNames = new Set([
    "System Admin", "system_admin",
    "ผู้อำนวยการโรงเรียน", "Director", "director",
    "เจ้าหน้าที่สารบรรณ", "Registry Officer", "registry_officer"
  ]);
  const hasDeleteRole = (userRoles || []).some((row: any) => {
    const role = Array.isArray(row.roles) ? row.roles[0] : row.roles;
    return role && (allowedRoleNames.has(role.name) || allowedRoleNames.has(role.code));
  });
  if (!hasDeleteRole) return out({ ok: false, code: "INSUFFICIENT_ROLE" }, 403);
  let body: { document_file_id?: unknown };
  try { body = await req.json(); } catch { return out({ ok: false, code: "INVALID_JSON" }, 400); }
  const attachmentId = typeof body.document_file_id === "string" ? body.document_file_id : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(attachmentId)) return out({ ok: false, code: "INVALID_ATTACHMENT_ID" }, 400);

  // Read through the caller's RLS policies first: inaccessible attachments cannot be targeted.
  const { data: attachment, error: attachmentError } = await user.from("document_files")
    .select("id,document_id,google_drive_file_id,documents(id),google_drive_files(id,drive_file_id,name)")
    .eq("id", attachmentId).maybeSingle();
  if (attachmentError || !attachment) return out({ ok: false, code: "ATTACHMENT_NOT_FOUND_OR_NOT_ACCESSIBLE" }, 404);
  const meta = Array.isArray(attachment.google_drive_files) ? attachment.google_drive_files[0] : attachment.google_drive_files;
  if (!meta?.id || !meta?.drive_file_id) return out({ ok: false, code: "DRIVE_METADATA_MISSING" }, 409);

  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: refs, error: refsError } = await admin.from("document_files").select("id").eq("google_drive_file_id", attachment.google_drive_file_id);
  if (refsError || !refs) return out({ ok: false, code: "ATTACHMENT_REFERENCE_CHECK_FAILED" }, 500);
  if (refs.length !== 1 || refs[0].id !== attachmentId) {
    // Shared Drive metadata must never be trashed when another attachment references it.
    return out({ ok: false, code: "SHARED_FILE_DELETE_BLOCKED", message: "ไฟล์นี้ถูกอ้างอิงโดยรายการอื่น จึงไม่ลบไฟล์ต้นฉบับเพื่อป้องกันข้อมูลสูญหาย" }, 409);
  }

  try { await trashDriveFile(meta.drive_file_id); }
  catch (e) {
    console.error("Attachment Drive trash failed", e);
    return out({ ok: false, code: "DRIVE_TRASH_FAILED", message: "ย้ายไฟล์ไปถังขยะ Google Drive ไม่สำเร็จ จึงยังไม่ลบข้อมูลแนบ" }, 502);
  }

  const { error: detachError } = await admin.from("document_files").delete().eq("id", attachmentId);
  if (detachError) {
    console.error("Attachment metadata detach failed after Drive trash", detachError.message);
    return out({ ok: false, code: "ATTACHMENT_RECORD_DELETE_FAILED", message: "ไฟล์ถูกย้ายไปถังขยะแล้ว แต่ลบข้อมูลแนบไม่สำเร็จ กรุณาแจ้งผู้ดูแลระบบ" }, 500);
  }
  const { error: metadataDeleteError } = await admin.from("google_drive_files").delete().eq("id", meta.id);
  if (metadataDeleteError) console.error("Orphaned Drive metadata cleanup required", metadataDeleteError.message);
  return out({ ok: true, attachment_id: attachmentId, drive_file_trashed: true, metadata_cleanup_pending: Boolean(metadataDeleteError) });
});
