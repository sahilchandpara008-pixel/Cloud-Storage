// Creates a Bunny Stream video entry and returns everything the caller needs
// to upload the file directly to Bunny over TUS, without ever sending it the
// Bunny API key. Callable by admin (any channel) or by a creator posting into
// their own approved channel -- the same can_post_in() rule that already
// gates every other write to that channel's posts.
//
// Flow: the caller provides channel_id, gets back { videoId,
// authorizationSignature, authorizationExpire, libraryId }, then uses a TUS
// client to upload straight to https://video.bunnycdn.com/tusupload with
// those as headers. Once the upload finishes, the caller inserts the
// post_items row itself (bunny_video_id = videoId), same as for Supabase
// uploads.
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

  let title: string;
  let channelId: string;
  try {
    const body = await req.json();
    title = String(body.title ?? "").trim().slice(0, 200) || "Untitled";
    channelId = String(body.channel_id ?? "");
  } catch {
    return json({ error: "invalid request body" }, 400);
  }
  if (!channelId) return json({ error: "channel_id is required" }, 400);

  const { data: canPost } = await asUser.rpc("can_post_in", { p_channel_id: channelId });
  if (!canPost) return json({ error: "you can't post in this channel" }, 403);

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

  // 6 hours to finish the upload (large videos on slow or flaky connections).
  const authorizationExpire = Math.floor(Date.now() / 1000) + 6 * 3600;
  const authorizationSignature = await sha256Hex(`${libraryId}${apiKey}${authorizationExpire}${videoId}`);

  return json({
    videoId,
    libraryId,
    authorizationSignature,
    authorizationExpire,
  });
});
