import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ usePathname: () => "/orders", useRouter: () => ({ push: () => {} }) }));
vi.mock("server-only", () => ({}));

import { splitLabel, StatusBadge } from "@/components/ui/StatusBadge";
import { OrderTable } from "@/components/orders/OrderTable";
import { list } from "@/lib/search-params";
import { FUNDS_STATE_LABELS, PAYMENT_STATUS_LABELS, TRANSFER_STATUS_LABELS } from "@/lib/format";
import type { OrderRow } from "@/lib/types";

const words = (s: string) => s.replace(/[()—]/g, " ").split(/\s+/).filter(Boolean);

/**
 * The v2 layout moves a label's qualifier ("not confirmed settled") under its
 * pill. The reviewed wording is A's; layout may change, words may not.
 */
describe("status qualifiers move, never disappear", () => {
  const vocab = { ...PAYMENT_STATUS_LABELS, ...TRANSFER_STATUS_LABELS, ...FUNDS_STATE_LABELS };

  it("every reviewed label splits into head + qualifier with no word lost", () => {
    for (const [key, label] of Object.entries(vocab)) {
      const { head, tail } = splitLabel(label);
      expect(words(`${head} ${tail ?? ""}`), key).toEqual(words(label));
    }
  });

  it("splits on a trailing parenthetical and on an em dash, and leaves plain labels alone", () => {
    expect(splitLabel("Refund recorded (not confirmed settled)")).toEqual({ head: "Refund recorded", tail: "not confirmed settled" });
    expect(splitLabel("Release scheduled — Stripe Transfer pending")).toEqual({ head: "Release scheduled", tail: "Stripe Transfer pending" });
    expect(splitLabel("Captured")).toEqual({ head: "Captured", tail: null });
  });

  it("the badge renders the qualifier only when asked to move it, and the full text either way", () => {
    const inline = renderToStaticMarkup(createElement(StatusBadge, { status: "refunded", label: PAYMENT_STATUS_LABELS.refunded }));
    const below = renderToStaticMarkup(createElement(StatusBadge, { status: "refunded", label: PAYMENT_STATUS_LABELS.refunded, qualifier: "below" }));
    expect(inline).toContain("Refund recorded (not confirmed settled)");
    expect(below).toContain("Refund recorded");
    expect(below).toContain("not confirmed settled");
    expect(below).not.toContain("(not confirmed settled)");
  });
});

describe("order rows keep the reviewed vocabulary and the references", () => {
  const row: OrderRow = {
    payment_id: "9a900000-0000-4000-8000-000000000013",
    created_at: "2026-10-01T12:00:00Z",
    payment_status: "refunded",
    amount: 4000,
    total: 4400,
    stripe_payment_intent_id: "pi_test_000013",
    event_name: "Little Havana Block Party",
    transfer_id: "7a000000-0000-4000-8000-000000000013",
    transfer_status: "buyer_confirmed",
    buyer_confirmed_at: null,
    seller_funds_state: "refund_pending",
    open_cases: 2,
    buyer: { id: "b0000000-0000-4000-8000-000000000003", display_name: "Ava Chen" },
    seller: { id: "5e11e000-0000-4000-8000-000000000002", display_name: "Sofia Reyes" },
  };
  const html = renderToStaticMarkup(createElement(OrderTable, { rows: [row], basePath: "/orders" }));

  it("says what the money did, in A's words", () => {
    expect(html).toContain("Refund recorded");
    expect(html).toContain("not confirmed settled");
    expect(html).toContain("Refund owed to buyer");
    expect(html).toContain("not yet executed");
  });

  it("uses the row-aware transfer label, not the bare status map", () => {
    // buyer_confirmed with no confirmation timestamp is NOT a buyer confirmation (transferStateLabel).
    expect(html).toContain("Confirmed status, no confirmation record");
    expect(html).not.toContain(">Buyer confirmed<");
  });

  it("keeps the order, payment and Stripe references and the open-case link", () => {
    expect(html).toContain('href="/orders/9a900000-0000-4000-8000-000000000013"');
    expect(html).toContain("pi_test_000013");
    expect(html).toContain('href="/cases?subject_id=9a900000-0000-4000-8000-000000000013"');
    expect(html).toContain("2 open cases");
  });
});

describe("multi-value filters", () => {
  it("accepts repeated keys (checkbox groups) as well as comma lists", () => {
    expect(list(["succeeded", "refunded"])).toEqual(["succeeded", "refunded"]);
    expect(list("succeeded,refunded")).toEqual(["succeeded", "refunded"]);
    expect(list(["succeeded,failed", "refunded"])).toEqual(["succeeded", "failed", "refunded"]);
    expect(list(undefined)).toBeUndefined();
    expect(list("")).toBeUndefined();
  });
});

describe("a failed read says what was lost, keeps the reason, offers recovery", () => {
  it("leads with the subject, keeps the database reason and code for support, and links Try again", async () => {
    const { OpsFailureAlert } = await import("@/components/ui/Alert");
    const failure = { ok: false as const, kind: "error" as const, message: "canceling statement due to statement timeout", code: "57014" };
    const led = renderToStaticMarkup(createElement(OpsFailureAlert, { failure, fn: "list_orders", retryHref: "/orders", subject: "Orders" }));
    expect(led).toContain("Orders couldn&#x27;t be loaded.");
    expect(led).toContain("canceling statement due to statement timeout");
    expect(led).toContain("57014");
    expect(led).toMatch(/href="\/orders"[^>]*>Try again|>Try again/);
    expect(led).toContain('role="alert"');
    // Without a subject the shared wording elsewhere in the console is unchanged.
    const plain = renderToStaticMarkup(createElement(OpsFailureAlert, { failure, retryHref: "/x" }));
    expect(plain).toContain("Request failed");
    expect(plain).not.toContain("couldn&#x27;t be loaded");
  });
});

describe("a person in a record reads as a name, never as JSON", () => {
  it("renders { id, display_name } as a link to the user, at any depth", async () => {
    const { renderValue } = await import("@/components/generic/GenericRpc");
    const party = { id: "b0000000-0000-4000-8000-000000000002", display_name: "Jordan Kim" };
    for (const depth of [0, 1]) {
      const html = renderToStaticMarkup(createElement("div", null, renderValue("buyer", party, depth)));
      expect(html).toContain('href="/users/b0000000-0000-4000-8000-000000000002"');
      expect(html).toContain("Jordan Kim");
      expect(html).not.toContain("display_name");
    }
    // Other objects keep their generic rendering.
    const other = renderToStaticMarkup(createElement("div", null, renderValue("meta", { a: 1, b: 2 }, 1)));
    expect(other).toContain("&quot;a&quot;");
  });
});
