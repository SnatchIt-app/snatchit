import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";

/**
 * The page's own header: what kind of page this is (overline), a large title,
 * a context pill (counts, a period, a status), one line of explanation, and
 * the page's actions on the right.
 */
export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  meta,
  back,
}: {
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  meta?: ReactNode;
  back?: { href: string; label: string };
}) {
  return (
    <div className="enter mb-6 flex flex-wrap items-end justify-between gap-x-8 gap-y-4 md:mb-8">
      <div className="min-w-0">
        {back || eyebrow ? (
          <p className="mb-2 flex items-center gap-2">
            {back ? (
              <Link href={back.href} className="btn-icon h-8 w-8" aria-label={back.label} title={back.label}>
                <Icon name="back" size={16} />
              </Link>
            ) : null}
            {eyebrow ? <span className="kicker">{eyebrow}</span> : null}
          </p>
        ) : null}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <h1 className="title-page min-w-0 break-words">{title}</h1>
          {meta ? <span className="context-pill">{meta}</span> : null}
        </div>
        {description ? <p className="mt-2 max-w-2xl text-[0.9375rem] leading-relaxed text-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
