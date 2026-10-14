"use client";

import { Button } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";

/** Native StateView (error): warning glyph, title, muted body, Retry. */
export function ErrorState({
  title = "Couldn't load this",
  message = "Something went wrong on our side. Try again in a moment.",
  onRetry,
  retryLabel = "Try again",
  as: Heading = "h2",
}: {
  title?: string;
  message?: string;
  onRetry?: () => void;
  retryLabel?: string;
  /** h1 when the error replaces the whole page (app/error.tsx). */
  as?: "h1" | "h2";
}) {
  return (
    <div role="alert" className="flex flex-col items-center px-6 py-14 text-center sm:py-20">
      <span className="mb-5 inline-flex size-14 items-center justify-center rounded-full bg-surface text-danger">
        <Icon name="alert" size={26} />
      </span>
      <Heading className="t-name-state max-w-md text-ink">{title}</Heading>
      <p className="t-body mt-2.5 max-w-sm text-muted">{message}</p>
      {onRetry ? (
        <Button variant="secondary" className="mt-7" onClick={onRetry}>
          {retryLabel}
        </Button>
      ) : null}
    </div>
  );
}
