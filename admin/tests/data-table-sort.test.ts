import { createElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * V-1 item 3 — client-side sorting and a text filter on the shared DataTable.
 *
 * The server still renders every cell; the client component receives the
 * rendered cells, each row's underlying sort values and its filter text, and
 * only re-orders or hides rows on this page. Nothing re-fetches, the server's
 * row set is unchanged, and the server-side filter chips stay. Headers are
 * native buttons (keyboard operable) with aria-sort on the sorted column.
 * There is no DOM in this suite, so interaction is proven through the pure
 * view functions and the rendered markup of a default sort.
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

import { matchesFilter, nextSort, sortedIndices, viewIndices } from "@/lib/table-view";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { OrderTable, orderFilterText } from "@/components/orders/OrderTable";
import { CaseTable, caseFilterText } from "@/components/cases/CaseTable";
import { UserTable, userFilterText } from "@/components/users/UserTable";
import { ListingTable, listingFilterText } from "@/components/marketplace/ListingTable";
import { ActionTable } from "@/components/actions/ActionTable";
import OrdersPage from "@/app/(console)/orders/page";
import UsersPage from "@/app/(console)/users/page";
import MarketplacePage from "@/app/(console)/marketplace/page";
import CasesPage from "@/app/(console)/cases/page";
import type { OrderRow, OpsCase, UserListItem, ListingSummary } from "@/lib/types";

const h = (el: ReactElement) => renderToStaticMarkup(el);
const thead = (html: string) => html.slice(html.indexOf("<thead"), html.indexOf("</thead>"));
const tbodyRows = (html: string) => [...html.slice(html.indexOf("<tbody")).matchAll(/<tr[^>]*>/g)].length;
/** td[data-sort-value] values of one column, in row order. */
const sortValues = (html: string, col: number) =>
  [...html.slice(html.indexOf("<tbody")).matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)].map((m) => [...m[1].matchAll(/<td([^>]*)>/g)][col]?.[1].match(/data-sort-value="([^"]*)"/)?.[1] ?? null);
/** The underlying values of every sortable cell in the body. */
const allSortValues = (html: string) => [...html.slice(html.indexOf("<tbody")).matchAll(/data-sort-value="([^"]*)"/g)].map((m) => m[1]);
const SEARCH_INPUT = /<input[^>]*type="search"/;

// ---------------------------------------------------------------------------
// Pure view functions
// ---------------------------------------------------------------------------

describe("nextSort — none → first direction → the other → back to server order", () => {
  it("cycles on one column and restarts on another", () => {
    expect(nextSort(null, "amount")).toEqual({ key: "amount", dir: "asc" });
    expect(nextSort({ key: "amount", dir: "asc" }, "amount")).toEqual({ key: "amount", dir: "desc" });
    expect(nextSort({ key: "amount", dir: "desc" }, "amount")).toBeNull();
    expect(nextSort({ key: "amount", dir: "desc" }, "name")).toEqual({ key: "name", dir: "asc" });
  });
  it("a column whose first direction is desc (counts, dates) cycles desc → asc → none", () => {
    expect(nextSort(null, "created", "desc")).toEqual({ key: "created", dir: "desc" });
    expect(nextSort({ key: "created", dir: "desc" }, "created", "desc")).toEqual({ key: "created", dir: "asc" });
    expect(nextSort({ key: "created", dir: "asc" }, "created", "desc")).toBeNull();
  });
});

describe("sortedIndices — by the underlying value, stable, blanks last in both directions", () => {
  it("numbers", () => {
    expect(sortedIndices([30, 10, 20], "asc")).toEqual([1, 2, 0]);
    expect(sortedIndices([30, 10, 20], "desc")).toEqual([0, 2, 1]);
  });
  it("strings compare case-insensitively and naturally (a9 before a10)", () => {
    expect(sortedIndices(["b", "A", "c"], "asc")).toEqual([1, 0, 2]);
    expect(sortedIndices(["a10", "a9", "a1"], "asc")).toEqual([2, 1, 0]);
  });
  it("ties keep the server's order, ascending and descending alike", () => {
    expect(sortedIndices([5, 5, 5, 1], "asc")).toEqual([3, 0, 1, 2]);
    expect(sortedIndices([5, 5, 5, 1], "desc")).toEqual([0, 1, 2, 3]);
  });
  it("null, undefined and empty strings sort last whichever the direction", () => {
    expect(sortedIndices([null, 2, undefined, 1, ""], "asc")).toEqual([3, 1, 0, 2, 4]);
    expect(sortedIndices([null, 2, undefined, 1, ""], "desc")).toEqual([1, 3, 0, 2, 4]);
  });
  it("booleans: false before true", () => {
    expect(sortedIndices([true, false, true], "asc")).toEqual([1, 0, 2]);
  });
});

describe("matchesFilter — case-insensitive, every word must appear, blank matches all", () => {
  it("matches", () => {
    expect(matchesFilter("Little Havana Block Party pi_test_000013", "")).toBe(true);
    expect(matchesFilter("Little Havana Block Party pi_test_000013", "   ")).toBe(true);
    expect(matchesFilter("Little Havana Block Party pi_test_000013", "havana")).toBe(true);
    expect(matchesFilter("Little Havana Block Party pi_test_000013", "party little")).toBe(true);
    expect(matchesFilter("Little Havana Block Party pi_test_000013", "PI_TEST")).toBe(true);
  });
  it("does not match when any word is missing", () => {
    expect(matchesFilter("Little Havana Block Party", "havana miami")).toBe(false);
    expect(matchesFilter("", "x")).toBe(false);
  });
});

describe("viewIndices — filter then sort; no sort keeps the server's order", () => {
  const rows = [
    { sort: { n: 3, s: "c" }, filter: "alpha c" },
    { sort: { n: 1, s: "a" }, filter: "beta a" },
    { sort: { n: 2, s: "b" }, filter: "alpha b" },
  ];
  it("server order with no sort and no query", () => expect(viewIndices(rows, null, "")).toEqual([0, 1, 2]));
  it("sorted", () => expect(viewIndices(rows, { key: "n", dir: "asc" }, "")).toEqual([1, 2, 0]));
  it("filtered, order kept", () => expect(viewIndices(rows, null, "alpha")).toEqual([0, 2]));
  it("filtered and sorted", () => expect(viewIndices(rows, { key: "s", dir: "desc" }, "alpha")).toEqual([0, 2]));
  it("a sort key no row carries leaves the server order", () => expect(viewIndices(rows, { key: "missing", dir: "asc" }, "")).toEqual([0, 1, 2]));
});

// ---------------------------------------------------------------------------
// DataTable markup
// ---------------------------------------------------------------------------

type R = { id: string; name: string; amount: number | null; when: string };
const ROWS: R[] = [
  { id: "r1", name: "Beta", amount: 300, when: "2026-10-02T00:00:00Z" },
  { id: "r2", name: "alpha", amount: null, when: "2026-10-03T00:00:00Z" },
  { id: "r3", name: "Gamma", amount: 100, when: "2026-10-01T00:00:00Z" },
];
const cols = (sortable: boolean): Column<R>[] => [
  { key: "name", header: "Name", render: (r) => r.name, ...(sortable ? { sortValue: (r) => r.name } : {}) },
  { key: "amount", header: "Amount", align: "right", render: (r) => (r.amount === null ? "—" : `$${r.amount}`), ...(sortable ? { sortValue: (r) => r.amount, firstSortDir: "desc" as const } : {}) },
  { key: "when", header: createElement("abbr", { title: "Created at" }, "Created"), headerText: "Created", render: (r) => r.when, ...(sortable ? { sortValue: (r) => r.when } : {}) },
];
const table = (props: Partial<Parameters<typeof DataTable<R>>[0]> & { sortable?: boolean } = {}) => {
  const { sortable = true, ...rest } = props;
  return h(createElement(DataTable<R>, { columns: cols(sortable), rows: ROWS, rowKey: (r) => r.id, basePath: "/x", caption: "Things", ...rest }));
};

describe("DataTable with sortable columns", () => {
  it("every sortable header is a native button labelled for its column; a plain header stays plain; nothing is sorted until asked", () => {
    const html = table();
    const head = thead(html);
    expect(head.match(/<button type="button"/g)?.length).toBe(3);
    expect(head).toContain('aria-label="Sort by Name"');
    expect(head).toContain('aria-label="Sort by Amount"');
    expect(head).toContain('aria-label="Sort by Created"'); // headerText when the header is not a string
    expect(head).not.toContain("aria-sort");
    expect(head).not.toContain('tabindex="-1"');
    expect(head).not.toContain("onkeydown");
    // rows in the server's order, each sortable cell carrying its underlying value (not its rendering)
    expect(sortValues(html, 0)).toEqual(["Beta", "alpha", "Gamma"]);
    expect(sortValues(html, 1)).toEqual(["300", "", "100"]);
  });

  it("a default sort renders the rows in that order with aria-sort on that column only", () => {
    const html = table({ defaultSort: { key: "amount", dir: "desc" } });
    expect(thead(html).match(/aria-sort="descending"/g)?.length).toBe(1);
    expect(thead(html)).not.toContain('aria-sort="ascending"');
    expect(sortValues(html, 1)).toEqual(["300", "100", ""]); // blanks last
    expect(sortValues(html, 0)).toEqual(["Beta", "Gamma", "alpha"]);
    const asc = table({ defaultSort: { key: "name", dir: "asc" } });
    expect(thead(asc)).toContain('aria-sort="ascending"');
    expect(sortValues(asc, 0)).toEqual(["alpha", "Beta", "Gamma"]);
  });

  it("the sort status says the order applies to this page only", () => {
    const html = table({ defaultSort: { key: "amount", dir: "desc" } });
    expect(html).toContain("Sorted by Amount, descending — this page only");
  });

  it("filterable: a labelled search field before the table (focus order), with the shown-of-total status and each row's filter text; not filterable: no field", () => {
    const html = table({ filterable: true, filterText: (r) => `${r.name} ${r.when}` });
    const input = html.search(SEARCH_INPUT);
    expect(input).toBeGreaterThan(-1);
    expect(input).toBeLessThan(html.indexOf("<table"));
    expect(html).toMatch(/<label for="[^"]+"[^>]*><span>Filter rows on this page<\/span><input id="[^"]+"[^>]*type="search"/);
    expect(html).toContain("3 of 3 rows shown");
    expect(html).toContain('data-filter="Beta 2026-10-02T00:00:00Z"');
    expect(table()).not.toMatch(SEARCH_INPUT);
    expect(table()).not.toContain("data-filter=");
    // filterable alone (no sortable column) is enough to opt in
    const onlyFilter = table({ sortable: false, filterable: true });
    expect(onlyFilter).toMatch(SEARCH_INPUT);
    expect(thead(onlyFilter)).not.toContain("<button");
  });

  it("keeps the server-side pagination, the caption, the selected row and the card layout around the client table", () => {
    const html = h(
      createElement(DataTable<R>, {
        columns: cols(true),
        rows: ROWS,
        rowKey: (r) => r.id,
        basePath: "/x",
        caption: "Things",
        nextCursor: "abc",
        searchParams: { cursor: "prev" },
        isSelected: (r) => r.id === "r2",
        card: (r) => createElement("article", null, r.name),
      }),
    );
    expect(html).toContain('<caption class="sr-only">Things</caption>');
    expect(html).toContain('href="/x?cursor=abc"');
    expect(html).toContain("(continued)");
    expect(html).toContain("First page");
    expect(html.match(/aria-selected="true"/g)?.length).toBe(1);
    expect(html).toMatch(/<ul[^>]*md:hidden/);
    expect(html).toMatch(/hidden md:block/);
    expect(html.match(/<article>/g)?.length).toBe(3);
  });

  it("the DC-2 notice slot renders above the table", () => {
    const html = table({ notice: createElement("em", null, "slot-marker") });
    expect(html.indexOf("<em>slot-marker</em>")).toBeLessThan(html.indexOf("<table"));
  });

  it("a table that opts into nothing is the plain server table: no buttons, no field, no status line", () => {
    const html = table({ sortable: false });
    expect(thead(html)).not.toContain("<button");
    expect(html).not.toMatch(SEARCH_INPUT);
    expect(html).not.toContain("this page only");
    expect(html).not.toContain("data-sort-value=");
    expect(tbodyRows(html)).toBe(3);
    // control: a table elsewhere in the console that did not opt in renders no controls either
    const actions = h(createElement(ActionTable, { rows: [{ id: "a1", action_type: "case_note", state: "succeeded" }], basePath: "/x" }));
    expect(thead(actions)).not.toContain("<button");
    expect(actions).not.toMatch(SEARCH_INPUT);
  });

  it("rows are the server's rows: sorting never drops or adds one", () => {
    for (const d of [null, { key: "name", dir: "asc" as const }, { key: "amount", dir: "desc" as const }, { key: "when", dir: "asc" as const }]) {
      const html = table({ defaultSort: d ?? undefined });
      expect(tbodyRows(html), JSON.stringify(d)).toBe(3);
      for (const r of ROWS) expect(html, r.id).toContain(r.name);
    }
  });
});

// ---------------------------------------------------------------------------
// The console's tables: underlying values and filter text
// ---------------------------------------------------------------------------

const order: OrderRow = {
  payment_id: "9a900000-0000-4000-8000-000000000013",
  created_at: "2026-10-01T12:00:00Z",
  payment_status: "refunded",
  amount: 4000,
  total: 4400,
  stripe_payment_intent_id: "pi_test_000013",
  event_name: "Little Havana Block Party",
  event_date: "2026-11-02",
  mode: "buy_now",
  transfer_id: "7a000000-0000-4000-8000-000000000013",
  transfer_status: "buyer_confirmed",
  buyer_confirmed_at: null,
  seller_funds_state: "refund_pending",
  open_cases: 2,
  buyer: { id: "b0000000-0000-4000-8000-000000000003", display_name: "Ava Chen" },
  seller: { id: "5e11e000-0000-4000-8000-000000000002", display_name: "Sofia Reyes" },
};

describe("OrderTable sorts by the row's recorded values and filters on what the row shows", () => {
  it("amount is cents, statuses are the recorded codes, the transfer label is row-aware", () => {
    const html = h(createElement(OrderTable, { rows: [order], basePath: "/orders" }));
    const head = thead(html);
    expect(head.match(/<button type="button"/g)?.length).toBeGreaterThanOrEqual(5);
    const values = allSortValues(html);
    expect(values).toContain("4000");
    expect(values).not.toContain("$40.00 USD");
    expect(values).toContain("refunded");
    expect(values).toContain("Little Havana Block Party");
    expect(values).toContain("refund_pending");
  });
  it("filter text carries the name, references, parties and the reviewed labels", () => {
    const t = orderFilterText(order);
    for (const s of ["Little Havana Block Party", "9a900000-0000-4000-8000-000000000013", "pi_test_000013", "Ava Chen", "Sofia Reyes", "Refund recorded", "Confirmed status, no confirmation record", "Refund owed to buyer", "buy now", "2026-11-02"]) {
      expect(t, s).toContain(s);
    }
    expect(matchesFilter(t, "havana ava")).toBe(true);
    // and the table hands exactly that text to the client when a page opts in
    const html = h(createElement(OrderTable, { rows: [order], basePath: "/orders", filterable: true }));
    expect(html).toContain(`data-filter="${t.replace(/&/g, "&amp;").replace(/"/g, "&quot;")}"`);
  });
});

describe("CaseTable, UserTable and ListingTable expose their underlying values", () => {
  const c: OpsCase = { id: "11111111-2222-4333-8444-555555555555", title: "Transfer overdue", summary: "sum", case_type: "transfer_overdue", status: "open", priority: "p1", due_at: "2026-10-05T00:00:00Z", detected_at: "2026-10-01T00:00:00Z", assignee: null, subject_kind: "transfer", subject_label: "TR-1" };
  it("CaseTable: priority code, ISO timestamps; filter text has title, type, status, subject", () => {
    const html = h(createElement(CaseTable, { rows: [c], basePath: "/" }));
    const values = allSortValues(html);
    expect(values).toContain("p1");
    expect(values).toContain("2026-10-05T00:00:00Z");
    expect(values).toContain("2026-10-01T00:00:00Z");
    const t = caseFilterText(c, "me-id");
    for (const s of ["Transfer overdue", "sum", "transfer_overdue", "open", "p1", "TR-1", "unassigned"]) expect(t, s).toContain(s);
  });
  const u: UserListItem = { id: "b0000000-0000-4000-8000-000000000003", display_name: "Ava Chen", email_masked: "a***@example.test", is_verified_seller: true, stripe_onboarding_complete: false, listing_count: 3, risk_tier: "low", is_listing_blocked: false, open_cases: 0, created_at: "2026-09-01T00:00:00Z" };
  it("UserTable: counts are numbers, flags booleans, joined is ISO", () => {
    const html = h(createElement(UserTable, { rows: [u], basePath: "/users" }));
    const values = allSortValues(html);
    expect(values).toEqual(expect.arrayContaining(["Ava Chen", "a***@example.test", "true", "false", "3", "low", "0", "2026-09-01T00:00:00Z"]));
    expect(userFilterText(u)).toContain("Ava Chen");
    expect(userFilterText(u)).toContain("a***@example.test");
  });
  const l: ListingSummary = { id: "1a000000-0000-4000-8000-0000000000f1", event_name: "Fixture night", venue: "Room", status: "active", auction_status: "active", proof_status: "pending", buy_now_enabled: true, buy_now_price: 9900, current_bid: null, starting_bid: 5000, bid_count: 0, report_count: 1, open_cases: 0, ends_at: "2026-12-01T00:00:00Z", seller_id: "5e11e000-0000-4000-8000-000000000002", seller_display_name: "Sofia Reyes" };
  it("ListingTable: price is cents, counts numbers, ends ISO", () => {
    const html = h(createElement(ListingTable, { rows: [l], basePath: "/marketplace" }));
    const values = allSortValues(html);
    expect(values).toEqual(expect.arrayContaining(["Fixture night", "Sofia Reyes", "active", "pending", "9900", "1", "0", "2026-12-01T00:00:00Z"]));
    expect(listingFilterText(l)).toContain("Fixture night");
    expect(listingFilterText(l)).toContain("Room");
  });
});

// ---------------------------------------------------------------------------
// The pages opt in, and keep their server-side filters
// ---------------------------------------------------------------------------

const ME = "aaaaaaaa-0000-4000-8000-000000000001";
type Row = Record<string, unknown>;
const page = (items: Row[], count = items.length) => ({ ok: true, data: { items, next_cursor: null, count_hint: count } });

function operator() {
  mocks.requireOperator.mockResolvedValue({ id: ME, role: "platform_admin", email: null, aal: "aal2", whoami: { role: "platform_admin", email_masked: "f***@example.test" } });
}

describe("Orders, Users, Marketplace and Cases offer client-side sort and filter beside their server-side filters", () => {
  beforeEach(() => {
    mocks.callOps.mockReset();
    mocks.requireOperator.mockReset();
    operator();
  });

  it("Orders: dimension chips stay, the table gets sort buttons and the page filter; the same payment ids are rendered", async () => {
    const rows = [1, 2].map((i) => ({ ...order, payment_id: `9a900000-0000-4000-8000-0000000000${i}0`, event_name: `Event ${i}` }));
    mocks.callOps.mockImplementation(async (fn: string, args: Record<string, unknown> = {}) => (fn === "list_orders" ? (args.p_limit === 100 ? page([], 7) : page(rows)) : { ok: false, kind: "error", message: fn }));
    const html = h(await OrdersPage({ searchParams: Promise.resolve({ payment_status: "refunded" }) }));
    expect(html).toContain("filter-chip");
    expect(html).toContain("Remove filter: Payment:");
    expect(html).toContain("Filter rows on this page");
    expect(thead(html)).toContain('aria-label="Sort by Amount"');
    expect(html).toContain("9a900000-0000-4000-8000-000000000010");
    expect(html).toContain("9a900000-0000-4000-8000-000000000020");
    expect(mocks.callOps.mock.calls.filter(([fn]) => fn === "list_orders").length).toBe(5); // one list + four queue counts, as before
  });

  it("Users: the GET filter form stays and the table sorts and filters", async () => {
    mocks.callOps.mockImplementation(async (fn: string) => (fn === "list_users" ? page([{ id: "b0000000-0000-4000-8000-000000000003", display_name: "Ava Chen", listing_count: 3 }]) : { ok: false, kind: "error", message: fn }));
    const html = h(await UsersPage({ searchParams: Promise.resolve({}) }));
    expect(html).toContain('name="is_seller"');
    expect(html).toContain("Filter rows on this page");
    expect(thead(html)).toContain('aria-label="Sort by Listings"');
  });

  it("Marketplace: the GET filter form stays and the table sorts and filters", async () => {
    mocks.callOps.mockImplementation(async (fn: string) => (fn === "list_listings" ? page([{ id: "1a000000-0000-4000-8000-0000000000f1", event_name: "Fixture night", status: "active" }]) : { ok: false, kind: "error", message: fn }));
    const html = h(await MarketplacePage({ searchParams: Promise.resolve({}) }));
    expect(html).toContain('name="auction_status"');
    expect(html).toContain("Filter rows on this page");
    expect(thead(html)).toContain('aria-label="Sort by Status"');
  });

  it("Cases: the queue keeps its chips and keyboard model and gains a sort control and the page filter", async () => {
    const rows = [1, 2, 3].map((i) => ({ id: `11111111-2222-4333-8444-5555555555${i}0`, title: `Case ${i}`, case_type: "transfer_overdue", status: "open", priority: `p${i}`, detected_at: `2026-10-0${i}T00:00:00Z` }));
    mocks.callOps.mockImplementation(async (fn: string, args: Record<string, unknown> = {}) => (fn === "list_cases" ? (args.p_limit === 1 ? page([], 9) : page(rows)) : { ok: false, kind: "error", message: fn }));
    const html = h(await CasesPage({ searchParams: Promise.resolve({}) }));
    expect(html).toContain("filter-chip");
    expect(html).toContain('aria-describedby="queue-keys"');
    expect(html.match(/data-case-link=/g)?.length).toBe(3);
    expect(html).toContain("Filter rows on this page");
    expect(html).toMatch(/<select[^>]*aria-label="Sort cases on this page"/);
    for (const o of ["Server order", "Detected", "Due", "Priority", "Title"]) expect(html, o).toContain(`>${o}</option>`);
    expect(html).toMatch(/<button type="button"[^>]*aria-label="Sort direction/);
  });
});
