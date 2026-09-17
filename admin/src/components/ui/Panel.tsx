import type { ReactNode } from "react";

export function Panel({
  title,
  eyebrow,
  actions,
  children,
  className = "",
}: {
  title?: ReactNode;
  eyebrow?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`border border-line bg-card ${className}`}>
      {title || eyebrow || actions ? (
        <header className="flex flex-wrap items-end justify-between gap-2 border-b border-line px-4 py-3">
          <div>
            {eyebrow ? <p className="eyebrow text-dim">{eyebrow}</p> : null}
            {title ? <h2 className="text-[15px] font-semibold text-ink">{title}</h2> : null}
          </div>
          {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
        </header>
      ) : null}
      <div className="p-4">{children}</div>
    </section>
  );
}
