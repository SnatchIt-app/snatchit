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
    // The refund form is unaffected by a release on the transfer.
    expect(actionTypes(html)).toContain("refund_execute");
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
    expect(actionTypes(html)).toContain("payout_release");
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
    expect(html).toContain("Couldn&#x27;t check for an earlier request");
    expect(actionTypes(html)).toContain("payout_release");
  });
});
