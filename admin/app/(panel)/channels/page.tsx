import Link from "next/link";
import { DatePresets } from "@/components/date-range";
import {
  AudienceBadge,
  Badge,
  Button,
  Empty,
  Flash,
  Input,
  LinkButton,
  PageHeader,
  SegmentTabs,
  Select,
  StatusBadge,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { requireAdmin } from "@/lib/auth";
import { dayEnd, dayStart, isDate, rangeLabel } from "@/lib/dates";
import { AUDIENCES, formatDate } from "@/lib/format";
import { reviewChannel } from "./actions";

type Creator = {
  channel_id: string;
  email: string | null;
  display_name: string | null;
  source: "ads" | "organic" | null;
};

type Row = {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  icon_url: string | null;
  audience: string;
  status: string;
  members_count: number;
  review_status: string;
  created_by: string | null;
  created_at: string;
  reviewed_at: string | null;
  channel_folders: { count: number }[];
  posts: { count: number }[];
};

type SP = {
  ok?: string;
  error?: string;
  view?: string;
  q?: string;
  audience?: string;
  status?: string;
  by?: string;
  sort?: string;
  from?: string;
  to?: string;
  date?: string;
};

const channelSorts = [
  { value: "newest", label: "Newest first" },
  { value: "oldest", label: "Oldest first" },
  { value: "name", label: "Name A–Z" },
  { value: "members", label: "Most members" },
  { value: "posts", label: "Most posts" },
];

const requestStatuses = [
  { value: "pending", label: "Waiting" },
  { value: "approved", label: "Approved" },
  { value: "rejected", label: "Rejected" },
  { value: "all", label: "All requests" },
];

function url(sp: SP, patch: Partial<SP>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...sp, ok: undefined, error: undefined, ...patch })) {
    if (v) q.set(k, v);
  }
  const s = q.toString();
  return s ? `/channels?${s}` : "/channels";
}

const label = "flex flex-col gap-1 text-xs font-medium text-gray-600";

export default async function ChannelsPage({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams;
  const { supabase, role } = await requireAdmin();
  const owner = role === "owner";
  const view = owner && sp.view === "requests" ? "requests" : "channels";
  const from = isDate(sp.from) ? sp.from : undefined;
  const to = isDate(sp.to) ? sp.to : undefined;
  const q = (sp.q ?? "").trim();

  // Requests = channels made by app users. Dates = when requested, or when decided.
  const reqStatus = requestStatuses.some((r) => r.value === sp.status) ? sp.status! : "all";
  const dateField = view === "requests" && sp.date === "decided" ? "reviewed_at" : "created_at";

  let query = supabase
    .from("channels")
    .select(
      "id, name, description, category, icon_url, audience, status, members_count, review_status, created_by, created_at, reviewed_at, channel_folders(count), posts(count)",
    )
    .limit(1000);
  if (q) query = query.ilike("name", `%${q.replace(/[%_]/g, "")}%`);
  if (dayStart(from)) query = query.gte(dateField, dayStart(from)!);
  if (dayEnd(to)) query = query.lt(dateField, dayEnd(to)!);

  if (view === "requests") {
    query = query.not("created_by", "is", null);
    if (reqStatus !== "all") query = query.eq("review_status", reqStatus);
    query = query.order(dateField, { ascending: false, nullsFirst: false });
  } else {
    query = query.neq("review_status", "pending");
    if (AUDIENCES.some((a) => a.value === sp.audience)) query = query.eq("audience", sp.audience!);
    if (sp.status === "rejected") query = query.eq("review_status", "rejected");
    else if (sp.status === "published" || sp.status === "hidden" || sp.status === "draft")
      query = query.eq("status", sp.status).neq("review_status", "rejected");
    if (sp.by === "admin") query = query.is("created_by", null);
    if (sp.by === "users") query = query.not("created_by", "is", null);
    query = query.order("created_at", { ascending: sp.sort === "oldest" });
  }

  const [{ data, error }, { data: creatorRows }, pendingRes] = await Promise.all([
    query,
    supabase.rpc("admin_channel_creators"),
    owner
      ? supabase.from("channels").select("id", { count: "exact", head: true }).eq("review_status", "pending")
      : Promise.resolve({ count: 0 }),
  ]);
  let rows = (data ?? []) as Row[];
  const creators = new Map(((creatorRows ?? []) as Creator[]).map((c) => [c.channel_id, c]));
  // Channels an admin made are not requests.
  if (view === "requests") rows = rows.filter((r) => creators.get(r.id)?.email || creators.get(r.id)?.display_name);
  if (view === "channels") {
    if (sp.sort === "name") rows.sort((a, b) => a.name.localeCompare(b.name));
    if (sp.sort === "members") rows.sort((a, b) => b.members_count - a.members_count);
    if (sp.sort === "posts") rows.sort((a, b) => (b.posts[0]?.count ?? 0) - (a.posts[0]?.count ?? 0));
  }
  const pendingCount = pendingRes.count ?? 0;
  const range = rangeLabel(from, to);
  const counts = {
    approved: rows.filter((r) => r.review_status === "approved").length,
    rejected: rows.filter((r) => r.review_status === "rejected").length,
    pending: rows.filter((r) => r.review_status === "pending").length,
  };

  return (
    <>
      <PageHeader
        title="Channels"
        subtitle="Channels hold folders and posts. Their posts also appear in Explore."
        action={<LinkButton href="/channels/new">New channel</LinkButton>}
      />
      <Flash ok={sp.ok} error={sp.error ?? error?.message} />

      {owner && (
        <SegmentTabs
          className="mb-4"
          items={[
            { href: "/channels", label: "Channels", active: view === "channels" },
            {
              href: "/channels?view=requests&status=pending",
              label: `Requests${pendingCount ? ` (${pendingCount} waiting)` : ""}`,
              active: view === "requests",
            },
          ]}
        />
      )}

      <DatePresets className="mb-3" from={from} to={to} href={(f, t) => url(sp, { from: f, to: t })} />

      <form className="mb-3 flex flex-wrap items-end gap-3 rounded-xl border border-gray-200 bg-white p-3 shadow-sm">
        {view === "requests" && <input type="hidden" name="view" value="requests" />}
        <label className={`${label} min-w-44 flex-1`}>
          Search
          <Input name="q" defaultValue={q} placeholder="Channel name" />
        </label>
        {view === "channels" ? (
          <>
            <label className={label}>
              Who sees it
              <Select name="audience" defaultValue={sp.audience ?? ""} className="w-44">
                <option value="">Any audience</option>
                {AUDIENCES.map((a) => (
                  <option key={a.value} value={a.value}>{a.label}</option>
                ))}
              </Select>
            </label>
            <label className={label}>
              Status
              <Select name="status" defaultValue={sp.status ?? ""} className="w-36">
                <option value="">Any</option>
                <option value="published">Published</option>
                <option value="hidden">Hidden</option>
                <option value="draft">Draft</option>
                <option value="rejected">Rejected</option>
              </Select>
            </label>
            <label className={label}>
              Created by
              <Select name="by" defaultValue={sp.by ?? ""} className="w-36">
                <option value="">Anyone</option>
                <option value="admin">Admin panel</option>
                <option value="users">App users</option>
              </Select>
            </label>
            <label className={label}>
              Sort by
              <Select name="sort" defaultValue={sp.sort ?? "newest"} className="w-36">
                {channelSorts.map((s) => (
                  <option key={s.value} value={s.value}>{s.label}</option>
                ))}
              </Select>
            </label>
          </>
        ) : (
          <>
            <label className={label}>
              Status
              <Select name="status" defaultValue={reqStatus} className="w-36">
                {requestStatuses.map((s) => (
                  <option key={s.value} value={s.value}>{s.label}</option>
                ))}
              </Select>
            </label>
            <label className={label}>
              Dates are
              <Select name="date" defaultValue={sp.date === "decided" ? "decided" : "requested"} className="w-48">
                <option value="requested">When requested</option>
                <option value="decided">When approved / rejected</option>
              </Select>
            </label>
          </>
        )}
        <label className={label}>
          From
          <Input type="date" name="from" defaultValue={from ?? ""} className="w-40" />
        </label>
        <label className={label}>
          To
          <Input type="date" name="to" defaultValue={to ?? ""} className="w-40" />
        </label>
        <div className="flex items-center gap-3">
          <Button type="submit">Apply</Button>
          <Link
            href={view === "requests" ? "/channels?view=requests" : "/channels"}
            className="text-sm font-medium text-gray-500 hover:text-gray-800"
          >
            Reset
          </Link>
        </div>
      </form>

      <p className="mb-3 text-sm text-gray-500">
        <b className="text-gray-800">{rows.length}</b> {view === "requests" ? "request" : "channel"}
        {rows.length === 1 ? "" : "s"} · {range}
        {view === "requests" && reqStatus === "all" && (
          <> · {counts.approved} approved · {counts.rejected} rejected · {counts.pending} waiting</>
        )}
      </p>

      {view === "requests" ? (
        rows.length === 0 ? (
          <Empty icon="✓">No channel requests here.</Empty>
        ) : (
          <div className="space-y-3">
            {rows.map((r) => {
              const cr = creators.get(r.id);
              const pending = r.review_status === "pending";
              return (
                <div
                  key={r.id}
                  className={`flex flex-wrap items-center gap-4 rounded-xl border p-4 ${
                    pending ? "border-amber-200 bg-amber-50/60" : "border-gray-200 bg-white"
                  }`}
                >
                  {r.icon_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={r.icon_url} alt="" loading="lazy" decoding="async" className="h-12 w-12 rounded-full object-cover" />
                  ) : (
                    <div className="h-12 w-12 rounded-full bg-gray-200" />
                  )}
                  <div className="min-w-[200px] flex-1">
                    <p className="font-medium">
                      {pending ? r.name : <Link href={`/channels/${r.id}`} className="hover:text-brand-700">{r.name}</Link>}
                    </p>
                    {r.description && <p className="text-sm text-gray-600">{r.description}</p>}
                    <p className="mt-1 text-xs text-gray-500">
                      by {cr?.display_name ?? "—"} ({cr?.email ?? "no email"}) ·{" "}
                      {cr?.source === "ads" ? "ads user" : "organic user"} · requested {formatDate(r.created_at)}
                      {r.reviewed_at && !pending && <> · decided {formatDate(r.reviewed_at)}</>}
                    </p>
                  </div>
                  {pending ? (
                    <>
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
                    </>
                  ) : r.review_status === "approved" ? (
                    <div className="flex items-center gap-2">
                      <Badge tone="green">Approved</Badge>
                      <AudienceBadge audience={r.audience} />
                    </div>
                  ) : (
                    <Badge tone="red">Rejected</Badge>
                  )}
                </div>
              );
            })}
          </div>
        )
      ) : rows.length === 0 ? (
        <Empty>No channels match. Change the filters or create a channel.</Empty>
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
              <Th>Created</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map((c) => {
              const cr = creators.get(c.id);
              return (
                <tr key={c.id} className="hover:bg-gray-50">
                  <Td>
                    <Link href={`/channels/${c.id}`} className="font-medium text-gray-900 hover:text-brand-700">
                      {c.name}
                    </Link>
                    {c.category && <p className="text-xs text-gray-500">{c.category}</p>}
                  </Td>
                  <Td>
                    {!cr?.email && !cr?.display_name ? (
                      <span className="text-xs text-gray-500">Admin panel</span>
                    ) : (
                      <>
                        <p className="text-sm">{cr.email ?? "Guest"}</p>
                        <p className="text-xs text-gray-500">
                          {cr.display_name}
                          {cr.source && <> · {cr.source === "ads" ? "Ads" : "Organic"}</>}
                        </p>
                      </>
                    )}
                  </Td>
                  <Td><AudienceBadge audience={c.audience} /></Td>
                  <Td>
                    {c.review_status === "rejected" ? <Badge tone="red">Rejected</Badge> : <StatusBadge status={c.status} />}
                  </Td>
                  <Td className="text-right tabular-nums">{c.members_count}</Td>
                  <Td className="text-right tabular-nums">{c.channel_folders[0]?.count ?? 0}</Td>
                  <Td className="text-right tabular-nums">{c.posts[0]?.count ?? 0}</Td>
                  <Td className="whitespace-nowrap text-xs text-gray-600">{formatDate(c.created_at)}</Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </>
  );
}
