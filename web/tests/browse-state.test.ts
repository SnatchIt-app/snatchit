import { describe, expect, it } from "vitest";
import { isNarrowed } from "@/lib/browse-state";

describe("isNarrowed: a search or a filter narrows the feed; a sort does not", () => {
  it("is false for the plain feed, whatever the sort", () => {
    expect(isNarrowed({})).toBe(false);
    expect(isNarrowed({ sort: "price_asc" })).toBe(false);
  });
  it("is true for a search or any filter", () => {
    expect(isNarrowed({ q: "neon" })).toBe(true);
    expect(isNarrowed({ category: "clubs" })).toBe(true);
    expect(isNarrowed({ neighborhood: "wynwood" })).toBe(true);
    expect(isNarrowed({ type: "buy_now" })).toBe(true);
    expect(isNarrowed({ maxPrice: 100 })).toBe(true);
  });
});
