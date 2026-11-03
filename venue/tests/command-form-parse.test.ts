import { describe, expect, it } from "vitest";
import { capacity, dollarsToCents, kind, rank, visibility } from "@/lib/db/command-form-parse";

describe("dollars → integer cents, the server's unit", () => {
  it("accepts whole dollars, one or two decimals, a leading $ and thousands commas", () => {
    expect(dollarsToCents("25")).toEqual({ ok: true, value: 2500 });
    expect(dollarsToCents("25.5")).toEqual({ ok: true, value: 2550 });
    expect(dollarsToCents("25.05")).toEqual({ ok: true, value: 2505 });
    expect(dollarsToCents("$1,250.99")).toEqual({ ok: true, value: 125099 });
    expect(dollarsToCents("0.01")).toEqual({ ok: true, value: 1 });
  });
  it("refuses zero, negatives, three decimals, words and empty — before any call", () => {
    for (const bad of ["0", "0.00", "-5", "1.005", "ten", "", "1e3", "25.", ".5"]) expect(dollarsToCents(bad).ok, bad).toBe(false);
    const z = dollarsToCents("0");
    expect(!z.ok && z.message).toContain("at least $0.01");
  });
  it("never produces a float: no 19.99 → 1998.9999 rounding path", () => {
    expect(dollarsToCents("19.99")).toEqual({ ok: true, value: 1999 });
    expect(dollarsToCents("0.29")).toEqual({ ok: true, value: 29 });
  });
});

describe("rank, capacity, kind, visibility", () => {
  it("rank is 0–999 whole; capacity is 0 or more whole; kinds and visibilities are the server's enums", () => {
    expect(rank("0")).toEqual({ ok: true, value: 0 });
    expect(rank("999")).toEqual({ ok: true, value: 999 });
    for (const bad of ["1000", "-1", "1.5", "", "x"]) expect(rank(bad).ok, bad).toBe(false);
    expect(capacity("300")).toEqual({ ok: true, value: 300 });
    expect(capacity("0")).toEqual({ ok: true, value: 0 });
    for (const bad of ["-1", "3.5", "", "many"]) expect(capacity(bad).ok, bad).toBe(false);
    expect(kind("table")).toEqual({ ok: true, value: "table" });
    expect(kind("vip").ok).toBe(false);
    expect(visibility("door_only")).toEqual({ ok: true, value: "door_only" });
    expect(visibility("secret").ok).toBe(false);
  });
});
