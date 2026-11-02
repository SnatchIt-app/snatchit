import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

/**
 * Door times are in the VENUE's zone with EST/EDT, never the phone's (owner decision 2026-11-02:
 * Snatch It operates in Eastern Time; venue event times keep their venue's zone).
 *
 * Before this change the live scanner passed timeZone=null in database mode
 * (scan/page.tsx: `p.ctx.source === "database" ? null : p.timeZone`), so the session list,
 * "Where you are", the history and "Already admitted at …" used the runtime zone: UTC in the server
 * render, then whatever zone the door phone is set to. The payouts page showed raw UTC strings.
 *
 * Modules load fresh under each runtime zone: a formatter keeps the zone it was built in, and the
 * development machine runs America/New_York, which would hide a fallback to the runtime zone.
 */
vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }), usePathname: () => "/", useSearchParams: () => new URLSearchParams() }));

const ORIGINAL_TZ = process.env.TZ;
afterAll(() => {
  if (ORIGINAL_TZ === undefined) delete process.env.TZ;
  else process.env.TZ = ORIGINAL_TZ;
});

async function load(tz: string) {
  process.env.TZ = tz;
  vi.resetModules();
  const [outcome, format, zone, scanner] = await Promise.all([import("@/lib/scan/outcome"), import("@/lib/format"), import("@/lib/events/zone"), import("@/components/scan/ScannerClient")]);
  return { ...outcome, ...format, ...zone, ...scanner };
}

const PRIOR = { scanId: "5ca0b1c2-d3e4-4f5a-8b6c-7d8e9f0a1b2c", occurredAt: "2026-11-02T04:59:59Z", actorLabel: null, deviceLabel: "Door A phone" };
const ATOM = "a70b1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";

describe("NEGATIVE CONTROL — the two runtime zones really differ", () => {
  it("a formatter with no timeZone gives different text under UTC and Los Angeles", () => {
    const seen = ["UTC", "America/Los_Angeles"].map((tz) => {
      process.env.TZ = tz;
      return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date("2026-11-02T04:59:59Z"));
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

    it("the door clock is the venue's time with EST/EDT at every anchor", () => {
      const NY = "America/New_York";
      expect(m.clock("2026-11-02T04:59:59Z", NY)).toBe("11:59 PM EST");
      expect(m.clock("2026-11-01T04:00:00Z", NY)).toBe("12:00 AM EDT");
      expect(m.clock("2026-11-01T05:30:00Z", NY)).toBe("1:30 AM EDT"); // 1:30 happens twice on Nov 1 …
      expect(m.clock("2026-11-01T06:30:00Z", NY)).toBe("1:30 AM EST"); // … the label tells them apart
      expect(m.clock("2026-03-08T06:59:59Z", NY)).toBe("1:59 AM EST");
      expect(m.clock("2026-03-08T07:00:00Z", NY)).toBe("3:00 AM EDT");
      expect(m.clock("not a time", NY)).toBeNull();
      expect(m.clock(null, NY)).toBeNull();
    });

    it("a venue outside New York keeps its own zone (the venue-zone contract)", () => {
      expect(m.clock("2026-11-02T04:59:59Z", "America/Chicago")).toBe("10:59 PM CST");
    });

    it("'Already admitted at …' names the time and its zone", () => {
      const o = { kind: "already_used" as const, atomId: ATOM, prior: PRIOR, possiblyThisPhone: false };
      expect(m.outcomeDetail(o, "America/New_York")).toBe("Already admitted at 11:59 PM EST (Door A phone).");
    });

    it("the scanner setup lists sessions in the venue's zone and never mentions the phone's zone", () => {
      const html = renderToStaticMarkup(
        createElement(m.ScannerClient, {
          demo: false,
          ids: { orgId: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", venueId: "1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e", eventId: "2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f" },
          eventTitle: "Fixture night",
          sessions: [{ sessionId: "3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a", label: "Doors", startsAt: "2026-11-02T04:59:59Z", endsAt: null, status: "live" }],
          defaultSessionId: "3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a",
          staff: { label: "door@example.test", role: "Scanner" },
          timeZone: "America/New_York",
          loginHref: "/login",
        }),
      );
      expect(html).toContain("Doors · Sun, Nov 1, 11:59 PM EST · live");
      expect(html).toContain("Times are in America/New_York");
      expect(html.toLowerCase()).not.toContain("phone&#x27;s time zone");
      expect(html.toLowerCase()).not.toContain("phone’s zone");
    });

    it("an org's Stripe times are Eastern with EST/EDT; a value that is not a date is shown as sent", () => {
      expect(m.PLATFORM_TIME_ZONE).toBe("America/New_York");
      expect(m.PLATFORM_DEFAULT_TIME_ZONE).toBe(m.PLATFORM_TIME_ZONE); // one zone, one name
      expect(m.platformTime("2026-11-02T04:59:59+00:00")).toBe("Sun, Nov 1, 11:59 PM EST");
      expect(m.platformTime("2026-03-08T07:00:00.000Z")).toBe("Sun, Mar 8, 3:00 AM EDT");
      expect(m.platformTime("soon")).toBe("soon");
    });
  });
}

describe("the pages pass a zone, and show no raw UTC", () => {
  const src = (rel: string) => readFileSync(resolve(__dirname, "../src", rel), "utf8");
  it("the live scanner page passes the event's venue zone in database mode too", () => {
    const page = src("app/o/[org]/v/[venue]/events/[event]/scan/page.tsx");
    expect(page).toContain("timeZone={p.timeZone}");
    expect(page).not.toMatch(/timeZone=\{[^}]*\?\s*null/);
  });
  it("payouts format the Stripe sync time and deadline", () => {
    expect(src("app/o/[org]/payouts/page.tsx")).toContain("platformTime(state.syncedAt)");
    expect(src("components/org/ConnectActions.tsx")).toContain("platformTime(snapshot.requirementsDeadline)");
  });
});
