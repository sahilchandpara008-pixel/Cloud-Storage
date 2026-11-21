"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireOwner } from "@/lib/auth";
import { withMessage } from "@/lib/format";

// All changes go through database functions that check the owner role,
// the amount and that each UTR is used only once.

export async function markPaid(orderId: string, back: string, formData: FormData) {
  const { supabase } = await requireOwner();
  const utr = String(formData.get("utr") ?? "").trim();
  const amount = Number(String(formData.get("amount") ?? "").trim());
  if (!utr) redirect(withMessage(back, "error", "Enter the UTR from your bank statement."));
  if (!Number.isFinite(amount) || amount <= 0) redirect(withMessage(back, "error", "Enter the amount you received."));
  const { error } = await supabase.rpc("admin_mark_payment_paid", {
    p_order_id: orderId,
    p_utr: utr,
    p_amount_rupees: amount,
  });
  if (error) redirect(withMessage(back, "error", error.message));
  revalidatePath("/", "layout");
  redirect(withMessage(back, "ok", "Marked as paid. The plan is active."));
}

export async function revokePayment(orderId: string, back: string, formData: FormData) {
  const { supabase } = await requireOwner();
  const reason = String(formData.get("reason") ?? "").trim();
  const { error } = await supabase.rpc("admin_revoke_payment", { p_order_id: orderId, p_reason: reason || null });
  if (error) redirect(withMessage(back, "error", error.message));
  revalidatePath("/", "layout");
  redirect(withMessage(back, "ok", "Payment revoked. The plan it granted has ended."));
}

export async function saveSettings(back: string, formData: FormData) {
  const { supabase } = await requireOwner();
  const upiId = String(formData.get("upi_id") ?? "").trim();
  const payee = String(formData.get("payee_name") ?? "").trim();
  if (!/^[\w.\-]{2,256}@[a-zA-Z]{2,64}$/.test(upiId)) redirect(withMessage(back, "error", "Enter a valid UPI ID (name@bank)."));
  if (!payee) redirect(withMessage(back, "error", "Enter the payee name."));
  const { error, count } = await supabase
    .from("payment_settings")
    .update(
      { upi_id: upiId, payee_name: payee, enabled: formData.get("enabled") === "on", updated_at: new Date().toISOString() },
      { count: "exact" },
    )
    .eq("id", 1);
  if (error) redirect(withMessage(back, "error", error.message));
  if (count === 0) redirect(withMessage(back, "error", "You don't have permission to change this."));
  revalidatePath("/plans");
  redirect(withMessage(back, "ok", "UPI settings saved."));
}

export async function savePlay(back: string, formData: FormData) {
  const { supabase } = await requireOwner();
  const pkg = String(formData.get("package_name") ?? "").trim();
  if (!/^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$/.test(pkg)) {
    redirect(withMessage(back, "error", "Enter the app's package name, e.g. com.flixvault.app"));
  }
  const { error } = await supabase
    .from("play_settings")
    .update({ package_name: pkg, enabled: formData.get("enabled") === "on" })
    .eq("id", 1);
  if (error) redirect(withMessage(back, "error", error.message));
  redirect(withMessage(back, "ok", "Google Play reporting settings saved."));
}
