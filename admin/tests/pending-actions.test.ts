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
  it("clear only when list_actions answered a page with nothing unsettled for this subject", () => {
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: settled, listed: ok([]) })).toEqual({ kind: "clear" });
    // Rows that do not match type/subject/state never block, even if the server returned them.
    const strays = [act({ state: "succeeded" }), act({ state: "rejected" }), act({ subject_id: "other" }), act({ action_type: "refund_execute" })];
    expect(decidePendingGuard({ type: "payout_release", subjectId: TR, known: [], listed: ok(strays) })).toEqual({ kind: "clear" });
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
