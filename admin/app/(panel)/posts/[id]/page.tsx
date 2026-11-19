import Link from "next/link";
import { redirect } from "next/navigation";
import { DeleteButton } from "@/components/delete-button";
import { MediaUploader } from "@/components/media-uploader";
import { PostForm, type PostValues } from "@/components/post-form";
import { Card, Flash, PageHeader } from "@/components/ui";
import { LiveBanner, MediaItemCard, type Item, type Post } from "@/components/post-media";
import { requireAdmin } from "@/lib/auth";
import { withMessage } from "@/lib/format";
import { loadChannelOptions } from "@/lib/channels";
import { deleteItem, deletePost, setItemPremium, updatePost } from "../actions";

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

  const { data: postRow } = await supabase
    .from("posts")
    .select("id, channel_id, folder_id, title, caption, audience, status, published_at, view_count, channels(name)")
    .eq("id", id)
    .maybeSingle();
  if (!postRow) redirect(withMessage("/posts", "error", "That post no longer exists. It may have been deleted."));
  const post = postRow as unknown as Post;

  const [channels, { data: itemRows }] = await Promise.all([
    loadChannelOptions(supabase),
    supabase
      .from("post_items")
      .select("id, kind, is_premium, processing_status, duration_s, position, thumb_key, has_trailer, auto_preview, trailer_status")
      .eq("post_id", id)
      .order("position"),
  ]);
  const items = (itemRows ?? []) as Item[];

  return (
    <>
      <Link href={`/posts?channel=${post.channel_id}`} className="mb-2 inline-block text-sm text-gray-500 hover:text-brand-700">
        ← {post.channels?.name ?? "Posts"}
      </Link>
      <PageHeader title={post.title} subtitle={`${post.view_count} views`} />
      <Flash ok={ok} error={error} />

      <LiveBanner post={post} items={items} />

      <Card className="mb-6">
        <div className="mb-4 flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="font-semibold">Videos &amp; images</h2>
          <p className="text-sm text-gray-500">Videos and previews are stored on Bunny and stream from there.</p>
        </div>

        {items.length === 0 ? (
          <p className="mb-4 text-sm text-gray-500">No media yet.</p>
        ) : (
          <ul className="mb-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {items.map((item, i) => (
              <MediaItemCard
                key={item.id}
                item={item}
                index={i}
                postId={id}
                channelId={post.channel_id}
                togglePremium={setItemPremium.bind(null, id, item.id, !item.is_premium)}
                remove={deleteItem.bind(null, id, item.id)}
              />
            ))}
          </ul>
        )}
        <MediaUploader postId={id} channelId={post.channel_id} nextPosition={items.length} />
      </Card>

      <Card>
        <h2 className="mb-4 font-semibold">Post details</h2>
        <PostForm
          action={updatePost.bind(null, id)}
          channels={channels}
          values={postRow as PostValues}
          submitLabel="Save post"
        />
      </Card>

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
