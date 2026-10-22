import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * F1 (AV2-04, agreed with A) — the order page's "Already requested" guard.
 *
 * ops.order_detail caps `actions` at the newest 50 across the payment, the
 * transfer and the listing (116:584-592). An old unsettled payout_release can
 * fall out of that window, and the page then re-offers "Request release" with
 * a fresh idempotency key. The guard therefore also reads ops.list_actions,
 * filtered to this one subject and the unsettled states, and fails closed when
 * that read fails. These render the real page with the data layer mocked.
 */
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

const PAY = "9a900000-0000-4000-8000-0000000000f1";
const TR = "7a000000-0000-4000-8000-0000000000f1";
const LISTING = "1a000000-0000-4000-8000-0000000000f1";
const OLD_RELEASE = "aaaaaaaa-0000-4000-8000-0000000000f1";
const OLD_REFUND = "bbbbbbbb-0000-4000-8000-0000000000f1";
const UNSETTLED = ["requested", "awaiting_approval", "processing", "succeeded_at_provider", "unknown"];

type Row = Record<string, unknown>;
type Ops = { ok: true; data: unknown } | { ok: false; kind: string; message?: string };

/** 50 newer, settled actions on the listing — enough to push anything older out of order_detail's window. */
const newerSettled: Row[] = Array.from({ length: 50 }, (_, i) => ({
  id: `cccccccc-0000-4000-8000-${String(i).padStart(12, "0")}`,
  action_type: "listing_relist",
  subject_kind: "listing",
  subject_id: LISTING,
  state: "succeeded",
  requested_at: `2026-10-20T10:${String(i).padStart(2, "0")}:00Z`,
  created_at: `2026-10-20T10:${String(i).padStart(2, "0")}:00Z`,
}));

const oldRelease: Row = {
  id: OLD_RELEASE,
  action_type: "payout_release",
  subject_kind: "transfer",
  subject_id: TR,
  state: "awaiting_approval",
  requested_at: "2026-09-01T09:00:00Z",
  created_at: "2026-09-01T09:00:00Z",
};
const oldRefund: Row = { ...oldRelease, id: OLD_REFUND, action_type: "refund_execute", subject_kind: "payment", subject_id: PAY, state: "unknown" };

function orderDetail(over: { actions?: Row[]; refundActions?: Row[] } = {}) {
  return {
    payment: { id: PAY, status: "succeeded", total: 9900, amount: 9000, buyer_fee: 900, seller_fee: 450, listing_id: LISTING },
    transfer: { id: TR, payment_id: PAY, status: "seller_sent", payout_review_status: "manual_review", payout_released_at: null, disputed_at: null },
    listing: { id: LISTING, event_name: "Fixture night" },
    buyer: null,
    seller: null,
    disputes: [],
    dispute_resolutions: [],
    payout_decisions: [],
    refund: { payment_status: "succeeded", refund_actions: over.refundActions ?? [] },
    seller_funds_state: "held_platform",
    cases: [],
    actions: over.actions ?? newerSettled,
    evidence: {},
    bank_payout: { tracked: false, note: null },
  };
}

const page = (items: Row[]): Ops => ({ ok: true, data: { items, next_cursor: null, count_hint: items.length } });

async function render({
  detail = orderDetail(),
  release = page([]),
  refund = page([]),
}: { detail?: ReturnType<typeof orderDetail>; release?: Ops; refund?: Ops } = {}) {
  mocks.callOps.mockImplementation(async (fn: string, args: Record<string, unknown> = {}) => {
    if (fn === "order_detail") return { ok: true, data: detail };
    if (fn === "order_timeline") return { ok: true, data: { events: [] } };
    if (fn === "settings") return { ok: true, data: [{ key: "refund_execute_enabled", value: true }] };
    if (fn === "list_actions") {
      const type = ((args.p_filters as Row | undefined)?.action_type as string[] | undefined)?.[0];
      if (type === "payout_release") return release;
      if (type === "refund_execute") return refund;
    }
    return { ok: false, kind: "error", message: `unexpected ${fn}` };
  });
  mocks.requireOperator.mockResolvedValue({ id: "f0000000-0000-4000-8000-0000000000a1", role: "platform_admin" });
  const el = await OrderPage({ params: Promise.resolve({ paymentId: PAY }) });
  return renderToStaticMarkup(el);
}

const forms = (html: string) => html.split("<form").slice(1).map((f) => f.slice(0, f.indexOf("</form>")));
const actionTypes = (html: string) => forms(html).map((f) => f.match(/name="action_type" value="([^"]*)"/)?.[1]);
const listCalls = () => mocks.callOps.mock.calls.filter(([fn]) => fn === "list_actions");
/** The money forms only (the page always offers "Open a case" too). */
const moneyForms = (html: string) => actionTypes(html).filter((t) => t === "payout_release" || t === "refund_execute");
/** The markup of one Panel, found by its title. */
const panel = (html: string, title: string) => html.split("<section").find((s) => s.includes(`<h2 class="title-section">${title}</h2>`)) ?? "";
const RELEASE_PANEL = "Release held payout";
const REFUND_PANEL = "Execute refund";
const UNVERIFIED = "Couldn&#x27;t check for an earlier request";

beforeEach(() => {
  mocks.callOps.mockReset();
  mocks.requireOperator.mockReset();
});

describe("F1 — payout_release guard does not depend on order_detail's 50-row window", () => {
  it("positive control: nothing unsettled anywhere → both request forms are offered", async () => {
    const html = await render();
    expect(actionTypes(html)).toEqual(expect.arrayContaining(["payout_release", "refund_execute"]));
    expect(html).not.toContain("Already requested");
  });

  it("an old unsettled release outside the capped list but returned by list_actions → guard shown, no release form", async () => {
    const html = await render({ release: page([oldRelease]) });
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(html).toContain("Already requested — Awaiting approval");
    expect(html).toContain(`href="/actions/${OLD_RELEASE}"`);
    // P3: money on an order is one subject — the pending release hides the refund form too, naming the release.
    expect(actionTypes(html)).not.toContain("refund_execute");
    expect(panel(html, REFUND_PANEL)).toContain("Release held payout");
    expect(panel(html, REFUND_PANEL)).toContain(`href="/actions/${OLD_RELEASE}"`);
  });

  it("asks list_actions for exactly this transfer, payout_release only, in every unsettled state", async () => {
    await render();
    const call = listCalls().find(([, a]) => (a as Row).p_filters && ((a as Row).p_filters as Row).subject_kind === "transfer");
    expect(call, "list_actions was not asked about the transfer").toBeDefined();
    expect((call![1] as Row).p_filters).toEqual({ action_type: ["payout_release"], subject_kind: "transfer", subject_id: TR, state: UNSETTLED });
  });

  it("list_actions fails → the release form is hidden and an error says why (fail closed)", async () => {
    const html = await render({ release: { ok: false, kind: "error", message: "upstream timeout" } });
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(html).toContain("Couldn&#x27;t check for an earlier request");
    expect(html).not.toContain("Already requested");
  });

  it("list_actions denied or an unrecognised payload → still hidden, never re-armed", async () => {
    for (const release of [{ ok: false, kind: "denied" } as Ops, { ok: true, data: null } as Ops, { ok: true, data: { rows: "nope" } } as Ops]) {
      const html = await render({ release });
      expect(actionTypes(html), JSON.stringify(release)).not.toContain("payout_release");
      expect(html).toContain("Couldn&#x27;t check for an earlier request");
    }
  });

  it("list_actions returns a row the client cannot match (subject_id case, reshaped row) → still blocked, never re-armed", async () => {
    const upper = { ...oldRelease, subject_id: TR.toUpperCase() };
    const reshaped = { id: OLD_RELEASE, action_type: "payout_release", subject: { kind: "transfer", id: TR }, state: "requested" };
    for (const row of [upper, reshaped]) {
      const html = await render({ release: page([row]) });
      expect(actionTypes(html), JSON.stringify(row)).not.toContain("payout_release");
      expect(html).toContain("Already requested");
      expect(html).toContain(`href="/actions/${OLD_RELEASE}"`);
      // P3: a row the server returned for the transfer blocks the refund form as well.
      expect(actionTypes(html)).not.toContain("refund_execute");
    }
  });

  it("a returned row with no state reads 'Already requested', never 'undefined'", async () => {
    const html = await render({ release: page([{ id: OLD_RELEASE }]) });
    expect(actionTypes(html)).not.toContain("payout_release");
    // The Alert title ends the <p>: no " — undefined" / " — null" suffix.
    expect(html).toContain("Already requested</p>");
    expect(html).not.toContain("undefined");
  });

  it("count_hint > 0 with no usable row → hidden as unverified, not offered", async () => {
    const html = await render({ release: { ok: true, data: { items: [], next_cursor: null, count_hint: 1 } } });
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(html).toContain("Couldn&#x27;t check for an earlier request");
  });

  it("the capped list still counts: an unsettled release there blocks even when list_actions fails", async () => {
    const html = await render({ detail: orderDetail({ actions: [oldRelease] }), release: { ok: false, kind: "error", message: "x" } });
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(html).toContain("Already requested — Awaiting approval");
  });
});

describe("F1 — refund_execute guard reads list_actions too, refund_actions stays a source", () => {
  it("an unsettled refund returned only by list_actions → refund form hidden", async () => {
    const html = await render({ refund: page([oldRefund]) });
    expect(actionTypes(html)).not.toContain("refund_execute");
    expect(html).toContain("Already requested — Outcome unknown — needs reconciliation");
    expect(html).toContain(`href="/actions/${OLD_REFUND}"`);
    // P3: the unsettled refund hides the release form too, naming the refund.
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(panel(html, RELEASE_PANEL)).toContain("Execute refund");
    expect(panel(html, RELEASE_PANEL)).toContain(`href="/actions/${OLD_REFUND}"`);
  });

  it("asks list_actions for exactly this payment, refund_execute only, in every unsettled state", async () => {
    await render();
    const call = listCalls().find(([, a]) => ((a as Row).p_filters as Row | undefined)?.subject_kind === "payment");
    expect(call, "list_actions was not asked about the payment").toBeDefined();
    expect((call![1] as Row).p_filters).toEqual({ action_type: ["refund_execute"], subject_kind: "payment", subject_id: PAY, state: UNSETTLED });
  });

  it("refund_actions alone still blocks (list_actions empty)", async () => {
    const html = await render({ detail: orderDetail({ refundActions: [oldRefund] }) });
    expect(actionTypes(html)).not.toContain("refund_execute");
  });

  it("list_actions fails for the payment → the refund form is hidden (fail closed)", async () => {
    const html = await render({ refund: { ok: false, kind: "error", message: "boom" } });
    expect(actionTypes(html)).not.toContain("refund_execute");
    expect(html).toContain(UNVERIFIED);
    // P3: an unverified refund read hides the release form as well (fail closed on either read).
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(panel(html, RELEASE_PANEL)).toContain(UNVERIFIED);
  });
});

/**
 * P3 (reviewer E, pre-deploy) — one money action at a time per order.
 *
 * list_actions is filtered by one action_type, so before this a pending
 * refund_execute on the payment left the payout_release form offered and a
 * pending payout_release on the transfer left the refund form offered: two
 * founders in two tabs could park both. The page now reads BOTH money types
 * for the same order whenever either form is offered and hides BOTH forms when
 * EITHER is unsettled or unverified. The pending notice names the action that
 * blocks and links it.
 */
describe("P3 — a pending money action of either type hides both money forms", () => {
  it("control: both reads answer an empty page → both forms, two list_actions reads (one per type)", async () => {
    const html = await render();
    expect(actionTypes(html)).toEqual(expect.arrayContaining(["payout_release", "refund_execute"]));
    const types = listCalls().map(([, a]) => ((a as Row).p_filters as Row).action_type);
    expect(types).toEqual(expect.arrayContaining([["payout_release"], ["refund_execute"]]));
    expect(listCalls()).toHaveLength(2);
    expect(html).not.toContain("Already requested");
    expect(html).not.toContain(UNVERIFIED);
  });

  it("a pending refund (list_actions, payment subject) hides the release form; the release panel names the refund and links it", async () => {
    const html = await render({ refund: page([oldRefund]) });
    expect(moneyForms(html)).toEqual([]);
    const release = panel(html, RELEASE_PANEL);
    expect(release).toContain("Already requested — Outcome unknown — needs reconciliation");
    expect(release).toContain("Execute refund");
    expect(release).toContain(`href="/actions/${OLD_REFUND}"`);
    expect(panel(html, REFUND_PANEL)).toContain(`href="/actions/${OLD_REFUND}"`);
  });

  it("a pending release (list_actions, transfer subject) hides the refund form; the refund panel names the release and links it", async () => {
    const html = await render({ release: page([oldRelease]) });
    expect(moneyForms(html)).toEqual([]);
    const refund = panel(html, REFUND_PANEL);
    expect(refund).toContain("Already requested — Awaiting approval");
    expect(refund).toContain("Release held payout");
    expect(refund).toContain(`href="/actions/${OLD_RELEASE}"`);
    expect(panel(html, RELEASE_PANEL)).toContain(`href="/actions/${OLD_RELEASE}"`);
  });

  it("a pending refund held only in refund_actions (list_actions empty) hides the release form too", async () => {
    const html = await render({ detail: orderDetail({ refundActions: [oldRefund] }) });
    expect(moneyForms(html)).toEqual([]);
    expect(panel(html, RELEASE_PANEL)).toContain(`href="/actions/${OLD_REFUND}"`);
  });

  it("the release read fails → both forms hidden as unverified", async () => {
    const html = await render({ release: { ok: false, kind: "error", message: "upstream timeout" } });
    expect(moneyForms(html)).toEqual([]);
    expect(panel(html, RELEASE_PANEL)).toContain(UNVERIFIED);
    expect(panel(html, REFUND_PANEL)).toContain(UNVERIFIED);
    expect(html).not.toContain("Already requested");
  });

  it("the refund read fails or answers an unrecognised page → both forms hidden as unverified", async () => {
    for (const refund of [{ ok: false, kind: "denied" } as Ops, { ok: true, data: null } as Ops, { ok: true, data: { items: [], count_hint: 1 } } as Ops]) {
      const html = await render({ refund });
      expect(moneyForms(html), JSON.stringify(refund)).toEqual([]);
      expect(panel(html, RELEASE_PANEL)).toContain(UNVERIFIED);
      expect(panel(html, REFUND_PANEL)).toContain(UNVERIFIED);
    }
  });

  it("one read fails and the other is pending → both hidden, the pending action named on both (nothing is re-armed)", async () => {
    const html = await render({ release: { ok: false, kind: "error", message: "x" }, refund: page([oldRefund]) });
    expect(moneyForms(html)).toEqual([]);
    expect(panel(html, RELEASE_PANEL)).toContain(`href="/actions/${OLD_REFUND}"`);
    expect(panel(html, REFUND_PANEL)).toContain(`href="/actions/${OLD_REFUND}"`);
  });

  it("the transfer is not yet releasable (no release form) → payout_release is still read, and a pending release hides the refund form", async () => {
    const detail = orderDetail();
    detail.transfer = { ...detail.transfer, status: "pending" };
    const html = await render({ detail, release: page([oldRelease]) });
    expect(panel(html, RELEASE_PANEL)).toBe("");
    const types = listCalls().map(([, a]) => ((a as Row).p_filters as Row).action_type);
    expect(types).toEqual(expect.arrayContaining([["payout_release"], ["refund_execute"]]));
    expect(moneyForms(html)).toEqual([]);
    expect(panel(html, REFUND_PANEL)).toContain("Release held payout");
    expect(panel(html, REFUND_PANEL)).toContain(`href="/actions/${OLD_RELEASE}"`);
  });

  it("the transfer is not yet releasable and its read fails → the refund form is hidden as unverified", async () => {
    const detail = orderDetail();
    detail.transfer = { ...detail.transfer, status: "pending" };
    const html = await render({ detail, release: { ok: false, kind: "error", message: "x" } });
    expect(moneyForms(html)).toEqual([]);
    expect(panel(html, REFUND_PANEL)).toContain(UNVERIFIED);
  });

  it("no transfer row → nothing to cross-check: the refund form stands on its own read (control)", async () => {
    const detail = orderDetail();
    (detail as { transfer: unknown }).transfer = null;
    const html = await render({ detail });
    expect(moneyForms(html)).toEqual(["refund_execute"]);
    expect(listCalls()).toHaveLength(1);
    expect(((listCalls()[0][1] as Row).p_filters as Row).subject_kind).toBe("payment");
  });
});
