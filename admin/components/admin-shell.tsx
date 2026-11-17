import type { ReactNode } from "react";
import { Breadcrumb, Nav, type NavGroup } from "@/components/nav";
import { Button } from "@/components/ui";

function Logo() {
  return (
    <span className="flex items-center gap-3 font-semibold tracking-tight text-gray-900">
      <span className="grid h-10 w-10 place-items-center rounded-xl bg-red-700 text-sm font-bold text-white">FV</span>
      <span>
        Flixvault
        <span className="block text-[10px] font-medium uppercase tracking-[.2em] text-gray-400">Admin</span>
      </span>
    </span>
  );
}

// The admin frame: sidebar (grouped navigation, account, sign out), top bar
// with breadcrumb, centred content. Data and permissions come from the layout.
export function AdminShell({
  groups,
  email,
  isOwner,
  signOut,
  children,
}: {
  groups: NavGroup[];
  email: string;
  isOwner: boolean;
  signOut: () => Promise<void>;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-gray-50">
      <aside className="border-b border-gray-200 bg-white md:fixed md:inset-y-0 md:left-0 md:z-20 md:flex md:w-60 md:flex-col md:border-b-0 md:border-r">
        <div className="flex items-center justify-between gap-3 px-4 py-4 md:border-b md:border-gray-100 md:px-6 md:py-5">
          <Logo />
          <form action={signOut} className="md:hidden">
            <Button variant="secondary">Sign out</Button>
          </form>
        </div>
        <div className="md:flex-1 md:overflow-y-auto md:pt-6">
          <Nav groups={groups} />
        </div>
        <div className="hidden border-t border-gray-100 p-5 md:block">
          <p className="truncate text-xs font-medium text-gray-700" title={email}>
            {email}
          </p>
          <p className="mt-1 mb-4 text-xs text-gray-400">{isOwner ? "Owner" : "Content admin"}</p>
          <form action={signOut}>
            <Button variant="secondary" className="w-full">
              Sign out
            </Button>
          </form>
        </div>
      </aside>

      <div className="md:pl-60">
        <div className="flex items-center justify-between gap-4 border-b border-gray-200 bg-white px-4 py-3 text-xs text-gray-500 md:px-6">
          <Breadcrumb groups={groups} />
          <span className="hidden shrink-0 sm:block">{isOwner ? "Owner" : "Content admin"} · India · IST</span>
        </div>
        <main className="mx-auto max-w-6xl p-4 md:p-6 lg:py-8">{children}</main>
        <footer className="mx-auto max-w-6xl px-4 pb-6 text-xs text-gray-400 md:px-6">Flixvault admin</footer>
      </div>
    </div>
  );
}
