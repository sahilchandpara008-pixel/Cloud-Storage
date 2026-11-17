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

export function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  return new Date(value).toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

// <input type="datetime-local"> value, in the admin's local time.
export function toLocalInput(value: string | null | undefined) {
  if (!value) return "";
  const d = new Date(value);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
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
