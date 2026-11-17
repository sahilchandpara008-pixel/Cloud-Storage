"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { Button, Field, Input, Select } from "@/components/ui";
import { MAX_THUMBNAIL_BYTES, MAX_VIDEO_BYTES, uploadVideoToBunny } from "@/lib/bunny-upload";
import { AUDIENCES } from "@/lib/format";
import {
  MAX_UPLOAD_BYTES,
  extension,
  formatBytes,
  readMedia,
  toJpegThumbnail,
  type MediaInfo,
} from "@/lib/media";
import { createClient } from "@/lib/supabase/browser";
import type { ChannelOption } from "./post-form";

type Row = {
  file: File;
  isVideo: boolean;
  title: string;
  thumb?: File; // optional hand-picked cover (otherwise taken from the video)
  preview?: File; // optional preview clip (played by ads users before they buy)
  state: "waiting" | "uploading" | "encoding" | "done" | "error";
  message?: string;
};

// Lets the admin drop many videos/images into any channel at once (their own
// or one created by a user): each file becomes its own post. Videos -- and
// their optional previews -- are stored on Bunny Stream and streamed from
// there; images go to Supabase Storage. Visibility (audience, premium) follows
// the same rules as every other post -- nothing here bypasses
// post_visible() or the premium gate.
export function BulkUploader({ channels }: { channels: ChannelOption[] }) {
  const router = useRouter();
  const [channelId, setChannelId] = useState(channels[0]?.id ?? "");
  const [folderId, setFolderId] = useState("");
  const [audience, setAudience] = useState("all");
  const [premium, setPremium] = useState(true);
  const [publishNow, setPublishNow] = useState(true);
  const [rows, setRows] = useState<Row[]>([]);
  const [busy, setBusy] = useState(false);

  const channel = useMemo(() => channels.find((c) => c.id === channelId), [channels, channelId]);
  const lockedAudience = channel && channel.audience !== "all" ? channel.audience : null;
  const effectiveAudience = lockedAudience ?? audience;
  const audienceLabel = AUDIENCES.find((a) => a.value === effectiveAudience)?.label ?? effectiveAudience;

  function choose(list: FileList | null) {
    const picked = Array.from(list ?? []).map<Row>((f) => ({
      file: f,
      isVideo: f.type.startsWith("video/"),
      title: f.name.replace(/\.[^.]+$/, ""),
      state: "waiting",
    }));
    setRows((prev) => [...prev, ...picked]);
  }

  function update(i: number, patch: Partial<Row>) {
    setRows((prev) => prev.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  }

  function remove(i: number) {
    setRows((prev) => prev.filter((_, j) => j !== i));
  }

  function pickThumb(i: number, file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("image/")) return update(i, { message: "The thumbnail must be a picture" });
    if (file.size > MAX_THUMBNAIL_BYTES) return update(i, { message: "The thumbnail must be under 5 MB" });
    update(i, { thumb: file, message: undefined });
  }

  function pickPreview(i: number, file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("video/")) return update(i, { message: "The preview must be a video" });
    if (file.size > MAX_VIDEO_BYTES) return update(i, { message: "The preview must be under 2 GB" });
    update(i, { preview: file, message: undefined });
  }

  async function run() {
    setBusy(true);
    const supabase = createClient();
    const { data: userData } = await supabase.auth.getUser();
    const uid = userData.user?.id;
    if (!uid) {
      setBusy(false);
      return;
    }
    const pendingItemIds: string[] = [];

    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      if (r.state !== "waiting") continue;
      const limit = r.isVideo ? MAX_VIDEO_BYTES : MAX_UPLOAD_BYTES;
      if (r.file.size > limit) {
        update(i, { state: "error", message: `Larger than ${r.isVideo ? "2 GB" : "50 MB (free plan limit)"}` });
        continue;
      }
      update(i, { state: "uploading", message: "Reading file…" });
      let createdPostId: string | null = null;
      try {
        // A browser can't always decode a video (MKV, HEVC, ...). That must not
        // block the upload: Bunny takes its own thumbnail and measures the
        // video once it has encoded it (see the bunny-stream-sync function).
        let info: MediaInfo | null = null;
        try {
          info = await readMedia(r.file);
        } catch (e) {
          if (!r.isVideo) throw e;
        }
        // No published_at on purpose: "publish now" is stamped by the database
        // clock (this computer's clock may be wrong, which once hid a video).
        const { data: post, error: postError } = await supabase
          .from("posts")
          .insert({
            channel_id: channelId,
            folder_id: folderId || null,
            title: r.title.trim() || r.file.name,
            audience: effectiveAudience,
            status: publishNow ? "published" : "draft",
            created_by: uid,
          })
          .select("id")
          .single();
        if (postError) throw postError;
        createdPostId = post.id as string;

        // Cover: the hand-picked picture, else a frame from the video, else
        // (browser couldn't decode it) Bunny's own frame is saved later.
        const id = crypto.randomUUID();
        let thumbKey: string | null = null;
        const cover: Blob | null = r.thumb ? await toJpegThumbnail(r.thumb) : (info?.thumbnail ?? null);
        if (cover) {
          thumbKey = `thumbs/${post.id}/${id}.jpg`;
          update(i, { message: "Uploading thumbnail…" });
          const thumb = await supabase.storage
            .from("public")
            .upload(thumbKey, cover, { contentType: "image/jpeg", upsert: false });
          if (thumb.error) throw thumb.error;
        }

        if (r.isVideo) {
          update(i, { message: "Starting video…" });
          const videoId = await uploadVideoToBunny(r.file, channelId, (pct) =>
            update(i, { message: `Uploading video… ${pct}%` }),
          );
          let previewId: string | null = null;
          if (r.preview) {
            previewId = await uploadVideoToBunny(r.preview, channelId, (pct) =>
              update(i, { message: `Uploading preview… ${pct}%` }),
            );
          }

          const { data: item, error } = await supabase
            .from("post_items")
            .insert({
              post_id: post.id,
              position: 0,
              kind: "video",
              is_premium: premium,
              bunny_video_id: videoId,
              trailer_bunny_video_id: previewId,
              trailer_status: previewId ? "pending" : null,
              thumb_key: thumbKey,
              duration_s: info?.durationS ?? null,
              width: info?.width ?? null,
              height: info?.height ?? null,
              processing_status: "pending",
            })
            .select("id")
            .single();
          if (error) throw error;
          pendingItemIds.push(item.id as string);
          update(i, { state: "encoding", message: "Uploaded. Bunny is encoding it; it goes live automatically." });
        } else {
          const mediaKey = `posts/${post.id}/${id}.${extension(r.file)}`;
          update(i, { message: "Uploading…" });
          const media = await supabase.storage
            .from("media")
            .upload(mediaKey, r.file, { contentType: r.file.type, upsert: false });
          if (media.error) throw media.error;

          const { error } = await supabase.from("post_items").insert({
            post_id: post.id,
            position: 0,
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
          update(i, { state: "done", message: undefined });
        }
      } catch (e) {
        // Don't leave an empty post behind: it would show in the app with no media.
        if (createdPostId) await supabase.from("posts").delete().eq("id", createdPostId);
        update(i, { state: "error", message: e instanceof Error ? e.message : "Upload failed" });
      }
    }

    // Videos stay hidden from users until Bunny finishes encoding. The server
    // checks Bunny every minute on its own; poll a few times here as well so
    // short clips show "Posted" without waiting.
    for (let attempt = 0; attempt < 6 && pendingItemIds.length > 0; attempt++) {
      await new Promise((r) => setTimeout(r, 10_000));
      for (const itemId of [...pendingItemIds]) {
        try {
          const { data } = await supabase.functions.invoke("bunny-stream-status", { body: { item_id: itemId } });
          if (data?.status === "ready" || data?.status === "failed") {
            pendingItemIds.splice(pendingItemIds.indexOf(itemId), 1);
            setRows((prev) =>
              prev.map((r) =>
                r.state === "encoding" && pendingItemIds.length === 0 ? { ...r, state: "done" as const } : r,
              ),
            );
          }
        } catch {
          // keep retrying on the next pass
        }
      }
    }
    setRows((prev) =>
      prev.map((r) =>
        r.state === "encoding"
          ? { ...r, message: "Still encoding. It goes live by itself within a minute or two." }
          : r,
      ),
    );

    setBusy(false);
    router.refresh();
  }

  const waiting = rows.filter((r) => r.state === "waiting").length;

  return (
    <div className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Channel">
          <Select value={channelId} onChange={(e) => setChannelId(e.target.value)} disabled={busy}>
            {channels.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
                {c.audience !== "all" ? ` (${c.audience === "ads" ? "Ads only" : "Organic only"})` : ""}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Folder">
          <Select key={channelId} value={folderId} onChange={(e) => setFolderId(e.target.value)} disabled={busy}>
            <option value="">No folder</option>
            {channel?.folders.map((f) => (
              <option key={f.id} value={f.id}>
                {f.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          label="Who can see these posts"
          hint={lockedAudience ? "Set by the channel's audience" : "Everyone, organic users only, or users from your ads only"}
        >
          <Select
            value={effectiveAudience}
            onChange={(e) => setAudience(e.target.value)}
            disabled={busy || !!lockedAudience}
          >
            {AUDIENCES.map((a) => (
              <option key={a.value} value={a.value}>
                {a.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Publishing">
          <Select
            value={publishNow ? "now" : "draft"}
            onChange={(e) => setPublishNow(e.target.value === "now")}
            disabled={busy}
          >
            <option value="now">Publish immediately</option>
            <option value="draft">Save as draft</option>
          </Select>
        </Field>
      </div>

      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={premium}
          onChange={(e) => setPremium(e.target.checked)}
          disabled={busy}
          className="h-4 w-4 accent-red-700"
        />
        👑 Premium: a plan is needed to play the full video (untick to make it free for everyone)
      </label>

      <p className="rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-600">
        {publishNow ? "Goes live as soon as the video is encoded" : "Saved as drafts"} · visible to {audienceLabel} ·{" "}
        {premium ? "👑 full video needs a plan" : "free to play"} · the preview (if you add one) can be watched by
        ads users before they buy.
      </p>

      <div className="rounded-lg border border-dashed border-gray-300 bg-gray-50 p-4">
        <label className="block cursor-pointer text-center text-sm text-gray-600">
          <span className="font-medium text-red-700">Choose videos or images</span>
          <span className="block text-xs text-gray-500">
            Each file becomes its own post. Videos and previews stream from Bunny (up to 2 GB each) · JPG/PNG
            images up to 50 MB
          </span>
          <input
            type="file"
            multiple
            accept="video/*,image/*"
            className="sr-only"
            disabled={busy}
            onChange={(e) => {
              choose(e.target.files);
              e.target.value = "";
            }}
          />
        </label>

        {rows.length > 0 && (
          <>
            <ul className="mt-3 space-y-3">
              {rows.map((r, i) => (
                <li key={i} className="rounded-lg border border-gray-200 bg-white p-3 text-sm">
                  <div className="flex items-start gap-2">
                    <div className="min-w-0 flex-1">
                      <Input
                        value={r.title}
                        onChange={(e) => update(i, { title: e.target.value })}
                        disabled={busy || r.state !== "waiting"}
                        aria-label="Post title"
                      />
                      <p className="mt-1 truncate text-xs text-gray-500">
                        {r.isVideo ? "Video" : "Image"} · {r.file.name} · {formatBytes(r.file.size)}
                      </p>
                    </div>
                    {r.state === "waiting" && !busy && (
                      <button
                        type="button"
                        onClick={() => remove(i)}
                        className="text-xs text-gray-500 hover:text-red-700 hover:underline"
                      >
                        Remove
                      </button>
                    )}
                  </div>

                  {r.isVideo && r.state === "waiting" && (
                    <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
                      <label className="cursor-pointer font-medium text-red-700 hover:underline">
                        {r.thumb ? `Thumbnail: ${r.thumb.name}` : "Add thumbnail"}
                        <input
                          type="file"
                          accept="image/*"
                          className="sr-only"
                          disabled={busy}
                          onChange={(e) => {
                            pickThumb(i, e.target.files?.[0]);
                            e.target.value = "";
                          }}
                        />
                      </label>
                      <label className="cursor-pointer font-medium text-red-700 hover:underline">
                        {r.preview ? `Preview: ${r.preview.name}` : "Add preview"}
                        <input
                          type="file"
                          accept="video/*"
                          className="sr-only"
                          disabled={busy}
                          onChange={(e) => {
                            pickPreview(i, e.target.files?.[0]);
                            e.target.value = "";
                          }}
                        />
                      </label>
                      {!r.thumb && <span className="text-gray-500">No thumbnail? One is taken from the video.</span>}
                    </div>
                  )}

                  {(r.message || r.state === "done") && (
                    <p
                      className={`mt-1 text-xs ${
                        r.state === "done"
                          ? "text-green-700"
                          : r.state === "error"
                            ? "text-red-700"
                            : r.state === "encoding"
                              ? "text-blue-700"
                              : "text-gray-500"
                      }`}
                    >
                      {r.state === "done" ? "Posted" : r.message}
                    </p>
                  )}
                </li>
              ))}
            </ul>
            <Button type="button" onClick={run} disabled={busy || waiting === 0} className="mt-3 w-full">
              {busy ? "Uploading… keep this page open" : `Upload ${waiting} item(s)`}
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
