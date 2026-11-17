import { PostForm } from "@/components/post-form";
import { UploadTabs } from "@/components/upload-tabs";
import { Card, Flash, PageHeader } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { loadChannelOptions } from "@/lib/channels";
import { createPost } from "../actions";

export default async function NewPostPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; channel?: string; mode?: string }>;
}) {
  const { error, channel, mode } = await searchParams;
  const { supabase } = await requireAdmin();
  const channels = await loadChannelOptions(supabase);

  return (
    <>
      <PageHeader
        title="Upload content"
        subtitle="Post into any channel, yours or one a user created. Single post: choose the main file, a preview and a thumbnail. Bulk upload: many files at once, one post each. Videos and previews are stored on Bunny."
      />
      <Flash error={error} />
      <Card>
        {channels.length === 0 ? (
          <p className="text-sm text-gray-600">Create a channel first.</p>
        ) : (
          <UploadTabs
            channels={channels}
            initialChannelId={channel}
            initialMode={mode === "bulk" ? "bulk" : "single"}
          />
        )}
      </Card>

      <details className="mt-6 rounded-xl border border-gray-200 bg-white">
        <summary className="cursor-pointer px-5 py-3 text-sm font-medium text-gray-700">
          Or create a post without media (write the details now, add videos and images later)
        </summary>
        <div className="border-t border-gray-200 p-5">
          <PostForm
            action={createPost}
            channels={channels}
            values={channel ? { channel_id: channel } : undefined}
            submitLabel="Create post"
          />
        </div>
      </details>
    </>
  );
}
