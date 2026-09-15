"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { NAV, isNavActive } from "@/lib/nav";

/**
 * F9 — navigation below `md` (768 px), where the sidebar is hidden.
 *
 * Disclosure pattern: a real button (aria-expanded / aria-controls) reveals the
 * same sections as the sidebar. Escape closes and returns focus to the button;
 * choosing a section or any navigation (including `g` shortcuts) closes it,
 * because "open" is tied to the pathname it was opened on. No new routes and no
 * data reads — every page still enforces session, aal2 and operator role.
 */
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
    <div className="md:hidden">
      <button
        ref={buttonRef}
        type="button"
        className="btn btn-ghost btn-sm min-h-9"
        aria-expanded={open}
        aria-controls="mobile-nav"
        onClick={() => setOpenedOn(open ? null : pathname)}
      >
        <span aria-hidden="true">{open ? "✕" : "☰"}</span>
        {open ? "Close" : "Menu"}
      </button>
      <MobileNavPanel id="mobile-nav" open={open} pathname={pathname} onNavigate={() => setOpenedOn(null)} />
    </div>
  );
}

export function MobileNavPanel({ id, open, pathname, onNavigate }: { id: string; open: boolean; pathname: string; onNavigate: () => void }) {
  if (!open) return null;
  return (
    <nav id={id} aria-label="Console sections (menu)" className="absolute inset-x-0 top-full max-h-[calc(100dvh-4rem)] overflow-y-auto border-b border-line bg-card shadow-lg md:hidden">
      <ul className="py-1">
        {NAV.map((item) => {
          const active = isNavActive(pathname, item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                onClick={onNavigate}
                aria-current={active ? "page" : undefined}
                className={`flex min-h-11 items-center border-l-2 px-4 text-[15px] font-medium ${
                  active ? "border-primary bg-primary-soft text-ink" : "border-transparent text-muted hover:text-ink"
                }`}
              >
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
