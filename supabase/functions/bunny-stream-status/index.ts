// Checks a Bunny Stream video's encoding status and, once it has finished,
// marks the post_item ready and fills in its real duration/size. Callable by
// admin or by the post's own creator (can_post_in() on its channel) -- the
// same rule that already gates every other write to that channel's posts.
// Reads/writes bunny_video_id with the service role (not RLS) because that
// column is hidden from every client by column grants -- even the uploader's
// own browser session can't read it directly -- but authorization is checked
// first, via RLS, through the caller's own session.
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
  try {
    const body = await req.json();
    itemId = String(body.item_id ?? "");
  } catch {
    return json({ error: "invalid request body" }, 400);
  }
  if (!itemId) return json({ error: "item_id is required" }, 400);

  // Authorization: RLS only returns this row if the caller is admin or can
  // post in the item's channel (items_manage policy) -- no row means no.
  const { data: ownItem } = await asUser.from("post_items").select("id").eq("id", itemId).maybeSingle();
  if (!ownItem) return json({ error: "not found, or you can't manage this item" }, 403);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: item, error: itemError } = await admin
    .from("post_items")
    .select("bunny_video_id, processing_status")
    .eq("id", itemId)
    .maybeSingle();
  if (itemError) return json({ error: itemError.message }, 500);
  if (!item?.bunny_video_id) return json({ error: "not a Bunny-backed item" }, 400);
  if (item.processing_status === "ready") return json({ status: "ready" });

  const libraryId = Deno.env.get("BUNNY_STREAM_LIBRARY_ID")!;
  const apiKey = Deno.env.get("BUNNY_STREAM_API_KEY")!;
  const res = await fetch(`https://video.bunnycdn.com/library/${libraryId}/videos/${item.bunny_video_id}`, {
    headers: { AccessKey: apiKey, Accept: "application/json" },
  });
  if (!res.ok) return json({ error: `Bunny lookup failed (${res.status})` }, 502);
  const video = await res.json();

  // Bunny status: 0 Created, 1 Uploaded, 2 Processing, 3 Transcoding,
  // 4 Finished, 5 Error, 6 UploadFailed.
  if (video.status === 4) {
    await admin
      .from("post_items")
      .update({
        processing_status: "ready",
        duration_s: Math.round(video.length ?? 0) || null,
        width: video.width || null,
        height: video.height || null,
      })
      .eq("id", itemId);
    return json({ status: "ready" });
  }
  if (video.status === 5 || video.status === 6) {
    await admin.from("post_items").update({ processing_status: "failed" }).eq("id", itemId);
    return json({ status: "failed" });
  }
  // encodeProgress: Bunny's own 0-100 encoding progress, shown in the admin.
  const progress = Number.isFinite(video.encodeProgress) ? Math.max(0, Math.min(100, Math.round(video.encodeProgress))) : null;
  return json({ status: "processing", progress, bunny_status: video.status });
});
