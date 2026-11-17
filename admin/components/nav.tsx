"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export type NavItem = { href: string; label: string; icon: string; badge?: number };
export type NavGroup = { label: string; items: NavItem[] };

function isActive(pathname: string, href: string) {
  return href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(href + "/");
}

// Sidebar on desktop (grouped, with icons); a compact horizontal strip on phones.
export function Nav({ groups }: { groups: NavGroup[] }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Main navigation" className="flex gap-1 overflow-x-auto px-3 pb-3 md:block md:overflow-visible md:pb-0">
      {groups.map((g) => (
        <div key={g.label} className="contents md:mb-5 md:block">
          <p className="hidden px-3 pb-1.5 text-[10px] font-semibold uppercase tracking-[.18em] text-gray-400 md:block">
            {g.label}
          </p>
          {g.items.map((item) => {
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`relative flex min-h-10 shrink-0 items-center gap-3 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors md:mb-0.5 ${
                  active ? "bg-red-50 text-red-800" : "text-gray-500 hover:bg-gray-50 hover:text-gray-900"
                }`}
              >
                <span aria-hidden="true" className="hidden w-5 text-center text-base opacity-70 md:block">
                  {item.icon}
                </span>
                {item.label}
                {!!item.badge && (
                  <span className="ml-auto rounded-full bg-red-600 px-2 py-0.5 text-xs font-semibold text-white">
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
          <Link href={current.href} className="font-medium text-gray-700 hover:text-red-700">
            {current.label}
          </Link>
        </>
      )}
    </span>
  );
}
