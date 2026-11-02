import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

/**
 * Snatch It operates in Eastern Time (owner decision, 2026-11-02). Dates and times the web shows a buyer or
 * seller are Miami (America/New_York) dates, never the runtime zone: the web server runs on UTC and a
 * browser can run anywhere.
 *
 * Every anchor is a PAIR around Eastern midnight, so a fallback to UTC or to Los Angeles fails at least one
 * side. Modules load fresh under each runtime zone: a formatter built at import keeps the zone it was built
 * in, and a Miami development machine runs America/New_York, which would hide a fallback.
 */
const ORIGINAL_TZ = process.env.TZ;
afterAll(() => {
  if (ORIGINAL_TZ === undefined) delete process.env.TZ;
  else process.env.TZ = ORIGINAL_TZ;
});

async function load(tz: string) {
  process.env.TZ = tz;
  vi.resetModules();
  return import("@/lib/listing-display");
}

const live = (ends_at: string) => ({ id: "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d", status: "active", auction_status: "active", ends_at }) as never;

describe("NEGATIVE CONTROL — the two runtime zones really differ", () => {
  it("a formatter with no timeZone gives a different day under UTC and Los Angeles", () => {
    const seen = ["UTC", "America/Los_Angeles"].map((tz) => {
      process.env.TZ = tz;
      return new Date("2026-11-02T04:59:59Z").toLocaleDateString("en-US");
    });
    expect(seen[0]).not.toBe(seen[1]);
  });
});

for (const tz of ["UTC", "America/Los_Angeles"]) {
  describe(`runtime zone ${tz}`, () => {
    let m: Awaited<ReturnType<typeof load>>;
    beforeAll(async () => {
      m = await load(tz);
    });

    it("today in Miami, on both sides of Eastern midnight (EST and EDT)", () => {
      expect(m.marketDateISO(new Date("2026-11-02T04:59:59Z"))).toBe("2026-11-01");
      expect(m.marketDateISO(new Date("2026-11-02T05:00:00Z"))).toBe("2026-11-02");
      expect(m.marketDateISO(new Date("2026-11-01T03:59:59Z"))).toBe("2026-10-31");
      expect(m.marketDateISO(new Date("2026-11-01T04:00:00Z"))).toBe("2026-11-01");
    });

    it("the footer year turns at Eastern midnight", () => {
      expect(m.marketYear(new Date("2027-01-01T04:59:59Z"))).toBe(2026);
      expect(m.marketYear(new Date("2027-01-01T05:00:00Z"))).toBe(2027);
    });

    it("'Member since' and 'Sold' dates are Miami dates", () => {
      expect(m.marketMonthYear("2026-11-01T03:59:59Z")).toBe("October 2026");
      expect(m.marketMonthYear("2026-11-01T04:00:00Z")).toBe("November 2026");
      expect(m.marketShortDate("2026-11-02T04:59:59Z")).toBe("Nov 1");
      expect(m.marketShortDate("2026-11-02T05:00:00Z")).toBe("Nov 2");
    });

    it("the auction clock prints its EST/EDT label", () => {
      const now = (iso: string) => new Date(new Date(iso).getTime() - 3 * 24 * 3_600_000);
      expect(m.clockState(live("2026-11-02T04:59:00Z"), now("2026-11-02T04:59:00Z")).text).toBe("Ends Sun, 11:59 PM EST");
      expect(m.clockState(live("2026-11-01T03:59:00Z"), now("2026-11-01T03:59:00Z")).text).toBe("Ends Sat, 11:59 PM EDT");
      expect(m.clockState(live("2026-03-08T07:30:00Z"), now("2026-03-08T07:30:00Z")).text).toBe("Ends Sun, 3:30 AM EDT");
    });
  });
}

describe("no page or component formats a date in the runtime zone", () => {
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.(ts|tsx)$/.test(name)) files.push(p);
    }
  };
  walk(resolve(__dirname, "../src/app"));
  walk(resolve(__dirname, "../src/components"));

  it("no toLocaleDateString / toLocaleTimeString / getFullYear / UTC-date slicing; every Intl.DateTimeFormat names a zone", () => {
    const bad: string[] = [];
    for (const f of files) {
      const s = readFileSync(f, "utf8");
      if (/toLocale(Date|Time)String\(|\.getFullYear\(\)|toISOString\(\)\.slice\(0,\s*10\)/.test(s)) bad.push(f);
      for (const mt of s.matchAll(/new Intl\.DateTimeFormat\(([^)]*)\)/g)) if (!/timeZone/.test(mt[1])) bad.push(f);
    }
    expect(bad).toEqual([]);
  });
});
