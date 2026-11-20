import type { ReactNode } from "react";
import { inter, spaceGrotesk } from "@/app/fonts";
import { Breadcrumb, Nav, type NavGroup } from "@/components/nav";

// Small outlined button for the dark sidebar.
const darkButton =
  "rounded-lg border border-white/15 px-3 py-1.5 text-xs font-medium text-[#e4e4e7] transition-colors hover:border-white/30 hover:bg-white/5 hover:text-white";

function Logo() {
  return (
    <span className="flex items-center gap-3 font-semibold tracking-tight text-white">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/site/logo.png" alt="" width={36} height={36} className="h-9 w-9 rounded-xl" />
      <span className="font-display text-lg">
        Flixvault
        <span className="block font-sans text-[10px] font-medium uppercase tracking-[.2em] text-[#8a8a94]">Admin</span>
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
    <div className={`admin-theme ${inter.variable} ${spaceGrotesk.variable} min-h-screen`}>
      <aside className="bg-[#0f0f12] md:border-r md:border-[#1f1f25] md:fixed md:inset-y-0 md:left-0 md:z-20 md:flex md:w-60 md:flex-col">
        <div className="flex items-center justify-between gap-3 px-4 py-3 md:border-b md:border-[#1f1f25] md:px-5 md:py-5">
          <Logo />
          <form action={signOut} className="md:hidden">
            <button className={darkButton}>Sign out</button>
          </form>
        </div>
        <div className="md:flex-1 md:overflow-y-auto md:pt-4">
          <Nav groups={groups} />
        </div>
        <div className="hidden items-center gap-3 border-t border-[#1f1f25] px-4 py-3 md:flex">
          <div className="min-w-0 flex-1">
            <p className="truncate text-xs font-medium text-[#e4e4e7]" title={email}>
              {email}
            </p>
            <p className="text-[11px] text-gray-500">{isOwner ? "Owner" : "Content admin"}</p>
          </div>
          <form action={signOut}>
            <button className={darkButton}>Sign out</button>
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
