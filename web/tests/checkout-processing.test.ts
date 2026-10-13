import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { PAYMENT_STILL_PROCESSING } from "@/lib/checkout-wording";

// Stripe returns to /checkout/[id]/complete with redirect_status "processing" when a payment
// has not settled yet. That is an UNKNOWN outcome: the page must not call it a failure or send
// the buyer back to pay again. The page is a client component, so its branch is read from source.
const PAGE = readFileSync(path.resolve(__dirname, "../src/app/checkout/[id]/complete/page.tsx"), "utf8");

describe("payment return page: processing is not a failure", () => {
  it("routes redirect_status=processing to its own pending state before the failure branch", () => {
    expect(PAGE).toMatch(/const stillProcessing = redirectStatus === "processing" && !!paymentIntentId;/);
    expect(PAGE).toMatch(/stillProcessing \? "pending" : failedUpfront \? "error" : "processing"/);
    expect(PAGE).toMatch(/stillProcessing\s*\? PAYMENT_STILL_PROCESSING/);
  });

  it("the pending state points at purchases, never back to the listing", () => {
    const pending = PAGE.slice(PAGE.indexOf('if (status === "pending")'), PAGE.indexOf('if (status === "error")'));
    expect(pending).toContain('router.push("/account/purchases")');
    expect(pending).not.toContain("/listing/");
  });

  it("says nothing failed and does not invite paying again", () => {
    expect(PAYMENT_STILL_PROCESSING).not.toMatch(/fail|try again|did not complete/i);
  });
});
