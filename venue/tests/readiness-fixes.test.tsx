/**
 * Regression guards for the 2026-10-12 functional-readiness audit. Each test
 * names the finding it guards; each was checked to fail with its fix reverted.
 */
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, DEVICES, EVENTS, FLAGS, HOLDS, MANIFEST_EPISODES, ORDERS, PINS, PREVIEW_NOW, ROSTER, SCANS, TICKET_TYPES, VENUE } from "@/fixtures/venue";
import { buildSignals, doorSummary, eventStage, stillAvailable } from "@/lib/signals";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { Tonight } from "@/components/overview/Tonight";
import { Attendees } from "@/components/attendees/Attendees";
import { DoorStatus } from "@/components/door/DoorStatus";
import { EventSetup } from "@/components/events/EventSetup";
import { EventsTable } from "@/components/events/EventsTable";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { CreateEventWizard } from "@/components/events/CreateEventWizard";
import { DeniedState } from "@/components/ui/State";

const base = "/o/smp_org_wynwood/v/smp_ven_room";
const tz = VENUE.timeZone;
const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const as = (role: PreviewContext["role"], over: Partial<PreviewContext> = {}): PreviewContext => ({ role, state: "live", ...over });
const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false };
const live = EVENTS[0];
const liveSession = live.sessions[0];

describe("V2 — preview links keep the persona when the href already has a query or a fragment", () => {
  it("merges role/state into an existing query and keeps the fragment last", () => {
    expect(withPreview("/a/attendees?view=purchasers", as("org_finance"))).toBe("/a/attendees?view=purchasers&role=org_finance");
    expect(withPreview("/a/door#lookup", as("venue_scanner"))).toBe("/a/door?role=venue_scanner#lookup");
    expect(withPreview("/a?checkIn=not_scanned#x", as("venue_manager", { state: "error" }))).toBe("/a?checkIn=not_scanned&state=error#x");
  });
  it("leaves the default persona's links untouched and replaces a stale role", () => {
    expect(withPreview("/a#attention", as("venue_manager"))).toBe("/a#attention");
    expect(withPreview("/a?role=org_owner", as("venue_marketing"))).toBe("/a?role=venue_marketing");
  });
});

function tonight(ctx: PreviewContext) {
  const built = buildSignals({ events: EVENTS, types: TICKET_TYPES, batches: BATCHES, holds: HOLDS, devices: DEVICES, flags: FLAGS, tonight: [{ event: live, session: liveSession }], now: PREVIEW_NOW, basePath: base, link: (h) => withPreview(h, ctx) });
  return html(
    <Tonight signals={built.signals} clear={built.clear} stageView={eventStage(EVENTS, [{ event: live, session: liveSession }], PREVIEW_NOW)} door={doorSummary([{ event: live, session: liveSession }], SCANS, DEVICES)} events={EVENTS} available={stillAvailable(EVENTS, TICKET_TYPES, BATCHES)} ctx={ctx} basePath={base} timeZone={tz} now={PREVIEW_NOW} />,
  );
}

describe("V5 — Today shows less, never more, than the door screen", () => {
  it("a manager still gets the door action and figures", () => {
    const out = tonight(as("venue_manager"));
    expect(out).toContain("Open check-in");
    expect(out).toContain("Checked in");
  });
  it("finance gets neither the door action nor door figures nor door items", () => {
    const out = tonight(as("org_finance"));
    expect(out).not.toContain("Open check-in");
    expect(out).not.toContain("Checked in");
    expect(out).not.toContain("Scanners online");
    expect(out).not.toMatch(/\/door[?#"]/);
  });
});

describe("V3 / V6 / V-attendees-phone-columns — the guest list honours the role's classes everywhere", () => {
  const props = { event: live, session: liveSession, roster: ROSTER, orders: ORDERS, basePath: base, timeZone: tz, filter: {}, totalUnfiltered: ROSTER.length, view: "holders" as const };
  it("box office is not sent to a door screen it cannot open", () => {
    const out = html(<Attendees {...props} ctx={as("venue_box_office")} />);
    expect(out).not.toContain("/door");
  });
  it("finance phone cards carry no ticket-type (OPS) data", () => {
    const out = html(<Attendees {...props} ctx={as("org_finance")} />);
    const cards = out.slice(out.indexOf('class="space-y-2 md:hidden"'));
    for (const t of new Set(ROSTER.flatMap((r) => r.ticketTypes))) expect(cards).not.toContain(t);
  });
  it("marketing phone cards show the email the table shows", () => {
    const out = html(<Attendees {...props} ctx={as("venue_marketing")} />);
    const cards = out.slice(out.indexOf('class="space-y-2 md:hidden"'));
    const withEmail = ROSTER.find((r) => r.email);
    expect(withEmail).toBeTruthy();
    expect(cards).toContain(withEmail!.email!);
  });
});

describe("V9 — a freeze that hasn't happened yet is not reported as past", () => {
  it("an upcoming night says transfers will freeze", () => {
    const basel = EVENTS.find((e) => e.eventId === "smp_evt_basel")!;
    const out = html(<DoorStatus event={basel} session={basel.sessions[0]} pins={PINS} devices={DEVICES} episodes={[]} scans={SCANS} flags={FLAGS} lookup={null} ctx={as("venue_manager")} basePath={base} timeZone={tz} now={PREVIEW_NOW} />);
    expect(out).toContain("Transfers will freeze at");
    expect(out).not.toContain("Transfers frozen since");
  });
  it("V12 — the flag queue is the #flags target", () => {
    const out = html(<DoorStatus event={live} session={liveSession} pins={PINS} devices={DEVICES} episodes={MANIFEST_EPISODES} scans={SCANS} flags={FLAGS} lookup={null} ctx={as("venue_manager")} basePath={base} timeZone={tz} now={PREVIEW_NOW} />);
    expect(out).toContain('id="flags"');
  });
});

describe("database mode states only what it read", () => {
  it("V8 — check-in list state is not invented", () => {
    const sess = { ...liveSession, doorOpenAt: "2026-09-13T01:05:00Z" };
    const out = html(<EventSetup event={{ ...live, sessions: [sess] }} types={TICKET_TYPES} batches={BATCHES} ctx={db} basePath={base} timeZone={tz} openManifestSessionIds={null} />);
    expect(out).toContain("Check-in list state isn&#x27;t readable in this mode.");
    expect(out).not.toContain("Doors closed");
  });
  it("V-db-larger-screen-claim — no 'open on a larger screen to make changes' when nothing can be changed", () => {
    const out = html(<EventSetup event={live} types={TICKET_TYPES} batches={BATCHES} ctx={db} basePath={base} timeZone={tz} openManifestSessionIds={null} />);
    expect(out).not.toContain("Open on a larger screen to make changes");
  });
  it("V1 — holds that were never read are not reported as none", () => {
    const out = html(<InventoryOverview event={live} types={TICKET_TYPES.filter((t) => t.eventId === live.eventId)} batches={BATCHES} holds={[]} ctx={db} basePath={base} timeZone={tz} now={PREVIEW_NOW} />);
    expect(out).not.toContain("No active holds");
    expect(out).toContain("Holds aren&#x27;t readable in this mode.");
  });
  it("V7 — no 'Needs attention' chip computed from unread sold counts", () => {
    const zeroed = BATCHES.map((b) => ({ ...b, held: 0, sold: 0, countersKnown: false }));
    const out = html(<EventsTable events={EVENTS} batches={zeroed} types={TICKET_TYPES} holds={[]} ctx={db} basePath={base} timeZone={tz} now={PREVIEW_NOW} filter={{}} />);
    expect(out).not.toContain("Needs attention");
  });
});

describe("small honesty and access fixes", () => {
  it("V11 — the price field accepts cents", () => {
    const out = html(<CreateEventWizard ctx={as("venue_manager")} basePath={base} step={2} venueApproved venueName={VENUE.name} />);
    expect(out).toMatch(/name="price"[^>]*step="0.01"|step="0.01"[^>]*name="price"/);
  });
  it("V-denied-outside-shell — a whole-page denial has a main landmark and a page heading", () => {
    const out = html(<DeniedState standalone surface="This venue" />);
    expect(out).toMatch(/^<main id="main"/);
    expect(out).toContain("<h1");
  });
});

import { readFileSync } from "node:fs";
import { PartialCell } from "@/components/ui/State";

describe("found by the H3b sweep", () => {
  it("a dash with a reason keeps its sr-only text inside a positioned box (it widened the phone page from inside a table scroller)", () => {
    const out = renderToStaticMarkup(<PartialCell why="Couldn't load payment detail" />);
    expect(out).toMatch(/^<span class="relative"><span aria-hidden="true"[^>]*>—<\/span><span class="sr-only">/);
  });
  it("the create-event state screens (loading, error, denied) get the page heading from the frame", () => {
    const s = readFileSync(new URL("../src/app/o/[org]/v/[venue]/events/new/page.tsx", import.meta.url), "utf8");
    expect(s).toContain('title={showsWizard ? undefined : "New event"}');
    expect(s).toMatch(/const showsWizard = ctx\.source !== "database" && !denied && ctx\.state !== "loading" && ctx\.state !== "error";/);
  });
});
