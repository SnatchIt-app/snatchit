import { describe, expect, it, vi } from "vitest";
import { combineMoneyGuards, decidePendingGuard, loadMoneyGuards, pendingActionFilters, UNSETTLED_STATES, type OpsRead } from "@/lib/pending-actions";
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
  it("reads both money types once each whenever a money form is offered, with the agreed filter shape", async () => {
    const read = vi.fn<OpsRead>(async () => ok([]));
    const g = await loadMoneyGuards(read, detail(), { release: true, refund: true });
    expect(g).toEqual({ release: { kind: "clear" }, refund: { kind: "clear" } });
    expect(read).toHaveBeenCalledTimes(2);
    expect(read).toHaveBeenCalledWith("list_actions", { p_filters: { action_type: ["payout_release"], subject_kind: "transfer", subject_id: TR, state: [...UNSETTLED_STATES] }, p_cursor: null, p_limit: 5 });
    expect(read).toHaveBeenCalledWith("list_actions", { p_filters: { action_type: ["refund_execute"], subject_kind: "payment", subject_id: PAY, state: [...UNSETTLED_STATES] }, p_cursor: null, p_limit: 5 });
    expect(UNSETTLED_STATES).toEqual(["requested", "awaiting_approval", "processing", "succeeded_at_provider", "unknown"]);
    expect(pendingActionFilters("refund_execute", PAY).subject_kind).toBe("payment");
  });
  it("capped list misses the old release, list_actions has it → release pending, and the refund guard is pending too, carrying the release (P3)", async () => {
    const read: OpsRead = async (_fn, args) => ((args.p_filters as { action_type: string[] }).action_type[0] === "payout_release" ? ok([act({})]) : ok([]));
    const g = await loadMoneyGuards(read, detail(), { release: true, refund: true });
    expect(g.release?.kind).toBe("pending");
    expect(g.refund).toEqual({ kind: "pending", action: expect.objectContaining({ id: "aaaaaaaa-0000-4000-8000-0000000000e1", action_type: "payout_release" }) });
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
  it("no read and no guard when no money form is offered", async () => {
    const read = vi.fn<OpsRead>(async () => ok([]));
    expect(await loadMoneyGuards(read, detail(), { release: false, refund: false })).toEqual({ release: null, refund: null });
    expect(read).not.toHaveBeenCalled();
  });
});

/**
 * P3 (reviewer E) — money on an order is one subject. list_actions filters by
 * one action_type, so each form's guard folds the other verb's answer in:
 * either pending → pending (the blocking action, so the page can name it);
 * either unverified → unverified; only both clear → clear. A verb without a
 * subject row has nothing to read and never blocks the other.
 */
describe("P3 — loadMoneyGuards reads both money types and each guard folds the other in", () => {
  const refundRow = act({ id: "rrrrrrrr-0000-4000-8000-0000000000e1", action_type: "refund_execute", subject_kind: "payment", subject_id: PAY, state: "unknown" });
  const byType = (release: unknown, refund: unknown): OpsRead => async (_fn, args) => ((args.p_filters as { action_type: string[] }).action_type[0] === "payout_release" ? release : refund) as never;

  it("a pending refund makes the release guard pending with the refund action", async () => {
    const g = await loadMoneyGuards(byType(ok([]), ok([refundRow])), detail(), { release: true, refund: true });
    expect(g.release).toEqual({ kind: "pending", action: expect.objectContaining({ id: refundRow.id, action_type: "refund_execute" }) });
    expect(g.refund?.kind).toBe("pending");
  });

  it("a pending row of the form's own type is preferred over the other type's", async () => {
    const g = await loadMoneyGuards(byType(ok([act({})]), ok([refundRow])), detail(), { release: true, refund: true });
    expect(g.release).toEqual({ kind: "pending", action: expect.objectContaining({ action_type: "payout_release" }) });
    expect(g.refund).toEqual({ kind: "pending", action: expect.objectContaining({ action_type: "refund_execute" }) });
  });

  it("only the refund form offered → payout_release is still read, and a pending release blocks the refund", async () => {
    const read = vi.fn<OpsRead>(byType(ok([act({})]), ok([])));
    const g = await loadMoneyGuards(read, detail(), { release: false, refund: true });
    expect(read).toHaveBeenCalledTimes(2);
    expect(read).toHaveBeenCalledWith("list_actions", expect.objectContaining({ p_filters: expect.objectContaining({ action_type: ["payout_release"], subject_id: TR }) }));
    expect(g.release).toBeNull();
    expect(g.refund).toEqual({ kind: "pending", action: expect.objectContaining({ action_type: "payout_release" }) });
  });

  it("only the release form offered → refund_execute is still read, and a failed refund read leaves the release unverified", async () => {
    const failure = { ok: false as const, kind: "error" as const, message: "boom" };
    const read = vi.fn<OpsRead>(byType(ok([]), failure));
    const g = await loadMoneyGuards(read, detail(), { release: true, refund: false });
    expect(read).toHaveBeenCalledTimes(2);
    expect(g.release).toEqual({ kind: "unverified", failure });
    expect(g.refund).toBeNull();
  });

  it("the other type's read failing or answering an unrecognised page → unverified, never clear", async () => {
    for (const bad of [{ ok: false, kind: "denied" }, { ok: true, data: null }, { ok: true, data: { items: [], count_hint: 1 } }]) {
      const g = await loadMoneyGuards(byType(bad, ok([])), detail(), { release: true, refund: true });
      expect(g.refund?.kind, JSON.stringify(bad)).toBe("unverified");
      expect(g.release?.kind, JSON.stringify(bad)).toBe("unverified");
    }
  });

  it("pending on one side and unverified on the other → pending on both (the action is named; nothing is re-armed)", async () => {
    const g = await loadMoneyGuards(byType({ ok: false, kind: "error", message: "x" }, ok([refundRow])), detail(), { release: true, refund: true });
    expect(g.release).toEqual({ kind: "pending", action: expect.objectContaining({ id: refundRow.id }) });
    expect(g.refund).toEqual({ kind: "pending", action: expect.objectContaining({ id: refundRow.id }) });
  });

  it("both clear → both clear (control)", async () => {
    expect(await loadMoneyGuards(async () => ok([]), detail(), { release: true, refund: true })).toEqual({ release: { kind: "clear" }, refund: { kind: "clear" } });
  });

  it("no transfer row → nothing to read for payout_release; the refund guard stands alone", async () => {
    const read = vi.fn<OpsRead>(async () => ok([]));
    const d = { ...detail(), transfer: null } as unknown as OrderDetail;
    expect(await loadMoneyGuards(read, d, { release: false, refund: true })).toEqual({ release: null, refund: { kind: "clear" } });
    expect(read).toHaveBeenCalledTimes(1);
  });

  it("a transfer row without an id cannot be checked → both unverified (fail closed)", async () => {
    const d = { ...detail(), transfer: { status: "seller_sent" } } as unknown as OrderDetail;
    const g = await loadMoneyGuards(async () => ok([]), d, { release: true, refund: true });
    expect(g.release).toEqual({ kind: "unverified", failure: null });
    expect(g.refund).toEqual({ kind: "unverified", failure: null });
  });

  it("combineMoneyGuards: the pure fold", () => {
    const clear = { kind: "clear" } as const;
    const unv = { kind: "unverified", failure: null } as const;
    const pend = { kind: "pending", action: act({}) } as const;
    const pend2 = { kind: "pending", action: refundRow } as const;
    expect(combineMoneyGuards(null, pend)).toBeNull();
    expect(combineMoneyGuards(clear, null)).toEqual(clear);
    expect(combineMoneyGuards(clear, clear)).toEqual(clear);
    expect(combineMoneyGuards(clear, pend)).toEqual(pend);
    expect(combineMoneyGuards(clear, unv)).toEqual(unv);
    expect(combineMoneyGuards(unv, clear)).toEqual(unv);
    expect(combineMoneyGuards(unv, pend)).toEqual(pend);
    expect(combineMoneyGuards(pend, pend2)).toEqual(pend);
    expect(combineMoneyGuards(pend, unv)).toEqual(pend);
  });
});
