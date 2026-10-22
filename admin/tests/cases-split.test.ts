import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ usePathname: () => "/cases", useRouter: () => ({ push: () => {} }) }));
vi.mock("server-only", () => ({}));

import { CaseControls, CaseNotes, caseEnvelope } from "@/components/cases/CaseWork";
import type { CaseDetail, OpsCase } from "@/lib/types";

const ID = "11111111-2222-4333-8444-555555555555";
const c: OpsCase = { id: ID, title: "Transfer overdue", case_type: "transfer_overdue", status: "open", priority: "p1", version: 7 };
const detail = { case: c, notes: [], events: [], operators: [], actions: [], subject: null } as unknown as CaseDetail;
const me = { id: "aaaaaaaa-0000-4000-8000-000000000001", label: "f***@example.test" };

const forms = (html: string) => html.split("<form").slice(1).map((f) => f.slice(0, f.indexOf("</form>")));
const hidden = (form: string, name: string) => form.match(new RegExp(`name="${name}" value="([^"]*)"`))?.[1]?.replace(/&quot;/g, '"');

/**
 * The split view's pane and the full case page share one set of forms. The
 * safeguards must be identical in both: the same action types, the version
 * that was rendered (stale edits are rejected), and a required audit reason.
 */
describe("case work keeps its safeguards wherever it is rendered", () => {
  for (const revalidate of ["/cases", `/cases/${ID}`]) {
    it(`assign/status/priority/due each carry the rendered version and require a reason (revalidate ${revalidate})`, () => {
      const env = caseEnvelope(c, ID, revalidate);
      const html = renderToStaticMarkup(createElement(CaseControls, { c, detail, me, envelope: env, idPrefix: "t" }));
      const fs = forms(html);
      expect(fs.map((f) => hidden(f, "action_type"))).toEqual(["case_assign", "case_status", "case_priority", "case_due"]);
      for (const f of fs) {
        expect(hidden(f, "subject_kind")).toBe("case");
        expect(hidden(f, "subject_id")).toBe(ID);
        expect(JSON.parse(hidden(f, "expected") ?? "{}")).toEqual({ version: 7 });
        expect(hidden(f, "reason_required")).toBe("1");
        expect(f).toMatch(/<textarea[^>]*name="reason"[^>]*required/);
        expect(hidden(f, "revalidate")).toBe(revalidate);
      }
    });
  }

  it("notes stay append-only without a reason, and carry the version", () => {
    const html = renderToStaticMarkup(createElement(CaseNotes, { c, detail, meId: me.id, envelope: caseEnvelope(c, ID, "/cases"), idPrefix: "t" }));
    const [f] = forms(html);
    expect(hidden(f, "action_type")).toBe("case_note");
    expect(hidden(f, "reason_required")).toBe("0");
    expect(JSON.parse(hidden(f, "expected") ?? "{}")).toEqual({ version: 7 });
    expect(html).toContain("Append-only; visible to all operators.");
  });

  it("a case without a version sends no expected state rather than a made-up one", () => {
    expect(caseEnvelope({ ...c, version: undefined }, ID, "/cases").expected).toEqual({});
  });
});

describe("the split view is URL state with a way back on every size", () => {
  const page = readFileSync(resolve(__dirname, "../src/app/(console)/cases/page.tsx"), "utf8");
  it("both the pane and the full page render the shared controls", () => {
    const full = readFileSync(resolve(__dirname, "../src/app/(console)/cases/[id]/page.tsx"), "utf8");
    expect(page).toContain("<CaseControls");
    expect(full).toContain("<CaseControls");
    expect(full).not.toContain('actionType="case_');
  });
  it("below xl the open case replaces the queue and offers All cases", () => {
    expect(page).toMatch(/open \? "hidden xl:block" : ""/);
    expect(page).toContain("All cases");
  });
});
