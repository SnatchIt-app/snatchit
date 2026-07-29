import Image from "next/image";
import Link from "next/link";
import { Container } from "@/components/ui/Container";

const marketplace = [
  { href: "/browse", label: "Browse all tickets" },
  { href: "/browse?category=festivals", label: "Festivals" },
  { href: "/browse?category=clubs", label: "Clubs & nightlife" },
  { href: "/browse?type=buy_now", label: "Buy Now listings" },
  { href: "/browse?type=auction", label: "Live auctions" },
] as const;

const neighborhoods = [
  { href: "/browse?neighborhood=wynwood", label: "Wynwood" },
  { href: "/browse?neighborhood=downtown miami", label: "Downtown Miami" },
  { href: "/browse?neighborhood=south beach", label: "South Beach" },
  { href: "/browse?neighborhood=e11even", label: "E11EVEN" },
] as const;

export function Footer() {
  return (
    <footer className="mt-24 border-t border-white/[0.06] bg-[#07090C]">
      <Container className="pb-10 pt-14">
        <div className="grid gap-12 md:grid-cols-[1.5fr_1fr_1fr_1fr]">
          <div>
            <Image src="/brand/sn-logo-white.svg" alt="Snatch It" width={96} height={35} />
            <p className="mt-5 max-w-[300px] text-[14px] leading-relaxed text-muted">
              Miami&apos;s peer-to-peer ticket marketplace. Bid or Buy Now on real tickets from
              real people — all-in prices, funds held until your ticket arrives.
            </p>
          </div>

          <FooterCol title="Marketplace" links={marketplace} />
          <FooterCol title="Neighborhoods" links={neighborhoods} />

          <div>
            <h3 className="text-[13.5px] font-bold text-ink">Company</h3>
            <ul className="mt-4 space-y-0.5">
              <li>
                <a
                  href="https://snatchitapp.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-9 items-center text-[14px] text-muted transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
                >
                  About Snatch It
                </a>
              </li>
              <li>
                <a
                  href="https://snatchitapp.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-9 items-center text-[14px] text-muted transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
                >
                  Get the iOS app
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-12 border-t border-white/[0.06] pt-7">
          <p className="max-w-3xl text-[12.5px] leading-relaxed text-dim">
            All prices shown include fees. Snatch It is a peer-to-peer resale marketplace —
            tickets are transferred on the original ticketing platform after purchase, and
            sellers are paid only after delivery. Snatch It is not affiliated with
            Ticketmaster, AXS, DICE, Posh, or any other ticket issuer.
          </p>
          <p className="mt-5 text-[13px] font-semibold text-dim">
            © {new Date().getFullYear()} JDT LLC · Snatch It · Miami, FL
          </p>
        </div>
      </Container>
    </footer>
  );
}

function FooterCol({
  title,
  links,
}: {
  title: string;
  links: readonly { href: string; label: string }[];
}) {
  return (
    <div>
      <h3 className="text-[13.5px] font-bold text-ink">{title}</h3>
      <ul className="mt-4 space-y-0.5">
        {links.map((l) => (
          <li key={l.href}>
            <Link
              href={l.href}
              className="inline-flex min-h-9 items-center text-[14px] text-muted transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
            >
              {l.label}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
