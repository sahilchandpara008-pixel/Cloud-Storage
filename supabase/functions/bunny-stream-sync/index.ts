// Called every minute by pg_cron (public.bunny_sync_tick) -- no user session.
//
// 1. Bunny videos still "pending": ask Bunny; once encoding has finished, mark
//    the item ready (that is what makes the post visible in the app) and fill
//    in the real duration/size; mark it failed if Bunny reports an error.
// 2. Ready Bunny videos with no thumbnail (admin skipped it, or the browser
//    could not decode the file): take Bunny's own frame from the video and
//    save it as the item's thumbnail.
//
// This is safe to leave without a login: it never reads anything from the
// request, only reconciles our rows with what Bunny says, and it returns early
// when there is nothing to do.
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

// Same Bunny directory-token signing as bunny-stream-url.
async function signBunnyDirectoryUrl(host: string, videoId: string, securityKey: string, file: string) {
  const pathDir = `/${videoId}/`;
  const expires = Math.floor(Date.now() / 1000) + 600;
  const message = pathDir + String(expires) + `token_path=${pathDir}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(securityKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  const token = "HS256-" + b64urlNoPad(digest);
  return `https://${host}/bcdn_token=${token}&token_path=${encodeURIComponent(pathDir)}&expires=${expires}${pathDir}${file}`;
}

type Item = { id: string; post_id: string; bunny_video_id: string; thumb_key: string | null; created_at: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const libraryId = Deno.env.get("BUNNY_STREAM_LIBRARY_ID")!;
  const apiKey = Deno.env.get("BUNNY_STREAM_API_KEY")!;
  const host = Deno.env.get("BUNNY_STREAM_HOST")!;
  const tokenKey = Deno.env.get("BUNNY_STREAM_TOKEN_KEY")!;

  const threeDaysAgo = new Date(Date.now() - 3 * 86_400_000).toISOString();
  const [{ data: pending }, { data: noThumb }] = await Promise.all([
    admin
      .from("post_items")
      .select("id, post_id, bunny_video_id, thumb_key, created_at")
      .eq("processing_status", "pending")
      .not("bunny_video_id", "is", null)
      .order("created_at")
      .limit(25),
    admin
      .from("post_items")
      .select("id, post_id, bunny_video_id, thumb_key, created_at")
      .eq("processing_status", "ready")
      .is("thumb_key", null)
      .not("bunny_video_id", "is", null)
      .gt("created_at", threeDaysAgo)
      .limit(25),
  ]);

  const result = { ready: 0, failed: 0, thumbnails: 0, stillProcessing: 0 };

  async function captureThumbnail(item: Item): Promise<boolean> {
    const res = await fetch(await signBunnyDirectoryUrl(host, item.bunny_video_id, tokenKey, "thumbnail.jpg"));
    if (!res.ok) return false;
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length === 0) return false;
    const key = `thumbs/${item.post_id}/${item.id}.jpg`;
    const { error } = await admin.storage.from("public").upload(key, bytes, {
      contentType: "image/jpeg",
      upsert: true,
    });
    if (error) return false;
    await admin.from("post_items").update({ thumb_key: key }).eq("id", item.id).is("thumb_key", null);
    return true;
  }

  for (const item of (pending ?? []) as Item[]) {
    const res = await fetch(`https://video.bunnycdn.com/library/${libraryId}/videos/${item.bunny_video_id}`, {
      headers: { AccessKey: apiKey, Accept: "application/json" },
    }).catch(() => null);
    if (!res?.ok) continue; // try again next minute

    const video = await res.json();
    // Bunny: 0 Created, 1 Uploaded, 2 Processing, 3 Transcoding, 4 Finished, 5 Error, 6 UploadFailed.
    if (video.status === 4) {
      await admin
        .from("post_items")
        .update({
          processing_status: "ready",
          duration_s: Math.round(video.length ?? 0) || null,
          width: video.width || null,
          height: video.height || null,
        })
        .eq("id", item.id);
      result.ready++;
      if (!item.thumb_key && (await captureThumbnail(item))) result.thumbnails++;
    } else if (video.status === 5 || video.status === 6) {
      await admin.from("post_items").update({ processing_status: "failed" }).eq("id", item.id);
      result.failed++;
    } else if (video.status === 0 && Date.now() - Date.parse(item.created_at) > 12 * 3_600_000) {
      // Created on Bunny but the file never arrived: stop retrying forever.
      await admin.from("post_items").update({ processing_status: "failed" }).eq("id", item.id);
      result.failed++;
    } else {
      result.stillProcessing++;
    }
  }

  for (const item of (noThumb ?? []) as Item[]) {
    if (await captureThumbnail(item)) result.thumbnails++;
  }

  return json(result);
});
