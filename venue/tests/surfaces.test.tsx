import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, DEVICES, EVENTS, FLAGS, HOLDS, MANIFEST_EPISODES, ORDERS, PINS, PREVIEW_NOW, ROSTER, SCANS, TICKET_TYPES, VENUE } from "@/fixtures/venue";
import { PREVIEW_DATA_LABEL, type PreviewContext } from "@/lib/preview";
import { Attendees } from "@/components/attendees/Attendees";
import { DoorStatus } from "@/components/door/DoorStatus";
import { CreateEventWizard } from "@/components/events/CreateEventWizard";
import { EventSetup } from "@/components/events/EventSetup";
import { EventsTable } from "@/components/events/EventsTable";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { Shell } from "@/components/shell/Shell";
import { DeniedState, EmptyState, ErrorState, Skeleton } from "@/components/ui/State";

const base = "/o/smp_org_wynwood/v/smp_ven_room";
const vm: PreviewContext = { role: "venue_manager", state: "live" };
const live = EVENTS[0];
const session = live.sessions[0];
const html = (el: React.ReactElement) => renderToStaticMarkup(el);

describe("shell", () => {
  it("always shows the Preview data indicator and names the persona", () => {
    const out = html(
      <Shell ctx={{ role: "org_finance", state: "live" }} event={null} active="events">
        <p>x</p>
      </Shell>,
    );
    expect(out).toContain(PREVIEW_DATA_LABEL);
    expect(out).toContain("Org finance");
    expect(out).not.toContain("Door</a>"); // finance has no door surface (row 30)
  });
});

describe("events list (§7.1)", () => {
  const props = { batches: BATCHES, types: TICKET_TYPES, holds: HOLDS, ctx: vm, basePath: base, venueName: VENUE.name, timeZone: VENUE.timeZone, now: PREVIEW_NOW };
  it("renders every event with status pills and an inventory warning chip on tonight's event", () => {
    const out = html(<EventsTable {...props} events={EVENTS} filter={{}} />);
    for (const e of EVENTS) expect(out).toContain(e.title);
    expect(out).toContain("Inventory warning");
    expect(out).toContain("411 / 520");
  });
  it("distinguishes no events from no matches", () => {
    expect(html(<EventsTable {...props} events={[]} filter={{}} />)).toContain("No events yet.");
    expect(html(<EventsTable {...props} events={EVENTS} filter={{ q: "zzz" }} />)).toContain("No events match these filters.");
  });
  it("shows availability, not counters, to org_member", () => {
    const out = html(<EventsTable {...props} ctx={{ role: "org_member", state: "live" }} events={EVENTS} filter={{}} />);
    expect(out).toContain("available");
    expect(out).not.toContain("411 / 520");
  });
});

describe("event setup (§7.3–§7.9)", () => {
  it("offers only the next legal status and says events can't move backwards", () => {
    const out = html(<EventSetup event={EVENTS[1]} types={[]} batches={[]} ctx={vm} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(out).toContain("Next step: <strong>Live</strong>");
    expect(out).toContain("can&#x27;t move an event backwards");
  });
  it("names the missing requirement before on_sale instead of a dead button", () => {
    const out = html(<EventSetup event={EVENTS[2]} types={[]} batches={[]} ctx={vm} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(out).toContain("Add a ticket type before going on sale.");
    expect(out).not.toContain("Set to On sale");
  });
  it("states the manifest consequence on the live session", () => {
    const out = html(<EventSetup event={live} types={TICKET_TYPES} batches={BATCHES} ctx={vm} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set([session.sessionId])} />);
    expect(out).toContain("Door open — transfers closed");
    expect(out).toContain("Held back for the door: <strong>40 of 520</strong>");
  });
  it("wizard blocks at step 1 when the venue is not approved", () => {
    const out = html(<CreateEventWizard ctx={vm} basePath={base} step={1} venueApproved={false} venueName="X" />);
    expect(out).toContain("isn&#x27;t approved to sell yet");
  });
});

describe("inventory (§8)", () => {
  const props = { event: live, types: TICKET_TYPES.filter((t) => t.eventId === live.eventId), batches: BATCHES, holds: HOLDS, basePath: base, timeZone: VENUE.timeZone, now: PREVIEW_NOW };
  it("keeps sold out and all held distinct, and warns on untouched door stock", () => {
    const out = html(<InventoryOverview {...props} ctx={vm} />);
    expect(out).toContain("Sold out.");
    expect(out).toContain("everything is on hold");
    expect(out).toContain("Door stock untouched");
    expect(out).toContain("you can&#x27;t go below 288");
  });
  it("shows remaining only to a scanner and no holds panel", () => {
    const out = html(<InventoryOverview {...props} ctx={{ role: "venue_scanner", state: "live" }} />);
    expect(out).not.toContain("Inventory warnings");
    expect(out).toContain("available");
    expect(out).not.toContain("venue.release_inventory_hold");
  });
  it("uses the specific empties", () => {
    expect(html(<InventoryOverview {...props} ctx={vm} types={[]} />)).toContain("No ticket types yet");
    expect(html(<InventoryOverview {...props} ctx={vm} batches={[]} />)).toContain("No releases yet");
  });
});

describe("attendees (§9)", () => {
  const props = { event: live, session, roster: ROSTER, orders: ORDERS, basePath: base, timeZone: VENUE.timeZone, filter: {}, totalUnfiltered: ROSTER.length, view: "holders" as const };
  it("is holder-keyed: the six-ticket table shows six people, one marked purchaser", () => {
    const out = html(<Attendees {...props} ctx={vm} />);
    for (const n of ["Camila R.", "Andrés P.", "Lucía M.", "Tomás V.", "Sofía A.", "Diego L."]) expect(out).toContain(n);
    expect(out).toContain("Export · money list");
  });
  it("denies the scanner and names the alternative", () => {
    const out = html(<Attendees {...props} ctx={{ role: "venue_scanner", state: "live" }} />);
    expect(out).toContain("You don&#x27;t have access to this.");
    expect(out).toContain("Door access uses ticket lookup, not the attendee list.");
    expect(out).not.toContain("Camila");
  });
  it("hides check-in and email from finance, hides money from marketing", () => {
    const fin = html(<Attendees {...props} ctx={{ role: "venue_finance", state: "live" }} />);
    expect(fin).not.toContain("Admitted 9:22");
    expect(fin).not.toContain("camila@example.test");
    const mkt = html(<Attendees {...props} ctx={{ role: "venue_marketing", state: "live" }} />);
    expect(mkt).toContain("camila@example.test");
    expect(mkt).not.toContain("Purchasers");
    expect(mkt).toContain("Export · audience list");
  });
  it("keeps no-sales and no-match distinct", () => {
    expect(html(<Attendees {...props} ctx={vm} roster={[]} totalUnfiltered={0} />)).toContain("No tickets sold for this session yet.");
    expect(html(<Attendees {...props} ctx={vm} roster={[]} filter={{ q: "zzz" }} />)).toContain("No attendees match these filters.");
  });
  it("purchaser view says Voided, never refunded, for tickets", () => {
    const out = html(<Attendees {...props} ctx={vm} view="purchasers" />);
    expect(out).toContain("1 voided");
    expect(out).toContain("$3,000.00");
  });
});

describe("door (§12)", () => {
  const props = { event: live, session, pins: PINS, devices: DEVICES, episodes: MANIFEST_EPISODES, scans: SCANS, flags: FLAGS, lookup: null, basePath: base, timeZone: VENUE.timeZone, now: PREVIEW_NOW };
  it("is counter-first with the five scan results and no Resolve control", () => {
    const out = html(<DoorStatus {...props} ctx={vm} />);
    expect(out).toContain("291");
    expect(out).toContain("Already used");
    expect(out).toContain("Blocked (door manifest)");
    expect(out).toContain("Escalate with a note");
    expect(out).not.toMatch(/>Resolve</);
    expect(out).toContain("Door open — transfers closed");
    expect(out).toContain("because the door manifest was opened");
  });
  it("never offers the manifest control to a scanner and never shows a PIN resend", () => {
    const out = html(<DoorStatus {...props} ctx={{ role: "venue_scanner", state: "live" }} />);
    expect(out).not.toContain("Open door manifest");
    expect(out).not.toContain("Close manifest");
    expect(out).not.toMatch(/resend/i);
    expect(out).toContain("A door PIN can never authorize a refund.");
  });
  it("manual lookup returns one record with the wallet-staleness note", () => {
    const out = html(<DoorStatus {...props} ctx={vm} lookup={{ q: "Priya", result: ROSTER.find((r) => r.name.startsWith("Priya")) ?? null }} />);
    expect(out).toContain("Refuse — Blocked (door manifest)");
    expect(out).toContain("A pass shown from a wallet can be out of date.");
    expect(html(<DoorStatus {...props} ctx={vm} lookup={{ q: "nobody", result: null }} />)).toContain("No ticket matches that.");
  });
  it("uses the door empties", () => {
    const out = html(<DoorStatus {...props} ctx={vm} pins={[]} devices={[]} flags={[]} scans={{ ...SCANS, admitted: 0, duplicate: 0, invalid: 0, frozen: 0, fraudReview: 0, arrivalsPer5Min: [] }} />);
    expect(out).toContain("No PINs for this session.");
    expect(out).toContain("No devices registered.");
    expect(out).toContain("Nothing flagged.");
    expect(out).toContain("No scans yet — doors haven&#x27;t opened.");
  });
});

describe("shared states (§18)", () => {
  it("denial reveals nothing; error names the read; skeleton is labelled", () => {
    expect(html(<DeniedState />)).toContain("You don&#x27;t have access to this.");
    expect(html(<ErrorState read="venue.scan" retryHref="/r" />)).toContain("venue.scan");
    expect(html(<Skeleton rows={2} />)).toContain("aria-label=\"Loading\"");
    expect(html(<EmptyState title="No events yet." />)).toContain("No events yet.");
  });
});
