// Sends queued push notifications through Firebase Cloud Messaging (HTTP v1).
//
// Called every minute by pg_cron (public.push_tick) when something is queued,
// and right after the owner presses Send in the admin panel. No login: it
// takes NOTHING from the request; it only sends deliveries the database has
// already queued (owner-only admin_push_create), so calling it can never
// send anything new. GET returns whether the Firebase key is set (no secrets);
// GET ?check=1 also tests the Firebase sign-in.
//
// Secret: FCM_SERVICE_ACCOUNT = the Firebase service-account JSON
// (Firebase console -> Project settings -> Service accounts -> Generate key).
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

type Account = { project_id: string; client_email: string; private_key: string };

function serviceAccount(): Account | null {
  try {
    const a = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "");
    if (a?.project_id && a?.client_email && a?.private_key) return a as Account;
  } catch {
    // not set or not JSON
  }
  return null;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cached: { token: string; until: number } | null = null;

// OAuth access token for FCM from the service account (signed JWT, RS256).
async function accessToken(a: Account): Promise<string> {
  if (cached && cached.until > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(
    JSON.stringify({
      iss: a.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const pem = a.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    throw new Error(`Firebase login failed (${res.status}): ${body.error_description ?? body.error ?? "unknown"}`);
  }
  cached = { token: body.access_token, until: Date.now() + (Number(body.expires_in ?? 3600) - 60) * 1000 };
  return cached.token;
}

type Item = {
  id: number;
  token: string;
  mid: string;
  title: string;
  body: string;
  image: string | null;
  type: string;
  target: string | null;
  url: string | null;
};
type Result = { id: number; ok: boolean; error?: string; unregistered?: boolean; retry?: boolean };

async function sendOne(a: Account, bearer: string, it: Item): Promise<Result> {
  const data: Record<string, string> = { mid: it.mid, type: it.type };
  if (it.target) data.id = it.target;
  if (it.url) data.url = it.url;
  const notification: Record<string, string> = { title: it.title };
  if (it.body) notification.body = it.body;
  if (it.image) notification.image = it.image;
  try {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${a.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: it.token,
          notification,
          data,
          android: {
            priority: "high",
            notification: { channel_id: "flixvault_updates", ...(it.image ? { image: it.image } : {}) },
          },
        },
      }),
    });
    if (res.ok) return { id: it.id, ok: true };
    const body = await res.json().catch(() => ({}));
    const status: string = body?.error?.status ?? "";
    const code: string =
      (body?.error?.details ?? []).find((d: { errorCode?: string }) => d?.errorCode)?.errorCode ?? status;
    const msg = `${res.status} ${code}: ${body?.error?.message ?? ""}`.trim();
    const unregistered =
      code === "UNREGISTERED" ||
      (res.status === 400 && /registration token/i.test(body?.error?.message ?? ""));
    const retry = res.status === 429 || res.status >= 500;
    return { id: it.id, ok: false, error: msg, unregistered, retry };
  } catch (e) {
    return { id: it.id, ok: false, error: String(e).slice(0, 200), retry: true };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const a = serviceAccount();
  if (req.method === "GET") {
    // ?check=1 also signs in to Firebase (sends nothing) to prove the key works.
    let login: string | undefined;
    if (a && new URL(req.url).searchParams.get("check") === "1") {
      try {
        await accessToken(a);
        login = "ok";
      } catch (e) {
        login = String(e).slice(0, 200);
      }
    }
    return json({ key: !!a, project: a?.project_id ?? null, ...(login ? { login } : {}) });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const started = Date.now();
  let sent = 0;
  let failed = 0;
  while (Date.now() - started < 45_000) {
    const { data: items, error } = await db.rpc("push_claim", { p_limit: 500 });
    if (error) return json({ error: error.message }, 500);
    const list = (items ?? []) as Item[];
    if (list.length === 0) break;
    let results: Result[] = [];
    if (!a) {
      results = list.map((it) => ({ id: it.id, ok: false, error: "Firebase key (FCM_SERVICE_ACCOUNT) is not set" }));
    } else {
      let bearer = "";
      try {
        bearer = await accessToken(a);
      } catch (e) {
        results = list.map((it) => ({ id: it.id, ok: false, error: String(e).slice(0, 280) }));
      }
      if (bearer) {
        results = [];
        for (let i = 0; i < list.length; i += 25) {
          results.push(...(await Promise.all(list.slice(i, i + 25).map((it) => sendOne(a, bearer, it)))));
        }
      }
    }
    const { error: finErr } = await db.rpc("push_finish", { p_results: results });
    if (finErr) return json({ error: finErr.message }, 500);
    sent += results.filter((r) => r.ok).length;
    failed += results.filter((r) => !r.ok).length;
  }
  return json({ sent, failed });
});
