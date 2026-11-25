import { createElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { SaleView } from "@/lib/sales";

const mocks = vi.hoisted(() => ({ sales: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth/session", () => ({ getAuthedUser: async () => ({ id: "seller" }) }));
vi.mock("@/lib/sales", async (original) => ({
  ...await original<typeof import("@/lib/sales")>(), getMySales: mocks.sales,
}));
vi.mock("next/link", () => ({ default: ({ href, children, ...props }: { href: string; children: ReactNode }) => createElement("a", { href, ...props }, children) }));
vi.mock("@/components/account/AccountHeader", () => ({ AccountHeader: ({ title }: { title: string }) => createElement("h1", null, title) }));
import SalesPage from "@/app/account/sales/page";

const sale = (patch: Partial<SaleView> = {}): SaleView => ({
  id: "sale", listing_id: "listing", status: "auto_released", createdAt: null,
  soldAtLabel: null, eventName: "Event", venue: "Venue", coverImagePath: "", buyerName: null,
  grossCents: 200, netCents: 180, paymentStatus: "succeeded", payoutReleasedAt: null,
  payoutReviewStatus: null, payoutHoldUntil: null, autoReleaseAt: null,
  disputeResolution: null, disputeResolvedAt: null, buyerConfirmedAt: null, ...patch,
});
const release = "2026-11-25T16:00:00Z";
async function summary(rows: SaleView[]) {
  mocks.sales.mockResolvedValue(rows);
  const html = renderToStaticMarkup(await SalesPage());
  return html.match(/<dl\b[^>]*>([\s\S]*?)<\/dl>/)?.[1] ?? "";
}

describe("seller release summary does not claim bank deposits", () => {
  beforeEach(() => vi.clearAllMocks());

  it("counts recorded releases, excludes reversals, and does not sum estimated seller net", async () => {
    const html = await summary([
      sale({ id: "released", payoutReleasedAt: release }),
      sale({ id: "unknown-net", payoutReleasedAt: release, netCents: null }),
      sale({ id: "decision-only" }),
      sale({ id: "reversed", status: "reversed", payoutReleasedAt: release }),
    ]);
    expect(html).toMatch(/Sales released to Stripe<\/dt><dd[^>]*>2<\/dd>/);
    expect(html).not.toMatch(/Paid out|\$|USD/);
    expect(html).toContain("Bank arrival is not shown here.");
  });

  it("a release decision without transfer evidence contributes zero", async () => {
    const html = await summary([sale(), sale({ id: "confirmed", status: "buyer_confirmed" })]);
    expect(html).toMatch(/Sales released to Stripe<\/dt><dd[^>]*>0<\/dd>/);
  });

  it("expired and reversed rows do not promise their original sale amount to the seller", async () => {
    mocks.sales.mockResolvedValue([sale({ status: "expired" }), sale({ id: "reversed", status: "reversed", payoutReleasedAt: release })]);
    const html = renderToStaticMarkup(await SalesPage());
    expect(html).toContain("no payout for this order");
    expect(html).toContain("Payout reversed");
    expect(html).not.toContain("to you");
    expect(html).toContain("Original seller amount");
    expect(html).not.toContain("Seller amount unavailable");
    expect(html).toContain("Amounts shown are before refunds or reversals.");
  });

  it("unknown seller amounts are unavailable, never a zero payout", async () => {
    mocks.sales.mockResolvedValue([sale({ netCents: null })]);
    const html = renderToStaticMarkup(await SalesPage());
    expect(html).toContain("Seller amount unavailable");
    expect(html).not.toContain("$0");
  });
});
