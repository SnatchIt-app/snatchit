/**
 * The account areas, grouped like the native settings hub. One list feeds the
 * desktop sidebar (AccountNav) and the phone hub rows on /account, so the two
 * can never disagree about where a section lives or what it is called.
 */
export type AccountLink = { href: string; label: string; showsUnread?: boolean };
export type AccountGroup = { label: string; links: readonly AccountLink[] };

export const ACCOUNT_OVERVIEW_HREF = "/account";

export const ACCOUNT_GROUPS: readonly AccountGroup[] = [
  {
    label: "Buying",
    links: [
      { href: "/account/purchases", label: "Purchases" },
      { href: "/account/saved", label: "Saved" },
    ],
  },
  {
    label: "Selling",
    links: [
      { href: "/account/listings", label: "Your listings" },
      { href: "/account/sales", label: "Sales" },
    ],
  },
  {
    label: "Account",
    links: [
      { href: ACCOUNT_OVERVIEW_HREF, label: "Overview" },
      { href: "/account/profile", label: "Profile" },
      { href: "/account/notifications", label: "Notifications", showsUnread: true },
      { href: "/account/settings", label: "Settings" },
    ],
  },
];

/** Overview matches only itself; every other section also owns its nested routes (e.g. a listing's edit page). */
export function isAccountLinkActive(href: string, pathname: string): boolean {
  if (href === ACCOUNT_OVERVIEW_HREF) return pathname === ACCOUNT_OVERVIEW_HREF;
  return pathname === href || pathname.startsWith(`${href}/`);
}
