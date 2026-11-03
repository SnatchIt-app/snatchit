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
    <section className={`panel min-w-0 ${className}`}>
      {title || eyebrow || actions ? (
        <header className="flex flex-wrap items-start justify-between gap-3 px-5 pb-3 pt-5 md:px-6">
          <div className="min-w-0">
            {eyebrow ? <p className="kicker">{eyebrow}</p> : null}
            {title ? <h2 className="title-section">{title}</h2> : null}
            {description ? <p className="mt-1 text-[0.8125rem] text-muted">{description}</p> : null}
          </div>
          {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
        </header>
      ) : null}
      <div className={flush ? "" : "px-5 pb-5 pt-1 md:px-6"}>{children}</div>
    </section>
  );
}
