import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// Owner (via A, 2026-10-15): a waived listing must make the waiver clear BEFORE purchase — on the
// listing's purchase panel and at checkout — and nothing on a card or page may imply Snatch It
// verified or reviewed the ticket proof.

vi.mock("@/lib/env", () => ({ STRIPE_PUBLISHABLE_KEY: null }));
vi.mock("@/lib/checkout-actions", () => ({ createPaymentIntentAction: async () => ({}) }));
vi.mock("@stripe/stripe-js", () => ({ loadStripe: () => null }));
vi.mock("@stripe/react-stripe-js", () => ({ Elements: () => null }));
vi.mock("next/image", () => ({ default: () => null }));
vi.mock("@/components/checkout/PaymentForm", () => ({ PaymentForm: () => null }));

import { CheckoutClient } from "@/components/checkout/CheckoutClient";
import { ProofWaiverNotice } from "@/components/listing/ProofWaiverNotice";

const SRC = path.resolve(__dirname, "../src");
const read = (rel: string) => readFileSync(path.join(SRC, rel), "utf8");

const checkout = (proofWaived?: boolean) =>
  renderToStaticMarkup(
    createElement(CheckoutClient, {
      listingId: "l",
      mode: "buy_now",
      eventName: "Show",
      venue: "Club",
      baseDollars: 100,
      ...(proofWaived === undefined ? {} : { proofWaived }),
    }),
  );

describe("the waiver is disclosed before purchase", () => {
  it("the notice states the waiver and claims no verification", () => {
    const html = renderToStaticMarkup(createElement(ProofWaiverNotice));
    expect(html).toContain("Ticket proof waived by Snatch It");
    expect(html).not.toMatch(/verif|review/i);
  });

  it("checkout: the order summary carries it for a waived listing, above the payment form", () => {
    const html = checkout(true);
    const note = html.indexOf("Ticket proof waived by Snatch It");
    expect(note).toBeGreaterThan(-1);
    expect(note).toBeLessThan(html.indexOf('id="payment-title"'));
  });

  it("checkout: nothing for an ordinary listing (default off)", () => {
    expect(checkout(false)).not.toContain("Ticket proof waived");
    expect(checkout()).not.toContain("Ticket proof waived");
  });

  it("the checkout page passes the listing's waiver through", () => {
    expect(read("app/checkout/[id]/page.tsx")).toContain("proofWaived={proofWaiverNote(listing) !== null}");
  });

  it("listing page: every purchase block (#buy) opens with the notice — Buy Now/bid, pay for a win, finish checkout", () => {
    const src = read("app/listing/[id]/page.tsx");
    const blocks = src.split('id="buy"').slice(1);
    expect(blocks).toHaveLength(3);
    for (const b of blocks) {
      const notice = b.indexOf("{proofNote ? <ProofWaiverNotice /> : null}");
      expect(notice).toBeGreaterThan(-1);
      // before the first control in the block
      const firstControl = Math.min(...["<BuyNowButton", "<BidPanel", "<LinkButton"].map((t) => b.indexOf(t)).filter((i) => i >= 0));
      expect(notice).toBeLessThan(firstControl);
    }
  });
});

describe("no listing-level verified/reviewed claim", () => {
  const files = (dir: string): string[] =>
    readdirSync(dir).flatMap((f) => {
      const p = path.join(dir, f);
      return statSync(p).isDirectory() ? files(p) : p.endsWith(".tsx") ? [p] : [];
    });

  it("cards and feed rows (home, browse, related) show no 'Verified' or 'reviewed' text", () => {
    const cardFiles = [
      path.join(SRC, "components/ListingCard.tsx"),
      path.join(SRC, "components/listing/FeedRow.tsx"),
      path.join(SRC, "components/listing/ListingFeature.tsx"),
      ...files(path.join(SRC, "components/browse")),
    ];
    for (const f of cardFiles) expect(readFileSync(f, "utf8"), f).not.toMatch(/verified|reviewed/i);
  });

  it("the only 'Verified' badges are seller/buyer badges, never a ticket or proof claim", () => {
    for (const f of files(SRC)) {
      const s = readFileSync(f, "utf8");
      // Natural-language claims only (identifiers like is_verified_seller don't count).
      expect(s, f).not.toMatch(
        /\b(ticket|proof)s?( has| have| is| was| were)?( been)? (verified|reviewed|checked)\b|\b(verified|reviewed|checked) (ticket|proof)|\b(verified|reviewed) by snatch it/i,
      );
      // A bare literal "Verified" badge is gone; the listing page goes through sellerVerifiedLabel.
      expect(s, f).not.toMatch(/>Verified<\/Badge>/);
    }
  });
});
