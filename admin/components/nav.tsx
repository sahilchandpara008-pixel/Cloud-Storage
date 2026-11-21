"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export type NavItem = { href: string; label: string; icon: string; badge?: number };
export type NavGroup = { label: string; items: NavItem[] };

// Line icons for the menu, by page. Unknown pages fall back to the item's
// own text icon.
const ICONS: Record<string, string> = {
  "/": "M3 3h7v9H3zM14 3h7v5h-7zM14 12h7v9h-7zM3 16h7v5H3z",
  "/channels": "M3 6h18v13H3zM8 2l4 4 4-4",
  "/posts": "M4 4h16v16H4zM10 9l5 3-5 3z",
  "/users": "M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21c1-4 4-6 7-6s6 2 7 6M17 11a3 3 0 1 0 0-6M22 21c-.6-2.6-2-4.3-4-5",
  "/requests": "M4 4h16v12H8l-4 4z",
  "/payments": "M3 6h18v12H3zM3 10h18M7 15h3",
  "/plans": "M12 2 3 7l9 5 9-5zM3 12l9 5 9-5M3 17l9 5 9-5",
  "/notifications": "M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0",
  "/meta": "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
  "/admins": "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1",
};

function NavIcon({ href, fallback }: { href: string; fallback: string }) {
  const d = ICONS[href];
  if (!d) {
    return (
      <span aria-hidden="true" className="hidden w-5 text-center text-base opacity-70 md:block">
        {fallback}
      </span>
    );
  }
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="hidden shrink-0 md:block"
    >
      <path d={d} />
    </svg>
  );
}

function isActive(pathname: string, href: string) {
  return href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(href + "/");
}

// Sidebar on desktop (grouped, with icons); a compact horizontal strip on phones.
export function Nav({ groups }: { groups: NavGroup[] }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Main navigation" className="flex gap-1 overflow-x-auto px-3 pb-3 md:block md:overflow-visible md:pb-0">
      {groups.map((g) => (
        <div key={g.label} className="contents md:mb-4 md:block">
          <p className="hidden px-3 pb-1 text-[10px] font-semibold uppercase tracking-[.18em] text-gray-500 md:block">
            {g.label}
          </p>
          {g.items.map((item) => {
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`relative flex min-h-10 shrink-0 items-center gap-3 whitespace-nowrap rounded-lg px-3 py-1.5 text-sm font-medium transition-colors md:mb-0.5 ${
                  active
                    ? "bg-brand-500/15 font-semibold text-brand-400"
                    : "text-[#c4c4cc] hover:bg-white/5 hover:text-white"
                }`}
              >
                <NavIcon href={item.href} fallback={item.icon} />
                {item.label}
                {!!item.badge && (
                  <span className="ml-auto rounded-full bg-brand-500 px-2 py-0.5 text-xs font-bold text-ink-900">
                    <span className="sr-only">, </span>
                    {item.badge}
                    <span className="sr-only"> waiting</span>
                  </span>
                )}
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );
}

// "Flixvault / Admin / Posts" strip above every page.
export function Breadcrumb({ groups }: { groups: NavGroup[] }) {
  const pathname = usePathname();
  const current = groups.flatMap((g) => g.items).find((i) => isActive(pathname, i.href));
  return (
    <span className="min-w-0 truncate">
      Admin
      {current && (
        <>
          <span aria-hidden="true" className="mx-2 text-gray-300">
            /
          </span>
          <Link href={current.href} className="font-medium text-gray-700 hover:text-brand-700">
            {current.label}
          </Link>
        </>
      )}
    </span>
  );
}
