import { Suspense } from "react";
import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";
import { LinkButton, iconButtonClasses } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";
import { SearchForm } from "@/components/ui/SearchInput";
import { HeaderNavLink, HideOnBrowse } from "@/components/site/NavLinks";
import type { AuthedUser } from "@/lib/auth/session";
import { LoginLink } from "@/components/site/LoginLink";

const LOGIN_LINK_CLS =
  "pressable inline-flex min-h-10 items-center whitespace-nowrap rounded-full px-3.5 text-[15px] font-semibold text-ink hover:bg-ink/[0.06]";

/**
 * Top bar. Desktop: a translucent glass bar (the native dock's material) with
 * the SN logo, Browse and Sell, a search field and the account controls.
 * Phone: logo, search and notifications only — primary navigation lives in
 * the floating dock at the bottom of the screen, as in the native app.
 *
 * Auth state is read once per request in the root layout (getClaims() is a
 * cheap, locally verified check) and passed in, so the header switches between
 * signed-out and signed-in without a client round-trip.
 */
export function Header({ user, unread }: { user: AuthedUser | null; unread: number }) {
  const bellLabel = unread > 0 ? `Notifications, ${unread} unread` : "Notifications";

  return (
    <header className="glass-bar sticky top-0 z-40 border-b border-[var(--sn-glass-line)]">
      <Container className="flex h-16 items-center gap-3 lg:gap-6">
        <Link href="/" className="flex min-h-11 shrink-0 items-center pr-2" aria-label="Snatch It home">
          <Image
            src="/brand/sn-logo.svg"
            alt="Snatch It"
            width={83}
            height={30}
            priority
            className="h-[26px] w-auto dark:invert"
          />
        </Link>

        <nav aria-label="Primary" className="hidden items-center gap-1 md:flex">
          <HeaderNavLink href="/browse" section="browse">
            Browse
          </HeaderNavLink>
          <HeaderNavLink href="/sell" section="sell">
            Sell
          </HeaderNavLink>
          {user ? (
            <HeaderNavLink href="/account/purchases" section="purchases">
              Purchases
            </HeaderNavLink>
          ) : null}
        </nav>

        <div className="ml-auto flex items-center gap-1.5 sm:gap-2">
          <HideOnBrowse>
            <SearchForm size="sm" className="w-[min(28vw,340px)] max-lg:hidden" />
          </HideOnBrowse>
          <Link href="/browse" className={iconButtonClasses("plain", "lg:hidden max-[299px]:hidden")} aria-label="Search listings">
            <Icon name="search" />
          </Link>

          {user ? (
            <>
              <Link href="/account/saved" className={iconButtonClasses("plain", "max-md:hidden")} aria-label="Saved listings">
                <Icon name="bookmark" />
              </Link>
              <Link href="/account/notifications" className={iconButtonClasses("plain", "relative")} aria-label={bellLabel}>
                <Icon name="bell" />
                {unread > 0 ? (
                  <span
                    aria-hidden="true"
                    className="absolute right-2 top-2 inline-flex min-w-4 items-center justify-center rounded-full bg-brand px-1 text-[10px] font-bold leading-4 text-inverse"
                  >
                    {unread > 9 ? "9+" : unread}
                  </span>
                ) : null}
              </Link>
              <Link
                href="/account"
                className="pressable ml-1 inline-flex min-h-10 items-center gap-2 rounded-full border border-line pl-1.5 pr-3.5 text-[14px] font-semibold text-ink hover:border-control max-md:hidden"
              >
                <span className="inline-flex size-7 items-center justify-center rounded-full bg-surface text-ink-2">
                  <Icon name="user" size={16} />
                </span>
                Account
              </Link>
            </>
          ) : (
            <>
              {/* Comes back to this page after login. The fallback (plain /login) only shows if the
                  query isn't available while rendering. */}
              <Suspense
                fallback={
                  <Link href="/login" className={LOGIN_LINK_CLS}>
                    Log in
                  </Link>
                }
              >
                <LoginLink className={LOGIN_LINK_CLS} />
              </Suspense>
              <LinkButton href="/signup" size="sm" className="whitespace-nowrap max-sm:hidden">
                Create account
              </LinkButton>
            </>
          )}
        </div>
      </Container>
    </header>
  );
}
