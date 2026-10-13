import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import * as W from "@/lib/policy-wording";
import { CONFIRM_OUTCOME_UNKNOWN } from "@/lib/transfers";

// FU-4: the web app's policy sentences are POLICY_WORDING.md's (owner ruling 2026-10-13),
// verbatim, and the claims that ruling withdrew appear nowhere in web/src.
vi.mock("server-only", () => ({}));

const SRC = path.resolve(__dirname, "../src");

function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) return sources(full);
    return /\.(tsx?|mdx?)$/.test(name) ? [full] : [];
  });
}

const ALL = sources(SRC).map((f) => ({ f: path.relative(SRC, f), text: readFileSync(f, "utf8") }));

describe("canonical sentences (POLICY_WORDING.md)", () => {
  it("are verbatim", () => {
    expect(W.REFUND_SHORT).toBe(
      "If the seller doesn't send within 24 hours, the order is cancelled and a full refund is issued automatically.",
    );
    expect(W.PAYOUT_SHORT).toBe(
      "The seller isn't paid until you confirm your tickets arrived, or until the 72-hour window passes and the order clears Snatch It's risk checks.",
    );
    expect(W.REPORT_FREEZES_PAYOUT).toBe("Reporting a problem freezes the seller's payout while we review.");
    expect(W.SELLER_TERMS).toBe(
      "You keep 90% of the sale price. Your payout starts when the buyer confirms, or after the 72-hour window and Snatch It's risk checks.",
    );
    expect(W.PAYOUT_CONNECTED).toBe(
      "Your account is connected. After an order is released, we send your payout (the sale price, less the seller fee and any refund) to your Stripe account.",
    );
    expect(W.REPORT_CONFIRM).toBe("Report a problem? This freezes the seller's payout and opens a case for our team.");
    expect(W.SELLER_MISSED_DEADLINE).toBe(
      "Miss it and the order is cancelled and the buyer's refund is issued automatically.",
    );
  });

  it("are each used by a screen", () => {
    const users = (name: string) => ALL.filter(({ f, text }) => f !== "lib/policy-wording.ts" && text.includes(name));
    for (const name of Object.keys(W)) expect(users(name).length, name).toBeGreaterThan(0);
  });
});

describe("withdrawn claims (owner ruling 2026-10-13)", () => {
  const WITHDRAWN: [string, RegExp][] = [
    ["unconditional refund", /you're refunded (in full, )?automatically/i],
    ["auto-refund without the cancellation", /buyer is refunded automatically/i],
    ["payout on sale", /deposited automatically when/i],
    ["payout only on confirmation", /paid only after you confirm/i],
    ["money held by Snatch It", /money is held by Snatch It/i],
    ["fee base unnamed", /90% of the sale(?! price)/i],
    ["funds held until delivery", /funds held until/i],
    ["report notifies support", /notifies support/i],
    ["unproven non-release", /nothing was (charged or )?released/i],
    ["turnaround promise", /within a few business days/i],
    ["instant claims", /\binstantly\b|no human involved/i],
  ];
  for (const [what, re] of WITHDRAWN) {
    it(`no screen says: ${what}`, () => {
      const hits = ALL.filter(({ text }) =>
        text
          .split("\n")
          .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
          .some((l) => re.test(l)),
      ).map(({ f }) => f);
      expect(hits).toEqual([]);
    });
  }

  it("a confirmation whose outcome is unknown says so, and offers a safe retry", () => {
    expect(CONFIRM_OUTCOME_UNKNOWN).toMatch(/couldn't tell whether/);
    expect(CONFIRM_OUTCOME_UNKNOWN).not.toMatch(/nothing|charged|released/i);
  });
});
