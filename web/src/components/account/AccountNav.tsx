"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { UnreadDot } from "@/components/ui/Badge";

const TABS = [
  { href: "/account", label: "Overview" },
  { href: "/account/listings", label: "Listings" },
  { href: "/account/purchases", label: "Purchases" },
  { href: "/account/profile", label: "Profile" },
  { href: "/account/saved", label: "Saved" },
  { href: "/account/notifications", label: "Notifications" },
  { href: "/account/settings", label: "Settings" },
] as const;

export function AccountNav({ unreadCount = 0 }: { unreadCount?: number }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Account" className="flex gap-6 overflow-x-auto border-b border-primary/15">
      {TABS.map((tab) => {
        const active = tab.href === "/account" ? pathname === "/account" : pathname.startsWith(tab.href);
        return (
          <Link
            key={tab.href}
            href={tab.href}
            aria-current={active ? "page" : undefined}
            className={`inline-flex min-h-11 shrink-0 items-center gap-2 border-b-2 text-[11px] font-medium uppercase tracking-[0.25em] transition-colors duration-200 motion-reduce:transition-none ${
              active ? "border-primary text-primary" : "border-transparent text-white/50 hover:text-white/80"
            }`}
          >
            {tab.label}
            {tab.href === "/account/notifications" && unreadCount > 0 ? <UnreadDot /> : null}
          </Link>
        );
      })}
    </nav>
  );
}
