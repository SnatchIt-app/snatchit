"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { NAV, isNavActive } from "@/lib/nav";
import { Icon } from "@/components/ui/Icon";

/**
 * Below `md` (768 px) the rail becomes a floating tab bar: the four sections an
 * operator lives in, plus "More", which opens every section as a sheet.
 *
 * "More" keeps the F9 disclosure contract: a real button (aria-expanded /
 * aria-controls); Escape closes and returns focus to it; choosing a section or
 * any navigation (including `g` shortcuts) closes it, because "open" is tied
 * to the pathname it was opened on. No new routes and no data reads.
 */
export function MobileTabBar() {
  const pathname = usePathname() ?? "/";
  const primary = NAV.filter((n) => n.primary);
  return (
    <div className="fixed inset-x-3 bottom-3 z-40 lg:hidden">
      <nav aria-label="Main sections" className="glass rounded-[26px] p-1.5">
        <ul className="flex items-stretch">
          {primary.map((item) => {
            const on = isNavActive(pathname, item.href);
            return (
              <li key={item.href} className="min-w-0 flex-1">
                <Link
                  href={item.href}
                  aria-current={on ? "page" : undefined}
                  className={`flex min-h-[3.25rem] flex-col items-center justify-center gap-0.5 rounded-[20px] px-1 transition-colors ${on ? "bg-ink text-white" : "text-[rgba(28,25,23,0.72)] hover:bg-[rgba(28,25,23,0.05)]"}`}
                >
                  <Icon name={item.icon} size={19} />
                  <span className={`truncate text-[0.6875rem] leading-tight ${on ? "font-semibold" : ""}`}>{item.short ?? item.label}</span>
                </Link>
              </li>
            );
          })}
          <li className="min-w-0 flex-1">
            <MobileNav />
          </li>
        </ul>
      </nav>
    </div>
  );
}

export function MobileNav() {
  const pathname = usePathname() ?? "/";
  const [openedOn, setOpenedOn] = useState<string | null>(null);
  const open = openedOn === pathname;
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      setOpenedOn(null);
      buttonRef.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <div className="lg:hidden">
      <button
        ref={buttonRef}
        type="button"
        className={`flex min-h-[3.25rem] w-full flex-col items-center justify-center gap-0.5 rounded-[20px] px-1 transition-colors ${open ? "bg-ink text-white" : "text-[rgba(28,25,23,0.72)] hover:bg-[rgba(28,25,23,0.05)]"}`}
        aria-expanded={open}
        aria-controls="mobile-nav"
        aria-label={open ? "Close the list of sections" : "All sections"}
        onClick={() => setOpenedOn(open ? null : pathname)}
      >
        <Icon name={open ? "close" : "menu"} size={19} />
        <span className="text-[0.6875rem] leading-tight">{open ? "Close" : "More"}</span>
      </button>
      <MobileNavPanel id="mobile-nav" open={open} pathname={pathname} onNavigate={() => setOpenedOn(null)} />
    </div>
  );
}

export function MobileNavPanel({ id, open, pathname, onNavigate }: { id: string; open: boolean; pathname: string; onNavigate: () => void }) {
  if (!open) return null;
  return (
    <nav id={id} aria-label="Console sections (menu)" className="glass popover absolute inset-x-0 bottom-[calc(100%+0.5rem)] max-h-[70dvh] overflow-y-auto rounded-[24px] p-2 lg:hidden">
      <ul className="grid grid-cols-2 gap-1">
        {NAV.map((item) => {
          const active = isNavActive(pathname, item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                onClick={onNavigate}
                aria-current={active ? "page" : undefined}
                className={`flex min-h-12 items-center gap-3 rounded-2xl px-3 text-[0.9375rem] font-medium transition-colors ${active ? "bg-ink text-white" : "text-ink hover:bg-[rgba(28,25,23,0.05)]"}`}
              >
                <Icon name={item.icon} size={18} />
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
