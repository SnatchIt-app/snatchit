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
      <section className="border-b border-white/[0.06]">
        <Container className="grid items-center gap-14 py-20 lg:grid-cols-[minmax(0,1.15fr)_390px] lg:py-28">
          <div>
            <p className="u-label flex items-center gap-3 text-primary">
              <span aria-hidden="true" className="h-px w-8 bg-primary" />
              Miami · Peer-to-peer tickets
            </p>
            <h1 className="mt-7 max-w-[19ch] text-balance text-[clamp(2.6rem,6.5vw,4.5rem)] font-extrabold leading-[0.98] tracking-[-0.03em] text-ink">
              Sold-out night? Snatch a ticket from someone who can&apos;t go.
            </h1>
            <p className="mt-7 max-w-[52ch] text-[16px] leading-relaxed text-muted sm:text-[17px]">
              Bid or Buy Now on real tickets across Miami — clubs, festivals, arenas. Every
              price is all-in, and your money is held until the ticket is in your hands.
            </p>
            <SearchForm size="lg" className="mt-10 max-w-xl" />
            <ul className="mt-7 flex flex-wrap items-center gap-x-3 gap-y-2">
              {TRUST_POINTS.map((point, i) => (
                <li
                  key={point}
                  className="flex items-center gap-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-dim"
                >
                  {i > 0 ? (
                    <span aria-hidden="true" className="text-[8px] text-dim/60">
                      ●
                    </span>
                  ) : null}
                  {point}
                </li>
              ))}
            </ul>
          </div>

          {featured ? (
            <div className="hidden lg:block">
              <ListingCard listing={featured} priority />
              <p className="u-label mt-5 text-center text-dim">Live now on Snatch It</p>
            </div>
          ) : null}
        </Container>
      </section>

      {/* ── Live listings ────────────────────────────────────────────── */}
      <section className="py-20">
        <Container>
          <SectionHeader
            eyebrow="The marketplace"
            title="Live right now"
            action={{ href: "/browse", label: "Browse all" }}
          />
          {listings.length > 0 ? (
            <div className="grid grid-cols-1 gap-x-5 gap-y-12 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
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
      <section id="how-it-works" className="scroll-mt-24 py-20">
        <Container>
          <SectionHeader eyebrow="How it works" title="Three steps between you and the door" />
          <div className="grid gap-x-10 gap-y-10 md:grid-cols-3">
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
              <div key={step.n} className="rule-t pt-6">
                <p className="text-[13px] font-bold tabular-nums tracking-[0.08em] text-primary">
                  {step.n}
                </p>
                <h3 className="mt-4 text-[19px] font-bold tracking-[-0.01em] text-ink">
                  {step.title}
                </h3>
                <p className="mt-2.5 max-w-[40ch] text-[13.5px] leading-relaxed text-muted">
                  {step.body}
                </p>
              </div>
            ))}
          </div>
        </Container>
      </section>

      {/* ── Buyer protection ─────────────────────────────────────────── */}
      <section className="py-20">
        <Container>
          <div className="grid gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)]">
            <div>
              <p className="u-label mb-3 text-primary">Buyer protection</p>
              <h2 className="text-[26px] font-bold leading-[1.05] tracking-[-0.02em] text-ink sm:text-[32px]">
                Built so nobody gets burned.
              </h2>
              <p className="mt-5 max-w-[44ch] text-[14.5px] leading-relaxed text-muted">
                Ticket resale runs on trust. We replaced trust with mechanics: your payment
                sits with Snatch It — not the seller — until the ticket is actually yours.
              </p>
            </div>
            <ul className="grid gap-x-10 gap-y-8 sm:grid-cols-2">
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
                <li key={item.title} className="rule-t pt-5">
                  <h3 className="flex items-center gap-2.5 text-[15px] font-bold tracking-[-0.01em] text-ink">
                    <ShieldIcon />
                    {item.title}
                  </h3>
                  <p className="mt-2 text-[13px] leading-relaxed text-muted">{item.body}</p>
                </li>
              ))}
            </ul>
          </div>
        </Container>
      </section>

      {/* ── Sell CTA ─────────────────────────────────────────────────── */}
      <section id="sell" className="scroll-mt-24 py-20">
        <Container>
          <div className="grid items-center gap-14 lg:grid-cols-2">
            <div>
              <p className="u-label mb-3 text-primary">Sell on Snatch It</p>
              <h2 className="text-[26px] font-bold leading-[1.05] tracking-[-0.02em] text-ink sm:text-[32px]">
                Plans changed? Your ticket still gets used.
              </h2>
              <p className="mt-5 max-w-[48ch] text-[14.5px] leading-relaxed text-muted">
                List in minutes as an auction, Buy Now, or both. You keep 90% of the sale and
                get paid through Stripe once the buyer confirms delivery.
              </p>
              <ul className="mt-7 space-y-3">
                {[
                  "Flat 10% seller fee — nothing hidden",
                  "Payouts via Stripe Connect, straight to your bank",
                  "Proof-of-ownership review keeps the marketplace clean",
                ].map((point) => (
                  <li key={point} className="flex items-center gap-3 text-[13.5px] text-muted">
                    <CheckIcon />
                    {point}
                  </li>
                ))}
              </ul>
              <LinkButton href="https://snatchitapp.com" size="lg" className="mt-10">
                Start selling in the app
              </LinkButton>
            </div>
            <div className="grid grid-cols-3 gap-10">
              {[
                { big: "90%", small: "of the sale price goes to you" },
                { big: "24h", small: "transfer window keeps buyers safe" },
                { big: "10%", small: "flat seller fee, disclosed up front" },
              ].map((stat) => (
                <div key={stat.big} className="rule-t pt-5">
                  <p className="text-[clamp(2rem,4vw,3rem)] font-extrabold leading-none tracking-[-0.03em] tabular-nums text-ink">
                    {stat.big}
                  </p>
                  <p className="mt-3 text-[11px] font-semibold uppercase leading-[1.5] tracking-[0.1em] text-dim">
                    {stat.small}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </Container>
      </section>

      {/* ── App CTA ──────────────────────────────────────────────────── */}
      <section className="border-t border-white/[0.06] py-24">
        <Container className="flex flex-col items-center text-center">
          <Image
            src="/brand/sn-app-icon-1024.png"
            alt=""
            width={56}
            height={56}
            className="rounded-[12px] border border-white/10"
          />
          <h2 className="mt-7 text-[26px] font-bold tracking-[-0.02em] text-ink sm:text-[32px]">
            Snatch It for iPhone
          </h2>
          <p className="mt-4 max-w-[46ch] text-[14.5px] leading-relaxed text-muted">
            The full marketplace — live bidding, Buy Now, transfers, and seller payouts — is in
            the iOS app. Coming soon to the App Store.
          </p>
          <LinkButton href="https://snatchitapp.com" variant="secondary" className="mt-9">
            Visit snatchitapp.com
          </LinkButton>
        </Container>
      </section>
    </>
  );
}

function CheckIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 16 16" fill="none" className="size-3.5 shrink-0 text-success">
      <path
        d="m3 8.5 3.2 3L13 4.5"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-4 shrink-0 text-primary">
      <path
        d="M10 1.8 3.2 4.4v4.4c0 4.4 2.9 7.6 6.8 9.4 3.9-1.8 6.8-5 6.8-9.4V4.4L10 1.8Z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      <path
        d="m7 9.8 2.2 2.2L13.4 7.6"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
