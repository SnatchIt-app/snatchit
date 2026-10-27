import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ callOps: vi.fn(), requireOperator: vi.fn(), revalidatePath: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidatePath }));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import { readPrimaryReconciliation, recordPrimaryRefundForm } from "@/lib/primary-refund-actions";

const ORDER = "7a000000-0000-4000-8000-0000000000d4";
const KEY = "pr.11111111-2222-4333-8444-555555555555";
const payload = { from: null, to: null, computed_at: "2026-10-27T06:30:00Z", currency: "USD", basis: "b", count: 0, attention_count: 0, critical_count: 0, rows: [], attention: [] };

const fd = (o: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries({ orderId: ORDER, commandKey: KEY, amount_minor: "2750", reasonCode: "buyer_request", confirm: "REFUND", ...o })) f.append(k, v);
  return f;
};

beforeEach(() => {
  mocks.callOps.mockReset();
  mocks.revalidatePath.mockReset();
  mocks.requireOperator.mockReset().mockResolvedValue({ id: "f0000000-0000-4000-8000-0000000000a1", role: "platform_admin" });
});

describe("the reconciliation read", () => {
  it("passes only well-formed dates through, and nulls anything else", async () => {
    mocks.callOps.mockResolvedValue({ ok: true, data: payload });
    await readPrimaryReconciliation("2026-11-01", "2026-11-30");
    expect(mocks.callOps).toHaveBeenLastCalledWith("primary_reconciliation", { p_from: "2026-11-01", p_to: "2026-11-30" });
    await readPrimaryReconciliation("last week", null);
    expect(mocks.callOps).toHaveBeenLastCalledWith("primary_reconciliation", { p_from: null, p_to: null });
  });
  it("an unrecognised payload is a failure, not an empty page", async () => {
    mocks.callOps.mockResolvedValue({ ok: true, data: { rows: [] } });
    const r = await readPrimaryReconciliation();
    expect(r.ok).toBe(false);
  });
});

describe("recording a refund", () => {
  it("sends the server's four arguments verbatim and revalidates on a receipt", async () => {
    mocks.callOps.mockResolvedValue({ ok: true, data: { status: "ok", refund_id: "r1", voided_atoms: 2, full: true } });
    const s = await recordPrimaryRefundForm({ outcome: null }, fd({}));
    expect(mocks.callOps).toHaveBeenCalledWith("record_primary_refund", { p_order_id: ORDER, p_amount_minor: 2750, p_reason_code: "buyer_request", p_command_key: KEY });
    expect(s.outcome?.kind).toBe("recorded");
    expect(mocks.revalidatePath).toHaveBeenCalledWith("/money/ticket-orders");
  });
  it("nothing is sent without the typed confirmation, a reason, or a sane amount", async () => {
    const bads: Record<string, string>[] = [{ confirm: "yes" }, { confirm: "" }, { reasonCode: " " }, { amount_minor: "0" }, { amount_minor: "abc" }, { orderId: "nope" }, { commandKey: "req:x" }];
    for (const bad of bads) {
      mocks.callOps.mockClear();
      const s = await recordPrimaryRefundForm({ outcome: null }, fd(bad));
      expect(s.problems?.length, JSON.stringify(bad)).toBeGreaterThan(0);
      expect(mocks.callOps, JSON.stringify(bad)).not.toHaveBeenCalled();
    }
  });
  it("an amount above the order's total is refused with the number, before sending", async () => {
    const s = await recordPrimaryRefundForm({ outcome: null }, fd({ amount_minor: "9999", max_minor: "2750" }));
    expect(s.problems?.map((p) => p.field)).toContain("amountMinor");
    expect(mocks.callOps).not.toHaveBeenCalled();
  });
  it("the retry re-sends the SAME key, so a lost answer cannot refund twice", async () => {
    mocks.callOps.mockResolvedValue({ ok: true, data: { status: "idempotency_replay", refund_id: "r1" } });
    const first = await recordPrimaryRefundForm({ outcome: null }, fd({}));
    expect(first.commandKey).toBe(KEY);
    expect(first.outcome?.kind).toBe("replayed");
    const second = await recordPrimaryRefundForm(first, fd({}));
    expect(mocks.callOps.mock.calls.every(([, a]) => (a as Record<string, unknown>).p_command_key === KEY)).toBe(true);
    expect(second.outcome?.kind).toBe("replayed");
  });
  it("the console's own failure kinds are rendered as themselves, and nothing is revalidated", async () => {
    for (const [failure, expected] of [
      [{ ok: false, kind: "denied" }, "role cannot"],
      [{ ok: false, kind: "mfa" }, "authenticator"],
      [{ ok: false, kind: "paused", message: "paused" }, "paused"],
      [{ ok: false, kind: "error", message: "precondition_failed: over_refund" }, "more than the order was paid"],
    ] as const) {
      mocks.callOps.mockResolvedValue(failure);
      const s = await recordPrimaryRefundForm({ outcome: null }, fd({}));
      expect(s.refusal?.toLowerCase(), JSON.stringify(failure)).toContain(String(expected).toLowerCase());
      expect(s.outcome?.kind).toBe("refused");
    }
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
  it("a status the console does not recognise is NOT success and warns against refunding in Stripe", async () => {
    mocks.callOps.mockResolvedValue({ ok: true, data: { status: "queued" } });
    const s = await recordPrimaryRefundForm({ outcome: null }, fd({}));
    expect(s.outcome?.kind).toBe("refused");
    expect(s.refusal).toContain("NOT recorded");
    expect(s.outcome?.kind === "refused" && s.outcome.detail).toBe("queued"); // the server's own word is kept
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
});

describe("the surface says plainly that it moves no money", () => {
  it("the page and the form both carry the manual-refund sentence, and the page is linked from Money", () => {
    const SRC = resolve(__dirname, "../src");
    const form = readFileSync(resolve(SRC, "components/money/PrimaryRefundForm.tsx"), "utf8");
    expect(form).toContain("MANUAL_REFUND_NOTE");
    const page = readFileSync(resolve(SRC, "app/(console)/money/ticket-orders/page.tsx"), "utf8");
    expect(page).toContain("does not move money");
    expect(readFileSync(resolve(SRC, "app/(console)/money/page.tsx"), "utf8")).toContain("/money/ticket-orders");
    // the direct action is not routed through execute_action, and must not claim an approval it has no part in
    expect(page).not.toContain("two-founder");
    expect(form).not.toContain("two-founder");
  });
});
