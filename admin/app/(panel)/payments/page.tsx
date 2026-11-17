import Link from "next/link";
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
import { formatDate } from "@/lib/format";
import { markPaid, revokePayment, savePlay, saveSettings } from "./actions";

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

type Purchase = { reference: string; plan: string; amount_paise: number; at: string; utr: string | null };

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

const isDate = (v?: string) => !!v && /^\d{4}-\d{2}-\d{2}$/.test(v);
// Dates in the filters are Indian dates (whole days, IST).
const dayStart = (v?: string) => (isDate(v) ? `${v}T00:00:00+05:30` : null);
const dayEnd = (v?: string) => {
  if (!isDate(v)) return null;
  const d = new Date(`${v}T00:00:00+05:30`);
  d.setDate(d.getDate() + 1);
  return d.toISOString();
};
const isUuid = (v?: string) => !!v && /^[0-9a-f-]{36}$/i.test(v);

function query(sp: SP, patch: Partial<SP>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...sp, ok: undefined, error: undefined, ...patch })) {
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

  const [{ data: planRows }, { data: settings }, { data: play }, { data: playSummary }] = await Promise.all([
    supabase.from("plans").select("id, name, price_inr").order("position"),
    supabase.from("payment_settings").select("upi_id, payee_name, enabled").eq("id", 1).maybeSingle(),
    supabase.from("play_settings").select("package_name, enabled, last_run_at, last_error").eq("id", 1).maybeSingle(),
    supabase.rpc("admin_play_report_summary"),
  ]);
  const ps = (playSummary ?? {}) as Record<string, number>;
  const plans = (planRows ?? []) as { id: string; name: string; price_inr: number }[];

  const tabs = (
    <SegmentTabs
      className="mb-5"
      items={views.map((v) => ({ href: query({}, { view: v.value }), label: v.label, active: v.value === view }))}
    />
  );

  const dateInputs = (
    <>
      <label className="text-xs text-gray-600">
        From
        <Input type="date" name="from" defaultValue={isDate(sp.from) ? sp.from : ""} />
      </label>
      <label className="text-xs text-gray-600">
        To
        <Input type="date" name="to" defaultValue={isDate(sp.to) ? sp.to : ""} />
      </label>
    </>
  );

  let body: React.ReactNode;
  let loadError: string | undefined;

  if (view === "plans") {
    const { data, error } = await supabase.rpc("admin_plan_sales", {
      p_from: dayStart(sp.from),
      p_to: dayEnd(sp.to),
    });
    loadError = error?.message;
    const rows = (data ?? []) as PlanSales[];
    const total = rows.reduce(
      (a, r) => ({ purchases: a.purchases + r.purchases, revenue: a.revenue + Number(r.revenue_paise) }),
      { purchases: 0, revenue: 0 },
    );
    body = (
      <>
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
                    href={query({}, { view: "orders", status: "success", plan: r.plan_id, from: sp.from, to: sp.to })}
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
          {buyers.length} customer{buyers.length === 1 ? "" : "s"} ·{" "}
          {buyers.filter((b) => b.purchases > 1).length} bought more than once
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
    const { data, error } = await supabase.rpc("admin_payment_orders_filtered", {
      p_status: status,
      p_plan: plan ?? null,
      p_user: user ?? null,
      p_from: dayStart(sp.from),
      p_to: dayEnd(sp.to),
      p_sort: sort,
      p_limit: 500,
    });
    loadError = error?.message;
    const orders = (data ?? []) as Order[];
    const { data: playRows } = orders.length
      ? await supabase.rpc("admin_play_report_rows", { p_ids: orders.map((o) => o.id) })
      : { data: [] };
    const playStatus = new Map(
      ((playRows ?? []) as { id: string; play_report_status: string | null; play_report_error: string | null }[]).map(
        (r) => [r.id, r],
      ),
    );
    const approved = orders.filter((o) => o.status === "approved");
    body = (
      <>
        <SegmentTabs
          className="mb-3"
          items={filters.map((f) => ({ href: query(sp, { status: f.value }), label: f.label, active: f.value === status }))}
        />
        <form className="mb-3 flex flex-wrap items-end gap-3">
          <input type="hidden" name="view" value="orders" />
          <input type="hidden" name="status" value={status} />
          {user && <input type="hidden" name="user" value={user} />}
          <label className="text-xs text-gray-600">
            Plan
            <Select name="plan" defaultValue={plan ?? ""}>
              <option value="">All plans</option>
              {plans.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} (₹{p.price_inr})
                </option>
              ))}
            </Select>
          </label>
          <label className="text-xs text-gray-600">
            Sort by
            <Select name="sort" defaultValue={sort}>
              {sorts.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </Select>
          </label>
          {dateInputs}
          <Button type="submit">Apply</Button>
          <Link href="/payments" className="text-sm text-gray-500 underline">
            Reset
          </Link>
        </form>
        {user && (
          <p className="mb-3 text-sm">
            Showing orders of <b>{orders[0]?.email ?? "this user"}</b> ·{" "}
            <Link href={query(sp, { user: undefined })} className="text-brand-700 underline">
              show everyone
            </Link>
          </p>
        )}
        <p className="mb-3 text-sm text-gray-500">
          {orders.length} order{orders.length === 1 ? "" : "s"} · {approved.length} successful · ₹
          {rupees(approved.reduce((a, o) => a + o.amount_paise, 0))} received
        </p>
        {orders.length === 0 ? (
          <Empty>No orders.</Empty>
        ) : (
        <Table>
          <thead>
            <tr>
              <Th>Order</Th>
              <Th>User</Th>
              <Th>Plan</Th>
              <Th>Amount</Th>
              <Th>Status</Th>
              <Th>UTR / source</Th>
              <Th>Raw UPI answer</Th>
              <Th>Times</Th>
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
                  </Td>
                  <Td>
                    <p className="font-medium">{o.display_name ?? "—"}</p>
                    <p className="text-xs text-gray-500">{o.email ?? "Guest"}</p>
                    <SourceBadge source={o.source} />
                    {o.user_purchases > 1 && (
                      <Link href={query(sp, { view: "buyers", q: o.email ?? "", min: "1" })} className="ml-1">
                        <Badge tone="purple">Repeat · {o.user_purchases} purchases</Badge>
                      </Link>
                    )}
                  </Td>
                  <Td>{o.plan_name}</Td>
                  <Td className="whitespace-nowrap font-semibold">₹{rupees(o.amount_paise)}</Td>
                  <Td>
                    <OrderStatus status={o.status} />
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
                  </Td>
                  <Td>
                    {o.upi_response ? (
                      <details>
                        <summary className="text-xs font-medium text-brand-700">Show</summary>
                        <code className="mt-1 block max-w-64 break-all text-[11px] text-gray-700">{o.upi_response}</code>
                      </details>
                    ) : (
                      <span className="text-xs text-gray-400">none yet</span>
                    )}
                    {o.report_count > 1 && <p className="text-[10px] text-gray-400">{o.report_count} answers</p>}
                  </Td>
                  <Td className="whitespace-nowrap text-xs text-gray-600">
                    <p>Created {formatDate(o.created_at)}</p>
                    <p>Updated {formatDate(o.updated_at)}</p>
                    <p>Verified {formatDate(o.verified_at)}</p>
                  </Td>
                  <Td>
                    {o.status === "approved" ? (
                      <form action={revokePayment.bind(null, o.id, back)} className="flex min-w-48 flex-col gap-1">
                        <Input name="reason" placeholder="Reason (optional)" aria-label="Revoke reason" />
                        <Button variant="danger" type="submit">Revoke</Button>
                      </form>
                    ) : o.status !== "revoked" ? (
                      <form action={markPaid.bind(null, o.id, back)} className="flex min-w-48 flex-col gap-1">
                        <Input name="utr" required minLength={6} maxLength={40} placeholder="Bank UTR" aria-label="Bank UTR" />
                        <Input
                          name="amount"
                          required
                          inputMode="decimal"
                          placeholder={`Amount received (₹${rupees(o.amount_paise)})`}
                          aria-label="Amount received"
                        />
                        <Button variant="success" type="submit">Mark as paid</Button>
                      </form>
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
      <PageHeader title="Payments" subtitle="UPI orders from the app. Check every success against your bank statement." />
      <Flash ok={sp.ok} error={sp.error ?? loadError} />
      <Card className="mb-6 border-amber-200 bg-amber-50 text-sm text-amber-900">
        <p className="font-semibold">How to read this page</p>
        <ul className="mt-1 list-disc space-y-1 pl-5">
          <li>
            <b>Success (source upi_app)</b>: the customer&apos;s UPI app said SUCCESS and the order passed the checks
            (matching reference, unused transaction id, under 2 hours). This answer comes from the customer&apos;s phone and{" "}
            <b>can be forged</b>. Confirm the UTR and amount in your bank statement; use <b>Revoke</b> if it isn&apos;t there.
          </li>
          <li>
            <b>Pending</b>: no reliable answer yet. If the money is in your bank, use <b>Mark as paid</b> with the bank UTR.
          </li>
          <li>Open orders are cancelled automatically after 24 hours.</li>
        </ul>
      </Card>

      {tabs}
      {body}

      <Card className="mt-8 max-w-xl">
        <h2 className="mb-3 font-semibold">UPI settings</h2>
        <form action={saveSettings.bind(null, back)} className="grid gap-3">
          <label className="text-sm">
            UPI ID
            <Input name="upi_id" defaultValue={settings?.upi_id ?? ""} required />
          </label>
          <label className="text-sm">
            Payee name (shown in the UPI app)
            <Input name="payee_name" defaultValue={settings?.payee_name ?? ""} required />
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="enabled" defaultChecked={settings?.enabled ?? true} /> Accept payments in the app
          </label>
          <div>
            <Button type="submit">Save</Button>
          </div>
        </form>
      </Card>

      <Card className="mt-6 max-w-xl">
        <div className="mb-2 flex items-center justify-between">
          <h2 className="font-semibold">Google Play reporting (Play Store version only)</h2>
          {play?.enabled ? <Badge tone="green">On</Badge> : <Badge>Off</Badge>}
        </div>
        <p className="mb-3 text-sm text-gray-600">
          Payments in the Play Store version are still your UPI flow. Google only requires each approved payment to be
          reported to it (within 24 hours) so it can bill its service fee. This happens automatically every 5 minutes.
          Payments from the APKs you share yourself are never reported.
        </p>
        <div className="mb-3 grid grid-cols-4 gap-2 text-center text-sm">
          <div><p className="text-lg font-bold">{ps.pending ?? 0}</p><p className="text-xs text-gray-500">waiting</p></div>
          <div><p className="text-lg font-bold">{ps.reported ?? 0}</p><p className="text-xs text-gray-500">reported</p></div>
          <div><p className="text-lg font-bold">{ps.refunded ?? 0}</p><p className="text-xs text-gray-500">refunds</p></div>
          <div><p className={`text-lg font-bold ${ps.failed ? "text-red-600" : ""}`}>{ps.failed ?? 0}</p><p className="text-xs text-gray-500">failed</p></div>
        </div>
        {(ps.overdue ?? 0) > 0 && (
          <p className="mb-3 text-sm font-medium text-red-700">{ps.overdue} payment(s) are close to Google&apos;s 24-hour limit.</p>
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
            <input type="checkbox" name="enabled" defaultChecked={play?.enabled ?? false} /> Report Play Store payments to Google
          </label>
          <div>
            <Button type="submit">Save</Button>
          </div>
        </form>
        <details className="mt-4 text-sm text-gray-600">
          <summary className="cursor-pointer font-medium text-gray-900">One-time setup</summary>
          <ol className="mt-2 list-decimal space-y-1 pl-5">
            <li>Play Console → your app → <b>Monetize with Play → Alternative billing</b>: enrol in <b>Alternative billing only</b> for India.</li>
            <li>Google Cloud Console → create a <b>service account</b> → Keys → <b>Add key → JSON</b> (downloads a file).</li>
            <li>Play Console → <b>Users and permissions → Invite new users</b> → the service account email → give it access to this app (View financial data / Manage orders).</li>
            <li>Supabase → Edge Functions → <b>Secrets</b> → add <code>GOOGLE_SERVICE_ACCOUNT_JSON</code> = the whole JSON file content.</li>
            <li>Tick <b>Report Play Store payments to Google</b> above and Save.</li>
          </ol>
        </details>
      </Card>
    </>
  );
}
