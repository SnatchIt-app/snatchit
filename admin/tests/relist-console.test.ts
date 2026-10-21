import { createElement, isValidElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

// listing_relist contract with migration 158 (PR #125): the live console sends the listing version the operator
// saw, byte for byte, and renders the server's answers. The page, ConfirmForm, the form-post adapter and the
// failure mapper run unchanged; only the transport (callOps) and the session are faked.

const h = vi.hoisted(() => ({
  calls: [] as { fn: string; args: Record<string, unknown> }[],
  detail: null as unknown,
  execReply: null as unknown,
  role: "platform_admin" as string,
  /**
   * When set, useActionState answers with this state: the state React keeps for a ConfirmForm instance it reuses
   * across the action's own refresh (same slot, same type, same key). Undefined = React's real hook.
   */
  heldState: undefined as unknown,
}));

vi.mock("react", async (importOriginal) => {
  const actual = await importOriginal<typeof import("react")>();
  const useActionState = ((action: never, initial: never, permalink?: string) =>
    h.heldState !== undefined ? [h.heldState, () => {}, false] : actual.useActionState(action, initial, permalink)) as typeof actual.useActionState;
  return { ...actual, useActionState };
});
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/ops", () => ({
  callOps: vi.fn(async (fn: string, args: Record<string, unknown> = {}) => {
    h.calls.push({ fn, args });
    if (fn === "listing_detail") return { ok: true, data: h.detail };
    return h.execReply;
  }),
}));
vi.mock("@/lib/auth/session", () => ({
  requireOperator: vi.fn(async () => ({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: h.role, whoami: { role: h.role } })),
}));

import { revalidatePath } from "next/cache";
import ListingPage from "../src/app/(console)/marketplace/[id]/page";
import { ConfirmForm, OutcomeText } from "../src/components/ui/ConfirmForm";
import { OpsFailureAlert } from "../src/components/ui/Alert";
import { submitActionForm } from "../src/lib/actions";
import { mapOpsError } from "../src/lib/ops-errors";
import { coerceParam, parseParamField } from "../src/lib/form-params";
import { toActionOutcome, type ActionOutcome } from "../src/lib/types";

const LISTING_ID = "5a150000-0000-4000-8000-000000000158";
const ACTION_ID = "a1580000-0000-4000-8000-000000000001";

// Raw to_jsonb(timestamptz) strings as ops.listing_detail returns them: offset + microseconds. A Date round trip
// would turn RAW_UPDATED into "2026-10-21T03:47:04.123Z" (milliseconds) and 158 would answer stale_state.
const RAW_UPDATED = "2026-10-21T03:47:04.123456+00:00";
const RAW_ENDS = "2026-10-20T23:59:00.000001-04:00";
const RAW_ENDED = "2026-10-21T03:47:04.5+00:00";

const STALE_COPY = "listing changed since you loaded it — reload and try again";
const OUTDATED_RAISE =
  "invalid_input: listing_relist requires expected.updated_at (the listing's updated_at exactly as ops.listing_detail returned it); reload the listing";

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

function detailWith(listing: Record<string, unknown>): Record<string, unknown> {
  return {
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
}

// ---- element-tree helpers (the page returns a tree; nothing is mounted) ----

function walk(node: unknown, visit: (el: ReactElement) => void): void {
  if (Array.isArray(node)) {
    for (const n of node) walk(n, visit);
    return;
  }
  if (isValidElement(node)) {
    visit(node);
    for (const v of Object.values(node.props as Record<string, unknown>)) walk(v, visit);
    return;
  }
  if (node && typeof node === "object" && Object.getPrototypeOf(node) === Object.prototype) {
    for (const v of Object.values(node as Record<string, unknown>)) walk(v, visit);
  }
}

function isRelistHost(el: ReactElement): boolean {
  return el.type === ConfirmForm && (el.props as Record<string, unknown>).actionType === "listing_relist";
}

/** Every listing_relist ConfirmForm in the tree: the open form, or the closed host that only holds the last answer. */
function relistForms(tree: unknown): ReactElement<Record<string, unknown>>[] {
  const out: ReactElement<Record<string, unknown>>[] = [];
  walk(tree, (el) => {
    if (isRelistHost(el)) out.push(el as ReactElement<Record<string, unknown>>);
  });
  return out;
}

/** The relist forms an operator can submit (not closed). */
function openRelistForms(tree: unknown): ReactElement<Record<string, unknown>>[] {
  return relistForms(tree).filter((f) => f.props.closed !== true);
}

function containsElement(node: unknown, isTarget: (el: ReactElement) => boolean): boolean {
  let found = false;
  walk(node, (el) => {
    if (isTarget(el)) found = true;
  });
  return found;
}

function typeName(t: unknown): string {
  if (typeof t === "string") return t;
  if (typeof t === "function") return t.name || "anonymous";
  if (typeof t === "symbol") return t.description ?? "symbol";
  return String(t);
}

/**
 * Where React places the target on the client: one step per level, from the page's output down to the target,
 * as `<position>:<type>`. position is `key=<key>` for a keyed element (React matches those by key) and `#<index>`
 * among its siblings otherwise (React matches by index; a null/false child still holds its index). Server
 * components on the way (Panel) are rendered, because the client reconciles their OUTPUT, not the JSX that
 * names them; host elements and fragments contribute props.children. Two renders with the same path keep the same
 * component instance, so its useActionState state survives the refresh (Next: "Client state is preserved for
 * re-rendered components", 07-mutating-data.md:512). null = the target is not in the tree.
 */
async function slotPath(node: unknown, isTarget: (el: ReactElement) => boolean): Promise<string[] | null> {
  const items = Array.isArray(node) ? node : [node];
  for (let i = 0; i < items.length; i++) {
    const item: unknown = items[i];
    if (Array.isArray(item)) {
      const sub = await slotPath(item, isTarget);
      if (sub) return [`#${i}:array`, ...sub];
      continue;
    }
    if (!isValidElement(item)) continue;
    const label = `${item.key != null ? `key=${item.key}` : `#${i}`}:${typeName(item.type)}`;
    if (isTarget(item)) return [label];
    if (!containsElement(item.props, isTarget)) continue;
    const props = item.props as Record<string, unknown>;
    const inner = typeof item.type === "function" ? await (item.type as (p: unknown) => unknown)(props) : props.children;
    const sub = await slotPath(inner, isTarget);
    if (sub) return [label, ...sub];
  }
  return null;
}

function treeText(tree: unknown): string {
  const parts: string[] = [];
  const collect = (n: unknown): void => {
    if (typeof n === "string" || typeof n === "number") parts.push(String(n));
    else if (Array.isArray(n)) n.forEach(collect);
    else if (isValidElement(n)) for (const v of Object.values(n.props as Record<string, unknown>)) collect(v);
  };
  collect(tree);
  return parts.join(" ");
}

function decode(s: string): string {
  return s.replace(/&quot;/g, '"').replace(/&#x27;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}

function textOf(html: string): string {
  return decode(html.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
}

/** Every <input>'s name/value in the rendered markup, decoded — what the browser would post. */
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

async function renderPage(listing: Record<string, unknown>) {
  h.detail = detailWith(listing);
  return ListingPage({ params: Promise.resolve({ id: LISTING_ID }) });
}

/** Posts the page's relist form the way the browser would: its hidden inputs, the new end and a reason. */
async function postRelist(listing: Record<string, unknown>, newEnds: string) {
  const [form] = openRelistForms(await renderPage(listing));
  const html = renderToStaticMarkup(form);
  const fd = new FormData();
  for (const i of inputs(html)) {
    if (i.type === "hidden") fd.set(i.name, i.value ?? "");
  }
  const ends = inputs(html).find((i) => i.type === "datetime-local");
  fd.set(ends?.name ?? "missing", newEnds);
  fd.set("reason", "relist house inventory for the weekend");
  h.calls.length = 0;
  const state = await submitActionForm({}, fd);
  const exec = h.calls.find((c) => c.fn === "execute_action");
  return { state, exec };
}

beforeEach(() => {
  h.calls.length = 0;
  h.role = "platform_admin";
  h.heldState = undefined;
  vi.mocked(revalidatePath).mockClear();
  h.execReply = { ok: true, data: { status: "succeeded", action_id: ACTION_ID, result: { status: "succeeded" } } };
});

// ---------------------------------------------------------------------------

describe("marketplace/[id]: when the relist form renders", () => {
  it("renders for status=active + auction_status=cancelled + a string updated_at", async () => {
    expect(openRelistForms(await renderPage(listingRow()))).toHaveLength(1);
  });

  it.each([
    ["auction active", { auction_status: "active" }],
    ["auction ended", { auction_status: "ended" }],
    ["listing sold", { status: "sold" }],
    ["listing cancelled", { status: "cancelled" }],
    ["status null", { status: null }],
  ])("does not render for %s", async (_label, over) => {
    const tree = await renderPage(listingRow(over));
    expect(openRelistForms(tree)).toHaveLength(0);
    expect(treeText(tree)).toContain("Relist applies only to active listings whose auction is cancelled.");
  });

  it.each([
    ["updated_at null", { updated_at: null }],
    ["updated_at a number", { updated_at: 1729482424123 }],
    ["updated_at absent", { updated_at: undefined }],
    ["ends_at absent", { ends_at: undefined }],
    ["ended_at absent", { ended_at: undefined }],
  ])("does not render for active + cancelled when %s (no exact version to state)", async (_label, over) => {
    const row = listingRow();
    for (const [k, v] of Object.entries(over)) {
      if (v === undefined) delete row[k];
      else row[k] = v;
    }
    const tree = await renderPage(row);
    expect(openRelistForms(tree)).toHaveLength(0);
    expect(treeText(tree)).toContain("ops.listing_detail did not return this listing's version");
  });

  it("a non-founder sees the founder-only note, not the form", async () => {
    h.role = "platform_support";
    const tree = await renderPage(listingRow());
    expect(relistForms(tree)).toHaveLength(0);
    expect(treeText(tree)).toContain("Only a founder can relist.");
  });
});

describe("marketplace/[id]: p_expected carries the five raw values byte-identical", () => {
  it("passes ConfirmForm exactly {status, auction_status, ends_at, ended_at, updated_at} as returned", async () => {
    const [form] = relistForms(await renderPage(listingRow()));
    expect(form.props.expected).toStrictEqual({
      status: "active",
      auction_status: "cancelled",
      ends_at: RAW_ENDS,
      ended_at: RAW_ENDED,
      updated_at: RAW_UPDATED,
    });
  });

  it("keeps JSON null as null (SQL NULL) and keeps the key", async () => {
    const [form] = relistForms(await renderPage(listingRow({ ended_at: null })));
    const expected = form.props.expected as Record<string, unknown>;
    expect("ended_at" in expected).toBe(true);
    expect(expected.ended_at).toBeNull();
    expect(expected.updated_at).toBe(RAW_UPDATED);
  });

  it("serialises the hidden expected field so the raw strings survive byte for byte", async () => {
    const [form] = relistForms(await renderPage(listingRow()));
    const html = renderToStaticMarkup(form);
    const hidden = inputs(html).find((i) => i.name === "expected");
    expect(hidden?.type).toBe("hidden");
    expect(hidden?.value).toContain(`"updated_at":"${RAW_UPDATED}"`);
    expect(hidden?.value).toContain(`"ends_at":"${RAW_ENDS}"`);
    expect(hidden?.value).toContain(`"ended_at":"${RAW_ENDED}"`);
    expect(JSON.parse(hidden?.value ?? "null")).toStrictEqual({
      status: "active",
      auction_status: "cancelled",
      ends_at: RAW_ENDS,
      ended_at: RAW_ENDED,
      updated_at: RAW_UPDATED,
    });
  });

  it("the new-end input is typed so the submitted value carries 'Z'", async () => {
    const [form] = relistForms(await renderPage(listingRow()));
    const ends = inputs(renderToStaticMarkup(form)).find((i) => i.type === "datetime-local");
    expect(ends?.name).toBe("param.new_ends_at:utc");
  });
});

describe("relist form post → ops.execute_action (the whole console pipeline)", () => {
  it("sends p_expected with all five raw values and p_params.new_ends_at with 'Z'", async () => {
    const { exec } = await postRelist(listingRow(), "2026-10-28T03:47");
    expect(exec).toBeDefined();
    expect(exec?.args.p_action_type).toBe("listing_relist");
    expect(exec?.args.p_subject_kind).toBe("listing");
    expect(exec?.args.p_subject_id).toBe(LISTING_ID);
    expect(exec?.args.p_expected).toStrictEqual({
      status: "active",
      auction_status: "cancelled",
      ends_at: RAW_ENDS,
      ended_at: RAW_ENDED,
      updated_at: RAW_UPDATED,
    });
    expect(JSON.stringify(exec?.args.p_expected)).toContain(`"updated_at":"${RAW_UPDATED}"`);
    expect(exec?.args.p_params).toStrictEqual({ new_ends_at: "2026-10-28T03:47Z" });
  });

  it("sends ended_at: null when the listing's ended_at is SQL NULL", async () => {
    const { exec } = await postRelist(listingRow({ ended_at: null }), "2026-10-28T03:47:30");
    const expected = exec?.args.p_expected as Record<string, unknown>;
    expect("ended_at" in expected).toBe(true);
    expect(expected.ended_at).toBeNull();
    expect(exec?.args.p_params).toStrictEqual({ new_ends_at: "2026-10-28T03:47:30Z" });
  });

  it("a missing reason is refused before any call (reason-required precedence)", async () => {
    const [form] = relistForms(await renderPage(listingRow()));
    const fd = new FormData();
    for (const i of inputs(renderToStaticMarkup(form))) if (i.type === "hidden") fd.set(i.name, i.value ?? "");
    fd.set("param.new_ends_at:utc", "2026-10-28T03:47");
    h.calls.length = 0;
    const state = await submitActionForm({}, fd);
    expect(state.invalid).toBe("A reason is required.");
    expect(h.calls).toHaveLength(0);
  });
});

describe("param.<key>:utc coercion (datetime-local is a UTC wall clock)", () => {
  it("parses the typed field name", () => {
    expect(parseParamField("param.new_ends_at:utc")).toEqual({ key: "new_ends_at", type: "utc" });
  });
  it("appends 'Z' to a zone-less wall clock", () => {
    expect(coerceParam("utc", "2026-10-28T03:47")).toEqual({ ok: true, value: "2026-10-28T03:47Z" });
    expect(coerceParam("utc", "2026-10-28T03:47:05")).toEqual({ ok: true, value: "2026-10-28T03:47:05Z" });
    expect(coerceParam("utc", "2026-10-28T03:47:05.123")).toEqual({ ok: true, value: "2026-10-28T03:47:05.123Z" });
  });
  it("keeps a value that already states its zone", () => {
    expect(coerceParam("utc", "2026-10-28T03:47Z")).toEqual({ ok: true, value: "2026-10-28T03:47Z" });
    expect(coerceParam("utc", "2026-10-28T03:47:00-04:00")).toEqual({ ok: true, value: "2026-10-28T03:47:00-04:00" });
  });
  it("refuses anything that is not a date-time; empty stays null", () => {
    for (const bad of ["tomorrow", "2026-10-28", "28/10/2026 03:47", "2026-10-28T3:47", "2026-10-28T03:47+0400x"]) {
      expect(coerceParam("utc", bad).ok).toBe(false);
    }
    expect(coerceParam("utc", "")).toEqual({ ok: true, value: null });
  });
});

// ---------------------------------------------------------------------------
// Answers (ops.execute_action → ops.action_run → 158's dispatch branch)
// ---------------------------------------------------------------------------

function outcome(raw: Record<string, unknown>): ActionOutcome {
  const o = toActionOutcome(raw);
  if (!o) throw new Error("fixture is not an ActionOutcome");
  return o;
}

function renderOutcome(o: ActionOutcome, actionType = "listing_relist"): string {
  return renderToStaticMarkup(createElement(OutcomeText, { outcome: o, actionType }));
}

const LIVE = {
  status: "active",
  auction_status: "cancelled",
  ends_at: "2026-10-22T18:00:00+00:00",
  ended_at: null,
  updated_at: "2026-10-21T19:02:11.654321+00:00",
};

describe("listing_relist answers render as specified", () => {
  it("succeeded: shows the action, admin_relist_listing's answer and the server-locked 'before' row", () => {
    const html = renderOutcome(
      outcome({
        status: "succeeded",
        action_id: ACTION_ID,
        result: {
          status: "succeeded",
          result: {
            listing_id: LISTING_ID,
            event_name: "House listing",
            relisted_by: "0b000000-0000-4000-8000-0000000000aa",
            new_ends_at: "2026-10-28T03:47:00+00:00",
            previous_ends_at: RAW_ENDS,
          },
          before: { status: "active", auction_status: "cancelled", ends_at: RAW_ENDS, ended_at: RAW_ENDED, updated_at: RAW_UPDATED },
        },
        reject_reason: null,
        message: null,
      }),
    );
    const text = textOf(html);
    expect(text).toContain("Recorded.");
    expect(html).toContain(`href="/actions/${ACTION_ID}"`);
    expect(text).toContain("new_ends_at 2026-10-28T03:47:00+00:00");
    expect(text).toContain(`previous_ends_at ${RAW_ENDS}`);
    expect(text).toContain(`updated_at ${RAW_UPDATED}`);
    expect(text).toContain(`ended_at ${RAW_ENDED}`);
    expect(text).toContain("auction_status cancelled");
  });

  it("succeeded from today's pre-158 server (no 'before') still renders", () => {
    const text = textOf(
      renderOutcome(
        outcome({
          status: "succeeded",
          action_id: ACTION_ID,
          result: { status: "succeeded", result: { listing_id: LISTING_ID, new_ends_at: "2026-10-28T03:47:00+00:00", previous_ends_at: RAW_ENDS } },
        }),
      ),
    );
    expect(text).toContain("Recorded.");
    expect(text).toContain("new_ends_at 2026-10-28T03:47:00+00:00");
  });

  it("rejected/stale_state: the reload prompt plus the live five fields from result.current", () => {
    const html = renderOutcome(
      outcome({
        status: "rejected",
        action_id: ACTION_ID,
        reject_reason: "stale_state",
        message: STALE_COPY,
        result: { status: "rejected", reject_reason: "stale_state", message: STALE_COPY, current: LIVE },
      }),
    );
    const text = textOf(html);
    expect(text).toContain(STALE_COPY);
    expect(text).toContain("Reload now");
    expect(html).toContain('type="button"');
    expect(text).toContain(`updated_at ${LIVE.updated_at}`);
    expect(text).toContain(`ends_at ${LIVE.ends_at}`);
    expect(text).toContain("ended_at null");
    expect(text).toContain("status active");
    expect(text).toContain("auction_status cancelled");
  });

  it.each([
    "Listing not found.",
    "Listing has payment/transfer/bid history and cannot be relisted.",
    "Only admin-owned inventory can be relisted; a real seller's cancellation stands.",
    "Listing is not in the cancelled resting state (status=active, auction_status=active).",
    "New end time must be in the future.",
  ])("rejected/precondition keeps the domain message byte for byte: %s", (message) => {
    const html = renderOutcome(
      outcome({
        status: "rejected",
        action_id: ACTION_ID,
        reject_reason: "precondition",
        message,
        result: { status: "rejected", reject_reason: "precondition", message },
      }),
    );
    expect(textOf(html)).toContain("Rejected: precondition");
    const body = /<div class="mt-1 text-muted">([\s\S]*?)<\/div>/.exec(html);
    expect(body).not.toBeNull();
    expect(decode(body?.[1] ?? "")).toBe(message);
  });

  it("idempotent_replay is unchanged", () => {
    const text = textOf(renderOutcome(outcome({ status: "idempotent_replay", action_id: ACTION_ID, state: "succeeded", result: {} })));
    expect(text).toContain("Already submitted — no second action was created.");
    expect(text).toContain("succeeded");
  });

  it("other actions' stale_state keep the generic reload copy", () => {
    const text = textOf(
      renderOutcome(outcome({ status: "rejected", reject_reason: "stale_state", message: "report is actioned, you saw open", result: {} }), "report_resolve"),
    );
    expect(text).toContain("This record changed since you loaded it — reload.");
    expect(text).toContain("report is actioned, you saw open");
    expect(text).not.toContain(STALE_COPY);
  });
});

describe("raised errors: out-of-date console vs 42501 / reason / pause precedence", () => {
  it("P0001 'invalid_input: listing_relist requires expected.updated_at …' is an out-of-date console", () => {
    const f = mapOpsError("execute_action", { code: "P0001", message: OUTDATED_RAISE });
    expect(f).toMatchObject({ ok: false, kind: "error", outdated: true, code: "P0001", message: OUTDATED_RAISE });
    const text = textOf(renderToStaticMarkup(createElement(OpsFailureAlert, { failure: f, fn: "execute_action" })));
    expect(text).toContain("This console is out of date — reload the page");
    expect(text).not.toContain("Request failed");
  });

  it("reaches the form state through submitActionForm", async () => {
    h.execReply = mapOpsError("execute_action", { code: "P0001", message: OUTDATED_RAISE });
    const [form] = relistForms(await renderPage(listingRow()));
    const fd = new FormData();
    for (const i of inputs(renderToStaticMarkup(form))) if (i.type === "hidden") fd.set(i.name, i.value ?? "");
    fd.set("param.new_ends_at:utc", "2026-10-28T03:47");
    fd.set("reason", "relist");
    const state = await submitActionForm({}, fd);
    expect(state.failure).toMatchObject({ kind: "error", outdated: true });
  });

  it("42501 / insufficient_privilege stays denied even with the same text", () => {
    expect(mapOpsError("execute_action", { code: "42501", message: OUTDATED_RAISE })).toEqual({ ok: false, kind: "denied" });
    expect(mapOpsError("execute_action", { code: "42501", message: "insufficient_privilege: platform_support may not perform listing_relist" })).toEqual({
      ok: false,
      kind: "denied",
    });
  });

  it("console_actions_paused stays paused", () => {
    expect(mapOpsError("execute_action", { code: "P0001", message: "precondition_failed: console_actions_paused" })).toMatchObject({ kind: "paused" });
  });

  it("the server's reason-required raise stays a generic error with its message", () => {
    const f = mapOpsError("execute_action", { code: "P0001", message: "invalid_input: a reason is required for listing_relist" });
    expect(f).toEqual({ ok: false, kind: "error", code: "P0001", message: "invalid_input: a reason is required for listing_relist" });
  });

  it("only that exact P0001 prefix is 'out of date'", () => {
    expect(mapOpsError("execute_action", { code: "P0001", message: "invalid_input: unknown action_type listing_relist" })).not.toMatchObject({ outdated: true });
    expect(mapOpsError("execute_action", { code: "XX000", message: OUTDATED_RAISE })).not.toMatchObject({ outdated: true });
  });
});

// ---------------------------------------------------------------------------
// The answer outlives the refresh that carries it. submitActionForm calls revalidatePath after every outcome, so
// the action's response re-renders this page in the same roundtrip (Next 16: server-actions.md:34-39, :150).
// After a relist (auction active) or a lost race the listing is no longer relistable; the refreshed page must
// keep the SAME ConfirmForm instance in the same slot (closed) or useActionState's answer is thrown away.
// ---------------------------------------------------------------------------

const PATH = `/marketplace/${LISTING_ID}`;
const NEW_ENDS = "2026-10-28T03:47:00+00:00";
const RELISTED_UPDATED = "2026-10-21T22:05:31.000987+00:00";
const OTHER_ENDS = "2026-10-25T20:00:00+00:00";
const OTHER_UPDATED = "2026-10-21T22:04:59.314159+00:00";

const BEFORE_LOCKED = { status: "active", auction_status: "cancelled", ends_at: RAW_ENDS, ended_at: RAW_ENDED, updated_at: RAW_UPDATED };

const SUCCEEDED_REPLY = {
  ok: true,
  data: {
    status: "succeeded",
    action_id: ACTION_ID,
    result: {
      status: "succeeded",
      result: { listing_id: LISTING_ID, event_name: "House listing", new_ends_at: NEW_ENDS, previous_ends_at: RAW_ENDS },
      before: BEFORE_LOCKED,
    },
  },
};

/** Another operator relisted first: 158 compares the stated version under the row lock and answers stale_state. */
const OTHER_CURRENT = { status: "active", auction_status: "active", ends_at: OTHER_ENDS, ended_at: null, updated_at: OTHER_UPDATED };
const STALE_REPLY = {
  ok: true,
  data: {
    status: "rejected",
    action_id: ACTION_ID,
    reject_reason: "stale_state",
    message: STALE_COPY,
    result: { status: "rejected", reject_reason: "stale_state", message: STALE_COPY, current: OTHER_CURRENT },
  },
};

describe("the relist answer outlives the page refresh that carries it (revalidatePath)", () => {
  /** Load the relistable page, post its form, then re-render the page from the row the refresh reads. */
  async function submitThenRefresh(reply: unknown, afterRow: Record<string, unknown>) {
    const beforeTree = await renderPage(listingRow());
    const before = await slotPath(beforeTree, isRelistHost);
    const [beforeHost] = relistForms(beforeTree);
    h.execReply = reply;
    const { state } = await postRelist(listingRow(), "2026-10-28T03:47");
    const afterTree = await renderPage(afterRow);
    const after = await slotPath(afterTree, isRelistHost);
    const hosts = relistForms(afterTree);
    return { before, beforeHost, after, state, afterTree, hosts };
  }

  it("succeeded → refreshed row is auction active: same ConfirmForm slot and key, closed, and 'Recorded.' + result.result + result.before stay visible", async () => {
    const { before, after, state, afterTree, hosts } = await submitThenRefresh(SUCCEEDED_REPLY, listingRow({ auction_status: "active", ends_at: NEW_ENDS, ended_at: null, updated_at: RELISTED_UPDATED }));
    expect(state.outcome?.status).toBe("succeeded");
    expect(revalidatePath).toHaveBeenCalledWith(PATH);

    expect(before).not.toBeNull();
    expect(after).toEqual(before);
    expect(before?.at(-1)).toBe("key=listing_relist:ConfirmForm");
    expect(hosts).toHaveLength(1);
    expect(hosts[0].props.closed).toBe(true);
    expect(openRelistForms(afterTree)).toHaveLength(0);
    expect(treeText(afterTree)).toContain("Relist applies only to active listings whose auction is cancelled.");

    h.heldState = state;
    const html = renderToStaticMarkup(hosts[0]);
    const text = textOf(html);
    expect(text).toContain("Recorded.");
    expect(html).toContain(`href="/actions/${ACTION_ID}"`);
    expect(text).toContain(`new_ends_at ${NEW_ENDS}`);
    expect(text).toContain(`previous_ends_at ${RAW_ENDS}`);
    expect(text).toContain("Listing as the server locked it (before)");
    expect(text).toContain(`updated_at ${RAW_UPDATED}`);
    expect(text).toContain(`ended_at ${RAW_ENDED}`);
    // Nothing left to submit: no form, no inputs, no button.
    expect(html).not.toContain("<form");
    expect(inputs(html)).toHaveLength(0);
    expect(html).not.toContain('type="submit"');
  });

  it("stale_state (another operator relisted first) → refreshed row is auction active: same slot, closed, the stale copy + result.current + Reload now stay visible", async () => {
    const { before, after, state, hosts } = await submitThenRefresh(STALE_REPLY, listingRow(OTHER_CURRENT));
    expect(state.outcome).toMatchObject({ status: "rejected", reason: "stale_state" });
    expect(revalidatePath).toHaveBeenCalledWith(PATH);

    expect(before).not.toBeNull();
    expect(after).toEqual(before);
    expect(hosts).toHaveLength(1);
    expect(hosts[0].props.closed).toBe(true);

    h.heldState = state;
    const html = renderToStaticMarkup(hosts[0]);
    const text = textOf(html);
    expect(text).toContain(STALE_COPY);
    expect(text).toContain("Reload now");
    expect(text).toContain("The listing now (server row)");
    expect(text).toContain(`updated_at ${OTHER_UPDATED}`);
    expect(text).toContain(`ends_at ${OTHER_ENDS}`);
    expect(text).toContain("auction_status active");
    expect(text).toContain("ended_at null");
    expect(html).not.toContain("<form");
    expect(inputs(html)).toHaveLength(0);
  });

  it("stale_state with the listing still relistable (a newer version): same slot, the form re-opens with the new version and a new key, and the answer stays under it", async () => {
    const NEWER = "2026-10-21T22:06:00.271828+00:00";
    const { before, beforeHost, after, state, hosts } = await submitThenRefresh(
      { ok: true, data: { ...STALE_REPLY.data, result: { ...STALE_REPLY.data.result, current: { ...BEFORE_LOCKED, updated_at: NEWER } } } },
      listingRow({ updated_at: NEWER }),
    );
    expect(after).toEqual(before);
    expect(hosts).toHaveLength(1);
    expect(hosts[0].props.closed).not.toBe(true);
    expect((hosts[0].props.expected as Record<string, unknown>).updated_at).toBe(NEWER);
    expect(hosts[0].props.idempotencyKey).not.toBe(beforeHost.props.idempotencyKey);

    h.heldState = state;
    const html = renderToStaticMarkup(hosts[0]);
    expect(textOf(html)).toContain(STALE_COPY);
    expect(inputs(html).find((i) => i.type === "datetime-local")?.name).toBe("param.new_ends_at:utc");
    expect(JSON.parse(inputs(html).find((i) => i.name === "expected")?.value ?? "null")).toMatchObject({ updated_at: NEWER });
  });

  it("a fresh load of a non-relistable listing mounts the closed host, which renders nothing until it holds an answer", async () => {
    const tree = await renderPage(listingRow({ auction_status: "active" }));
    const hosts = relistForms(tree);
    expect(hosts).toHaveLength(1);
    expect(hosts[0].props.closed).toBe(true);
    expect(renderToStaticMarkup(hosts[0])).toBe("");
  });

  it("the version-missing note keeps the same slot too (active + cancelled, no updated_at)", async () => {
    const before = await slotPath(await renderPage(listingRow()), isRelistHost);
    const row = listingRow();
    delete row.updated_at;
    const tree = await renderPage(row);
    expect(await slotPath(tree, isRelistHost)).toEqual(before);
    expect(relistForms(tree)[0].props.closed).toBe(true);
    expect(treeText(tree)).toContain("ops.listing_detail did not return this listing's version");
  });

  it("a closed host keeps a server failure, not a client-side validation note", async () => {
    const [host] = relistForms(await renderPage(listingRow({ auction_status: "active" })));
    h.heldState = { submitted: true, failure: mapOpsError("execute_action", { code: "P0001", message: OUTDATED_RAISE }) };
    expect(textOf(renderToStaticMarkup(host))).toContain("This console is out of date — reload the page");
    h.heldState = { submitted: true, invalid: "A reason is required." };
    expect(renderToStaticMarkup(host)).toBe("");
  });

  it("a non-founder gets no relist host on either side of the refresh", async () => {
    h.role = "platform_support";
    expect(relistForms(await renderPage(listingRow()))).toHaveLength(0);
    expect(relistForms(await renderPage(listingRow({ auction_status: "active" })))).toHaveLength(0);
  });
});
