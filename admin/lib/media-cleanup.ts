import type { SupabaseClient } from "@supabase/supabase-js";

type ItemKeys = { media_key: string | null; thumb_key: string | null; trailer_key: string | null };

// Removes the Supabase Storage objects (main file, trailer, thumbnail) for a
// list of post_items, in batches of 100 per bucket. Call this BEFORE
// deleting the post_items/posts/channels rows -- their keys are gone once
// the row is (cascade-deleted.
export async function removeItemStorage(supabase: SupabaseClient, items: ItemKeys[]) {
  const media = items.flatMap((i) => [i.media_key, i.trailer_key].filter((k): k is string => !!k));
  const thumbs = items.flatMap((i) => (i.thumb_key ? [i.thumb_key] : []));
  for (let i = 0; i < media.length; i += 100) {
    await supabase.storage.from("media").remove(media.slice(i, i + 100));
  }
  for (let i = 0; i < thumbs.length; i += 100) {
    await supabase.storage.from("public").remove(thumbs.slice(i, i + 100));
  }
}
