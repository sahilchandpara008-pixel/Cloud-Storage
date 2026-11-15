import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";

// The admin panel's opening link. Signed-in admins land on the dashboard at
// "/"; requireAdmin sends anyone else to /login first. No other page moved.
export default async function AdminEntry() {
  await requireAdmin();
  redirect("/");
}
