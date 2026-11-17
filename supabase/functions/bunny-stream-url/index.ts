// Returns a signed, time-limited HLS playback URL for a post item that is
// backed by Bunny Stream. Enforces the exact same visibility + premium rule
// as the rest of the app (public.bunny_video_access, called inside
// public.bunny_video_path) -- this function never decides who can watch,
// the database does.
//
// Returns { url: null } for an item that isn't Bunny-backed (legacy
// Supabase-storage item): the app falls back to its existing signed-URL
// code for those.
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

function b64urlNoPad(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Bunny CDN "Advanced Token Authentication" directory token: one signed URL
// covers the whole /{videoId}/ folder (the HLS playlist and every segment
// file inside it), as Bunny's docs recommend for video streaming.
async function signBunnyDirectoryUrl(host: string, videoId: string, securityKey: string, file: string) {
  const pathDir = `/${videoId}/`;
  const expires = Math.floor(Date.now() / 1000) + 3600; // 1 hour
  const signingData = `token_path=${pathDir}`;
  const message = pathDir + String(expires) + signingData;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(securityKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  const token = "HS256-" + b64urlNoPad(digest);
  const encodedPath = encodeURIComponent(pathDir);
  return `https://${host}/bcdn_token=${token}&token_path=${encodedPath}&expires=${expires}${pathDir}${file}`;
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

  let itemId: string;
  let kind: string;
  try {
    const body = await req.json();
    itemId = String(body.item_id ?? "");
    kind = body.kind === "trailer" ? "trailer" : "video";
  } catch {
    return json({ error: "invalid request body" }, 400);
  }
  if (!itemId) return json({ error: "item_id is required" }, 400);

  // The database decides who may watch: the full video follows the audience +
  // premium rule, the trailer follows the (looser) trailer rule.
  const { data: videoId, error: rpcError } = await asUser.rpc(
    kind === "trailer" ? "bunny_trailer_path" : "bunny_video_path",
    { p_item_id: itemId },
  );
  if (rpcError) return json({ error: rpcError.message }, 403);
  if (!videoId) return json({ url: null });

  const host = Deno.env.get("BUNNY_STREAM_HOST")!;
  const securityKey = Deno.env.get("BUNNY_STREAM_TOKEN_KEY")!;
  const playlist = await signBunnyDirectoryUrl(host, videoId, securityKey, "playlist.m3u8");
  return json({ url: playlist });
});
