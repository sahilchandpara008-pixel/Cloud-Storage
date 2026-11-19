import { CheckEncoding } from "@/components/check-encoding";
import { ThumbnailUpload } from "@/components/thumbnail-upload";
import { TrailerUpload } from "@/components/trailer-upload";
import { Badge, smallAction } from "@/components/ui";
import { AUDIENCES, formatDate, formatDuration } from "@/lib/format";
import { publicUrl } from "@/lib/supabase/browser";

export type Item = {
  id: string;
  kind: string;
  is_premium: boolean;
  processing_status: string;
  duration_s: number | null;
  position: number;
  thumb_key: string | null;
  has_trailer: boolean;
  // Premium video with no uploaded preview: viewers see its first 2 minutes.
  auto_preview?: boolean;
  trailer_status: string | null;
};

export type Post = {
  id: string;
  channel_id: string;
  title: string;
  audience: string;
  status: string;
  published_at: string | null;
  view_count: number;
  channels: { name: string } | null;
};

// One sentence that tells the admin whether app users can see this post now.
export function liveState(post: Post, items: Item[]) {
  if (post.status === "draft") {
    return { tone: "amber", icon: "📝", title: "Draft: not in the app", text: "Change Status to Published and save to put it in the app." };
  }
  if (post.status === "hidden") {
    return { tone: "gray", icon: "🙈", title: "Hidden: not in the app", text: "Change Status to Published and save to show it again." };
  }
  if (items.length === 0) {
    return { tone: "amber", icon: "⚠️", title: "No media yet: not in the app", text: "Add a video or image below." };
  }
  if (items.some((i) => i.processing_status === "failed")) {
    return {
      tone: "red",
      icon: "❌",
      title: "A video failed to process: not in the app",
      text: "Remove the failed video and upload it again (MP4 works best).",
    };
  }
  if (items.some((i) => i.processing_status === "pending")) {
    return {
      tone: "blue",
      icon: "⏳",
      title: "Uploaded successfully. Bunny is processing the video",
      text: "It appears in the app by itself as soon as processing finishes. Long videos take longer (a 50-minute video can take 10 to 30 minutes). You can close this page.",
    };
  }
  if (post.published_at && new Date(post.published_at).getTime() > Date.now()) {
    return { tone: "blue", icon: "🕒", title: `Scheduled for ${formatDate(post.published_at)}`, text: "It appears in the app at that time." };
  }
  return { tone: "green", icon: "✅", title: "Live in the app", text: null };
}

export const bannerTones: Record<string, string> = {
  green: "bg-green-50 text-green-900 ring-green-200",
  blue: "bg-blue-50 text-blue-900 ring-blue-200",
  amber: "bg-amber-50 text-amber-900 ring-amber-200",
  red: "bg-red-50 text-red-900 ring-red-200",
  gray: "bg-gray-50 text-gray-900 ring-gray-200",
};


export function LiveBanner({ post, items }: { post: Post; items: Item[] }) {
  const state = liveState(post, items);
  const audienceLabel = AUDIENCES.find((a) => a.value === post.audience)?.label ?? post.audience;
  const premiumCount = items.filter((i) => i.is_premium).length;
  return (
      <div className={`mb-6 rounded-xl px-5 py-4 ring-1 ${bannerTones[state.tone]}`} role="status">
        <p className="font-semibold">
          {state.icon} {state.title}
        </p>
        {state.text && <p className="mt-1 text-sm opacity-90">{state.text}</p>}
        <p className="mt-2 text-sm opacity-80">
          Who sees it: <strong>{audienceLabel}</strong>
          {post.audience === "ads" && " (people who installed from your Meta ads)"}
          {post.audience === "organic" && " (people who did not come from ads)"}
          {premiumCount > 0 && (
            <>
              {" "}· 👑 the full video needs a plan
              {post.audience !== "organic" && items.some((i) => i.has_trailer) ? "; ads users can watch the preview first" : ""}
            </>
          )}
        </p>
      </div>

  );
}

// One video or image of a post, with its actions. The two forms are server
// actions passed in already bound to this item.
export function MediaItemCard({
  item,
  index,
  postId,
  channelId,
  togglePremium,
  remove,
}: {
  item: Item;
  index: number;
  postId: string;
  channelId: string;
  togglePremium: () => Promise<void>;
  remove: () => Promise<void>;
}) {
  const i = index;
  const id = postId;
  const duration = formatDuration(item.duration_s);
  return (
                <li className="overflow-hidden rounded-xl border border-gray-200 bg-white">
                  <div className="relative aspect-video bg-gray-100">
                    {item.thumb_key ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={publicUrl(item.thumb_key)!}
                        alt=""
                        loading="lazy"
                        decoding="async"
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-xs text-gray-400">
                        {item.processing_status === "pending" ? "Thumbnail appears after processing" : "No thumbnail"}
                      </div>
                    )}
                    <div className="absolute left-2 top-2 flex gap-1">
                      {item.is_premium ? <Badge tone="amber">👑 Premium</Badge> : <Badge tone="green">Free</Badge>}
                    </div>
                    {duration && (
                      <span className="absolute bottom-2 right-2 rounded bg-black/75 px-1.5 py-0.5 text-xs font-medium tabular-nums text-white">
                        {duration}
                      </span>
                    )}
                  </div>

                  <div className="space-y-3 p-3">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-sm font-medium">
                        {i + 1}. {item.kind === "video" ? "Video" : "Image"}
                      </p>
                      {item.processing_status === "ready" && <Badge tone="green">✓ Ready</Badge>}
                      {item.processing_status === "failed" && <Badge tone="red">Processing failed</Badge>}
                    </div>

                    {item.processing_status === "pending" && <CheckEncoding itemId={item.id} />}

                    {item.kind === "video" && (
                      <p className="text-xs text-gray-600">
                        Preview:{" "}
                        {item.has_trailer && !item.auto_preview ? (
                          <span className="font-medium text-green-700">✓ uploaded preview</span>
                        ) : item.trailer_status === "pending" ? (
                          <span className="font-medium text-blue-700">
                            processing on Bunny…{item.auto_preview ? " (first 2 min shown meanwhile)" : ""}
                          </span>
                        ) : item.auto_preview ? (
                          <span className="font-medium text-amber-700">
                            automatic: first 2 min{item.trailer_status === "failed" ? " (uploaded preview failed)" : ""}
                          </span>
                        ) : item.trailer_status === "failed" ? (
                          <span className="font-medium text-red-700">failed, upload it again</span>
                        ) : item.is_premium ? (
                          <span className="text-gray-400">none yet (shown once the video is ready)</span>
                        ) : (
                          <span className="text-gray-400">not needed for free videos</span>
                        )}
                      </p>
                    )}

                    <div className="flex flex-wrap gap-1.5 border-t border-gray-100 pt-3">
                      {item.kind === "video" && (
                        <ThumbnailUpload postId={id} itemId={item.id} currentKey={item.thumb_key} />
                      )}
                      {item.kind === "video" && (
                        <TrailerUpload
                          channelId={channelId}
                          itemId={item.id}
                          hasTrailer={(item.has_trailer && !item.auto_preview) || item.trailer_status !== null}
                        />
                      )}
                      <form action={togglePremium}>
                        <button className={smallAction}>{item.is_premium ? "Make free" : "👑 Make premium"}</button>
                      </form>
                      <form action={remove}>
                        <button className={`${smallAction} text-red-700 hover:bg-red-50`}>Remove</button>
                      </form>
                    </div>
                  </div>
                </li>
  );
}
