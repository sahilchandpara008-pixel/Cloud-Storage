import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AdminRole = "owner" | "content_admin";

// Every panel page and action starts here: signed in AND listed in admins.
// The panel layout and every page both call this on each request; cache()
// makes React reuse the one result instead of re-checking auth + admins
// twice per navigation.
export const requireAdmin = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: admin } = await supabase
    .from("admins")
    .select("role")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!admin) redirect("/login?error=not_admin");

  return { supabase, user, role: admin.role as AdminRole };
});

export async function requireOwner() {
  const ctx = await requireAdmin();
  if (ctx.role !== "owner") redirect("/?error=owner_only");
  return ctx;
}
