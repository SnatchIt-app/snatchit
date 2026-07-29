import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";

const nav = [
  { href: "/browse", label: "Browse" },
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#sell", label: "Sell tickets" },
] as const;

/**
 * Solid black bar with the site's red hairline underline, carrying the
 * official SN logo asset at a confident size.
 */
export function Header() {
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
              <Link
                key={item.href}
                href={item.href}
                className="inline-flex min-h-11 items-center text-[11px] font-medium uppercase tracking-[0.3em] text-white/60 transition-colors duration-200 hover:text-primary motion-reduce:transition-none"
              >
                {item.label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-4">
          <Link
            href="/browse"
            className="inline-flex min-h-11 items-center text-[11px] font-medium uppercase tracking-[0.3em] text-white/60 transition-colors duration-200 hover:text-primary motion-reduce:transition-none md:hidden"
          >
            Browse
          </Link>
          <LinkButton href="https://snatchitapp.com" variant="primary">
            Get the app
          </LinkButton>
        </div>
      </Container>
    </header>
  );
}
