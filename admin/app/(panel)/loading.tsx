// Skeleton shown while a page loads: same shape as a page, so nothing jumps.
export default function PanelLoading() {
  return (
    <div role="status" aria-label="Loading page" className="animate-pulse space-y-5">
      <div className="h-8 w-48 rounded-lg bg-gray-200" />
      <div className="h-4 w-72 max-w-full rounded bg-gray-200" />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="h-28 rounded-xl border border-gray-200 bg-white" />
        ))}
      </div>
      <div className="h-64 rounded-xl border border-gray-200 bg-white" />
      <span className="sr-only">Loading…</span>
    </div>
  );
}
