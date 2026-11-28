import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Listing amounts are whole dollars; the console's money display takes cents.
 *
 * The owner saw a $291 buy-now price as "$2.91" and a $211 bid as "$2.11" on the v2 preview:
 * ops.listing_summary / ops.listing_detail return public.listings and public.bids amounts as
 * stored (whole dollars, 000_baseline_schema.sql:85-95,145; 004: "bids.amount is also stored in
 * DOLLARS"), and the console passed them to <Money cents>, which divides by 100. The fix converts
 * once, where RPC data becomes console data (toListingSummary / toListingDetail, and the listing
 * subject snapshot). Payments are true cents and must not change.
 */
const mocks = vi.hoisted(() => ({ callOps: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new Error("notFound");
  },
  redirect: () => {
    throw new Error("redirect");
  },
  usePathname: () => "/",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({
  requireOperator: vi.fn(async () => ({ id: "0fa1b2c3-d4e5-4f6a-8b7c-9d0e1f2a3b4c", email: null, aal: "aal2", role: "platform_admin", whoami: { role: "platform_admin" } })),
}));

import { formatMoney } from "@/lib/format";
import { listingDollarsToCents } from "@/lib/listing-money";
import { toListingDetail, toListingSummary, toOrderRows } from "@/lib/types";
import { renderSubjectValue } from "@/components/generic/GenericRpc";
import { ListingTable } from "@/components/marketplace/ListingTable";
import { OrderTable } from "@/components/orders/OrderTable";
import ListingPage from "@/app/(console)/marketplace/[id]/page";
import CasePage from "@/app/(console)/cases/[id]/page";
import ActionPage from "@/app/(console)/actions/[id]/page";

const LISTING = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d";
const SELLER = "5e1ab2c3-d4e5-4f6a-9b7c-8d9e0f1a2b3c";
const BIDDER = "b1dde2f3-a4b5-4c6d-8e7f-9a0b1c2d3e4f";
const CASE = "c4a5e6f7-a8b9-4cad-9ebf-a0b1c2d3e4f5";
const ACTION = "ac7e0b1c-d2e3-4f4a-8b5c-6d7e8f9a0b1c";

/** One listing as ops.listing_summary sends it: whole dollars. The owner's "Anotr" listing: buy now $291, bid $211. */
const serverListing = (over: Record<string, unknown> = {}) => ({
  id: LISTING,
  event_name: "Anotr",
  venue: "Room",
  status: "active",
  auction_status: "active",
  proof_status: "approved",
  seller_id: SELLER,
  buy_now_enabled: true,
  buy_now_price: 291,
  starting_bid: 150,
  current_bid: 211,
  bid_count: 2,
  winner_user_id: BIDDER,
  winning_bid_amount: 211,
  ends_at: "2026-12-01T00:00:00Z",
  created_at: "2026-11-01T00:00:00Z",
  ...over,
});

const centsIn = (html: string) => [...html.matchAll(/data-cents="(-?\d+)"/g)].map((m) => Number(m[1]));
const WRONG = ["$2.91", "$2.11", "$1.50"];

describe("whole dollars → cents", () => {
  it("291 → $291.00 and 211 → $211.00", () => {
    expect(listingDollarsToCents(291)).toBe(29100);
    expect(formatMoney(listingDollarsToCents(291))).toBe("$291.00 USD");
    expect(listingDollarsToCents(211)).toBe(21100);
    expect(formatMoney(listingDollarsToCents(211))).toBe("$211.00 USD");
    expect(listingDollarsToCents("291")).toBe(29100);
  });
  it("29100 cents (a payment) → $291.00, unchanged", () => {
    expect(formatMoney(29100)).toBe("$291.00 USD");
  });
  it("NEGATIVE CONTROL — the defect: whole dollars passed straight to the cents formatter", () => {
    expect(formatMoney(291)).toBe("$2.91 USD");
    expect(formatMoney(211)).toBe("$2.11 USD");
  });
  it("missing → null (shown as —)", () => {
    for (const v of [null, undefined]) {
      expect(listingDollarsToCents(v)).toBeNull();
      expect(formatMoney(listingDollarsToCents(v))).toBe("—");
    }
  });
  it("zero → $0.00, a real value, not —", () => {
    expect(listingDollarsToCents(0)).toBe(0);
    expect(formatMoney(listingDollarsToCents(0))).toBe("$0.00 USD");
  });
  it("invalid → null: fractional, non-numeric, non-finite, unsafe", () => {
    for (const v of [2.5, "2.5", "abc", "", " ", Number.NaN, Number.POSITIVE_INFINITY, true, {}, [], Number.MAX_SAFE_INTEGER]) {
      expect(listingDollarsToCents(v), JSON.stringify(v)).toBeNull();
    }
  });
});

describe("the parse boundary carries cents under explicit names", () => {
  it("toListingSummary converts every listing amount", () => {
    const l = toListingSummary(serverListing())!;
    expect(l.buy_now_price_cents).toBe(29100);
    expect(l.starting_bid_cents).toBe(15000);
    expect(l.current_bid_cents).toBe(21100);
    expect(l.winning_bid_cents).toBe(21100);
    // the whole-dollar names do not survive onto the typed row, so nothing can pass them to <Money>
    for (const k of ["buy_now_price", "starting_bid", "current_bid", "winning_bid_amount"]) expect(l).not.toHaveProperty(k);
  });
  it("toListingSummary: missing amounts stay null", () => {
    const l = toListingSummary(serverListing({ buy_now_enabled: false, buy_now_price: null, current_bid: undefined, winning_bid_amount: null }))!;
    expect(l.buy_now_price_cents).toBeNull();
    expect(l.current_bid_cents).toBeNull();
    expect(l.winning_bid_cents).toBeNull();
  });
  it("toListingDetail converts the highest bid and each recent bid", () => {
    const d = toListingDetail({ listing: serverListing(), bids: { count: 2, highest: 211, highest_bidder_id: BIDDER, recent: [{ id: "1", amount: 211 }, { id: "2", amount: 200 }] } })!;
    expect(d.bids.highest_cents).toBe(21100);
    expect(d.bids.recent.map((b) => b.amount_cents)).toEqual([21100, 20000]);
  });
});

describe("listing rows", () => {
  it("buy now $291.00 and bid $211.00", () => {
    const html = renderToStaticMarkup(createElement(ListingTable, { rows: [toListingSummary(serverListing())!], basePath: "/marketplace" }));
    expect(html).toContain("$291.00 USD");
    expect(html).toContain("$211.00 USD");
    for (const w of WRONG) expect(html).not.toContain(w);
  });
  it("no current bid falls back to the starting bid, in cents", () => {
    const html = renderToStaticMarkup(createElement(ListingTable, { rows: [toListingSummary(serverListing({ buy_now_enabled: false, current_bid: null }))!], basePath: "/marketplace" }));
    expect(html).toContain("$150.00 USD");
    expect(html).toContain("no buy now");
  });
  it("sorting by price uses the same cents the cell shows", () => {
    const html = renderToStaticMarkup(createElement(ListingTable, { rows: [toListingSummary(serverListing())!], basePath: "/marketplace" }));
    expect(html).toContain('data-sort-value="29100"');
  });
});

describe("listing page: listing, highest bid, recent bids, winner", () => {
  beforeEach(() => {
    mocks.callOps.mockReset().mockImplementation(async (fn: string) =>
      fn === "listing_detail"
        ? {
            ok: true,
            data: {
              listing: serverListing(),
              seller: null,
              payments: [],
              transfer: null,
              bids: { count: 2, highest: 211, highest_bidder_id: BIDDER, recent: [{ id: "d1e2f3a4-b5c6-4d7e-8f9a-0b1c2d3e4f5a", amount: 211, bidder_id: BIDDER, created_at: "2026-11-01T12:00:00Z" }, { id: "e2f3a4b5-c6d7-4e8f-9a0b-1c2d3e4f5a6b", amount: 200, bidder_id: BIDDER, created_at: "2026-11-01T11:00:00Z" }] },
              reports: [],
              seller_flags: [],
              cases: [],
              actions: [],
              evidence: [],
            },
          }
        : { ok: false, kind: "error", message: `unexpected call ${fn}` },
    );
  });
  it("every amount is in cents and matches the app", async () => {
    const html = renderToStaticMarkup(await ListingPage({ params: Promise.resolve({ id: LISTING }) }));
    const cents = centsIn(html);
    // listing panel: buy now, starting bid, current bid, winning bid
    expect(cents).toEqual(expect.arrayContaining([29100, 15000, 21100, 20000]));
    // 211 appears as current bid, winning bid, highest bid and the newest recent bid
    expect(cents.filter((c) => c === 21100).length).toBeGreaterThanOrEqual(4);
    expect(html).toContain("$291.00 USD");
    expect(html).toContain("$200.00 USD");
    for (const w of [...WRONG, "$2.00"]) expect(html).not.toContain(w);
    for (const raw of [291, 211, 150, 200]) expect(cents).not.toContain(raw);
  });
});

describe("subject snapshot of a listing (case and action pages)", () => {
  it("renderSubjectValue converts only the listing's dollar keys", () => {
    const html = (k: string, v: unknown, kind = "listing") => renderToStaticMarkup(createElement("div", null, renderSubjectValue(kind, k, v)));
    expect(html("buy_now_price", 291)).toContain("$291.00 USD");
    expect(html("starting_bid", 150)).toContain("$150.00 USD");
    expect(html("current_bid", 211)).toContain("$211.00 USD");
    expect(html("winning_bid_amount", 211)).toContain("$211.00 USD");
    expect(html("buy_now_price", null)).toContain("—");
    expect(html("current_bid", "abc")).toContain("—");
    expect(html("current_bid", 0)).toContain("$0.00 USD");
    // NEGATIVE CONTROLS: a count is not money; a payment's amount is already cents
    expect(html("bid_count", 3)).not.toContain("$");
    expect(html("amount", 29100, "payment")).toContain("$291.00 USD");
  });

  it("the case page shows a listing subject in cents", async () => {
    mocks.callOps.mockReset().mockImplementation(async (fn: string) =>
      fn === "case_detail"
        ? { ok: true, data: { case: { id: CASE, case_type: "manual", status: "open", priority: "normal", version: 1, subject_kind: "listing", subject_id: LISTING, created_at: "2026-11-01T00:00:00Z" }, notes: [], events: [], operators: [], actions: [], subject: serverListing() } }
        : { ok: false, kind: "error", message: `unexpected call ${fn}` },
    );
    const html = renderToStaticMarkup(await CasePage({ params: Promise.resolve({ id: CASE }) }));
    expect(centsIn(html)).toEqual(expect.arrayContaining([29100, 15000, 21100]));
    for (const w of WRONG) expect(html).not.toContain(w);
    expect(html).not.toMatch(/>\s*211\s*</); // current_bid used to render as a bare number
  });

  it("the action page shows a listing subject in cents", async () => {
    mocks.callOps.mockReset().mockImplementation(async (fn: string) =>
      fn === "action_detail"
        ? { ok: true, data: { action: { id: ACTION, action_type: "listing_relist", state: "succeeded", subject_kind: "listing", subject_id: LISTING, requested_at: "2026-11-01T00:00:00Z", params: {}, expected: {} }, approvals: [], audit: [], subject: serverListing(), related_cases: [] } }
        : { ok: false, kind: "error", message: `unexpected call ${fn}` },
    );
    const html = renderToStaticMarkup(await ActionPage({ params: Promise.resolve({ id: ACTION }) }));
    expect(centsIn(html)).toEqual(expect.arrayContaining([29100, 15000, 21100]));
    for (const w of WRONG) expect(html).not.toContain(w);
  });
});

describe("payments stay in cents", () => {
  it("NEGATIVE CONTROL — an order of 29100 cents shows $291.00, not $29,100.00", () => {
    const rows = toOrderRows([{ payment_id: "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d", amount: 29100, buyer_fee: 2910, total: 32010, status: "succeeded", created_at: "2026-11-01T00:00:00Z" }]);
    const html = renderToStaticMarkup(createElement(OrderTable, { rows, basePath: "/orders" }));
    expect(html).toContain("$291.00 USD");
    expect(html).not.toContain("$29,100.00");
  });
});
