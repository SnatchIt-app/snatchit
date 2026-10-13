"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { UnreadDot } from "@/components/ui/Badge";
import { ACCOUNT_GROUPS, isAccountLinkActive } from "@/components/account/sections";

/**
 * Desktop account sidebar (lg+). Grouped like the native settings hub, each
 * group a micro label over its links; the current page sits on the native
 * selected capsule. Phones have no strip at all — /account is the hub there.
 */
export function AccountNav({ unreadCount = 0 }: { unreadCount?: number }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Account" className="space-y-7">
      {ACCOUNT_GROUPS.map((group) => {
        const labelId = `account-nav-${group.label.toLowerCase()}`;
        return (
          <div key={group.label}>
            <p id={labelId} className="t-micro mb-2 px-4 text-muted">
              {group.label}
            </p>
            <ul aria-labelledby={labelId} className="space-y-0.5">
              {group.links.map((link) => {
                const active = isAccountLinkActive(link.href, pathname);
                return (
                  <li key={link.href}>
                    <Link
                      href={link.href}
                      aria-current={active ? "page" : undefined}
                      className={`pressable flex min-h-11 items-center gap-2 rounded-full px-4 text-[15px] font-semibold ${
                        active ? "bg-ink/[0.07] text-ink" : "text-ink-2 hover:bg-ink/[0.04] hover:text-ink"
                      }`}
                    >
                      <span className="min-w-0 break-words">{link.label}</span>
                      {link.showsUnread && unreadCount > 0 ? <UnreadDot /> : null}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        );
      })}
    </nav>
  );
}
