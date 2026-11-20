export const AUDIENCES = [
  { value: "all", label: "Everyone" },
  { value: "organic", label: "Organic users only" },
  { value: "ads", label: "Ads users only" },
] as const;

export const STATUSES = [
  { value: "draft", label: "Draft" },
  { value: "published", label: "Published" },
  { value: "hidden", label: "Hidden" },
] as const;

export type Audience = (typeof AUDIENCES)[number]["value"];
export type Status = (typeof STATUSES)[number]["value"];

export function audienceLabel(value: string) {
  return AUDIENCES.find((a) => a.value === value)?.label ?? value;
}

// Every time in the admin is India time (IST), whatever time zone the server
// (Vercel runs in UTC) or the admin's computer is set to.
export const ADMIN_TZ = "Asia/Kolkata";

export function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString("en-IN", {
    timeZone: ADMIN_TZ,
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}

// <input type="datetime-local"> value ("2026-11-20T18:30") in India time.
export function toLocalInput(value: string | null | undefined) {
  if (!value) return "";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "";
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: ADMIN_TZ,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(d)
      .map((p) => [p.type, p.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

// The time typed in a datetime-local box, read as India time -> ISO (UTC).
// Returns null for an empty or invalid value.
export function fromLocalInput(value: string | null | undefined) {
  if (!value) return null;
  const d = new Date(`${value.length === 16 ? `${value}:00` : value}+05:30`);
  return Number.isNaN(d.getTime()) ? null : d;
}

// Redirect target carrying a flash message (?ok= / ?error=).
export function withMessage(path: string, kind: "ok" | "error", message: string) {
  const sep = path.includes("?") ? "&" : "?";
  return `${path}${sep}${kind}=${encodeURIComponent(message)}`;
}

// 3118 -> "51:58", 4000 -> "1:06:40"
export function formatDuration(seconds: number | null | undefined) {
  if (!seconds || seconds < 0) return null;
  const s = Math.round(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = String(s % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}
