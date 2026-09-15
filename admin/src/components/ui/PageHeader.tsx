import type { ReactNode } from "react";

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  meta,
}: {
  /** Short context above the title (section or record type), sentence case. */
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  /** Freshness line, counts, etc. Rendered under the title in muted text. */
  meta?: ReactNode;
}) {
  return (
    <div className="mb-8 flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
      <div className="min-w-0">
        {eyebrow ? <p className="eyebrow text-dim">{eyebrow}</p> : null}
        <h1 className="mt-0.5 text-[26px] font-semibold leading-tight tracking-[-0.01em] text-ink">{title}</h1>
        {description ? <p className="mt-2 max-w-3xl text-[14px] leading-relaxed text-muted">{description}</p> : null}
        {meta ? <div className="mt-2 text-[13px] text-dim">{meta}</div> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
