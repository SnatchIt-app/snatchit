import { createElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * V-1 item 2 — trend comparison and status breakdowns from REAL reads only.
 *
 * Money: the period-over-previous-period comparison that ops.money_overview
 * already provides (v2 reads the current and the previous window) rendered
 * with the sign, both periods labelled, and "n/a" when either window could
 * not be read. Orders and Cases: a count per status over the rows the page's
 * own list read returned — never a new metric, never a total the server did
 * not state. The pages render for real with the data layer mocked.
 */
const mocks = vi.hoisted(() => ({ readPeriod: vi.fn(), readSeries: vi.fn(), callOps: vi.fn(), requireOperator: vi.fn() }));

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
vi.mock("@/lib/analytics", () => ({ readPeriod: mocks.readPeriod, readSeries: mocks.readSeries }));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import { compareWindows, figuresFrom } from "@/lib/analytics-core";
import { breakdown, NOT_STATED } from "@/lib/breakdown";
import { PeriodComparison } from "@/components/analytics/PeriodComparison";
import { StatusBreakdown } from "@/components/ui/StatusBreakdown";
import { MoneyKpis } from "@/components/analytics/sections";
import { toMoneyOverview } from "@/lib/types";
import OrdersPage from "@/app/(console)/orders/page";
import CasesPage from "@/app/(console)/cases/page";

const h = (el: ReactElement) => renderToStaticMarkup(el);

// ---------------------------------------------------------------------------
// Pure: comparison and breakdown
// ---------------------------------------------------------------------------

describe("compareWindows — the sign is always stated; a missing window is n/a, never zero", () => {
  it("up, down, flat", () => {
    expect(compareWindows(150, 100)).toEqual({ kind: "ok", current: 150, previous: 100, change: 50, sign: "+", pct: 50 });
    expect(compareWindows(50, 100)).toEqual({ kind: "ok", current: 50, previous: 100, change: -50, sign: "−", pct: -50 });
    expect(compareWindows(100, 100)).toEqual({ kind: "ok", current: 100, previous: 100, change: 0, sign: "±", pct: 0 });
    expect(compareWindows(0, 0)).toEqual({ kind: "ok", current: 0, previous: 0, change: 0, sign: "±", pct: 0 });
  });
  it("a zero previous period has no percentage (none in previous period), not infinity", () => {
    expect(compareWindows(5, 0)).toEqual({ kind: "ok", current: 5, previous: 0, change: 5, sign: "+", pct: null });
  });
  it("either window unknown → n/a naming the missing side", () => {
    expect(compareWindows(null, 100)).toEqual({ kind: "na", missing: "current" });
    expect(compareWindows(100, null)).toEqual({ kind: "na", missing: "previous" });
    expect(compareWindows(null, null)).toEqual({ kind: "na", missing: "current" });
  });
  it("percentages are whole numbers of the previous value's magnitude", () => {
    expect(compareWindows(1, 3)).toMatchObject({ kind: "ok", pct: -67 });
    expect(compareWindows(-50, -100)).toMatchObject({ change: 50, sign: "+", pct: 50 });
  });
});

describe("breakdown — counts per status over the rows given, nothing hidden", () => {
  const rows = [{ s: "a" }, { s: "b" }, { s: "a" }, { s: null }, { s: "c" }, { s: "" }, { s: "b" }];
  it("counts, shares of the row total, most common first, ties in first-seen order, 'not stated' last", () => {
    const b = breakdown(rows, (r) => ({ key: r.s, label: r.s ? r.s.toUpperCase() : undefined }));
    expect(b.total).toBe(7);
    expect(b.items.map((i) => [i.key, i.label, i.count])).toEqual([
      ["a", "A", 2],
      ["b", "B", 2],
      ["c", "C", 1],
      ["", NOT_STATED, 2],
    ]);
    expect(b.items.map((i) => i.share)).toEqual([2 / 7, 2 / 7, 1 / 7, 2 / 7]);
    expect(b.items.reduce((n, i) => n + i.count, 0)).toBe(7);
  });
  it("empty input is an empty breakdown with total 0", () => {
    expect(breakdown([], () => ({ key: "x" }))).toEqual({ total: 0, items: [] });
  });
  it("the label defaults to the key", () => {
    expect(breakdown([{ s: "open" }], (r) => ({ key: r.s })).items[0].label).toBe("open");
  });
});

// ---------------------------------------------------------------------------
// Rendered: comparison table and breakdown bars
// ---------------------------------------------------------------------------

type Metric = { value_cents: number | null; count: number | null; basis: string; upper_bound_cents?: number | null; certainty?: string };
const metric = (value_cents: number | null, count: number | null, basis = "paid_at"): Metric => ({ value_cents, count, basis });
const figures = (metrics: Record<string, Metric>) => figuresFrom(toMoneyOverview({ from: "a", to: "b", computed_at: "2026-10-22T10:54:59Z", metrics })!);
const CUR = {
  gross_captured_volume: metric(132000, 11),
  platform_fees_gross: metric(18640, 10),
  refunded_volume: { value_cents: null, count: 1, upper_bound_cents: 4400, certainty: "uncertain", basis: "refunded_at" },
  seller_funds_released: metric(22500, 1, "payout_released_at"),
  seller_funds_pending: metric(26280, 4, "now()"),
  bank_payouts: { value_cents: null, count: null, basis: "not_tracked" },
};
const PREV = { ...CUR, gross_captured_volume: metric(82000, 7), platform_fees_gross: metric(18640, 9), refunded_volume: { ...CUR.refunded_volume, count: 2 }, seller_funds_released: metric(0, 0, "payout_released_at") };

describe("PeriodComparison — both periods labelled, every change signed, n/a when a window is missing", () => {
  const labels = { currentLabel: "Sep 23 – Oct 22, 2026", previousLabel: "Aug 24 – Sep 22, 2026" };
  it("rows for the four period measures with current, previous and the signed change", () => {
    const html = h(createElement(PeriodComparison, { ...labels, current: figures(CUR), previous: figures(PREV) }));
    expect(html).toContain("Sep 23 – Oct 22, 2026");
    expect(html).toContain("Aug 24 – Sep 22, 2026");
    expect(html).toContain("<caption");
    expect(html).toMatch(/<th[^>]*>Sep 23 – Oct 22, 2026 \(current\)<\/th>/);
    expect(html).toMatch(/<th[^>]*>Aug 24 – Sep 22, 2026 \(previous\)<\/th>/);
    // captured: +$500.00 (+61%)
    expect(html).toContain("+$500.00 (+61%)");
    // fees: ±$0.00 (no change)
    expect(html).toContain("±$0.00 (no change)");
    // refunds: a count, −1 (−50%)
    expect(html).toContain("−1 (−50%)");
    // released: 22500 cents vs 0 → none in previous period, no percentage
    expect(html).toContain("+$225.00 (none in previous period)");
    expect(html).not.toContain("Infinity");
    expect(html).not.toContain("NaN");
    // the point-in-time and not-tracked measures are not compared
    expect(html).not.toContain("pending");
    expect(html).not.toContain("Bank payouts");
  });
  it("previous window could not be read → n/a on every row, the current figures still shown", () => {
    const html = h(createElement(PeriodComparison, { ...labels, current: figures(CUR), previous: null }));
    expect(html.match(/n\/a — previous period couldn&#x27;t be read/g)?.length).toBe(4);
    expect(html).toContain("$1,320.00");
    expect(html).not.toContain("%");
  });
  it("a measure the server did not return in one window → n/a for that row only", () => {
    const html = h(createElement(PeriodComparison, { ...labels, current: figures({ ...CUR, gross_captured_volume: undefined as unknown as Metric }), previous: figures(PREV) }));
    expect(html.match(/n\/a — not returned by the server/g)?.length).toBe(1);
    expect(html).toContain("±$0.00 (no change)");
  });
  it("the bars compare the same measure across the two periods (never two measures on one axis) and are decorative", () => {
    const html = h(createElement(PeriodComparison, { ...labels, current: figures(CUR), previous: figures(PREV) }));
    const bars = [...html.matchAll(/<div[^>]*data-compare-bars=""[^>]*aria-hidden="true"/g)];
    expect(bars.length).toBe(4);
    // captured: current 132000 is the max → 100%; previous 82000 → 62%
    expect(html).toContain("width:100%");
    expect(html).toContain("width:62%");
  });
});

describe("StatusBreakdown — a labelled stacked bar plus a legend with counts and shares; empty says so", () => {
  const items = breakdown([{ s: "open" }, { s: "open" }, { s: "waiting" }, { s: null }], (r) => ({ key: r.s, label: r.s === "open" ? "Open" : r.s === "waiting" ? "Waiting" : undefined }));
  it("renders the scope, every bucket with its count and percentage, and bar segments whose widths are the shares", () => {
    const html = h(createElement(StatusBreakdown, { title: "Status", noun: "cases", scope: "on this page", ...items }));
    expect(html).toContain("Status");
    expect(html).toContain("4 cases on this page");
    expect(html).toContain("Open");
    expect(html).toContain("Waiting");
    expect(html).toContain(NOT_STATED);
    expect(html).toMatch(/Open[\s\S]*?2[\s\S]*?\(50%\)/);
    expect(html).toMatch(/Waiting[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html).toMatch(/<div[^>]*data-breakdown-bar=""[^>]*aria-hidden="true"/);
    expect(html.match(/width:50%/g)?.length).toBe(1);
    expect(html.match(/width:25%/g)?.length).toBe(2);
    // the list is the accessible form: one item per bucket
    expect(html.match(/<li/g)?.length).toBe(3);
  });
  it("no rows → an explicit empty state, no bar", () => {
    const html = h(createElement(StatusBreakdown, { title: "Status", noun: "cases", scope: "on this page", total: 0, items: [] }));
    expect(html).toContain("No cases on this page.");
    expect(html).toContain('role="status"');
    expect(html).not.toContain("data-breakdown-bar");
  });
});

// ---------------------------------------------------------------------------
// Money page: the comparison is wired from the two windows v2 already reads
// ---------------------------------------------------------------------------

const period = (from: string, to: string, m: Record<string, Metric>) => {
  const o = toMoneyOverview({ from, to, computed_at: "2026-10-22T10:54:59Z", metrics: m })!;
  return { ok: true as const, overview: o, figures: figuresFrom(o) };
};
const FAIL = { ok: false as const, kind: "error" as const, message: "timeout", code: "57014" };

describe("MoneyKpis renders the period comparison from the current and previous windows", () => {
  beforeEach(() => mocks.readPeriod.mockReset());
  it("both windows read → the table with both labels and signed changes (Money page)", async () => {
    mocks.readPeriod.mockImplementation(async (f: string) => (f === "2026-09-23" ? period("2026-09-23", "2026-10-21", CUR) : period("2026-08-25", "2026-09-22", PREV)));
    const html = h(await MoneyKpis({ from: "2026-09-23", to: "2026-10-21" }));
    expect(html).toContain("Sep 23 – Oct 21, 2026 (current)");
    expect(html).toContain("Aug 25 – Sep 22, 2026 (previous)");
    expect(html).toContain("+$500.00 (+61%)");
  });
  it("previous window failed → n/a, and the current tiles are unaffected", async () => {
    mocks.readPeriod.mockImplementation(async (f: string) => (f === "2026-09-23" ? period("2026-09-23", "2026-10-21", CUR) : FAIL));
    const html = h(await MoneyKpis({ from: "2026-09-23", to: "2026-10-21" }));
    expect(html.match(/n\/a — previous period couldn&#x27;t be read/g)?.length).toBe(4);
    expect(html).toContain("$1,320");
    expect(html).toContain("Previous period unavailable");
  });
  it("compact (Today) keeps the tiles and the labelled 'compared with' line without the table", async () => {
    mocks.readPeriod.mockImplementation(async (f: string) => (f === "2026-09-23" ? period("2026-09-23", "2026-10-21", CUR) : period("2026-08-25", "2026-09-22", PREV)));
    const html = h(await MoneyKpis({ from: "2026-09-23", to: "2026-10-21", compact: true }));
    expect(html).not.toContain("<table");
    expect(html).toContain("Compared with Aug 25 – Sep 22 (UTC)");
  });
});

// ---------------------------------------------------------------------------
// Orders and Cases pages: breakdowns over the rows the list read returned
// ---------------------------------------------------------------------------

type Row = Record<string, unknown>;
const ME = "aaaaaaaa-0000-4000-8000-000000000001";
const order = (i: number, over: Row): Row => ({
  payment_id: `9a900000-0000-4000-8000-0000000000${String(i).padStart(2, "0")}`,
  created_at: "2026-10-01T12:00:00Z",
  payment_status: "succeeded",
  amount: 4000,
  total: 4400,
  event_name: `Event ${i}`,
  transfer_id: `7a000000-0000-4000-8000-0000000000${String(i).padStart(2, "0")}`,
  transfer_status: "pending",
  buyer_confirmed_at: null,
  seller_funds_state: "awaiting_delivery",
  open_cases: 0,
  ...over,
});
const ORDERS: Row[] = [
  order(1, {}),
  order(2, { payment_status: "refunded", transfer_status: "buyer_confirmed", buyer_confirmed_at: null, seller_funds_state: "refunded" }),
  order(3, { transfer_status: "buyer_confirmed", buyer_confirmed_at: "2026-10-02T12:00:00Z", seller_funds_state: "release_scheduled" }),
  order(4, { transfer_id: null, transfer_status: null, seller_funds_state: null }),
];

async function ordersPage(main: unknown, sp: Record<string, string> = {}) {
  mocks.callOps.mockImplementation(async (fn: string, args: Record<string, unknown> = {}) => {
    if (fn === "list_orders") return args.p_limit === 100 ? { ok: true, data: { items: [], next_cursor: null, count_hint: 7 } } : main;
    return { ok: false, kind: "error", message: `unexpected ${fn}` };
  });
  mocks.requireOperator.mockResolvedValue({ id: ME, role: "platform_admin", email: null, aal: "aal2", whoami: { role: "platform_admin" } });
  return h(await OrdersPage({ searchParams: Promise.resolve(sp) }));
}

describe("Orders — a status breakdown of the rows on this page, in the reviewed vocabulary, beside the server-side filters", () => {
  beforeEach(() => {
    mocks.callOps.mockReset();
    mocks.requireOperator.mockReset();
  });
  it("three breakdowns (payment, ticket transfer, seller funds) counted from the page's rows and scoped to them", async () => {
    const html = await ordersPage({ ok: true, data: { items: ORDERS, next_cursor: null, count_hint: 4 } });
    expect(html.match(/4 orders on this page/g)?.length).toBe(3);
    expect(html).toMatch(/Captured[\s\S]*?3[\s\S]*?\(75%\)/);
    expect(html).toMatch(/Refund recorded[\s\S]*?1[\s\S]*?\(25%\)/);
    // the transfer breakdown is row-aware: a buyer_confirmed status with no confirmation record is NOT a buyer confirmation
    expect(html).toMatch(/Confirmed status, no confirmation record[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html).toMatch(/Buyer confirmed<[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html).toContain("No transfer");
    // seller funds in the reviewed labels; a null state is "Not stated", never dropped
    expect(html).toContain("Awaiting seller delivery");
    expect(html).toContain("Refunded to buyer");
    expect(html).toContain(NOT_STATED);
    // the server-side filter chips and the saved views are still there, and the rows are all rendered
    expect(html).toContain("filter-chip");
    expect(html.match(/9a900000-0000-4000-8000-00000000000[1-4]/g)?.length).toBeGreaterThanOrEqual(4);
    expect(html.match(/stat-num/g)?.length).toBe(4);
  });
  it("no rows → no breakdown, the existing empty copy; a failed read → no breakdown, the alert", async () => {
    const empty = await ordersPage({ ok: true, data: { items: [], next_cursor: null, count_hint: 0 } });
    expect(empty).not.toContain("data-breakdown");
    expect(empty).toContain("No orders yet.");
    const failed = await ordersPage({ ok: false, kind: "error", message: "boom" });
    expect(failed).not.toContain("data-breakdown");
    expect(failed).toContain("Orders couldn&#x27;t be loaded.");
  });
});

const kase = (i: number, over: Row): Row => ({
  id: `11111111-2222-4333-8444-5555555555${String(i).padStart(2, "0")}`,
  title: `Case ${i}`,
  case_type: "transfer_overdue",
  status: "open",
  priority: "p2",
  detected_at: "2026-10-01T12:00:00Z",
  version: 1,
  ...over,
});
const CASES: Row[] = [kase(1, {}), kase(2, { status: "in_progress", priority: "p1" }), kase(3, { status: "waiting" }), kase(4, { status: null, priority: null })];

async function casesPage(main: unknown, sp: Record<string, string> = {}) {
  mocks.callOps.mockImplementation(async (fn: string, args: Record<string, unknown> = {}) => {
    if (fn === "list_cases") return args.p_limit === 1 ? { ok: true, data: { items: [], next_cursor: null, count_hint: 9 } } : main;
    return { ok: false, kind: "error", message: `unexpected ${fn}` };
  });
  mocks.requireOperator.mockResolvedValue({ id: ME, role: "platform_admin", email: null, aal: "aal2", whoami: { role: "platform_admin", email_masked: "f***@example.test" } });
  return h(await CasesPage({ searchParams: Promise.resolve(sp) }));
}

describe("Cases — status and priority breakdowns of the rows on this page", () => {
  beforeEach(() => {
    mocks.callOps.mockReset();
    mocks.requireOperator.mockReset();
  });
  it("two breakdowns counted from the queue's rows, scoped to the page, next to the chips", async () => {
    const html = await casesPage({ ok: true, data: { items: CASES, next_cursor: null, count_hint: 4 } });
    expect(html.match(/4 cases on this page/g)?.length).toBe(2);
    expect(html).toMatch(/Open[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html).toMatch(/In progress[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html).toMatch(/Waiting[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html).toMatch(/P2[\s\S]*?2[\s\S]*?\(50%\)/);
    expect(html).toMatch(/P1[\s\S]*?1[\s\S]*?\(25%\)/);
    expect(html.match(new RegExp(NOT_STATED, "g"))?.length).toBe(2);
    expect(html).toContain("filter-chip");
    expect(html.match(/data-case-link=/g)?.length).toBe(4);
  });
  it("no rows → no breakdown and the existing empty copy", async () => {
    const html = await casesPage({ ok: true, data: { items: [], next_cursor: null, count_hint: 0 } });
    expect(html).not.toContain("data-breakdown");
    expect(html).toContain("No cases.");
  });
});
