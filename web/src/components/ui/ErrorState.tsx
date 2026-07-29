"use client";

import { Button } from "@/components/ui/Button";

export function ErrorState({
  title = "Something went sideways",
  message = "We couldn't load this right now. It's us, not you — try again in a moment.",
  onRetry,
}: {
  title?: string;
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <div
      role="alert"
      className="rule-t flex flex-col items-center border-b border-line px-6 py-20 text-center"
    >
      <svg aria-hidden="true" viewBox="0 0 48 48" fill="none" className="mb-5 size-9 text-danger">
        <circle cx="24" cy="24" r="19" stroke="currentColor" strokeWidth="2" />
        <path d="M24 14v13" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
        <circle cx="24" cy="33" r="1.75" fill="currentColor" />
      </svg>
      <h3 className="text-[17px] font-bold tracking-[-0.01em] text-ink">{title}</h3>
      <p className="mt-2 max-w-sm text-[13.5px] leading-relaxed text-muted">{message}</p>
      {onRetry ? (
        <Button variant="secondary" className="mt-7" onClick={onRetry}>
          Try again
        </Button>
      ) : null}
    </div>
  );
}
