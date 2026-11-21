import Link from "next/link";

export const PAGE_SIZES = [10, 20, 50, 100, 200] as const;
export const DEFAULT_PAGE_SIZE = 20;

// Rows per page and page number from the URL (?per=50&page=2), made safe.
export function pageParams(per?: string, page?: string, total?: number) {
  const size = (PAGE_SIZES as readonly number[]).includes(Number(per)) ? Number(per) : DEFAULT_PAGE_SIZE;
  const pages = total === undefined ? undefined : Math.max(1, Math.ceil(total / size));
  let n = Math.max(1, Math.floor(Number(page) || 1));
  if (pages !== undefined) n = Math.min(n, pages);
  return { size, page: n, offset: (n - 1) * size };
}

// "Rows per page 10 20 50 100 200 · Showing 21–40 of 87 · ‹ Previous  Page 2 of 5  Next ›"
// href(patch) builds the link with the other filters kept.
export function Pager({
  total,
  size,
  page,
  href,
}: {
  total: number;
  size: number;
  page: number;
  href: (patch: { per?: string; page?: string }) => string;
}) {
  const pages = Math.max(1, Math.ceil(total / size));
  const from = total === 0 ? 0 : (page - 1) * size + 1;
  const to = Math.min(total, page * size);
  const btn =
    "inline-flex min-h-9 items-center rounded-lg px-3 text-sm font-medium ring-1 ring-gray-300 transition-colors";
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-medium text-gray-500">Rows per page</span>
        <span className="inline-flex gap-1 rounded-xl border border-gray-200 bg-white p-1">
          {PAGE_SIZES.map((n) => (
            <Link
              key={n}
              href={href({ per: String(n), page: "1" })}
              aria-current={n === size ? "true" : undefined}
              className={`rounded-lg px-2.5 py-1 text-xs font-medium tabular-nums ${
                n === size ? "bg-gray-900 font-semibold text-gray-50" : "text-gray-600 hover:bg-gray-100"
              }`}
            >
              {n}
            </Link>
          ))}
        </span>
        <span className="text-xs text-gray-500 tabular-nums">
          Showing {from}–{to} of {total}
        </span>
      </div>
      <div className="flex items-center gap-2">
        {page > 1 ? (
          <Link href={href({ per: String(size), page: String(page - 1) })} className={`${btn} text-gray-700 hover:bg-gray-50`}>
            ‹ Previous
          </Link>
        ) : (
          <span className={`${btn} cursor-not-allowed text-gray-400 opacity-50`}>‹ Previous</span>
        )}
        <span className="px-1 text-xs text-gray-500 tabular-nums">
          Page {page} of {pages}
        </span>
        {page < pages ? (
          <Link href={href({ per: String(size), page: String(page + 1) })} className={`${btn} text-gray-700 hover:bg-gray-50`}>
            Next ›
          </Link>
        ) : (
          <span className={`${btn} cursor-not-allowed text-gray-400 opacity-50`}>Next ›</span>
        )}
      </div>
    </div>
  );
}
