import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { coverImageUrl, getActiveListings, type WebListing } from "@/lib/listings";
import { allInFromDollars } from "@snatchit/core";
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
  const heroStack = listings.slice(0, 3);

  return (
    <>
      {/* ── Hero ─────────────────────────────────────────────────────── */}
      <section className="overflow-hidden border-b border-white/[0.06] bg-[#080B0F]">
        <Container className="grid items-center gap-12 py-16 lg:grid-cols-[minmax(0,1.05fr)_440px] lg:py-24">
          <div className="rise-in">
            <p className="eyebrow inline-flex items-center gap-2 rounded-[6px] bg-primary-soft px-2.5 py-1.5 text-[#ff7a75]">
              Miami · Peer-to-peer tickets
            </p>
            <h1 className="mt-6 max-w-[19ch] text-balance text-[clamp(2.4rem,5.5vw,4rem)] font-extrabold leading-[1.02] tracking-[-0.03em] text-ink">
              Sold-out night? Snatch a ticket from someone who can&apos;t go.
            </h1>
            <p className="mt-5 max-w-[52ch] text-[16px] leading-relaxed text-white/70 sm:text-[17px]">
              Bid or Buy Now on real tickets across Miami — clubs, festivals, arenas. Every
              price is all-in, and your money is held until the ticket is in your hands.
            </p>
            <SearchForm size="lg" className="mt-8 max-w-xl" />
            <ul className="mt-6 space-y-2">
              {TRUST_POINTS.map((point) => (
                <li key={point} className="flex items-center gap-2.5 text-[13.5px] font-medium text-white/70">
                  <CheckIcon />
                  {point}
                </li>
              ))}
            </ul>

            {/* Mobile inventory strip — real artwork above the fold */}
            {heroStack.length > 0 ? (
              <div className="mt-9 grid grid-cols-3 gap-2.5 lg:hidden">
                {heroStack.map((l) => (
                  <Link
                    key={l.id}
                    href={`/listing/${l.id}`}
                    className="group relative aspect-[4/3] overflow-hidden rounded-[10px] border border-white/10"
                    aria-label={`${l.event_name} at ${l.venue}`}
                  >
                    <Image
                      src={coverImageUrl(l.cover_image_path)}
                      alt=""
                      fill
                      sizes="30vw"
                      className="object-cover transition-transform duration-300 group-hover:scale-105 motion-reduce:transition-none"
                    />
                  </Link>
                ))}
              </div>
            ) : null}
          </div>

          {/* Fanned event-art stack — the marketplace, immediately */}
          {heroStack.length > 0 ? (
            <div className="rise-in relative hidden h-[440px] lg:block" aria-label="Live listings">
              {heroStack[2] ? (
                <HeroCard listing={heroStack[2]} className="left-0 top-10 w-[220px] -rotate-6" />
              ) : null}
              {heroStack[1] ? (
                <HeroCard listing={heroStack[1]} className="left-[110px] top-2 w-[240px] rotate-2" />
              ) : null}
              <HeroCard
                listing={heroStack[0]}
                className="right-0 top-6 z-10 w-[270px] rotate-[4deg]"
                showPrice
                priority
              />
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
      <section id="how-it-works" className="scroll-mt-24 py-16">
        <Container>
          <SectionHeader eyebrow="How it works" title="Three steps between you and the door" />
          <div className="grid gap-5 md:grid-cols-3">
            {[
              {
                n: "1",
                title: "Snatch it",
                body: "Place a bid or hit Buy Now. Checkout is Stripe-secured, and the price you see is the price you pay — fees included.",
              },
              {
                n: "2",
                title: "Get the transfer",
                body: "The seller sends your ticket through the platform it lives on — Ticketmaster, Posh, DICE, and more — with step-by-step instructions.",
              },
              {
                n: "3",
                title: "Confirm and go",
                body: "Confirm delivery and the seller gets paid. If the ticket isn't sent within 24 hours, you're refunded automatically.",
              },
            ].map((step) => (
              <div
                key={step.n}
                className="rounded-[12px] border border-white/[0.07] bg-card p-6"
              >
                <span className="flex size-9 items-center justify-center rounded-full bg-primary-soft text-[15px] font-extrabold text-[#ff7a75]">
                  {step.n}
                </span>
                <h3 className="mt-4 text-[17px] font-extrabold tracking-[-0.01em] text-ink">
                  {step.title}
                </h3>
                <p className="mt-2 text-[14px] leading-relaxed text-white/65">{step.body}</p>
              </div>
            ))}
          </div>
        </Container>
      </section>

      {/* ── Buyer protection ─────────────────────────────────────────── */}
      <section className="py-16">
        <Container>
          <div className="grid gap-10 rounded-[16px] border border-white/[0.07] bg-card p-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)] lg:p-11">
            <div>
              <p className="eyebrow mb-3 text-primary">Buyer protection</p>
              <h2 className="text-[26px] font-extrabold leading-[1.08] tracking-[-0.02em] text-ink sm:text-[30px]">
                Built so nobody gets burned.
              </h2>
              <p className="mt-4 max-w-[44ch] text-[14.5px] leading-relaxed text-white/70">
                Ticket resale runs on trust. We replaced trust with mechanics: your payment
                sits with Snatch It — not the seller — until the ticket is actually yours.
              </p>
            </div>
            <ul className="grid gap-x-8 gap-y-7 sm:grid-cols-2">
              {[
                {
                  icon: <LockIcon />,
                  title: "Stripe-secured payments",
                  body: "Cards and Apple Pay processed by Stripe. Snatch It never sees your card number.",
                },
                {
                  icon: <ShieldIcon />,
                  title: "Funds held until delivery",
                  body: "Sellers are paid only after you confirm the ticket arrived in your account.",
                },
                {
                  icon: <ClockIcon />,
                  title: "24-hour transfer deadline",
                  body: "If a seller doesn't send within 24 hours, the sale cancels and you're refunded in full.",
                },
                {
                  icon: <FlagIcon />,
                  title: "Report & dispute tools",
                  body: "Something off? Open a dispute and a human reviews it before any payout moves.",
                },
              ].map((item) => (
                <li key={item.title} className="flex gap-3.5">
                  <span className="flex size-10 shrink-0 items-center justify-center rounded-[10px] bg-white/[0.06]">
                    {item.icon}
                  </span>
                  <div>
                    <h3 className="text-[15px] font-bold text-ink">{item.title}</h3>
                    <p className="mt-1 text-[13.5px] leading-relaxed text-white/60">{item.body}</p>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </Container>
      </section>

      {/* ── Sell CTA ─────────────────────────────────────────────────── */}
      <section id="sell" className="scroll-mt-24 py-16">
        <Container>
          <div className="grid items-center gap-12 lg:grid-cols-2">
            <div>
              <p className="eyebrow mb-3 text-primary">Sell on Snatch It</p>
              <h2 className="text-[26px] font-extrabold leading-[1.08] tracking-[-0.02em] text-ink sm:text-[30px]">
                Plans changed? Your ticket still gets used.
              </h2>
              <p className="mt-4 max-w-[48ch] text-[14.5px] leading-relaxed text-white/70">
                List in minutes as an auction, Buy Now, or both. You keep 90% of the sale and
                get paid through Stripe once the buyer confirms delivery.
              </p>
              <ul className="mt-6 space-y-2.5">
                {[
                  "Flat 10% seller fee — nothing hidden",
                  "Payouts via Stripe Connect, straight to your bank",
                  "Proof-of-ownership review keeps the marketplace clean",
                ].map((point) => (
                  <li key={point} className="flex items-center gap-2.5 text-[13.5px] font-medium text-white/70">
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
                  className="rounded-[12px] border border-white/[0.07] bg-card p-5 text-center"
                >
                  <p className="text-[clamp(1.8rem,3.5vw,2.5rem)] font-extrabold leading-none tracking-[-0.02em] tabular-nums text-ink">
                    {stat.big}
                  </p>
                  <p className="mt-2.5 text-[12.5px] leading-snug text-muted">{stat.small}</p>
                </div>
              ))}
            </div>
          </div>
        </Container>
      </section>

      {/* ── App CTA ──────────────────────────────────────────────────── */}
      <section className="border-t border-white/[0.06] py-20">
        <Container className="flex flex-col items-center text-center">
          <Image
            src="/brand/sn-app-icon-1024.png"
            alt=""
            width={60}
            height={60}
            className="rounded-[14px] border border-white/10"
          />
          <h2 className="mt-6 text-[26px] font-extrabold tracking-[-0.02em] text-ink sm:text-[30px]">
            Snatch It for iPhone
          </h2>
          <p className="mt-3 max-w-[46ch] text-[14.5px] leading-relaxed text-white/70">
            The full marketplace — live bidding, Buy Now, transfers, and seller payouts — is in
            the iOS app. Coming soon to the App Store.
          </p>
          <LinkButton href="https://snatchitapp.com" variant="secondary" className="mt-8">
            Visit snatchitapp.com
          </LinkButton>
        </Container>
      </section>
    </>
  );
}

/** Rotated artwork card for the hero stack — real inventory, clickable. */
function HeroCard({
  listing,
  className = "",
  showPrice = false,
  priority = false,
}: {
  listing: WebListing;
  className?: string;
  showPrice?: boolean;
  priority?: boolean;
}) {
  const price = listing.buy_now_enabled && listing.buy_now_price ? listing.buy_now_price : listing.current_bid;
  return (
    <Link
      href={`/listing/${listing.id}`}
      className={`group absolute block overflow-hidden rounded-[14px] border border-white/[0.12] bg-card transition-transform duration-200 ease-[var(--ease-swift)] hover:z-20 hover:scale-[1.03] motion-reduce:transition-none motion-reduce:hover:scale-100 ${className}`}
      aria-label={`${listing.event_name} at ${listing.venue} — ${allInFromDollars(price)} total`}
    >
      <div className="relative aspect-[3/4]">
        <Image
          src={coverImageUrl(listing.cover_image_path)}
          alt=""
          fill
          priority={priority}
          sizes="270px"
          className="object-cover"
        />
        <div
          aria-hidden="true"
          className="absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-black/70 to-transparent"
        />
        <div className="absolute inset-x-3 bottom-3">
          <p className="truncate text-[13px] font-extrabold text-white">{listing.event_name}</p>
          <p className="mt-0.5 flex items-center justify-between gap-2">
            <span className="truncate text-[11.5px] font-medium text-white/75">{listing.venue}</span>
            {showPrice ? (
              <span className="shrink-0 rounded-[6px] bg-primary px-2 py-1 text-[12px] font-extrabold leading-none text-white">
                {allInFromDollars(price)}
              </span>
            ) : null}
          </p>
        </div>
      </div>
    </Link>
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
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-[18px] text-primary">
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

function LockIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-[18px] text-primary">
      <rect x="3.5" y="8.5" width="13" height="9" rx="2" stroke="currentColor" strokeWidth="1.6" />
      <path d="M6.5 8.5V6.3a3.5 3.5 0 1 1 7 0v2.2" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-[18px] text-primary">
      <circle cx="10" cy="10" r="7.5" stroke="currentColor" strokeWidth="1.6" />
      <path d="M10 6v4l2.7 1.8" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

function FlagIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-[18px] text-primary">
      <path
        d="M4.5 18V3.2m0 0c1.8-1.1 3.6-1.1 5.5 0s3.7 1.1 5.5 0v8.2c-1.8 1.1-3.6 1.1-5.5 0s-3.7-1.1-5.5 0"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
