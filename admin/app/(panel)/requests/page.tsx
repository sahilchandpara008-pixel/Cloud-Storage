import Link from "next/link";
import { DatePresets } from "@/components/date-range";
import { Badge, Button, Card, Empty, Flash, Input, PageHeader, SegmentTabs, Select } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { dayEnd, dayStart, isDate, rangeLabel } from "@/lib/dates";
import { formatDate } from "@/lib/format";
import { closeRequest, deleteRequestedAccount } from "./actions";

type Req = {
  id: string;
  kind: "delete_account" | "content_report";
  email: string;
  name: string | null;
  content_url: string | null;
  details: string | null;
  user_id: string | null;
  status: "open" | "done" | "rejected";
  note: string | null;
  created_at: string;
  closed_at: string | null;
};

export default async function RequestsPage({
  searchParams,
}: {
  searchParams: Promise<{
    ok?: string;
    error?: string;
    status?: string;
    kind?: string;
    q?: string;
    sort?: string;
    from?: string;
    to?: string;
  }>;
}) {
  const sp = await searchParams;
  const status = sp.status === "closed" ? "closed" : sp.status === "all" ? "all" : "open";
  const kind = sp.kind === "delete_account" || sp.kind === "content_report" ? sp.kind : "";
  const from = isDate(sp.from) ? sp.from : undefined;
  const to = isDate(sp.to) ? sp.to : undefined;
  const search = (sp.q ?? "").trim().replace(/[%_,()]/g, "");
  const link = (patch: Record<string, string | undefined>) => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries({ status, kind, q: sp.q, sort: sp.sort, from, to, ...patch })) if (v) p.set(k, v);
    return `/requests?${p.toString()}`;
  };
  const back = link({});
  const { supabase } = await requireOwner();
  let q = supabase
    .from("support_requests")
    .select("*")
    .order("created_at", { ascending: sp.sort === "oldest" })
    .limit(500);
  if (status === "open") q = q.eq("status", "open");
  if (status === "closed") q = q.neq("status", "open");
  if (kind) q = q.eq("kind", kind);
  if (search) q = q.or(`email.ilike.%${search}%,name.ilike.%${search}%,content_url.ilike.%${search}%`);
  if (dayStart(from)) q = q.gte("created_at", dayStart(from)!);
  if (dayEnd(to)) q = q.lt("created_at", dayEnd(to)!);
  const { data, error } = await q;
  const list = (data ?? []) as Req[];

  return (
    <>
      <PageHeader
        title="Requests"
        subtitle="Account deletion requests and content / copyright reports from the website."
      />
      <Flash ok={sp.ok} error={sp.error ?? error?.message} />
      <SegmentTabs
        className="mb-4"
        items={[
          ["open", "Open"],
          ["closed", "Closed"],
          ["all", "All"],
        ].map(([v, l]) => ({ href: link({ status: v }), label: l, active: v === status }))}
      />
      <DatePresets className="mb-3" from={from} to={to} href={(f, t) => link({ from: f, to: t })} />
      <form className="mb-3 flex flex-wrap items-end gap-3 rounded-xl border border-gray-200 bg-white p-3 shadow-sm">
        <input type="hidden" name="status" value={status} />
        <label className="flex min-w-44 flex-1 flex-col gap-1 text-xs font-medium text-gray-600">
          Search
          <Input name="q" defaultValue={sp.q ?? ""} placeholder="Email, name or link" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          Type
          <Select name="kind" defaultValue={kind} className="w-44">
            <option value="">All types</option>
            <option value="delete_account">Delete account</option>
            <option value="content_report">Content report</option>
          </Select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          Sort by
          <Select name="sort" defaultValue={sp.sort === "oldest" ? "oldest" : "newest"} className="w-36">
            <option value="newest">Newest first</option>
            <option value="oldest">Oldest first</option>
          </Select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          From
          <Input type="date" name="from" defaultValue={from ?? ""} className="w-40" />
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-gray-600">
          To
          <Input type="date" name="to" defaultValue={to ?? ""} className="w-40" />
        </label>
        <div className="flex items-center gap-3">
          <Button type="submit">Apply</Button>
          <Link href="/requests" className="text-sm font-medium text-gray-500 hover:text-gray-800">
            Reset
          </Link>
        </div>
      </form>
      <p className="mb-3 text-sm text-gray-500">
        <b className="text-gray-800">{list.length}</b> request{list.length === 1 ? "" : "s"} · {rangeLabel(from, to)}
      </p>
      <Card className="mb-4 text-sm text-gray-600">
        <b>Delete account:</b> press <b>Delete this account now</b> (removes the account, its cloud files and data),
        then reply to the user by email. We promise deletion within 7 days.{" "}
        <b>Reports:</b> check the content, hide or delete it under Posts / Channels, then mark done.
      </Card>
      {list.length === 0 ? (
        <Empty>No requests match.</Empty>
      ) : (
        <div className="space-y-3">
          {list.map((r) => (
            <Card key={r.id}>
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div>
                  {r.kind === "delete_account" ? <Badge tone="red">Delete account</Badge> : <Badge tone="amber">Content report</Badge>}{" "}
                  {r.status !== "open" && <Badge>{r.status}</Badge>}
                  <p className="mt-2 font-semibold">{r.name ? `${r.name} · ` : ""}{r.email}</p>
                  {r.kind === "delete_account" && (
                    <p className="text-xs text-gray-500">{r.user_id ? "Matches an account" : "No account with this email"}</p>
                  )}
                </div>
                <p className="text-xs text-gray-500">{formatDate(r.created_at)}</p>
              </div>
              {r.content_url && <p className="mt-2 text-sm"><b>Content:</b> {r.content_url}</p>}
              {r.details && <p className="mt-1 whitespace-pre-line text-sm text-gray-700">{r.details}</p>}
              {r.note && <p className="mt-2 text-xs text-gray-500">Note: {r.note} · closed {formatDate(r.closed_at)}</p>}
              {r.status === "open" ? (
                <form className="mt-3 flex flex-wrap items-center gap-2">
                  <Input name="note" placeholder="Note (optional)" className="max-w-xs" />
                  {r.kind === "delete_account" && r.user_id && (
                    <Button formAction={deleteRequestedAccount.bind(null, r.id, back)} variant="danger" type="submit">
                      Delete this account now
                    </Button>
                  )}
                  <Button formAction={closeRequest.bind(null, r.id, "done", back)} variant="success" type="submit">Mark done</Button>
                  <Button formAction={closeRequest.bind(null, r.id, "rejected", back)} variant="secondary" type="submit">Reject</Button>
                </form>
              ) : (
                <form className="mt-3" action={closeRequest.bind(null, r.id, "open", back)}>
                  <Button variant="secondary" type="submit">Reopen</Button>
                </form>
              )}
            </Card>
          ))}
        </div>
      )}
    </>
  );
}
