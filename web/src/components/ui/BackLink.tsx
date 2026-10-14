"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";
import { iconButtonClasses } from "@/components/ui/Button";
import { hasInAppHistory } from "@/lib/nav-history";

/**
 * Back affordance for pushed screens (native 44pt round back chip). When the
 * visitor reached this page from another page of this site — by an in-app
 * navigation (NavTracker) or a same-origin page load — it steps back through
 * history, so filters, scroll position and form state on the previous page
 * survive. Opened directly (a shared link, a new tab), it goes to `href`.
 */
export function BackLink({
  href,
  label,
  variant = "chip",
  children,
}: {
  href: string;
  label: string;
  variant?: "chip" | "text";
  children?: ReactNode;
}) {
  const router = useRouter();
  function onClick(e: React.MouseEvent<HTMLAnchorElement>) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    let sameOrigin = false;
    try {
      sameOrigin = !!document.referrer && new URL(document.referrer).origin === window.location.origin;
    } catch {
      sameOrigin = false;
    }
    if (hasInAppHistory() || (sameOrigin && window.history.length > 1)) {
      e.preventDefault();
      router.back();
    }
  }
  if (variant === "text") {
    return (
      <Link
        href={href}
        onClick={onClick}
        className="group -ml-2 inline-flex min-h-11 items-center gap-1 rounded-full pl-1 pr-3 text-[15px] font-semibold text-ink hover:bg-ink/[0.06]"
      >
        <Icon name="chevronLeft" size={20} strokeWidth={2.2} />
        {children ?? label}
      </Link>
    );
  }
  return (
    <Link href={href} onClick={onClick} aria-label={label} className={iconButtonClasses("chip")}>
      <Icon name="chevronLeft" size={22} strokeWidth={2.2} />
    </Link>
  );
}
