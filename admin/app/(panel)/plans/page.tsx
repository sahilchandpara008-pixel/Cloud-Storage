import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { Button, Card, Field, Flash, Input, PageHeader, Select, Textarea } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { withMessage } from "@/lib/format";
import { saveSettings } from "../payments/actions";

type Plan = {
  id: string;
  code: string;
  name: string;
  duration_days: number;
  price_inr: number;
  perks: string[];
  active: boolean;
  position: number;
  recommended: boolean;
};

async function savePlan(id: string, formData: FormData) {
  "use server";
  const { supabase } = await requireOwner();
  const perks = String(formData.get("perks") ?? "")
    .split("\n")
    .map((p) => p.trim())
    .filter(Boolean);
  const name = String(formData.get("name") ?? "").trim();
  const price = Number(String(formData.get("price_inr") ?? "").trim());
  const days = Number(String(formData.get("duration_days") ?? "").trim());
  const position = Number(String(formData.get("position") ?? "0").trim() || "0");
  // A blank, zero or decimal price would break UPI payments in the app.
  if (!name) redirect(withMessage("/plans", "error", "Enter the plan name."));
  if (!Number.isInteger(price) || price < 1 || price > 100000) {
    redirect(withMessage("/plans", "error", "Price must be a whole number of rupees, at least ₹1."));
  }
  if (!Number.isInteger(days) || days < 1 || days > 3650) {
    redirect(withMessage("/plans", "error", "Duration must be a whole number of days (1 to 3650)."));
  }
  if (!Number.isInteger(position)) redirect(withMessage("/plans", "error", "Order must be a whole number."));
  const { error, count } = await supabase
    .from("plans")
    .update(
      {
      name,
      price_inr: price,
      duration_days: days,
      position,
      active: formData.get("active") === "on",
      perks,
      },
      { count: "exact" },
    )
    .eq("id", id);
  if (error) redirect(withMessage("/plans", "error", error.message));
  if (count === 0) redirect(withMessage("/plans", "error", "Plan not found, or you don't have permission."));
  revalidatePath("/plans");
  redirect(withMessage("/plans", "ok", "Plan saved."));
}

async function saveRecommended(formData: FormData) {
  "use server";
  const { supabase } = await requireOwner();
  const id = String(formData.get("plan_id") ?? "").trim();
  const { error } = await supabase.rpc("admin_set_recommended_plan", { p_plan_id: id || null });
  if (error) redirect(withMessage("/plans", "error", error.message));
  revalidatePath("/plans");
  redirect(
    withMessage(
      "/plans",
      "ok",
      id ? "Recommended plan saved. The app now opens with it selected." : "No recommended plan: the first plan is selected.",
    ),
  );
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
  const [{ data }, { data: mode }, { data: upi }] = await Promise.all([
    supabase.from("plans").select("*").order("position"),
    supabase.from("app_mode").select("free_mode").eq("id", 1).maybeSingle(),
    supabase.from("payment_settings").select("upi_id, payee_name, enabled").eq("id", 1).maybeSingle(),
  ]);
  const plans = (data ?? []) as Plan[];
  const freeMode = (mode as { free_mode?: boolean } | null)?.free_mode ?? false;
  const recommended = plans.find((p) => p.recommended);
  // Same rule as the app: lowest price per day among plans shown (3 or more).
  const shown = plans.filter((p) => p.active && p.duration_days > 0);
  const bestId =
    shown.length > 2
      ? [...shown].sort((a, b) => a.price_inr / a.duration_days - b.price_inr / b.duration_days)[0].id
      : undefined;

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

      <Card className="mb-5">
        <h2 className="mb-1 font-semibold text-gray-900">UPI settings</h2>
        <p className="mb-3 text-xs text-gray-500">Where plan payments in the app are paid to.</p>
        <form action={saveSettings.bind(null, "/plans")} className="grid gap-3 sm:grid-cols-2">
          <label className="text-sm">
            UPI ID
            <Input name="upi_id" defaultValue={upi?.upi_id ?? ""} required />
          </label>
          <label className="text-sm">
            Payee name (shown in the UPI app)
            <Input name="payee_name" defaultValue={upi?.payee_name ?? ""} required />
          </label>
          <label className="flex items-center gap-2 text-sm sm:col-span-2">
            <input type="checkbox" name="enabled" defaultChecked={upi?.enabled ?? true} /> Accept payments in the app
          </label>
          <div>
            <Button type="submit">Save</Button>
          </div>
        </form>
      </Card>

      <Card className="mb-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0 flex-1 basis-80">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="font-semibold text-gray-900">Recommended plan</h2>
              <span className="rounded-full bg-brand-500 px-2.5 py-0.5 text-xs font-bold text-ink-900">🔥 MOST POPULAR</span>
            </div>
            <p className="mt-1 text-xs leading-5 text-gray-500">
              This plan is already selected when people open the Premium page, and shows a “🔥 Most popular” badge. The plan
              with the lowest price per day keeps its “★ Best value” badge. Changes show in the app right away (app 1.11.8
              and newer).
            </p>
          </div>
          <form action={saveRecommended} className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
              Plan
              <Select name="plan_id" defaultValue={recommended?.id ?? ""} className="w-56!">
                <option value="">None (first plan is selected)</option>
                {plans.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                    {p.active ? "" : " (hidden)"}
                  </option>
                ))}
              </Select>
            </label>
            <Button type="submit">Save</Button>
          </form>
        </div>
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
                    {p.recommended ? (
                      <span className="shrink-0 rounded-full bg-brand-500 px-2 py-0.5 text-[11px] font-bold text-ink-900">
                        🔥 Most popular
                      </span>
                    ) : p.id === bestId ? (
                      <span className="shrink-0 rounded-full bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-800">
                        ★ Best value
                      </span>
                    ) : (
                      <span className="hidden shrink-0 font-mono text-[11px] text-gray-400 xl:inline">{p.code}</span>
                    )}
                  </div>
                </label>
                <label className="block">
                  <span className="mb-1 block text-xs font-medium text-gray-600 lg:sr-only">Price (₹)</span>
                  <Input
                    name="price_inr"
                    type="number"
                    min={1}
                    step={1}
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
