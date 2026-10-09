import Link from "next/link";
import type { ReactNode } from "react";
import { EventArt } from "@/components/ui/EventArt";

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
export function Page({ eyebrow, title, lead, action, art, children }: { eyebrow?: string; title: string; lead?: ReactNode; action?: ReactNode; /** An event title to draw as artwork beside the header. */ art?: string; children: ReactNode }) {
  return (
    <div>
      <header className={`enter pb-8 ${art ? "grid gap-x-6 gap-y-5 md:grid-cols-[6.5rem_minmax(0,1fr)]" : ""}`}>
        {art ? <EventArt title={art} className="hidden aspect-[3/4] w-full rounded-[4px] shadow-[0_18px_30px_-20px_rgba(30,20,10,0.6)] md:block" /> : null}
        <div className="flex flex-wrap items-end justify-between gap-x-8 gap-y-5">
          <div className="flex min-w-0 gap-4">
            {art ? <EventArt title={art} variant="thumb" className="h-14 w-14 shrink-0 overflow-hidden rounded-[6px] md:hidden" /> : null}
            <div className="min-w-0">
            {eyebrow ? <p className="eyebrow-caps">{eyebrow}</p> : null}
            <h1 className={`title-page ${eyebrow ? "mt-3" : ""}`}>{title}</h1>
            {lead ? <p className="mt-3 max-w-2xl text-[0.9375rem] leading-relaxed text-muted">{lead}</p> : null}
            </div>
          </div>
          {action ? <div className="flex shrink-0 flex-wrap items-center gap-2.5">{action}</div> : null}
        </div>
      </header>
      <div className="enter-2 space-y-6">{children}</div>
    </div>
  );
}

/** A section of the page: a quiet panel with an editorial heading and its one action. */
export function Block({ title, lead, action, children, id }: { title?: string; lead?: ReactNode; action?: ReactNode; children: ReactNode; id?: string }) {
  const headingId = id ? `${id}-heading` : undefined;
  return (
    <section aria-labelledby={headingId} id={id} className="panel px-5 pb-5 pt-5 md:px-6">
      {title ? (
        <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-2">
          <h2 id={headingId} className="title-section">
            {title}
          </h2>
          {action ? <div className="shrink-0">{action}</div> : null}
        </div>
      ) : null}
      {lead ? <p className="mt-2 max-w-2xl text-[0.875rem] leading-relaxed text-muted">{lead}</p> : null}
      <div className={title || lead ? "mt-4" : ""}>{children}</div>
    </section>
  );
}

/** Hairline-divided rows — the site's event list, which is also what a dashboard list wants. */
export function Rows({ children }: { children: ReactNode }) {
  return <ul className="divide-y divide-line border-t border-line">{children}</ul>;
}

/**
 * One row: the name of the thing in display type, a meta line under it, and
 * at most one action on the right. Everything else belongs further down the
 * page, not in the row.
 */
export function Row({
  title,
  href,
  meta,
  badge,
  right,
  leading,
  serif = false,
  children,
}: {
  title: string;
  href?: string;
  meta?: ReactNode;
  badge?: ReactNode;
  right?: ReactNode;
  /** Artwork or an icon before the text. */
  leading?: ReactNode;
  /** Set the name in the editorial serif (events, venues). */
  serif?: boolean;
  children?: ReactNode;
}) {
  const cls = serif ? "serif text-[1.125rem] leading-tight" : "item-title";
  const name = href ? (
    <Link href={href} className={`${cls} underline-offset-4 transition-colors hover:underline`}>
      {title}
    </Link>
  ) : (
    <span className={cls}>{title}</span>
  );
  return (
    <li className="flex flex-wrap items-center gap-x-4 gap-y-2 py-3.5">
      {leading ? <div className="shrink-0">{leading}</div> : null}
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          {name}
          {badge}
        </div>
        {meta ? <p className="mt-0.5 text-[0.8125rem] text-muted">{meta}</p> : null}
        {children}
      </div>
      {right ? <div className="shrink-0">{right}</div> : null}
    </li>
  );
}

/** The primary action — warm black, once per section. */
export function Action({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link className="btn btn-primary" href={href}>
      {children}
    </Link>
  );
}

/** A secondary way on: a quiet link with a chevron. */
export function ArrowLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link className="arrow-link" href={href}>
      {children}
      <svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M9 18l6-6-6-6" />
      </svg>
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
          <dt className="text-[0.875rem] text-muted">{f.label}</dt>
          <dd>
            <span className="font-medium tabular-nums">{f.value}</span>
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
      <summary className="arrow-link cursor-pointer rounded-lg">{summary}</summary>
      <div className="mt-3 text-sm text-muted">{children}</div>
    </details>
  );
}
