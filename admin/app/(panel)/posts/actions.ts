"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { withMessage } from "@/lib/format";
import { removeItemStorage } from "@/lib/media-cleanup";

const NO_PERMISSION = "You don't have permission to change this.";

function postFields(formData: FormData) {
  const status = String(formData.get("status") ?? "draft");
  const publishedAt = String(formData.get("published_at") ?? "");
  return {
    channel_id: String(formData.get("channel_id") ?? ""),
    folder_id: String(formData.get("folder_id") ?? "") || null,
    title: String(formData.get("title") ?? "").trim(),
    caption: String(formData.get("caption") ?? "").trim() || null,
    audience: String(formData.get("audience") ?? "all"),
    status,
    // Publishing without a time means "now".
    published_at: publishedAt || (status === "published" ? new Date().toISOString() : null),
  };
}

function friendly(message: string) {
  if (message.includes("must match its channel audience")) {
    return "This channel is limited to one audience. The post must use the same audience.";
  }
  if (message.includes("row-level security")) return NO_PERMISSION;
  return message;
}

export async function createPost(formData: FormData) {
  const { supabase, user } = await requireAdmin();
  const fields = postFields(formData);
  const { data, error } = await supabase
    .from("posts")
    .insert({ ...fields, created_by: user.id })
    .select("id")
    .single();
  if (error) redirect(withMessage(`/posts/new?channel=${fields.channel_id}`, "error", friendly(error.message)));
  revalidatePath("/posts");
  redirect(withMessage(`/posts/${data.id}`, "ok", "Post created."));
}

export async function updatePost(id: string, formData: FormData) {
  const { supabase } = await requireAdmin();
  const { error, count } = await supabase
    .from("posts")
    .update({ ...postFields(formData), updated_at: new Date().toISOString() }, { count: "exact" })
    .eq("id", id);
  if (error) redirect(withMessage(`/posts/${id}`, "error", friendly(error.message)));
  if (count === 0) redirect(withMessage(`/posts/${id}`, "error", NO_PERMISSION));
  revalidatePath("/posts");
  redirect(withMessage(`/posts/${id}`, "ok", "Post saved."));
}

export async function deletePost(id: string) {
  const { supabase } = await requireAdmin();
  const { data: items } = await supabase
    .from("post_items")
    .select("media_key, thumb_key, trailer_key")
    .eq("post_id", id);
  if (items?.length) await removeItemStorage(supabase, items);
  await supabase.functions.invoke("bunny-stream-delete", { body: { post_id: id } });
  const { error, count } = await supabase.from("posts").delete({ count: "exact" }).eq("id", id);
  if (error) redirect(withMessage(`/posts/${id}`, "error", friendly(error.message)));
  if (count === 0) redirect(withMessage(`/posts/${id}`, "error", NO_PERMISSION));
  revalidatePath("/posts");
  redirect(withMessage("/posts", "ok", "Post and its media deleted."));
}

export async function setItemPremium(postId: string, itemId: string, premium: boolean) {
  const { supabase } = await requireAdmin();
  const { error, count } = await supabase
    .from("post_items")
    .update({ is_premium: premium }, { count: "exact" })
    .eq("id", itemId);
  if (error) redirect(withMessage(`/posts/${postId}`, "error", friendly(error.message)));
  if (count === 0) redirect(withMessage(`/posts/${postId}`, "error", NO_PERMISSION));
  revalidatePath(`/posts/${postId}`);
  redirect(withMessage(`/posts/${postId}`, "ok", premium ? "Marked as premium." : "Marked as free."));
}

export async function deleteItem(postId: string, itemId: string) {
  const { supabase } = await requireAdmin();
  const { data: item } = await supabase
    .from("post_items")
    .select("media_key, thumb_key, trailer_key")
    .eq("id", itemId)
    .maybeSingle();
  if (item) await removeItemStorage(supabase, [item]);
  await supabase.functions.invoke("bunny-stream-delete", { body: { item_id: itemId } });
  const { error, count } = await supabase.from("post_items").delete({ count: "exact" }).eq("id", itemId);
  if (error) redirect(withMessage(`/posts/${postId}`, "error", friendly(error.message)));
  if (count === 0) redirect(withMessage(`/posts/${postId}`, "error", NO_PERMISSION));
  revalidatePath(`/posts/${postId}`);
  redirect(withMessage(`/posts/${postId}`, "ok", "Media removed."));
}
