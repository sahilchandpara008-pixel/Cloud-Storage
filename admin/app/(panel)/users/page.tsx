import Link from "next/link";
import { DatePresets } from "@/components/date-range";
import {
  Badge,
  Button,
  Empty,
  Flash,
  Input,
  PageHeader,
  Select,
  SourceBadge,
  Stat,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { dayEnd, dayStart, isDate, rangeLabel } from "@/lib/dates";
import { formatDate } from "@/lib/format";
import type { AppUser } from "@/lib/users";
import { dismissPlanRequest, grantPremium } from "./actions";

type PlanRequest = {
  id: string;
  user_id: string;
  email: string;
  display_name: string;
  source: "ads" | "organic";
  plan_code: string;
  plan_name: string;
  created_at: string;
};

const filters = [
  { value: "all", label: "All users" },
  { value: "registered", label: "Registered (logged in)" },
  { value: "guest", label: "Guests" },
  { value: "ads", label: "Gets ads content" },
  { value: "organic", label: "Organic (no ads content)" },
  { value: "premium", label: "Active subscribers" },
  { value: "expired", label: "Plan expired" },
  { value: "paying", label: "Paid at least once" },
  { value: "repeat", label: "Repeat buyers (2+)" },
  { value: "never_paid", label: "Never paid" },
];

const sorts = [
  { value: "newest", label: "Newest first" },
  { value: "oldest", label: "Oldest first" },
  { value: "name", label: "Name A–Z" },
  { value: "spent", label: "Spent: high to low" },
  { value: "purchases", label: "Most purchases" },
  { value: "last_purchase", label: "Latest purchase" },
  { value: "plan_end", label: "Plan ends soonest" },
];

const PAGE_SIZE = 100;

type Stats = {
  new_users: number;
  registered: number;
  guests: number;
  from_ads: number;
  organic: number;
  purchases: number;
  revenue_paise: number;
  paying_customers: number;
  new_customers: number;
  repeat_customers: number;
  active_subscribers: number;
  all_users: number;
  by_plan: { plan: string; price_inr: number; active_now: number; sold: number; revenue_paise: number }[];
};

type SP = {
  ok?: string;
  error?: string;
  filter?: string;
  q?: string;
  from?: string;
  to?: string;
  sort?: string;
  page?: string;
};

function usersUrl(sp: SP, patch: Partial<SP>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...sp, ok: undefined, error: undefined, ...patch })) {
    if (v && !(k === "filter" && v === "all") && !(k === "sort" && v === "newest") && !(k === "page" && v === "1")) {
      q.set(k, v);
    }
  }
  const s = q.toString();
  return s ? `/users?${s}` : "/users";
}

const inr = (paise: number) =>
  `₹${(Number(paise) / 100).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;


export default async function UsersPage({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams;
  const filter = filters.some((f) => f.value === sp.filter) ? sp.filter! : "all";
  const sort = sorts.some((o) => o.value === sp.sort) ? sp.sort! : "newest";
  const q = sp.q ?? "";
  const from = isDate(sp.from) ? sp.from : undefined;
  const to = isDate(sp.to) ? sp.to : undefined;
  const page = Math.max(1, Number(sp.page) || 1);
  const back = usersUrl(sp, {});
  const { supabase } = await requireOwner();

  const [{ data, error }, { data: plans }, { data: requestRows }, { data: statsRow }] = await Promise.all([
    supabase.rpc("admin_users", {
      p_filter: filter,
      p_search: q || null,
      p_limit: PAGE_SIZE,
      p_offset: (page - 1) * PAGE_SIZE,
      p_from: dayStart(from),
      p_to: dayEnd(to),
      p_sort: sort,
    }),
    supabase.from("plans").select("code, name").eq("active", true).order("position"),
    supabase.rpc("admin_plan_requests"),
    supabase.rpc("admin_user_stats", { p_from: dayStart(from), p_to: dayEnd(to) }),
  ]);
  const users = (data ?? []) as AppUser[];
  const total = Number(users[0]?.total_count ?? 0);
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const requests = (requestRows ?? []) as PlanRequest[];
  const stats = statsRow as Stats | null;
  const range = rangeLabel(from, to);
  const filtered = filter !== "all" || !!q;

  return (
    <>
      <PageHeader title="Users" subtitle="App users, where they came from, and their plans." />
      <Flash ok={sp.ok} error={sp.error ?? error?.message} />

      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <DatePresets from={from} to={to} href={(f, t) => usersUrl(sp, { from: f, to: t, page: undefined })} />
        <p className="text-xs text-gray-500">
          Showing <b className="text-gray-800">{range}</b> · sign-up date for users, payment date for sales
        </p>
      </div>

      {stats && (
        <section className="mb-6" aria-label="Summary">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat
              label="New users"
              value={stats.new_users.toLocaleString("en-IN")}
              hint={`${stats.registered} registered · ${stats.guests} guests`}
              icon="👥"
              tone="brand"
              href={usersUrl(sp, { filter: "all", page: undefined })}
            />
            <Stat
              label="From ads / organic"
              value={`${stats.from_ads.toLocaleString("en-IN")} / ${stats.organic.toLocaleString("en-IN")}`}
              hint={stats.new_users ? `${Math.round((stats.from_ads / stats.new_users) * 100)}% from ads` : "—"}
              icon="📣"
              tone="blue"
              href={usersUrl(sp, { filter: "ads", page: undefined })}
            />
            <Stat
              label="Paying customers"
              value={stats.paying_customers.toLocaleString("en-IN")}
              hint={`${stats.new_customers} first-time · ${stats.repeat_customers} bought again`}
              icon="💳"
              tone="green"
              href={usersUrl(sp, { filter: "paying", from: undefined, to: undefined, page: undefined })}
            />
            <Stat
              label="Sales"
              value={inr(stats.revenue_paise)}
              hint={`${stats.purchases} plan${stats.purchases === 1 ? "" : "s"} sold`}
              icon="₹"
              tone="amber"
              href={`/payments?view=plans${from ? `&from=${from}` : ""}${to ? `&to=${to}` : ""}`}
            />
          </div>
          <div className="mt-3 rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h2 className="font-semibold text-gray-900">
                Subscribers now: <span className="tabular-nums">{stats.active_subscribers}</span>
                <span className="ml-2 text-sm font-normal text-gray-500">of {stats.all_users.toLocaleString("en-IN")} users</span>
              </h2>
              <Link href={usersUrl(sp, { filter: "premium", from: undefined, to: undefined, page: undefined })} className="text-sm font-medium text-brand-700 hover:underline">
                See subscribers
              </Link>
            </div>
            <div className="mt-3 overflow-x-auto">
              <table className="w-full min-w-[480px] text-sm">
                <thead>
                  <tr className="text-left text-xs uppercase tracking-wide text-gray-500">
                    <th className="py-1.5 pr-3 font-semibold">Plan</th>
                    <th className="py-1.5 pr-3 text-right font-semibold">Active now</th>
                    <th className="py-1.5 pr-3 text-right font-semibold">Sold ({range})</th>
                    <th className="py-1.5 text-right font-semibold">Revenue ({range})</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {stats.by_plan.map((p) => (
                    <tr key={p.plan}>
                      <td className="py-1.5 pr-3">
                        {p.plan} <span className="text-xs text-gray-400">₹{p.price_inr}</span>
                      </td>
                      <td className="py-1.5 pr-3 text-right tabular-nums">{p.active_now}</td>
                      <td className="py-1.5 pr-3 text-right tabular-nums">{p.sold}</td>
                      <td className="py-1.5 text-right tabular-nums">{inr(p.revenue_paise)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      )}

      {requests.length > 0 && (
        <section className="mb-8">
          <h2 className="mb-2 font-semibold">Plan requests ({requests.length})</h2>
          <p className="mb-3 text-sm text-gray-500">
            Requests sent before UPI payments were added. Grant the plan here or dismiss them; new purchases appear under Payments.
          </p>
          <Table>
            <thead>
              <tr>
                <Th>User</Th>
                <Th>Source</Th>
                <Th>Requested</Th>
                <Th>When</Th>
                <Th className="text-right">Action</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {requests.map((r) => (
                <tr key={r.id} className="bg-amber-50/60">
                  <Td>
                    <p className="font-medium">{r.display_name}</p>
                    <p className="text-xs text-gray-500">{r.email}</p>
                  </Td>
                  <Td><SourceBadge source={r.source} /></Td>
                  <Td><Badge tone="amber">👑 {r.plan_name}</Badge></Td>
                  <Td className="whitespace-nowrap">{formatDate(r.created_at)}</Td>
                  <Td className="text-right">
                    <div className="flex justify-end gap-2">
                      <form action={grantPremium.bind(null, r.user_id, back)}>
                        <input type="hidden" name="plan" value={r.plan_code} />
                        <Button variant="success" type="submit">Grant {r.plan_name}</Button>
                      </form>
                      <form action={dismissPlanRequest.bind(null, r.id, back)}>
                        <Button variant="secondary" type="submit">Dismiss</Button>
                      </form>
                    </div>
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </section>
      )}

      <form className="mb-3 flex flex-wrap items-end gap-3 rounded-xl border border-gray-200 bg-white p-3 shadow-sm">
        <label className="flex min-w-48 flex-1 flex-col gap-1 text-xs font-medium text-gray-600">
          Search
          <Input name="q" defaultValue={q} placeholder="Name, email or user ID" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          Show
          <Select name="filter" defaultValue={filter} className="w-52">
            {filters.map((f) => (
              <option key={f.value} value={f.value}>{f.label}</option>
            ))}
          </Select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          Sort by
          <Select name="sort" defaultValue={sort} className="w-44">
            {sorts.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </Select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          Joined from
          <Input type="date" name="from" defaultValue={from ?? ""} className="w-40" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          to
          <Input type="date" name="to" defaultValue={to ?? ""} className="w-40" />
        </label>
        <div className="flex items-center gap-3">
          <Button type="submit">Apply</Button>
          <Link href="/users" className="text-sm font-medium text-gray-500 hover:text-gray-800">
            Reset
          </Link>
        </div>
      </form>

      <p className="mb-3 text-sm text-gray-500">
        <b className="text-gray-800">{total.toLocaleString("en-IN")}</b> user{total === 1 ? "" : "s"}
        {filtered || from || to ? " match" : ""}
        {total > PAGE_SIZE && ` · page ${page} of ${pages}`}
      </p>

      {users.length === 0 ? (
        <Empty>No users found.</Empty>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>User</Th>
              <Th>Source</Th>
              <Th>Plan</Th>
              <Th>Paid</Th>
              <Th>Ads content</Th>
              <Th>Joined</Th>
              <Th>Grant premium</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {users.map((u) => (
              <tr key={u.id}>
                <Td>
                  <p className="font-medium">{u.display_name}</p>
                  <p className="text-xs text-gray-500">{u.is_guest ? "Guest" : u.email}</p>
                </Td>
                <Td>
                  <SourceBadge source={u.source} />
                  {u.campaign && <p className="mt-1 text-xs text-gray-500">{u.campaign}</p>}
                </Td>
                <Td>
                  {u.plan_name ? (
                    <>
                      <Badge tone="amber">👑 {u.plan_name}</Badge>
                      <p className="mt-1 text-xs text-gray-500">until {formatDate(u.plan_ends_at)}</p>
                    </>
                  ) : (
                    <span className="text-gray-400">Free</span>
                  )}
                </Td>
                <Td className="whitespace-nowrap">
                  {u.purchases ? (
                    <>
                      <p className="font-semibold tabular-nums">{inr(u.spent_paise ?? 0)}</p>
                      <p className="text-xs text-gray-500">
                        {u.purchases} purchase{u.purchases === 1 ? "" : "s"}
                        {u.last_purchase_at ? ` · last ${formatDate(u.last_purchase_at)}` : ""}
                      </p>
                    </>
                  ) : (
                    <span className="text-xs text-gray-400">—</span>
                  )}
                </Td>
                <Td>
                  {u.ads_content ? (
                    <Badge tone="purple">Yes · Meta ad install</Badge>
                  ) : (
                    <span className="text-xs text-gray-500">
                      No{u.source === "ads" ? " (not a verified ad install, or Gujarat / Maharashtra)" : ""}
                    </span>
                  )}
                </Td>
                <Td className="whitespace-nowrap">{formatDate(u.created_at)}</Td>
                <Td>
                  {u.is_guest ? (
                    <span className="text-xs text-gray-400">Must log in first</span>
                  ) : (
                    <form action={grantPremium.bind(null, u.id, back)} className="flex gap-2">
                      <Select name="plan" aria-label="Plan" defaultValue="gold" className="min-w-32">
                        {(plans ?? []).map((p) => (
                          <option key={p.code} value={p.code}>{p.name}</option>
                        ))}
                      </Select>
                      <Button variant="secondary" type="submit">Grant</Button>
                    </form>
                  )}
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}

      {pages > 1 && (
        <nav className="mt-4 flex items-center justify-between text-sm" aria-label="Pages">
          {page > 1 ? (
            <Link href={usersUrl(sp, { page: String(page - 1) })} className="font-medium text-brand-700 hover:underline">
              ← Previous
            </Link>
          ) : (
            <span />
          )}
          <span className="text-gray-500">
            Page {page} of {pages}
          </span>
          {page < pages ? (
            <Link href={usersUrl(sp, { page: String(page + 1) })} className="font-medium text-brand-700 hover:underline">
              Next →
            </Link>
          ) : (
            <span />
          )}
        </nav>
      )}
    </>
  );
}
