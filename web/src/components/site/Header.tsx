import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";

const nav = [
  { href: "/browse", label: "Browse" },
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#sell", label: "Sell tickets" },
] as const;

export function Header() {
  return (
    <header className="sticky top-0 z-40 border-b border-line bg-bg/85 backdrop-blur-md">
      <Container className="flex h-16 items-center justify-between gap-4">
        <div className="flex items-center gap-8">
          <Link href="/" className="flex min-h-11 items-center" aria-label="Snatch It — home">
            <Image
              src="/brand/sn-logo-white.svg"
              alt="Snatch It"
              width={94}
              height={34}
              priority
            />
          </Link>
          <nav aria-label="Primary" className="hidden items-center gap-1 md:flex">
            {nav.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="inline-flex min-h-11 items-center rounded-field px-3 text-sm font-medium text-muted transition-colors hover:text-ink motion-reduce:transition-none"
              >
                {item.label}
              </Link>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-2">
          <Link
            href="/browse"
            className="inline-flex min-h-11 items-center rounded-field px-3 text-sm font-medium text-muted hover:text-ink md:hidden"
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
