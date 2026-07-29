import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Section heading in the marketing site's grammar: red tracked eyebrow over
 * an Oswald uppercase statement, with the tracked "SEE ALL →" idiom on the
 * right when there's an action.
 */
export function SectionHeader({
  eyebrow,
  title,
  action,
  as: Heading = "h2",
  className = "",
}: {
  eyebrow?: string;
  title: ReactNode;
  action?: { href: string; label: string };
  as?: "h1" | "h2";
  className?: string;
}) {
  return (
    <div className={`mb-8 flex items-end justify-between gap-6 ${className}`}>
      <div>
        {eyebrow ? <p className="eyebrow mb-3 text-primary/80">{eyebrow}</p> : null}
        <Heading className="font-display text-[28px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink sm:text-[34px]">
          {title}
        </Heading>
      </div>
      {action ? (
        <Link
          href={action.href}
          className="group inline-flex min-h-11 shrink-0 items-center gap-1.5 text-[11px] font-medium uppercase tracking-[0.3em] text-white/60 transition-colors duration-200 hover:text-primary motion-reduce:transition-none"
        >
          {action.label}
          <span
            aria-hidden="true"
            className="transition-transform duration-200 group-hover:translate-x-0.5 motion-reduce:transition-none motion-reduce:group-hover:translate-x-0"
          >
            →
          </span>
        </Link>
      ) : null}
    </div>
  );
}
