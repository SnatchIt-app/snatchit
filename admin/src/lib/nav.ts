/**
 * The console's sections — one list for the desktop sidebar, the mobile menu and
 * the `g` keyboard shortcuts. Navigation only: every route still enforces its own
 * session, aal2 and ops.whoami() role checks (proxy + requireOperator).
 */
export const NAV = [
  { href: "/", label: "Today", key: "t" },
  { href: "/cases", label: "Cases", key: "c" },
  { href: "/orders", label: "Orders & Transfers", key: "o" },
  { href: "/money", label: "Money", key: "m" },
  { href: "/users", label: "Users", key: "u" },
  { href: "/marketplace", label: "Marketplace", key: "k" },
  { href: "/reports", label: "Reports", key: "r" },
  { href: "/system", label: "System", key: "s" },
] as const;

/** Today is active only on `/`; a section is active on itself and its detail pages, never on a look-alike prefix. */
export function isNavActive(pathname: string, href: string): boolean {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}
