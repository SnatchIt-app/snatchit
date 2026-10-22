import { createElement, isValidElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * listing_relist with migration 158 (PR #125 head f5abd471), ported to v2.
 *
 * The console states the listing version the operator saw — status,
 * auction_status, ends_at, ended_at and updated_at copied from the raw
 * ops.listing_detail(id).listing record, byte for byte — and renders 158's
 * answers. The real page, ConfirmForm, submitActionForm → executeAction →
 * callOps → mapOpsError path runs; only the Supabase client and the session
 * are faked. Nothing here imports src/lib/relist.ts, so this file loads on the
 * parent commit and its failures there are the RED count.
 */
const h = vi.hoisted(() => ({
  calls: [] as { fn: string; args: Record<string, unknown> }[],
  detail: null as unknown,
  exec: { data: null as unknown, error: null as unknown },
  role: "platform_admin" as string,
}));

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
      rpc: async (fn: string, args: Record<string, unknown>) => {
        h.calls.push({ fn, args });
        if (fn === "listing_detail") return { data: h.detail, error: null };
        return h.exec;
      },
    }),
  }),
}));
vi.mock("@/lib/auth/session", () => ({
  requireOperator: vi.fn(async () => ({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: h.role, whoami: { role: h.role } })),
}));

import ListingPage from "@/app/(console)/marketplace/[id]/page";
import { ConfirmForm, OutcomeText } from "@/components/ui/ConfirmForm";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { submitActionForm } from "@/lib/actions";
import { mapOpsError } from "@/lib/ops-errors";
import { coerceParam, parseParamField } from "@/lib/form-params";
import { toActionOutcome, type ActionOutcome } from "@/lib/types";

const LISTING_ID = "5a150000-0000-4000-8000-000000000158";
const ACTION_ID = "a1580000-0000-4000-8000-000000000001";

// Raw to_jsonb(timestamptz) strings as ops.listing_detail returns them: an offset and up to six fractional digits,
// trailing zeros trimmed. A Date round trip would turn RAW_UPDATED into "2026-10-21T03:47:04.123Z" (milliseconds,
// UTC) and 158 would answer stale_state every time.
const RAW_UPDATED = "2026-10-21T03:47:04.123456+00:00";
const RAW_ENDS = "2026-10-20T23:59:00.000001-04:00";
const RAW_ENDED = "2026-10-21T03:47:04.5+00:00";
const FIVE = { status: "active", auction_status: "cancelled", ends_at: RAW_ENDS, ended_at: RAW_ENDED, updated_at: RAW_UPDATED };

const STALE_COPY = "listing changed since you loaded it — reload and try again";
// 158's raise, byte for byte (m158 line 225, '' unescaped).
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
  h.exec = { data: { status: "succeeded", action_id: ACTION_ID, result: { status: "succeeded" } }, error: null };
});

// ---------------------------------------------------------------------------

describe("marketplace/[id]: when the relist form renders", () => {
  it("renders for status=active + auction_status=cancelled + a string updated_at", async () => {
    expect(relistForms(await renderPage(listingRow()))).toHaveLength(1);
  });

  it.each([
    ["auction active (the state right after a relist)", { auction_status: "active" }],
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
    ["ends_at a number", { ends_at: 0 }],
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
    expect(form.props.expected).toStrictEqual(FIVE);
  });

  it("keeps JSON null as null (SQL NULL) and keeps the key", async () => {
    const [form] = relistForms(await renderPage(listingRow({ ended_at: null })));
    const expected = form.props.expected as Record<string, unknown>;
    expect("ended_at" in expected).toBe(true);
    expect(expected.ended_at).toBeNull();
    expect(expected.updated_at).toBe(RAW_UPDATED);
  });

  it("serialises the hidden expected field so the raw strings survive byte for byte (never via Date)", async () => {
    const [form] = relistForms(await renderPage(listingRow()));
    const html = renderToStaticMarkup(form);
    const hidden = inputs(html).find((i) => i.name === "expected");
    expect(hidden?.type).toBe("hidden");
    expect(hidden?.value).toContain(`"updated_at":"${RAW_UPDATED}"`);
    expect(hidden?.value).toContain(`"ends_at":"${RAW_ENDS}"`);
    expect(hidden?.value).toContain(`"ended_at":"${RAW_ENDED}"`);
    expect(JSON.parse(hidden?.value ?? "null")).toStrictEqual(FIVE);
    expect(hidden?.value).not.toContain(new Date(RAW_UPDATED).toISOString());
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
    expect(exec?.args.p_expected).toStrictEqual(FIVE);
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

  it("a new end that is not a date-time is refused before any call", async () => {
    const [form] = relistForms(await renderPage(listingRow()));
    const fd = new FormData();
    for (const i of inputs(renderToStaticMarkup(form))) if (i.type === "hidden") fd.set(i.name, i.value ?? "");
    fd.set("param.new_ends_at:utc", "next friday");
    fd.set("reason", "relist");
    h.calls.length = 0;
    const state = await submitActionForm({}, fd);
    expect(state.invalid).toMatch(/^new_ends_at: /);
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
      expect(coerceParam("utc", bad).ok, bad).toBe(false);
    }
    expect(coerceParam("utc", "")).toEqual({ ok: true, value: null });
  });
});

// ---------------------------------------------------------------------------
// Answers (ops.execute_action → ops.action_run → 158's dispatch branch). action_run returns
// {status, action_id, result: <dispatch answer>, reject_reason, message} (115:868-869).
// ---------------------------------------------------------------------------

function outcome(raw: Record<string, unknown>): ActionOutcome {
  const o = toActionOutcome(raw);
  if (!o) throw new Error("fixture is not an ActionOutcome");
  return o;
}

function renderOutcome(o: ActionOutcome, actionType = "listing_relist"): string {
  return renderToStaticMarkup(createElement(OutcomeText, { outcome: o, actionType } as Parameters<typeof OutcomeText>[0]));
}

const LIVE = {
  status: "active",
  auction_status: "active",
  ends_at: "2026-10-22T18:00:00+00:00",
  ended_at: null,
  updated_at: "2026-10-21T19:02:11.654321+00:00",
};

const SUCCEEDED = {
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
    before: FIVE,
  },
  reject_reason: null,
  message: null,
};

const STALE = {
  status: "rejected",
  action_id: ACTION_ID,
  reject_reason: "stale_state",
  message: STALE_COPY,
  result: { status: "rejected", reject_reason: "stale_state", message: STALE_COPY, current: LIVE },
};

describe("listing_relist answers render as specified", () => {
  it("succeeded: the action link, admin_relist_listing's answer and the server-locked 'before' row, raw", () => {
    const html = renderOutcome(outcome(SUCCEEDED));
    const text = textOf(html);
    expect(text).toContain("Recorded.");
    expect(html).toContain(`href="/actions/${ACTION_ID}"`);
    expect(text).toContain("new_ends_at 2026-10-28T03:47:00+00:00");
    expect(text).toContain(`previous_ends_at ${RAW_ENDS}`);
    expect(text).toContain(`updated_at ${RAW_UPDATED}`);
    expect(text).toContain(`ended_at ${RAW_ENDED}`);
    expect(text).toContain(`ends_at ${RAW_ENDS}`);
    expect(text).toContain("status active");
    expect(text).toContain("auction_status cancelled");
    expect(html).not.toMatch(/text-\[\d+(\.\d+)?px\]/);
  });

  it("succeeded from today's pre-158 server (no 'before') still renders the relist answer", () => {
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
    expect(text).not.toContain("before");
  });

  it("rejected/stale_state: 158's copy, a reload prompt and the live five fields from result.current", () => {
    const html = renderOutcome(outcome(STALE));
    const text = textOf(html);
    expect(text).toContain(STALE_COPY);
    expect(text).toContain("Reload now");
    expect(html).toMatch(/<button type="button"[^>]*>Reload now<\/button>/);
    expect(text).toContain(`updated_at ${LIVE.updated_at}`);
    expect(text).toContain(`ends_at ${LIVE.ends_at}`);
    expect(text).toContain("ended_at null");
    expect(text).toContain("status active");
    expect(text).toContain("auction_status active");
    // 158's copy is the title, once; not the generic "This record changed" line
    expect(html).toContain(`<p class="font-medium text-ink"><span class="sr-only">Stale: </span>${STALE_COPY}</p>`);
    expect(text.split(STALE_COPY)).toHaveLength(2);
    expect(text).not.toContain("This record changed since you loaded it");
    expect(html).not.toMatch(/text-\[\d+(\.\d+)?px\]/);
  });

  it.each([
    "Listing not found.",
    "Listing has payment/transfer/bid history and cannot be relisted.",
    "Only admin-owned inventory can be relisted; a real seller's cancellation stands.",
    "Listing is not in the cancelled resting state (status=active, auction_status=active).",
    "Listing carries a winner or reservation and cannot be relisted.",
    "New end time must be in the future.",
    "Relisting requires a known admin actor.",
  ])("rejected/precondition keeps the domain message byte for byte: %s", (message) => {
    const html = renderOutcome(
      outcome({ status: "rejected", action_id: ACTION_ID, reject_reason: "precondition", message, result: { status: "rejected", reject_reason: "precondition", message } }),
    );
    expect(textOf(html)).toContain("Rejected: precondition");
    const body = /<div class="mt-0\.5 text-\[0\.8125rem\] text-muted">([\s\S]*?)<\/div>/.exec(html);
    expect(body).not.toBeNull();
    expect(decode(body?.[1] ?? "")).toBe(message);
    // the same answer for any other action renders identically: nothing relist-specific is added
    expect(html).toBe(renderOutcome(outcome({ status: "rejected", action_id: ACTION_ID, reject_reason: "precondition", message, result: {} }), "report_resolve"));
  });

  it("idempotent_replay is unchanged", () => {
    const o = outcome({ status: "idempotent_replay", action_id: ACTION_ID, state: "succeeded", result: SUCCEEDED.result });
    const html = renderOutcome(o);
    expect(textOf(html)).toContain("Already submitted — no second action was created.");
    expect(textOf(html)).toContain("Succeeded");
    expect(html).toBe(renderOutcome(o, "report_resolve"));
  });

  it("other actions' stale_state keep the generic reload copy (control)", () => {
    const text = textOf(renderOutcome(outcome({ status: "rejected", reject_reason: "stale_state", message: "report is actioned, you saw open", result: {} }), "report_resolve"));
    expect(text).toContain("This record changed since you loaded it — reload.");
    expect(text).toContain("report is actioned, you saw open");
    expect(text).not.toContain(STALE_COPY);
  });

  it("other actions' success is unchanged: no relist fields even when result carries them (control)", () => {
    const html = renderOutcome(outcome(SUCCEEDED), "report_resolve");
    expect(textOf(html)).toContain("Recorded.");
    expect(textOf(html)).not.toContain("new_ends_at");
    expect(textOf(html)).not.toContain(RAW_UPDATED);
  });
});

describe("raised errors: out-of-date console vs 42501 / step-up / reason / pause precedence", () => {
  async function postAndRender(error: { code: string; message: string }) {
    h.exec = { data: null, error };
    const [form] = relistForms(await renderPage(listingRow()));
    const fd = new FormData();
    for (const i of inputs(renderToStaticMarkup(form))) if (i.type === "hidden") fd.set(i.name, i.value ?? "");
    fd.set("param.new_ends_at:utc", "2026-10-28T03:47");
    fd.set("reason", "relist");
    const state = await submitActionForm({}, fd);
    const html = state.failure ? renderToStaticMarkup(createElement(OpsFailureAlert, { failure: state.failure, fn: "execute_action" })) : "";
    return { state, text: textOf(html) };
  }

  it("P0001 'invalid_input: listing_relist requires expected.updated_at …' reads as an out-of-date console, keeping the DB's words", async () => {
    const { state, text } = await postAndRender({ code: "P0001", message: OUTDATED_RAISE });
    expect(state.failure).toMatchObject({ ok: false, kind: "error", outdated: true, code: "P0001", message: OUTDATED_RAISE });
    expect(text).toContain("This console is out of date — reload the page, then try again.");
    expect(text).toContain("Nothing was changed.");
    expect(text).toContain(OUTDATED_RAISE);
    expect(text).toContain("P0001");
    expect(text).not.toContain("Request failed");
  });

  it("42501 / insufficient_privilege stays denied, even with the same text", async () => {
    expect((await postAndRender({ code: "42501", message: OUTDATED_RAISE })).state.failure).toEqual({ ok: false, kind: "denied" });
    expect(mapOpsError("execute_action", { code: "42501", message: "insufficient_privilege: platform_support may not perform listing_relist" })).toEqual({ ok: false, kind: "denied" });
    expect(mapOpsError("execute_action", { code: "P0001", message: `insufficient_privilege: ${OUTDATED_RAISE}` })).toEqual({ ok: false, kind: "denied" });
  });

  it("step-up stays step-up", () => {
    expect(mapOpsError("execute_action", { code: "P0001", message: "step_up_required: aal2" })).toEqual({ ok: false, kind: "mfa" });
  });

  it("console_actions_paused stays paused", async () => {
    const { state, text } = await postAndRender({ code: "P0001", message: "precondition_failed: console_actions_paused" });
    expect(state.failure).toMatchObject({ kind: "paused" });
    expect(text).toContain("Actions are paused by a founder");
    expect(text).not.toContain("out of date");
  });

  it("the server's reason-required raise stays a generic error with its message", async () => {
    const { state, text } = await postAndRender({ code: "P0001", message: "invalid_input: a reason is required for listing_relist" });
    expect(state.failure).toEqual({ ok: false, kind: "error", code: "P0001", message: "invalid_input: a reason is required for listing_relist" });
    expect(text).toContain("Request failed");
    expect(text).not.toContain("out of date");
  });

  it("the earlier classes win over 'out of date' when a raise carries both markers (mapping order pinned)", () => {
    expect(mapOpsError("execute_action", { code: "P0001", message: `${OUTDATED_RAISE} insufficient_privilege` })).toEqual({ ok: false, kind: "denied" });
    expect(mapOpsError("execute_action", { code: "P0001", message: `${OUTDATED_RAISE} step_up_required` })).toEqual({ ok: false, kind: "mfa" });
    expect(mapOpsError("execute_action", { code: "P0001", message: `${OUTDATED_RAISE} console_actions_paused` })).toMatchObject({ kind: "paused" });
  });

  it("only that exact P0001 prefix is 'out of date'", () => {
    expect(mapOpsError("execute_action", { code: "P0001", message: "invalid_input: unknown action_type listing_relist" })).not.toHaveProperty("outdated");
    expect(mapOpsError("execute_action", { code: "XX000", message: OUTDATED_RAISE })).not.toHaveProperty("outdated");
    expect(mapOpsError("execute_action", { code: "P0001", message: ` ${OUTDATED_RAISE}` })).not.toHaveProperty("outdated");
  });
});
