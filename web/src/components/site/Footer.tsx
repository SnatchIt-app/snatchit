import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";

const marketplace = [
  { href: "/browse", label: "Browse all" },
  { href: "/browse?category=festivals", label: "Festivals" },
  { href: "/browse?category=clubs", label: "Clubs" },
  { href: "/browse?type=buy_now", label: "Buy Now" },
  { href: "/browse?type=auction", label: "Live auctions" },
] as const;

const neighborhoods = [
  { href: "/browse?neighborhood=wynwood", label: "Wynwood" },
  { href: "/browse?neighborhood=downtown miami", label: "Downtown" },
  { href: "/browse?neighborhood=south beach", label: "South Beach" },
  { href: "/browse?neighborhood=e11even", label: "E11EVEN" },
] as const;

// The marketing site's own pages — one connected product.
const company = [
  { href: "https://snatchitapp.com/about", label: "About" },
  { href: "https://snatchitapp.com/faq", label: "FAQ" },
  { href: "https://snatchitapp.com/support", label: "Support" },
  { href: "https://snatchitapp.com/buyer-guarantee", label: "Buyer Guarantee" },
  { href: "https://snatchitapp.com/privacy", label: "Privacy" },
  { href: "https://snatchitapp.com/terms", label: "Terms" },
  { href: "https://snatchitapp.com", label: "Get the app" },
] as const;

/** Quiet footer: the logo, three link groups, the marketplace disclaimer and the legal line. */
export function Footer() {
  return (
    <footer className="mt-20 border-t border-line">
      <Container className="grid gap-10 py-12 md:grid-cols-[1.2fr_1fr_1fr_1fr]">
        <div>
          <Image src="/brand/sn-logo.svg" alt="Snatch It" width={72} height={26} className="h-6 w-auto dark:invert" />
          <p className="t-body-sm mt-4 max-w-xs text-muted">Live auctions for nightlife tickets.</p>
        </div>
        <FooterGroup title="Marketplace" links={marketplace} />
        <FooterGroup title="Neighborhoods" links={neighborhoods} />
        <FooterGroup title="Company" links={company} />
      </Container>
      <Container className="border-t border-line py-8">
        <p className="t-body-sm max-w-3xl text-muted">
          All prices shown include fees. Snatch It is a peer-to-peer resale marketplace. Tickets transfer on the
          original ticketing platform after purchase, and sellers are paid only after delivery. Snatch It is not
          affiliated with Ticketmaster, AXS, DICE, Posh, or any other ticket issuer.
        </p>
        <p className="t-body-sm mt-4 text-muted">© {new Date().getFullYear()} Snatch It · JDT LLC · Miami, FL</p>
      </Container>
    </footer>
  );
}

function FooterGroup({ title, links }: { title: string; links: readonly { href: string; label: string }[] }) {
  return (
    <nav aria-label={title}>
      <p className="t-micro text-muted">{title}</p>
      <ul className="mt-3 space-y-0.5">
        {links.map((l) => (
          <li key={l.href}>
            {l.href.startsWith("http") ? (
              <a href={l.href} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-9 items-center text-[14px] text-ink-2 hover:text-ink hover:underline underline-offset-4">
                {l.label}
              </a>
            ) : (
              <Link href={l.href} className="inline-flex min-h-9 items-center text-[14px] text-ink-2 hover:text-ink hover:underline underline-offset-4">
                {l.label}
              </Link>
            )}
          </li>
        ))}
      </ul>
    </nav>
  );
}
