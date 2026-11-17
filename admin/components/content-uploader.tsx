"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Button, Field, Input, Select, Textarea } from "@/components/ui";
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
  file: File; // the main content
  isVideo: boolean;
  title: string;
  caption: string;
  thumb?: File; // optional hand-picked cover (otherwise taken from the video / image)
  preview?: File; // optional preview clip (videos only; ads users watch it before they buy)
  state: "waiting" | "uploading" | "encoding" | "done" | "error";
  message?: string;
};

type PublishMode = "now" | "schedule" | "draft";

// One box: shows what is chosen, or a clear button to choose it.
function Slot({
  title,
  required,
  hint,
  accept,
  file,
  disabled,
  onPick,
  onClear,
}: {
  title: string;
  required?: boolean;
  hint: string;
  accept?: string;
  file?: File;
  disabled?: boolean;
  onPick?: (file: File | undefined) => void;
  onClear?: () => void;
}) {
  return (
    <div className="rounded-lg border border-gray-200 bg-gray-50 p-2.5 text-xs">
      <p className="font-medium text-gray-800">
        {title}
        <span className="font-normal text-gray-400">{required ? " · required" : " · optional"}</span>
      </p>
      {file ? (
        <div className="mt-1 flex items-center justify-between gap-2">
          <span className="min-w-0 truncate text-gray-700">
            ✓ {file.name} · {formatBytes(file.size)}
          </span>
          {onClear && !disabled && (
            <button type="button" onClick={onClear} className="shrink-0 text-gray-500 hover:text-red-700 hover:underline">
              Remove
            </button>
          )}
        </div>
      ) : (
        <label
          className={`mt-1 inline-block rounded-md border border-gray-300 bg-white px-2.5 py-1 font-medium text-red-700 ${
            disabled ? "opacity-50" : "cursor-pointer hover:bg-gray-100"
          }`}
        >
          Choose file
          <input
            type="file"
            accept={accept}
            className="sr-only"
            disabled={disabled}
            onChange={(e) => {
              onPick?.(e.target.files?.[0]);
              e.target.value = "";
            }}
          />
        </label>
      )}
      <p className="mt-1 text-gray-500">{hint}</p>
    </div>
  );
}

// Upload content into any channel (the admin's own or one created by a user).
//   single: ONE post. The main file, the preview and the thumbnail are three
//           boxes you see straight away, plus title and caption.
//   bulk:   MANY files at once, each becoming its own post with its own
//           optional preview and thumbnail.
// Videos and previews are stored on Bunny Stream and streamed from there;
// images go to Supabase Storage. Visibility (audience, premium) follows the same
// rules as every other post -- nothing here bypasses post_visible() or the
// premium gate.
export function ContentUploader({
  channels,
  initialChannelId,
  mode,
  onBusyChange,
}: {
  channels: ChannelOption[];
  initialChannelId?: string;
  mode: "single" | "bulk";
  onBusyChange?: (busy: boolean) => void;
}) {
  const router = useRouter();
  const single = mode === "single";
  const [channelId, setChannelId] = useState(
    channels.some((c) => c.id === initialChannelId) ? (initialChannelId as string) : (channels[0]?.id ?? ""),
  );
  const [folderId, setFolderId] = useState("");
  const [audience, setAudience] = useState("all");
  const [premium, setPremium] = useState(true);
  const [publishMode, setPublishMode] = useState<PublishMode>("now");
  const [publishLocal, setPublishLocal] = useState("");
  const [rows, setRows] = useState<Row[]>([]);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  // Single mode: the preview / thumbnail / title / caption can be filled in
  // before the main file is chosen; they move into the row once it is.
  const [pre, setPre] = useState<{ thumb?: File; preview?: File }>({});
  const [preTitle, setPreTitle] = useState("");
  const [preCaption, setPreCaption] = useState("");

  useEffect(() => {
    onBusyChange?.(busy);
  }, [busy, onBusyChange]);

  const channel = useMemo(() => channels.find((c) => c.id === channelId), [channels, channelId]);
  const lockedAudience = channel && channel.audience !== "all" ? channel.audience : null;
  const effectiveAudience = lockedAudience ?? audience;
  const audienceLabel = AUDIENCES.find((a) => a.value === effectiveAudience)?.label ?? effectiveAudience;

  function update(i: number, patch: Partial<Row>) {
    setRows((prev) => prev.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  }

  function remove(i: number) {
    setRows((prev) => prev.filter((_, j) => j !== i));
  }

  // Bulk: add files as new rows.
  function choose(list: FileList | null) {
    const picked = Array.from(list ?? []).map<Row>((f) => ({
      file: f,
      isVideo: f.type.startsWith("video/"),
      title: f.name.replace(/\.[^.]+$/, ""),
      caption: "",
      state: "waiting",
    }));
    setRows((prev) => [...prev, ...picked]);
  }

  // Single: the main file was chosen -> build the one row, keeping anything
  // already filled in.
  function startFromFile(file: File | undefined) {
    if (!file) return;
    const isVideo = file.type.startsWith("video/");
    if (!isVideo && !file.type.startsWith("image/")) {
      setFormError("Choose a video or an image as the main file.");
      return;
    }
    setFormError(null);
    setRows([
      {
        file,
        isVideo,
        title: preTitle.trim() || file.name.replace(/\.[^.]+$/, ""),
        caption: preCaption,
        thumb: pre.thumb,
        preview: isVideo ? pre.preview : undefined,
        state: "waiting",
        message: !isVideo && pre.preview ? "Previews are for videos only, so the preview was left out." : undefined,
      },
    ]);
    setPre({});
    setPreTitle("");
    setPreCaption("");
  }

  // Single: take the main file back out (to choose another one).
  function clearMain() {
    const r = rows[0];
    if (r) {
      setPre({ thumb: r.thumb, preview: r.preview });
      setPreTitle(r.title);
      setPreCaption(r.caption);
    }
    setRows([]);
  }

  function checkThumb(file: File | undefined): string | null {
    if (!file) return null;
    if (!file.type.startsWith("image/")) return "The thumbnail must be a picture";
    if (file.size > MAX_THUMBNAIL_BYTES) return "The thumbnail must be under 5 MB";
    return null;
  }

  function checkPreview(file: File | undefined): string | null {
    if (!file) return null;
    if (!file.type.startsWith("video/")) return "The preview must be a video";
    if (file.size > MAX_VIDEO_BYTES) return "The preview must be under 2 GB";
    return null;
  }

  function pickThumb(i: number, file: File | undefined) {
    const bad = checkThumb(file);
    if (bad) return update(i, { message: bad });
    if (file) update(i, { thumb: file, message: undefined });
  }

  function pickPreview(i: number, file: File | undefined) {
    const bad = checkPreview(file);
    if (bad) return update(i, { message: bad });
    if (file) update(i, { preview: file, message: undefined });
  }

  function pickPreThumb(file: File | undefined) {
    const bad = checkThumb(file);
    if (bad) return setFormError(bad);
    setFormError(null);
    if (file) setPre((p) => ({ ...p, thumb: file }));
  }

  function pickPrePreview(file: File | undefined) {
    const bad = checkPreview(file);
    if (bad) return setFormError(bad);
    setFormError(null);
    if (file) setPre((p) => ({ ...p, preview: file }));
  }

  async function run() {
    setFormError(null);
    // "Publish at" is a time the admin typed, not this computer's clock.
    let scheduledAt: string | null = null;
    if (publishMode === "schedule") {
      const when = publishLocal ? new Date(publishLocal) : null;
      if (!when || Number.isNaN(when.getTime())) {
        setFormError("Pick the date and time to publish at.");
        return;
      }
      scheduledAt = when.toISOString();
    }

    setBusy(true);
    const supabase = createClient();
    const { data: userData } = await supabase.auth.getUser();
    const uid = userData.user?.id;
    if (!uid) {
      setBusy(false);
      return;
    }
    const pendingItemIds: string[] = [];
    const okPostIds: string[] = [];

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
        // "Publish now" sends no published_at: the database clock stamps it
        // (this computer's clock may be wrong, which once hid a video).
        const { data: post, error: postError } = await supabase
          .from("posts")
          .insert({
            channel_id: channelId,
            folder_id: folderId || null,
            title: r.title.trim() || r.file.name,
            caption: r.caption.trim() || null,
            audience: effectiveAudience,
            status: publishMode === "draft" ? "draft" : "published",
            ...(scheduledAt ? { published_at: scheduledAt } : {}),
            created_by: uid,
          })
          .select("id")
          .single();
        if (postError) throw postError;
        createdPostId = post.id as string;

        // Cover: the hand-picked picture, else a frame from the video (or the
        // image itself), else (browser couldn't decode it) Bunny's own frame is
        // saved later.
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
            update(i, { message: `Uploading main video… ${pct}%` }),
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
          okPostIds.push(post.id as string);
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
          okPostIds.push(post.id as string);
          update(i, { state: "done", message: undefined });
        }
      } catch (e) {
        // Don't leave an empty post behind: it would show in the app with no media.
        if (createdPostId) await supabase.from("posts").delete().eq("id", createdPostId);
        update(i, { state: "error", message: e instanceof Error ? e.message : "Upload failed" });
      }
    }

    // One item uploaded: go straight to its post (the post page shows the
    // encoding progress and lets the admin adjust anything).
    if (rows.length === 1 && okPostIds.length === 1) {
      setBusy(false);
      router.push(`/posts/${okPostIds[0]}`);
      return;
    }

    // Several items: videos stay hidden from users until Bunny finishes
    // encoding. The server checks Bunny every minute on its own; poll a few
    // times here as well so short clips show "Posted" without waiting.
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
  const uploadLabel = busy
    ? "Uploading… keep this page open"
    : single
      ? publishMode === "draft"
        ? "Upload and save as draft"
        : publishMode === "schedule"
          ? "Upload and schedule"
          : "Upload and publish"
      : `Upload ${waiting} item(s)`;

  function renderRow(r: Row, i: number) {
    const editable = !busy && r.state === "waiting";
    return (
      <li key={i} className="rounded-lg border border-gray-200 bg-white p-3 text-sm">
        <div className="flex items-start gap-2">
          <div className="min-w-0 flex-1 space-y-2">
            <Input
              value={r.title}
              onChange={(e) => update(i, { title: e.target.value })}
              disabled={!editable}
              placeholder="Title"
              aria-label="Post title"
            />
            <Textarea
              value={r.caption}
              onChange={(e) => update(i, { caption: e.target.value })}
              disabled={!editable}
              placeholder="Caption (optional)"
              aria-label="Post caption"
              rows={2}
            />
          </div>
          {editable && !single && (
            <button
              type="button"
              onClick={() => remove(i)}
              className="text-xs text-gray-500 hover:text-red-700 hover:underline"
            >
              Remove
            </button>
          )}
        </div>

        <div className={`mt-3 grid gap-2 ${r.isVideo ? "sm:grid-cols-3" : "sm:grid-cols-2"}`}>
          <Slot
            title={r.isVideo ? "Main video" : "Main image"}
            required
            file={r.file}
            hint={r.isVideo ? "The full video." : "The picture itself."}
            disabled={!single || !editable}
            onClear={single ? clearMain : undefined}
          />
          {r.isVideo && (
            <Slot
              title="Preview"
              accept="video/*"
              file={r.preview}
              disabled={!editable}
              onPick={(f) => pickPreview(i, f)}
              onClear={() => update(i, { preview: undefined })}
              hint="A short clip ads users can watch before buying."
            />
          )}
          <Slot
            title="Thumbnail"
            accept="image/*"
            file={r.thumb}
            disabled={!editable}
            onPick={(f) => pickThumb(i, f)}
            onClear={() => update(i, { thumb: undefined })}
            hint={`The cover picture. Empty: taken from the ${r.isVideo ? "video" : "image"} automatically.`}
          />
        </div>

        {(r.message || r.state === "done") && (
          <p
            className={`mt-2 text-xs ${
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
    );
  }

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
          label="Who can see this"
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
          <Select value={publishMode} onChange={(e) => setPublishMode(e.target.value as PublishMode)} disabled={busy}>
            <option value="now">Publish immediately</option>
            <option value="schedule">Schedule for a date and time</option>
            <option value="draft">Save as draft</option>
          </Select>
        </Field>
        {publishMode === "schedule" && (
          <Field label="Publish at" hint="Your local time. It goes live then, once its video is encoded.">
            <Input
              type="datetime-local"
              value={publishLocal}
              onChange={(e) => setPublishLocal(e.target.value)}
              disabled={busy}
            />
          </Field>
        )}
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
        {publishMode === "now"
          ? "Goes live as soon as the video is encoded"
          : publishMode === "schedule"
            ? "Goes live at the time you pick"
            : "Saved as a draft"}{" "}
        · visible to {audienceLabel} · {premium ? "👑 full video needs a plan" : "free to play"} · the preview (if you
        add one) can be watched by ads users before they buy.
      </p>

      {single ? (
        <div className="space-y-3">
          {rows.length === 0 ? (
            <div className="space-y-3 rounded-lg border border-gray-200 bg-white p-3 text-sm">
              <Input
                value={preTitle}
                onChange={(e) => setPreTitle(e.target.value)}
                placeholder="Title (filled in from the file name if you leave it empty)"
                aria-label="Post title"
              />
              <Textarea
                value={preCaption}
                onChange={(e) => setPreCaption(e.target.value)}
                placeholder="Caption (optional)"
                aria-label="Post caption"
                rows={2}
              />
              <div className="grid gap-2 sm:grid-cols-3">
                <Slot
                  title="Main file"
                  required
                  accept="video/*,image/*"
                  onPick={startFromFile}
                  hint="The full video, or the picture. Up to 2 GB for a video."
                />
                <Slot
                  title="Preview"
                  accept="video/*"
                  file={pre.preview}
                  onPick={pickPrePreview}
                  onClear={() => setPre((p) => ({ ...p, preview: undefined }))}
                  hint="A short clip ads users can watch before buying (videos only)."
                />
                <Slot
                  title="Thumbnail"
                  accept="image/*"
                  file={pre.thumb}
                  onPick={pickPreThumb}
                  onClear={() => setPre((p) => ({ ...p, thumb: undefined }))}
                  hint="The cover picture. Empty: taken from the main file automatically."
                />
              </div>
              {formError && <p className="text-sm text-red-700">{formError}</p>}
              <Button type="button" disabled className="w-full">
                Choose the main file to continue
              </Button>
            </div>
          ) : (
            <>
              <ul className="space-y-3">{rows.map(renderRow)}</ul>
              {formError && <p className="text-sm text-red-700">{formError}</p>}
              <Button type="button" onClick={run} disabled={busy || waiting === 0} className="w-full">
                {uploadLabel}
              </Button>
            </>
          )}
        </div>
      ) : (
        <div className="rounded-lg border border-dashed border-gray-300 bg-gray-50 p-4">
          <label className="block cursor-pointer text-center text-sm text-gray-600">
            <span className="font-medium text-red-700">Choose many videos or images at once</span>
            <span className="block text-xs text-gray-500">
              Each file becomes its own post, with its own title, preview and thumbnail boxes below. Videos and
              previews stream from Bunny (up to 2 GB each) · JPG/PNG images up to 50 MB
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
              <ul className="mt-3 space-y-3">{rows.map(renderRow)}</ul>
              {formError && <p className="mt-3 text-sm text-red-700">{formError}</p>}
              <Button type="button" onClick={run} disabled={busy || waiting === 0} className="mt-3 w-full">
                {uploadLabel}
              </Button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
