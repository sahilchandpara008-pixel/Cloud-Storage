import { Nav } from "@/components/nav";
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
  const pending = Number(stats?.pending_approvals ?? 0);
  const openRequests = (requests ?? []).length;

  const items = [
    { href: "/", label: "Dashboard" },
    { href: "/channels", label: "Channels", badge: role === "owner" ? Number(stats?.pending_channels ?? 0) : 0 },
    { href: "/posts", label: "Posts" },
    ...(role === "owner"
      ? [
          { href: "/approvals", label: "Approvals", badge: pending },
          { href: "/payments", label: "Payments", badge: Number(pendingPayments ?? 0) },
          { href: "/meta", label: "Meta Pixel" },
          { href: "/users", label: "Users", badge: openRequests },
          { href: "/requests", label: "Requests", badge: Number(openSupport ?? 0) },
          { href: "/plans", label: "Plans" },
          { href: "/admins", label: "Admins" },
        ]
      : []),
  ];

  return (
    <div className="min-h-screen md:flex">
      <aside className="border-b border-gray-200 bg-white p-4 md:sticky md:top-0 md:h-screen md:w-60 md:shrink-0 md:border-b-0 md:border-r">
        <div className="mb-4 flex items-center gap-2 md:mb-6">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-red-700 text-sm font-bold text-white">
            FV
          </div>
          <span className="font-semibold">Flixvault</span>
        </div>
        <Nav items={items} />
        <div className="mt-4 border-t border-gray-200 pt-4 md:absolute md:bottom-4 md:left-4 md:right-4">
          <p className="truncate text-xs text-gray-500" title={user.email ?? ""}>
            {user.email}
          </p>
          <p className="mb-2 text-xs font-medium text-gray-700">
            {role === "owner" ? "Owner" : "Content admin"}
          </p>
          <form action={signOut}>
            <button className="text-sm font-medium text-red-700 hover:underline">Sign out</button>
          </form>
        </div>
      </aside>
      <main className="flex-1 p-4 md:p-8">{children}</main>
    </div>
  );
}
