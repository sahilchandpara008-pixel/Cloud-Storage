"use server";

import { createHash } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireOwner } from "@/lib/auth";
import { withMessage } from "@/lib/format";

// Send one real test event with this Pixel ID and token, exactly the way the
// app's events are sent. "ok" = Meta received it; a string = Meta's error to
// show the owner; null = Meta could not be reached from here.
async function checkWithMeta(
  pixel: string,
  token: string,
  pageUrl: string,
  testCode: string | null,
): Promise<"ok" | string | null> {
  try {
    const res = await fetch(
      `https://graph.facebook.com/v21.0/${pixel}/events?access_token=${encodeURIComponent(token)}`,
      {
        method: "POST",
        cache: "no-store",
        signal: AbortSignal.timeout(10000),
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          data: [
            {
              event_name: "ViewContent",
              event_time: Math.floor(Date.now() / 1000),
              event_id: `connect-${crypto.randomUUID()}`,
              action_source: "website",
              event_source_url: pageUrl,
              user_data: {
                external_id: [createHash("sha256").update("flixvault-admin-connect").digest("hex")],
                client_user_agent: "FlixvaultAdmin/1.0",
              },
              custom_data: { content_type: "test", content_ids: ["connect"] },
            },
          ],
          // With a test code the check shows under Test events only and is
          // not counted with real events.
          ...(testCode ? { test_event_code: testCode } : {}),
        }),
      },
    );
    const body = (await res.json().catch(() => null)) as
      | { events_received?: number; error?: { message?: string } }
      | null;
    if (res.ok && (body?.events_received ?? 0) > 0) return "ok";
    return body?.error?.message ?? `Meta answered with error ${res.status}.`;
  } catch {
    return null;
  }
}

// The one step the owner needs: Pixel ID + access token. Saving turns tracking
// on for the download page and every app version, and sends a test event.
export async function connectMeta(formData: FormData) {
  const { supabase } = await requireOwner();
  const pixel = String(formData.get("pixel_id") ?? "").trim();
  const typed = String(formData.get("access_token") ?? "").trim();
  const origin = String(formData.get("origin") ?? "").trim();

  if (!/^[0-9]{5,20}$/.test(pixel)) {
    redirect(withMessage("/meta", "error", "Enter the Pixel ID. It is a number; find it in Meta Events Manager."));
  }
  const { data: saved } = await supabase
    .from("meta_settings")
    .select("access_token, test_event_code")
    .eq("id", 1)
    .maybeSingle();
  const current = (saved ?? {}) as { access_token?: string | null; test_event_code?: string | null };
  const token = typed || current.access_token || "";
  if (!token) redirect(withMessage("/meta", "error", "Paste the Conversions API access token."));

  const website = /^https?:\/\//.test(origin) ? `${origin}/d` : "https://flixvault-app.vercel.app/d";
  const check = await checkWithMeta(pixel, token, website, current.test_event_code ?? null);
  if (check !== "ok" && check !== null) {
    redirect(withMessage("/meta", "error", `Meta did not accept this Pixel ID and token: ${check}`));
  }

  const update: Record<string, unknown> = {
    pixel_id: pixel,
    access_token: token,
    // Keep action_source as set: the dataset is linked to the Flixvault app
    // (com.flixvault.app), so events go out as app events.
    enabled: true,
    updated_at: new Date().toISOString(),
  };
  if (/^https?:\/\//.test(origin)) update.website_url = website;

  const { error, count } = await supabase.from("meta_settings").update(update, { count: "exact" }).eq("id", 1);
  if (error) redirect(withMessage("/meta", "error", error.message));
  if (count === 0) redirect(withMessage("/meta", "error", "You don't have permission to change this."));
  if (check === null) await supabase.rpc("admin_meta_test_event"); // result shows in Recent events
  revalidatePath("/meta");
  redirect(
    withMessage(
      "/meta",
      "ok",
      check === "ok"
        ? "Connected. Meta received a test event with this Pixel and token. Tracking is on for the download page and the app."
        : "Saved and tracking is on. Meta could not be reached to confirm; check Recent events below in a minute.",
    ),
  );
}

export async function turnTrackingOff() {
  const { supabase } = await requireOwner();
  const { error } = await supabase
    .from("meta_settings")
    .update({ enabled: false, updated_at: new Date().toISOString() })
    .eq("id", 1);
  if (error) redirect(withMessage("/meta", "error", error.message));
  revalidatePath("/meta");
  redirect(withMessage("/meta", "ok", "Tracking is off. No events are sent to Meta."));
}

// Optional extras: download page file and text, test event code.
export async function saveMetaExtras(formData: FormData) {
  const { supabase } = await requireOwner();
  const testCode = String(formData.get("test_event_code") ?? "").trim();
  const apkUrl = String(formData.get("apk_url") ?? "").trim();
  const title = String(formData.get("page_title") ?? "").trim().slice(0, 60);
  const subtitle = String(formData.get("page_subtitle") ?? "").trim().slice(0, 160);
  if (apkUrl && !/^https?:\/\//.test(apkUrl)) {
    redirect(withMessage("/meta", "error", "The APK link must start with https://"));
  }
  const { error } = await supabase
    .from("meta_settings")
    .update({
      test_event_code: testCode || null,
      apk_url: apkUrl || null,
      page_title: title || "Flixvault",
      page_subtitle: subtitle || "Premium videos, trailers and 2 TB cloud storage — all in one app.",
      updated_at: new Date().toISOString(),
    })
    .eq("id", 1);
  if (error) redirect(withMessage("/meta", "error", error.message));
  revalidatePath("/meta");
  redirect(withMessage("/meta", "ok", "Saved."));
}

export async function sendTestEvent() {
  const { supabase } = await requireOwner();
  const { error } = await supabase.rpc("admin_meta_test_event");
  if (error) redirect(withMessage("/meta", "error", error.message));
  redirect(
    withMessage(
      "/meta",
      "ok",
      "Test event sent. Refresh this page in a minute to see Meta's answer, and check Events Manager → Test events.",
    ),
  );
}
