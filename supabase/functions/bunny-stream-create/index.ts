// Admin-only: creates a Bunny Stream video entry and returns everything the
// admin panel's browser needs to upload the file directly to Bunny over TUS,
// without ever sending it the Bunny API key.
//
// Flow: admin panel calls this first, gets { videoId, authorizationSignature,
// authorizationExpire, libraryId }, then uses a TUS client to upload straight
// to https://video.bunnycdn.com/tusupload with those as headers. Once the
// upload finishes, the admin panel inserts the post_items row itself
// (bunny_video_id = videoId), same as it already does for Supabase uploads.
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

async function sha256Hex(message: string): Promise<string> {
  const data = new TextEncoder().encode(message);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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

  const { data: isAdmin } = await asUser.rpc("is_admin");
  if (!isAdmin) return json({ error: "admin accounts only" }, 403);

  let title: string;
  try {
    const body = await req.json();
    title = String(body.title ?? "").trim().slice(0, 200) || "Untitled";
  } catch {
    return json({ error: "invalid request body" }, 400);
  }

  const libraryId = Deno.env.get("BUNNY_STREAM_LIBRARY_ID")!;
  const apiKey = Deno.env.get("BUNNY_STREAM_API_KEY")!;

  const createRes = await fetch(`https://video.bunnycdn.com/library/${libraryId}/videos`, {
    method: "POST",
    headers: { AccessKey: apiKey, Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });
  if (!createRes.ok) {
    return json({ error: `Bunny rejected the video (${createRes.status})` }, 502);
  }
  const created = await createRes.json();
  const videoId = created.guid as string;

  const authorizationExpire = Math.floor(Date.now() / 1000) + 3600; // 1 hour to finish the upload
  const authorizationSignature = await sha256Hex(`${libraryId}${apiKey}${authorizationExpire}${videoId}`);

  return json({
    videoId,
    libraryId,
    authorizationSignature,
    authorizationExpire,
  });
});
