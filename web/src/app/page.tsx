import type { Metadata } from "next";
import Image from "next/image";
import { getActiveListings, type WebListing } from "@/lib/listings";
import { getSavedListingIdSet } from "@/lib/favorites";
import { Container } from "@/components/ui/Container";
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
    title: "Find your ticket",
    body: "Live listings with current bids and countdowns.",
  },
  {
    n: "02",
    title: "Bid or buy",
    body: "Bid in real time or take the Buy Now price.",
  },
  {
    n: "03",
    title: "Get ready to go",
    body: "The seller transfers your ticket, or you're refunded automatically.",
  },
] as const;

export default async function HomePage() {
  let listings: WebListing[] = [];
  try {
    listings = await getActiveListings({}, 8);
  } catch {
    listings = [];
  }
  const savedIds = await getSavedListingIdSet(listings.map((l) => l.id));

  return (
    <>
      {/* ── The marketplace, immediately ── */}
      <section className="pb-12 pt-12 sm:pb-16 sm:pt-16">
        <Container>
          <SectionHeader
            as="h1"
            eyebrow="The marketplace"
            title="Live right now."
            action={{ href: "/browse", label: "Browse all" }}
          />
          {listings.length > 0 ? (
            <>
              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {listings.map((l, i) => (
                  <ListingCard key={l.id} listing={l} priority={i < 4} isSaved={savedIds.has(l.id)} />
                ))}
              </div>
              <div className="mt-9 text-center">
                <LinkButton href="/browse">Browse all tickets</LinkButton>
              </div>
            </>
          ) : (
            <EmptyState
              title="No live listings right now"
              message="New tickets drop all week. Check back soon or grab the app to get notified."
            />
          )}
        </Container>
      </section>

      {/* ── How it works — one compact horizontal row ── */}
      <section id="how-it-works" className="relative scroll-mt-24 overflow-hidden py-12 sm:py-16">
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
          <div className="mb-8 sm:mb-10">
            <p className="eyebrow text-primary/80">How it works</p>
            <h2 className="mt-4 font-display text-[clamp(1.7rem,3.2vw,2.4rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
              Three steps. One night.
            </h2>
          </div>
          <ol className="divide-y divide-primary/20 border-y border-primary/20 md:grid md:grid-cols-3 md:divide-x md:divide-y-0">
            {STEPS.map((step) => (
              <li key={step.n} className="py-6 md:px-8 md:py-7 md:first:pl-0 md:last:pr-0">
                <span
                  aria-hidden="true"
                  className="glow-red-subtle font-display text-[36px] font-bold leading-none tracking-[-0.03em] text-primary"
                >
                  {step.n}
                </span>
                <h3 className="mt-2.5 font-display text-[19px] font-bold uppercase tracking-tight text-ink">
                  {step.title}
                </h3>
                <p className="mt-1.5 text-[13.5px] leading-relaxed text-white/70">{step.body}</p>
              </li>
            ))}
          </ol>
        </Container>
      </section>

      {/* ── Sell on Snatch It ── */}
      <section id="sell" className="scroll-mt-24 border-t border-primary/15 py-14 sm:py-20">
        <Container>
          <div className="grid items-center gap-12 lg:grid-cols-2">
            <div>
              <p className="eyebrow text-primary/80">Sell on Snatch It</p>
              <h2 className="mt-4 max-w-[14ch] font-display text-[clamp(2rem,4vw,3rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
                Got a spare ticket? Sell it.
              </h2>
              <p className="mt-4 max-w-[44ch] text-[15px] leading-relaxed text-white/70">
                List it in minutes as an auction or Buy Now. You keep 90% of the sale, paid
                out through Stripe.
              </p>
              <LinkButton href="https://snatchitapp.com" size="lg" className="mt-7">
                Start selling
              </LinkButton>
            </div>
            <div className="grid grid-cols-3 gap-6 text-center lg:gap-8">
              {[
                { big: "90%", small: "of the sale is yours" },
                { big: "24h", small: "transfer window" },
                { big: "10%", small: "flat seller fee" },
              ].map((stat) => (
                <div key={stat.big}>
                  <p className="glow-red-subtle font-display text-[clamp(2.4rem,4.5vw,3.6rem)] font-bold leading-none tracking-[-0.03em] text-primary">
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
      <section className="relative overflow-hidden border-t border-primary/15 py-14 sm:py-20">
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
          <h2 className="mt-6 font-display text-[clamp(1.9rem,3.6vw,2.7rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
            Snatch It for iPhone
          </h2>
          <p className="mt-4 max-w-[42ch] text-[14.5px] leading-relaxed text-white/70">
            Live bidding, Buy Now, transfers, and seller payouts. Coming soon to the App
            Store.
          </p>
          <LinkButton href="https://snatchitapp.com" size="lg" className="mt-8">
            Visit snatchitapp.com
          </LinkButton>
        </Container>
      </section>
    </>
  );
}
