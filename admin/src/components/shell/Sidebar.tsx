"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV, isNavActive } from "@/lib/nav";
import { Icon } from "@/components/ui/Icon";

export { NAV };

/**
 * The rail — the same narrow dark column as the venue dashboard. Labels sit
 * under the icons (never icon-only); the `g` shortcut is in each tooltip.
 */
export function Sidebar() {
  const pathname = usePathname();
  return (
    <nav aria-label="Console sections" className="on-frame flex h-full flex-col items-center py-4">
      <Link href="/" className="grid h-11 w-11 place-items-center rounded-full bg-white" title="Snatch It · Operations console">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/sn-logo.svg" alt="Snatch It — Today" width={26} height={10} className="h-auto w-[1.6rem]" />
      </Link>
      <ul className="mt-6 flex flex-col items-center gap-1.5">
        {NAV.map((item) => {
          const active = isNavActive(pathname, item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                title={`${item.label} — press g then ${item.key}`}
                className="group flex w-[4.75rem] flex-col items-center gap-1 rounded-2xl py-1"
              >
                <span
                  className={`grid h-10 w-10 place-items-center rounded-full transition-colors ${
                    active ? "bg-white text-[#0f0f10]" : "text-white/70 group-hover:bg-white/10 group-hover:text-white"
                  }`}
                >
                  <Icon name={item.icon} size={18} />
                </span>
                <span className={`text-[0.6875rem] leading-tight ${active ? "font-semibold text-white" : "text-white/70 group-hover:text-white"}`}>{item.short ?? item.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
