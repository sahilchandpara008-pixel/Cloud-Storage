"use client";

import { useState, type ComponentProps } from "react";
import { Input } from "./ui";

// Password field with a show / hide eye. The field and its name are the same
// as a plain password input, so the form submits exactly as before.
export function PasswordInput(props: Omit<ComponentProps<"input">, "type">) {
  const [shown, setShown] = useState(false);
  return (
    <div className="relative">
      <Input {...props} type={shown ? "text" : "password"} className="pr-11" />
      <button
        type="button"
        onClick={() => setShown((s) => !s)}
        aria-label={shown ? "Hide password" : "Show password"}
        aria-pressed={shown}
        className="absolute inset-y-0 right-0 grid w-11 place-items-center rounded-r-lg text-gray-400 hover:text-gray-700"
      >
        {shown ? (
          <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth={1.8} aria-hidden="true">
            <path d="M3 3l18 18" strokeLinecap="round" />
            <path d="M10.6 10.6a2 2 0 002.8 2.8" strokeLinecap="round" />
            <path
              d="M9.9 5.1A9.8 9.8 0 0112 4.9c5 0 8.6 4.4 9.6 6.6a1.3 1.3 0 010 1c-.4.9-1.3 2.3-2.7 3.6M6.6 6.6C4.6 8 3.2 10 2.4 11.5a1.3 1.3 0 000 1C3.4 14.7 7 19.1 12 19.1c1.7 0 3.2-.5 4.5-1.2"
              strokeLinecap="round"
            />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth={1.8} aria-hidden="true">
            <path d="M2.4 11.5C3.4 9.3 7 4.9 12 4.9s8.6 4.4 9.6 6.6a1.3 1.3 0 010 1c-1 2.2-4.6 6.6-9.6 6.6S3.4 14.7 2.4 12.5a1.3 1.3 0 010-1z" />
            <circle cx="12" cy="12" r="3" />
          </svg>
        )}
      </button>
    </div>
  );
}
