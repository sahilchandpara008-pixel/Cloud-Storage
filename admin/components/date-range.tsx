import Link from "next/link";
import { datePresets, isDate } from "@/lib/dates";

/** Quick date buttons (Today, Last 7 days, ...). `href` builds the link for a range. */
export function DatePresets({
  from,
  to,
  href,
  className = "",
}: {
  from?: string;
  to?: string;
  href: (from?: string, to?: string) => string;
  className?: string;
}) {
  const presets = datePresets();
  const none = !isDate(from) && !isDate(to);
  return (
    <div className={`flex flex-wrap gap-1.5 ${className}`} role="group" aria-label="Quick date ranges">
      {presets.map((p) => {
        const active = p.key === "all" ? none : p.from === from && p.to === to;
        return (
          <Link
            key={p.key}
            href={href(p.from, p.to)}
            aria-current={active ? "true" : undefined}
            className={`rounded-full px-3 py-1 text-xs font-medium ring-1 transition-colors ${
              active
                ? "bg-brand-500 font-semibold text-ink-900 ring-brand-500"
                : "bg-white text-gray-700 ring-gray-200 hover:bg-gray-50 hover:ring-gray-300"
            }`}
          >
            {p.label}
          </Link>
        );
      })}
    </div>
  );
}
