"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

// Pop-up confirmation after an admin action (saved, created, deleted, failed).
// The server action already redirects with ?ok=... or ?error=...; this shows
// it in the corner instead of a banner, then removes it from the address so a
// refresh doesn't show it again. Success closes itself; an error stays until
// closed, so it can't be missed.
export function Toast({ ok, error }: { ok?: string; error?: string }) {
  const message = error ?? ok;
  const isError = !!error;
  const [open, setOpen] = useState(!!message);
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();

  useEffect(() => {
    setOpen(!!message);
    if (!message) return;
    // Clean the address bar (keeps every other filter in the URL).
    const next = new URLSearchParams(params.toString());
    next.delete("ok");
    next.delete("error");
    const qs = next.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
    if (isError) return;
    const t = setTimeout(() => setOpen(false), 5000);
    return () => clearTimeout(t);
    // Run once per message; params/router are read at that moment only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [message, isError]);

  if (!open || !message) return null;

  return (
    <div className="pointer-events-none fixed inset-x-0 top-3 z-50 flex justify-center px-3 sm:inset-x-auto sm:right-4 sm:top-4 sm:justify-end">
      <div
        role={isError ? "alert" : "status"}
        aria-live={isError ? "assertive" : "polite"}
        className={`toast-in pointer-events-auto flex w-full max-w-md items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm shadow-lg ${
          isError ? "border-red-200" : "border-green-200"
        }`}
      >
        <span
          aria-hidden="true"
          className={`mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs font-bold text-white ${
            isError ? "bg-red-600" : "bg-green-600 !text-[#04210f]"
          }`}
        >
          {isError ? "!" : "✓"}
        </span>
        <div className="min-w-0 flex-1">
          <p className={`font-semibold ${isError ? "text-red-800" : "text-green-800"}`}>
            {isError ? "That didn't work" : "Done"}
          </p>
          <p className="mt-0.5 break-words text-gray-700">{message}</p>
        </div>
        <button
          type="button"
          onClick={() => setOpen(false)}
          aria-label="Close"
          className="-mr-1 grid h-8 w-8 shrink-0 place-items-center rounded-md text-gray-400 hover:bg-gray-100 hover:text-gray-700"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
