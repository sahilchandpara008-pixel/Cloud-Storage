import Link from "next/link";
import { DatePresets } from "@/components/date-range";
import {
  Badge,
  Button,
  Card,
  Empty,
  Flash,
  Input,
  PageHeader,
  SegmentTabs,
  Select,
  SourceBadge,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { dayEnd, dayStart, isDate } from "@/lib/dates";
import { formatDate } from "@/lib/format";
import { markPaid, revokePayment, savePlay } from "./actions";

type Order = {
  id: string;
  reference: string;
  user_id: string;
  email: string | null;
  display_name: string | null;
  source: string;
  plan_name: string;
  amount_paise: number;
  status: string;
  status_reason: string | null;
  upi_response: string | null;
  client_status: string | null;
  txn_id: string | null;
  verification_source: string | null;
  reviewed_by_email: string | null;
  report_count: number;
  created_at: string;
  updated_at: string;
  verified_at: string | null;
  plan_id: string;
  user_purchases: number;
  admin_test: boolean;
};

type PlanSales = {
  plan_id: string;
  plan_name: string;
  price_inr: number;
  active: boolean;
  purchases: number;
  buyers: number;
  repeat_buyers: number;
  revenue_paise: number;
  pending: number;
  failed: number;
  last_purchase_at: string | null;
};

type Purchase = {
  reference: string;
  plan: string;
  amount_paise: number;
  at: string;
  utr: string | null;
};

type Buyer = {
  user_id: string;
  email: string | null;
  display_name: string | null;
  source: string;
  purchases: number;
  total_paise: number;
  first_purchase_at: string;
  last_purchase_at: string;
  current_plan: string | null;
  plan_ends_at: string | null;
  history: Purchase[];
};

type SP = {
  ok?: string;
  error?: string;
  view?: string;
  status?: string;
  plan?: string;
  sort?: string;
  from?: string;
  to?: string;
  user?: string;
  min?: string;
  q?: string;
};

const views = [
  { value: "orders", label: "Orders" },
  { value: "funnel", label: "Payment success" },
  { value: "plans", label: "Plan summary" },
  { value: "buyers", label: "Customers & repeat buyers" },
];

const sorts = [
  { value: "date_desc", label: "Date: newest first" },
  { value: "date_asc", label: "Date: oldest first" },
  { value: "amount_desc", label: "Price: high to low" },
  { value: "amount_asc", label: "Price: low to high" },
  { value: "plan", label: "Plan" },
];

const isUuid = (v?: string) => !!v && /^[0-9a-f-]{36}$/i.test(v);

function query(sp: SP, patch: Partial<SP>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({
    ...sp,
    ok: undefined,
    error: undefined,
    ...patch,
  })) {
    if (v) q.set(k, v);
  }
  return `/payments?${q.toString()}`;
}

const filters = [
  { value: "all", label: "All" },
  { value: "pending", label: "Pending" },
  { value: "success", label: "Success" },
  { value: "failed", label: "Failed" },
  { value: "cancelled", label: "Cancelled" },
  { value: "revoked", label: "Revoked" },
];

const rupees = (paise: number) => (paise / 100).toFixed(2);

function OrderStatus({ status }: { status: string }) {
  switch (status) {
    case "approved":
      return <Badge tone="green">Success</Badge>;
    case "failed":
      return <Badge tone="red">Failed</Badge>;
    case "cancelled":
      return <Badge>Cancelled</Badge>;
    case "revoked":
      return <Badge tone="purple">Revoked</Badge>;
    case "initiated":
      return <Badge tone="amber">Pending (app not answered)</Badge>;
    default:
      return <Badge tone="amber">Pending</Badge>;
  }
}

export default async function PaymentsPage({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams;
  const view = views.some((v) => v.value === sp.view) ? sp.view! : "orders";
  const status = filters.some((f) => f.value === sp.status) ? sp.status! : "all";
  const sort = sorts.some((s) => s.value === sp.sort) ? sp.sort! : "date_desc";
  const plan = isUuid(sp.plan) ? sp.plan! : undefined;
  const user = isUuid(sp.user) ? sp.user! : undefined;
  const back = query(sp, {});
  const { supabase } = await requireOwner();

  const [{ data: planRows }, { data: play }, { data: playSummary }] = await Promise.all([
    supabase.from("plans").select("id, name, price_inr").order("position"),
    supabase.from("play_settings").select("package_name, enabled, last_run_at, last_error").eq("id", 1).maybeSingle(),
    supabase.rpc("admin_play_report_summary"),
  ]);
  const ps = (playSummary ?? {}) as Record<string, number>;
  const plans = (planRows ?? []) as {
    id: string;
    name: string;
    price_inr: number;
  }[];

  const tabs = (
    <SegmentTabs
      className="mb-5"
      items={views.map((v) => ({
        href: query({}, { view: v.value }),
        label: v.label,
        active: v.value === view,
      }))}
    />
  );

  const dateInputs = (
    <>
      <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
        From
        <Input type="date" name="from" defaultValue={isDate(sp.from) ? sp.from : ""} className="w-40" />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
        To
        <Input type="date" name="to" defaultValue={isDate(sp.to) ? sp.to : ""} className="w-40" />
      </label>
    </>
  );

  let body: React.ReactNode;
  let loadError: string | undefined;

  if (view === "funnel") {
    const { data, error } = await supabase.rpc("admin_payment_funnel", {
      p_from: dayStart(sp.from),
      p_to: dayEnd(sp.to),
    });
    loadError = error?.message;
    type G = { installs: number; tried: number; paid: number; not_paid: number; waiting: number };
    const f = (data ?? {}) as {
      groups?: Record<string, G>;
      orders?: Record<string, number>;
      reasons?: { reason: string; n: number }[];
    };
    const pc = (a: number, b: number) => (b > 0 ? `${Math.round((a / b) * 100)}%` : "—");
    const rows: [string, G | undefined][] = [
      ["Everyone", f.groups?.all],
      ["From Meta ads", f.groups?.ads],
      ["Organic", f.groups?.organic],
    ];
    const o = f.orders ?? {};
    body = (
      <>
        <DatePresets
          className="mb-3"
          from={sp.from}
          to={sp.to}
          href={(fr, t) => query({}, { view: "funnel", from: fr, to: t })}
        />
        <form className="mb-4 flex flex-wrap items-end gap-3">
          <input type="hidden" name="view" value="funnel" />
          {dateInputs}
          <Button type="submit">Apply</Button>
        </form>
        <p className="mb-3 text-sm text-gray-500">
          People who installed the app in this period, and what happened when they tried to buy a plan (at any time
          after installing). Your own test payments are left out.
        </p>
        <div className="space-y-4">
          {rows.map(([label, g]) => {
            const x = g ?? { installs: 0, tried: 0, paid: 0, not_paid: 0, waiting: 0 };
            return (
              <Card key={label}>
                <h3 className="mb-3 font-semibold">{label}</h3>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
                  {[
                    ["Downloaded", String(x.installs), ""],
                    ["Tried to pay", String(x.tried), `${pc(x.tried, x.installs)} of downloads`],
                    ["Paid", String(x.paid), `${pc(x.paid, x.tried)} success`],
                    ["Did not pay", String(x.not_paid), `${pc(x.not_paid, x.tried)} unsuccessful`],
                    ["Still waiting", String(x.waiting), "payment not confirmed yet"],
                  ].map(([k, v, h]) => (
                    <div key={k} className="rounded-xl border border-gray-200 px-3 py-2">
                      <p className="text-xs text-gray-500">{k}</p>
                      <p className="text-2xl font-bold tabular-nums">{v}</p>
                      {h && <p className="text-xs text-gray-500">{h}</p>}
                    </div>
                  ))}
                </div>
                {x.tried > 0 && (
                  <div className="mt-3 flex h-2.5 overflow-hidden rounded-full bg-gray-100" aria-hidden="true">
                    <div className="h-full bg-green-600" style={{ width: `${(x.paid / x.tried) * 100}%` }} />
                    <div className="h-full bg-red-600" style={{ width: `${(x.not_paid / x.tried) * 100}%` }} />
                    <div className="h-full bg-amber-500" style={{ width: `${(x.waiting / x.tried) * 100}%` }} />
                  </div>
                )}
              </Card>
            );
          })}
          <Card>
            <h3 className="mb-3 font-semibold">Payment attempts in this period</h3>
            <p className="mb-3 text-sm text-gray-500">
              Every order started in this period (one person can try more than once).
            </p>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
              {[
                ["Started", o.total ?? 0, ""],
                ["Successful", o.approved ?? 0, pc(o.approved ?? 0, o.total ?? 0)],
                ["Failed", o.failed ?? 0, pc(o.failed ?? 0, o.total ?? 0)],
                ["Not completed", o.cancelled ?? 0, pc(o.cancelled ?? 0, o.total ?? 0)],
                ["Waiting", o.pending ?? 0, pc(o.pending ?? 0, o.total ?? 0)],
              ].map(([k, v, h]) => (
                <div key={String(k)} className="rounded-xl border border-gray-200 px-3 py-2">
                  <p className="text-xs text-gray-500">{k}</p>
                  <p className="text-2xl font-bold tabular-nums">{v}</p>
                  {h && <p className="text-xs text-gray-500">{h}</p>}
                </div>
              ))}
            </div>
            {(f.reasons?.length ?? 0) > 0 && (
              <>
                <h4 className="mb-2 mt-4 text-sm font-semibold">Why payments did not go through</h4>
                <ul className="space-y-1 text-sm">
                  {f.reasons!.map((x) => (
                    <li key={x.reason} className="flex justify-between gap-3">
                      <span className="text-gray-600">{x.reason}</span>
                      <b className="tabular-nums">{x.n}</b>
                    </li>
                  ))}
                </ul>
              </>
            )}
            <Link
              href={query({}, { view: "orders", status: "cancelled", from: sp.from, to: sp.to })}
              className="mt-3 inline-block text-sm text-brand-700 underline"
            >
              See the orders that did not go through
            </Link>
          </Card>
        </div>
      </>
    );
  } else if (view === "plans") {
    const { data, error } = await supabase.rpc("admin_plan_sales", {
      p_from: dayStart(sp.from),
      p_to: dayEnd(sp.to),
    });
    loadError = error?.message;
    const rows = (data ?? []) as PlanSales[];
    const total = rows.reduce(
      (a, r) => ({
        purchases: a.purchases + r.purchases,
        revenue: a.revenue + Number(r.revenue_paise),
      }),
      { purchases: 0, revenue: 0 },
    );
    body = (
      <>
        <DatePresets
          className="mb-3"
          from={sp.from}
          to={sp.to}
          href={(f, t) => query({}, { view: "plans", from: f, to: t })}
        />
        <form className="mb-4 flex flex-wrap items-end gap-3">
          <input type="hidden" name="view" value="plans" />
          {dateInputs}
          <Button type="submit">Apply</Button>
          {(sp.from || sp.to) && (
            <Link href={query({}, { view: "plans" })} className="text-sm text-gray-500 underline">
              Clear dates
            </Link>
          )}
        </form>
        <div className="mb-4 grid gap-3 sm:grid-cols-3">
          <Card>
            <p className="text-xs text-gray-500">Purchases</p>
            <p className="text-2xl font-bold">{total.purchases}</p>
          </Card>
          <Card>
            <p className="text-xs text-gray-500">Revenue</p>
            <p className="text-2xl font-bold">₹{rupees(total.revenue)}</p>
          </Card>
          <Card>
            <p className="text-xs text-gray-500">Best-selling plan</p>
            <p className="text-2xl font-bold">
              {[...rows].sort((a, b) => b.purchases - a.purchases)[0]?.purchases
                ? [...rows].sort((a, b) => b.purchases - a.purchases)[0].plan_name
                : "—"}
            </p>
          </Card>
        </div>
        <Table>
          <thead>
            <tr>
              <Th>Plan</Th>
              <Th>Price</Th>
              <Th>Purchases</Th>
              <Th>Buyers</Th>
              <Th>Bought it again</Th>
              <Th>Revenue</Th>
              <Th>Pending</Th>
              <Th>Failed / cancelled</Th>
              <Th>Last purchase</Th>
              <Th></Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map((r) => (
              <tr key={r.plan_id}>
                <Td>
                  <p className="font-medium">{r.plan_name}</p>
                  {!r.active && <Badge>Inactive</Badge>}
                </Td>
                <Td>₹{r.price_inr}</Td>
                <Td className="text-lg font-bold">{r.purchases}</Td>
                <Td>{r.buyers}</Td>
                <Td>{r.repeat_buyers}</Td>
                <Td className="font-semibold">₹{rupees(Number(r.revenue_paise))}</Td>
                <Td>{r.pending}</Td>
                <Td>{r.failed}</Td>
                <Td className="whitespace-nowrap text-xs">{formatDate(r.last_purchase_at)}</Td>
                <Td>
                  <Link
                    className="text-sm text-brand-700 underline"
                    href={query(
                      {},
                      {
                        view: "orders",
                        status: "success",
                        plan: r.plan_id,
                        from: sp.from,
                        to: sp.to,
                      },
                    )}
                  >
                    View orders
                  </Link>
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      </>
    );
  } else if (view === "buyers") {
    const min = sp.min === "2" || sp.min === "3" ? sp.min : "1";
    const { data, error } = await supabase.rpc("admin_buyers", {
      p_min_purchases: Number(min),
      p_search: sp.q?.trim() || null,
      p_limit: 500,
    });
    loadError = error?.message;
    const buyers = (data ?? []) as Buyer[];
    const minFilters = [
      { value: "1", label: "All paying customers" },
      { value: "2", label: "Repeat buyers (2+)" },
      { value: "3", label: "Loyal (3+)" },
    ];
    body = (
      <>
        <SegmentTabs
          className="mb-3"
          items={minFilters.map((f) => ({
            href: query({}, { view: "buyers", min: f.value, q: sp.q }),
            label: f.label,
            active: f.value === min,
          }))}
        />
        <form className="mb-4 flex flex-wrap items-end gap-3">
          <input type="hidden" name="view" value="buyers" />
          <input type="hidden" name="min" value={min} />
          <label className="text-xs text-gray-600">
            Search email or name
            <Input name="q" defaultValue={sp.q ?? ""} placeholder="name@gmail.com" />
          </label>
          <Button type="submit">Search</Button>
        </form>
        <p className="mb-3 text-sm text-gray-500">
          {buyers.length} customer{buyers.length === 1 ? "" : "s"} · {buyers.filter((b) => b.purchases > 1).length}{" "}
          bought more than once
        </p>
        {buyers.length === 0 ? (
          <Empty>No customers match.</Empty>
        ) : (
          <div className="space-y-3">
            {buyers.map((b) => (
              <Card key={b.user_id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold">
                      {b.display_name ?? "—"}{" "}
                      {b.purchases > 1 ? (
                        <Badge tone="purple">Repeat buyer · {b.purchases} purchases</Badge>
                      ) : (
                        <Badge>1 purchase</Badge>
                      )}
                    </p>
                    <p className="text-sm text-gray-600">{b.email ?? "Guest"}</p>
                    <SourceBadge source={b.source} />
                  </div>
                  <div className="text-right text-sm">
                    <p className="text-lg font-bold">₹{rupees(Number(b.total_paise))}</p>
                    <p className="text-xs text-gray-500">total paid</p>
                    <p className="mt-1 text-xs">
                      {b.current_plan ? (
                        <>
                          Active: <b>{b.current_plan}</b> until {formatDate(b.plan_ends_at)}
                        </>
                      ) : (
                        <span className="text-gray-500">No active plan</span>
                      )}
                    </p>
                  </div>
                </div>
                <div className="mt-3 grid gap-1 text-xs text-gray-600 sm:grid-cols-2">
                  <p>First purchase: {formatDate(b.first_purchase_at)}</p>
                  <p>Last purchase: {formatDate(b.last_purchase_at)}</p>
                </div>
                <details className="mt-3" open={b.purchases > 1}>
                  <summary className="cursor-pointer text-sm font-medium text-brand-700">
                    Purchase history ({b.history.length})
                  </summary>
                  <ol className="mt-2 space-y-1 border-l-2 border-brand-200 pl-4">
                    {b.history.map((h, i) => (
                      <li key={h.reference} className="text-sm">
                        <span className="font-semibold">#{i + 1}</span> · {formatDate(h.at)} · <b>{h.plan}</b> · ₹
                        {rupees(h.amount_paise)}
                        <span className="ml-2 font-mono text-xs text-gray-400">
                          {h.reference}
                          {h.utr ? ` · UTR ${h.utr}` : ""}
                        </span>
                      </li>
                    ))}
                  </ol>
                  <Link
                    href={query({}, { view: "orders", user: b.user_id })}
                    className="mt-2 inline-block text-xs text-gray-500 underline"
                  >
                    All orders of this user (incl. failed / pending)
                  </Link>
                </details>
              </Card>
            ))}
          </div>
        )}
      </>
    );
  } else {
    const filter = {
      p_status: status,
      p_plan: plan ?? null,
      p_user: user ?? null,
      p_from: dayStart(sp.from),
      p_to: dayEnd(sp.to),
    };
    const [{ data, error }, { data: totalsRow }] = await Promise.all([
      supabase.rpc("admin_payment_orders_list", { ...filter, p_sort: sort, p_limit: 500 }),
      supabase.rpc("admin_payment_orders_totals", filter),
    ]);
    loadError = error?.message;
    const orders = (data ?? []) as Order[];
    const totals = (totalsRow ?? {}) as {
      orders?: number;
      successful?: number;
      received_paise?: number;
      test_orders?: number;
    };
    const { data: playRows } = orders.length
      ? await supabase.rpc("admin_play_report_rows", {
          p_ids: orders.map((o) => o.id),
        })
      : { data: [] };
    const playStatus = new Map(
      (
        (playRows ?? []) as {
          id: string;
          play_report_status: string | null;
          play_report_error: string | null;
        }[]
      ).map((r) => [r.id, r]),
    );
    body = (
      <>
        <SegmentTabs
          className="mb-3"
          items={filters.map((f) => ({
            href: query(sp, { status: f.value }),
            label: f.label,
            active: f.value === status,
          }))}
        />
        <DatePresets className="mb-3" from={sp.from} to={sp.to} href={(f, t) => query(sp, { from: f, to: t })} />
        <form className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-gray-200 bg-white p-3 shadow-sm">
          <input type="hidden" name="view" value="orders" />
          <input type="hidden" name="status" value={status} />
          {user && <input type="hidden" name="user" value={user} />}
          <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
            Plan
            <Select name="plan" defaultValue={plan ?? ""} className="w-48">
              <option value="">All plans</option>
              {plans.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} (₹{p.price_inr})
                </option>
              ))}
            </Select>
          </label>
          <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
            Sort by
            <Select name="sort" defaultValue={sort} className="w-44">
              {sorts.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </Select>
          </label>
          {dateInputs}
          <div className="flex items-center gap-3">
            <Button type="submit">Apply</Button>
            <Link href="/payments" className="text-sm font-medium text-gray-500 hover:text-gray-800">
              Reset
            </Link>
          </div>
        </form>
        {user && (
          <p className="mb-3 text-sm">
            Showing orders of <b>{orders[0]?.email ?? "this user"}</b> ·{" "}
            <Link href={query(sp, { user: undefined })} className="text-brand-700 underline">
              show everyone
            </Link>
          </p>
        )}
        <div className="mb-4 grid grid-cols-3 gap-3">
          {[
            ["Orders", String(totals.orders ?? orders.length)],
            ["Successful", String(totals.successful ?? 0)],
            ["Received", `₹${rupees(Number(totals.received_paise ?? 0))}`],
          ].map(([label, value]) => (
            <div key={label} className="rounded-xl border border-gray-200 bg-white px-4 py-3 shadow-sm">
              <p className="text-xs font-medium text-gray-500">{label}</p>
              <p className="mt-0.5 text-xl font-semibold tabular-nums text-gray-900">{value}</p>
            </div>
          ))}
        </div>
        <p className="-mt-2 mb-4 text-xs text-gray-500">
          {status === "success" ? "Dates are when the payment was approved." : "Dates are when the order was made."}{" "}
          Successful and Received leave out your own test payments
          {totals.test_orders ? ` (${totals.test_orders} test payment${totals.test_orders === 1 ? "" : "s"} here)` : ""}.
          {(totals.orders ?? 0) > orders.length && ` The list shows the first ${orders.length} orders.`}
        </p>
        {orders.length === 0 ? (
          <Empty>No orders.</Empty>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>Order</Th>
                <Th>User</Th>
                <Th>Plan · amount</Th>
                <Th>Status</Th>
                <Th>UTR / UPI answer</Th>
                <Th>Action</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {orders.map((o) => {
                const open = o.status === "initiated" || o.status === "pending";
                return (
                  <tr key={o.id} className={open && o.upi_response ? "bg-amber-50/60" : ""}>
                    <Td>
                      <p className="font-mono text-xs font-semibold" title={`Order id ${o.id}`}>
                        {o.reference}
                      </p>
                      <p
                        className="mt-0.5 whitespace-nowrap text-[11px] text-gray-500"
                        title={`Created ${formatDate(o.created_at)}\nUpdated ${formatDate(o.updated_at)}\nVerified ${formatDate(o.verified_at)}`}
                      >
                        {formatDate(o.created_at)}
                      </p>
                    </Td>
                    <Td>
                      <p className="font-medium">{o.display_name ?? "—"}</p>
                      <p className="text-xs text-gray-500">{o.email ?? "Guest"}</p>
                      <div className="mt-1 flex flex-wrap items-center gap-1">
                        <SourceBadge source={o.source} />
                        {o.user_purchases > 1 && (
                          <Link
                            href={query(sp, {
                              view: "buyers",
                              q: o.email ?? "",
                              min: "1",
                            })}
                          >
                            <Badge tone="purple">Repeat · {o.user_purchases} purchases</Badge>
                          </Link>
                        )}
                      </div>
                    </Td>
                    <Td>
                      <p className="whitespace-nowrap font-semibold tabular-nums">₹{rupees(o.amount_paise)}</p>
                      <p className="text-xs text-gray-500">{o.plan_name}</p>
                    </Td>
                    <Td>
                      <OrderStatus status={o.status} />
                      {o.admin_test && (
                        <span className="ml-1">
                          <Badge>Admin test</Badge>
                        </span>
                      )}
                      {o.status_reason && <p className="mt-1 max-w-48 text-xs text-gray-500">{o.status_reason}</p>}
                      {playStatus.has(o.id) && (
                        <p className="mt-1">
                          <Badge tone={playStatus.get(o.id)!.play_report_status === "failed" ? "red" : "blue"}>
                            Play Store · Google report: {playStatus.get(o.id)!.play_report_status ?? "after payment"}
                          </Badge>
                          {playStatus.get(o.id)!.play_report_error && (
                            <span className="mt-1 block max-w-48 break-all text-[10px] text-red-600">
                              {playStatus.get(o.id)!.play_report_error}
                            </span>
                          )}
                        </p>
                      )}
                    </Td>
                    <Td>
                      <p className="font-mono text-xs">{o.txn_id ?? "—"}</p>
                      {o.verification_source && <p className="text-xs text-gray-500">{o.verification_source}</p>}
                      {o.reviewed_by_email && <p className="text-xs text-gray-400">by {o.reviewed_by_email}</p>}
                      {o.upi_response ? (
                        <details>
                          <summary className="text-xs font-medium text-brand-700">Show UPI answer</summary>
                          <code className="mt-1 block max-w-64 break-all text-[11px] text-gray-700">
                            {o.upi_response}
                          </code>
                        </details>
                      ) : (
                        <span className="text-[11px] text-gray-400">UPI answer: none yet</span>
                      )}
                      {o.report_count > 1 && <p className="text-[10px] text-gray-400">{o.report_count} answers</p>}
                    </Td>
                    <Td>
                      {o.status === "approved" ? (
                        <details className="group relative">
                          <summary className="inline-flex list-none items-center rounded-lg border border-red-200 bg-white px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-50 [&::-webkit-details-marker]:hidden">
                            Revoke…
                          </summary>
                          <form
                            action={revokePayment.bind(null, o.id, back)}
                            className="mt-2 flex w-56 flex-col gap-2 rounded-lg border border-gray-200 bg-gray-50 p-2"
                          >
                            <Input name="reason" placeholder="Reason (optional)" aria-label="Revoke reason" />
                            <Button variant="danger" type="submit">
                              Revoke
                            </Button>
                          </form>
                        </details>
                      ) : o.status !== "revoked" ? (
                        <details className="group relative">
                          <summary className="inline-flex list-none items-center whitespace-nowrap rounded-lg border border-green-200 bg-white px-3 py-1.5 text-xs font-semibold text-green-700 hover:bg-green-50 [&::-webkit-details-marker]:hidden">
                            Mark as paid…
                          </summary>
                          <form
                            action={markPaid.bind(null, o.id, back)}
                            className="mt-2 flex w-56 flex-col gap-2 rounded-lg border border-gray-200 bg-gray-50 p-2"
                          >
                            <Input
                              name="utr"
                              required
                              minLength={6}
                              maxLength={40}
                              placeholder="Bank UTR"
                              aria-label="Bank UTR"
                            />
                            <Input
                              name="amount"
                              required
                              inputMode="decimal"
                              placeholder={`Amount received (₹${rupees(o.amount_paise)})`}
                              aria-label="Amount received"
                            />
                            <Button variant="success" type="submit">
                              Mark as paid
                            </Button>
                          </form>
                        </details>
                      ) : null}
                    </Td>
                  </tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Payments"
        subtitle="UPI orders from the app. Check every success against your bank statement."
      />
      <Flash ok={sp.ok} error={sp.error ?? loadError} />
      <details className="mb-5 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
        <summary className="font-semibold">How to read this page</summary>
        <ul className="mt-2 list-disc space-y-1 pl-5">
          <li>
            <b>Success (source upi_app)</b>: the customer&apos;s UPI app said SUCCESS and the order passed the checks
            (matching reference, unused transaction id, under 2 hours). This answer comes from the customer&apos;s phone
            and <b>can be forged</b>. Confirm the UTR and amount in your bank statement; use <b>Revoke</b> if it
            isn&apos;t there.
          </li>
          <li>
            <b>Pending</b>: no reliable answer yet. If the money is in your bank, use <b>Mark as paid</b> with the bank
            UTR.
          </li>
          <li>Open orders are cancelled automatically after 24 hours.</li>
        </ul>
      </details>

      {tabs}
      {body}

      <div className="mt-8 max-w-2xl">
        <Card>
          <div className="mb-2 flex items-center justify-between gap-2">
            <h2 className="font-semibold">Google Play reporting (Play Store version only)</h2>
            {play?.enabled ? <Badge tone="green">On</Badge> : <Badge>Off</Badge>}
          </div>
          <p className="mb-3 text-sm text-gray-600">
            Payments in the Play Store version are still your UPI flow. Google only requires each approved payment to be
            reported to it (within 24 hours) so it can bill its service fee. This happens automatically every 5 minutes.
            Payments from the APKs you share yourself are never reported.
          </p>
          <div className="mb-3 grid grid-cols-4 gap-2 text-center text-sm">
            <div>
              <p className="text-lg font-bold">{ps.pending ?? 0}</p>
              <p className="text-xs text-gray-500">waiting</p>
            </div>
            <div>
              <p className="text-lg font-bold">{ps.reported ?? 0}</p>
              <p className="text-xs text-gray-500">reported</p>
            </div>
            <div>
              <p className="text-lg font-bold">{ps.refunded ?? 0}</p>
              <p className="text-xs text-gray-500">refunds</p>
            </div>
            <div>
              <p className={`text-lg font-bold ${ps.failed ? "text-red-600" : ""}`}>{ps.failed ?? 0}</p>
              <p className="text-xs text-gray-500">failed</p>
            </div>
          </div>
          {(ps.overdue ?? 0) > 0 && (
            <p className="mb-3 text-sm font-medium text-red-700">
              {ps.overdue} payment(s) are close to Google&apos;s 24-hour limit.
            </p>
          )}
          <p className="mb-3 text-xs text-gray-500">
            Last run: {formatDate(play?.last_run_at)}
            {play?.last_error && <span className="block text-red-600">Last error: {play.last_error}</span>}
          </p>
          <form action={savePlay.bind(null, back)} className="grid gap-3">
            <label className="text-sm">
              App package name
              <Input name="package_name" defaultValue={play?.package_name ?? "com.flixvault.app"} required />
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" name="enabled" defaultChecked={play?.enabled ?? false} /> Report Play Store
              payments to Google
            </label>
            <div>
              <Button type="submit">Save</Button>
            </div>
          </form>
          <details className="mt-4 text-sm text-gray-600">
            <summary className="cursor-pointer font-medium text-gray-900">One-time setup</summary>
            <ol className="mt-2 list-decimal space-y-1 pl-5">
              <li>
                Play Console → your app → <b>Monetize with Play → Alternative billing</b>: enrol in{" "}
                <b>Alternative billing only</b> for India.
              </li>
              <li>
                Google Cloud Console → create a <b>service account</b> → Keys → <b>Add key → JSON</b> (downloads a
                file).
              </li>
              <li>
                Play Console → <b>Users and permissions → Invite new users</b> → the service account email → give it
                access to this app (View financial data / Manage orders).
              </li>
              <li>
                Supabase → Edge Functions → <b>Secrets</b> → add <code>GOOGLE_SERVICE_ACCOUNT_JSON</code> = the whole
                JSON file content.
              </li>
              <li>
                Tick <b>Report Play Store payments to Google</b> above and Save.
              </li>
            </ol>
          </details>
        </Card>
      </div>
    </>
  );
}
