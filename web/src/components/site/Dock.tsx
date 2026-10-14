"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Icon, type IconName } from "@/components/ui/Icon";
import { sectionFor } from "@/components/site/NavLinks";

type Item = { href: string; label: string; icon: IconName; section: ReturnType<typeof sectionFor> };

/**
 * Phone navigation — the native AdaptiveDock on the web: a floating capsule
 * (66 tall, radius 33, 16 from the sides) in the translucent dock material,
 * with the active item on an inner selected capsule. Like the native dock it
 * collapses to a pill showing only the active item after a sustained scroll
 * down, expands again on a scroll up or near the top, and steps aside while
 * the on-screen keyboard is up.
 *
 * Shown on the top-level screens only. Pushed screens (a listing, checkout, a
 * transfer, sign-in) carry their own bottom action bar instead, as in the app.
 */
const SIGNED_IN: Item[] = [
  { href: "/", label: "Home", icon: "home", section: "home" },
  { href: "/browse", label: "Search", icon: "search", section: "browse" },
  { href: "/sell", label: "Sell", icon: "plus", section: "sell" },
  { href: "/account/purchases", label: "Purchases", icon: "receipt", section: "purchases" },
  { href: "/account", label: "You", icon: "user", section: "account" },
];
const SIGNED_OUT: Item[] = [
  { href: "/", label: "Home", icon: "home", section: "home" },
  { href: "/browse", label: "Search", icon: "search", section: "browse" },
  { href: "/sell", label: "Sell", icon: "plus", section: "sell" },
  { href: "/login", label: "Log in", icon: "user", section: null },
];

/** Routes whose screen owns the bottom edge (sticky purchase bar, forms with the keyboard up). */
export function dockHiddenOn(pathname: string): boolean {
  return (
    pathname.startsWith("/listing/") ||
    pathname.startsWith("/checkout/") ||
    pathname.startsWith("/transfer/") ||
    pathname.startsWith("/auth/") ||
    pathname === "/login" ||
    pathname === "/signup" ||
    pathname === "/forgot-password" ||
    pathname === "/reset-password" ||
    pathname === "/account/verify-phone" ||
    /^\/account\/listings\/[^/]+\/edit$/.test(pathname)
  );
}

export function Dock({ signedIn, unread = 0 }: { signedIn: boolean; unread?: number }) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [keyboard, setKeyboard] = useState(false);
  const anchor = useRef(0);
  // A new screen always starts with the dock expanded (reset during render, not in an effect).
  const [seenPath, setSeenPath] = useState(pathname);
  if (seenPath !== pathname) {
    setSeenPath(pathname);
    setCollapsed(false);
  }

  useEffect(() => {
    // dockMachine.ts: collapse after 40px of sustained scroll down past y=90;
    // expand after 28px up, or within 24px of the top.
    const onScroll = () => {
      const y = window.scrollY;
      if (y < 24) {
        setCollapsed(false);
        anchor.current = y;
        return;
      }
      const delta = y - anchor.current;
      if (delta > 40 && y > 90) {
        setCollapsed(true);
        anchor.current = y;
      } else if (delta < -28) {
        setCollapsed(false);
        anchor.current = y;
      } else if ((delta > 0 && anchor.current > y) || (delta < 0 && anchor.current < y)) {
        anchor.current = y;
      }
    };
    const isField = (el: Element | null) =>
      !!el && (el.matches("input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]), textarea, select") || (el as HTMLElement).isContentEditable);
    const onFocus = () => setKeyboard(window.matchMedia("(pointer: coarse)").matches && isField(document.activeElement));
    const onBlur = () => window.setTimeout(onFocus, 0);
    anchor.current = window.scrollY;
    window.addEventListener("scroll", onScroll, { passive: true });
    document.addEventListener("focusin", onFocus);
    document.addEventListener("focusout", onBlur);
    return () => {
      window.removeEventListener("scroll", onScroll);
      document.removeEventListener("focusin", onFocus);
      document.removeEventListener("focusout", onBlur);
    };
  }, []);

  if (dockHiddenOn(pathname)) return null;
  const items = signedIn ? SIGNED_IN : SIGNED_OUT;
  const current = sectionFor(pathname);
  const active = items.find((i) => i.section && i.section === current) ?? null;

  return (
    <>
      {/* Keeps the end of every page clear of the floating dock. */}
      <div aria-hidden="true" className="h-[calc(env(safe-area-inset-bottom)+96px)] md:hidden" />
      <nav
        aria-label="Primary"
        className={`fixed bottom-[calc(env(safe-area-inset-bottom)+12px)] z-40 md:hidden ${
          keyboard ? "pointer-events-none translate-y-6 opacity-0" : "opacity-100"
        } left-4 transition-[transform,opacity] duration-150 ${collapsed ? "right-auto" : "right-4"}`}
      >
        {collapsed && active ? (
          <button
            type="button"
            onClick={() => setCollapsed(false)}
            aria-label={`${active.label} — show navigation`}
            className="glass pressable flex h-[66px] w-[82px] items-center justify-center rounded-[33px] text-ink shadow-[var(--sn-shadow-float)] [animation:sn-fade_220ms_var(--ease-swift)]"
          >
            <Icon name={active.icon} size={28} strokeWidth={2.1} />
          </button>
        ) : (
          <ul className="glass mx-auto flex h-[66px] max-w-[346px] items-stretch justify-around rounded-[33px] px-2 shadow-[var(--sn-shadow-float)]">
            {items.map((item) => {
              const isActive = active?.href === item.href;
              return (
                <li key={item.href} className="flex min-w-0 flex-1">
                  <Link
                    href={item.href}
                    aria-current={isActive ? "page" : undefined}
                    className={`pressable relative my-2 flex flex-1 flex-col items-center justify-center gap-0.5 rounded-3xl px-1 ${
                      isActive ? "bg-[var(--sn-glass-selected)] text-ink" : "text-muted hover:text-ink"
                    }`}
                  >
                    <span className="relative">
                      <Icon name={item.icon} size={isActive ? 25 : 24} strokeWidth={isActive ? 2.1 : 1.8} />
                      {item.section === "account" && unread > 0 ? (
                        <span aria-hidden="true" className="absolute -right-1 -top-0.5 size-2 rounded-full bg-brand" />
                      ) : null}
                    </span>
                    <span className="max-w-full truncate text-[11px] font-medium leading-[13px] tracking-[0.01em] max-[339px]:sr-only">
                      {item.label}
                    </span>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </nav>
    </>
  );
}
