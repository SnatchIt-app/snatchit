import { describe, expect, it } from "vitest";
import { formatMoney, formatRelative, formatUtc } from "../src/lib/format";

describe("formatMoney", () => {
  it("formats integer cents as USD with the explicit currency code", () => {
    expect(formatMoney(0)).toBe("$0.00 USD");
    expect(formatMoney(1)).toBe("$0.01 USD");
    expect(formatMoney(123456)).toBe("$1,234.56 USD");
    expect(formatMoney(-2500)).toBe("-$25.00 USD");
    expect(formatMoney("7999")).toBe("$79.99 USD");
  });

  it("renders a dash for anything that is not integer cents", () => {
    for (const v of [null, undefined, "", "abc", 12.5, NaN, Infinity, {}, [], true]) {
      expect(formatMoney(v)).toBe("—");
    }
  });
});

describe("time formatters", () => {
  it("prints UTC with an explicit basis", () => {
    expect(formatUtc("2026-09-06T18:45:07Z")).toBe("2026-09-06 18:45 UTC");
    expect(formatUtc("2026-09-06T18:45:07Z", true)).toBe("2026-09-06 18:45:07 UTC");
    expect(formatUtc("nope")).toBe("—");
  });

  it("gives coarse relative times in both directions", () => {
    const now = new Date("2026-09-06T12:00:00Z");
    expect(formatRelative("2026-09-06T11:59:50Z", now)).toBe("just now");
    expect(formatRelative("2026-09-06T11:56:00Z", now)).toBe("4m ago");
    expect(formatRelative("2026-09-06T15:00:00Z", now)).toBe("in 3h");
    expect(formatRelative("2026-09-04T12:00:00Z", now)).toBe("2d ago");
  });
});
