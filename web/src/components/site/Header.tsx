import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";

const nav = [
  { href: "/browse", label: "Browse" },
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#sell", label: "Sell" },
] as const;

export function Header() {
  return (
    <header className="sticky top-0 z-40 border-b border-white/[0.06] bg-bg/90 backdrop-blur-md">
      <Container className="flex h-[68px] items-center justify-between gap-6">
        <div className="flex items-center gap-12">
          <Link href="/" className="flex min-h-11 items-center" aria-label="Snatch It — home">
            <Image
              src="/brand/sn-logo-white.svg"
              alt="Snatch It"
              width={83}
              height={30}
              priority
            />
          </Link>
          <nav aria-label="Primary" className="hidden items-center gap-8 md:flex">
            {nav.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="u-label inline-flex min-h-11 items-center text-muted transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
              >
                {item.label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-5">
          <Link
            href="/browse"
            className="u-label inline-flex min-h-11 items-center text-muted transition-colors duration-150 hover:text-ink md:hidden"
          >
            Browse
          </Link>
          <LinkButton href="https://snatchitapp.com" variant="primary" className="px-5">
            Get the app
          </LinkButton>
        </div>
      </Container>
    </header>
  );
}
