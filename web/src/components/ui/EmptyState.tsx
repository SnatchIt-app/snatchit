import type { ReactNode } from "react";

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
    <div className="flex flex-col items-center justify-center rounded-card border border-dashed border-line-strong bg-card/50 px-6 py-16 text-center">
      <svg aria-hidden="true" viewBox="0 0 48 48" fill="none" className="mb-4 size-10 text-dim">
        <rect x="6" y="14" width="36" height="20" rx="4" stroke="currentColor" strokeWidth="2.5" />
        <path d="M6 22c3 0 3 4 0 4M42 22c-3 0-3 4 0 4" stroke="currentColor" strokeWidth="2.5" />
        <path d="M29 14v20" stroke="currentColor" strokeWidth="2.5" strokeDasharray="3 4" />
      </svg>
      <h3 className="text-base font-semibold text-ink">{title}</h3>
      {message ? <p className="mt-1.5 max-w-sm text-sm text-muted">{message}</p> : null}
      {action ? <div className="mt-5">{action}</div> : null}
    </div>
  );
}
