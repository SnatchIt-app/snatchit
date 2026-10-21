import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ usePathname: () => "/", useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }), useParams: () => ({}) }));
vi.mock("server-only", () => ({}));

import { caseFilters, listTotal } from "@/lib/list-filters";
import { selfHref } from "@/lib/search-params";
import { deniedReasonCode, deniedReasonText, signInErrorMessage } from "@/lib/auth/messages";
import { OutcomeText, blockWhilePending, ConfirmForm } from "@/components/ui/ConfirmForm";
import { OrderActions, unsettledAction } from "@/components/orders/OrderActions";
import { loadMoneyGuards } from "@/lib/pending-actions";
import { CaseTable } from "@/components/cases/CaseTable";
import { AttentionSummary } from "@/components/analytics/sections";
import { TrendChart } from "@/components/charts/TrendChart";
import ConsoleError from "@/app/(console)/error";
import type { ActionOutcome, OpsAction, OrderDetail } from "@/lib/types";

/**
 * Regression guards for the 2026-10-12 functional-readiness audit. Each names
 * the finding it guards; each was checked to fail with its fix reverted.
 */
const src = (rel: string) => readFileSync(resolve(__dirname, "../src", rel), "utf8");
const h = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el);
const forms = (html: string) => html.split("<form").slice(1).map((f) => f.slice(0, f.indexOf("</form>")));
const actionTypes = (html: string) => forms(html).map((f) => f.match(/name="action_type" value="([^"]*)"/)?.[1]);

describe("A1 — 'Needs an owner' sends what list_cases reads", () => {
  it("unassigned travels as assignee='unassigned', never as an ignored `unassigned` key", () => {
    expect(caseFilters({ assignee: "unassigned", status: "open,waiting" }, "me-id")).toEqual({ assignee: "unassigned", status: ["open", "waiting"] });
    expect(caseFilters({ assignee: "me" }, "me-id")).toEqual({ assignee: "me-id" });
    expect(caseFilters({ assignee: "unassigned" }, "me-id")).not.toHaveProperty("unassigned");
  });
});

describe("A2 — a later page's length is never shown as the total", () => {
  const page = (items: number, next: string | null, hint?: number) => ({ ok: true, data: { items: Array.from({ length: items }, (_, i) => ({ i })), next_cursor: next, ...(hint !== undefined ? { count_hint: hint } : {}) } });
  it("unknown on a later page, even when it is the last one", () => expect(listTotal(page(20, null), true)).toBeNull());
  it("count_hint on the first page", () => expect(listTotal(page(50, "c", 120), false)).toBe(120));
  it("the first and only page counts itself; a first page with more does not", () => {
    expect(listTotal(page(7, null), false)).toBe(7);
    expect(listTotal(page(50, "c"), false)).toBeNull();
    expect(listTotal({ ok: false }, false)).toBeNull();
  });
});

describe("A5 / A16 — Try again reloads the same view", () => {
  it("keeps every parameter, including repeated keys", () => {
    expect(selfHref("/users", { q: "maya", blocked: "true", cursor: undefined })).toBe("/users?q=maya&blocked=true");
    expect(selfHref("/reports", { status: ["pending", "reviewing"] })).toBe("/reports?status=pending&status=reviewing");
    expect(selfHref("/money", {})).toBe("/money");
  });
});

describe("A6 — CaseTable headers do not offer a sort that never happens", () => {
  it("renders no ?sort= links and no aria-sort", () => {
    const html = h(createElement(CaseTable, { rows: [{ id: "11111111-2222-4333-8444-555555555555", title: "T", status: "open", priority: "p1", case_type: "transfer_overdue" }], basePath: "/", searchParams: { sort: "priority", dir: "asc" } }));
    expect(html).not.toContain("sort=");
    expect(html).not.toContain("aria-sort");
  });
});

describe("A9 — /system setting and job forms re-render after a change (fresh idempotency key, current value)", () => {
  it("setting_set and job_retry carry revalidate=/system like every other form", () => {
    const s = src("app/(console)/system/page.tsx");
    expect(s).toMatch(/actionType="setting_set"[^>]*revalidate="\/system"/);
    expect(s).toMatch(/actionType="job_retry"[^>]*revalidate="\/system"/);
  });
});

describe("A10 — the server's answer survives the keyed remount", () => {
  it("every version-keyed form sits inside an OutcomeHost", () => {
    const s = src("components/cases/CaseWork.tsx");
    const keyed = s.match(/<ConfirmForm key=\{`[a-z]+-\$\{c\.version\}`\}/g) ?? [];
    // assign, status, priority, due, note + migration 144's classify and obligation (PR #89 port)
    expect(keyed.length).toBe(7);
    for (const m of s.matchAll(/<OutcomeHost actionType="([a-z_]+)">\s*<ConfirmForm key=\{`[a-z]+-\$\{c\.version\}`\}[\s\S]*?actionType="([a-z_]+)"/g)) expect(m[1]).toBe(m[2]);
    expect([...s.matchAll(/<OutcomeHost actionType=/g)].length).toBe(7);
    expect(src("components/reports/ReportResolveForms.tsx")).toContain('<OutcomeHost actionType="report_resolve">');
  });
  it("inside a host the form posts the same fields and does not render its own copy of the answer", () => {
    const s = src("components/ui/ConfirmForm.tsx");
    expect(s).toContain("{host ? null : <FormResult state={ownState} actionType={actionType} />}");
    expect(s).toContain("const formAction = host ? host.formAction : ownAction;");
  });
});

describe("A3 (item 3) — pending submit keeps focus and cannot submit twice", () => {
  it("blockWhilePending cancels only while pending", () => {
    const e = { preventDefault: vi.fn() };
    expect(blockWhilePending(true, e)).toBe(true);
    expect(e.preventDefault).toHaveBeenCalledTimes(1);
    const f = { preventDefault: vi.fn() };
    expect(blockWhilePending(false, f)).toBe(false);
    expect(f.preventDefault).not.toHaveBeenCalled();
  });
  it("submit buttons use aria-disabled, never disabled (which drops focus to the page)", () => {
    const html = h(createElement(ConfirmForm, { idempotencyKey: "k-12345678", actionType: "case_note", subjectKind: "case", subjectId: "x", label: "Add note", reasonRequired: false }));
    expect(html).toMatch(/<button[^>]*type="submit"[^>]*aria-disabled="false"/);
    expect(html).not.toMatch(/<button[^>]*type="submit"[^>]*\sdisabled/);
    for (const f of ["components/auth/LoginForm.tsx", "components/auth/MfaFlow.tsx", "components/ui/ConfirmForm.tsx"]) {
      expect(src(f), f).not.toMatch(/type="submit"[^>]*\sdisabled=\{/);
    }
    expect(src("components/auth/MfaFlow.tsx")).toContain("if (busyRef.current) return;");
    expect(src("components/auth/LoginForm.tsx")).toContain("if (isPending || inFlight.current) {");
  });
});

const PAY = "9a900000-0000-4000-8000-000000000013";
const TR = "7a000000-0000-4000-8000-000000000013";
const action = (over: Partial<OpsAction>): OpsAction => ({ id: "aaaaaaaa-0000-4000-8000-000000000001", action_type: "refund_execute", subject_kind: "payment", subject_id: PAY, state: "awaiting_approval", requested_at: "2026-10-12T01:00:00Z", ...over });
const detail = (actions: OpsAction[], refundActions: OpsAction[] = []): OrderDetail =>
  ({
    payment: { id: PAY, status: "succeeded", total: 9900 },
    transfer: { id: TR, status: "seller_sent", payout_review_status: "manual_review" },
    listing: null, buyer: null, seller: null, disputes: [], dispute_resolutions: [], payout_decisions: [],
    refund: { refund_actions: refundActions }, seller_funds_state: null, cases: [], actions, evidence: [], bank_payout: { tracked: false, note: null }, raw: {},
  }) as unknown as OrderDetail;
// list_actions answers "nothing else pending" here, so only the rows order_detail already holds decide (F1 covers list_actions itself).
const nothingListed = async () => ({ ok: true as const, data: { items: [], next_cursor: null } });
const orderActions = async (d: OrderDetail) =>
  h(createElement(OrderActions, { d, me: { role: "platform_admin" }, path: `/orders/${PAY}`, refundEnabled: true, disputeOpen: false, canRelease: true, canRefund: true, guards: await loadMoneyGuards(nothingListed, d, { release: true, refund: true }) }));

describe("A11 (item 4) — no second refund or release can be parked from the order page", () => {
  it("positive control: with nothing pending both forms are offered", async () => {
    expect(actionTypes(await orderActions(detail([])))).toEqual(expect.arrayContaining(["payout_release", "refund_execute"]));
  });
  it("a refund awaiting approval replaces the refund form with the pending state and a link to the action", async () => {
    const html = await orderActions(detail([], [action({})]));
    expect(actionTypes(html)).not.toContain("refund_execute");
    expect(actionTypes(html)).toContain("payout_release");
    expect(html).toContain("Already requested — Awaiting approval");
    expect(html).toContain('href="/actions/aaaaaaaa-0000-4000-8000-000000000001"');
  });
  it("a release in processing replaces the release form", async () => {
    const html = await orderActions(detail([action({ action_type: "payout_release", subject_kind: "transfer", subject_id: TR, state: "processing" })]));
    expect(actionTypes(html)).not.toContain("payout_release");
    expect(actionTypes(html)).toContain("refund_execute");
  });
  it("unsettled means not terminal: unknown and succeeded_at_provider block; rejected, failed, succeeded do not; other subjects never", () => {
    expect(unsettledAction([action({ state: "unknown" })], "refund_execute", PAY)).not.toBeNull();
    expect(unsettledAction([action({ state: "succeeded_at_provider" })], "refund_execute", PAY)).not.toBeNull();
    for (const state of ["rejected", "failed", "succeeded"]) expect(unsettledAction([action({ state })], "refund_execute", PAY)).toBeNull();
    expect(unsettledAction([action({ subject_id: "other" })], "refund_execute", PAY)).toBeNull();
    expect(unsettledAction([action({ action_type: "payout_release" })], "refund_execute", PAY)).toBeNull();
  });
});

describe("A14 (item 6) — Orders queues use the reviewed wording", () => {
  it("manual review and open-case hints come from the reviewed labels", () => {
    const s = src("app/(console)/orders/page.tsx");
    expect(s).toContain("label: FUNDS_STATE_LABELS.manual_review");
    expect(s).toContain("hint: OPEN_CASE_LABELS.true");
    expect(s).not.toContain("Seller funds held for a person");
    expect(s).not.toContain("An order someone is working on");
  });
});

describe("A19 (item 7) — an unknown figure is never shown or drawn as 0", () => {
  it("a null metric is listed as unreadable, not counted as clear", () => {
    const html = h(createElement(AttentionSummary, { metrics: [{ key: "transfers_overdue", label: "Overdue", value: null }, { key: "reports_pending", label: "Reports", value: 0 }], definitions: {} }));
    expect(html).toContain("couldn&#x27;t be read");
    expect(html).toContain("1 check clear");
    expect(html).not.toContain("Nothing needs attention right now.");
  });
  it("a chart point with no figure is left out of the line, not plotted at 0", () => {
    const pts = [1, 2, null, 4].map((v, i) => ({ label: `d${i}`, detail: `day ${i}`, value: v }));
    const html = h(createElement(TrendChart, { kind: "line", unit: "count", points: pts, title: "t" }));
    expect(html).not.toContain("NaN");
    const d = html.match(/<path d="(M[^"]+)" fill="none"/)?.[1] ?? "";
    expect(d.match(/M/g)?.length).toBe(2);
  });
  it("money tiles show the existing dash for an unknown count", () => {
    const s = src("components/analytics/sections.tsx");
    expect(s).not.toMatch(/Count \?\? 0\}/);
    expect(s).toContain('valueNote={f.capturedCount == null ? "—"');
  });
});

describe("A21 (item 8) — a second founder's denial reads as a decision, not a failure", () => {
  it("rejected/denied renders the info line", () => {
    const html = h(createElement(OutcomeText, { outcome: { status: "rejected", reason: "denied", raw: {} } as unknown as ActionOutcome }));
    expect(html).toContain("Denied — nothing changed.");
    expect(html).not.toContain("Rejected");
  });
  it("other rejections still read as rejections", () => {
    const html = h(createElement(OutcomeText, { outcome: { status: "rejected", reason: "precondition", raw: {} } as unknown as ActionOutcome }));
    expect(html).toContain("Rejected: precondition");
  });
});

describe("item 9 — sign-in outage copy and coded denial reasons", () => {
  it("an outage is not a wrong password; credentials errors stay generic", () => {
    expect(signInErrorMessage(0)).toBe("Sign-in is unavailable right now. Try again in a moment.");
    expect(signInErrorMessage(503)).toBe("Sign-in is unavailable right now. Try again in a moment.");
    expect(signInErrorMessage(undefined)).toBe("Sign-in is unavailable right now. Try again in a moment.");
    expect(signInErrorMessage(400)).toBe("Sign-in failed. Check your email and password.");
  });
  it("/denied?reason= maps codes to fixed text and never echoes anything else", () => {
    expect(deniedReasonText("unavailable")).toBe("The console's database could not be reached.");
    expect(deniedReasonText("check_failed")).toBe("The access check returned an error.");
    expect(deniedReasonText("Call +1 555 0100 to restore access")).toBe("The access check returned an error.");
    expect(deniedReasonText("constructor")).toBe("The access check returned an error.");
    expect(deniedReasonCode({ unavailable: true })).toBe("unavailable");
    expect(deniedReasonCode({})).toBe("check_failed");
    expect(src("app/(auth)/denied/page.tsx")).not.toMatch(/compact>\s*\{reason\}/);
    expect(src("lib/auth/session.ts")).not.toContain("encodeURIComponent(res.message)");
    // …and the diagnostic is kept where support can read it: the server log.
    expect(src("lib/auth/session.ts")).toMatch(/console\.warn\("\[auth\] operator check failed", \{[^}]*message: "message" in res \? res\.message/);
  });
});

describe("BOTH-no-error-boundary — an unexpected throw gets a heading, a retry and a reference", () => {
  it("renders inside the console frame", () => {
    const err = Object.assign(new Error("x"), { digest: "abc123" });
    const html = h(createElement(ConsoleError, { error: err, retry: () => {} }));
    expect(html).toContain("<h1");
    expect(html).toContain("Try again");
    expect(html).toContain("Reference abc123");
    expect(html).not.toContain(">x<");
  });
});
