import { createElement, isValidElement, type ReactElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * The report_resolve answer outlives the refresh that comes back with it.
 *
 * submitActionForm calls revalidatePath after any outcome, and Next commits the
 * re-rendered page in the same response as the action's return value ("Client
 * state is preserved for re-rendered components", next/dist/docs/01-app/
 * 01-getting-started/07-mutating-data.md; "A single response carries data and
 * UI", 01-app/02-guides/server-actions.md). /marketplace/[id] lists only open
 * reports under "Resolve reports", and /reports?status=pending (the Today
 * tile) lists only pending ones, so Actioned / Dismiss (and Mark reviewing, on
 * the pending filter) drop the report from the refreshed list. If the
 * useActionState that holds the answer lives in that report's row, React
 * unmounts it in the same commit and the operator never sees 'Recorded.' or
 * the stale_state copy.
 *
 * Both halves run against the real page trees:
 *  1. Slot: find the element that receives the posted report's answer (the
 *     report_resolve host whose subtree holds that report's forms) in the
 *     loaded page. In the page re-rendered from the post-resolve rows, the
 *     element at that path (type and key at every level from the page root,
 *     and the index where there is no key; Server Components rendered as the
 *     client receives them) must be the same type with the same key: React's
 *     rule for keeping an instance and its state.
 *  2. Visible: that element, rendered with the state it holds, shows the answer
 *     once, at the report it belongs to (in that report's block or row when the
 *     report is still listed, else in the host's own place, naming the report),
 *     and nowhere else.
 * The answer comes from the real pipeline: the page's own form fields posted
 * through submitActionForm -> executeAction -> callOps, with only the Supabase
 * client and the session faked.
 *
 * The useActionState mock hands the held state to every host rendered while it
 * is set, so the visible half only renders the one element found by the slot
 * half (the element whose instance React keeps).
 */
const h = vi.hoisted(() => ({
  detail: null as unknown,
  listReports: null as unknown,
  exec: { data: null as unknown, error: null as unknown },
  calls: [] as { fn: string; args: Record<string, unknown> }[],
  /** The action state an already-mounted host holds; null = React's own useActionState. */
  held: null as unknown,
}));

vi.mock("react", async (importOriginal) => {
  const actual = await importOriginal<typeof import("react")>();
  return {
    ...actual,
    useActionState: ((action: never, initial: never, permalink?: string) =>
      h.held ? [h.held, () => {}, false] : actual.useActionState(action, initial, permalink)) as typeof actual.useActionState,
  };
});
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
}));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    schema: () => ({
      rpc: async (fn: string, args: Record<string, unknown>) => {
        h.calls.push({ fn, args });
        if (fn === "listing_detail") return { data: h.detail, error: null };
        if (fn === "list_reports") return h.listReports === null ? { data: null, error: { code: "XX000", message: "list_reports failed" } } : { data: h.listReports, error: null };
        if (fn === "execute_action") return h.exec;
        return { data: null, error: { code: "XX000", message: `unexpected call ${fn}` } };
      },
    }),
  }),
}));
vi.mock("@/lib/auth/session", () => ({
  requireOperator: vi.fn(async () => ({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: "platform_admin", whoami: { role: "platform_admin" } })),
}));

import { revalidatePath } from "next/cache";
import ListingPage from "@/app/(console)/marketplace/[id]/page";
import ReportsPage from "@/app/(console)/reports/page";
// ListOutcomeHost is what this fix adds; on the parent commit the import is undefined and this file still loads.
import { ConfirmForm, ListOutcomeHost, OutcomeHost } from "@/components/ui/ConfirmForm";
import { Panel } from "@/components/ui/Panel";
import { DataTable } from "@/components/ui/DataTable";
import { ReportResolveForms } from "@/components/reports/ReportResolveForms";
import { submitActionForm, type ActionFormState } from "@/lib/actions";

const LISTING_ID = "5a150000-0000-4000-8000-000000000121";
const ACTION_ID = "a1210000-0000-4000-8000-000000000001";
// Distinct 8-char prefixes, so a caption naming the wrong report cannot pass.
const A = "a7000000-0000-4000-8000-00000000000a";
const B = "b7000000-0000-4000-8000-00000000000b";
const STALE_COPY = "report is dismissed, you saw reviewing";

function report(id: string, over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id,
    reporter_id: "0c000000-0000-4000-8000-0000000000cc",
    reporter_label: "reporter",
    target_type: "listing",
    target_id: LISTING_ID,
    target_label: "House listing",
    reason: id === A ? "counterfeit" : "spam",
    notes: id === A ? "seat numbers do not exist" : "same photo on three listings",
    status: "pending",
    created_at: id === A ? "2026-10-21T12:00:00+00:00" : "2026-10-20T12:00:00+00:00",
    resolved_at: null,
    open_cases: 0,
    ...over,
  };
}
const closed = (id: string, status: "actioned" | "dismissed") => report(id, { status, resolved_at: "2026-10-21T22:10:31.000042+00:00" });

async function listingPage(reports: Record<string, unknown>[]): Promise<ReactNode> {
  h.detail = {
    listing: {
      id: LISTING_ID,
      seller_id: "0b000000-0000-4000-8000-0000000000bb",
      event_name: "House listing",
      status: "active",
      auction_status: "active",
      proof_status: "verified",
      starting_bid: 5000,
      bid_count: 0,
      buy_now_enabled: false,
      created_at: "2026-10-01T10:00:00+00:00",
      updated_at: "2026-10-21T03:47:04.123456+00:00",
    },
    seller: null,
    payments: [],
    transfer: null,
    bids: { count: 0, highest: null, highest_bidder_id: null, recent: [] },
    reports,
    seller_flags: [],
    cases: [],
    actions: [],
    evidence: {},
  };
  return ListingPage({ params: Promise.resolve({ id: LISTING_ID }) });
}

async function reportsPage(rows: Record<string, unknown>[] | null, sp: Record<string, string> = {}): Promise<ReactNode> {
  h.listReports = rows === null ? null : { items: rows, next_cursor: null, count_hint: rows.length };
  return ReportsPage({ searchParams: Promise.resolve(sp) });
}

// ---- the tree as the client reconciles it ----

type El = ReactElement<Record<string, unknown>>;
type Step = { type: unknown; key: string | null; index: number };
type Found = { path: Step[]; el: El };

/**
 * Server Components never reach the client as elements: their output takes
 * their place in the RSC payload, and a key on the Server Component element is
 * carried onto that output (React Flight's keyPath). Panel, DataTable and
 * ReportResolveForms have no "use client"; they are rendered here the same way.
 */
const SERVER_COMPONENTS = new Set<unknown>([Panel, DataTable, ReportResolveForms]);

/** Every element matching, with its client path, in tree order. */
function slots(tree: ReactNode, match: (el: El) => boolean): Found[] {
  const out: Found[] = [];
  const search = (node: unknown, trail: Step[]): void => {
    const list = Array.isArray(node) ? node : [node];
    for (let index = 0; index < list.length; index++) {
      let n = list[index];
      if (Array.isArray(n)) {
        search(n, [...trail, { type: "array", key: null, index }]);
        continue;
      }
      if (!isValidElement(n)) continue;
      let keyPath: string | null = null;
      while (isValidElement(n) && SERVER_COMPONENTS.has(n.type)) {
        if (n.key !== null) keyPath = keyPath === null ? n.key : `${keyPath},${n.key}`;
        n = (n.type as (p: unknown) => ReactNode)(n.props);
      }
      if (Array.isArray(n)) {
        search(n, [...trail, { type: "array", key: keyPath, index }]);
        continue;
      }
      if (!isValidElement(n)) continue;
      const el = n as El;
      const key = keyPath === null ? el.key : el.key === null ? keyPath : `${keyPath},${el.key}`;
      const step = { type: el.type, key, index };
      if (match(el)) out.push({ path: [...trail, step], el });
      search(el.props.children, [...trail, step]);
    }
  };
  search(tree, []);
  return out;
}

/**
 * React keeps a child when its type and key match; among siblings an explicit
 * key is matched wherever it moved, a missing key by position.
 */
const sameStep = (s: Step, t: Step) => s.type === t.type && s.key === t.key && (s.key !== null || s.index === t.index);
const samePath = (a: Step[], b: Step[]) => a.length === b.length && a.every((s, i) => sameStep(s, b[i]));

/** What the client reconciles at `path` in `tree`: an element of the same type and key there, or null. */
const atPath = (tree: ReactNode, path: Step[]): Found | null => slots(tree, () => true).find((f) => samePath(f.path, path)) ?? null;

/** Every element matching, Server Components rendered, every prop searched. */
function findAll(tree: unknown, match: (el: El) => boolean): El[] {
  const out: El[] = [];
  const visit = (n: unknown): void => {
    if (Array.isArray(n)) return n.forEach(visit);
    if (!isValidElement(n)) return;
    const el = n as El;
    if (match(el)) out.push(el);
    if (SERVER_COMPONENTS.has(el.type)) return visit((el.type as (p: unknown) => ReactNode)(el.props));
    for (const v of Object.values(el.props)) visit(v);
  };
  visit(tree);
  return out;
}

const resolveForms = (tree: unknown, subjectId?: string) =>
  findAll(tree, (el) => el.type === ConfirmForm && el.props.actionType === "report_resolve" && (subjectId === undefined || el.props.subjectId === subjectId));

/** A report_resolve host: an OutcomeHost (the parent keeps one per report row) or the ListOutcomeHost. */
const isAnswerHost = (el: El) => (el.type === OutcomeHost || el.type === ListOutcomeHost) && el.props.actionType === "report_resolve";

/**
 * The element whose state receives the answer to a post of `subjectId`'s
 * forms: the innermost report_resolve host around them (a form posts through
 * the nearest host). slots() lists ancestors first, so it is the last match.
 */
function hostFor(tree: ReactNode, subjectId: string): Found {
  const around = slots(tree, (el) => isAnswerHost(el) && resolveForms(el, subjectId).length > 0);
  expect(around.length, `a report_resolve host around ${subjectId}'s forms`).toBeGreaterThan(0);
  return around[around.length - 1];
}

/** The loaded page's answer host for `subjectId`, and what stands at its place after the refresh. */
function acrossRefresh(loaded: ReactNode, refreshed: ReactNode, subjectId: string): { before: Found; after: Found | null } {
  const before = hostFor(loaded, subjectId);
  return { before, after: atPath(refreshed, before.path) };
}

// ---- markup ----

function decode(s: string): string {
  return s.replace(/&quot;/g, '"').replace(/&#x27;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
const textOf = (html: string) => decode(html.replace(/<script\b[\s\S]*?<\/script>/g, " ").replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
const count = (s: string, sub: string) => s.split(sub).length - 1;
const ANSWER = "Recorded.";

/** The last report anchor (marketplace block or /reports row) before position `at`, or null. */
function anchorBefore(html: string, at: number): string | null {
  const all = [...html.slice(0, at).matchAll(/id="report-([0-9a-f-]{36})"/g)];
  return all.length ? all[all.length - 1][1] : null;
}
/** The subject of the last form field before position `at`, or null. */
function subjectBefore(html: string, at: number): string | null {
  const all = [...html.slice(0, at).matchAll(/name="subject_id" value="([^"]*)"/g)];
  return all.length ? all[all.length - 1][1] : null;
}

function inputs(html: string): { name: string; value: string | null; type: string | null }[] {
  return [...html.matchAll(/<input\b[^>]*>/g)].map((m) => {
    const tag = m[0];
    const attr = (a: string) => {
      const r = new RegExp(`\\s${a}="([^"]*)"`).exec(tag);
      return r ? decode(r[1]) : null;
    };
    return { name: attr("name") ?? "", value: attr("value"), type: attr("type") };
  });
}

/** Post the page's own form for (report, target status) through the real action, as the browser would. */
async function post(tree: ReactNode, reportId: string, status: string, reason = "triaged from the console"): Promise<ActionFormState> {
  const form = resolveForms(tree, reportId).find((f) => (f.props.params as Record<string, unknown>).status === status);
  expect(form, `${status} form for ${reportId}`).toBeDefined();
  const fd = new FormData();
  for (const i of inputs(renderToStaticMarkup(form!))) if (i.type === "hidden") fd.set(i.name, i.value ?? "");
  if (reason) fd.set("reason", reason);
  return submitActionForm({}, fd);
}

const succeeded = () => ({ data: { status: "succeeded", action_id: ACTION_ID, result: { status: "succeeded" } }, error: null });
const staleAnswer = () => ({ data: { status: "rejected", action_id: ACTION_ID, reject_reason: "stale_state", message: STALE_COPY, result: {} }, error: null });

beforeEach(() => {
  h.held = null;
  h.calls.length = 0;
  h.exec = succeeded();
  vi.mocked(revalidatePath).mockClear();
});

// ---------------------------------------------------------------------------

describe("submitActionForm names the subject its answer is for", () => {
  it("a report_resolve post: the outcome plus subject {kind, id} exactly as posted, and the page is revalidated", async () => {
    const state = await post(await listingPage([report(A), report(B)]), A, "actioned");
    expect(state.outcome?.status).toBe("succeeded");
    expect(state.subject).toStrictEqual({ kind: "report", id: A });
    expect(h.calls.find((c) => c.fn === "execute_action")?.args.p_subject_id).toBe(A);
    expect(revalidatePath).toHaveBeenCalledWith(`/marketplace/${LISTING_ID}`);
  });

  it("a refusal before any call still names the subject (no refresh follows it)", async () => {
    const state = await post(await listingPage([report(A), report(B)]), B, "dismissed", "");
    expect(state.invalid).toBe("A reason is required.");
    expect(state.subject).toStrictEqual({ kind: "report", id: B });
    expect(h.calls.some((c) => c.fn === "execute_action")).toBe(false);
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("a ref-addressed post (no subject id) names no subject", async () => {
    const fd = new FormData();
    for (const [k, v] of Object.entries({ idempotency_key: "0d000000-0000-4000-8000-000000000001", action_type: "job_retry", subject_kind: "job", subject_ref: "settle-payouts", reason: "retry" })) fd.set(k, v);
    const state = await submitActionForm({}, fd);
    expect(state.outcome?.status).toBe("succeeded");
    expect("subject" in state).toBe(false);
  });
});

describe("/marketplace/[id]: the host that receives the answer keeps its place across the refresh", () => {
  it.each([
    ["Actioned; another report is still open", [report(A), report(B)], [closed(A, "actioned"), report(B)]],
    ["Dismissed; it was the last open report", [report(A, { status: "reviewing" }), closed(B, "dismissed")], [closed(A, "dismissed"), closed(B, "dismissed")]],
    ["another operator dismissed it first (stale_state)", [report(A), report(B)], [closed(A, "dismissed"), report(B)]],
  ])("%s: the same type and key at every level of its path", async (_label, beforeRows, afterRows) => {
    const refreshed = await listingPage(afterRows);
    const { before, after } = acrossRefresh(await listingPage(beforeRows), refreshed, A);
    expect(after, "an element of the same type and key at the host's path after the refresh").not.toBeNull();
    expect(after?.el.type).toBe(before.el.type);
    expect(after?.el.key).toBe("report_resolve");
    // the path is the client's: Panel appears as its rendered <section>, never as a Panel element
    expect(before.path.some((s) => s.type === Panel || s.type === ReportResolveForms || s.type === DataTable)).toBe(false);
    // The gap this guards: A had forms in the loaded page; after the refresh it has none anywhere.
    expect(resolveForms(refreshed, A)).toHaveLength(0);
  });

  it("Mark reviewing keeps the report open: the host stays and A's forms re-key on the new status", async () => {
    const refreshed = await listingPage([report(A, { status: "reviewing" }), report(B)]);
    const { before, after } = acrossRefresh(await listingPage([report(A), report(B)]), refreshed, A);
    expect(after?.el.type).toBe(before.el.type);
    expect(resolveForms(refreshed, A).map((f) => f.key)).toEqual([`${A}-actioned-reviewing`, `${A}-dismissed-reviewing`]);
  });
});

describe("/marketplace/[id]: the refreshed page shows the answer the host holds, at the right report", () => {
  async function refreshedHostHtml(beforeRows: Record<string, unknown>[], afterRows: Record<string, unknown>[], subjectId: string): Promise<string> {
    const { after } = acrossRefresh(await listingPage(beforeRows), await listingPage(afterRows), subjectId);
    expect(after, "the host is still there after the refresh").not.toBeNull();
    return renderToStaticMarkup(after!.el);
  }

  it("Actioned, B still open: 'Recorded.' once, after the panel, naming A; A's forms are gone, B's block has no answer", async () => {
    const rows = [report(A), report(B)];
    h.held = await post(await listingPage(rows), A, "actioned");
    const html = await refreshedHostHtml(rows, [closed(A, "actioned"), report(B)], A);
    const text = textOf(html);
    expect(count(text, ANSWER)).toBe(1);
    expect(text).toContain(`Action ${ACTION_ID.slice(0, 8)}`);
    expect(text).toMatch(/report counterfeit · Actioned\s*—\s*no longer listed here/i);
    expect(html).not.toContain(`value="${A}"`);
    expect(html).toContain(`value="${B}"`);
    expect(html.indexOf(ANSWER)).toBeGreaterThan(html.lastIndexOf("</section>"));
  });

  it("Dismissed, the last open report: the panel is gone and the answer stays, naming A", async () => {
    const rows = [report(A, { status: "reviewing" }), closed(B, "dismissed")];
    h.held = await post(await listingPage(rows), A, "dismissed");
    const text = textOf(await refreshedHostHtml(rows, [closed(A, "dismissed"), closed(B, "dismissed")], A));
    expect(count(text, ANSWER)).toBe(1);
    expect(text).toMatch(/report counterfeit · Dismissed\s*—\s*no longer listed here/i);
    expect(text).not.toContain("Resolve reports");
  });

  it("stale_state after another operator dismissed it: the stale copy, the server's message and Reload now", async () => {
    h.exec = staleAnswer();
    const rows = [report(A, { status: "reviewing" }), report(B)];
    h.held = await post(await listingPage(rows), A, "actioned");
    expect(h.held).toMatchObject({ outcome: { status: "rejected", reason: "stale_state" } });
    const html = await refreshedHostHtml(rows, [closed(A, "dismissed"), report(B)], A);
    const text = textOf(html);
    expect(text).toContain("This record changed since you loaded it — reload.");
    expect(count(text, STALE_COPY)).toBe(1);
    expect(text).toContain("Reload now");
    expect(text).toMatch(/report counterfeit · Dismissed\s*—\s*no longer listed here/i);
  });

  it("Mark reviewing (still open): the answer shows in A's own place, right after A's forms, once", async () => {
    const rows = [report(A), report(B)];
    h.held = await post(await listingPage(rows), A, "reviewing");
    const html = await refreshedHostHtml(rows, [report(A, { status: "reviewing" }), report(B)], A);
    const at = html.indexOf(ANSWER);
    expect(count(textOf(html), ANSWER)).toBe(1);
    expect(subjectBefore(html, at)).toBe(A);
    expect([null, A]).toContain(anchorBefore(html, at));
    expect(textOf(html)).not.toContain("no longer listed here");
  });

  it("an answer about B shows at B, never at A", async () => {
    const rows = [report(A), report(B)];
    h.held = await post(await listingPage(rows), B, "reviewing");
    const html = await refreshedHostHtml(rows, [report(A), report(B, { status: "reviewing" })], B);
    const at = html.indexOf(ANSWER);
    expect(count(textOf(html), ANSWER)).toBe(1);
    expect(subjectBefore(html, at)).toBe(B);
    expect([null, B]).toContain(anchorBefore(html, at));
  });

  it("CONTROL: with nothing held, the refreshed host shows no answer (the text above comes from the held state)", async () => {
    const html = await refreshedHostHtml([report(A), report(B)], [closed(A, "actioned"), report(B)], B);
    expect(textOf(html)).not.toContain(ANSWER);
    expect(html).not.toContain('tabindex="-1"');
  });
});

describe("/marketplace/[id]: a fresh load lists the same open reports as before", () => {
  const resolvePanel = (tree: unknown) => findAll(tree, (el) => el.type === Panel && el.props.title === "Resolve reports")[0];
  const blocks = (html: string) => [...html.matchAll(/id="report-([0-9a-f-]{36})"/g)].map((m) => m[1]);

  it("only the open reports get a block and forms; closed ones get nothing", async () => {
    const tree = await listingPage([closed(A, "actioned"), report(B, { status: "reviewing" })]);
    const panel = resolvePanel(tree);
    expect(panel).toBeDefined();
    expect(panel.props.eyebrow).toBe("1");
    expect(blocks(renderToStaticMarkup(panel))).toEqual([B]);
    expect(resolveForms(tree, A)).toHaveLength(0);
    expect(resolveForms(tree, B).map((f) => (f.props.params as Record<string, unknown>).status)).toEqual(["actioned", "dismissed"]);
  });

  it("no open report: no Resolve reports panel, no forms, and nothing else rendered in its place", async () => {
    const tree = await listingPage([closed(A, "actioned"), closed(B, "dismissed")]);
    expect(resolvePanel(tree)).toBeUndefined();
    expect(resolveForms(tree)).toHaveLength(0);
    for (const host of slots(tree, isAnswerHost)) expect(renderToStaticMarkup(host.el)).toBe("");
  });
});

describe("/reports: the answer survives the row leaving the list", () => {
  it("status=pending (the Today tile): the host keeps its place when the actioned row leaves the page", async () => {
    const { before, after } = acrossRefresh(await reportsPage([report(A), report(B)], { status: "pending" }), await reportsPage([report(B)], { status: "pending" }), A);
    expect(after, "an element of the same type and key at the host's path after the refresh").not.toBeNull();
    expect(after?.el.type).toBe(before.el.type);
    expect(after?.el.key).toBe("report_resolve");
  });

  it("status=pending: the answer shows above the table, naming the report by its short id; nothing at B", async () => {
    const loaded = await reportsPage([report(A), report(B)], { status: "pending" });
    h.held = await post(loaded, A, "actioned", "counterfeit confirmed");
    expect(revalidatePath).toHaveBeenCalledWith("/reports?status=pending");
    const { after } = acrossRefresh(loaded, await reportsPage([report(B)], { status: "pending" }), A);
    expect(after).not.toBeNull();
    const html = renderToStaticMarkup(after!.el);
    const text = textOf(html);
    expect(count(text, ANSWER)).toBe(1);
    expect(text).toMatch(new RegExp(`report ${A.slice(0, 8)}\\s*—\\s*no longer listed here`, "i"));
    expect(html.indexOf(ANSWER)).toBeLessThan(html.indexOf("<table"));
    expect(html).toContain(`value="${B}"`);
  });

  it("Mark reviewing on the pending filter also drops the row; the answer stays", async () => {
    const loaded = await reportsPage([report(A), report(B)], { status: "pending" });
    h.held = await post(loaded, A, "reviewing");
    const { after } = acrossRefresh(loaded, await reportsPage([report(B)], { status: "pending" }), A);
    expect(after).not.toBeNull();
    const text = textOf(renderToStaticMarkup(after!.el));
    expect(count(text, ANSWER)).toBe(1);
    expect(text).toMatch(new RegExp(`report ${A.slice(0, 8)}\\s*—\\s*no longer listed here`, "i"));
  });

  it("unfiltered: the row stays (now closed) and shows the answer in its own cell, after the closed note, once", async () => {
    const loaded = await reportsPage([report(A), report(B)]);
    h.held = await post(loaded, A, "actioned");
    const { after } = acrossRefresh(loaded, await reportsPage([closed(A, "actioned"), report(B)]), A);
    expect(after).not.toBeNull();
    const html = renderToStaticMarkup(after!.el);
    const at = html.indexOf(ANSWER);
    expect(count(textOf(html), ANSWER)).toBe(1);
    expect(textOf(html.slice(0, at))).toMatch(/closed/);
    expect(subjectBefore(html, at)).toBeNull(); // before B's forms, and A has none now
    expect([null, A]).toContain(anchorBefore(html, at));
    expect(textOf(html)).not.toContain("no longer listed here");
  });

  it("a failed re-read after the action still shows the answer", async () => {
    const loaded = await reportsPage([report(A), report(B)], { status: "pending" });
    h.held = await post(loaded, A, "dismissed");
    const { after } = acrossRefresh(loaded, await reportsPage(null, { status: "pending" }), A);
    expect(after).not.toBeNull();
    const text = textOf(renderToStaticMarkup(after!.el));
    expect(text).toContain(ANSWER);
    expect(text).toMatch(new RegExp(`report ${A.slice(0, 8)}`, "i"));
  });

  it("CONTROL: a fresh load holds no answer", async () => {
    const tree = await reportsPage([report(B)], { status: "pending" });
    const html = renderToStaticMarkup(hostFor(tree, B).el);
    expect(textOf(html)).not.toContain(ANSWER);
    expect(html).not.toContain('tabindex="-1"');
  });
});

describe("ReportResolveForms outside a list host keeps its own host (unchanged behaviour)", () => {
  it("renders the held answer beside its forms", async () => {
    h.held = await post(await listingPage([report(A), report(B)]), A, "reviewing");
    const html = renderToStaticMarkup(createElement(ReportResolveForms, { report: { id: A, status: "reviewing" }, revalidate: "/x" }));
    expect(count(textOf(html), ANSWER)).toBe(1);
    expect(subjectBefore(html, html.indexOf(ANSWER))).toBe(A);
  });
});
