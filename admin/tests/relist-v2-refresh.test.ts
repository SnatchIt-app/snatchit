import { createElement, isValidElement, type ReactElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * The relist answer outlives the refresh that comes back with it.
 *
 * submitActionForm calls revalidatePath after any outcome, and Next commits the
 * re-rendered page in the same response as the action's return value ("Client
 * state is preserved for re-rendered components", next/dist/docs/01-app/
 * 01-getting-started/07-mutating-data.md). After a relist succeeds — or another
 * operator relisted first and 158 answers stale_state — the refreshed listing
 * is no longer relistable, so the form gives way to an info note. The
 * useActionState that holds the answer must therefore sit above that switch,
 * at the same place in the tree before and after, or React unmounts it and the
 * operator never sees 'Recorded.' / result.before or the stale copy /
 * result.current.
 *
 * Two halves, both against the real page tree:
 *  1. Slot: the listing_relist OutcomeHost has the same path (element type, key
 *     and index at every level, from the page root) in the page rendered from
 *     the loaded row and in the page rendered from the post-relist row. That is
 *     React's rule for keeping a component instance, so its state survives.
 *  2. Visible: the refreshed Relist panel, rendered with the state that host
 *     holds (useActionState returns it), shows the answer.
 */
const h = vi.hoisted(() => ({
  detail: null as unknown,
  role: "platform_admin" as string,
  /** The action state an already-mounted OutcomeHost holds; null = React's own useActionState. */
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
}));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    schema: () => ({
      rpc: async (fn: string) => (fn === "listing_detail" ? { data: h.detail, error: null } : { data: null, error: { code: "XX000", message: "unexpected call" } }),
    }),
  }),
}));
vi.mock("@/lib/auth/session", () => ({
  requireOperator: vi.fn(async () => ({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: h.role, whoami: { role: h.role } })),
}));

import ListingPage from "@/app/(console)/marketplace/[id]/page";
import { ConfirmForm, OutcomeHost } from "@/components/ui/ConfirmForm";
import { Panel } from "@/components/ui/Panel";
import { toActionOutcome } from "@/lib/types";

const LISTING_ID = "5a150000-0000-4000-8000-000000000158";
const ACTION_ID = "a1580000-0000-4000-8000-000000000001";
const RAW_UPDATED = "2026-10-21T03:47:04.123456+00:00";
const RAW_ENDS = "2026-10-20T23:59:00.000001-04:00";
const RAW_ENDED = "2026-10-21T03:47:04.5+00:00";
const NEW_ENDS = "2026-10-28T03:47:00+00:00";
const STALE_COPY = "listing changed since you loaded it — reload and try again";

function listingRow(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: LISTING_ID,
    seller_id: "0b000000-0000-4000-8000-0000000000bb",
    event_name: "House listing",
    status: "active",
    auction_status: "cancelled",
    proof_status: "verified",
    starting_bid: 5000,
    current_bid: null,
    bid_count: 0,
    buy_now_enabled: false,
    created_at: "2026-10-01T10:00:00+00:00",
    starts_at: "2026-10-01T10:00:00+00:00",
    ends_at: RAW_ENDS,
    ended_at: RAW_ENDED,
    updated_at: RAW_UPDATED,
    ...over,
  };
}

/** The row admin_relist_listing leaves behind: auction active, the new end, ended_at cleared, updated_at stamped by the listings trigger. */
const POST_RELIST = { auction_status: "active", ends_at: NEW_ENDS, ended_at: null, updated_at: "2026-10-21T22:10:31.000042+00:00" };
/** Another operator relisted first: the row this operator's stale_state answer reports as current. */
const RELISTED_ELSEWHERE = { auction_status: "active", ends_at: "2026-10-22T18:00:00+00:00", ended_at: null, updated_at: "2026-10-21T19:02:11.654321+00:00" };

const SUCCEEDED = toActionOutcome({
  status: "succeeded",
  action_id: ACTION_ID,
  result: {
    status: "succeeded",
    result: { listing_id: LISTING_ID, event_name: "House listing", relisted_by: "0b000000-0000-4000-8000-0000000000aa", new_ends_at: NEW_ENDS, previous_ends_at: RAW_ENDS },
    before: { status: "active", auction_status: "cancelled", ends_at: RAW_ENDS, ended_at: RAW_ENDED, updated_at: RAW_UPDATED },
  },
  reject_reason: null,
  message: null,
});

const STALE = toActionOutcome({
  status: "rejected",
  action_id: ACTION_ID,
  reject_reason: "stale_state",
  message: STALE_COPY,
  result: { status: "rejected", reject_reason: "stale_state", message: STALE_COPY, current: { status: "active", ...RELISTED_ELSEWHERE } },
});

async function page(listing: Record<string, unknown>): Promise<ReactNode> {
  h.detail = {
    listing,
    seller: null,
    payments: [],
    transfer: null,
    bids: { count: 0, highest: null, highest_bidder_id: null, recent: [] },
    reports: [],
    seller_flags: [],
    cases: [],
    actions: [],
    evidence: {},
  };
  return ListingPage({ params: Promise.resolve({ id: LISTING_ID }) });
}

type Step = { type: unknown; key: string | null; index: number };
type Found = { path: Step[]; el: ReactElement<Record<string, unknown>> };

/**
 * Where React reconciles an element on the client: from the page root down
 * `children`, the element type, key and index at each level (a nested array is
 * its own level, as React treats it). Panel is a Server Component, so the
 * client never sees a Panel element: it is rendered here and its output takes
 * its place, as in the RSC payload (section > [header, div > children]). A key
 * on the Server Component element is carried onto its output, as React Flight
 * does (keyPath), so keying the Panel still remounts what is under it.
 */
const SERVER_COMPONENTS = new Set<unknown>([Panel]);

function slotOf(tree: ReactNode, match: (el: ReactElement<Record<string, unknown>>) => boolean): Found | null {
  const search = (node: unknown, trail: Step[]): Found | null => {
    const list = Array.isArray(node) ? node : [node];
    for (let index = 0; index < list.length; index++) {
      let n = list[index];
      if (Array.isArray(n)) {
        const r = search(n, [...trail, { type: "array", key: null, index }]);
        if (r) return r;
        continue;
      }
      if (!isValidElement(n)) continue;
      if (match(n as ReactElement<Record<string, unknown>>)) {
        const el = n as ReactElement<Record<string, unknown>>;
        return { path: [...trail, { type: el.type, key: el.key, index }], el };
      }
      let keyPath: string | null = null;
      while (isValidElement(n) && SERVER_COMPONENTS.has(n.type)) {
        if (n.key !== null) keyPath = keyPath === null ? n.key : `${keyPath},${n.key}`;
        n = (n.type as (p: unknown) => ReactNode)(n.props);
      }
      if (Array.isArray(n)) {
        const r = search(n, [...trail, { type: "array", key: keyPath, index }]);
        if (r) return r;
        continue;
      }
      if (!isValidElement(n)) continue;
      const el = n as ReactElement<Record<string, unknown>>;
      const key = keyPath === null ? el.key : el.key === null ? keyPath : `${keyPath},${el.key}`;
      const step = { type: el.type, key, index };
      if (match(el)) return { path: [...trail, step], el };
      const r = search(el.props.children, [...trail, step]);
      if (r) return r;
    }
    return null;
  };
  return search(tree, []);
}

const isRelistHost = (el: ReactElement<Record<string, unknown>>) => el.type === OutcomeHost && el.props.actionType === "listing_relist";
const isRelistPanel = (el: ReactElement<Record<string, unknown>>) => el.type === Panel && el.props.title === "Relist";
const relistFormIn = (el: ReactElement<Record<string, unknown>> | undefined) =>
  el ? slotOf(el.props.children as ReactNode, (x) => x.type === ConfirmForm && x.props.actionType === "listing_relist") : null;

function decode(s: string): string {
  return s.replace(/&quot;/g, '"').replace(/&#x27;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
const textOf = (html: string) => decode(html.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();

beforeEach(() => {
  h.held = null;
  h.role = "platform_admin";
});

describe("the relist answer's host keeps its place across the refresh", () => {
  it.each([
    ["the relist succeeded", POST_RELIST],
    ["another operator relisted first (stale_state)", RELISTED_ELSEWHERE],
  ])("%s: same type, key and index at every level, so React keeps the instance", async (_label, after) => {
    const before = slotOf(await page(listingRow()), isRelistHost);
    const refreshed = slotOf(await page(listingRow(after)), isRelistHost);
    expect(before).not.toBeNull();
    expect(refreshed).not.toBeNull();
    expect(before?.el.key).toBe("listing_relist");
    expect(refreshed?.el.key).toBe("listing_relist");
    // the path is the client's: Panel appears as its rendered <section>, never as a Panel element
    expect(before?.path.some((s) => s.type === Panel)).toBe(false);
    expect(before?.path.map((s) => s.type)).toContain("section");
    expect(refreshed?.path.length).toBe(before?.path.length);
    refreshed?.path.forEach((step, i) => {
      expect(step.type, `level ${i}`).toBe(before?.path[i].type);
      expect(step.key, `level ${i}`).toBe(before?.path[i].key);
      expect(step.index, `level ${i}`).toBe(before?.path[i].index);
    });
    // The gap this guards: the loaded page has the form inside the host; the refreshed one has none.
    expect(relistFormIn(before?.el)).not.toBeNull();
    expect(relistFormIn(refreshed?.el)).toBeNull();
  });

  it("still relistable at a new version: the form re-keys on updated_at (fresh fields, new expected), the host stays", async () => {
    const NEWER = "2026-10-21T20:00:00.000777+00:00";
    const before = slotOf(await page(listingRow()), isRelistHost);
    const refreshed = slotOf(await page(listingRow({ updated_at: NEWER })), isRelistHost);
    expect(refreshed?.path.map((s) => [s.type, s.key, s.index])).toEqual(before?.path.map((s) => [s.type, s.key, s.index]));
    const f0 = relistFormIn(before?.el);
    const f1 = relistFormIn(refreshed?.el);
    expect(f0?.el.key).toBe(`relist-${RAW_UPDATED}`);
    expect(f1?.el.key).toBe(`relist-${NEWER}`);
    expect((f1?.el.props.expected as Record<string, unknown>).updated_at).toBe(NEWER);
  });

  it("the relist panel itself is the same Panel in the same slot in every state", async () => {
    const rows = [listingRow(), listingRow(POST_RELIST), listingRow({ updated_at: null }), listingRow({ status: "sold" })];
    const slots = await Promise.all(rows.map(async (r) => slotOf(await page(r), isRelistPanel)));
    for (const s of slots) {
      expect(s).not.toBeNull();
      expect(s?.path.map((x) => [x.type, x.key, x.index])).toEqual(slots[0]?.path.map((x) => [x.type, x.key, x.index]));
      expect(slotOf(s?.el.props.children as ReactNode, isRelistHost)).not.toBeNull();
    }
  });
});

describe("the refreshed page shows the answer the host holds", () => {
  async function refreshedPanel(after: Record<string, unknown>): Promise<string> {
    const panel = slotOf(await page(listingRow(after)), isRelistPanel);
    expect(panel).not.toBeNull();
    return textOf(renderToStaticMarkup(panel!.el));
  }

  it("succeeded: 'Recorded.', admin_relist_listing's answer and result.before, beside the note that it is no longer relistable", async () => {
    h.held = { submitted: true, outcome: SUCCEEDED };
    const text = await refreshedPanel(POST_RELIST);
    expect(text).toContain("Recorded.");
    expect(text).toContain(`Action ${ACTION_ID.slice(0, 8)}`);
    expect(text).toContain(`new_ends_at ${NEW_ENDS}`);
    expect(text).toContain(`previous_ends_at ${RAW_ENDS}`);
    expect(text).toContain(`updated_at ${RAW_UPDATED}`);
    expect(text).toContain(`ended_at ${RAW_ENDED}`);
    expect(text).toContain("Relist applies only to active listings whose auction is cancelled.");
  });

  it("stale_state after another operator relisted: 158's copy, Reload now and result.current", async () => {
    h.held = { submitted: true, outcome: STALE };
    const text = await refreshedPanel(RELISTED_ELSEWHERE);
    expect(text).toContain(STALE_COPY);
    expect(text).toContain("Reload now");
    expect(text).toContain(`updated_at ${RELISTED_ELSEWHERE.updated_at}`);
    expect(text).toContain("auction_status active");
    expect(text).toContain("ended_at null");
  });

  it("CONTROL: with nothing held, the refreshed panel shows no answer (the text above comes from the held state)", async () => {
    const text = await refreshedPanel(POST_RELIST);
    expect(text).not.toContain("Recorded.");
    expect(text).not.toContain(STALE_COPY);
    expect(text).toContain("Relist applies only to active listings whose auction is cancelled.");
  });

  it("a ConfirmForm without a host renders the relist answer the same way (own state)", () => {
    h.held = { submitted: true, outcome: SUCCEEDED };
    const html = renderToStaticMarkup(
      createElement(ConfirmForm, { idempotencyKey: "relist-key-0001", actionType: "listing_relist", subjectKind: "listing", subjectId: LISTING_ID, label: "Relist" }),
    );
    expect(textOf(html)).toContain(`new_ends_at ${NEW_ENDS}`);
    expect(textOf(html)).toContain(`updated_at ${RAW_UPDATED}`);
  });
});
