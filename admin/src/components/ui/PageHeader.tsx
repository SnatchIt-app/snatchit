import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";

/**
 * The page's own header row: serif title, a context pill beside it (the
 * reference's "Invite Guests  [Uncommon Presents: The Weekend]"), and the
 * page's actions on the right. The workspace's search and account sit to the
 * right of this row on md+, which is why the row leaves room for them.
 */
export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  meta,
  back,
}: {
  /** What kind of page this is (a section, a record type). Shown as the pill when there is no `meta`. */
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  /** Counts, a period, a status — shown as the pill beside the title. */
  meta?: ReactNode;
  back?: { href: string; label: string };
}) {
  const pill = meta ?? eyebrow;
  return (
    <div className="mb-6 md:pr-[21.5rem]">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        {back ? (
          <Link href={back.href} className="btn-icon" aria-label={back.label} title={back.label}>
            <Icon name="back" />
          </Link>
        ) : null}
        <h1 className="title-page min-w-0 break-words">{title}</h1>
        {pill ? <span className="context-pill">{pill}</span> : null}
      </div>
      {description || actions ? (
        <div className="mt-3 flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
          {description ? <p className="max-w-2xl text-[0.875rem] leading-relaxed text-muted">{description}</p> : <span />}
          {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
        </div>
      ) : null}
    </div>
  );
}
