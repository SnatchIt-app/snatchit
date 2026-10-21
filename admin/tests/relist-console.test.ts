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
}));

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

function relistForms(tree: unknown): ReactElement<Record<string, unknown>>[] {
  const out: ReactElement<Record<string, unknown>>[] = [];
  walk(tree, (el) => {
    if (el.type === ConfirmForm && (el.props as Record<string, unknown>).actionType === "listing_relist") out.push(el as ReactElement<Record<string, unknown>>);
  });
  return out;
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

beforeEach(() => {
  h.calls.length = 0;
  h.role = "platform_admin";
  h.execReply = { ok: true, data: { status: "succeeded", action_id: ACTION_ID, result: { status: "succeeded" } } };
});

// ---------------------------------------------------------------------------

describe("marketplace/[id]: when the relist form renders", () => {
  it("renders for status=active + auction_status=cancelled + a string updated_at", async () => {
    expect(relistForms(await renderPage(listingRow()))).toHaveLength(1);
  });

  it.each([
    ["auction active", { auction_status: "active" }],
    ["auction ended", { auction_status: "ended" }],
    ["listing sold", { status: "sold" }],
    ["listing cancelled", { status: "cancelled" }],
    ["status null", { status: null }],
  ])("does not render for %s", async (_label, over) => {
    const tree = await renderPage(listingRow(over));
    expect(relistForms(tree)).toHaveLength(0);
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
    expect(relistForms(tree)).toHaveLength(0);
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
  async function postRelist(listing: Record<string, unknown>, newEnds: string) {
    const [form] = relistForms(await renderPage(listing));
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
