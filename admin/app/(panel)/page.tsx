import { Empty, Flash, LinkButton, Notice, PageHeader, SectionTitle, SourceBadge, Stat, Table, Td, Th } from "@/components/ui";
import { requireAdmin } from "@/lib/auth";

type Stats = Record<string, number>;
type ReportRow = {
  source: string;
  campaign: string;
  installs: number;
  registrations: number;
  buyers: number;
};

export default async function Dashboard({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const { supabase, role } = await requireAdmin();
  const { data } = await supabase.rpc("admin_dashboard");
  const s = (data ?? {}) as Stats;

  let report: ReportRow[] = [];
  if (role === "owner") {
    const { data: rows } = await supabase.rpc("attribution_report");
    report = (rows ?? []) as ReportRow[];
  }

  // Same numbers as before; the rates are worked out from them. A tile
  // links only where a page has the exact matching filter.
  const n = (v: number | undefined) => Number(v ?? 0);
  const fmt = (v: number | undefined) => n(v).toLocaleString("en-IN");
  const pct = (part: number | undefined, whole: number | undefined) =>
    n(whole) > 0 ? `${Math.round((n(part) / n(whole)) * 100)}%` : "—";
  const installs = n(s.installs_ads) + n(s.installs_organic);
  const adsShare = installs > 0 ? (n(s.installs_ads) / installs) * 100 : 0;
  const owner = role === "owner";

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle="Overview of installs, users and content. All counts are all-time totals."
        action={<LinkButton href="/posts/new">+ Upload content</LinkButton>}
      />
      <Flash error={error === "owner_only" ? "That page is only available to the owner." : undefined} />

      {role === "owner" && (s.pending_channels > 0 || s.pending_approvals > 0) && (
        <div className="mb-6 space-y-3">
          {s.pending_channels > 0 && (
            <Notice href="/channels">
              {s.pending_channels} new channel request{s.pending_channels === 1 ? "" : "s"} to review
            </Notice>
          )}
          {s.pending_approvals > 0 && (
            <Notice href="/approvals" tone="red">
              {s.pending_approvals} organic buyer{s.pending_approvals === 1 ? "" : "s"} waiting for approval
            </Notice>
          )}
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm lg:col-span-1">
          <div className="flex items-baseline justify-between">
            <h2 className="text-sm font-semibold text-gray-900">Installs</h2>
            <span className="text-2xl font-semibold tabular-nums tracking-tight">{installs.toLocaleString("en-IN")}</span>
          </div>
          <div
            className="mt-4 flex h-2.5 overflow-hidden rounded-full bg-blue-100"
            role="img"
            aria-label={`${Math.round(adsShare)}% of installs came from ads`}
          >
            <div className="h-full bg-purple-500" style={{ width: `${adsShare}%` }} />
          </div>
          <dl className="mt-3 grid grid-cols-2 gap-2 text-sm">
            <div>
              <dt className="flex items-center gap-1.5 text-xs text-gray-500">
                <span className="h-2 w-2 rounded-full bg-purple-500" /> From ads
              </dt>
              <dd className="font-semibold tabular-nums">
                {fmt(s.installs_ads)} <span className="text-xs font-normal text-gray-400">{pct(s.installs_ads, installs)}</span>
              </dd>
            </div>
            <div>
              <dt className="flex items-center gap-1.5 text-xs text-gray-500">
                <span className="h-2 w-2 rounded-full bg-blue-200" /> Organic
              </dt>
              <dd className="font-semibold tabular-nums">
                {fmt(s.installs_organic)}{" "}
                <span className="text-xs font-normal text-gray-400">{pct(s.installs_organic, installs)}</span>
              </dd>
            </div>
          </dl>
        </section>

        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:col-span-2">
          <Stat label="App users" value={fmt(s.users)} icon="♙" tone="blue" href={owner ? "/users" : undefined} />
          <Stat label="Logged in" value={fmt(s.registered)} icon="✓" tone="green" hint={`${pct(s.registered, s.users)} of users`} />
          <Stat
            label="Premium users"
            value={fmt(s.premium)}
            icon="★"
            tone="amber"
            hint={`${pct(s.premium, s.users)} of users`}
            href={owner ? "/users?filter=premium" : undefined}
          />
          <Stat label="Channels" value={fmt(s.channels)} icon="▦" tone="brand" href="/channels" />
          <Stat label="Published posts" value={fmt(s.posts_published)} icon="▶" tone="purple" href="/posts?status=published" />
          <Stat label="Upload content" value="+" icon="⇪" tone="gray" hint="Single or bulk" href="/posts/new" />
        </div>
      </div>

      {role === "owner" && (
        <section className="mt-8">
          <SectionTitle action={<span className="text-xs text-gray-400">All time</span>}>
            Installs by source and campaign
          </SectionTitle>
          {report.length === 0 ? (
            <Empty>No installs yet. Campaign performance will appear here.</Empty>
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
                      {r.source === "meta" || r.source === "ads" ? <SourceBadge source="ads" /> : <span className="capitalize">{r.source}</span>}
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
        </section>
      )}
    </>
  );
}
