"use client";

import { Button, Card } from "@/components/ui";

// Shown instead of a blank screen when a page fails to load.
export default function PanelError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <Card>
      <h1 className="text-xl font-semibold text-gray-900">This page could not load</h1>
      <p className="my-4 text-sm leading-6 text-gray-500">
        Try again. If this keeps happening, check your connection and that your account still has admin access.
      </p>
      <Button onClick={reset}>Try again</Button>
    </Card>
  );
}
