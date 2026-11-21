import { AdminShell } from "@/components/admin-shell";
import type { NavGroup } from "@/components/nav";
import { requireAdmin } from "@/lib/auth";
import { signOut } from "../login/actions";

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const { supabase, user, role } = await requireAdmin();
  const isOwner = role === "owner";
  const [{ data: stats }, { data: requests }, { data: pendingPayments }, { data: openSupport }] =
    await Promise.all([
      supabase.rpc("admin_dashboard"),
      isOwner ? supabase.rpc("admin_plan_requests") : Promise.resolve({ data: [] }),
      isOwner ? supabase.rpc("admin_pending_payments") : Promise.resolve({ data: 0 }),
      isOwner ? supabase.rpc("admin_open_support_requests") : Promise.resolve({ data: 0 }),
    ]);
  const openRequests = (requests ?? []).length;

  // Same pages and the same owner-only rule as before; only grouped for the sidebar.
  // (Every owner-only page also checks the role on the server.)
  const groups: NavGroup[] = [
    { label: "Overview", items: [{ href: "/", label: "Dashboard", icon: "◫" }] },
    {
      label: "Content",
      items: [
        { href: "/channels", label: "Channels", icon: "▦", badge: isOwner ? Number(stats?.pending_channels ?? 0) : 0 },
        { href: "/posts", label: "Posts", icon: "▤" },
      ],
    },
    ...(isOwner
      ? [
          {
            label: "People",
            items: [
              { href: "/users", label: "Users", icon: "♙", badge: openRequests },
              { href: "/requests", label: "Requests", icon: "✉", badge: Number(openSupport ?? 0) },
            ],
          },
          {
            label: "Revenue",
            items: [
              { href: "/payments", label: "Payments", icon: "₹", badge: Number(pendingPayments ?? 0) },
              { href: "/plans", label: "Plans", icon: "◇" },
              { href: "/meta", label: "Meta Pixel", icon: "◎" },
            ],
          },
          { label: "Engage", items: [{ href: "/notifications", label: "Notifications", icon: "🔔" }] },
          { label: "Settings", items: [{ href: "/admins", label: "Admins", icon: "⚙" }] },
        ]
      : []),
  ];

  return (
    <AdminShell groups={groups} email={user.email ?? ""} isOwner={isOwner} signOut={signOut}>
      {children}
    </AdminShell>
  );
}
