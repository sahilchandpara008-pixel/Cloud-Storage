import Link from "next/link";
import {
  AudienceBadge,
  Badge,
  Button,
  Select,
  Empty,
  Flash,
  LinkButton,
  PageHeader,
  StatusBadge,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { AUDIENCES, formatDate } from "@/lib/format";
import { reviewChannel } from "./actions";

type ChannelRequest = {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  icon_url: string | null;
  creator_email: string | null;
  creator_name: string | null;
  creator_source: "ads" | "organic";
  created_at: string;
};

type Creator = {
  channel_id: string;
  email: string | null;
  display_name: string | null;
  source: "ads" | "organic" | null;
};

type Row = {
  id: string;
  name: string;
  category: string | null;
  audience: string;
  status: string;
  members_count: number;
  review_status: string;
  channel_folders: { count: number }[];
  posts: { count: number }[];
};

export default async function ChannelsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string; audience?: string }>;
}) {
  const { ok, error, audience } = await searchParams;
  const { supabase, role } = await requireAdmin();
  const { data: requestRows } =
    role === "owner" ? await supabase.rpc("admin_channel_requests") : { data: [] };
  const requests = (requestRows ?? []) as ChannelRequest[];

  let query = supabase
    .from("channels")
    .select("id, name, category, audience, status, members_count, review_status, channel_folders(count), posts(count)")
    .neq("review_status", "pending")
    .order("created_at", { ascending: false });
  if (audience) query = query.eq("audience", audience);
  const [{ data }, { data: creatorRows }] = await Promise.all([
    query,
    supabase.rpc("admin_channel_creators"),
  ]);
  const rows = (data ?? []) as Row[];
  const creators = new Map(((creatorRows ?? []) as Creator[]).map((c) => [c.channel_id, c]));

  const filters = [
    { value: "", label: "All" },
    { value: "all", label: "Everyone" },
    { value: "organic", label: "Organic only" },
    { value: "ads", label: "Ads only" },
  ];

  return (
    <>
      <PageHeader
        title="Channels"
        subtitle="Channels hold folders and posts. Their posts also appear in Explore."
        action={<LinkButton href="/channels/new">New channel</LinkButton>}
      />
      <Flash ok={ok} error={error} />

      {requests.length > 0 && (
        <section className="mb-8">
          <h2 className="mb-2 font-semibold">Channel requests ({requests.length})</h2>
          <p className="mb-3 text-sm text-gray-500">
            Channels created by app users. Choose who can see it, then approve, or reject the request.
          </p>
          <div className="space-y-3">
            {requests.map((r) => (
              <div key={r.id} className="flex flex-wrap items-center gap-4 rounded-xl border border-amber-200 bg-amber-50/60 p-4">
                {r.icon_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={r.icon_url} alt="" loading="lazy" decoding="async" className="h-12 w-12 rounded-full object-cover" />
                ) : (
                  <div className="h-12 w-12 rounded-full bg-gray-200" />
                )}
                <div className="min-w-[200px] flex-1">
                  <p className="font-medium">{r.name}</p>
                  {r.description && <p className="text-sm text-gray-600">{r.description}</p>}
                  <p className="mt-1 text-xs text-gray-500">
                    by {r.creator_name} ({r.creator_email ?? "no email"}) ·{" "}
                    {r.creator_source === "ads" ? "ads user" : "organic user"} · {formatDate(r.created_at)}
                  </p>
                </div>
                <form action={reviewChannel.bind(null, r.id, true)} className="flex items-center gap-2">
                  <Select name="audience" defaultValue="all" aria-label={`Audience for ${r.name}`}>
                    {AUDIENCES.map((a) => (
                      <option key={a.value} value={a.value}>{a.label}</option>
                    ))}
                  </Select>
                  <Button variant="success" type="submit">Approve</Button>
                </form>
                <form action={reviewChannel.bind(null, r.id, false)}>
                  <Button variant="danger" type="submit">Reject</Button>
                </form>
              </div>
            ))}
          </div>
        </section>
      )}

      <div className="mb-4 flex flex-wrap gap-2">
        {filters.map((f) => (
          <Link
            key={f.value}
            href={f.value ? `/channels?audience=${f.value}` : "/channels"}
            className={`rounded-full px-3 py-1 text-sm ${
              (audience ?? "") === f.value ? "bg-red-700 text-white" : "bg-white text-gray-700 ring-1 ring-gray-300"
            }`}
          >
            {f.label}
          </Link>
        ))}
      </div>

      {rows.length === 0 ? (
        <Empty>No channels yet. Create your first channel to start posting.</Empty>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>Channel</Th>
              <Th>Created by</Th>
              <Th>Audience</Th>
              <Th>Status</Th>
              <Th className="text-right">Members</Th>
              <Th className="text-right">Folders</Th>
              <Th className="text-right">Posts</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map((c) => (
              <tr key={c.id} className="hover:bg-gray-50">
                <Td>
                  <Link href={`/channels/${c.id}`} className="font-medium text-gray-900 hover:text-red-700">
                    {c.name}
                  </Link>
                  {c.category && <p className="text-xs text-gray-500">{c.category}</p>}
                </Td>
                <Td>
                  {(() => {
                    const cr = creators.get(c.id);
                    if (!cr?.email && !cr?.display_name) {
                      return <span className="text-xs text-gray-500">Admin panel</span>;
                    }
                    return (
                      <>
                        <p className="text-sm">{cr.email ?? "Guest"}</p>
                        <p className="text-xs text-gray-500">
                          {cr.display_name}
                          {cr.source && <> · {cr.source === "ads" ? "Ads" : "Organic"}</>}
                        </p>
                      </>
                    );
                  })()}
                </Td>
                <Td><AudienceBadge audience={c.audience} /></Td>
                <Td>
                  {c.review_status === "rejected" ? <Badge tone="red">Rejected</Badge> : <StatusBadge status={c.status} />}
                </Td>
                <Td className="text-right tabular-nums">{c.members_count}</Td>
                <Td className="text-right tabular-nums">{c.channel_folders[0]?.count ?? 0}</Td>
                <Td className="text-right tabular-nums">{c.posts[0]?.count ?? 0}</Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </>
  );
}
