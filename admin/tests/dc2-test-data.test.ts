import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * DC-2 — the console half of test-data classification (DC-1, A's 180 on #164):
 * every count, badge and footer comes from what the server sent; the restricted
 * view is the only caller that passes p_include_test; a server without 180
 * shows nothing new. Spec: docs/dashboards/ADMIN_TEST_DATA_CLASSIFICATION.md
 * §3 and §5 (rules DC1-R3, DC1-R1 recorded 2026-10-26).
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
  usePathname: () => "/system/test-data",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import { HiddenTestRowsNotice, TestDataFooter, TestRecordBadge } from "@/components/ui/HiddenTestRowsNotice";
import { boolOrNull, toCase, toCaseDetail, toListingSummary, toMoneyOverview, toOrderRow, toReport, toSearchHits, toTestExcluded, toToday } from "@/lib/types";
import TestDataPage from "@/app/(console)/system/test-data/page";

const h = (el: React.ReactElement) => renderToStaticMarkup(el);
const SRC = resolve(__dirname, "../src");

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

describe("payload parsers carry the server's classification and never invent one", () => {
  it("is_test is true/false as sent and null otherwise, on rows, hits and details", () => {
    expect(boolOrNull(true)).toBe(true);
    expect(boolOrNull(false)).toBe(false);
    for (const v of [null, undefined, "true", 1, 0, {}]) expect(boolOrNull(v)).toBeNull();
    expect(toCase({ id: "c1", is_test: true })?.is_test).toBe(true);
    expect(toCase({ id: "c1" })?.is_test).toBeNull();
    expect(toOrderRow({ payment_id: "p1", is_test: false })?.is_test).toBe(false);
    expect(toListingSummary({ id: "l1", is_test: "yes" })?.is_test).toBeNull();
    expect(toReport({ id: "r1", is_test: true })?.is_test).toBe(true);
    expect(toSearchHits([{ kind: "case", id: "c1", is_test: true }])[0].is_test).toBe(true);
    expect(toCaseDetail({ case: { id: "c1" }, is_test: true })?.is_test).toBe(true);
    expect(toCaseDetail({ case: { id: "c1" } })?.is_test).toBeNull();
  });
  it("today.test_excluded is the five integer counts or nothing; money carries includes_test and test_excluded or null", () => {
    expect(toTestExcluded({ open_cases: 15, payments: 49, transfers: 32, listings: 106, reports: 1 })).toEqual({ open_cases: 15, payments: 49, transfers: 32, listings: 106, reports: 1 });
    expect(toTestExcluded({ open_cases: 15, payments: 49 })).toBeNull();
    expect(toTestExcluded({ open_cases: 15, payments: 49, transfers: 32, listings: "106", reports: 1 })).toBeNull();
    expect(toTestExcluded({ open_cases: -1, payments: 0, transfers: 0, listings: 0, reports: 0 })).toBeNull();
    expect(toToday({ attention: [], metrics: {}, test_excluded: { open_cases: 0, payments: 0, transfers: 0, listings: 0, reports: 0 } })?.test_excluded).toEqual({ open_cases: 0, payments: 0, transfers: 0, listings: 0, reports: 0 });
    expect(toToday({ attention: [], metrics: {} })?.test_excluded).toBeNull();
    const m = toMoneyOverview({ metrics: {}, includes_test: false, test_excluded: 7 });
    expect(m?.includes_test).toBe(false);
    expect(m?.test_excluded).toBe(7);
    const old = toMoneyOverview({ metrics: {} });
    expect(old?.includes_test).toBeNull();
    expect(old?.test_excluded).toBeNull();
    expect(toMoneyOverview({ metrics: {}, test_excluded: "7" })?.test_excluded).toBeNull();
  });
});

describe("notice, badge and footer render only from server-sent values", () => {
  it("the hidden-rows notice shows the server's integer with the breakdown, and nothing for null, a float or a negative", () => {
    const out = h(createElement(HiddenTestRowsNotice, { count: 203, breakdown: { open_cases: 15, payments: 49, transfers: 32, listings: 106, reports: 1 } }));
    expect(out).toContain("203 test records hidden by the server");
    expect(out).toContain("open cases 15");
    expect(out).toContain("listings 106");
    expect(h(createElement(HiddenTestRowsNotice, { count: 1 }))).toContain("1 test record hidden");
    for (const c of [null, undefined, 1.5, -1]) expect(h(createElement(HiddenTestRowsNotice, { count: c as number }))).toBe("");
  });
  it("the badge appears for true only; the footer appears only when the rows are classified at all", () => {
    expect(h(createElement(TestRecordBadge, { isTest: true }))).toContain("Test record");
    expect(h(createElement(TestRecordBadge, { isTest: false }))).toBe("");
    expect(h(createElement(TestRecordBadge, { isTest: null }))).toBe("");
    expect(h(createElement(TestDataFooter, { rows: [{ is_test: false }, { is_test: false }] }))).toContain("Restricted view");
    expect(h(createElement(TestDataFooter, { rows: [{ is_test: false }] }))).toContain('href="/system/test-data"');
    expect(h(createElement(TestDataFooter, { rows: [{}, { is_test: null }] }))).toBe("");
    expect(h(createElement(TestDataFooter, { rows: [] }))).toBe("");
  });
});

describe("DC1-R3: the restricted view is the only caller of p_include_test", () => {
  it("in the whole console source, p_include_test appears in exactly one page: system/test-data", () => {
    const files = walk(SRC).filter((f) => readFileSync(f, "utf8").includes("p_include_test"));
    expect(files.map((f) => f.slice(SRC.length + 1))).toEqual(["app/(console)/system/test-data/page.tsx"]);
  });
  it("that page passes p_include_test: true to the four list readers and badges rows from the server's is_test", async () => {
    mocks.requireOperator.mockResolvedValue({ id: "f0000000-0000-4000-8000-0000000000a1", role: "platform_admin" });
    const page = (items: unknown[]) => ({ ok: true, data: { items, next_cursor: null } });
    mocks.callOps.mockImplementation(async (fn: string) => {
      if (fn === "list_cases") return page([{ id: "c1000000-0000-4000-8000-000000000001", case_type: "refund_resolution", status: "open", is_test: true, created_at: "2026-10-20T00:00:00Z" }]);
      if (fn === "list_orders") return page([{ payment_id: "9a900000-0000-4000-8000-0000000000d4", payment_status: "succeeded", stripe_livemode: false, is_test: true, created_at: "2026-10-20T00:00:00Z" }]);
      if (fn === "list_listings") return page([{ id: "1a000000-0000-4000-8000-0000000000d4", event_name: "Fixture night", status: "active", is_test: false }]);
      if (fn === "list_reports") return page([{ id: "ab000000-0000-4000-8000-0000000000d4", target_type: "listing", status: "pending", is_test: true }]);
      return { ok: false, kind: "error", message: `unexpected ${fn}` };
    });
    const html = h(await TestDataPage());
    const calls = mocks.callOps.mock.calls.map(([fn, args]) => [fn, (args as Record<string, unknown>).p_include_test]);
    expect(calls).toEqual([
      ["list_cases", true],
      ["list_orders", true],
      ["list_listings", true],
      ["list_reports", true],
    ]);
    expect(html).toContain("Test records (restricted view)");
    expect(html).toContain("The server classifies rows (DC-1 is applied).");
    expect((html.match(/Test record<\/span>/g) ?? []).length).toBe(3); // three test rows badged; the real listing says Real
    expect(html).toContain("Real");
  });
  it("on a server without 180 the page says so and badges nothing", async () => {
    mocks.requireOperator.mockResolvedValue({ id: "f0000000-0000-4000-8000-0000000000a1", role: "platform_admin" });
    mocks.callOps.mockImplementation(async () => ({ ok: true, data: { items: [{ id: "c1000000-0000-4000-8000-000000000001", status: "open" }], next_cursor: null } }));
    const html = h(await TestDataPage());
    expect(html).toContain("does not classify rows yet");
    expect(html).not.toContain("Test record</span>");
    expect(html).toContain("Not classified");
  });
});

describe("the ordinary pages carry the badge and the footer but never the switch", () => {
  beforeEach(() => mocks.callOps.mockReset());
  it("the cases, orders, listings, reports and search surfaces import the footer and badge", () => {
    const surfaces = ["app/(console)/cases/page.tsx", "components/orders/OrderTable.tsx", "components/marketplace/ListingTable.tsx", "app/(console)/reports/page.tsx", "app/(console)/search/page.tsx"];
    for (const f of surfaces) {
      const src = readFileSync(resolve(SRC, f), "utf8");
      expect(src, f).toContain("TestDataFooter");
      expect(src, f).toContain("TestRecordBadge");
      expect(src, f).not.toContain("p_include_test");
    }
    expect(readFileSync(resolve(SRC, "app/(console)/page.tsx"), "utf8")).toContain("HiddenTestRowsNotice");
    expect(readFileSync(resolve(SRC, "app/(console)/system/page.tsx"), "utf8")).toContain("/system/test-data");
  });
});
