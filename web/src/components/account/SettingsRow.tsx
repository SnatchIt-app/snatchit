import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";
import { UnreadDot } from "@/components/ui/Badge";

/**
 * Native AccountSection: a micro label over a hairline-topped stack. The
 * brand separates groups with a line and vertical rhythm, never a box.
 */
export function AccountSection({
  title,
  children,
  className = "",
}: {
  title: string;
  children: ReactNode;
  className?: string;
}) {
  const id = `section-${title.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`;
  return (
    <section aria-labelledby={id} className={className}>
      <h2 id={id} className="t-micro mb-2 text-muted">
        {title}
      </h2>
      <div className="border-t border-line">{children}</div>
    </section>
  );
}

/** Wrapper for a run of SettingsRow items inside an AccountSection. */
export function SettingsRows({ children }: { children: ReactNode }) {
  return <ul>{children}</ul>;
}

/**
 * Native SettingsRow: the row IS the control. Title, an optional description
 * under it, an optional compact value at the trailing edge, then a chevron,
 * over a bottom hairline. Minimum height 56. Text wraps; nothing truncates.
 */
export function SettingsRow({
  href,
  title,
  description,
  value,
  valueTone = "muted",
  unread = false,
}: {
  href: string;
  title: ReactNode;
  description?: ReactNode;
  value?: ReactNode;
  /** "action" draws the value as the row's call to action (ink, semibold). */
  valueTone?: "muted" | "action";
  /** Shows the brand unread dot after the title. */
  unread?: boolean;
}) {
  return (
    <li className="border-b border-line">
      <Link
        href={href}
        className="pressable group -mx-3 flex min-h-14 items-center gap-3 rounded-control px-3 py-3 hover:bg-surface"
      >
        {/* The value sits at the trailing edge, and drops under the text when the row runs out of room. */}
        <span className="flex min-w-0 flex-1 flex-wrap items-center gap-x-4 gap-y-1">
          <span className="min-w-0 grow basis-48">
            <span className="t-title flex flex-wrap items-center gap-x-2 break-words text-ink">
              {title}
              {unread ? <UnreadDot /> : null}
            </span>
            {description ? <span className="t-body-sm mt-0.5 block text-muted">{description}</span> : null}
          </span>
          {value ? (
            <span
              className={`t-body-sm ml-auto text-right ${valueTone === "action" ? "font-semibold text-ink" : "text-muted"}`}
            >
              {value}
            </span>
          ) : null}
        </span>
        <Icon name="chevronRight" size={18} strokeWidth={2} className="text-faint group-hover:text-muted" />
      </Link>
    </li>
  );
}
