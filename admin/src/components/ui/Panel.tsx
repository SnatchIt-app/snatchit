import type { ReactNode } from "react";

export function Panel({
  title,
  eyebrow,
  actions,
  children,
  className = "",
  description,
  flush = false,
}: {
  title?: ReactNode;
  eyebrow?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
  /** One line under the title (units, range, definition). */
  description?: ReactNode;
  /** No body padding — for tables that run edge to edge. */
  flush?: boolean;
}) {
  return (
    <section className={`rounded-[var(--radius-card)] border border-line bg-card ${className}`}>
      {title || eyebrow || actions ? (
        <header className="flex flex-wrap items-start justify-between gap-3 px-5 pb-3 pt-4">
          <div className="min-w-0">
            {eyebrow ? <p className="eyebrow text-dim">{eyebrow}</p> : null}
            {title ? <h2 className="text-[16px] font-semibold leading-snug text-ink">{title}</h2> : null}
            {description ? <p className="mt-0.5 text-[13px] text-dim">{description}</p> : null}
          </div>
          {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
        </header>
      ) : null}
      <div className={flush ? "" : "px-5 pb-5 pt-1"}>{children}</div>
    </section>
  );
}
