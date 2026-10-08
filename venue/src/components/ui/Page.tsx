import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Layout primitives, taken from the marketing site's white sections
 * (snatchitapp.com, measured 2026-10-06 — see the header of globals.css for
 * the reference sections and tokens).
 *
 * What the site does that this dashboard did not:
 *   · No boxed cards. Sections are separated by white space and a heading,
 *     and lists are hairline-divided rows — "border-y + divide-y rows", never
 *     a grid of panels.
 *   · One obvious action per block, as a filled black-on-red button. Every
 *     other action is a tracked uppercase text link with an arrow.
 *   · Generous vertical rhythm. The site runs py-40 between sections; a
 *     dashboard needs to be denser than a landing page, so this is scaled to
 *     roughly half, but it is space rather than borders doing the separating.
 */

/** The page frame: eyebrow, display title, the one thing to do, a lead line. */
export function Page({ eyebrow, title, lead, action, children }: { eyebrow?: string; title: string; lead?: ReactNode; action?: ReactNode; children: ReactNode }) {
  return (
    <div>
      <header className="pb-6">
        <div className="flex flex-wrap items-end justify-between gap-x-8 gap-y-4">
          <div className="min-w-0">
            {eyebrow ? <p className="eyebrow-accent">{eyebrow}</p> : null}
            <h1 className={`display display-xl ${eyebrow ? "mt-1.5" : ""}`}>{title}</h1>
            {lead ? <p className="mt-4 max-w-xl text-base leading-relaxed text-muted">{lead}</p> : null}
          </div>
          {action ? <div className="shrink-0">{action}</div> : null}
        </div>
      </header>
      <div className="space-y-6">{children}</div>
    </div>
  );
}

/** A block of the page. No border, no card — a heading and room to breathe. */
export function Block({ title, lead, action, children, id }: { title?: string; lead?: ReactNode; action?: ReactNode; children: ReactNode; id?: string }) {
  const headingId = id ? `${id}-heading` : undefined;
  return (
    <section aria-labelledby={headingId} id={id} className="panel p-5 md:p-6">
      {title ? (
        <div className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
          <h2 id={headingId} className="display display-lg">
            {title}
          </h2>
          {action ? <div className="shrink-0">{action}</div> : null}
        </div>
      ) : null}
      {lead ? <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted">{lead}</p> : null}
      <div className={title || lead ? "mt-4" : ""}>{children}</div>
    </section>
  );
}

/** Hairline-divided rows — the site's event list, which is also what a dashboard list wants. */
export function Rows({ children }: { children: ReactNode }) {
  return <ul className="divide-y divide-line">{children}</ul>;
}

/**
 * One row: the name of the thing in display type, a meta line under it, and
 * at most one action on the right. Everything else belongs further down the
 * page, not in the row.
 */
export function Row({ title, href, meta, badge, right, children }: { title: string; href?: string; meta?: ReactNode; badge?: ReactNode; right?: ReactNode; children?: ReactNode }) {
  const name = href ? (
    <Link href={href} className="item-title transition-colors hover:text-primary-ink">
      {title}
    </Link>
  ) : (
    <span className="item-title">{title}</span>
  );
  return (
    <li className="flex flex-wrap items-baseline gap-x-4 gap-y-2 py-4">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          {name}
          {badge}
        </div>
        {meta ? <p className="mt-1.5 text-sm text-muted">{meta}</p> : null}
        {children}
      </div>
      {right ? <div className="shrink-0">{right}</div> : null}
    </li>
  );
}

/** The primary action. Filled, black on red — the site's own CTA, once per block. */
export function Action({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link className="btn btn-primary" href={href}>
      {children}
    </Link>
  );
}

/** Every other action: the site has no filled secondary, only a tracked link with an arrow. */
export function ArrowLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link className="arrow-link" href={href}>
      {children} <span aria-hidden="true">→</span>
    </Link>
  );
}

/**
 * Supporting numbers, kept below the thing they support. The site's own
 * definition-list grid: a tracked label column and the value beside it. Each
 * figure carries the sentence that says what it counts — that rule does not
 * relax because the layout got simpler.
 */
export function Facts({ items }: { items: { label: string; value: string; meaning?: string }[] }) {
  return (
    <dl className="divide-y divide-line">
      {items.map((f) => (
        <div key={f.label} className="grid gap-x-8 gap-y-1 py-3 sm:grid-cols-[14rem_1fr]">
          <dt className="text-sm text-muted">{f.label}</dt>
          <dd>
            <span className="font-semibold tabular-nums">{f.value}</span>
            {f.meaning ? <span className="block text-sm text-dim">{f.meaning}</span> : null}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/** Technical or secondary detail, collapsed. Available, never in the way. */
export function Detail({ summary, children }: { summary: string; children: ReactNode }) {
  return (
    <details className="border-t border-line pt-3">
      <summary className="arrow-link cursor-pointer">{summary}</summary>
      <div className="mt-3 text-sm text-muted">{children}</div>
    </details>
  );
}
