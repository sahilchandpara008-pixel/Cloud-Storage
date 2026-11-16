"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/browser";

// Bunny encodes a video asynchronously after upload; this just asks once
// whether it's finished yet and refreshes the page if so.
export function CheckEncoding({ itemId }: { itemId: string }) {
  const router = useRouter();
  const [checking, setChecking] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function check() {
    setChecking(true);
    setMessage(null);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.functions.invoke("bunny-stream-status", { body: { item_id: itemId } });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      if (data?.status === "ready") {
        router.refresh();
      } else if (data?.status === "failed") {
        setMessage("Encoding failed.");
      } else {
        setMessage("Still processing — try again in a bit.");
      }
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Couldn't check.");
    } finally {
      setChecking(false);
    }
  }

  return (
    <div className="text-right">
      <button
        type="button"
        onClick={check}
        disabled={checking}
        className="text-xs font-medium text-blue-700 hover:underline"
      >
        {checking ? "Checking…" : "Check encoding"}
      </button>
      {message && <p className="text-xs text-gray-500">{message}</p>}
    </div>
  );
}
