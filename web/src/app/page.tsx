import type { Metadata } from "next";
import Image from "next/image";
import { getActiveListings, type WebListing } from "@/lib/listings";
import { Container } from "@/components/ui/Container";
import { SearchForm } from "@/components/ui/SearchInput";
import { SectionHeader } from "@/components/ui/SectionHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";
import { ListingCard } from "@/components/ListingCard";

export const metadata: Metadata = {
  alternates: { canonical: "/" },
};

const TRUST_POINTS = [
  "All-in pricing — no surprise fees",
  "Funds held until you confirm delivery",
  "Automatic refund if it isn't sent in 24h",
] as const;

export default async function HomePage() {
  let listings: WebListing[] = [];
  try {
    listings = await getActiveListings({}, 8);
  } catch {
    listings = [];
  }
  const featured = listings[0];

  return (
    <>
      {/* ── Hero ─────────────────────────────────────────────────────── */}
      <section className="relative overflow-hidden border-b border-line">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -top-64 right-[-12%] size-[560px] rounded-full bg-primary opacity-[0.06] blur-[140px]"
        />
        <Container className="relative grid items-center gap-12 py-16 lg:grid-cols-[minmax(0,1.1fr)_400px] lg:py-24">
          <div>
            <p className="mb-4 text-[12px] font-semibold uppercase tracking-[0.2em] text-primary">
              Miami · Peer-to-peer tickets
            </p>
            <h1 className="max-w-2xl text-4xl font-extrabold leading-[1.04] tracking-[-0.02em] text-ink sm:text-5xl lg:text-[56px]">
              Sold-out night?
              <br />
              Snatch a ticket from someone who can&apos;t go.
            </h1>
            <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted">
              Bid or Buy Now on real tickets across Miami — clubs, festivals, arenas. Every
              price is all-in, and your money is held until the ticket is in your hands.
            </p>
            <SearchForm size="lg" className="mt-8 max-w-xl" />
            <ul className="mt-6 flex flex-wrap gap-x-6 gap-y-2.5">
              {TRUST_POINTS.map((point) => (
                <li key={point} className="flex items-center gap-2 text-[13px] text-muted">
                  <CheckIcon />
                  {point}
                </li>
              ))}
            </ul>
          </div>

          {featured ? (
            <div className="hidden lg:block">
              <ListingCard listing={featured} priority />
              <p className="mt-3 text-center text-[13px] text-dim">Live now on Snatch It</p>
            </div>
          ) : null}
        </Container>
      </section>

      {/* ── Live listings ────────────────────────────────────────────── */}
      <section className="py-16">
        <Container>
          <SectionHeader
            eyebrow="The marketplace"
            title="Live right now"
            action={{ href: "/browse", label: "Browse all" }}
          />
          {listings.length > 0 ? (
            <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {listings.map((l) => (
                <ListingCard key={l.id} listing={l} />
              ))}
            </div>
          ) : (
            <EmptyState
              title="No live listings right now"
              message="New tickets drop all week. Check back soon or grab the app to get notified."
            />
          )}
        </Container>
      </section>

      {/* ── How it works ─────────────────────────────────────────────── */}
      <section id="how-it-works" className="scroll-mt-24 border-t border-line py-16">
        <Container>
          <SectionHeader eyebrow="How it works" title="Three steps between you and the door" />
          <div className="grid gap-5 md:grid-cols-3">
            {[
              {
                n: "01",
                title: "Snatch it",
                body: "Place a bid or hit Buy Now. Checkout is Stripe-secured, and the price you see is the price you pay — fees included.",
              },
              {
                n: "02",
                title: "Get the transfer",
                body: "The seller sends your ticket through the platform it lives on — Ticketmaster, Posh, DICE, and more — with step-by-step instructions.",
              },
              {
                n: "03",
                title: "Confirm and go",
                body: "Confirm delivery and the seller gets paid. If the ticket isn't sent within 24 hours, you're refunded automatically.",
              },
            ].map((step) => (
              <div key={step.n} className="rounded-card border border-line bg-card p-6">
                <p className="text-sm font-bold text-primary">{step.n}</p>
                <h3 className="mt-2 text-lg font-bold text-ink">{step.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted">{step.body}</p>
              </div>
            ))}
          </div>
        </Container>
      </section>

      {/* ── Buyer protection ─────────────────────────────────────────── */}
      <section className="py-16">
        <Container>
          <div className="grid gap-10 rounded-card border border-line bg-card p-8 lg:grid-cols-[1fr_1.4fr] lg:p-12">
            <div>
              <p className="mb-3 text-[12px] font-semibold uppercase tracking-[0.2em] text-primary">
                Buyer protection
              </p>
              <h2 className="text-2xl font-bold tracking-tight text-ink sm:text-3xl">
                Built so nobody gets burned.
              </h2>
              <p className="mt-4 text-[15px] leading-relaxed text-muted">
                Ticket resale runs on trust. We replaced trust with mechanics: your payment
                sits with Snatch It — not the seller — until the ticket is actually yours.
              </p>
            </div>
            <ul className="grid gap-6 sm:grid-cols-2">
              {[
                {
                  title: "Stripe-secured payments",
                  body: "Cards and Apple Pay processed by Stripe. Snatch It never sees your card number.",
                },
                {
                  title: "Funds held until delivery",
                  body: "Sellers are paid only after you confirm the ticket arrived in your account.",
                },
                {
                  title: "24-hour transfer deadline",
                  body: "If a seller doesn't send within 24 hours, the sale cancels and you're refunded in full.",
                },
                {
                  title: "Report & dispute tools",
                  body: "Something off? Open a dispute and a human reviews it before any payout moves.",
                },
              ].map((item) => (
                <li key={item.title} className="flex gap-3">
                  <ShieldIcon />
                  <div>
                    <h3 className="text-[15px] font-semibold text-ink">{item.title}</h3>
                    <p className="mt-1 text-[13px] leading-relaxed text-muted">{item.body}</p>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </Container>
      </section>

      {/* ── Sell CTA ─────────────────────────────────────────────────── */}
      <section id="sell" className="scroll-mt-24 border-t border-line py-16">
        <Container>
          <div className="grid items-center gap-10 lg:grid-cols-2">
            <div>
              <p className="mb-3 text-[12px] font-semibold uppercase tracking-[0.2em] text-primary">
                Sell on Snatch It
              </p>
              <h2 className="text-2xl font-bold tracking-tight text-ink sm:text-3xl">
                Plans changed? Your ticket still gets used.
              </h2>
              <p className="mt-4 max-w-lg text-[15px] leading-relaxed text-muted">
                List in minutes as an auction, Buy Now, or both. You keep 90% of the sale and
                get paid through Stripe once the buyer confirms delivery.
              </p>
              <ul className="mt-6 space-y-2.5">
                {[
                  "Flat 10% seller fee — nothing hidden",
                  "Payouts via Stripe Connect, straight to your bank",
                  "Proof-of-ownership review keeps the marketplace clean",
                ].map((point) => (
                  <li key={point} className="flex items-center gap-2 text-sm text-muted">
                    <CheckIcon />
                    {point}
                  </li>
                ))}
              </ul>
              <LinkButton href="https://snatchitapp.com" size="lg" className="mt-8">
                Start selling in the app
              </LinkButton>
            </div>
            <div className="grid grid-cols-3 gap-4">
              {[
                { big: "90%", small: "of the sale price goes to you" },
                { big: "24h", small: "transfer window keeps buyers safe" },
                { big: "10%", small: "flat seller fee, disclosed up front" },
              ].map((stat) => (
                <div
                  key={stat.big}
                  className="rounded-card border border-line bg-card p-5 text-center"
                >
                  <p className="text-2xl font-extrabold tracking-tight text-ink sm:text-3xl">
                    {stat.big}
                  </p>
                  <p className="mt-1.5 text-[12px] leading-snug text-muted">{stat.small}</p>
                </div>
              ))}
            </div>
          </div>
        </Container>
      </section>

      {/* ── App CTA ──────────────────────────────────────────────────── */}
      <section className="border-t border-line py-16">
        <Container className="flex flex-col items-center text-center">
          <Image
            src="/brand/sn-app-icon-1024.png"
            alt=""
            width={64}
            height={64}
            className="rounded-2xl border border-line"
          />
          <h2 className="mt-5 text-2xl font-bold tracking-tight text-ink sm:text-3xl">
            Snatch It for iPhone
          </h2>
          <p className="mt-3 max-w-md text-[15px] leading-relaxed text-muted">
            The full marketplace — live bidding, Buy Now, transfers, and seller payouts — is in
            the iOS app. Coming soon to the App Store.
          </p>
          <LinkButton href="https://snatchitapp.com" variant="secondary" className="mt-7">
            Visit snatchitapp.com
          </LinkButton>
        </Container>
      </section>
    </>
  );
}

function CheckIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 16 16" fill="none" className="size-4 shrink-0 text-success">
      <path
        d="m3 8.5 3.2 3L13 4.5"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="mt-0.5 size-5 shrink-0 text-primary">
      <path
        d="M10 1.8 3.2 4.4v4.4c0 4.4 2.9 7.6 6.8 9.4 3.9-1.8 6.8-5 6.8-9.4V4.4L10 1.8Z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <path
        d="m7 9.8 2.2 2.2L13.4 7.6"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
