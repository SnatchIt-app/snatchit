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
] as const;

/**
 * Footer as a centered stack, mirroring snatchitapp.com: Oswald red wordmark
 * with subtle glow, tracked tagline, tracked link rows that turn red on
 * hover, interpunct copyright line.
 */
export function Footer() {
  return (
    <footer className="mt-24 border-t border-primary/20 bg-black">
      <Container className="flex flex-col items-center gap-8 pb-12 pt-16 text-center">
        <p className="glow-red-subtle font-display text-[34px] font-bold uppercase leading-none tracking-[-0.02em] text-primary sm:text-[38px]">
          Snatch It
        </p>

        <p className="text-[10px] font-medium uppercase tracking-[0.4em] text-white/40 sm:text-[11px]">
          Live auctions for nightlife tickets.
        </p>

        <nav aria-label="Marketplace" className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
          {marketplace.map((l) => (
            <FooterLink key={l.href} {...l} />
          ))}
          {neighborhoods.map((l) => (
            <FooterLink key={l.href} {...l} />
          ))}
        </nav>

        <nav aria-label="Company" className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
          {company.map((l) => (
            <FooterLink key={l.href} {...l} />
          ))}
        </nav>

        <p className="max-w-2xl text-[12px] leading-relaxed text-white/35">
          All prices shown include fees. Snatch It is a peer-to-peer resale marketplace.
          Tickets transfer on the original ticketing platform after purchase, and sellers
          are paid only after delivery. Snatch It is not affiliated with Ticketmaster,
          AXS, DICE, Posh, or any other ticket issuer.
        </p>

        <p className="pt-2 text-[10px] uppercase tracking-[0.4em] text-white/30">
          © {new Date().getFullYear()} Snatch It · JDT LLC · Miami, FL
        </p>
      </Container>
    </footer>
  );
}

function FooterLink({ href, label }: { href: string; label: string }) {
  const cls =
    "inline-flex min-h-9 items-center text-[10px] uppercase tracking-[0.3em] text-white/60 " +
    "transition-colors duration-200 hover:text-primary motion-reduce:transition-none sm:text-[11px]";
  if (href.startsWith("http")) {
    return (
      <a href={href} target="_blank" rel="noopener noreferrer" className={cls}>
        {label}
      </a>
    );
  }
  return (
    <Link href={href} className={cls}>
      {label}
    </Link>
  );
}
