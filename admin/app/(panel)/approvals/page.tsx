import { Button, Empty, Flash, PageHeader, SegmentTabs, Table, Td, Th } from "@/components/ui";
import { requireOwner } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import type { AppUser } from "@/lib/users";
import { setAdsAccess } from "../users/actions";

const tabs = [
  { value: "pending", label: "Waiting" },
  { value: "approved", label: "Approved" },
  { value: "rejected", label: "Rejected" },
];

export default async function ApprovalsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; error?: string; tab?: string }>;
}) {
  const sp = await searchParams;
  const tab = tabs.some((t) => t.value === sp.tab) ? sp.tab! : "pending";
  const back = `/approvals?tab=${tab}`;
  const { supabase } = await requireOwner();
  const { data } = await supabase.rpc("admin_users", { p_filter: tab, p_limit: 200 });
  const users = (data ?? []) as AppUser[];

  return (
    <>
      <PageHeader
        title="Approvals"
        subtitle="Organic users who bought a plan. Approve them to show Ads-only content."
      />
      <Flash ok={sp.ok} error={sp.error} />

      <SegmentTabs
        className="mb-4"
        items={tabs.map((t) => ({ href: `/approvals?tab=${t.value}`, label: t.label, active: tab === t.value }))}
      />

      {users.length === 0 ? (
        <Empty icon="✓">
          {tab === "pending" ? (
            <>
              <span className="block font-medium text-gray-800">You&apos;re all caught up</span>
              Nobody is waiting for approval. Organic users who buy a plan appear here.
            </>
          ) : (
            `No ${tab} users.`
          )}
        </Empty>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>User</Th>
              <Th>Plan</Th>
              <Th>Joined</Th>
              <Th className="text-right">Decision</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {users.map((u) => (
              <tr key={u.id} className={tab === "pending" ? "bg-amber-50/60" : ""}>
                <Td>
                  <p className="font-medium">{u.display_name}</p>
                  <p className="text-xs text-gray-500">{u.email ?? "no email"}</p>
                </Td>
                <Td>
                  {u.plan_name ?? "Expired"}
                  {u.plan_ends_at && <p className="text-xs text-gray-500">until {formatDate(u.plan_ends_at)}</p>}
                </Td>
                <Td className="whitespace-nowrap">{formatDate(u.created_at)}</Td>
                <Td className="text-right">
                  <div className="flex justify-end gap-2">
                    {u.ads_access_status !== "approved" && (
                      <form action={setAdsAccess.bind(null, u.id, "approved", back)}>
                        <Button variant="success" type="submit">Approve</Button>
                      </form>
                    )}
                    {u.ads_access_status === "pending" && (
                      <form action={setAdsAccess.bind(null, u.id, "rejected", back)}>
                        <Button variant="danger" type="submit">Reject</Button>
                      </form>
                    )}
                    {u.ads_access_status === "approved" && (
                      <form action={setAdsAccess.bind(null, u.id, "rejected", back)}>
                        <Button variant="danger" type="submit">Revoke</Button>
                      </form>
                    )}
                  </div>
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
    </>
  );
}
