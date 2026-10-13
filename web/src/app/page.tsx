import type { Metadata } from "next";
import Image from "next/image";
import { getActiveListings, type WebListing } from "@/lib/listings";
import { homeSection, type HomeSection } from "@/lib/listing-display";
import { Container } from "@/components/ui/Container";
import { SectionHeader } from "@/components/ui/SectionHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton, ArrowLink } from "@/components/ui/Button";
import { FeedRow } from "@/components/listing/FeedRow";
import { ListingFeature } from "@/components/listing/ListingFeature";
import { REFUND_SHORT, SELLER_TERMS } from "@/lib/policy-wording";

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
    body: REFUND_SHORT,
  },
] as const;

const ORDER: (HomeSection | null)[] = ["Tonight", "This week", "Later", null];

/** Native Home grouping: reorders, never filters, and keeps the feed's own order inside each section. */
function groupBySection(listings: WebListing[], now: Date) {
  const groups = new Map<HomeSection | null, WebListing[]>();
  for (const l of listings) {
    const key = homeSection(l.event_date, now);
    groups.set(key, [...(groups.get(key) ?? []), l]);
  }
  return ORDER.filter((k) => groups.has(k)).map((k) => ({ label: k, items: groups.get(k)! }));
}

export default async function HomePage() {
  // Deliberately NOT wrapped in try/catch. It used to be, which turned a
  // database outage into the cheerful "No live listings right now" empty
  // state — every visitor saw an empty marketplace and no one saw a problem.
  // /browse already lets this throw. Letting it throw here too routes to
  // app/error.tsx, which reports to Sentry and offers a retry.
  const listings = await getActiveListings({}, 12);
  const now = new Date();
  const sections = groupBySection(listings, now);
  const [feature] = sections[0]?.items ?? [];

  return (
    <>
      <Container className="pt-5 sm:pt-8 lg:pt-10">
        <h1 className="sr-only">Live tickets on Snatch It</h1>
        {listings.length === 0 ? (
          <EmptyState
            icon="ticket"
            title="No live listings right now"
            message="New tickets drop all week. Selling something? List it in under a minute."
            action={<LinkButton href="/sell">Sell your tickets</LinkButton>}
          />
        ) : (
          <div className="space-y-10 lg:space-y-14">
            {sections.map((section, si) => {
              const rows = si === 0 ? section.items.slice(1) : section.items;
              return (
                <section key={section.label ?? "undated"} aria-label={section.label ?? "More listings"}>
                  {section.label ? (
                    <SectionHeader
                      title={section.label}
                      action={si === 0 ? { href: "/browse", label: "Browse all" } : undefined}
                      className="mb-4"
                    />
                  ) : (
                    <div className="mb-4 border-b border-line" />
                  )}
                  {si === 0 && feature ? (
                    <div className="mb-6 lg:mb-8">
                      <ListingFeature listing={feature} now={now} />
                    </div>
                  ) : null}
                  {rows.length > 0 ? (
                    <ul className="grid grid-cols-[minmax(0,1fr)] lg:grid-cols-2 lg:gap-x-12">
                      {rows.map((l) => (
                        <li key={l.id} className="border-b border-line last:border-b-0 lg:[&:nth-last-child(2):nth-child(odd)]:border-b-0">
                          <FeedRow listing={l} now={now} />
                        </li>
                      ))}
                    </ul>
                  ) : null}
                </section>
              );
            })}
            <div className="flex flex-wrap items-center justify-between gap-4 rounded-panel bg-surface px-5 py-4">
              <p className="t-body text-ink-2">Every price includes fees. Filter by neighborhood, price or sale type.</p>
              <LinkButton href="/browse" variant="secondary">
                Browse all tickets
              </LinkButton>
            </div>
          </div>
        )}
      </Container>

      {/* ── How it works ── */}
      <section id="how-it-works" aria-labelledby="how-title" className="mt-16 scroll-mt-24 sm:mt-20">
        <Container>
          <p className="t-micro text-muted">How it works</p>
          <h2 id="how-title" className="t-display-md mt-2 text-ink lg:t-display-lg">
            Three steps. One night.
          </h2>
          <ol className="mt-6 grid gap-px overflow-hidden rounded-card border border-line bg-line md:grid-cols-3">
            {STEPS.map((step) => (
              <li key={step.n} className="bg-canvas p-6 lg:p-8">
                <span aria-hidden="true" className="t-display-md text-brand-text">
                  {step.n}
                </span>
                <h3 className="t-title mt-3 text-ink">{step.title}</h3>
                <p className="t-body mt-1.5 text-muted">{step.body}</p>
              </li>
            ))}
          </ol>
        </Container>
      </section>

      {/* ── Sell on Snatch It ── */}
      <section id="sell" aria-labelledby="sell-title" className="mt-16 scroll-mt-24 sm:mt-20">
        <Container>
          <div className="grid overflow-hidden rounded-card bg-surface lg:grid-cols-[1.1fr_1fr]">
            <div className="p-6 sm:p-10 lg:p-12">
              <p className="t-micro text-muted">Sell on Snatch It</p>
              <h2 id="sell-title" className="t-display-md mt-2 max-w-[16ch] text-ink lg:t-display-lg">
                Got a spare ticket? Sell it.
              </h2>
              <p className="t-body mt-3 max-w-[46ch] text-ink-2">
                List it in minutes as an auction or Buy Now. {SELLER_TERMS}
              </p>
              <dl className="mt-7 grid max-w-md grid-cols-3 gap-4">
                {[
                  { big: "90%", small: "of the sale price is yours" },
                  { big: "24h", small: "transfer window" },
                  { big: "10%", small: "marketplace fee" },
                ].map((stat) => (
                  <div key={stat.big}>
                    <dt className="sr-only">{stat.small}</dt>
                    <dd>
                      <span className="t-display-md block text-ink">{stat.big}</span>
                      <span className="t-body-sm mt-1 block text-muted">{stat.small}</span>
                    </dd>
                  </div>
                ))}
              </dl>
              <LinkButton href="/sell" size="lg" className="mt-8">
                Start selling
              </LinkButton>
            </div>
            <div className="relative hidden min-h-[320px] lg:block">
              <Image src="/atmosphere/concert-lights.jpg" alt="" fill sizes="(min-width: 1024px) 540px, 0px" className="object-cover" />
            </div>
          </div>
        </Container>
      </section>

      {/* ── App ── */}
      <section aria-labelledby="app-title" className="mt-16 sm:mt-20">
        <Container>
          <div className="flex flex-col items-start gap-6 border-t border-line pt-10 sm:flex-row sm:items-center">
            <Image src="/brand/sn-app-icon-1024.png" alt="" width={64} height={64} className="rounded-[14px]" />
            <div className="min-w-0 flex-1">
              <h2 id="app-title" className="t-title text-ink">
                Snatch It for iPhone
              </h2>
              <p className="t-body mt-1 max-w-[52ch] text-muted">
                Live bidding, Buy Now, transfers, and seller payouts — the whole marketplace, in your pocket.
              </p>
            </div>
            <ArrowLink href="https://snatchitapp.com">Visit snatchitapp.com</ArrowLink>
          </div>
        </Container>
      </section>
    </>
  );
}
