import type { ReactNode } from "react";

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  meta,
}: {
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  /** Freshness line, counts, etc. Rendered under the title in muted text. */
  meta?: ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4 border-b border-line pb-4">
      <div className="min-w-0">
        {eyebrow ? <p className="eyebrow text-primary">{eyebrow}</p> : null}
        <h1 className="mt-1 text-2xl font-bold tracking-tight text-ink">{title}</h1>
        {description ? <p className="mt-1 max-w-2xl text-[13px] text-muted">{description}</p> : null}
        {meta ? <div className="mt-2 text-[12px] text-dim">{meta}</div> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
