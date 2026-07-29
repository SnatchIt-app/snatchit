import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";
import { UnreadDot } from "@/components/ui/Badge";
import { getAuthedUser } from "@/lib/auth/session";
import { unreadNotificationCount } from "@/lib/notifications";

const nav = [
  { href: "/browse", label: "Browse" },
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#sell", label: "Sell tickets" },
] as const;

const navLinkCls =
  "inline-flex min-h-11 items-center whitespace-nowrap text-[11px] font-medium uppercase tracking-[0.3em] text-white/60 transition-colors duration-200 hover:text-primary motion-reduce:transition-none";

/**
 * Solid black bar with the site's red hairline underline, carrying the
 * official SN logo asset at a confident size. Auth state is read on every
 * page (getClaims() is a cheap, locally-verified check) so the header can
 * switch between logged-out and logged-in nav without a client round-trip.
 */
export async function Header() {
  const user = await getAuthedUser();
  const unread = user ? await unreadNotificationCount() : 0;

  return (
    <header className="sticky top-0 z-40 border-b border-primary/20 bg-black">
      <Container className="flex h-16 items-center justify-between gap-6">
        <div className="flex items-center gap-10">
          <Link href="/" className="flex min-h-11 items-center" aria-label="Snatch It home">
            <Image
              src="/brand/sn-logo-white.svg"
              alt="Snatch It"
              width={99}
              height={36}
              priority
              className="h-8 w-auto sm:h-9"
            />
          </Link>
          <nav aria-label="Primary" className="hidden items-center gap-7 md:flex">
            {nav.map((item) => (
              <Link key={item.href} href={item.href} className={navLinkCls}>
                {item.label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-3 sm:gap-5">
          <Link href="/browse" className={`${navLinkCls} md:hidden`}>
            Browse
          </Link>

          {user ? (
            <Link href="/account" className={`${navLinkCls} gap-2`}>
              {unread > 0 ? <UnreadDot /> : null}
              Account
            </Link>
          ) : (
            <Link href="/login" className={navLinkCls}>
              Log in
            </Link>
          )}

          {user ? null : (
            <span className="hidden lg:inline-block">
              <LinkButton href="/signup" variant="secondary">
                Create account
              </LinkButton>
            </span>
          )}
          <LinkButton href="https://snatchitapp.com" variant="primary">
            <span className="sm:hidden">Get app</span>
            <span className="hidden sm:inline">Get the app</span>
          </LinkButton>
        </div>
      </Container>
    </header>
  );
}
