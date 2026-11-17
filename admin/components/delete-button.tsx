"use client";

import { useFormStatus } from "react-dom";
import { Button } from "@/components/ui";

// Submit button for a permanent delete. Must sit inside the <form action=...>.
// Asks first, then disables itself while the server works: deleting a channel
// removes its videos from Bunny and can take several seconds, and a second
// click used to send a second request for something already gone.
export function DeleteButton({
  label,
  pendingLabel,
  confirmText,
}: {
  label: string;
  pendingLabel: string;
  confirmText: string;
}) {
  const { pending } = useFormStatus();
  return (
    <Button
      variant="danger"
      type="submit"
      disabled={pending}
      onClick={(e) => {
        if (!pending && !window.confirm(confirmText)) e.preventDefault();
      }}
    >
      {pending ? pendingLabel : label}
    </Button>
  );
}
