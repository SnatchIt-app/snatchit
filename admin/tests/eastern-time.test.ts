import { createElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

/**
 * Snatch It operates in Eastern Time (owner decision, 2026-11-02; A/TIMEZONE-DECISION-20261102.md).
 * Every time the console shows a person is America/New_York with its EST/EDT label. Canonical
 * instants stay UTC (the <time dateTime> attribute). Report DAYS stay what the server counts — UTC
 * calendar days until registry 200 — so their labels must not move to Eastern yet.
 *
 * Each check runs under two runtime zones. The negative control proves the runtime zone really
 * changes between them, so a formatter that fell back to it would fail here.
 */
vi.mock("server-only", () => ({}));

// For the source sweep and the cron check only; the zone checks load fresh modules per zone (see load()).
import { formatEt } from "@/lib/format";

/**
 * Set the runtime zone, THEN load fresh modules. A formatter built at module load keeps the zone it was
 * built in, so switching TZ after import proves nothing — and this machine runs America/New_York, which
 * would hide a formatter that fell back to the runtime zone. Both zones below differ from New York.
 */
async function load(tz: string) {
  process.env.TZ = tz;
  vi.resetModules();
  const [format, figureMeta, dateTime, figure, generic] = await Promise.all([
    import("@/lib/format"),
    import("@/lib/figure-meta"),
    import("@/components/ui/DateTime"),
    import("@/components/charts/FigureMeta"),
    import("@/components/generic/GenericRpc"),
  ]);
  return { ...format, ...figureMeta, ...dateTime, ...figure, ...generic };
}

const ORIGINAL_TZ = process.env.TZ;
afterAll(() => {
  if (ORIGINAL_TZ === undefined) delete process.env.TZ;
  else process.env.TZ = ORIGINAL_TZ;
});
const ZONES = ["UTC", "America/Los_Angeles"] as const;
const html = (n: ReactNode) => renderToStaticMarkup(createElement("div", null, n));

/** D's discriminating anchors, plus the repeated and the skipped hour. */
const ANCHORS: [string, string][] = [
  ["2026-11-02T04:59:59Z", "2026-11-01 23:59:59 EST"], // last second of Nov 1 in ET (EST)
  ["2026-11-02T05:00:00Z", "2026-11-02 00:00:00 EST"], // ET midnight, EST
  ["2026-11-01T03:59:59Z", "2026-10-31 23:59:59 EDT"], // last second of Oct 31 in ET (EDT)
  ["2026-11-01T04:00:00Z", "2026-11-01 00:00:00 EDT"], // ET midnight, EDT — Nov 1 is a 25 h day
  ["2026-11-01T05:30:00Z", "2026-11-01 01:30:00 EDT"], // 01:30 happens twice on Nov 1 …
  ["2026-11-01T06:30:00Z", "2026-11-01 01:30:00 EST"], // … the label tells them apart
  ["2026-03-08T06:59:59Z", "2026-03-08 01:59:59 EST"], // spring forward: 02:00-02:59 does not exist
  ["2026-03-08T07:00:00Z", "2026-03-08 03:00:00 EDT"], // Mar 8 is a 23 h day
];

describe("NEGATIVE CONTROL — the two runtime zones really differ", () => {
  it("a formatter with no timeZone gives different text under UTC and Los Angeles", () => {
    const seen = ZONES.map((tz) => {
      process.env.TZ = tz;
      return new Date("2026-11-02T04:59:59Z").toLocaleString("en-US");
    });
    expect(seen[0]).not.toBe(seen[1]);
  });
});

for (const tz of ZONES) {
  describe(`runtime zone ${tz}`, () => {
    let m: Awaited<ReturnType<typeof load>>;
    beforeAll(async () => {
      m = await load(tz);
    });

    it("formatEt prints Eastern wall clock with EST/EDT at every anchor", () => {
      expect(m.DISPLAY_TIME_ZONE).toBe("America/New_York");
      for (const [iso, want] of ANCHORS) expect(m.formatEt(iso, true), iso).toBe(want);
      expect(m.formatEt("2026-11-02T04:59:59Z")).toBe("2026-11-01 23:59 EST");
      expect(m.formatEt("nope")).toBe("—");
      expect(m.formatEt(null)).toBe("—");
    });

    it("DateTime shows Eastern text and keeps the UTC instant in dateTime", () => {
      const out = html(createElement(m.DateTime, { value: "2026-11-02T04:59:59Z", relative: false }));
      expect(out).toContain("2026-11-01 23:59 EST");
      expect(out).toContain('dateTime="2026-11-02T04:59:59.000Z"');
      expect(out).not.toContain(" UTC");
    });

    it("TimeAgo puts the Eastern time in its hover", () => {
      expect(html(createElement(m.TimeAgo, { value: "2026-11-01T04:00:00Z" }))).toContain('title="2026-11-01 00:00:00 EDT"');
    });

    it("a zone-less date-time is read as UTC (the database's zone), never the runtime zone", () => {
      expect(m.parseDate("2026-11-01T12:00")?.toISOString()).toBe("2026-11-01T12:00:00.000Z");
      expect(m.parseDate("2026-11-01 12:00:30")?.toISOString()).toBe("2026-11-01T12:00:30.000Z");
      // an explicit offset is kept as given
      expect(m.parseDate("2026-11-01T12:00:00-04:00")?.toISOString()).toBe("2026-11-01T16:00:00.000Z");
    });

    it("a calendar date is shown as written, not shifted to the day before", () => {
      const out = html(m.renderValue("event_date", "2026-11-05", 1));
      expect(out).toContain("2026-11-05");
      expect(out).not.toContain("2026-11-04");
      expect(out).not.toContain("<time");
    });

    it("an instant under an _until or _by key renders as an Eastern time", () => {
      expect(html(m.renderValue("payout_hold_until", "2026-11-02T04:59:59+00:00", 1))).toContain("2026-11-01 23:59 EST");
      expect(html(m.renderValue("evidence_due_by", "2026-03-08T07:00:00+00:00", 1))).toContain("2026-03-08 03:00 EDT");
      // a uuid under a *_by key is still a link or id, not a time
      expect(html(m.renderValue("resolved_by", "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d", 1))).not.toContain("<time");
    });

    it("the figure line: the as-of time is Eastern; the report DAY stays the server's UTC day (registry 200 not applied)", () => {
      expect(m.asOfLabel("2026-11-02T04:59:59Z", new Date())).toBe("as of 2026-11-01 23:59:59 EST");
      expect(m.REPORT_DAY_BASIS).toBe("UTC");
      const out = html(createElement(m.FigureMeta, { range: { from: "2026-10-03", to: "2026-11-01" }, computedAt: "2026-11-02T04:59:59Z", readAt: new Date("2026-11-02T05:00:00Z") }));
      expect(out).toContain("UTC calendar days");
      expect(out).toContain("as of 2026-11-01 23:59:59 EST");
      // never relabel UTC report data as Eastern before the server counts Eastern days
      expect(out).not.toMatch(/(ET|EST|EDT|Eastern) calendar day/);
    });
  });
}

describe("the cron label states a fact that holds all year", () => {
  it("13:00 UTC is 8:00 AM EST in winter and 9:00 AM EDT in summer", () => {
    expect(formatEt("2026-01-15T13:00:00Z")).toBe("2026-01-15 08:00 EST");
    expect(formatEt("2026-07-15T13:00:00Z")).toBe("2026-07-15 09:00 EDT");
    const page = readFileSync(resolve(__dirname, "../src/app/(console)/system/page.tsx"), "utf8");
    expect(page).toContain("Daily at 13:00 UTC (8:00 AM EST, 9:00 AM EDT)");
  });
});

describe("no people-facing time bypasses the Eastern formatter", () => {
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.(ts|tsx)$/.test(name)) files.push(p);
    }
  };
  walk(resolve(__dirname, "../src"));

  it("formatUtc is used only where it is defined (support output), not in any page or component", () => {
    const users = files.filter((f) => !f.endsWith(join("lib", "format.ts")) && /\bformatUtc\(/.test(readFileSync(f, "utf8")));
    expect(users).toEqual([]);
  });

  it("no date is formatted with the runtime zone (toLocaleDateString / toLocaleTimeString / Intl.DateTimeFormat without timeZone)", () => {
    const bad = files.filter((f) => {
      const s = readFileSync(f, "utf8");
      if (/toLocale(Date|Time)String\(/.test(s)) return true;
      for (const m of s.matchAll(/new Intl\.DateTimeFormat\(([^)]*)\)/g)) if (!/timeZone/.test(m[1])) return true;
      return false;
    });
    expect(bad).toEqual([]);
  });
});
