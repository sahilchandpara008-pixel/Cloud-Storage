"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/browser";

// Bunny encodes a video after it is uploaded; until that finishes the app
// hides the post. While this page is open, ask Bunny every 15 seconds, show
// how far along it is, and refresh the page the moment the video is ready.
// (The server also checks every minute on its own, so closing the page is fine.)
export function CheckEncoding({ itemId }: { itemId: string }) {
  const router = useRouter();
  const [progress, setProgress] = useState<number | null>(null);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    async function check() {
      try {
        const supabase = createClient();
        const { data, error } = await supabase.functions.invoke("bunny-stream-status", { body: { item_id: itemId } });
        if (error) throw error;
        if (data?.error) throw new Error(data.error);
        if (stopped) return;
        setNote(null);
        if (data?.status === "ready" || data?.status === "failed") {
          router.refresh();
          return;
        }
        if (typeof data?.progress === "number") setProgress(data.progress);
      } catch {
        if (!stopped) setNote("Couldn't reach Bunny just now, retrying…");
      }
      if (!stopped) timer = setTimeout(check, 15_000);
    }

    check();
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }, [itemId, router]);

  return (
    <div>
      <div className="flex items-center justify-between text-xs text-blue-800">
        <span>Processing on Bunny…</span>
        <span className="tabular-nums">{progress !== null ? `${progress}%` : ""}</span>
      </div>
      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-blue-100">
        <div
          className={`h-full rounded-full bg-blue-600 transition-all duration-700 ${
            progress === null ? "w-1/4 animate-pulse" : ""
          }`}
          style={progress !== null ? { width: `${Math.max(progress, 3)}%` } : undefined}
        />
      </div>
      {note && <p className="mt-1 text-[11px] text-gray-500">{note}</p>}
    </div>
  );
}
