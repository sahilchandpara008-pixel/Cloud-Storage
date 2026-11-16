"use client";

import { Upload as TusUpload } from "tus-js-client";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { Button, Field, Select } from "@/components/ui";
import { AUDIENCES } from "@/lib/format";
import { MAX_UPLOAD_BYTES, extension, formatBytes, readMedia } from "@/lib/media";
import { createClient } from "@/lib/supabase/browser";
import type { ChannelOption } from "./post-form";

// Same ceiling as the single-post uploader: Bunny has no practical limit, so
// only images stay capped to the Supabase free-plan size.
const MAX_VIDEO_BYTES = 2 * 1024 * 1024 * 1024; // 2 GB

type Row = {
  file: File;
  isVideo: boolean;
  title: string;
  state: "waiting" | "uploading" | "encoding" | "done" | "error";
  message?: string;
};

// Lets the admin drop many videos/images into one channel at once: each file
// becomes its own post (title from the filename, editable on the post page
// afterwards). Videos go through the exact same Bunny Stream path as the
// single-post uploader; images still go to Supabase Storage. Visibility
// (audience, premium) follows the same rules as every other post -- nothing
// here bypasses post_visible()/the premium gate.
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

  function choose(list: FileList | null) {
    const picked = Array.from(list ?? []);
    setRows(
      picked.map((f) => ({
        file: f,
        isVideo: f.type.startsWith("video/"),
        title: f.name.replace(/\.[^.]+$/, ""),
        state: "waiting",
      })),
    );
  }

  function update(i: number, patch: Partial<Row>) {
    setRows((prev) => prev.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  }

  function uploadToBunny(
    file: File,
    auth: { videoId: string; libraryId: string; authorizationSignature: string; authorizationExpire: number },
    onProgress: (pct: number) => void,
  ) {
    return new Promise<void>((resolve, reject) => {
      const upload = new TusUpload(file, {
        endpoint: "https://video.bunnycdn.com/tusupload",
        retryDelays: [0, 1000, 3000, 5000],
        headers: {
          AuthorizationSignature: auth.authorizationSignature,
          AuthorizationExpire: String(auth.authorizationExpire),
          VideoId: auth.videoId,
          LibraryId: auth.libraryId,
        },
        metadata: { filetype: file.type, title: file.name },
        onError: reject,
        onProgress: (sent, total) => onProgress(Math.round((sent / total) * 100)),
        onSuccess: () => resolve(),
      });
      upload.start();
    });
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
    const publishedAt = publishNow ? new Date().toISOString() : null;
    const pendingItemIds: string[] = [];

    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      const limit = r.isVideo ? MAX_VIDEO_BYTES : MAX_UPLOAD_BYTES;
      if (r.file.size > limit) {
        update(i, { state: "error", message: `Larger than ${r.isVideo ? "2 GB" : "50 MB (free plan limit)"}` });
        continue;
      }
      update(i, { state: "uploading", message: "Reading file…" });
      try {
        const info = await readMedia(r.file);
        const { data: post, error: postError } = await supabase
          .from("posts")
          .insert({
            channel_id: channelId,
            folder_id: folderId || null,
            title: r.title.trim() || r.file.name,
            audience: effectiveAudience,
            status: publishNow ? "published" : "draft",
            published_at: publishedAt,
            created_by: uid,
          })
          .select("id")
          .single();
        if (postError) throw postError;

        const id = crypto.randomUUID();
        const thumbKey = `thumbs/${post.id}/${id}.jpg`;
        update(i, { message: "Uploading thumbnail…" });
        const thumb = await supabase.storage
          .from("public")
          .upload(thumbKey, info.thumbnail, { contentType: "image/jpeg", upsert: false });
        if (thumb.error) throw thumb.error;

        if (r.isVideo) {
          update(i, { message: "Starting video…" });
          const { data: auth, error: createError } = await supabase.functions.invoke("bunny-stream-create", {
            body: { title: r.file.name },
          });
          if (createError) throw createError;
          if (auth?.error) throw new Error(auth.error);

          await uploadToBunny(r.file, auth, (pct) => update(i, { message: `Uploading… ${pct}%` }));

          const { data: item, error } = await supabase
            .from("post_items")
            .insert({
              post_id: post.id,
              position: 0,
              kind: "video",
              is_premium: premium,
              bunny_video_id: auth.videoId,
              thumb_key: thumbKey,
              duration_s: info.durationS,
              width: info.width,
              height: info.height,
              processing_status: "pending",
            })
            .select("id")
            .single();
          if (error) throw error;
          pendingItemIds.push(item.id as string);
          update(i, { state: "encoding", message: "Uploaded; Bunny is encoding it" });
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
            kind: info.kind,
            is_premium: premium,
            media_key: mediaKey,
            thumb_key: thumbKey,
            duration_s: info.durationS,
            width: info.width,
            height: info.height,
            processing_status: "ready",
          });
          if (error) throw error;
          update(i, { state: "done", message: undefined });
        }
      } catch (e) {
        update(i, { state: "error", message: e instanceof Error ? e.message : "Upload failed" });
      }
    }

    // Videos are invisible to users until Bunny finishes encoding (the whole
    // post stays hidden meanwhile). Poll a few times so most clips go live
    // without the admin having to open each post and click "Check encoding".
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
      prev.map((r) => (r.state === "encoding" ? { ...r, message: "Still encoding — check its post later" } : r)),
    );

    setBusy(false);
    router.refresh();
  }

  const ready = rows.some((r) => r.state === "waiting");

  return (
    <div className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Channel">
          <Select value={channelId} onChange={(e) => setChannelId(e.target.value)}>
            {channels.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
                {c.audience !== "all" ? ` (${c.audience === "ads" ? "Ads only" : "Organic only"})` : ""}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Folder">
          <Select key={channelId} value={folderId} onChange={(e) => setFolderId(e.target.value)}>
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
          <Select value={effectiveAudience} onChange={(e) => setAudience(e.target.value)} disabled={!!lockedAudience}>
            {AUDIENCES.map((a) => (
              <option key={a.value} value={a.value}>
                {a.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Publishing">
          <Select value={publishNow ? "now" : "draft"} onChange={(e) => setPublishNow(e.target.value === "now")}>
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
          className="h-4 w-4 accent-red-700"
        />
        Mark every item as 👑 premium (login + plan needed to play)
      </label>

      <div className="rounded-lg border border-dashed border-gray-300 bg-gray-50 p-4">
        <label className="block cursor-pointer text-center text-sm text-gray-600">
          <span className="font-medium text-red-700">Choose videos or images</span>
          <span className="block text-xs text-gray-500">
            Each file becomes its own post in the selected channel. Videos stream from Bunny (up to 2 GB) ·
            JPG/PNG images up to 50 MB
          </span>
          <input
            type="file"
            multiple
            accept="video/*,image/*"
            className="sr-only"
            disabled={busy}
            onChange={(e) => choose(e.target.files)}
          />
        </label>

        {rows.length > 0 && (
          <>
            <ul className="mt-3 space-y-1 text-sm">
              {rows.map((r, i) => (
                <li key={i} className="flex items-center justify-between gap-2">
                  <span className="truncate">
                    {r.title} <span className="text-gray-400">· {formatBytes(r.file.size)}</span>
                  </span>
                  <span
                    className={`shrink-0 text-xs ${
                      r.state === "done"
                        ? "text-green-700"
                        : r.state === "error"
                          ? "text-red-700"
                          : r.state === "encoding"
                            ? "text-blue-700"
                            : "text-gray-500"
                    }`}
                  >
                    {r.state === "done" ? "Posted" : r.message ?? (r.state === "waiting" ? "Ready" : "")}
                  </span>
                </li>
              ))}
            </ul>
            <Button type="button" onClick={run} disabled={busy || !ready} className="mt-3 w-full">
              {busy ? "Uploading…" : `Upload ${rows.length} item(s)`}
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
