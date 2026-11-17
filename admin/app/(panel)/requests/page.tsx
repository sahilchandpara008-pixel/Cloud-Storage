import { Badge, Button, Card, Empty, Flash, Input, PageHeader, SegmentTabs } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
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
  searchParams: Promise<{ ok?: string; error?: string; status?: string }>;
}) {
  const sp = await searchParams;
  const status = sp.status === "closed" ? "closed" : "open";
  const back = `/requests?status=${status}`;
  const { supabase } = await requireOwner();
  let q = supabase.from("support_requests").select("*").order("created_at", { ascending: false }).limit(300);
  q = status === "open" ? q.eq("status", "open") : q.neq("status", "open");
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
        ].map(([v, l]) => ({ href: `/requests?status=${v}`, label: l, active: v === status }))}
      />
      <Card className="mb-4 text-sm text-gray-600">
        <b>Delete account:</b> press <b>Delete this account now</b> (removes the account, its cloud files and data),
        then reply to the user by email. We promise deletion within 7 days.{" "}
        <b>Reports:</b> check the content, hide or delete it under Posts / Channels, then mark done.
      </Card>
      {list.length === 0 ? (
        <Empty>No {status} requests.</Empty>
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
