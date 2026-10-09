import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@6";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const DRIVE_API = "https://www.googleapis.com/drive/v3/files";
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
async function token(sa: SA) {
  const now = Math.floor(Date.now() / 1000);
  const key = await importPKCS8(sa.private_key, "RS256");
  const jwt = await new SignJWT({ iss: sa.client_email, scope: DRIVE_SCOPE, aud: sa.token_uri || TOKEN_URL })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" }).setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const r = await fetch(sa.token_uri || TOKEN_URL, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }) });
  if (!r.ok) throw new Error("GOOGLE_TOKEN_EXCHANGE_FAILED");
  const p = await r.json();
  if (!p.access_token) throw new Error("GOOGLE_ACCESS_TOKEN_MISSING");
  return p.access_token as string;
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
  if (!(file instanceof File) || !documentId) return out({ ok: false, code: "FILE_AND_DOCUMENT_REQUIRED" }, 400);
  if (file.size <= 0) return out({ ok: false, code: "EMPTY_FILE" }, 400);
  if (file.size > 25 * 1024 * 1024) return out({ ok: false, code: "FILE_TOO_LARGE", max_bytes: 25 * 1024 * 1024 }, 413);

  const { data: permissions, error: permissionError } = await sb.rpc("get_my_permissions");
  if (permissionError) return out({ ok: false, code: "PERMISSION_CHECK_FAILED" }, 403);
  if (!Array.isArray(permissions) || !permissions.some((p: { permission_code?: string }) => p.permission_code === "document.update")) {
    return out({ ok: false, code: "INSUFFICIENT_PERMISSION" }, 403);
  }
  const { data: document, error: documentError } = await sb.from("documents").select("id").eq("id", documentId).maybeSingle();
  if (documentError || !document) return out({ ok: false, code: "DOCUMENT_NOT_FOUND_OR_NOT_ACCESSIBLE" }, 404);

  const raw = Deno.env.get("GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON");
  const folder = Deno.env.get("GOOGLE_DRIVE_ROOT_FOLDER_ID");
  if (!raw || !folder) return out({ ok: false, code: "GOOGLE_DRIVE_CONFIGURATION_MISSING" }, 500);
  let sa: SA;
  try { sa = JSON.parse(raw); } catch { return out({ ok: false, code: "GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON_INVALID" }, 500); }

  try {
    const access = await token(sa);
    const meta = new Blob([JSON.stringify({ name: file.name, parents: [folder] })], { type: "application/json" });
    const body = new FormData();
    body.append("metadata", meta);
    body.append("file", file, file.name);
    const params = new URLSearchParams({ uploadType: "multipart", fields: "id,name,mimeType,size,md5Checksum,webViewLink,parents" });
    const r = await fetch(`${DRIVE_API}?${params}`, { method: "POST", headers: { Authorization: `Bearer ${access}` }, body });
    if (!r.ok) {
      const t = await r.text();
      console.error("Drive upload failed", r.status, t.slice(0, 800));
      return out({ ok: false, code: "GOOGLE_DRIVE_UPLOAD_FAILED", upstream_status: r.status }, 502);
    }
    const d = await r.json();
    return out({ ok: true, document_id: documentId, file: {
      drive_file_id: d.id, name: d.name, mime_type: d.mimeType,
      size_bytes: Number(d.size || file.size), checksum: d.md5Checksum || null,
      drive_url: d.webViewLink || `https://drive.google.com/open?id=${d.id}`, folder_id: folder
    }});
  } catch (e) {
    console.error("Drive upload error", e);
    return out({ ok: false, code: "GOOGLE_DRIVE_UPLOAD_ERROR" }, 500);
  }
});