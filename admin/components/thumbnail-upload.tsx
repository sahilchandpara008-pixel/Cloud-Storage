"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { MAX_THUMBNAIL_BYTES } from "@/lib/bunny-upload";
import { prepareThumbnail } from "@/lib/media";
import { createClient } from "@/lib/supabase/browser";
import { smallAction } from "./ui";

// Add or replace the thumbnail (cover picture) of a video item.
export function ThumbnailUpload({
  postId,
  itemId,
  currentKey,
}: {
  postId: string;
  itemId: string;
  currentKey: string | null;
}) {
  const router = useRouter();
  const [status, setStatus] = useState<string | null>(null);

  async function onFile(file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      setStatus("Choose a picture");
      return;
    }
    if (file.size > MAX_THUMBNAIL_BYTES) {
      setStatus("Max 5 MB");
      return;
    }
    const supabase = createClient();
    try {
      setStatus("Uploading…");
      const cover = await prepareThumbnail(file);
      const key = `thumbs/${postId}/${crypto.randomUUID()}.${cover.ext}`;
      const up = await supabase.storage
        .from("public")
        .upload(key, cover.blob, { contentType: cover.contentType, upsert: false });
      if (up.error) throw up.error;
      const { error } = await supabase.from("post_items").update({ thumb_key: key }).eq("id", itemId);
      if (error) throw error;
      // The old picture is no longer used anywhere. Best effort.
      if (currentKey) await supabase.storage.from("public").remove([currentKey]);
      setStatus(null);
      router.refresh();
    } catch (e) {
      setStatus(e instanceof Error ? e.message : "Upload failed");
    }
  }

  return (
    <label className={smallAction}>
      🖼 {status ?? (currentKey ? "Change thumbnail" : "Add thumbnail")}
      <input type="file" accept="image/*" className="sr-only" onChange={(e) => onFile(e.target.files?.[0])} />
    </label>
  );
}
