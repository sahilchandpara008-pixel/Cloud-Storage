// Date-range helpers for admin reports. Dates are Indian calendar days
// (YYYY-MM-DD, IST); the database gets the matching instants.

export const isDate = (v?: string | null): v is string => !!v && /^\d{4}-\d{2}-\d{2}$/.test(v);

/** Start of an Indian day, as a timestamp the database understands. */
export const dayStart = (v?: string | null) => (isDate(v) ? `${v}T00:00:00+05:30` : null);

/** End (exclusive) of an Indian day. */
export const dayEnd = (v?: string | null) => {
  if (!isDate(v)) return null;
  const d = new Date(`${v}T00:00:00+05:30`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString();
};

/** Today's date in India. */
export function istToday(now = new Date()) {
  return now.toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
}

function addDays(day: string, n: number) {
  const d = new Date(`${day}T12:00:00+05:30`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
}

export type Preset = { key: string; label: string; from?: string; to?: string };

/** Quick ranges shown above reports. */
export function datePresets(now = new Date()): Preset[] {
  const today = istToday(now);
  const [y, m] = today.split("-").map(Number);
  const monthStart = `${y}-${String(m).padStart(2, "0")}-01`;
  const lastMonthEnd = addDays(monthStart, -1);
  const lastMonthStart = `${lastMonthEnd.slice(0, 7)}-01`;
  return [
    { key: "today", label: "Today", from: today, to: today },
    { key: "yesterday", label: "Yesterday", from: addDays(today, -1), to: addDays(today, -1) },
    { key: "7d", label: "Last 7 days", from: addDays(today, -6), to: today },
    { key: "30d", label: "Last 30 days", from: addDays(today, -29), to: today },
    { key: "month", label: "This month", from: monthStart, to: today },
    { key: "last_month", label: "Last month", from: lastMonthStart, to: lastMonthEnd },
    { key: "all", label: "All time" },
  ];
}

/** Human label for the selected range, e.g. "1 Nov 2026 – 19 Nov 2026". */
export function rangeLabel(from?: string, to?: string) {
  const f = (d: string) =>
    new Date(`${d}T12:00:00+05:30`).toLocaleDateString("en-IN", {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: "Asia/Kolkata",
    });
  if (isDate(from) && isDate(to)) return from === to ? f(from) : `${f(from)} – ${f(to)}`;
  if (isDate(from)) return `from ${f(from)}`;
  if (isDate(to)) return `until ${f(to)}`;
  return "All time";
}
