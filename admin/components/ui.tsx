import Link from "next/link";
import { Suspense, type ComponentProps, type ReactNode } from "react";
import { Toast } from "./toast";

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: ReactNode;
}) {
  return (
    <header className="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div className="min-w-0">
        <h1 className="text-3xl font-bold tracking-tight text-gray-900">{title}</h1>
        {subtitle && <p className="mt-1 max-w-3xl text-sm leading-6 text-gray-500">{subtitle}</p>}
      </div>
      {action && <div className="flex shrink-0 flex-wrap items-center gap-2">{action}</div>}
    </header>
  );
}

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <section
      className={`min-w-0 rounded-2xl border border-gray-200 p-5 shadow-sm ${className.includes("bg-") ? "" : "bg-white"} ${className}`}
    >
      {children}
    </section>
  );
}

// After an action: a pop-up in the corner (see Toast) saying it worked or
// what went wrong.
export function Flash({ ok, error }: { ok?: string; error?: string }) {
  if (!ok && !error) return null;
  return (
    <Suspense fallback={null}>
      <Toast ok={ok} error={error} />
    </Suspense>
  );
}

const buttonStyles = {
  primary: "bg-brand-500 font-semibold text-ink-900 hover:bg-brand-400",
  secondary: "bg-white text-gray-700 ring-1 ring-gray-300 hover:bg-gray-50",
  danger: "bg-white text-red-700 ring-1 ring-red-300 hover:bg-red-50",
  success: "bg-green-700 font-semibold text-ink-900 hover:bg-green-800",
};

type Variant = keyof typeof buttonStyles;

const buttonBase =
  "inline-flex min-h-9 items-center justify-center gap-2 rounded-lg px-3.5 py-2 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50";

export function Button({
  variant = "primary",
  className = "",
  ...props
}: ComponentProps<"button"> & { variant?: Variant }) {
  return (
    <button
      className={`${buttonBase} ${buttonStyles[variant]} ${className}`}
      {...props}
    />
  );
}

export function LinkButton({
  variant = "primary",
  className = "",
  ...props
}: ComponentProps<typeof Link> & { variant?: Variant }) {
  return (
    <Link
      className={`${buttonBase} ${buttonStyles[variant]} ${className}`}
      {...props}
    />
  );
}

export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <label className="flex min-w-0 flex-col gap-1.5">
      <span className="text-sm font-medium text-gray-700">{label}</span>
      {children}
      {hint && <span className="text-xs leading-5 text-gray-500">{hint}</span>}
    </label>
  );
}

const inputClass =
  "block w-full min-w-0 rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm outline-none placeholder:text-gray-400 focus:border-brand-600 focus:ring-1 focus:ring-brand-600 disabled:bg-gray-50 disabled:text-gray-500";

export function Input({ className = "", ...props }: ComponentProps<"input">) {
  return <input className={`${inputClass} ${className}`} {...props} />;
}

export function Textarea({ className = "", ...props }: ComponentProps<"textarea">) {
  return <textarea className={`${inputClass} ${className}`} rows={3} {...props} />;
}

export function Select({ className = "", ...props }: ComponentProps<"select">) {
  return <select className={`${inputClass} ${className}`} {...props} />;
}

// Small secondary action used on media cards (labels, buttons, links).
export const smallAction =
  "inline-flex cursor-pointer items-center gap-1 rounded-md border border-gray-300 bg-white px-2.5 py-1 text-xs font-medium text-gray-700 shadow-sm hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50";

const badgeTones = {
  gray: "bg-gray-100 text-gray-800",
  red: "bg-red-100 text-red-800",
  green: "bg-green-100 text-green-800",
  amber: "bg-amber-100 text-amber-800",
  blue: "bg-blue-100 text-blue-800",
  purple: "bg-purple-100 text-purple-800",
};

export function Badge({
  tone = "gray",
  children,
}: {
  tone?: keyof typeof badgeTones;
  children: ReactNode;
}) {
  return (
    <span
      className={`inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium ${badgeTones[tone]}`}
    >
      {children}
    </span>
  );
}

export function AudienceBadge({ audience }: { audience: string }) {
  if (audience === "ads") return <Badge tone="purple">Ads only</Badge>;
  if (audience === "organic") return <Badge tone="blue">Organic only</Badge>;
  return <Badge>Everyone</Badge>;
}

export function StatusBadge({ status }: { status: string }) {
  if (status === "published") return <Badge tone="green">Published</Badge>;
  if (status === "hidden") return <Badge tone="red">Hidden</Badge>;
  if (!status || status === "draft") return <Badge tone="amber">Draft</Badge>;
  const tone = ["sent", "success", "paid", "approved", "active", "ready", "closed"].includes(status)
    ? "green"
    : ["failed", "error", "rejected", "revoked"].includes(status)
      ? "red"
      : ["pending", "queued", "open", "scheduled", "created", "review"].includes(status)
        ? "amber"
        : "gray";
  const label = status.replaceAll("_", " ");
  return <Badge tone={tone}>{label[0].toUpperCase() + label.slice(1)}</Badge>;
}

export function SourceBadge({ source }: { source: string }) {
  return source === "ads" ? <Badge tone="purple">Ads</Badge> : <Badge tone="blue">Organic</Badge>;
}

export function Table({ children }: { children: ReactNode }) {
  return (
    <div className="min-w-0 max-w-full overflow-x-auto rounded-xl border border-gray-200 bg-white shadow-sm">
      <table className="w-full divide-y divide-gray-200 text-left text-sm">{children}</table>
    </div>
  );
}

export function Th({ children, className = "" }: { children?: ReactNode; className?: string }) {
  return (
    <th className={`whitespace-nowrap bg-gray-50 px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-gray-500 ${className}`}>
      {children}
    </th>
  );
}

export function Td({ children, className = "" }: { children?: ReactNode; className?: string }) {
  return <td className={`px-4 py-3 align-middle text-gray-700 ${className}`}>{children}</td>;
}

export function Empty({ children, icon = "○" }: { children: ReactNode; icon?: string }) {
  return (
    <div className="flex flex-col items-center rounded-xl border border-gray-200 bg-white px-6 py-10 text-center shadow-sm">
      <span
        aria-hidden="true"
        className="mb-3 grid h-11 w-11 place-items-center rounded-full bg-brand-50 text-lg text-brand-600"
      >
        {icon}
      </span>
      <div className="max-w-sm text-sm leading-6 text-gray-500">{children}</div>
    </div>
  );
}

// Segmented filter tabs (links, so the filter stays in the URL).
export function SegmentTabs({
  items,
  className = "",
}: {
  items: { href: string; label: ReactNode; active: boolean }[];
  className?: string;
}) {
  return (
    <nav
      aria-label="Filter"
      className={`inline-flex max-w-full flex-wrap gap-1 rounded-xl border border-gray-200 bg-white p-1 ${className}`}
    >
      {items.map((t) => (
        <Link
          key={t.href}
          href={t.href}
          aria-current={t.active ? "page" : undefined}
          className={`rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
            t.active ? "bg-gray-900 font-semibold text-gray-50" : "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
          }`}
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}

// A heading inside a card or page section.
export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
      <h2 className="text-base font-semibold text-gray-900">{children}</h2>
      {action}
    </div>
  );
}

// A metric tile. href makes it a shortcut to the matching filtered page.
const statTones = {
  brand: "bg-brand-50 text-brand-700",
  purple: "bg-purple-50 text-purple-700",
  blue: "bg-blue-50 text-blue-700",
  green: "bg-green-50 text-green-700",
  amber: "bg-amber-50 text-amber-700",
  gray: "bg-gray-100 text-gray-700",
};

export function Stat({
  label,
  value,
  hint,
  href,
  icon,
  tone = "brand",
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  href?: string;
  icon?: string;
  tone?: keyof typeof statTones;
}) {
  const body = (
    <>
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-medium text-gray-500">{label}</p>
        {icon && (
          <span aria-hidden="true" className={`grid h-8 w-8 shrink-0 place-items-center rounded-lg text-sm ${statTones[tone]}`}>
            {icon}
          </span>
        )}
      </div>
      <p className="font-display mt-2 text-3xl font-bold tabular-nums tracking-tight text-gray-900">{value}</p>
      {hint && <p className="mt-1 text-xs text-gray-400">{hint}</p>}
    </>
  );
  const cls = "block min-w-0 rounded-2xl border border-gray-200 bg-white p-5 shadow-sm";
  return href ? (
    <Link href={href} className={`${cls} transition-colors hover:border-brand-200 hover:bg-brand-50/40`}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

// A highlighted call to action (pending reviews, payments to check, ...).
export function Notice({
  href,
  children,
  action = "Review →",
  tone = "amber",
}: {
  href: string;
  children: ReactNode;
  action?: string;
  tone?: "amber" | "red";
}) {
  return (
    <Link
      href={href}
      className={`flex flex-wrap items-center justify-between gap-3 rounded-xl px-5 py-4 text-sm shadow-sm transition-colors ${
        tone === "red"
          ? "bg-brand-500 text-ink-900 hover:bg-brand-400"
          : "border border-amber-200 bg-amber-50 text-amber-900 hover:bg-amber-100"
      }`}
    >
      <span className="font-medium">{children}</span>
      <span className={tone === "red" ? "font-semibold text-ink-900" : "font-medium text-amber-800"}>{action}</span>
    </Link>
  );
}
