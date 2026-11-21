"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireOwner } from "@/lib/auth";
import { withMessage } from "@/lib/format";

const AUDIENCES = ["all", "members", "channels", "premium", "not_premium", "ads", "organic", "guests", "logged_in"];
const ACTIONS = ["home", "post", "channel", "premium", "url"];

// Send (or schedule) a push message; "test" goes only to the owner's phones.
export async function sendPush(formData: FormData) {
  const { supabase } = await requireOwner();
  const get = (k: string) => String(formData.get(k) ?? "").trim();
  const test = get("mode") === "test";
  const title = get("title");
  const action = ACTIONS.includes(get("action_type")) ? get("action_type") : "home";
  const audience = test ? "test" : AUDIENCES.includes(get("audience")) ? get("audience") : "all";
  const channels = formData.getAll("channel_ids").map(String).filter((v) => /^[0-9a-f-]{36}$/i.test(v));
  const when = get("when") === "later" && get("scheduled_at") ? get("scheduled_at") : "";
  if (!title) redirect(withMessage("/notifications", "error", "Enter a title."));

  let scheduledAt: string | null = null;
  if (!test && when) {
    // datetime-local is India time (the admin works in IST).
    const d = new Date(`${when}:00+05:30`);
    if (Number.isNaN(d.getTime())) redirect(withMessage("/notifications", "error", "Pick a valid date and time."));
    scheduledAt = d.toISOString();
  }

  const { error } = await supabase.rpc("admin_push_create", {
    p_title: title,
    p_body: get("body"),
    p_image_url: get("image_url") || null,
    p_action_type: action,
    p_action_id: action === "post" ? get("post_id") : action === "channel" ? get("channel_id") : null,
    p_action_url: action === "url" ? get("url") : null,
    p_audience: audience,
    p_channel_ids: audience === "channels" ? channels : [],
    p_scheduled_at: scheduledAt,
  });
  if (error) redirect(withMessage("/notifications", "error", error.message));
  if (!scheduledAt) await supabase.rpc("admin_push_kick");
  revalidatePath("/notifications");
  redirect(
    withMessage(
      test ? "/notifications" : "/notifications?tab=history",
      "ok",
      test
        ? "Test sent to your phone. It should arrive within a minute."
        : scheduledAt
          ? "Message scheduled."
          : "Message is being sent.",
    ),
  );
}

export async function cancelPush(id: string) {
  const { supabase } = await requireOwner();
  const { error } = await supabase.rpc("admin_push_cancel", { p_id: id });
  if (error) redirect(withMessage("/notifications?tab=history", "error", error.message));
  revalidatePath("/notifications");
  redirect(withMessage("/notifications?tab=history", "ok", "Scheduled message cancelled."));
}

const AUTO_KINDS = ["payment_reminder", "payment_approved", "plan_ending", "come_back", "new_videos"];

// Automatic messages: on/off, title and text (and for new videos: who, how often).
export async function saveAuto(kind: string, formData: FormData) {
  const { supabase } = await requireOwner();
  if (!AUTO_KINDS.includes(kind)) redirect(withMessage("/notifications?tab=auto", "error", "Unknown message type."));
  const get = (k: string) => String(formData.get(k) ?? "").trim();
  const mode = get("nv_mode");
  const hours = Number(get("interval_hours"));
  const { error } = await supabase.rpc("admin_push_auto_save", {
    p_kind: kind,
    p_enabled: formData.get("enabled") === "on",
    p_title: get("title"),
    p_body: get("body"),
    p_nv_mode: mode === "members" || mode === "all" ? mode : null,
    p_interval_hours: Number.isInteger(hours) && hours >= 1 && hours <= 48 ? hours : null,
  });
  if (error) redirect(withMessage("/notifications?tab=auto", "error", error.message));
  revalidatePath("/notifications");
  redirect(withMessage("/notifications?tab=auto", "ok", "Saved."));
}

export async function saveChannelMode(channelId: string, formData: FormData) {
  const { supabase } = await requireOwner();
  const mode = String(formData.get("mode") ?? "default");
  const { error } = await supabase.rpc("admin_push_channel_mode", { p_channel_id: channelId, p_mode: mode });
  if (error) redirect(withMessage("/notifications?tab=auto", "error", error.message));
  revalidatePath("/notifications");
  redirect(withMessage("/notifications?tab=auto", "ok", "Channel setting saved."));
}
