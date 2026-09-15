"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV, isNavActive } from "@/lib/nav";

export { NAV };

export function Sidebar() {
  const pathname = usePathname();
  return (
    <nav aria-label="Console sections" className="flex h-full flex-col">
      <div className="px-5 pb-4 pt-5">
        <Link href="/" className="block">
          <span className="block text-[17px] font-bold leading-tight text-ink">
            Snatch It<span className="text-primary-ink">.</span>
          </span>
          <span className="block text-[13px] text-dim">Operations console</span>
        </Link>
      </div>
      <ul className="flex-1 space-y-0.5 px-3 py-2">
        {NAV.map((item) => {
          const active = isNavActive(pathname, item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`flex items-center justify-between rounded-[var(--radius-control)] px-3 py-2 text-[14px] transition-colors ${
                  active ? "bg-primary-soft font-semibold text-primary-ink" : "text-muted hover:bg-raised hover:text-ink"
                }`}
              >
                <span>{item.label}</span>
                <kbd aria-hidden="true">
                  g {item.key}
                </kbd>
              </Link>
            </li>
          );
        })}
      </ul>
      <div className="border-t border-line px-5 py-3 text-[12px] text-dim">
        <p>
          <kbd>/</kbd> search · <kbd>g</kbd> then a key to jump
        </p>
      </div>
    </nav>
  );
}
