// Uploads one personal cloud file to Bunny Storage and records it. The
// Bunny Storage password never reaches the device -- the file's bytes are
// streamed through this function to Bunny instead.
//
// Request: POST with the raw file bytes as the body, a Content-Length
// header, and X-File-Name (URL-encoded) / X-Parent-Id / X-File-Mime headers.
// Same premium-only / quota rule as the existing Supabase-storage upload path.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// Proxying the whole file through a function keeps its memory bounded by
// capping the size here, well above the old 50 MB Supabase-plan limit.
const MAX_BYTES = 300 * 1024 * 1024; // 300 MB

function safeName(name: string) {
  return name.replace(/[^A-Za-z0-9._-]/g, "_");
}

async function deleteFromBunny(path: string) {
  const zone = Deno.env.get("BUNNY_CLOUD_ZONE")!;
  const endpoint = Deno.env.get("BUNNY_CLOUD_ENDPOINT")!;
  const password = Deno.env.get("BUNNY_CLOUD_PASSWORD")!;
  await fetch(`https://${endpoint}/${zone}/${path}`, {
    method: "DELETE",
    headers: { AccessKey: password },
  }).catch(() => {});
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  if (userError || !userData.user) return json({ error: "not signed in" }, 401);

  const { data: isPremium } = await asUser.rpc("is_premium_user");
  if (!isPremium) return json({ error: "an active plan is required" }, 403);

  let name: string;
  try {
    name = decodeURIComponent(req.headers.get("X-File-Name") ?? "").trim().slice(0, 255);
  } catch {
    return json({ error: "invalid X-File-Name" }, 400);
  }
  const parentId = req.headers.get("X-Parent-Id") || null;
  const mime = req.headers.get("X-File-Mime") || null;
  if (!name) return json({ error: "X-File-Name is required" }, 400);

  const size = Number(req.headers.get("Content-Length") ?? "0");
  if (!Number.isFinite(size) || size <= 0) return json({ error: "Content-Length is required" }, 400);
  if (size > MAX_BYTES) return json({ error: "Files over 300 MB aren't supported yet" }, 413);

  // Pre-check the quota so we don't push bytes to Bunny only to reject them.
  const { data: status } = await asUser.rpc("my_status");
  const used = Number(status?.used_bytes ?? 0);
  const quota = Number(status?.quota_bytes ?? 0);
  if (used + size > quota) return json({ error: "storage quota exceeded" }, 403);

  const zone = Deno.env.get("BUNNY_CLOUD_ZONE")!;
  const endpoint = Deno.env.get("BUNNY_CLOUD_ENDPOINT")!;
  const password = Deno.env.get("BUNNY_CLOUD_PASSWORD")!;
  const path = `${userData.user.id}/${crypto.randomUUID()}-${safeName(name)}`;

  if (!req.body) return json({ error: "empty body" }, 400);
  const putRes = await fetch(`https://${endpoint}/${zone}/${path}`, {
    method: "PUT",
    headers: { AccessKey: password, "Content-Type": "application/octet-stream" },
    body: req.body,
    // Deno requires this when streaming a body alongside a readable request.
    duplex: "half",
  } as RequestInit);
  if (!putRes.ok) {
    return json({ error: `Bunny rejected the upload (${putRes.status})` }, 502);
  }

  const { data: row, error } = await asUser
    .from("cloud_files")
    .insert({ parent_id: parentId, name, bunny_path: path, mime, size })
    .select("id")
    .single();
  if (error) {
    await deleteFromBunny(path);
    return json({ error: error.message }, 400);
  }

  return json({ id: row.id });
});
