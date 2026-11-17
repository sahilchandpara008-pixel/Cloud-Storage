import { redirect } from "next/navigation";
import { CheckEncoding } from "@/components/check-encoding";
import { DeleteButton } from "@/components/delete-button";
import { MediaUploader } from "@/components/media-uploader";
import { TrailerUpload } from "@/components/trailer-upload";
import { PostForm, type PostValues } from "@/components/post-form";
import { Badge, Card, Flash, PageHeader } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { withMessage } from "@/lib/format";
import { loadChannelOptions } from "@/lib/channels";
import { publicUrl } from "@/lib/supabase/browser";
import { deleteItem, deletePost, setItemPremium, updatePost } from "../actions";

type Item = {
  id: string;
  kind: string;
  is_premium: boolean;
  processing_status: string;
  duration_s: number | null;
  position: number;
  thumb_key: string | null;
  has_trailer: boolean;
  trailer_status: string | null;
};

export default async function PostPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase } = await requireAdmin();

  const { data: post } = await supabase
    .from("posts")
    .select("id, channel_id, folder_id, title, caption, audience, status, published_at, view_count")
    .eq("id", id)
    .maybeSingle();
  if (!post) redirect(withMessage("/posts", "error", "That post no longer exists. It may have been deleted."));

  const [channels, { data: itemRows }] = await Promise.all([
    loadChannelOptions(supabase),
    supabase
      .from("post_items")
      .select("id, kind, is_premium, processing_status, duration_s, position, thumb_key, has_trailer, trailer_status")
      .eq("post_id", id)
      .order("position"),
  ]);
  const items = (itemRows ?? []) as Item[];

  return (
    <>
      <PageHeader title={post.title} subtitle={`${post.view_count} views`} />
      <Flash ok={ok} error={error} />

      <div className="grid gap-6 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <h2 className="mb-4 font-semibold">Post details</h2>
          <PostForm
            action={updatePost.bind(null, id)}
            channels={channels}
            values={post as PostValues}
            submitLabel="Save post"
          />
        </Card>

        <Card>
          <h2 className="mb-1 font-semibold">Videos &amp; images</h2>
          <p className="mb-4 text-sm text-gray-500">
            Mark each item 👑 premium (login + plan needed to play) or free. Ads users can watch a
            video&apos;s preview before buying. Videos and previews are stored on Bunny.
          </p>
          <ul className="mb-4 space-y-2">
            {items.length === 0 && <li className="text-sm text-gray-500">No media yet.</li>}
            {items.map((item, i) => (
              <li key={item.id} className="flex items-center justify-between gap-2 rounded-lg border border-gray-200 p-3 text-sm">
                <div className="flex items-center gap-3">
                  {item.thumb_key ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={publicUrl(item.thumb_key)!}
                      alt=""
                      loading="lazy"
                      decoding="async"
                      className="h-14 w-14 shrink-0 rounded-md object-cover"
                    />
                  ) : (
                    <div className="h-14 w-14 shrink-0 rounded-md bg-gray-100" />
                  )}
                  <div>
                  <p className="font-medium">
                    {i + 1}. {item.kind === "video" ? "Video" : "Image"}
                    {item.duration_s ? ` · ${Math.round(item.duration_s)}s` : ""}
                  </p>
                  <div className="mt-1 flex gap-1">
                    {item.is_premium ? <Badge tone="amber">👑 Premium</Badge> : <Badge>Free</Badge>}
                    {item.has_trailer && <Badge tone="purple">Preview</Badge>}
                    {item.trailer_status === "pending" && <Badge tone="blue">Preview processing…</Badge>}
                    {item.trailer_status === "failed" && <Badge tone="red">Preview failed</Badge>}
                    {item.processing_status !== "ready" && (
                      <Badge tone={item.processing_status === "failed" ? "red" : "blue"}>
                        {item.processing_status === "failed" ? "Processing failed" : "Processing…"}
                      </Badge>
                    )}
                  </div>
                  </div>
                </div>
                <div className="flex flex-col items-end gap-1">
                  <form action={setItemPremium.bind(null, id, item.id, !item.is_premium)}>
                    <button className="text-xs font-medium text-red-700 hover:underline">
                      {item.is_premium ? "Make free" : "Make premium"}
                    </button>
                  </form>
                  {item.kind === "video" && (
                    <TrailerUpload
                      channelId={post.channel_id}
                      itemId={item.id}
                      hasTrailer={item.has_trailer || item.trailer_status !== null}
                    />
                  )}
                  {item.processing_status === "pending" && <CheckEncoding itemId={item.id} />}
                  <form action={deleteItem.bind(null, id, item.id)}>
                    <button className="text-xs text-gray-500 hover:text-red-700 hover:underline">Remove</button>
                  </form>
                </div>
              </li>
            ))}
          </ul>
          <MediaUploader postId={id} channelId={post.channel_id} nextPosition={items.length} />
        </Card>
      </div>

      <Card className="mt-6 border-red-200">
        <h2 className="font-semibold text-red-800">Delete post</h2>
        <p className="mb-3 text-sm text-gray-600">Removes the post and its media from the app.</p>
        <form action={deletePost.bind(null, id)}>
          <DeleteButton
            label="Delete post"
            pendingLabel="Deleting… please wait"
            confirmText={`Delete "${post.title}" and permanently remove its videos and images? This cannot be undone.`}
          />
        </form>
      </Card>
    </>
  );
}
