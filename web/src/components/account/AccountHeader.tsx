import type { ReactNode } from "react";
import { BackLink } from "@/components/ui/BackLink";

type Back = {
  href: string;
  /** Accessible name of the back chip. */
  label: string;
  /** Visible text — renders the text back link instead of the round chip. */
  text?: ReactNode;
  /**
   * Keep the back link on desktop too. Sections in the sidebar hide it at lg+
   * (the sidebar is the way back); pushed screens such as a listing edit keep it.
   */
  desktop?: boolean;
};

const TO_ACCOUNT: Back = { href: "/account", label: "Back to your account" };

/**
 * Account sub-page header: on phones the native pushed-screen back chip (to
 * the /account hub), then the page title — display type, larger on desktop.
 * Titles wrap (and hyphenate) rather than overflow at narrow widths and 200%
 * zoom. `action` sits beside the title and drops under it when space runs out.
 */
export function AccountHeader({
  title,
  action,
  back = TO_ACCOUNT,
}: {
  title: ReactNode;
  action?: ReactNode;
  back?: Back | null;
}) {
  return (
    <div className="mb-6 lg:mb-8">
      {back ? (
        <div className={`mb-3 ${back.desktop ? "" : "lg:hidden"}`}>
          {back.text ? (
            <BackLink href={back.href} label={back.label} variant="text">
              {back.text}
            </BackLink>
          ) : (
            <BackLink href={back.href} label={back.label} />
          )}
        </div>
      ) : null}
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
        <h1 className="t-display-md min-w-0 break-words hyphens-auto text-ink lg:t-display-lg">{title}</h1>
        {action ? <div className="max-w-full shrink-0">{action}</div> : null}
      </div>
    </div>
  );
}
