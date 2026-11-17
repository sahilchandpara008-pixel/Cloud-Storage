"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui";
import { MAX_VIDEO_BYTES, uploadVideoToBunny } from "@/lib/bunny-upload";
import { MAX_UPLOAD_BYTES, extension, formatBytes, readMedia, type MediaInfo } from "@/lib/media";
import { createClient } from "@/lib/supabase/browser";

// Videos go to Bunny Stream (seamless adaptive streaming); images still go to
// Supabase Storage as before. Bunny has no practical size limit, so videos
// skip the 50 MB check that still applies to images.

type Row = { name: string; size: number; state: "waiting" | "uploading" | "done" | "error"; message?: string };

export function MediaUploader({
  postId,
  channelId,
  nextPosition,
}: {
  postId: string;
  channelId: string;
  nextPosition: number;
}) {
  const router = useRouter();
  const [files, setFiles] = useState<File[]>([]);
  const [rows, setRows] = useState<Row[]>([]);
  const [premium, setPremium] = useState(true);
  const [busy, setBusy] = useState(false);

  function choose(list: FileList | null) {
    const picked = Array.from(list ?? []);
    setFiles(picked);
    setRows(
      picked.map((f) => {
        const isVideo = f.type.startsWith("video/");
        const limit = isVideo ? MAX_VIDEO_BYTES : MAX_UPLOAD_BYTES;
        return {
          name: f.name,
          size: f.size,
          state: f.size > limit ? "error" : "waiting",
          message: f.size > limit ? `Larger than ${isVideo ? "2 GB" : "50 MB (free plan limit)"}` : undefined,
        };
      }),
    );
  }

  function update(i: number, patch: Partial<Row>) {
    setRows((prev) => prev.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  }

  async function upload() {
    setBusy(true);
    const supabase = createClient();
    let position = nextPosition;

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const isVideo = file.type.startsWith("video/");
      const limit = isVideo ? MAX_VIDEO_BYTES : MAX_UPLOAD_BYTES;
      if (file.size > limit) continue;
      update(i, { state: "uploading", message: "Reading file…" });
      try {
        // If the browser can't decode a video, carry on: Bunny takes its own
        // thumbnail and measures the video once it has encoded it.
        let info: MediaInfo | null = null;
        try {
          info = await readMedia(file);
        } catch (e) {
          if (!isVideo) throw e;
        }
        const id = crypto.randomUUID();
        let thumbKey: string | null = null;
        if (info) {
          thumbKey = `thumbs/${postId}/${id}.jpg`;
          update(i, { message: "Uploading thumbnail…" });
          const thumb = await supabase.storage
            .from("public")
            .upload(thumbKey, info.thumbnail, { contentType: "image/jpeg", upsert: false });
          if (thumb.error) throw thumb.error;
        }

        if (isVideo) {
          update(i, { message: "Starting video…" });
          const videoId = await uploadVideoToBunny(file, channelId, (pct) =>
            update(i, { message: `Uploading… ${pct}%` }),
          );

          const { error } = await supabase.from("post_items").insert({
            post_id: postId,
            position: position++,
            kind: "video",
            is_premium: premium,
            bunny_video_id: videoId,
            thumb_key: thumbKey,
            duration_s: info?.durationS ?? null,
            width: info?.width ?? null,
            height: info?.height ?? null,
            processing_status: "pending",
          });
          if (error) throw error;
        } else {
          const mediaKey = `posts/${postId}/${id}.${extension(file)}`;
          update(i, { message: "Uploading…" });
          const media = await supabase.storage
            .from("media")
            .upload(mediaKey, file, { contentType: file.type, upsert: false });
          if (media.error) throw media.error;

          const { error } = await supabase.from("post_items").insert({
            post_id: postId,
            position: position++,
            kind: info!.kind,
            is_premium: premium,
            media_key: mediaKey,
            thumb_key: thumbKey,
            duration_s: info!.durationS,
            width: info!.width,
            height: info!.height,
            processing_status: "ready",
          });
          if (error) throw error;
        }
        update(i, { state: "done", message: undefined });
      } catch (e) {
        update(i, { state: "error", message: e instanceof Error ? e.message : "Upload failed" });
      }
    }

    setBusy(false);
    router.refresh();
  }

  const ready = rows.some((r) => r.state === "waiting");

  return (
    <div className="rounded-lg border border-dashed border-gray-300 bg-gray-50 p-4">
      <label className="block cursor-pointer text-center text-sm text-gray-600">
        <span className="font-medium text-red-700">Choose videos or images</span>
        <span className="block text-xs text-gray-500">
          Videos stream from Bunny (up to 2 GB) · JPG/PNG images up to 50 MB
        </span>
        <input
          type="file"
          multiple
          accept="video/*,image/*"
          className="sr-only"
          disabled={busy}
          onChange={(e) => choose(e.target.files)}
          data-testid="media-input"
        />
      </label>

      {rows.length > 0 && (
        <>
          <ul className="mt-3 space-y-1 text-sm">
            {rows.map((r, i) => (
              <li key={i} className="flex items-center justify-between gap-2">
                <span className="truncate">
                  {r.name} <span className="text-gray-400">· {formatBytes(r.size)}</span>
                </span>
                <span
                  className={`shrink-0 text-xs ${
                    r.state === "done" ? "text-green-700" : r.state === "error" ? "text-red-700" : "text-gray-500"
                  }`}
                >
                  {r.state === "done" ? "Uploaded" : r.message ?? (r.state === "waiting" ? "Ready" : "")}
                </span>
              </li>
            ))}
          </ul>
          <label className="mt-3 flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={premium}
              onChange={(e) => setPremium(e.target.checked)}
              className="h-4 w-4 accent-red-700"
            />
            Mark as 👑 premium
          </label>
          <Button type="button" onClick={upload} disabled={busy || !ready} className="mt-3 w-full">
            {busy ? "Uploading…" : "Upload"}
          </Button>
        </>
      )}
    </div>
  );
}
