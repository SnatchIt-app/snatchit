import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Port of PR #89 (3dab1614) onto console v2: migration 144's refund workflow
 * lives in the shared case controls (CaseWork), so the split view's pane and
 * the full case page offer the same controls with the same safeguards.
 *
 * What the forms post is checked against migration 144 as it stands on
 * release/production-gate-20260918 (and 20261013000000, whose case arms are
 * byte-identical): execute_action's allow-list names case_refund_classify and
 * case_refund_obligation; the dispatcher reads params classification /
 * assignee and kind / settled / note, and requires a reason to classify.
 *
 * The real submitActionForm → executeAction → callOps path runs; only the
 * Supabase client is faked.
 */
const rpc = vi.hoisted(() => ({ reply: { data: null as unknown, error: null as unknown }, calls: [] as { fn: string; args: Record<string, unknown> }[] }));

vi.mock("next/navigation", () => ({ usePathname: () => "/cases", useRouter: () => ({ push: () => {} }) }));
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    schema: () => ({
      rpc: async (fn: string, args: Record<string, unknown>) => {
        rpc.calls.push({ fn, args });
        return rpc.reply;
      },
    }),
  }),
}));

import { CaseControls, CaseRefundResolution, caseEnvelope, caseRefundState } from "@/components/cases/CaseWork";
import { OutcomeText } from "@/components/ui/ConfirmForm";
import { submitActionForm } from "@/lib/actions";
import type { CaseDetail, CaseEvent, OpsCase } from "@/lib/types";

const ID = "11111111-2222-4333-8444-555555555555";
const ME = "aaaaaaaa-0000-4000-8000-000000000001";
const me = { id: ME, label: "f***@example.test" };
const refundCase: OpsCase = { id: ID, title: "Refund recorded — support action needed", case_type: "refund_resolution", status: "open", priority: "p2", version: 7 };

const classified = (value: string, at: string): CaseEvent => ({ kind: "classified", at, data: { classification: value, reason: "Stripe shows a partial refund" } });
const obligation = (kind: string, settled: boolean, at: string, note?: string): CaseEvent => ({ kind: "obligation_changed", at, data: { kind, settled, ...(note ? { note } : {}) } });
const detailOf = (c: OpsCase, events: CaseEvent[]) => ({ case: c, notes: [], events, operators: [], actions: [], subject: null }) as unknown as CaseDetail;

const controls = (c: OpsCase, events: CaseEvent[]) =>
  renderToStaticMarkup(createElement(CaseControls, { c, detail: detailOf(c, events), me, envelope: caseEnvelope(c, ID, `/cases/${ID}`), idPrefix: "t" }));
const forms = (html: string) => html.split("<form").slice(1).map((f) => f.slice(0, f.indexOf("</form>")));
const hidden = (form: string, name: string) => form.match(new RegExp(`name="${name}" value="([^"]*)"`))?.[1]?.replace(/&quot;/g, '"');
const formFor = (html: string, actionType: string) => forms(html).find((f) => hidden(f, "action_type") === actionType);
const options = (form: string, name: string) => {
  const sel = form.match(new RegExp(`<select[^>]*name="${name.replace(/[.:]/g, "\\$&")}"[^>]*>([\\s\\S]*?)</select>`))?.[1] ?? "";
  return [...sel.matchAll(/<option[^>]*value="([^"]*)"/g)].map((m) => m[1]);
};

/** FormData exactly as the browser would post the rendered form: its hidden inputs plus the visible fields given. */
function post(form: string, visible: Record<string, string>): FormData {
  const fd = new FormData();
  for (const m of form.matchAll(/<input type="hidden" name="([^"]+)" value="([^"]*)"/g)) fd.set(m[1], m[2].replace(/&quot;/g, '"'));
  for (const [k, v] of Object.entries(visible)) {
    expect(form, `the rendered form has a field named ${k}`).toContain(`name="${k}"`);
    fd.set(k, v);
  }
  return fd;
}

beforeEach(() => {
  rpc.calls.length = 0;
  rpc.reply = { data: { status: "succeeded", action_id: "9a900000-0000-4000-8000-0000000000c1" }, error: null };
});

describe("a refund-resolution case offers 144's controls, and only where they can succeed", () => {
  it("an unclassified open case offers Classify first, no obligation control, and warns on Status", () => {
    const html = controls(refundCase, []);
    expect(forms(html).map((f) => hidden(f, "action_type"))).toEqual(["case_refund_classify", "case_assign", "case_status", "case_priority", "case_due"]);
    const f = formFor(html, "case_refund_classify")!;
    expect(hidden(f, "subject_kind")).toBe("case");
    expect(hidden(f, "subject_id")).toBe(ID);
    expect(JSON.parse(hidden(f, "expected") ?? "{}")).toEqual({ version: 7 });
    expect(hidden(f, "reason_required")).toBe("1");
    expect(f).toMatch(/<textarea[^>]*name="reason"[^>]*required/);
    expect(options(f, "param.classification")).toEqual(["", "A", "B", "C"]);
    expect(f).toMatch(/<select[^>]*name="param.classification"[^>]*required/);
    expect(options(f, "param.assignee")).toEqual(["", ME]);
    expect(formFor(html, "case_status")).toContain("Resolving or dismissing will be refused: classify this case first (case_refund_classify: A, B or C)");
  });

  it("once B raised payout_owed, Record an obligation offers exactly the raised kind, as a note-carrying form", () => {
    const html = controls(refundCase, [classified("B", "2026-09-19T10:00:00Z"), obligation("payout_owed", false, "2026-09-19T10:00:01Z")]);
    expect(forms(html).map((f) => hidden(f, "action_type"))).toEqual(["case_refund_classify", "case_refund_obligation", "case_assign", "case_status", "case_priority", "case_due"]);
    const f = formFor(html, "case_refund_obligation")!;
    expect(JSON.parse(hidden(f, "expected") ?? "{}")).toEqual({ version: 7 });
    expect(hidden(f, "reason_required")).toBe("0");
    expect(options(f, "param.kind")).toEqual(["payout_owed"]);
    expect(options(f, "param.settled:boolean")).toEqual(["true", "false"]);
    expect(f).toMatch(/<textarea[^>]*name="param.note"[^>]*required/);
    expect(html).toContain("1 unsettled");
    expect(formFor(html, "case_status")).toContain("Resolving or dismissing will be refused: unsettled obligation(s): payout_owed");
  });

  it("with every obligation recorded settled the Status warning goes away", () => {
    const html = controls(refundCase, [
      classified("B", "2026-09-19T10:00:00Z"),
      obligation("payout_owed", false, "2026-09-19T10:00:01Z"),
      obligation("payout_owed", true, "2026-09-19T11:00:00Z", "paid by bank transfer"),
    ]);
    expect(html).toContain("All recorded settled");
    expect(html).not.toContain("will be refused");
  });

  it("a closed refund case offers no classify or obligation form", () => {
    const html = controls({ ...refundCase, status: "resolved" }, [classified("A", "2026-09-19T10:00:00Z")]);
    expect(forms(html).map((f) => hidden(f, "action_type"))).toEqual(["case_assign", "case_status", "case_priority", "case_due"]);
  });

  it("any other case type is untouched, whatever its event log holds", () => {
    const other = { ...refundCase, case_type: "transfer_overdue" };
    expect(caseRefundState(other, detailOf(other, [classified("B", "2026-09-19T10:00:00Z")]))).toBeNull();
    const html = controls(other, [classified("B", "2026-09-19T10:00:00Z"), obligation("payout_owed", false, "2026-09-19T10:00:01Z")]);
    expect(forms(html).map((f) => hidden(f, "action_type"))).toEqual(["case_assign", "case_status", "case_priority", "case_due"]);
    expect(html).not.toContain("will be refused");
  });

  it("the full page and the split view's pane both render the refund panel; the page itself still holds no case form", () => {
    const full = readFileSync(resolve(__dirname, "../src/app/(console)/cases/[id]/page.tsx"), "utf8");
    const pane = readFileSync(resolve(__dirname, "../src/app/(console)/cases/page.tsx"), "utf8");
    for (const src of [full, pane]) {
      expect(src).toContain("caseRefundState(c, detail)");
      expect(src).toContain("<CaseRefundResolution c={c} refund={refund} />");
    }
    expect(full).not.toContain('actionType="case_');
  });
});

describe("what the forms post is what migration 144 reads", () => {
  it("classify sends classification, assignee and the reason, with the rendered version", async () => {
    const f = formFor(controls(refundCase, []), "case_refund_classify")!;
    const state = await submitActionForm({}, post(f, { "param.classification": "B", "param.assignee": ME, reason: "Stripe shows 40.00 of 75.00 refunded" }));
    expect(state.outcome?.status).toBe("succeeded");
    expect(rpc.calls).toHaveLength(1);
    expect(rpc.calls[0].fn).toBe("execute_action");
    expect(rpc.calls[0].args).toMatchObject({
      p_action_type: "case_refund_classify",
      p_subject_kind: "case",
      p_subject_id: ID,
      p_params: { classification: "B", assignee: ME },
      p_reason: "Stripe shows 40.00 of 75.00 refunded",
      p_expected: { version: 7 },
    });
  });

  it("record-settled sends kind, a JSON boolean and the note, and the note doubles as the audit reason", async () => {
    const f = formFor(controls(refundCase, [classified("B", "2026-09-19T10:00:00Z"), obligation("payout_owed", false, "2026-09-19T10:00:01Z")]), "case_refund_obligation")!;
    const note = "paid out manually, Stripe payout po_test_1";
    await submitActionForm({}, post(f, { "param.kind": "payout_owed", "param.settled:boolean": "true", "param.note": note }));
    expect(rpc.calls[0].args).toMatchObject({
      p_action_type: "case_refund_obligation",
      p_subject_id: ID,
      p_params: { kind: "payout_owed", settled: true, note },
      p_reason: note,
      p_expected: { version: 7 },
    });
  });

  it("'Still outstanding' sends settled false, never a string", async () => {
    const f = formFor(controls(refundCase, [classified("C", "2026-09-19T10:00:00Z"), obligation("remainder_refund_owed", false, "2026-09-19T10:00:01Z")]), "case_refund_obligation")!;
    await submitActionForm({}, post(f, { "param.kind": "remainder_refund_owed", "param.settled:boolean": "false", "param.note": "the refund failed at Stripe" }));
    expect((rpc.calls[0].args.p_params as Record<string, unknown>).settled).toBe(false);
  });

  it("the dispatcher's refusal is shown in its own words", async () => {
    const message = "classification B leaves payout_owed outstanding: an assignee is required";
    rpc.reply = { data: { status: "rejected", reject_reason: "precondition", message }, error: null };
    const f = formFor(controls(refundCase, []), "case_refund_classify")!;
    const state = await submitActionForm({}, post(f, { "param.classification": "B", "param.assignee": "", reason: "Stripe shows a partial refund" }));
    expect((rpc.calls[0].args.p_params as Record<string, unknown>).assignee).toBeNull();
    const html = renderToStaticMarkup(createElement(OutcomeText, { outcome: state.outcome! }));
    expect(html).toContain("Rejected: precondition");
    expect(html).toContain(message);
  });
});

describe("the refund panel says what the record establishes", () => {
  const panel = (c: OpsCase, events: CaseEvent[]) => renderToStaticMarkup(createElement(CaseRefundResolution, { c, refund: caseRefundState(c, detailOf(c, events))! }));

  it("unclassified: no classification recorded, and the close refusal in the database's words", () => {
    const html = panel(refundCase, []);
    expect(html).toContain("No classification is recorded for this case.");
    expect(html).toContain("classify this case first (case_refund_classify: A, B or C)");
  });

  it("an obligation reads as recorded settled or unsettled, never as money that moved", () => {
    const html = panel(refundCase, [
      classified("C", "2026-09-19T10:00:00Z"),
      obligation("remainder_refund_owed", true, "2026-09-19T11:00:00Z", "refunded the rest"),
      obligation("reversal_decision", false, "2026-09-19T11:00:01Z"),
    ]);
    expect(html).toContain("Recorded as");
    expect(html).toContain("C — a partial refund, and the order was cancelled");
    expect(html).toContain("Recorded settled");
    expect(html).toContain("refunded the rest");
    expect(html).toContain("Unsettled");
    expect(html).toContain("unsettled obligation(s): reversal_decision");
    expect(html.toLowerCase()).not.toContain("money has moved");
    expect(html).toContain("nothing in the console moves this money");
  });

  it("a closed case shows its record without a 'cannot be closed' warning", () => {
    const html = panel({ ...refundCase, status: "dismissed" }, []);
    expect(html).not.toContain("cannot be closed yet");
  });
});
