import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type ClaimedEvent = {
  outbox_id: string;
  lease_token: string;
  event_key: string;
  request_id: string;
  recipient_id: string;
  event_type: string;
  channel: string;
  safe_payload: Record<string, unknown>;
  attempts: number;
};

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

function sameLengthSecretMatch(expected: string, provided: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(expected);
  const b = encoder.encode(provided);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return response({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);

  const expectedSecret = Deno.env.get("STAFF_LEAVE_WORKER_SECRET");
  const providedSecret = req.headers.get("x-staff-leave-worker-secret") ?? "";
  if (!expectedSecret || !sameLengthSecretMatch(expectedSecret, providedSecret)) {
    return response({ ok: false, code: "WORKER_AUTH_FAILED" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return response({ ok: false, code: "SERVER_CONFIGURATION_MISSING" }, 500);
  }

  let requestedLimit = 20;
  try {
    const body = await req.json();
    if (body?.limit !== undefined) requestedLimit = Number(body.limit);
  } catch {
    return response({ ok: false, code: "INVALID_JSON" }, 400);
  }
  if (!Number.isInteger(requestedLimit) || requestedLimit < 1 || requestedLimit > 50) {
    return response({ ok: false, code: "INVALID_LIMIT" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await admin.rpc("staff_leave_outbox_claim", {
    p_limit: requestedLimit,
    p_lease_seconds: 90,
  });
  if (error) {
    console.error("Leave notification claim failed", { code: error.code ?? "CLAIM_FAILED" });
    return response({ ok: false, code: "CLAIM_FAILED" }, 500);
  }

  const events = (Array.isArray(data) ? data : []) as ClaimedEvent[];
  let delivered = 0;
  let retried = 0;
  let deadLettered = 0;
  let deferred = 0;

  for (const event of events) {
    if (!event?.outbox_id || !event.lease_token) {
      deferred++;
      continue;
    }

    if (event.channel !== "in_app") {
      // Provider channels are intentionally not implemented. Do not mark these delivered.
      const { data: state, error: failError } = await admin.rpc("staff_leave_outbox_fail", {
        p_outbox_id: event.outbox_id,
        p_lease_token: event.lease_token,
        p_error_code: "CHANNEL_NOT_IMPLEMENTED",
        p_permanent: true,
      });
      if (failError) {
        console.error("Leave notification state update failed", { code: failError.code ?? "STATE_UPDATE_FAILED" });
        deferred++;
      } else if (state === "dead_letter") deadLettered++;
      else retried++;
      continue;
    }

    const { error: deliveryError } = await admin.rpc("staff_leave_outbox_deliver_in_app", {
      p_outbox_id: event.outbox_id,
      p_lease_token: event.lease_token,
    });
    if (!deliveryError) {
      delivered++;
      continue;
    }

    // Keep the persisted error value generic; never write provider response or payload to logs.
    const { data: state, error: failError } = await admin.rpc("staff_leave_outbox_fail", {
      p_outbox_id: event.outbox_id,
      p_lease_token: event.lease_token,
      p_error_code: "IN_APP_DELIVERY_FAILED",
      p_permanent: false,
    });
    if (failError) {
      console.error("Leave notification failure handling failed", { code: failError.code ?? "STATE_UPDATE_FAILED" });
      deferred++;
    } else if (state === "dead_letter") deadLettered++;
    else retried++;
  }

  return response({
    ok: true,
    claimed: events.length,
    delivered_in_app: delivered,
    scheduled_retry: retried,
    dead_lettered: deadLettered,
    deferred,
    note: "This endpoint only processes in_app notifications; email and push are not implemented.",
  });
});
