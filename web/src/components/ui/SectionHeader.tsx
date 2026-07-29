import Link from "next/link";
import type { ReactNode } from "react";

export function SectionHeader({
  eyebrow,
  title,
  action,
  className = "",
}: {
  eyebrow?: string;
  title: ReactNode;
  action?: { href: string; label: string };
  className?: string;
}) {
  return (
    <div className={`mb-10 flex items-end justify-between gap-6 ${className}`}>
      <div>
        {eyebrow ? <p className="u-label mb-3 text-primary">{eyebrow}</p> : null}
        <h2 className="text-[26px] font-bold leading-[1.05] tracking-[-0.02em] text-ink sm:text-[32px]">
          {title}
        </h2>
      </div>
      {action ? (
        <Link
          href={action.href}
          className="u-label inline-flex min-h-11 shrink-0 items-center gap-1.5 text-muted transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
        >
          {action.label}
          <span aria-hidden="true" className="text-[13px] leading-none">→</span>
        </Link>
      ) : null}
    </div>
  );
}
