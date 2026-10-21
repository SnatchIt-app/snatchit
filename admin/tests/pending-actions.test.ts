import { describe, expect, it, vi } from "vitest";
import { decidePendingGuard, loadMoneyGuards, pendingActionFilters, UNSETTLED_STATES, type OpsRead } from "@/lib/pending-actions";
import type { OpsAction, OrderDetail } from "@/lib/types";

/** F1 — the decision behind the order page's money-form guard, with the reads mocked. */
const PAY = "9a900000-0000-4000-8000-0000000000e1";
const TR = "7a000000-0000-4000-8000-0000000000e1";

const act = (over: Partial<OpsAction>): OpsAction => ({
  id: "aaaaaaaa-0000-4000-8000-0000000000e1",
  action_type: "payout_release",
  subject_kind: "transfer",
  subject_id: TR,
  state: "awaiting_approval",
  requested_at: "2026-09-01T09:00:00Z",
  ...over,
});
const settled = Array.from({ length: 50 }, (_, i) => act({ id: `c-${i}`, action_type: "listing_relist", subject_kind: "listing", subject_id: "l", state: "succeeded" }));
const detail = (actions: OpsAction[] = settled, refundActions: OpsAction[] = []) =>
  ({ payment: { id: PAY, status: "succeeded" }, transfer: { id: TR, status: "seller_sent" }, actions, refund: { refund_actions: refundActions } }) as unknown as OrderDetail;
const ok = (items: unknown[]) => ({ ok: true as const, data: { items, next_cursor: null } });

describe("decidePendingGuard", () => {
  it("capped list without the action + list_actions with it → pending, newest linked", () => {
    const g = decidePendingGuard({ type: "payout_release", subjectId: TR, known: settled, listed: ok([act({})]) });
    expect(g).toEqual({ kind: "pending", action: expect.objectContaining({ id: "aaaaaaaa-0000-4000-8000-0000000000e1" }) });
  });
  it("read error → unverified (the form must be hidden), carrying the failure", () => {
    const failure = { ok: false as const, kind: "error" as const, message: "timeout" };
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: settled, listed: failure })).toEqual({ kind: "unverified", failure });
    expect(decidePendingGuard({ type: "refund_execute", subjectId: PAY, known: [], listed: { ok: false, kind: "denied" } }).kind).toBe("unverified");
  });
  it("an unrecognised payload is not a clear answer", () => {
    for (const data of [null, [], "x", { rows: [] }, { items: "nope" }]) {
      expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: { ok: true, data } }), JSON.stringify(data)).toEqual({ kind: "unverified", failure: null });
    }
  });
  it("a pending row already held still blocks when the read fails", () => {
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [act({ state: "processing" })], listed: { ok: false, kind: "error", message: "x" } }).kind).toBe("pending");
  });
  it("clear only when list_actions answered an empty page", () => {
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: settled, listed: ok([]) })).toEqual({ kind: "clear" });
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: { ok: true, data: { items: [], next_cursor: null, count_hint: 0 } } })).toEqual({ kind: "clear" });
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: { ok: true, data: { items: [], next_cursor: null, count_hint: null } } })).toEqual({ kind: "clear" });
    // Rows the page already held that do not match type/subject/state never block on their own.
    const strays = [act({ state: "succeeded" }), act({ state: "rejected" }), act({ subject_id: "other" }), act({ action_type: "refund_execute" })];
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: strays, listed: ok([]) })).toEqual({ kind: "clear" });
  });
});

/**
 * list_actions has already filtered by action_type, subject_kind, subject_id
 * and the unsettled states (116:1428-1433), so every row it returns is a
 * pending duplicate by construction. The client's own exact-string match is a
 * second opinion: when it cannot match a returned row, the row still blocks.
 */
describe("decidePendingGuard — any row list_actions returns blocks (reviewer probes)", () => {
  it("probe 1: subject_id in another case → pending, not clear", () => {
    const row = { action_type: "payout_release", subject_kind: "transfer", subject_id: TR.toUpperCase(), state: "requested" };
    const g = decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: { ok: true, data: { items: [row], count_hint: 1 } } });
    expect(g).toEqual({ kind: "pending", action: expect.objectContaining({ subject_id: TR.toUpperCase(), state: "requested" }) });
  });
  it("probe 2: a reshaped row ({subject:{kind,id}}) → pending, not clear", () => {
    const row = { id: "dddddddd-0000-4000-8000-0000000000e1", action_type: "payout_release", subject: { kind: "transfer", id: TR }, state: "requested" };
    const g = decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: { ok: true, data: { items: [row], count_hint: 1 } } });
    expect(g).toEqual({ kind: "pending", action: expect.objectContaining({ id: "dddddddd-0000-4000-8000-0000000000e1" }) });
  });
  it("rows the client reads as settled, other-subject or other-type still block when the server returned them", () => {
    for (const row of [act({ state: "succeeded" }), act({ state: undefined }), act({ subject_id: "other" }), act({ action_type: "refund_execute" })]) {
      expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: ok([row]) }).kind, JSON.stringify(row)).toBe("pending");
    }
  });
  it("an exact match is still preferred over the first unmatched row", () => {
    const g = decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: ok([act({ id: "x-upper", subject_id: TR.toUpperCase() }), act({ id: "x-exact" })]) });
    expect(g).toEqual({ kind: "pending", action: expect.objectContaining({ id: "x-exact" }) });
  });
  it("count_hint > 0 with no usable row → not clear (unverified: nothing to link)", () => {
    for (const data of [{ items: [], count_hint: 1 }, { items: [], count_hint: "2" }, { items: ["opaque"], count_hint: null }, { items: [null, 7] }]) {
      expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: { ok: true, data } }), JSON.stringify(data)).toEqual({ kind: "unverified", failure: null });
    }
  });
});

describe("loadMoneyGuards", () => {
  it("asks list_actions once per offered form, with the agreed filter shape", async () => {
    const read = vi.fn<OpsRead>(async () => ok([]));
    const g = await loadMoneyGuards(read, detail(), { release: true, refund: true });
    expect(g).toEqual({ release: { kind: "clear" }, refund: { kind: "clear" } });
    expect(read).toHaveBeenCalledTimes(2);
    expect(read).toHaveBeenCalledWith("list_actions", { p_filters: { action_type: ["payout_release"], subject_kind: "transfer", subject_id: TR, state: [...UNSETTLED_STATES] }, p_cursor: null, p_limit: 5 });
    expect(read).toHaveBeenCalledWith("list_actions", { p_filters: { action_type: ["refund_execute"], subject_kind: "payment", subject_id: PAY, state: [...UNSETTLED_STATES] }, p_cursor: null, p_limit: 5 });
    expect(UNSETTLED_STATES).toEqual(["requested", "awaiting_approval", "processing", "succeeded_at_provider", "unknown"]);
    expect(pendingActionFilters("refund_execute", PAY).subject_kind).toBe("payment");
  });
  it("capped list misses the old release, list_actions has it → release pending, refund clear", async () => {
    const read: OpsRead = async (_fn, args) => ((args.p_filters as { action_type: string[] }).action_type[0] === "payout_release" ? ok([act({})]) : ok([]));
    const g = await loadMoneyGuards(read, detail(), { release: true, refund: true });
    expect(g.release?.kind).toBe("pending");
    expect(g.refund).toEqual({ kind: "clear" });
  });
  it("a read that throws is a failed read → unverified, never clear", async () => {
    const read: OpsRead = async () => {
      throw new Error("network down");
    };
    const g = await loadMoneyGuards(read, detail(), { release: true, refund: true });
    expect(g.release).toEqual({ kind: "unverified", failure: { ok: false, kind: "error", message: "network down" } });
    expect(g.refund?.kind).toBe("unverified");
  });
  it("refund_actions stays a source for refunds", async () => {
    const g = await loadMoneyGuards(async () => ok([]), detail(settled, [act({ action_type: "refund_execute", subject_kind: "payment", subject_id: PAY, state: "succeeded_at_provider" })]), { release: false, refund: true });
    expect(g.refund?.kind).toBe("pending");
  });
  it("no read and no guard for a form that is not offered", async () => {
    const read = vi.fn<OpsRead>(async () => ok([]));
    expect(await loadMoneyGuards(read, detail(), { release: false, refund: false })).toEqual({ release: null, refund: null });
    expect(read).not.toHaveBeenCalled();
  });
});
