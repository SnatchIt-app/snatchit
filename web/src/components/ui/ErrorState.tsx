"use client";

import { Button } from "@/components/ui/Button";

/**
 * Error state in the same voice as EmptyState: Oswald statement between red
 * hairlines, no icon, square retry action.
 */
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
      className="flex flex-col items-center border-y border-primary/15 px-6 py-20 text-center"
    >
      <p className="eyebrow text-primary/80">Error</p>
      <h3 className="mt-4 font-display text-[26px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink sm:text-[30px]">
        {title}
      </h3>
      <p className="mt-4 max-w-sm text-[14px] leading-relaxed text-muted">{message}</p>
      {onRetry ? (
        <Button variant="secondary" className="mt-7" onClick={onRetry}>
          Try again
        </Button>
      ) : null}
    </div>
  );
}
