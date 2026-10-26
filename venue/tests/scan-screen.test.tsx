import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ScannerClient } from "@/components/scan/ScannerClient";
import ScanPage from "@/app/o/[org]/v/[venue]/events/[event]/scan/page";
import { EVENTS, ORG, VENUE } from "@/fixtures/venue";
import { canScan, VENUE_ROLES, ORG_ROLES } from "@/lib/roles";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const anchors = (h: string) => h.match(/<a [^>]*>/g) ?? [];
const scanLinks = (h: string) => anchors(h).filter((a) => /href="[^"]*\/events\/[^"]+\/scan[^"]*"/.test(a));
const EVENT = EVENTS[0];
const page = (role?: string, event = EVENT.eventId) => ScanPage({ params: Promise.resolve({ org: ORG.orgId, venue: VENUE.venueId, event }), searchParams: Promise.resolve(role ? { role } : {}) });

describe("who gets the scanner (fixture mode mirrors the server's role gate)", () => {
  it("exactly venue_scanner and venue_manager may scan; every other principal is refused, as venue.record_scan refuses them", () => {
    expect([...VENUE_ROLES, ...ORG_ROLES, "fan"].filter((r) => canScan(r as never))).toEqual(["venue_manager", "venue_scanner"]);
  });
  it("a venue manager sees the setup step, the demo label and a Scanner entry in the event navigation", async () => {
    const h = html(await page());
    expect(h).toContain("Set up this phone");
    expect(h).toContain("Demo — sample data");
    expect(h).toContain("Start scanning");
    const current = anchors(h).filter((a) => a.includes('aria-current="page"'));
    expect(current.some((a) => /href="[^"]*\/events\/[^"]+\/scan[^"]*"/.test(a))).toBe(true);
    expect(scanLinks(h).length).toBeGreaterThan(0);
  });
  it("a venue scanner gets the screen; finance, box office, marketing and org roles get the refusal with the reason", async () => {
    expect(html(await page("venue_scanner"))).toContain("Start scanning");
    for (const role of ["venue_finance", "venue_box_office", "venue_marketing", "org_owner", "org_admin", "fan"]) {
      const h = html(await page(role));
      expect(h, role).toContain("Scanning needs the venue scanner or venue manager role");
      expect(h, role).not.toContain("Start scanning");
      expect(scanLinks(h), role).toEqual([]);
    }
  });
  it("an event that is not there is refused the same way as one that is not yours", async () => {
    const h = html(await page(undefined, "smp_evt_nope"));
    expect(h).toContain("Either it isn&#x27;t yours to see, or it isn&#x27;t there");
  });
});

describe("the scanner screen's first paint", () => {
  const props = {
    demo: false,
    ids: { orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", venueId: "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75", eventId: "9a000000-0000-4000-8000-000000000001" },
    eventTitle: "Snatch It pop-up",
    sessions: [
      { sessionId: "5e55e55e-0000-4000-8000-000000000001", label: "Doors", startsAt: "2026-11-30T03:00:00Z", endsAt: null, status: "live" },
      { sessionId: "5e55e55e-0000-4000-8000-000000000002", label: "Late", startsAt: "2026-11-30T06:00:00Z", endsAt: null, status: "scheduled" },
    ],
    defaultSessionId: "5e55e55e-0000-4000-8000-000000000001",
    staff: { label: "door@example.test", role: "Scanner" },
    timeZone: null,
    loginHref: "/login?next=%2Fx",
  };
  it("setup first: a labelled session choice, a labelled phone label, one primary button, no demo label, and the human ID check named", () => {
    const h = html(createElement(ScannerClient, props));
    expect(h).not.toContain("Demo — sample data");
    expect(h).toContain("<select");
    expect(h).toMatch(/<option[^>]*value="5e55e55e-0000-4000-8000-000000000001"[^>]*selected/);
    expect(h).toContain("Doors ·");
    expect(h).toContain("name=\"device_label\"");
    expect(h).toContain("Start scanning");
    expect(h).toContain("the 21+ ID check stays with you");
    expect(h).toContain("phone&#x27;s time zone");
    expect(h).toContain("door@example.test");
  });
  it("with the venue's zone known, times say so; with no sessions the button is disabled", () => {
    expect(html(createElement(ScannerClient, { ...props, timeZone: "America/New_York" }))).toContain("Times in America/New_York.");
    const none = html(createElement(ScannerClient, { ...props, sessions: [], defaultSessionId: null }));
    expect(none).toContain("No sessions on this event");
    expect(none).toMatch(/<button[^>]*disabled[^>]*>\s*Start scanning/);
  });
  it("nothing in the scanner's copy turns a camera scan into age or identity verification, or a timeout into an admit", () => {
    const src = [readFileSync(resolve(__dirname, "../src/components/scan/ScannerClient.tsx"), "utf8"), readFileSync(resolve(__dirname, "../src/lib/scan/outcome.ts"), "utf8")].join("\n");
    expect(src.toLowerCase()).not.toMatch(/age verif|verifies (their )?age|id verified/);
    expect(src).toContain("21+ ID check stays with you");
    expect(src).not.toMatch(/timeout[^\n]*admitted:|admitted[^\n]*on timeout/);
  });
});
