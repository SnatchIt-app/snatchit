import type { ReactNode } from "react";

/**
 * Empty state in the marketing site's grammar: no box, no icon — an Oswald
 * statement between red hairlines with body copy and a square action.
 */
export function EmptyState({
  title,
  message,
  action,
}: {
  title: string;
  message?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center border-y border-primary/15 px-6 py-20 text-center">
      <h3 className="font-display text-[26px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink sm:text-[30px]">
        {title}
      </h3>
      {message ? (
        <p className="mt-4 max-w-sm text-[14px] leading-relaxed text-muted">{message}</p>
      ) : null}
      {action ? <div className="mt-7">{action}</div> : null}
    </div>
  );
}
