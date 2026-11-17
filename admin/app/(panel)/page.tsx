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

  // Same numbers as before. A tile links only where a page has the exact
  // matching filter.
  const tiles: { label: string; value: number | undefined; href?: string }[] = [
    { label: "Installs from ads", value: s.installs_ads },
    { label: "Organic installs", value: s.installs_organic },
    { label: "App users", value: s.users, href: role === "owner" ? "/users" : undefined },
    { label: "Logged in", value: s.registered },
    { label: "Premium users", value: s.premium, href: role === "owner" ? "/users?filter=premium" : undefined },
    { label: "Channels", value: s.channels, href: "/channels" },
    { label: "Published posts", value: s.posts_published, href: "/posts?status=published" },
  ];

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

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {tiles.map((t) => (
          <Stat key={t.label} label={t.label} value={Number(t.value ?? 0).toLocaleString("en-IN")} href={t.href} />
        ))}
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
