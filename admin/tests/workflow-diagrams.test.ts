import { createElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * V-1 item 4 — two small static workflow diagrams on the order page, behind a
 * "How this works" disclosure: the refund path as it is today and the payout
 * release path. Every step is taken from the repo's own records — the
 * console's copy (OrderActions, the order page), the status vocabulary
 * (lib/format.ts) and the manual refund SOP (a draft) — never from memory, and
 * each step cites its source. The tests pin each step's phrases against those
 * sources, the accessible structure (role="img", title + desc, a hidden text
 * list), and the placement (collapsed, in the actions column, OrderActions
 * untouched).
 */
const mocks = vi.hoisted(() => ({ callOps: vi.fn(), requireOperator: vi.fn() }));

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new Error("notFound");
  },
  redirect: () => {
    throw new Error("redirect");
  },
  usePathname: () => "/orders",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import { HowThisWorks, PAYOUT_RELEASE_PATH, REFUND_PATH, SOP_SOURCE, WorkflowDiagram, wrapLines, type WorkflowStep } from "@/components/orders/WorkflowDiagrams";
import { ACTION_STATE_LABELS, ACTION_TYPE_LABELS, PAYMENT_STATUS_LABELS, TRANSFER_STATUS_LABELS, payoutStateLabel } from "@/lib/format";
import OrderPage from "@/app/(console)/orders/[paymentId]/page";

const h = (el: ReactElement) => renderToStaticMarkup(el);
const SRC = resolve(__dirname, "../src");
/** JSX text in the sources escapes apostrophes; compare as plain text. */
const plain = (s: string) => s.replace(/&apos;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ");
const sourceText = (file: string) => plain(readFileSync(resolve(SRC, file), "utf8"));

/** The SOP lives on branch admin/manual-refund-sop; read it where it is checked out, or from this tree if it lands here. */
const SOP_CANDIDATES = [resolve(__dirname, "../../docs/admin-console/MANUAL_REFUND_SOP.md"), "/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-admin-sop/docs/admin-console/MANUAL_REFUND_SOP.md"];
const sopPath = SOP_CANDIDATES.find((p) => existsSync(p));
const sop = sopPath ? plain(readFileSync(sopPath, "utf8")) : null;

const stepText = (s: WorkflowStep) => plain(`${s.title} ${s.detail}`).toLowerCase();

function pinsAgainstSources(path: WorkflowStep[]) {
  for (const step of path) {
    expect(step.pins.length, step.title).toBeGreaterThan(0);
    expect(step.sources.length, step.title).toBeGreaterThan(0);
    for (const pin of step.pins) {
      expect(stepText(step), `${step.title}: "${pin}" is in the step's own text`).toContain(pin.toLowerCase());
      const inTree = step.sources.filter((s) => s.file !== SOP_SOURCE).map((s) => sourceText(s.file).toLowerCase());
      const inSop = step.sources.some((s) => s.file === SOP_SOURCE) && sop ? [sop.toLowerCase()] : [];
      const haystacks = [...inTree, ...inSop];
      if (haystacks.length === 0) continue; // SOP-only pin with no SOP on this machine: checked by the SOP block below
      expect(haystacks.some((t) => t.includes(pin.toLowerCase())), `${step.title}: "${pin}" appears in a cited source (${step.sources.map((s) => s.file).join(", ")})`).toBe(true);
    }
    for (const s of step.sources) {
      if (s.file === SOP_SOURCE) continue;
      expect(existsSync(resolve(SRC, s.file)), `${step.title}: cited source ${s.file} exists`).toBe(true);
      expect(sourceText(s.file), `${step.title}: ${s.file} contains "${s.quote}"`).toContain(plain(s.quote));
    }
  }
}

// ---------------------------------------------------------------------------
// The steps and their sources
// ---------------------------------------------------------------------------

describe("the refund path as it actually is today", () => {
  it("five steps: request → two-founder approval → execution disabled → manual Stripe Dashboard refund (SOP, draft) → webhook records the result", () => {
    expect(REFUND_PATH.map((s) => s.title)).toEqual([
      "Request refund",
      "Two-founder approval",
      "Execution disabled in production",
      "Manual Stripe Dashboard refund (SOP, draft)",
      "Webhook records the result",
    ]);
  });
  it("every phrase is pinned to the console's copy, the vocabulary or the SOP", () => pinsAgainstSources(REFUND_PATH));
  it("uses the reviewed labels verbatim and states that the SOP is a draft and that the console never calls Stripe", () => {
    const text = REFUND_PATH.map(stepText).join(" ");
    expect(text).toContain(ACTION_STATE_LABELS.awaiting_approval.toLowerCase());
    expect(text).toContain(PAYMENT_STATUS_LABELS.refunded.toLowerCase());
    expect(text).toContain("the console never calls stripe");
    expect(text).toContain("refund_execute_enabled");
    expect(text).toContain("draft");
    expect(text).toContain("not approved for use");
    // never a claim the refund settled: "refunded" appears only in the webhook's event name and the tile's noun
    expect(text).not.toMatch(/(?<!charge\.)\brefunded\b(?! payments)/);
    expect(text).not.toContain("money is back");
  });
});

describe("the payout release path", () => {
  it("four steps: seller_sent → release request → second founder approval → the payout worker", () => {
    expect(PAYOUT_RELEASE_PATH.map((s) => s.title)).toEqual([TRANSFER_STATUS_LABELS.seller_sent, "Request release", "Second founder approval", "Payout worker"]);
  });
  it("every phrase is pinned to the console's copy or the vocabulary", () => pinsAgainstSources(PAYOUT_RELEASE_PATH));
  it("uses the reviewed labels verbatim and never calls a connected-account transfer a bank payout or says the seller received money", () => {
    const text = PAYOUT_RELEASE_PATH.map(stepText).join(" ");
    expect(text).toContain(ACTION_TYPE_LABELS.payout_release.toLowerCase());
    expect(text).toContain(ACTION_STATE_LABELS.awaiting_approval.toLowerCase());
    expect(text).toContain(payoutStateLabel({ status: "buyer_confirmed", payout_released_at: "2026-01-01T00:00:00Z" }).toLowerCase());
    expect(text).toContain("not a bank payout");
    expect(text).not.toContain("received");
  });
});

describe("the SOP quotes, verified against the SOP file where it is checked out", () => {
  const sopSteps = [...REFUND_PATH, ...PAYOUT_RELEASE_PATH].flatMap((s) => s.sources.filter((x) => x.file === SOP_SOURCE).map((x) => ({ step: s.title, ...x })));
  it("the refund path cites the SOP for the manual step and the webhook, each quote placed in the document", () => {
    expect(sopSteps.length).toBeGreaterThanOrEqual(2);
    for (const s of sopSteps) expect(s.at, `${s.step}: ${s.quote}`).toBeTruthy();
    // the numbered sections are cited by number where the quote lives in one
    expect(sopSteps.some((s) => /§\d/.test(s.at ?? ""))).toBe(true);
  });
  it.skipIf(!sop)("each quoted sentence is in the SOP verbatim", () => {
    for (const s of sopSteps) expect(sop, `${s.step} (${s.at}): ${s.quote}`).toContain(plain(s.quote));
    expect(sop).toContain("DRAFT — not approved for use");
  });
  it("the SOP source is named with its branch so a reader can find it", () => {
    expect(SOP_SOURCE).toContain("docs/admin-console/MANUAL_REFUND_SOP.md");
    expect(SOP_SOURCE).toContain("admin/manual-refund-sop");
  });
});

// ---------------------------------------------------------------------------
// Accessible structure
// ---------------------------------------------------------------------------

describe("WorkflowDiagram — an inline SVG with role=img, title + desc, and a visually hidden text list", () => {
  const html = h(createElement(WorkflowDiagram, { id: "refund-path", title: "Refund path", description: "How a refund happens today.", steps: REFUND_PATH }));
  it("the svg is labelled by its own title and desc, scales with its container and is not focusable", () => {
    expect(html).toMatch(/<svg[^>]*role="img"/);
    expect(html).toMatch(/<svg[^>]*aria-labelledby="refund-path-title refund-path-desc"/);
    expect(html).toContain('<title id="refund-path-title">Refund path</title>');
    expect(html).toContain('<desc id="refund-path-desc">How a refund happens today.</desc>');
    expect(html).toMatch(/<svg[^>]*viewBox="0 0 \d+ \d+"/);
    expect(html).toMatch(/<svg[^>]*class="[^"]*\bw-full\b[^"]*"/);
    expect(html).toMatch(/<svg[^>]*class="[^"]*\bmax-w-full\b[^"]*"/);
    expect(html).toMatch(/<svg[^>]*class="[^"]*\bh-auto\b[^"]*"/);
    expect(html).toMatch(/<svg[^>]*focusable="false"/);
    expect(html).not.toMatch(/<svg[\s\S]*<a [\s\S]*<\/svg>/);
  });
  it("every step is drawn and listed: numbered boxes in the svg, the same titles in a visually hidden ordered list with each step's source", () => {
    const svg = html.slice(html.indexOf("<svg"), html.indexOf("</svg>"));
    const list = html.slice(html.indexOf("<ol"), html.indexOf("</ol>"));
    expect(list).toMatch(/<ol[^>]*class="[^"]*\bsr-only\b/);
    expect(list.match(/<li/g)?.length).toBe(REFUND_PATH.length);
    for (const s of REFUND_PATH) {
      expect(svg, s.title).toContain(s.title.replace(/'/g, "&#x27;"));
      expect(list, s.title).toContain(s.title.replace(/'/g, "&#x27;"));
      expect(list, s.title).toContain(plain(s.detail).replace(/'/g, "&#x27;").replace(/"/g, "&quot;"));
      for (const src of s.sources) expect(list, `${s.title} cites ${src.file}`).toContain(src.file);
    }
    expect(svg.match(/<text/g)?.length).toBeGreaterThanOrEqual(REFUND_PATH.length * 2);
    // one arrow between each pair of steps
    expect(svg.match(/data-arrow=""/g)?.length).toBe(REFUND_PATH.length - 1);
  });
  it("step detail is wrapped into lines that fit the box, never splitting a word", () => {
    expect(wrapLines("a b c", 3)).toEqual(["a b", "c"]);
    expect(wrapLines("supercalifragilistic word", 8)).toEqual(["supercalifragilistic", "word"]);
    expect(wrapLines("", 10)).toEqual([]);
    for (const s of [...REFUND_PATH, ...PAYOUT_RELEASE_PATH]) {
      for (const line of wrapLines(s.detail, 58)) expect(line.length, `${s.title}: "${line}"`).toBeLessThanOrEqual(58);
      expect(wrapLines(s.detail, 58).join(" ")).toBe(s.detail);
    }
  });
  it("the footnote says where the steps come from and that nothing here is a new rule", () => {
    expect(html).toContain("manual refund SOP (draft");
    expect(html).toContain("nothing here is a new rule");
  });
});

// ---------------------------------------------------------------------------
// Placement: the order page, collapsed, next to the actions; OrderActions untouched
// ---------------------------------------------------------------------------

const PAY = "9a900000-0000-4000-8000-0000000000d4";
const TR = "7a000000-0000-4000-8000-0000000000d4";
type Row = Record<string, unknown>;
const page = (items: Row[]) => ({ ok: true, data: { items, next_cursor: null, count_hint: items.length } });
function orderDetail() {
  return {
    payment: { id: PAY, status: "succeeded", total: 9900, amount: 9000, buyer_fee: 900, seller_fee: 450, stripe_livemode: true },
    transfer: { id: TR, payment_id: PAY, status: "seller_sent", payout_review_status: "manual_review", payout_released_at: null, disputed_at: null },
    listing: { id: "1a000000-0000-4000-8000-0000000000d4", event_name: "Fixture night" },
    buyer: null,
    seller: null,
    disputes: [],
    dispute_resolutions: [],
    payout_decisions: [],
    refund: { payment_status: "succeeded", refund_actions: [] },
    seller_funds_state: "held",
    cases: [],
    actions: [],
    evidence: {},
    bank_payout: { tracked: false, note: null },
  };
}

describe("HowThisWorks on the order page", () => {
  beforeEach(() => {
    mocks.callOps.mockReset();
    mocks.requireOperator.mockReset();
    mocks.callOps.mockImplementation(async (fn: string) => {
      if (fn === "order_detail") return { ok: true, data: orderDetail() };
      if (fn === "order_timeline") return { ok: true, data: { events: [] } };
      if (fn === "settings") return { ok: true, data: [{ key: "refund_execute_enabled", value: false }] };
      if (fn === "list_actions") return page([]);
      return { ok: false, kind: "error", message: `unexpected ${fn}` };
    });
    mocks.requireOperator.mockResolvedValue({ id: "f0000000-0000-4000-8000-0000000000a1", role: "platform_admin" });
  });

  it("a collapsed disclosure in the actions column, after the action panels, holding both diagrams", async () => {
    const html = h(await OrderPage({ params: Promise.resolve({ paymentId: PAY }) }));
    const summary = html.match(/<details[^>]*>\s*<summary[^>]*>[^<]*How this works/);
    expect(summary).not.toBeNull();
    expect(summary![0]).not.toContain(" open");
    expect(html.indexOf("How this works")).toBeGreaterThan(html.indexOf("Safe actions"));
    expect(html.indexOf("How this works")).toBeGreaterThan(html.indexOf("Execute refund"));
    expect(html).toContain('aria-labelledby="refund-path-title refund-path-desc"');
    expect(html).toContain('aria-labelledby="payout-release-path-title payout-release-path-desc"');
    // the money forms and their guard copy are exactly as before
    const forms = html.split("<form").slice(1).map((f) => f.match(/name="action_type" value="([^"]*)"/)?.[1]);
    expect(forms.filter((t) => t === "payout_release" || t === "refund_execute")).toEqual(["payout_release", "refund_execute"]);
    expect(html).toContain("Disabled until ops-refund-execute is deployed.");
  });

  it("OrderActions itself is untouched: it neither imports nor renders the diagrams", () => {
    const s = readFileSync(resolve(SRC, "components/orders/OrderActions.tsx"), "utf8");
    expect(s).not.toContain("WorkflowDiagram");
    expect(s).not.toContain("How this works");
    expect(h(createElement(HowThisWorks))).toContain("How this works");
  });
});
