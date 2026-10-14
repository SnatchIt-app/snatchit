"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

/** Which top-level section a path belongs to (shared by the header and the dock). */
export function sectionFor(pathname: string): "home" | "browse" | "sell" | "purchases" | "account" | null {
  if (pathname === "/") return "home";
  if (pathname.startsWith("/browse")) return "browse";
  if (pathname.startsWith("/sell")) return "sell";
  if (pathname.startsWith("/account/purchases")) return "purchases";
  if (pathname.startsWith("/account")) return "account";
  return null;
}

/** Desktop header link with the native selected-capsule treatment. */
export function HeaderNavLink({
  href,
  section,
  children,
}: {
  href: string;
  section: ReturnType<typeof sectionFor>;
  children: ReactNode;
}) {
  const active = sectionFor(usePathname()) === section;
  return (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      className={`pressable inline-flex min-h-10 items-center rounded-full px-4 text-[15px] font-semibold ${
        active ? "bg-ink/[0.07] text-ink" : "text-ink-2 hover:text-ink"
      }`}
    >
      {children}
    </Link>
  );
}

/** The header search hides on /browse, which has its own full-width search field. */
export function HideOnBrowse({ children }: { children: ReactNode }) {
  return usePathname().startsWith("/browse") ? null : <>{children}</>;
}
