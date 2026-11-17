"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { MAX_VIDEO_BYTES, uploadVideoToBunny } from "@/lib/bunny-upload";
import { formatBytes } from "@/lib/media";
import { createClient } from "@/lib/supabase/browser";

// Add or replace the preview (trailer) of a video item -- played by ads users
// before they buy. It is a second Bunny Stream video, so it streams as
// smoothly as the full video and has no 50 MB limit.
export function TrailerUpload({
  channelId,
  itemId,
  hasTrailer,
}: {
  channelId: string;
  itemId: string;
  hasTrailer: boolean;
}) {
  const router = useRouter();
  const [status, setStatus] = useState<string | null>(null);

  async function onFile(file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("video/")) {
      setStatus("Choose a video file");
      return;
    }
    if (file.size > MAX_VIDEO_BYTES) {
      setStatus(`Max 2 GB (${formatBytes(file.size)})`);
      return;
    }
    const supabase = createClient();
    try {
      setStatus("Starting…");
      const videoId = await uploadVideoToBunny(file, channelId, (pct) => setStatus(`Uploading… ${pct}%`));

      // Replacing: remove the old Bunny preview (the row still points at it
      // until the update below). Best effort -- a leftover never shows in the app.
      if (hasTrailer) {
        await supabase.functions.invoke("bunny-stream-delete", { body: { trailer_item_id: itemId } });
      }

      const { error } = await supabase
        .from("post_items")
        .update({ trailer_bunny_video_id: videoId, trailer_status: "pending", trailer_key: null })
        .eq("id", itemId);
      if (error) throw error;
      setStatus(null);
      router.refresh();
    } catch (e) {
      setStatus(e instanceof Error ? e.message : "Upload failed");
    }
  }

  return (
    <label className="cursor-pointer text-xs font-medium text-red-700 hover:underline">
      {status ?? (hasTrailer ? "Replace preview" : "Add preview")}
      <input type="file" accept="video/*" className="sr-only" onChange={(e) => onFile(e.target.files?.[0])} />
    </label>
  );
}
