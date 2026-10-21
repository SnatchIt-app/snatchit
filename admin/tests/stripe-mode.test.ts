import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { stripeModeOf } from "../src/lib/format";

/**
 * "Stripe mode" on the order page's Payment panel, from payments.stripe_livemode
 * (migration 045). ops.order_detail returns the column through ops.payment_json,
 * which is to_jsonb(p) minus the client secret (116:172-176), so the field is in
 * the payload; pre-045 rows carry null. Column comment: true = live, false =
 * test-era, null = unclassified.
 *
 * Truth rule: only a literal `true` reads as Live and only a literal `false` as
 * Test. A recorded null says automation fails closed (ops-refund-execute refuses
 * row_mode_unclassified; claim_payout_attempt raises PAYMENT_NOT_LIVE). A missing
 * or non-boolean field is not a recorded null, so it claims nothing about what
 * automation will do, only that the console can't tell.
 */

describe("stripeModeOf — the label states what the record establishes", () => {
  it("true → Live, no note", () => {
    expect(stripeModeOf({ stripe_livemode: true })).toEqual({ mode: "live", label: "Live", note: null });
  });

  it("false → Test, no note", () => {
    expect(stripeModeOf({ stripe_livemode: false })).toEqual({ mode: "test", label: "Test", note: null });
  });

  it("null → Unclassified, with the fail-closed note and the stop-and-ask-the-owner rule", () => {
    const m = stripeModeOf({ stripe_livemode: null });
    expect(m.mode).toBe("unclassified");
    expect(m.label).toBe("Unclassified");
    expect(m.note).toContain("fail closed");
    expect(m.note).toContain("a manual refund must stop here and go to the owner");
  });

  it("field missing (or no record at all) → Unclassified (not provided by the server)", () => {
    for (const rec of [{}, { stripe_livemode: undefined }, null, undefined]) {
      const m = stripeModeOf(rec as Record<string, unknown> | null | undefined);
      expect(m.mode, JSON.stringify(rec)).toBe("not_provided");
      expect(m.label).toBe("Unclassified (not provided by the server)");
      expect(m.note).toContain("a manual refund must stop here and go to the owner");
      // Nothing recorded a null, so the note must not claim what automation will do.
      expect(m.note).not.toContain("fail closed");
    }
  });

  it("a non-boolean value is unrecognised, never Live or Test", () => {
    for (const v of ["true", "false", 1, 0, "live", {}]) {
      const m = stripeModeOf({ stripe_livemode: v });
      expect(m.mode, JSON.stringify(v)).toBe("unrecognised");
      expect(m.label).toBe("Unclassified (unrecognised value)");
      expect(m.note).toContain("a manual refund must stop here and go to the owner");
      expect(m.note).not.toContain("fail closed");
    }
  });

  it("only a literal true can read as Live", () => {
    for (const v of [false, null, undefined, "true", 1, "live"]) {
      expect(stripeModeOf({ stripe_livemode: v }).label, JSON.stringify(v)).not.toContain("Live");
    }
  });

  // Control: the negative assertions above are not vacuous — both definite labels are reachable.
  it("CONTROL: Live and Test are both reachable", () => {
    expect(stripeModeOf({ stripe_livemode: true }).label).toBe("Live");
    expect(stripeModeOf({ stripe_livemode: false }).label).toBe("Test");
  });
});

// ---------------------------------------------------------------------------
// The real order page, data layer mocked (same harness as order-money-guard).

const mocks = vi.hoisted(() => ({ callOps: vi.fn(), requireOperator: vi.fn() }));

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new Error("notFound");
  },
  redirect: () => {
    throw new Error("redirect");
  },
  usePathname: () => "/orders",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import OrderPage from "@/app/(console)/orders/[paymentId]/page";

const PAY = "9a900000-0000-4000-8000-0000000000e1";
const TR = "7a000000-0000-4000-8000-0000000000e1";
const LISTING = "1a000000-0000-4000-8000-0000000000e1";
const MISSING = Symbol("missing");

function orderDetail(livemode: unknown) {
  const payment: Record<string, unknown> = { id: PAY, status: "succeeded", total: 9900, amount: 9000, buyer_fee: 900, seller_fee: 450, listing_id: LISTING };
  if (livemode !== MISSING) payment.stripe_livemode = livemode;
  return {
    payment,
    transfer: { id: TR, payment_id: PAY, status: "seller_sent", payout_released_at: null, disputed_at: null },
    listing: { id: LISTING, event_name: "Fixture night" },
    buyer: null,
    seller: null,
    disputes: [],
    dispute_resolutions: [],
    payout_decisions: [],
    refund: { payment_status: "succeeded", refund_actions: [] },
    seller_funds_state: "awaiting_confirmation",
    cases: [],
    actions: [],
    evidence: {},
    bank_payout: { tracked: false, note: null },
  };
}

async function render(livemode: unknown) {
  mocks.callOps.mockImplementation(async (fn: string) => {
    if (fn === "order_detail") return { ok: true, data: orderDetail(livemode) };
    if (fn === "order_timeline") return { ok: true, data: { events: [] } };
    if (fn === "settings") return { ok: true, data: [] };
    if (fn === "list_actions") return { ok: true, data: { items: [], next_cursor: null, count_hint: 0 } };
    return { ok: false, kind: "error", message: `unexpected ${fn}` };
  });
  mocks.requireOperator.mockResolvedValue({ id: "f0000000-0000-4000-8000-0000000000a1", role: "platform_admin" });
  const el = await OrderPage({ params: Promise.resolve({ paymentId: PAY }) });
  return renderToStaticMarkup(el);
}

const text = (html: string) => html.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/\s+/g, " ").trim();
/** The Payment panel: from its title to the next panel's title. */
const paymentPanel = (html: string) => {
  const start = html.indexOf(">Payment</");
  const end = html.indexOf(">Transfer</", start);
  expect(start, "Payment panel not found").toBeGreaterThan(-1);
  return html.slice(start, end);
};
/** The visible text of the "Stripe mode" row's value, or null when there is no such row. */
const stripeModeRow = (html: string) => {
  const m = paymentPanel(html).match(/<dt[^>]*>Stripe mode<\/dt><dd[^>]*>([\s\S]*?)<\/dd>/);
  return m ? text(m[1]) : null;
};
/** The header's existing test-mode badge (kept; it shows only for a literal false). */
const TEST_BADGE = /data-status="test"><span[^>]*>[^<]*<\/span>Stripe test mode<\/span>/;

beforeEach(() => {
  mocks.callOps.mockReset();
  mocks.requireOperator.mockReset();
});

describe("order page — Payment panel shows a Stripe mode row", () => {
  it("true → Live, and no unclassified note", async () => {
    const html = await render(true);
    expect(stripeModeRow(html)).toBe("• Live");
    expect(text(paymentPanel(html))).not.toContain("manual refund must stop");
    expect(html).not.toMatch(TEST_BADGE);
  });

  it("false → Test, and the header's test-mode badge is kept", async () => {
    const html = await render(false);
    expect(stripeModeRow(html)).toBe("– Test");
    expect(text(paymentPanel(html))).not.toContain("manual refund must stop");
    expect(html).toMatch(TEST_BADGE);
  });

  it("null → Unclassified, with the note in the Payment panel", async () => {
    const html = await render(null);
    expect(stripeModeRow(html)).toBe("! Unclassified");
    const panel = text(paymentPanel(html));
    expect(panel).toContain("fail closed");
    expect(panel).toContain("a manual refund must stop here and go to the owner");
    expect(html).not.toMatch(TEST_BADGE);
  });

  it("field missing from the payload → Unclassified (not provided by the server), never a recorded null", async () => {
    const html = await render(MISSING);
    expect(stripeModeRow(html)).toBe("! Unclassified not provided by the server");
    const panel = text(paymentPanel(html));
    expect(panel).toContain("a manual refund must stop here and go to the owner");
    expect(panel).not.toContain("fail closed");
  });

  it("a string 'true' is not Live on the page either", async () => {
    const html = await render("true");
    expect(stripeModeRow(html)).toBe("! Unclassified unrecognised value");
  });
});
