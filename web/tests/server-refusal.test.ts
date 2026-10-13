import { beforeEach, describe, expect, it, vi } from "vitest";

// The four web write paths that migration 152 can refuse, driven through a fake Supabase client:
// the refusal's hint decides the sentence, and anything else keeps the copy web showed before.
const h = vi.hoisted(() => ({ resolve: ((): unknown => ({ error: null })) as (target: string) => unknown }));

vi.mock("server-only", () => ({}));
vi.mock("@/lib/payouts", () => ({ getPayoutStatus: async () => ({ status: "connected" }) }));
vi.mock("@/lib/edge-functions", () => ({ callEdgeFunction: async () => ({}) }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    from(table: string) {
      const ops: string[] = [];
      const builder: unknown = new Proxy(
        {},
        {
          get(_t, prop) {
            if (prop === "then") {
              return (ok: (v: unknown) => unknown, fail: (e: unknown) => unknown) =>
                Promise.resolve(h.resolve(`${table}.${ops.join(".")}`)).then(ok, fail);
            }
            return () => {
              ops.push(String(prop));
              return builder;
            };
          },
        },
      );
      return builder;
    },
    rpc: async (name: string) => h.resolve(`rpc:${name}`),
  }),
}));

import {
  PROHIBITED_CONTENT_FALLBACK,
  REFUSAL_COPY,
  prohibitedContentMessage,
  readServerRefusal,
} from "@/lib/server-refusal";
import { placeBid } from "@/lib/bids";
import { reserveBuyNow } from "@/lib/checkout";
import { createListing } from "@/lib/create-listing";
import { updateSellerListing } from "@/lib/seller-listings";

/** A PostgREST error shaped like 152's RAISE (P0001, sentence in message, code in hint). */
const pg = (hint: string | null, extra: { message?: string; details?: string | null } = {}) => ({
  code: "P0001",
  message: extra.message ?? "refused",
  details: extra.details ?? null,
  hint,
});

const K2 = {
  BLOCKED_PARTY: "This listing isn't available to you.",
  LISTING_UNAVAILABLE: "This listing isn't available right now.",
  ACCOUNT_SUSPENDED:
    "Your account is suspended, so you can't bid, buy or create listings. Orders you already have aren't affected. Contact support@snatchitapp.com.",
};

describe("readServerRefusal (POLICY_WORDING K2)", () => {
  it("maps the three fixed refusals to the canonical sentences", () => {
    expect(REFUSAL_COPY).toEqual(K2);
    for (const code of Object.keys(K2) as (keyof typeof K2)[]) {
      expect(readServerRefusal(pg(code))).toEqual({ code, message: K2[code] });
    }
  });

  it("names the term for PROHIBITED_CONTENT from details, then the message, else the fallback", () => {
    expect(readServerRefusal(pg("PROHIBITED_CONTENT", { details: "weed" }))?.message).toBe(
      prohibitedContentMessage("weed"),
    );
    expect(
      readServerRefusal(pg("PROHIBITED_CONTENT", { message: 'Listings can\'t mention "molly". Please revise…' }))
        ?.message,
    ).toBe(prohibitedContentMessage("molly"));
    expect(readServerRefusal(pg("PROHIBITED_CONTENT"))?.message).toBe(PROHIBITED_CONTENT_FALLBACK);
  });

  it("is null for anything that is not exactly one of the four hints", () => {
    expect(readServerRefusal(null)).toBeNull();
    expect(readServerRefusal("BLOCKED_PARTY")).toBeNull();
    expect(readServerRefusal(pg(null, { message: K2.BLOCKED_PARTY }))).toBeNull();
    expect(readServerRefusal(pg("blocked_party"))).toBeNull();
    expect(readServerRefusal(pg(" BLOCKED_PARTY"))).toBeNull();
    expect(readServerRefusal(pg("SOMETHING_ELSE"))).toBeNull();
  });

  it("never invites a retry for a block or a suspension", () => {
    expect(K2.BLOCKED_PARTY).not.toMatch(/try again/i);
    expect(K2.ACCOUNT_SUSPENDED).not.toMatch(/try again/i);
  });
});

describe("web write paths show the refusal, and keep their old copy otherwise", () => {
  beforeEach(() => {
    h.resolve = () => ({ error: null });
  });

  it("bid insert", async () => {
    h.resolve = (t) => (t === "bids.insert" ? { error: pg("BLOCKED_PARTY") } : { error: null });
    expect(await placeBid("l", "u", 50)).toEqual({ error: K2.BLOCKED_PARTY });

    h.resolve = (t) => (t === "bids.insert" ? { error: pg("ACCOUNT_SUSPENDED") } : { error: null });
    expect(await placeBid("l", "u", 50)).toEqual({ error: K2.ACCOUNT_SUSPENDED });

    h.resolve = () => ({ error: { message: "This auction has ended", hint: null } });
    expect(await placeBid("l", "u", 50)).toEqual({ error: "This auction has ended." });
  });

  it("Buy Now reservation", async () => {
    h.resolve = (t) => (t === "rpc:reserve_buy_now" ? { error: pg("LISTING_UNAVAILABLE") } : { error: null });
    expect(await reserveBuyNow("l", "u")).toEqual({ error: K2.LISTING_UNAVAILABLE });

    h.resolve = () => ({ error: { message: "Listing already reserved", hint: null } });
    expect(await reserveBuyNow("l", "u")).toEqual({ error: "Reserved by another buyer. Try again in a few minutes." });
  });

  const payload = {
    eventName: "Show",
    venue: "Club",
    neighborhood: "wynwood",
    eventDate: "2026-11-01",
    eventTime: "22:00",
    ticketType: "GA",
    quantity: 1,
    transferMethod: "app",
    restrictions: null,
    startingBid: 20,
    buyNowEnabled: false,
    buyNowPrice: null,
    durationHours: 24,
    ticketPlatform: "other",
    coverImagePath: "c",
    proofImagePath: "p",
    sellerCommitmentAccepted: true,
    category: "clubs",
  } as unknown as Parameters<typeof createListing>[1];

  it("listing insert", async () => {
    h.resolve = (t) =>
      t === "listings.insert.select.single" ? { data: null, error: pg("PROHIBITED_CONTENT", { details: "weed" }) } : {};
    expect(await createListing("u", payload)).toEqual({ error: prohibitedContentMessage("weed") });

    h.resolve = (t) =>
      t === "listings.insert.select.single" ? { data: null, error: pg("ACCOUNT_SUSPENDED") } : {};
    expect(await createListing("u", payload)).toEqual({ error: K2.ACCOUNT_SUSPENDED });

    h.resolve = () => ({ data: null, error: { message: "new row violates row-level security policy", hint: null } });
    expect((await createListing("u", payload)).error).toMatch(/^You don't have permission to create a listing yet/);
  });

  it("listing text edit", async () => {
    const id = "b0000000-0000-4000-8000-000000000001";
    const listing = {
      id,
      status: "active",
      auction_status: "active",
      ends_at: new Date(Date.now() + 86_400_000).toISOString(),
      reserved_until: null,
    };
    const base = (t: string): unknown => {
      if (t === "listings.select.eq.order") return { data: [listing], error: null };
      if (t === "transfers.select.eq") return { data: [] };
      if (t.startsWith("bids.")) return { data: [], count: 0 };
      return { error: null };
    };
    const fields = { eventName: "Show", venue: "Club", restrictions: null, ticketPlatform: "other" };

    h.resolve = (t) => (t === "listings.update.eq.eq" ? { error: pg("ACCOUNT_SUSPENDED") } : base(t));
    expect(await updateSellerListing("u", id, fields)).toEqual({ error: K2.ACCOUNT_SUSPENDED });

    h.resolve = (t) =>
      t === "listings.update.eq.eq" ? { error: { message: "Listing not found", hint: null } } : base(t);
    expect(await updateSellerListing("u", id, fields)).toEqual({ error: "This listing no longer exists." });

    // The pre-check answers before any write, with the server's sentence.
    h.resolve = base;
    expect(await updateSellerListing("u", id, { ...fields, venue: "Open bar rooftop" })).toEqual({
      error: prohibitedContentMessage("open bar"),
    });
  });
});
