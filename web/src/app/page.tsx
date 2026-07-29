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

const STEPS = [
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
] as const;

const TRUST_ROWS = [
  {
    head: "Stripe-secured payments",
    body: "Cards and Apple Pay processed by Stripe. Snatch It never sees your card number.",
  },
  {
    head: "Funds held until delivery",
    body: "Sellers are paid only after you confirm the ticket arrived in your account.",
  },
  {
    head: "24-hour transfer deadline",
    body: "If a seller doesn't send within 24 hours, the sale cancels and you're refunded in full.",
  },
  {
    head: "Disputes freeze payouts",
    body: "Something off? Open a dispute and a human reviews it before any payout moves.",
  },
] as const;

export default async function HomePage() {
  let listings: WebListing[] = [];
  try {
    listings = await getActiveListings({}, 8);
  } catch {
    listings = [];
  }

  return (
    <>
      {/* ── Hero — full-bleed atmosphere, continuous with snatchitapp.com ── */}
      <section className="vignette-red relative overflow-hidden border-b border-primary/15 bg-black">
        {/* Crowd underlay at the site's opacity, emerging from black */}
        <div aria-hidden="true" className="absolute inset-0">
          <Image
            src="/atmosphere/crowd.jpg"
            alt=""
            fill
            priority
            sizes="100vw"
            className="object-cover object-bottom opacity-20"
          />
          <div className="absolute inset-0 bg-black/20 mix-blend-multiply" />
        </div>
        <div
          aria-hidden="true"
          className="absolute left-1/2 top-1/2 h-[400px] w-[900px] -translate-x-1/2 -translate-y-1/2 bg-primary/15 blur-[180px]"
        />
        <div
          aria-hidden="true"
          className="absolute left-1/4 top-1/4 h-[2px] w-[300px] rotate-45 bg-primary/20 blur-[8px]"
        />
        <div
          aria-hidden="true"
          className="absolute bottom-1/3 right-1/4 h-[2px] w-[400px] -rotate-12 bg-primary/15 blur-[10px]"
        />

        <Container className="rise-in relative z-10 py-20 text-center sm:py-28">
          <p className="eyebrow text-primary/80">Now live · Miami</p>
          <h1 className="glow-red flicker mx-auto mt-7 max-w-[14ch] font-display text-[clamp(3.2rem,9vw,6.5rem)] font-bold uppercase leading-[0.85] tracking-[-0.03em] text-primary">
            Sold out isn&apos;t over.
          </h1>
          <p className="mt-7 font-display text-[15px] font-bold uppercase tracking-[0.2em] text-ink sm:text-[21px]">
            Miami nightlife, on demand.
          </p>
          <p className="mx-auto mt-6 max-w-[52ch] text-[15px] leading-relaxed text-white/70 sm:text-[16px]">
            Bid or Buy Now on real tickets to the city&apos;s sold-out nights — clubs, festivals,
            arenas. Every price is all-in, and your money is held until the ticket is in your
            hands.
          </p>
          <SearchForm size="lg" className="mx-auto mt-9 max-w-xl" />
          <p className="mt-8 text-[10px] uppercase tracking-[0.5em] text-white/30">
            Every price all-in · Sellers verified · 21+
          </p>
        </Container>
      </section>

      {/* ── Live listings — the marketplace, immediately ── */}
      <section className="py-16 sm:py-20">
        <Container>
          <SectionHeader
            eyebrow="The marketplace"
            title="Live right now."
            action={{ href: "/browse", label: "Browse all" }}
          />
          {listings.length > 0 ? (
            <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {listings.map((l, i) => (
                <ListingCard key={l.id} listing={l} priority={i < 4} />
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

      {/* ── How it works — the site's numbered editorial rows ── */}
      <section id="how-it-works" className="relative scroll-mt-24 overflow-hidden py-20 sm:py-28">
        <div aria-hidden="true" className="absolute inset-0">
          <Image
            src="/atmosphere/silhouettes.jpg"
            alt=""
            fill
            sizes="100vw"
            className="object-cover opacity-[0.08]"
          />
          <div className="absolute inset-0 bg-black/30 mix-blend-multiply" />
        </div>
        <Container className="relative z-10">
          <div className="mb-14 text-center sm:mb-16">
            <p className="eyebrow text-primary/80">How it works</p>
            <h2 className="mt-5 font-display text-[clamp(2rem,4.5vw,3.4rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
              Three steps. One night.
            </h2>
          </div>
          <ol className="mx-auto max-w-4xl divide-y divide-primary/20 border-y border-primary/20">
            {STEPS.map((step) => (
              <li
                key={step.n}
                className="grid grid-cols-[auto_1fr] items-baseline gap-6 py-8 sm:gap-12 sm:py-11"
              >
                <span
                  aria-hidden="true"
                  className="glow-red-subtle font-display text-[52px] font-bold leading-none tracking-[-0.03em] text-primary sm:text-[76px]"
                >
                  {step.n}
                </span>
                <div>
                  <h3 className="font-display text-[22px] font-bold uppercase tracking-tight text-ink sm:text-[30px]">
                    {step.title}
                  </h3>
                  <p className="mt-2.5 max-w-xl text-[14px] leading-relaxed text-white/70 sm:text-[15px]">
                    {step.body}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        </Container>
      </section>

      {/* ── Trust & safety — the site's label-grid definition rows ── */}
      <section className="py-16 sm:py-24">
        <Container>
          <div className="mb-14 text-center sm:mb-16">
            <p className="eyebrow text-primary/80">Trust &amp; safety</p>
            <h2 className="mx-auto mt-5 max-w-[16ch] font-display text-[clamp(2rem,4.5vw,3.4rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
              Built so nobody gets burned.
            </h2>
          </div>
          <ul className="mx-auto max-w-4xl divide-y divide-primary/20 border-y border-primary/20">
            {TRUST_ROWS.map((row) => (
              <li
                key={row.head}
                className="grid gap-2 py-7 sm:grid-cols-[16rem_1fr] sm:items-baseline sm:gap-12 sm:py-8"
              >
                <h3 className="font-display text-[19px] font-bold uppercase tracking-tight text-primary sm:text-[22px]">
                  {row.head}
                </h3>
                <p className="text-[14px] leading-relaxed text-white/70 sm:text-[15px]">
                  {row.body}
                </p>
              </li>
            ))}
          </ul>
        </Container>
      </section>

      {/* ── Sell — statement plus oversized Oswald stats ── */}
      <section id="sell" className="scroll-mt-24 border-t border-primary/15 py-16 sm:py-24">
        <Container>
          <div className="grid items-center gap-14 lg:grid-cols-2">
            <div>
              <p className="eyebrow text-primary/80">Sell on Snatch It</p>
              <h2 className="mt-5 max-w-[16ch] font-display text-[clamp(1.9rem,3.8vw,2.9rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
                Plans changed? Your ticket still gets used.
              </h2>
              <p className="mt-5 max-w-[48ch] text-[14.5px] leading-relaxed text-white/70">
                List in minutes as an auction, Buy Now, or both. You keep 90% of the sale and
                get paid through Stripe once the buyer confirms delivery.
              </p>
              <ul className="mt-6 space-y-3 text-[14px] leading-relaxed text-white/70">
                {[
                  "Flat 10% seller fee — nothing hidden",
                  "Payouts via Stripe Connect, straight to your bank",
                  "Proof-of-ownership review keeps the marketplace clean",
                ].map((point) => (
                  <li key={point} className="flex gap-3">
                    <span aria-hidden="true" className="font-bold text-primary">·</span>
                    {point}
                  </li>
                ))}
              </ul>
              <LinkButton href="https://snatchitapp.com" size="lg" className="mt-9">
                Start selling in the app
              </LinkButton>
            </div>
            <div className="grid grid-cols-3 gap-6 text-center lg:gap-8">
              {[
                { big: "90%", small: "of the sale is yours" },
                { big: "24h", small: "transfer window" },
                { big: "10%", small: "flat seller fee" },
              ].map((stat) => (
                <div key={stat.big}>
                  <p className="glow-red-subtle font-display text-[clamp(2.6rem,5vw,4rem)] font-bold leading-none tracking-[-0.03em] text-primary">
                    {stat.big}
                  </p>
                  <p className="mt-3 text-[10px] uppercase tracking-[0.25em] text-white/45">
                    {stat.small}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </Container>
      </section>

      {/* ── App CTA ── */}
      <section className="relative overflow-hidden border-t border-primary/15 py-20 sm:py-28">
        <div aria-hidden="true" className="absolute inset-0">
          <Image
            src="/atmosphere/sold-out.jpg"
            alt=""
            fill
            sizes="100vw"
            className="object-cover opacity-10"
          />
          <div className="absolute inset-0 bg-black/30 mix-blend-multiply" />
        </div>
        <Container className="relative z-10 flex flex-col items-center text-center">
          <Image
            src="/brand/sn-app-icon-1024.png"
            alt=""
            width={64}
            height={64}
            className="rounded-[14px] border border-white/10"
          />
          <h2 className="mt-7 font-display text-[clamp(2rem,4vw,3rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
            Snatch It for iPhone
          </h2>
          <p className="mt-4 max-w-[46ch] text-[14.5px] leading-relaxed text-white/70">
            The full marketplace — live bidding, Buy Now, transfers, and seller payouts — is in
            the iOS app. Coming soon to the App Store.
          </p>
          <LinkButton href="https://snatchitapp.com" size="lg" className="mt-9">
            Visit snatchitapp.com
          </LinkButton>
        </Container>
      </section>
    </>
  );
}
