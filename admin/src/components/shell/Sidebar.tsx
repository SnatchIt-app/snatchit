"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV, isNavActive } from "@/lib/nav";

export { NAV };

export function Sidebar() {
  const pathname = usePathname();
  return (
    <nav aria-label="Console sections" className="flex h-full flex-col">
      <div className="border-b border-line px-4 py-4">
        <Link href="/" className="block">
          <span className="block text-[17px] font-black uppercase tracking-[0.2em] text-primary">Snatch It</span>
          <span className="eyebrow block text-dim">Operating console</span>
        </Link>
      </div>
      <ul className="flex-1 py-2">
        {NAV.map((item) => {
          const active = isNavActive(pathname, item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`flex items-center justify-between border-l-2 px-4 py-2 text-[13px] font-medium transition-colors ${
                  active ? "border-primary bg-primary-soft text-ink" : "border-transparent text-muted hover:text-ink"
                }`}
              >
                <span>{item.label}</span>
                <kbd aria-hidden="true" className="opacity-60">
                  g {item.key}
                </kbd>
              </Link>
            </li>
          );
        })}
      </ul>
      <div className="border-t border-line-neutral px-4 py-3 text-[11px] text-dim">
        <p>
          <kbd>/</kbd> search · <kbd>g</kbd> then a key to jump
        </p>
      </div>
    </nav>
  );
}
