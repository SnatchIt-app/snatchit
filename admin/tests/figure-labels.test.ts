import { createElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * V-1 item 1 — every figure surface states the date range it covers, the
 * currency, the timezone the dates are shown in and the freshness of this
 * read; the current UTC day is labelled partial; and the empty, unavailable
 * and error states of each KPI and chart are distinct and explicit (an error
 * is never a zero or an empty plot). Money KPIs and charts render the real
 * server components with the analytics read layer mocked.
 */
const mocks = vi.hoisted(() => ({ readPeriod: vi.fn(), readSeries: vi.fn() }));

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ usePathname: () => "/money", useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }), useParams: () => ({}) }));
vi.mock("@/lib/analytics", () => ({ readPeriod: mocks.readPeriod, readSeries: mocks.readSeries }));

import { asOfLabel, CURRENCY, isPartialPeriod, PARTIAL_LABEL, rangeLabel, readFailedLabel, tileState, TIMEZONE } from "@/lib/figure-meta";
import { formatMoney, formatUtc } from "@/lib/format";
import { FigureMeta } from "@/components/charts/FigureMeta";
import { HiddenTestRowsNotice } from "@/components/ui/HiddenTestRowsNotice";
import { KpiTile } from "@/components/charts/KpiTile";
import { ChartCard } from "@/components/charts/ChartCard";
import { AttentionSummary, MoneyCharts, MoneyKpis } from "@/components/analytics/sections";
import { buckets, figuresFrom, isoDay } from "@/lib/analytics-core";
import { toMoneyOverview } from "@/lib/types";

const h = (el: ReactElement) => renderToStaticMarkup(el);
const src = (rel: string) => readFileSync(resolve(__dirname, "../src", rel), "utf8");
const READ_AT = new Date("2026-10-22T10:55:01Z");
const COMPUTED = "2026-10-22T10:54:59Z";
const TODAY = isoDay(new Date());

// ---------------------------------------------------------------------------
// Pure labels
// ---------------------------------------------------------------------------

describe("figure-meta — the labels state what the formatters do", () => {
  it("currency and timezone are the ones the money and time formatters print", () => {
    expect(CURRENCY).toBe("USD");
    expect(formatMoney(100)).toMatch(new RegExp(`${CURRENCY}$`));
    expect(TIMEZONE).toBe("UTC");
    expect(formatUtc("2026-10-22T10:54:59Z")).toMatch(new RegExp(`${TIMEZONE}$`));
  });

  it("rangeLabel names both inclusive UTC calendar days, with the year once unless it changes", () => {
    expect(rangeLabel("2026-09-23", "2026-10-22")).toBe("Sep 23 – Oct 22, 2026");
    expect(rangeLabel("2025-12-30", "2026-01-02")).toBe("Dec 30, 2025 – Jan 2, 2026");
    expect(rangeLabel("2026-10-22", "2026-10-22")).toBe("Oct 22, 2026");
    // malformed input is shown raw, never guessed
    expect(rangeLabel("2026-13-01", "x")).toBe("2026-13-01 – x");
  });

  it("asOfLabel states the server's computed_at with seconds and the UTC basis; a missing one is 'not stated', never the read time dressed up as freshness", () => {
    expect(asOfLabel(COMPUTED, READ_AT)).toBe("as of 2026-10-22 10:54:59 UTC");
    for (const missing of [null, undefined, "", "not a date"]) {
      const text = asOfLabel(missing, READ_AT);
      expect(text, String(missing)).toBe("as of: not stated by the server (read 2026-10-22 10:55:01 UTC)");
      expect(text.startsWith("as of 2026")).toBe(false);
    }
    expect(readFailedLabel(READ_AT)).toBe("read at 2026-10-22 10:55:01 UTC failed — nothing is shown");
  });

  it("isPartialPeriod: a range ending today (UTC) or later is still accumulating; one ending yesterday is complete", () => {
    const now = new Date("2026-10-22T15:00:00Z");
    expect(isPartialPeriod("2026-10-22", now)).toBe(true);
    expect(isPartialPeriod("2026-10-23", now)).toBe(true);
    expect(isPartialPeriod("2026-10-21", now)).toBe(false);
    // just after midnight UTC the new day is the partial one
    expect(isPartialPeriod("2026-10-21", new Date("2026-10-22T00:00:01Z"))).toBe(false);
    expect(isPartialPeriod("nope", now)).toBe(false);
    expect(PARTIAL_LABEL).toBe("includes today so far (partial)");
  });

  it("tileState: null value → unavailable; zero rows → empty; a figure → ok; a zero sum with an unknown count stays ok (no claim about rows)", () => {
    expect(tileState(null, 3, "payments")).toEqual({ kind: "unavailable", message: "Not returned by the server for this period." });
    expect(tileState(null, null, "payments")).toEqual({ kind: "unavailable", message: "Not returned by the server for this period." });
    expect(tileState(0, 0, "payments")).toEqual({ kind: "empty", message: "No payments in this period." });
    expect(tileState(500, 2, "payments")).toEqual({ kind: "ok" });
    expect(tileState(0, null, "payments")).toEqual({ kind: "ok" });
  });
});

// ---------------------------------------------------------------------------
// The meta line and the DC-2 hook
// ---------------------------------------------------------------------------

describe("FigureMeta — one line with range, timezone, currency, freshness and the partial mark", () => {
  it("period surfaces: range · UTC calendar days · USD · as of …", () => {
    const html = h(createElement(FigureMeta, { range: { from: "2026-09-23", to: "2026-10-21" }, currency: "USD", computedAt: COMPUTED, readAt: READ_AT }));
    expect(html).toContain("Sep 23 – Oct 21, 2026");
    expect(html).toContain("UTC calendar days");
    expect(html).toContain("USD");
    expect(html).toContain("as of 2026-10-22 10:54:59 UTC");
    expect(html).not.toContain(PARTIAL_LABEL);
    expect(html).toContain('data-figure-meta=""');
  });

  it("a range that ends today is labelled partial; the mark is derived from the read time, not asserted by the caller", () => {
    const html = h(createElement(FigureMeta, { range: { from: "2026-09-23", to: TODAY }, currency: "USD", computedAt: COMPUTED, readAt: new Date() }));
    expect(html).toContain(PARTIAL_LABEL);
  });

  it("point-in-time surfaces say so instead of a range, and still carry the timezone and freshness", () => {
    const html = h(createElement(FigureMeta, { pointInTime: true, computedAt: null, readAt: READ_AT }));
    expect(html).toContain("Point in time (now), not a period");
    expect(html).toContain("UTC");
    expect(html).toContain("as of: not stated by the server (read 2026-10-22 10:55:01 UTC)");
    expect(html).not.toContain("USD");
    expect(html).not.toContain(PARTIAL_LABEL);
  });

  it("a failed read says so and claims no freshness and no partial mark", () => {
    const html = h(createElement(FigureMeta, { range: { from: "2026-09-23", to: TODAY }, currency: "USD", readAt: READ_AT, failed: true }));
    expect(html).toContain("read at 2026-10-22 10:55:01 UTC failed — nothing is shown");
    expect(html).not.toContain("as of ");
    expect(html).not.toContain(PARTIAL_LABEL);
  });

  it("carries the DC-2 notice slot verbatim", () => {
    const html = h(createElement(FigureMeta, { pointInTime: true, computedAt: COMPUTED, readAt: READ_AT, notice: createElement("em", null, "slot-marker") }));
    expect(html).toContain("<em>slot-marker</em>");
  });
});

describe("HiddenTestRowsNotice — the single hook for DC-2; renders nothing until the server reports a count", () => {
  it("null / undefined → nothing", () => {
    expect(h(createElement(HiddenTestRowsNotice, { count: null }))).toBe("");
    expect(h(createElement(HiddenTestRowsNotice, { count: undefined }))).toBe("");
  });
  it("a server-reported integer → the notice, singular and plural", () => {
    expect(h(createElement(HiddenTestRowsNotice, { count: 3 }))).toContain("3 test records hidden by the server");
    expect(h(createElement(HiddenTestRowsNotice, { count: 1 }))).toContain("1 test record hidden by the server");
    expect(h(createElement(HiddenTestRowsNotice, { count: 0 }))).toContain("0 test records hidden by the server");
  });
  it("a non-integer is not a count and renders nothing", () => {
    for (const v of [1.5, -1, NaN, Infinity]) expect(h(createElement(HiddenTestRowsNotice, { count: v })), String(v)).toBe("");
  });
  it("no page or component invents a count: the notice is rendered only from server-sent values (DC-2 wired to A's 180)", () => {
    // DC-2 wired it: the hook itself, Today (ops.today.test_excluded) and the money KPIs (money_overview.test_excluded) render it,
    // each from a server-sent value; nothing else does, and no caller passes a literal count.
    const root = resolve(__dirname, "../src");
    const files: string[] = [];
    const visit = (dir: string) => {
      for (const name of readdirSync(dir)) {
        const full = resolve(dir, name);
        if (statSync(full).isDirectory()) visit(full);
        else if (/\.(ts|tsx)$/.test(name)) files.push(full);
      }
    };
    visit(root);
    const renderers = files.filter((f) => /<HiddenTestRowsNotice\b|function HiddenTestRowsNotice/.test(readFileSync(f, "utf8"))).map((f) => f.slice(root.length + 1)).sort();
    expect(renderers).toEqual(["app/(console)/page.tsx", "components/analytics/sections.tsx", "components/ui/HiddenTestRowsNotice.tsx"]);
    for (const f of renderers) expect(readFileSync(resolve(root, f), "utf8")).not.toMatch(/HiddenTestRowsNotice count=\{\d/);
   });
});

// ---------------------------------------------------------------------------
// Tile and chart states
// ---------------------------------------------------------------------------

describe("KpiTile — four distinct states", () => {
  const base = { label: "Captured sales", value: "$1,234", valueNote: "11 payments", definition: "def" };
  it("ok: the value and its note", () => {
    const html = h(createElement(KpiTile, { ...base, state: { kind: "ok" } }));
    expect(html).toContain('data-state="ok"');
    expect(html).toContain("$1,234");
    expect(html).toContain("11 payments");
  });
  it("empty: the genuine zero stays, with an explicit empty message", () => {
    const html = h(createElement(KpiTile, { ...base, value: "$0", valueNote: "0 payments", state: { kind: "empty", message: "No payments in this period." } }));
    expect(html).toContain('data-state="empty"');
    expect(html).toContain("$0");
    expect(html).toContain("No payments in this period.");
  });
  it("unavailable: no figure, no dash, no delta — the message says the server returned nothing", () => {
    const html = h(createElement(KpiTile, { ...base, value: "—", valueNote: "—", delta: { kind: "up", pct: 10, text: "+10%" }, state: { kind: "unavailable", message: "Not returned by the server for this period." } }));
    expect(html).toContain('data-state="unavailable"');
    expect(html).toContain("Not available");
    expect(html).toContain("Not returned by the server for this period.");
    expect(html).not.toContain("$1,234");
    expect(html).not.toContain("+10%");
    expect(html).not.toContain(">—<");
  });
  it("error: 'Not read', never a zero, no delta", () => {
    const html = h(createElement(KpiTile, { ...base, value: "$0", valueNote: "0 payments", delta: { kind: "flat", pct: 0, text: "no change" }, state: { kind: "error", message: "Couldn't be read." } }));
    expect(html).toContain('data-state="error"');
    expect(html).toContain("Not read");
    expect(html).toContain("Couldn&#x27;t be read.");
    expect(html).not.toContain("$0");
    expect(html).not.toContain("0 payments");
    expect(html).not.toContain("no change");
  });
  it("default state is ok and the meta slot renders", () => {
    const html = h(createElement(KpiTile, { ...base, meta: createElement("i", null, "meta-marker") }));
    expect(html).toContain('data-state="ok"');
    expect(html).toContain("<i>meta-marker</i>");
  });
});

describe("ChartCard — unavailable is its own state, distinct from empty and error", () => {
  const card = (state: Parameters<typeof ChartCard>[0]["state"]) => h(createElement(ChartCard, { title: "T", description: "d", state, meta: createElement("i", null, "meta-marker") }, createElement("svg", { "data-plot": "" })));
  it("unavailable: role=status, 'Not available', no plot", () => {
    const html = card({ kind: "unavailable", message: "Not returned by the server." });
    expect(html).toContain('data-state="unavailable"');
    expect(html).toContain('role="status"');
    expect(html).toContain("Not available");
    expect(html).toContain("Not returned by the server.");
    expect(html).not.toContain("data-plot");
  });
  it("empty and error keep their roles and their own wording; ok draws the plot; every state carries the meta line", () => {
    expect(card({ kind: "empty", message: "nothing" })).toMatch(/data-state="empty"[\s\S]*role="status"[\s\S]*nothing/);
    expect(card({ kind: "error", message: "boom" })).toMatch(/data-state="error"[\s\S]*role="alert"[\s\S]*boom/);
    expect(card({ kind: "ok" })).toContain("data-plot");
    for (const s of [{ kind: "ok" } as const, { kind: "empty", message: "e" } as const, { kind: "error", message: "x" } as const, { kind: "unavailable", message: "u" } as const]) {
      expect(card(s), s.kind).toContain("<i>meta-marker</i>");
    }
  });
});

// ---------------------------------------------------------------------------
// Money KPIs — the real server component, read layer mocked
// ---------------------------------------------------------------------------

type Metric = { value_cents: number | null; count: number | null; basis: string; upper_bound_cents?: number | null; certainty?: string };
const metric = (value_cents: number | null, count: number | null, basis = "paid_at"): Metric => ({ value_cents, count, basis });

function overview(from: string, to: string, metrics: Record<string, Metric>, computed_at: string | null = COMPUTED) {
  const o = toMoneyOverview({ from, to, computed_at, metrics })!;
  return { ok: true as const, overview: o, figures: figuresFrom(o) };
}
const FULL = {
  gross_captured_volume: metric(132000, 11),
  platform_fees_gross: metric(18640, 10),
  refunded_volume: { value_cents: null, count: 1, upper_bound_cents: 4400, certainty: "uncertain", basis: "refunded_at" },
  seller_funds_released: metric(22500, 1, "payout_released_at"),
  seller_funds_pending: metric(26280, 4, "now()"),
  bank_payouts: { value_cents: null, count: null, basis: "not_tracked" },
};
const EMPTY = {
  gross_captured_volume: metric(0, 0),
  platform_fees_gross: metric(0, 0),
  refunded_volume: { value_cents: null, count: 0, upper_bound_cents: 0, certainty: "uncertain", basis: "refunded_at" },
  seller_funds_released: metric(0, 0, "payout_released_at"),
  seller_funds_pending: metric(0, 0, "now()"),
  bank_payouts: { value_cents: null, count: null, basis: "not_tracked" },
};
const FAIL = { ok: false as const, kind: "error" as const, message: "canceling statement due to statement timeout", code: "57014" };
const FROM = "2026-09-23";
const TO_PAST = "2026-10-21";

const tiles = (html: string) => [...html.matchAll(/data-state="(ok|empty|unavailable|error)"/g)].map((m) => m[1]);

beforeEach(() => {
  mocks.readPeriod.mockReset();
  mocks.readSeries.mockReset();
});

async function kpis(cur: unknown, prev: unknown, opts: { from?: string; to?: string; compact?: boolean } = {}) {
  const from = opts.from ?? FROM;
  const to = opts.to ?? TO_PAST;
  mocks.readPeriod.mockImplementation(async (f: string) => (f === from ? cur : prev));
  return h(await MoneyKpis({ from, to, compact: opts.compact ?? false }));
}

describe("MoneyKpis — labels on the KPI surface", () => {
  it("ok: range, UTC, USD and the server's computed_at are stated once for the period tiles; the pending tile is labelled point in time", async () => {
    const html = await kpis(overview(FROM, TO_PAST, FULL), overview("2026-08-25", "2026-09-22", FULL));
    expect(html).toContain("Sep 23 – Oct 21, 2026");
    expect(html).toContain("UTC calendar days");
    expect(html).toContain("USD");
    expect(html).toContain("as of 2026-10-22 10:54:59 UTC");
    expect(html).not.toContain(PARTIAL_LABEL);
    expect(html).toContain("Point in time (now), not a period");
    // every money tile is in the ok state (the bank tile is "Not tracked", a stated fact, and stays ok)
    expect(tiles(html)).toEqual(["ok", "ok", "ok", "ok", "ok", "ok"]);
    expect(html).toContain("$1,320");
  });

  it("a range that ends today carries the partial mark", async () => {
    const html = await kpis(overview(FROM, TODAY, FULL), overview("2026-08-25", "2026-09-22", FULL), { to: TODAY });
    expect(html).toContain(PARTIAL_LABEL);
  });

  it("a server that states no computed_at gets 'not stated', never a fabricated time", async () => {
    const html = await kpis(overview(FROM, TO_PAST, FULL, null), overview("2026-08-25", "2026-09-22", FULL));
    expect(html).toContain("as of: not stated by the server (read ");
    expect(html).not.toContain("as of 2026");
  });

  it("empty: zero rows in the period → each period tile is explicitly empty, the zeros stay", async () => {
    const html = await kpis(overview(FROM, TO_PAST, EMPTY), overview("2026-08-25", "2026-09-22", EMPTY));
    expect(tiles(html).slice(0, 4)).toEqual(["empty", "empty", "empty", "empty"]);
    expect(html).toContain("No payments in this period.");
    expect(html).toContain("No succeeded payments in this period.");
    expect(html).toContain("No fully refunded payments in this period.");
    expect(html).toContain("No released transfers in this period.");
    expect(html).toContain("$0");
  });

  it("unavailable: a payload without the measures → every period tile says the server returned nothing; no $0 and no dash as a figure", async () => {
    const html = await kpis(overview(FROM, TO_PAST, { bank_payouts: { value_cents: null, count: null, basis: "not_tracked" } }), FAIL);
    expect(tiles(html).slice(0, 4)).toEqual(["unavailable", "unavailable", "unavailable", "unavailable"]);
    expect(html.match(/Not returned by the server for this period\./g)?.length).toBeGreaterThanOrEqual(4);
    expect(html).not.toContain("$0");
  });

  it("error: the failed read is an alert and every tile is in the error state — no zero, no dash, no comparison", async () => {
    const html = await kpis(FAIL, overview("2026-08-25", "2026-09-22", FULL));
    expect(html).toContain('role="alert"');
    expect(html).toContain("couldn&#x27;t be loaded");
    expect(html).toContain("canceling statement due to statement timeout");
    expect(tiles(html)).toEqual(["error", "error", "error", "error", "error", "error"]);
    expect(html).toContain("read at ");
    expect(html).toContain("failed — nothing is shown");
    expect(html).not.toContain("$0");
    expect(html).not.toContain("$1,320");
    expect(html).not.toContain("vs previous period");
    // No freshness claim of any kind on a failed read — not even "not stated": every label says the read failed.
    expect(html).not.toContain("as of");
    expect(html.match(/failed — nothing is shown/g)?.length).toBe(2); // the group label and the pending tile's own label
  });

  it("compact (Today): same labels, four tiles, error state has four error tiles and the failed label", async () => {
    const ok = await kpis(overview(FROM, TO_PAST, FULL), overview("2026-08-25", "2026-09-22", FULL), { compact: true });
    expect(tiles(ok)).toEqual(["ok", "ok", "ok", "ok"]);
    expect(ok).toContain("as of 2026-10-22 10:54:59 UTC");
    expect(ok).toContain("USD");
    const err = await kpis(FAIL, FAIL, { compact: true });
    expect(tiles(err)).toEqual(["error", "error", "error", "error"]);
    expect(err).toContain("failed — nothing is shown");
    expect(err).not.toContain("as of");
  });
});

// ---------------------------------------------------------------------------
// Money charts
// ---------------------------------------------------------------------------

function series(from: string, to: string, figuresFor: (i: number) => Record<string, Metric>, computedAt: string | null = COMPUTED) {
  const list = buckets(from, to);
  return { ok: true as const, grain: "day" as const, calls: list.length, computedAt, points: list.map((b, i) => ({ bucket: b, figures: figuresFrom(toMoneyOverview({ from: b.from, to: b.to, computed_at: computedAt, metrics: figuresFor(i) })!) })) };
}
const cards = (html: string) => [...html.matchAll(/<figure[^>]*data-state="(ok|empty|unavailable|error)"/g)].map((m) => m[1]);

describe("MoneyCharts — labels and states on every chart", () => {
  it("ok: each card carries the range, UTC, USD or payments, and the series' oldest computed_at", async () => {
    mocks.readSeries.mockResolvedValue(series("2026-10-15", TO_PAST, () => FULL));
    const html = h(await MoneyCharts({ from: "2026-10-15", to: TO_PAST }));
    expect(cards(html)).toEqual(["ok", "ok", "ok", "ok"]);
    expect(html.match(/Oct 15 – Oct 21, 2026/g)?.length).toBeGreaterThanOrEqual(4);
    expect(html.match(/as of 2026-10-22 10:54:59 UTC/g)?.length).toBeGreaterThanOrEqual(4);
    expect(html.match(/UTC calendar days/g)?.length).toBeGreaterThanOrEqual(4);
    expect(html).not.toContain(PARTIAL_LABEL);
  });

  it("a series ending today is partial on every card", async () => {
    mocks.readSeries.mockResolvedValue(series("2026-10-15", TODAY, () => FULL));
    const html = h(await MoneyCharts({ from: "2026-10-15", to: TODAY }));
    expect(html.match(new RegExp(PARTIAL_LABEL.replace(/[()]/g, "\\$&"), "g"))?.length).toBeGreaterThanOrEqual(4);
    expect(html).toContain("today so far");
  });

  it("empty: every bucket has zero rows → empty state, nothing drawn", async () => {
    mocks.readSeries.mockResolvedValue(series("2026-10-15", TO_PAST, () => EMPTY));
    const html = h(await MoneyCharts({ from: "2026-10-15", to: TO_PAST }));
    expect(cards(html)).toEqual(["empty", "empty", "empty", "empty"]);
    expect(html).toContain("Nothing is drawn rather than a flat line");
    expect(html).not.toContain("<path d=");
  });

  it("unavailable: a measure the server did not return in any bucket is 'Not available', not an empty plot and not 'empty' — the others still draw", async () => {
    const withoutCaptured = () => ({ ...FULL, gross_captured_volume: undefined as unknown as Metric });
    mocks.readSeries.mockResolvedValue(series("2026-10-15", TO_PAST, withoutCaptured));
    const html = h(await MoneyCharts({ from: "2026-10-15", to: TO_PAST }));
    expect(cards(html)).toEqual(["unavailable", "ok", "ok", "ok"]);
    expect(html).toContain("Not available");
    expect(html).toContain("not returned by the server in any period");
  });

  it("a payload with no measures at all is unavailable on every card (never 'empty': nothing says the period had no rows)", async () => {
    mocks.readSeries.mockResolvedValue(series("2026-10-15", TO_PAST, () => ({})));
    const html = h(await MoneyCharts({ from: "2026-10-15", to: TO_PAST }));
    expect(cards(html)).toEqual(["unavailable", "unavailable", "unavailable", "unavailable"]);
  });

  it("error: the card is an alert with the failed bucket and the read-failed label; the Today variant too", async () => {
    mocks.readSeries.mockResolvedValue({ ...FAIL, failedBucket: "2026-10-17…2026-10-17" });
    const html = h(await MoneyCharts({ from: "2026-10-15", to: TO_PAST }));
    expect(cards(html)).toEqual(["error"]);
    expect(html).toContain('role="alert"');
    expect(html).toContain("2026-10-17…2026-10-17");
    expect(html).toContain("failed — nothing is shown");
    expect(html).not.toContain("as of 2026");
    const today = h(await MoneyCharts({ from: "2026-10-15", to: TO_PAST, only: "captured" }));
    expect(cards(today)).toEqual(["error"]);
    expect(today).toContain("failed — nothing is shown");
  });
});

// ---------------------------------------------------------------------------
// Today's counts and the System metric row
// ---------------------------------------------------------------------------

describe("Today's attention counts and the System metric row are labelled point in time with their freshness", () => {
  it("AttentionSummary with computed_at", () => {
    const html = h(createElement(AttentionSummary, { metrics: [{ key: "open_cases", label: "Open cases", value: 2 }], definitions: {}, computedAt: COMPUTED }));
    expect(html).toContain("Point in time (now), not a period");
    expect(html).toContain("as of 2026-10-22 10:54:59 UTC");
    expect(html).toContain("UTC");
  });
  it("AttentionSummary without computed_at says so (and the existing callers that pass none still render)", () => {
    const html = h(createElement(AttentionSummary, { metrics: [{ key: "open_cases", label: "Open cases", value: 0 }], definitions: {} }));
    expect(html).toContain("as of: not stated by the server (read ");
    expect(html).toContain("Nothing needs attention right now.");
  });
  it("Today passes ops.today()'s computed_at; System labels its metric row from job_health's generated_at", () => {
    expect(src("app/(console)/page.tsx")).toContain("<AttentionSummary metrics={today.metrics} definitions={METRIC_DEFINITIONS} computedAt={today.computed_at} />");
    const system = src("app/(console)/system/page.tsx");
    expect(system).toMatch(/<\/MetricGrid>\s*<FigureMeta pointInTime computedAt=\{health\.generated_at\} readAt=\{readAt\}/);
    expect(system).toContain("const readAt = new Date();");
  });
});
