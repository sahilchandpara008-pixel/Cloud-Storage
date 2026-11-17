import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";

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
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-gray-500">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border border-gray-200 bg-white p-5 shadow-sm ${className}`}>
      {children}
    </div>
  );
}

export function Flash({ ok, error }: { ok?: string; error?: string }) {
  if (!ok && !error) return null;
  return (
    <div
      role="status"
      className={`mb-5 rounded-lg px-4 py-3 text-sm ${
        error ? "bg-red-50 text-red-800 ring-1 ring-red-200" : "bg-green-50 text-green-800 ring-1 ring-green-200"
      }`}
    >
      {error ?? ok}
    </div>
  );
}

const buttonStyles = {
  primary: "bg-red-700 text-white hover:bg-red-800",
  secondary: "bg-white text-gray-800 ring-1 ring-gray-300 hover:bg-gray-50",
  danger: "bg-white text-red-700 ring-1 ring-red-300 hover:bg-red-50",
  success: "bg-green-700 text-white hover:bg-green-800",
};

type Variant = keyof typeof buttonStyles;

export function Button({
  variant = "primary",
  className = "",
  ...props
}: ComponentProps<"button"> & { variant?: Variant }) {
  return (
    <button
      className={`inline-flex items-center justify-center gap-2 rounded-lg px-3.5 py-2 text-sm font-medium transition disabled:opacity-50 ${buttonStyles[variant]} ${className}`}
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
      className={`inline-flex items-center justify-center gap-2 rounded-lg px-3.5 py-2 text-sm font-medium transition ${buttonStyles[variant]} ${className}`}
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
    <label className="block">
      <span className="mb-1 block text-sm font-medium text-gray-700">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-gray-500">{hint}</span>}
    </label>
  );
}

const inputClass =
  "block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-red-600 focus:outline-none focus:ring-1 focus:ring-red-600";

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
  gray: "bg-gray-100 text-gray-700",
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
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${badgeTones[tone]}`}>
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
  return <Badge tone="amber">Draft</Badge>;
}

export function SourceBadge({ source }: { source: string }) {
  return source === "ads" ? <Badge tone="purple">Ads</Badge> : <Badge tone="blue">Organic</Badge>;
}

export function Table({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white shadow-sm">
      <table className="min-w-full divide-y divide-gray-200 text-sm">{children}</table>
    </div>
  );
}

export function Th({ children, className = "" }: { children?: ReactNode; className?: string }) {
  return (
    <th className={`whitespace-nowrap bg-gray-50 px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-gray-500 ${className}`}>
      {children}
    </th>
  );
}

export function Td({ children, className = "" }: { children?: ReactNode; className?: string }) {
  return <td className={`px-4 py-3 align-middle text-gray-800 ${className}`}>{children}</td>;
}

export function Empty({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-gray-300 bg-white px-6 py-12 text-center text-sm text-gray-500">
      {children}
    </div>
  );
}
