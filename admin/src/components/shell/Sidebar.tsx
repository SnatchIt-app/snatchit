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
          <span className="flex items-center gap-2 text-[0.9375rem] font-semibold leading-tight tracking-tight text-white">
            <span aria-hidden="true" className="inline-block h-2 w-2 rounded-full bg-primary" />
            Snatch It
          </span>
          <span className="mt-0.5 block text-[0.75rem] text-white/55">Operations console</span>
        </Link>
      </div>
      <ul className="flex-1 space-y-1 px-3 py-2">
        {NAV.map((item) => {
          const active = isNavActive(pathname, item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`relative flex min-h-[2.5rem] items-center justify-between rounded-[10px] px-3 text-[0.875rem] transition-colors ${
                  active ? "bg-white/[0.10] font-semibold text-white" : "text-white/70 hover:bg-white/[0.06] hover:text-white"
                }`}
              >
                {/* Active is fill AND a red bar — never colour alone. */}
                {active ? <span aria-hidden="true" className="absolute left-0 top-1/2 h-4 w-[3px] -translate-y-1/2 rounded-full bg-primary" /> : null}
                <span>{item.label}</span>
                <kbd aria-hidden="true" className="border-white/20 bg-white/10 text-white/60">
                  g {item.key}
                </kbd>
              </Link>
            </li>
          );
        })}
      </ul>
      <div className="border-t border-white/10 px-5 py-3 text-[0.75rem] text-white/50">
        <p>
          <kbd className="border-white/20 bg-white/10 text-white/70">/</kbd> search · <kbd className="border-white/20 bg-white/10 text-white/70">g</kbd> then a key to jump
        </p>
      </div>
    </nav>
  );
}
