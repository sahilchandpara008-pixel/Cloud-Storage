"use client";

import { useState } from "react";
import { ContentUploader } from "./content-uploader";
import type { ChannelOption } from "./post-form";

// "Single post" or "Bulk upload". Switching is blocked while an upload runs,
// so nothing is cut off half-way.
export function UploadTabs({
  channels,
  initialChannelId,
  initialMode,
}: {
  channels: ChannelOption[];
  initialChannelId?: string;
  initialMode: "single" | "bulk";
}) {
  const [mode, setMode] = useState(initialMode);
  const [busy, setBusy] = useState(false);

  const tab = (value: "single" | "bulk", label: string, hint: string) => (
    <button
      type="button"
      role="tab"
      aria-selected={mode === value}
      disabled={busy && mode !== value}
      onClick={() => setMode(value)}
      className={`flex-1 rounded-lg border px-4 py-2.5 text-left text-sm transition ${
        mode === value
          ? "border-red-700 bg-red-50 text-red-800"
          : "border-gray-200 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-50"
      }`}
    >
      <span className="block font-semibold">{label}</span>
      <span className="block text-xs text-gray-500">{hint}</span>
    </button>
  );

  return (
    <div className="space-y-5">
      <div role="tablist" className="flex flex-col gap-2 sm:flex-row">
        {tab("single", "Single post", "One post: main file, preview and thumbnail")}
        {tab("bulk", "Bulk upload", "Many files at once, one post each")}
      </div>
      {/* key: each mode starts fresh */}
      <ContentUploader
        key={mode}
        mode={mode}
        channels={channels}
        initialChannelId={initialChannelId}
        onBusyChange={setBusy}
      />
    </div>
  );
}
