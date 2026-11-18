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
      free
        ? "Free mode is on: plans are hidden in the app."
        : "Paid mode is on: plans and UPI payments are shown in the app.",
    ),
  );
}

export default async function PlansPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
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
      <Card className="mb-5 py-4">
        <form action={saveFreeMode} className="flex flex-wrap items-center gap-x-4 gap-y-3">
          <div className="min-w-0 flex-1 basis-72">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="font-semibold text-gray-900">Free mode</h2>
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                  freeMode ? "bg-amber-100 text-amber-800" : "bg-green-100 text-green-800"
                }`}
              >
                {freeMode ? "On: plans hidden" : "Off: plans on sale"}
              </span>
            </div>
            <p className="mt-1 text-xs leading-5 text-gray-500">
              On: the app is free, no plans or payments are shown, and no Purchase events reach Meta. Off: plans and UPI
              payments are shown in every version of the app, and each approved payment is sent to Meta as a Purchase.
            </p>
          </div>
          <label className="flex items-center gap-2 text-sm font-medium text-gray-700">
            <input type="checkbox" name="free_mode" defaultChecked={freeMode} className="h-4 w-4" />
            Free mode on
          </label>
          <Button type="submit">Save</Button>
        </form>
      </Card>

      <Card className="overflow-hidden p-0!">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 px-5 py-3">
          <h2 className="font-semibold text-gray-900">Plans</h2>
          <span className="text-xs text-gray-500">
            {plans.filter((p) => p.active).length} of {plans.length} shown in the app
          </span>
        </div>
        <div
          aria-hidden="true"
          className="hidden grid-cols-[minmax(0,1fr)_7rem_6rem_5rem_7.5rem_6.5rem] gap-3 border-b border-gray-100 bg-gray-50 px-5 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500 lg:grid"
        >
          <span>Name</span>
          <span>Price (₹)</span>
          <span>Days</span>
          <span>Order</span>
          <span>In app</span>
          <span />
        </div>
        <div className="divide-y divide-gray-100">
          {plans.map((p) => (
            <form key={p.id} action={savePlan.bind(null, p.id)} className="px-5 py-4 hover:bg-gray-50/60">
              <div className="grid grid-cols-2 items-end gap-3 sm:grid-cols-4 lg:grid-cols-[minmax(0,1fr)_7rem_6rem_5rem_7.5rem_6.5rem] lg:items-center">
                <label className="col-span-2 block sm:col-span-4 lg:col-span-1">
                  <span className="mb-1 block text-xs font-medium text-gray-600 lg:sr-only">Name</span>
                  <div className="flex items-center gap-2">
                    <Input name="name" defaultValue={p.name} required className="min-w-0 flex-1" />
                    <span className="hidden shrink-0 font-mono text-[11px] text-gray-400 xl:inline">{p.code}</span>
                  </div>
                </label>
                <label className="block">
                  <span className="mb-1 block text-xs font-medium text-gray-600 lg:sr-only">Price (₹)</span>
                  <Input
                    name="price_inr"
                    type="number"
                    min={0}
                    defaultValue={p.price_inr}
                    required
                    className="tabular-nums"
                  />
                </label>
                <label className="block">
                  <span className="mb-1 block text-xs font-medium text-gray-600 lg:sr-only">Days</span>
                  <Input
                    name="duration_days"
                    type="number"
                    min={1}
                    defaultValue={p.duration_days}
                    required
                    className="tabular-nums"
                  />
                </label>
                <label className="block">
                  <span className="mb-1 block text-xs font-medium text-gray-600 lg:sr-only">Order</span>
                  <Input name="position" type="number" defaultValue={p.position} className="tabular-nums" />
                </label>
                <label className="flex min-h-9 items-center gap-2 text-sm text-gray-700">
                  <input type="checkbox" name="active" defaultChecked={p.active} className="h-4 w-4" />
                  <span
                    className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                      p.active ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-600"
                    }`}
                  >
                    {p.active ? "In app" : "Hidden"}
                  </span>
                </label>
                <Button type="submit" className="col-span-2 w-full sm:col-span-4 lg:col-span-1">
                  Save
                </Button>
              </div>
              <details className="group mt-2">
                <summary className="inline-flex list-none items-center gap-2 text-xs text-gray-500 [&::-webkit-details-marker]:hidden">
                  <span className="font-medium text-brand-700 group-open:hidden">Edit perks</span>
                  <span className="hidden font-medium text-brand-700 group-open:inline">Hide perks</span>
                  <span className="truncate group-open:hidden">
                    {p.perks.length ? p.perks.join(" · ") : "No perks yet"}
                  </span>
                </summary>
                <div className="mt-2 max-w-2xl">
                  <Field label="Perks" hint="One per line">
                    <Textarea name="perks" rows={3} defaultValue={p.perks.join("\n")} />
                  </Field>
                </div>
              </details>
            </form>
          ))}
        </div>
      </Card>
    </>
  );
}
