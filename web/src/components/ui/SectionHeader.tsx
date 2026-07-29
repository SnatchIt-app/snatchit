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
    <div className={`mb-8 flex items-end justify-between gap-6 ${className}`}>
      <div>
        {eyebrow ? <p className="eyebrow mb-2.5 text-primary">{eyebrow}</p> : null}
        <h2 className="text-[26px] font-extrabold leading-[1.05] tracking-[-0.02em] text-ink sm:text-[30px]">
          {title}
        </h2>
      </div>
      {action ? (
        <Link
          href={action.href}
          className="group inline-flex min-h-11 shrink-0 items-center gap-1.5 text-[14px] font-bold text-white/70 transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
        >
          {action.label}
          <span
            aria-hidden="true"
            className="transition-transform duration-150 group-hover:translate-x-0.5 motion-reduce:transition-none motion-reduce:group-hover:translate-x-0"
          >
            →
          </span>
        </Link>
      ) : null}
    </div>
  );
}
