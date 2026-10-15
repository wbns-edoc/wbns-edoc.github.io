import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
    },
  });
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\\+/g, "-").replace(/\\//g, "_");
}

async function signedBridgeHealth() {
  const url = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_URL");
  const secret = Deno.env.get("GOOGLE_APPS_SCRIPT_BRIDGE_SECRET");
  if (!url || !secret || !/^https:\\/\\//i.test(url)) {
    throw new Error("APPS_SCRIPT_BRIDGE_CONFIGURATION_INVALID");
  }

  const payload = {
    action: "health",
    timestamp: Math.floor(Date.now() / 1000),
    requestId: crypto.randomUUID(),
  };
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = base64Url(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(JSON.stringify(payload))),
    ),
  );

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ ...payload, signature }),
    signal: AbortSignal.timeout(45000),
  });
  if (!response.ok) throw new Error("APPS_SCRIPT_BRIDGE_HTTP_FAILED");

  const result = await response.json().catch(() => null);
  if (!result || result.ok !== true || typeof result.folder_name !== "string" || !result.folder_name) {
    const code = result && typeof result.code === "string" ? result.code : "INVALID_RESPONSE";
    console.error("Apps Script bridge health failed", code);
    throw new Error("APPS_SCRIPT_BRIDGE_HEALTH_FAILED");
  }
  return result as { ok: true; folder_name: string };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "GET") return json({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const result = await signedBridgeHealth();
    return json({
      ok: true,
      storage: "google_apps_script_bridge",
      folder_name: result.folder_name,
      write_test_performed: false,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "APPS_SCRIPT_BRIDGE_HEALTH_FAILED";
    console.error("Drive bridge health check failed", message);
    if (message === "APPS_SCRIPT_BRIDGE_CONFIGURATION_INVALID") {
      return json({ ok: false, code: message }, 500);
    }
    return json({ ok: false, code: "APPS_SCRIPT_BRIDGE_HEALTH_FAILED" }, 502);
  }
});
