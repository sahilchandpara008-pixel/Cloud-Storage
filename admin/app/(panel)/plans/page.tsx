import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { Button, Card, Field, Flash, Input, PageHeader, Textarea } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { withMessage } from "@/lib/format";

type Plan = {
  id: string;
  code: string;
  name: string;
  duration_days: number;
  price_inr: number;
  perks: string[];
  active: boolean;
  position: number;
};

async function savePlan(id: string, formData: FormData) {
  "use server";
  const { supabase } = await requireOwner();
  const perks = String(formData.get("perks") ?? "")
    .split("\n")
    .map((p) => p.trim())
    .filter(Boolean);
  const { error } = await supabase
    .from("plans")
    .update({
      name: String(formData.get("name") ?? "").trim(),
      price_inr: Number(formData.get("price_inr")),
      duration_days: Number(formData.get("duration_days")),
      position: Number(formData.get("position")),
      active: formData.get("active") === "on",
      perks,
    })
    .eq("id", id);
  if (error) redirect(withMessage("/plans", "error", error.message));
  revalidatePath("/plans");
  redirect(withMessage("/plans", "ok", "Plan saved."));
}

async function saveFreeMode(formData: FormData) {
  "use server";
  const { supabase } = await requireOwner();
  const free = formData.get("free_mode") === "on";
  const { error } = await supabase
    .from("app_mode")
    .update({ free_mode: free, updated_at: new Date().toISOString() })
    .eq("id", 1);
  if (error) redirect(withMessage("/plans", "error", error.message));
  revalidatePath("/plans");
  redirect(
    withMessage(
      "/plans",
      "ok",
      free ? "Free mode is on: plans are hidden in the app." : "Paid mode is on: plans and UPI payments are shown in the app.",
    ),
  );
}

export default async function PlansPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { ok, error } = await searchParams;
  const { supabase } = await requireOwner();
  const [{ data }, { data: mode }] = await Promise.all([
    supabase.from("plans").select("*").order("position"),
    supabase.from("app_mode").select("free_mode").eq("id", 1).maybeSingle(),
  ]);
  const plans = (data ?? []) as Plan[];
  const freeMode = (mode as { free_mode?: boolean } | null)?.free_mode ?? false;

  return (
    <>
      <PageHeader
        title="Plans"
        subtitle="Prices and perks shown on the app's Premium page. Users pay by UPI; the app updates live."
      />
      <Flash ok={ok} error={error} />
      <Card className="mb-6">
        <form action={saveFreeMode} className="grid gap-3">
          <div className="flex items-center justify-between gap-3">
            <h2 className="font-semibold">Free mode</h2>
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                freeMode ? "bg-amber-100 text-amber-800" : "bg-green-100 text-green-800"
              }`}
            >
              {freeMode ? "On: plans hidden" : "Off: plans on sale"}
            </span>
          </div>
          <p className="text-sm text-gray-600">
            On: the app is free, no plans or payments are shown, and no Purchase events reach Meta.
            Off: plans and UPI payments are shown in every version of the app (website APK, ads APK and Google Play),
            and each approved payment is sent to Meta as a Purchase for ROAS.
          </p>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="free_mode" defaultChecked={freeMode} className="h-4 w-4 accent-red-700" />
            Free mode on
          </label>
          <div>
            <Button type="submit">Save</Button>
          </div>
        </form>
      </Card>
      <div className="grid gap-4 lg:grid-cols-2">
        {plans.map((p) => (
          <Card key={p.id}>
            <form action={savePlan.bind(null, p.id)} className="grid gap-3 sm:grid-cols-2">
              <Field label="Name">
                <Input name="name" defaultValue={p.name} required />
              </Field>
              <Field label="Code" hint="Used internally">
                <Input value={p.code} disabled readOnly />
              </Field>
              <Field label="Price (₹)">
                <Input name="price_inr" type="number" min={0} defaultValue={p.price_inr} required />
              </Field>
              <Field label="Duration (days)">
                <Input name="duration_days" type="number" min={1} defaultValue={p.duration_days} required />
              </Field>
              <div className="sm:col-span-2">
                <Field label="Perks" hint="One per line">
                  <Textarea name="perks" rows={3} defaultValue={p.perks.join("\n")} />
                </Field>
              </div>
              <Field label="Order">
                <Input name="position" type="number" defaultValue={p.position} />
              </Field>
              <label className="flex items-center gap-2 self-end pb-2 text-sm">
                <input type="checkbox" name="active" defaultChecked={p.active} className="h-4 w-4 accent-red-700" />
                Show in app
              </label>
              <div className="sm:col-span-2">
                <Button type="submit">Save</Button>
              </div>
            </form>
          </Card>
        ))}
      </div>
    </>
  );
}
