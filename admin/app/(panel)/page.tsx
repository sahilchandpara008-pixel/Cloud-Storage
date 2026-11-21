import Link from "next/link";
import { DatePresets } from "@/components/date-range";
import {
  Button,
  Empty,
  Flash,
  Input,
  LinkButton,
  Notice,
  PageHeader,
  SectionTitle,
  SourceBadge,
  Stat,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { dayEnd, dayStart, isDate, rangeLabel } from "@/lib/dates";

type Stats = Record<string, number>;
type Day = {
  day: string;
  installs_ads: number;
  installs_organic: number;
  purchases: number;
  revenue_paise: number | null;
};
type Analytics = Record<string, number | null> & { daily?: Day[] };
type ReportRow = {
  source: string;
  campaign: string;
  installs: number;
  registrations: number;
  buyers: number;
};

const n = (v: number | null | undefined) => Number(v ?? 0);
const fmt = (v: number | null | undefined) => n(v).toLocaleString("en-IN");
const pct = (part: number | null | undefined, whole: number | null | undefined) =>
  n(whole) > 0 ? `${Math.round((n(part) / n(whole)) * 100)}%` : "—";
const inr = (paise: number | null | undefined) =>
  `₹${(n(paise) / 100).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;

function dashUrl(from?: string, to?: string) {
  const q = new URLSearchParams();
  if (from) q.set("from", from);
  if (to) q.set("to", to);
  const s = q.toString();
  return s ? `/?${s}` : "/";
}

// Installs per day (ads vs organic); a green dot marks days with a sale.
function DailyChart({ days, showMoney }: { days: Day[]; showMoney: boolean }) {
  const max = Math.max(1, ...days.map((d) => n(d.installs_ads) + n(d.installs_organic)));
  return (
    <div>
      <div className="flex h-40 items-end gap-[3px] pt-2" role="img" aria-label="Installs per day, ads and organic">
        {days.map((d) => {
          const ads = n(d.installs_ads);
          const org = n(d.installs_organic);
          const label = new Date(`${d.day}T12:00:00+05:30`).toLocaleDateString("en-IN", {
            day: "numeric",
            month: "short",
          });
          return (
            <div
              key={d.day}
              className="relative flex h-full min-w-0 flex-1 flex-col justify-end"
              title={`${label}: ${ads} from ads, ${org} organic${d.purchases ? `, ${d.purchases} sale(s)` : ""}${
                showMoney && d.revenue_paise ? ` (${inr(d.revenue_paise)})` : ""
              }`}
            >
              <div className="w-full rounded-t-sm bg-[#6b7cff]" style={{ height: `${(org / max) * 100}%` }} />
              <div className="w-full bg-brand-500" style={{ height: `${(ads / max) * 100}%` }} />
              {d.purchases > 0 && (
                <span className="absolute -top-2 left-1/2 h-1.5 w-1.5 -translate-x-1/2 rounded-full bg-green-600" />
              )}
            </div>
          );
        })}
      </div>
      <div className="mt-1 flex justify-between text-[10px] text-gray-400">
        <span>{days[0]?.day}</span>
        <span>{days[days.length - 1]?.day}</span>
      </div>
      <div className="mt-2 flex flex-wrap gap-4 text-xs text-gray-500">
        <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-brand-500" /> From ads</span>
        <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-[#6b7cff]" /> Organic</span>
        <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-green-600" /> Day with a sale</span>
        <span>Hover a bar for numbers</span>
      </div>
    </div>
  );
}

type Rates = Record<string, number>;

// Success / failure split for All, Ads and Organic (payments or notifications).
function RateCard({
  title,
  href,
  groups,
  base,
  good,
  bad,
  rest,
  labels,
  baseLabel,
}: {
  title: string;
  href?: string;
  groups: Record<string, Rates>;
  base: string;
  good: string;
  bad: string;
  rest: string;
  labels: [string, string, string];
  baseLabel: string;
}) {
  const share = (v: number, t: number) => (t > 0 ? Math.round((v / t) * 100) : 0);
  return (
    <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
      <div className="mb-3 flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-semibold text-gray-900">{title}</h2>
        {href && (
          <Link href={href} className="text-xs font-medium text-brand-700 hover:underline">
            Details →
          </Link>
        )}
      </div>
      <div className="space-y-3">
        {(["all", "ads", "organic"] as const).map((k) => {
          const g = groups[k] ?? {};
          const t = n(g[base]);
          const ok = n(g[good]);
          const no = n(g[bad]);
          const wait = n(g[rest]);
          return (
            <div key={k}>
              <div className="mb-1 flex items-baseline justify-between text-xs">
                <span className="font-medium text-gray-700">
                  {k === "all" ? "All" : k === "ads" ? "Ads" : "Organic"}{" "}
                  <span className="font-normal text-gray-400">
                    · {fmt(t)} {baseLabel}
                  </span>
                </span>
                <span className="tabular-nums">
                  <b className="text-green-700">{share(ok, t)}%</b>{" "}
                  <span className="text-gray-400">{labels[0].toLowerCase()}</span>
                  {" · "}
                  <b className="text-red-700">{share(no, t)}%</b>{" "}
                  <span className="text-gray-400">{labels[1].toLowerCase()}</span>
                </span>
              </div>
              <div
                className="flex h-2 overflow-hidden rounded-full bg-gray-100"
                role="img"
                aria-label={`${labels[0]} ${share(ok, t)}%, ${labels[1]} ${share(no, t)}%, ${labels[2]} ${share(wait, t)}%`}
              >
                <div className="h-full bg-green-600" style={{ width: `${share(ok, t)}%` }} />
                <div className="h-full bg-red-500" style={{ width: `${share(no, t)}%` }} />
              </div>
              <p className="mt-1 text-[11px] text-gray-400 tabular-nums">
                {labels[0]} {fmt(ok)} · {labels[1]} {fmt(no)} · {labels[2]} {fmt(wait)}
              </p>
            </div>
          );
        })}
      </div>
    </section>
  );
}

export default async function Dashboard({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; from?: string; to?: string }>;
}) {
  const sp = await searchParams;
  const from = isDate(sp.from) ? sp.from : undefined;
  const to = isDate(sp.to) ? sp.to : undefined;
  const { supabase, role } = await requireAdmin();
  const owner = role === "owner";

  const range: Record<string, string> = {};
  if (dayStart(from)) range.p_from = dayStart(from)!;
  if (dayEnd(to)) range.p_to = dayEnd(to)!;

  const [{ data }, { data: an }, { data: rows }, { data: fun }, { data: nt }] = await Promise.all([
    supabase.rpc("admin_dashboard"),
    supabase.rpc("admin_analytics", { p_from: dayStart(from), p_to: dayEnd(to) }),
    owner ? supabase.rpc("attribution_report", range) : Promise.resolve({ data: [] }),
    owner ? supabase.rpc("admin_payment_funnel", range) : Promise.resolve({ data: null }),
    owner ? supabase.rpc("admin_notif_stats", range) : Promise.resolve({ data: null }),
  ]);
  const payGroups = ((fun as { groups?: Record<string, Rates> } | null)?.groups ?? {}) as Record<string, Rates>;
  const notifGroups = (nt ?? {}) as Record<string, Rates>;
  const s = (data ?? {}) as Stats;
  const a = (an ?? {}) as Analytics;
  const report = (rows ?? []) as ReportRow[];
  const days = (a.daily ?? []) as Day[];
  const label = rangeLabel(from, to);

  const installs = n(a.installs);
  const adsShare = installs > 0 ? (n(a.installs_ads) / installs) * 100 : 0;
  const rangeQuery = `${from ? `&from=${from}` : ""}${to ? `&to=${to}` : ""}`;

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle="Installs, users, subscriptions and content for the dates you pick."
        action={<LinkButton href="/posts/new">+ Upload content</LinkButton>}
      />
      <Flash error={sp.error === "owner_only" ? "That page is only available to the owner." : undefined} />

      {owner && s.pending_channels > 0 && (
        <div className="mb-5">
          <Notice href="/channels?view=requests&status=pending">
            {s.pending_channels} new channel request{s.pending_channels === 1 ? "" : "s"} to review
          </Notice>
        </div>
      )}

      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <DatePresets from={from} to={to} href={dashUrl} />
          <p className="mt-2 text-xs text-gray-500">
            Showing <b className="text-gray-800">{label}</b>
          </p>
        </div>
        <form className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
            From
            <Input type="date" name="from" defaultValue={from ?? ""} className="w-40" />
          </label>
          <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
            To
            <Input type="date" name="to" defaultValue={to ?? ""} className="w-40" />
          </label>
          <Button type="submit">Apply</Button>
        </form>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
          <div className="flex items-baseline justify-between">
            <h2 className="text-sm font-semibold text-gray-900">Installs</h2>
            <span className="text-2xl font-semibold tabular-nums tracking-tight">{fmt(installs)}</span>
          </div>
          <div
            className="mt-4 flex h-2.5 overflow-hidden rounded-full bg-blue-100"
            role="img"
            aria-label={`${Math.round(adsShare)}% of installs came from ads`}
          >
            <div className="h-full bg-brand-500" style={{ width: `${adsShare}%` }} />
          </div>
          <dl className="mt-3 grid grid-cols-2 gap-2 text-sm">
            <div>
              <dt className="flex items-center gap-1.5 text-xs text-gray-500">
                <span className="h-2 w-2 rounded-full bg-brand-500" /> From ads
              </dt>
              <dd className="font-semibold tabular-nums">
                {fmt(a.installs_ads)} <span className="text-xs font-normal text-gray-400">{pct(a.installs_ads, installs)}</span>
              </dd>
            </div>
            <div>
              <dt className="flex items-center gap-1.5 text-xs text-gray-500">
                <span className="h-2 w-2 rounded-full bg-[#6b7cff]" /> Organic
              </dt>
              <dd className="font-semibold tabular-nums">
                {fmt(a.installs_organic)}{" "}
                <span className="text-xs font-normal text-gray-400">{pct(a.installs_organic, installs)}</span>
              </dd>
            </div>
          </dl>
          <p className="mt-3 border-t border-gray-100 pt-2 text-xs text-gray-500">
            {fmt(a.installs_ads_content)} ads installs get ads content · {fmt(a.installs_ads_geo)} blocked (Gujarat /
            Maharashtra)
          </p>
        </section>

        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:col-span-2">
          <Stat
            label="New users"
            value={fmt(a.users)}
            icon="♙"
            tone="blue"
            hint={`${fmt(a.registered)} logged in · ${fmt(a.guests)} guests`}
            href={owner ? `/users?filter=all${rangeQuery}` : undefined}
          />
          <Stat
            label="New subscribers"
            value={fmt(a.new_subscribers)}
            icon="★"
            tone="amber"
            hint={`${fmt(a.purchases)} plans sold · ${fmt(a.active_subscribers)} active now`}
            href={owner ? "/users?filter=premium" : undefined}
          />
          {owner ? (
            <Stat
              label="Sales"
              value={inr(a.revenue_paise)}
              icon="₹"
              tone="green"
              hint={`${fmt(a.purchases)} payments`}
              href={`/payments?view=plans${rangeQuery}`}
            />
          ) : (
            <Stat label="Plans sold" value={fmt(a.purchases)} icon="₹" tone="green" />
          )}
          <Stat
            label="Channel requests"
            value={fmt(a.channels_requested)}
            icon="▦"
            tone="brand"
            hint={`${fmt(a.channels_approved)} approved · ${fmt(a.channels_rejected)} rejected · ${fmt(a.channels_pending)} waiting`}
            href={owner ? `/channels?view=requests${rangeQuery}` : undefined}
          />
          <Stat label="Posts published" value={fmt(a.posts_published)} icon="▶" tone="purple" href="/posts?status=published" />
          <Stat label="Video views" value={fmt(a.video_views)} icon="◉" tone="gray" hint={`${fmt(a.preview_views)} preview views`} />
        </div>
      </div>

      {owner && (
        <div className="mt-6 grid gap-4 lg:grid-cols-2">
          <RateCard
            title="Payment success"
            href={`/payments?view=funnel${rangeQuery}`}
            groups={payGroups}
            base="tried"
            good="paid"
            bad="not_paid"
            rest="waiting"
            labels={["Paid", "Didn't pay", "Waiting"]}
            baseLabel="tried to pay"
          />
          <RateCard
            title="Notifications"
            groups={notifGroups}
            base="installs"
            good="allowed"
            bad="denied"
            rest="unknown"
            labels={["Allowed", "Not allowed", "Not asked yet"]}
            baseLabel="installs"
          />
        </div>
      )}

      <section className="mt-6 rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
        <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="text-sm font-semibold text-gray-900">Installs per day</h2>
          <span className="text-xs text-gray-400">{from || to ? label : "Last 30 days"} · up to 120 days shown</span>
        </div>
        {days.length === 0 ? <Empty>No days in this range.</Empty> : <DailyChart days={days} showMoney={owner} />}
      </section>

      {owner && (
        <section className="mt-8">
          <SectionTitle action={<span className="text-xs text-gray-400">{label}</span>}>
            Installs by source and campaign
          </SectionTitle>
          {report.length === 0 ? (
            <Empty>No installs in this range.</Empty>
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>Source</Th>
                  <Th>Campaign</Th>
                  <Th className="text-right">Installs</Th>
                  <Th className="text-right">Logged in</Th>
                  <Th className="text-right">Buyers</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {report.map((r) => (
                  <tr key={`${r.source}-${r.campaign}`}>
                    <Td>
                      {r.source === "meta" || r.source === "ads" ? (
                        <SourceBadge source="ads" />
                      ) : (
                        <span className="capitalize">{r.source}</span>
                      )}
                    </Td>
                    <Td>{r.campaign || "—"}</Td>
                    <Td className="text-right tabular-nums">{r.installs}</Td>
                    <Td className="text-right tabular-nums">{r.registrations}</Td>
                    <Td className="text-right tabular-nums">{r.buyers}</Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
          <p className="mt-2 text-xs text-gray-400">
            All time: {fmt(s.users)} users, {fmt(s.premium)} with an active plan, {fmt(s.channels)} channels.{" "}
            <Link href="/users" className="underline">
              Open Users
            </Link>
          </p>
        </section>
      )}
    </>
  );
}
