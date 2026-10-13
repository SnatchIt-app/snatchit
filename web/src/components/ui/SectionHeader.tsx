import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";

/**
 * Native section label: a short bold label over a hairline ("Tonight",
 * "This week"), with an optional quiet action on the right. `eyebrow` adds the
 * native micro label above for page-level sections.
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
  as?: "h1" | "h2" | "h3";
  className?: string;
}) {
  return (
    <div className={`mb-1 border-b border-line pb-2.5 ${className}`}>
      {eyebrow ? <p className="t-micro mb-1.5 text-muted">{eyebrow}</p> : null}
      <div className="flex items-end justify-between gap-4">
        <Heading className="t-section text-ink-2">{title}</Heading>
        {action ? (
          <Link
            href={action.href}
            className="group -mb-1 inline-flex min-h-9 shrink-0 items-center gap-0.5 text-[14px] font-semibold text-ink hover:underline underline-offset-4"
          >
            {action.label}
            <Icon name="chevronRight" size={16} strokeWidth={2.2} />
          </Link>
        ) : null}
      </div>
    </div>
  );
}

/** Page title block for top-level screens (native tab-root header, larger on desktop). */
export function PageTitle({
  eyebrow,
  title,
  description,
  action,
  className = "",
}: {
  eyebrow?: string;
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <div className={`flex flex-wrap items-end justify-between gap-x-6 gap-y-4 ${className}`}>
      <div className="min-w-0">
        {eyebrow ? <p className="t-micro mb-2 text-muted">{eyebrow}</p> : null}
        <h1 className="t-display-lg text-ink">{title}</h1>
        {description ? <p className="t-body mt-2 max-w-xl text-muted">{description}</p> : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </div>
  );
}
