"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireOwner } from "@/lib/auth";
import { withMessage } from "@/lib/format";
import { createServiceClient } from "@/lib/supabase/server";

export async function addAdmin(formData: FormData) {
  const { supabase, user } = await requireOwner();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const role = String(formData.get("role") ?? "content_admin");
  const channelIds = formData.getAll("channels").map(String);

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) redirect(withMessage("/admins", "error", "Enter a valid email address."));
  if (role !== "owner" && role !== "content_admin") redirect(withMessage("/admins", "error", "Pick a role."));
  if (password.length < 8) redirect(withMessage("/admins", "error", "Password must be at least 8 characters."));

  // Creating a login needs the Auth admin API (service role, server only).
  const service = createServiceClient();
  const { data: created, error: createError } = await service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    redirect(withMessage("/admins", "error", createError?.message ?? "Could not create the account."));
  }

  const { error } = await supabase
    .from("admins")
    .insert({ user_id: created.user.id, role, invited_by: user.id });
  if (error) {
    // Don't leave a login behind that has no admin access: a retry with the
    // same email would then fail with "already registered".
    await service.auth.admin.deleteUser(created.user.id);
    redirect(withMessage("/admins", "error", error.message));
  }

  if (role === "content_admin" && channelIds.length > 0) {
    await supabase
      .from("admin_channel_access")
      .insert(channelIds.map((channel_id) => ({ admin_id: created.user.id, channel_id })));
  }
  revalidatePath("/admins");
  redirect(withMessage("/admins", "ok", `${email} can now sign in to the panel.`));
}

export async function removeAdmin(userId: string) {
  const { supabase, user } = await requireOwner();
  if (userId === user.id) redirect(withMessage("/admins", "error", "You can't remove yourself."));
  const { error } = await supabase.from("admins").delete().eq("user_id", userId);
  if (error) redirect(withMessage("/admins", "error", error.message));
  revalidatePath("/admins");
  redirect(withMessage("/admins", "ok", "Admin access removed."));
}
