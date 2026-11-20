"use client";

import { useState } from "react";

export function CopyButton({ text }: { text: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      type="button"
      onClick={async () => {
        await navigator.clipboard.writeText(text);
        setDone(true);
        setTimeout(() => setDone(false), 1500);
      }}
      className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-semibold text-ink-900"
    >
      {done ? "Copied ✓" : "Copy"}
    </button>
  );
}
