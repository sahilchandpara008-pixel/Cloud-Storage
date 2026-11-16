// Returns a signed, time-limited download link for a Bunny-backed personal
// cloud file. Ownership is enforced by cloud_files' own RLS (select only
// your own rows) -- this function never uses the service role, so it can
// never read or sign a path belonging to someone else's file.
//
// Returns { url: null } for a file that isn't Bunny-backed (legacy
// Supabase-storage file): the app falls back to its existing signed-URL code.
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

// Bunny CDN "Advanced Token Authentication", same HS256/token_path scheme
// already verified live for Bunny Stream playback (see bunny-stream-url) --
// here the signed path is the exact file itself rather than a directory of
// segments, which the same prefix-match mechanism handles just as well.
async function signBunnyFileUrl(host: string, path: string, securityKey: string) {
  const rawPath = "/" + path;
  const expires = Math.floor(Date.now() / 1000) + 3600; // 1 hour
  const signingData = `token_path=${rawPath}`;
  const message = rawPath + String(expires) + signingData;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(securityKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  const token = "HS256-" + b64urlNoPad(digest);
  const encodedPath = encodeURIComponent(rawPath);
  return `https://${host}/bcdn_token=${token}&token_path=${encodedPath}&expires=${expires}${rawPath}`;
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

  let fileId: string;
  try {
    const body = await req.json();
    fileId = String(body.file_id ?? "");
  } catch {
    return json({ error: "invalid request body" }, 400);
  }
  if (!fileId) return json({ error: "file_id is required" }, 400);

  const { data: file, error } = await asUser
    .from("cloud_files")
    .select("bunny_path")
    .eq("id", fileId)
    .maybeSingle();
  if (error) return json({ error: error.message }, 400);
  if (!file?.bunny_path) return json({ url: null });

  const host = Deno.env.get("BUNNY_CLOUD_HOST")!;
  const tokenKey = Deno.env.get("BUNNY_CLOUD_TOKEN_KEY")!;
  const signed = await signBunnyFileUrl(host, file.bunny_path, tokenKey);
  return json({ url: signed });
});
