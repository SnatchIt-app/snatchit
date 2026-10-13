import type { ReactNode } from "react";
import { Icon, type IconName } from "@/components/ui/Icon";

/**
 * Native StateView (empty): optional 56pt round glyph, an Oswald title in its
 * own case, muted body, then the action.
 */
export function EmptyState({
  title,
  message,
  action,
  icon,
  className = "",
  as: Heading = "h2",
}: {
  title: string;
  message?: string;
  action?: ReactNode;
  icon?: IconName;
  className?: string;
  /** h1 when the state is the whole page (not-found, a top-level empty screen). */
  as?: "h1" | "h2" | "h3";
}) {
  return (
    <div className={`flex flex-col items-center px-6 py-14 text-center sm:py-20 ${className}`}>
      {icon ? (
        <span className="mb-5 inline-flex size-14 items-center justify-center rounded-full bg-surface text-ink-2">
          <Icon name={icon} size={26} />
        </span>
      ) : null}
      <Heading className="t-name-state max-w-md text-ink">{title}</Heading>
      {message ? <p className="t-body mt-2.5 max-w-sm text-muted">{message}</p> : null}
      {action ? <div className="mt-7 flex flex-wrap justify-center gap-3">{action}</div> : null}
    </div>
  );
}
