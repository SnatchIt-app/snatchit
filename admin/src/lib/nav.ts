/**
 * The console's sections — one list for the desktop sidebar, the mobile menu and
 * the `g` keyboard shortcuts. Navigation only: every route still enforces its own
 * session, aal2 and ops.whoami() role checks (proxy + requireOperator).
 */
import type { IconName } from "@/components/ui/Icon";

/**
 * "Orders" carries transfers: every transfer belongs to the order whose payment
 * created it, /transfers/:id redirects to that order, and the Orders filter and
 * search still select by transfer state and tr_ id.
 */
export type NavGroup = "Work" | "Money" | "People" | "Platform";

export const NAV: readonly { href: string; label: string; short?: string; key: string; icon: IconName; primary?: boolean; group?: NavGroup }[] = [
  { href: "/", label: "Today", key: "t", icon: "today", primary: true },
  { href: "/cases", label: "Cases", key: "c", icon: "case", primary: true, group: "Work" },
  { href: "/orders", label: "Orders & transfers", short: "Orders", key: "o", icon: "receipt", primary: true, group: "Money" },
  { href: "/money", label: "Money & refunds", short: "Money", key: "m", icon: "money", primary: true, group: "Money" },
  { href: "/users", label: "Users", key: "u", icon: "users", group: "People" },
  { href: "/marketplace", label: "Marketplace", short: "Market", key: "k", icon: "store", group: "Platform" },
  { href: "/reports", label: "Reports", key: "r", icon: "flag", group: "People" },
  { href: "/system", label: "System", key: "s", icon: "pulse", group: "Platform" },
];

/** Today is active only on `/`; a section is active on itself and its detail pages, never on a look-alike prefix. */
export function isNavActive(pathname: string, href: string): boolean {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}
