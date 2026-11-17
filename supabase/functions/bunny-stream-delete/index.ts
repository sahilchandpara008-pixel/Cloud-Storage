// Admin-only: deletes the Bunny Stream video(s) backing a channel's, a
// post's, or a single item's content. Used when the admin panel deletes a
// channel or a post, so Bunny-hosted videos don't become orphaned (kept
// forever, still counted against the library's storage/bandwidth).
//
// Looks up bunny_video_id with the service role, since that column is
// hidden from every client (even the admin panel's own browser session) by
// column grants -- the admin never needs to see the raw id, only trigger
// its deletion.
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

  const { data: isAdmin } = await asUser.rpc("is_admin");
  if (!isAdmin) return json({ error: "admin accounts only" }, 403);

  let channelId: string | null;
  let postId: string | null;
  let itemId: string | null;
  let trailerItemId: string | null;
  try {
    const body = await req.json();
    channelId = body.channel_id ? String(body.channel_id) : null;
    postId = body.post_id ? String(body.post_id) : null;
    itemId = body.item_id ? String(body.item_id) : null;
    // Only the item's trailer (used when an admin replaces a trailer).
    trailerItemId = body.trailer_item_id ? String(body.trailer_item_id) : null;
  } catch {
    return json({ error: "invalid request body" }, 400);
  }
  if ([channelId, postId, itemId, trailerItemId].filter(Boolean).length !== 1) {
    return json({ error: "exactly one of channel_id, post_id, item_id, trailer_item_id is required" }, 400);
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // An item can hold two Bunny videos: the full video and its trailer.
  let query = admin.from("post_items").select("bunny_video_id, trailer_bunny_video_id");
  if (trailerItemId) {
    query = query.eq("id", trailerItemId);
  } else if (itemId) {
    query = query.eq("id", itemId);
  } else if (postId) {
    query = query.eq("post_id", postId);
  } else {
    const { data: posts, error: postsError } = await admin.from("posts").select("id").eq("channel_id", channelId!);
    if (postsError) return json({ error: postsError.message }, 500);
    const postIds = (posts ?? []).map((p) => p.id as string);
    if (postIds.length === 0) return json({ deleted: 0 });
    query = query.in("post_id", postIds);
  }

  const { data: items, error } = await query;
  if (error) return json({ error: error.message }, 500);
  const videoIds = (items ?? [])
    .flatMap((i) => (trailerItemId ? [i.trailer_bunny_video_id] : [i.bunny_video_id, i.trailer_bunny_video_id]))
    .filter((id): id is string => typeof id === "string" && id.length > 0);
  if (videoIds.length === 0) return json({ deleted: 0 });

  const libraryId = Deno.env.get("BUNNY_STREAM_LIBRARY_ID")!;
  const apiKey = Deno.env.get("BUNNY_STREAM_API_KEY")!;
  let deleted = 0;
  await Promise.all(
    videoIds.map(async (videoId) => {
      const res = await fetch(`https://video.bunnycdn.com/library/${libraryId}/videos/${videoId}`, {
        method: "DELETE",
        headers: { AccessKey: apiKey },
      }).catch(() => null);
      if (res?.ok) deleted++;
    }),
  );

  return json({ deleted });
});
