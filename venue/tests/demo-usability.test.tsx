/**
 * The fixes this demo branch makes to the 2026-09-17 dashboard usability audit.
 * Each test names the finding it is the regression guard for.
 */
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, DEVICES, EVENTS, FLAGS, HOLDS, PREVIEW_NOW, SCANS, TICKET_TYPES } from "@/fixtures/venue";
import { listEvents } from "@/lib/data";
import { buildSignals, doorSummary, stillAvailable, type SignalInput } from "@/lib/signals";
import type { PreviewContext } from "@/lib/preview";
import { EventsTable } from "@/components/events/EventsTable";
import { Tonight } from "@/components/overview/Tonight";

const base = "/o/smp_org_wynwood/v/smp_ven_room";
const vm: PreviewContext = { role: "venue_manager", state: "live" };
const html = (el: React.ReactElement) => renderToStaticMarkup(el);

const tableProps = { batches: BATCHES, types: TICKET_TYPES, holds: HOLDS, ctx: vm, basePath: base, venueName: "The Room", timeZone: "America/New_York", now: PREVIEW_NOW };

const input = (over: Partial<SignalInput> = {}): SignalInput => ({
  events: EVENTS,
  types: TICKET_TYPES,
  batches: BATCHES,
  holds: HOLDS,
  devices: DEVICES,
  flags: FLAGS,
  tonight: [{ event: EVENTS[0], session: EVENTS[0].sessions[0] }],
  now: PREVIEW_NOW,
  basePath: base,
  link: (h) => h,
  ...over,
});

describe("X2 — filtered to nothing is never 'you have no events'", () => {
  it("names the filter, keeps the count, and offers Clear filters — not Create event", () => {
    const out = html(<EventsTable {...tableProps} events={EVENTS} filter={{ status: "no-such-status" }} />);
    expect(out).toContain("No events match these filters.");
    expect(out).toContain(`Your ${EVENTS.length} events are still here.`);
    expect(out).toContain("Clear filters");
    expect(out).not.toContain("No events yet.");
    expect(out).not.toContain("Create event");
  });

  it("still says 'No events yet' when there genuinely are none", () => {
    const out = html(<EventsTable {...tableProps} events={[]} filter={{}} />);
    expect(out).toContain("No events yet.");
    expect(out).toContain("Create event");
    expect(out).not.toContain("match these filters");
  });

  it("the nodata read no longer empties the set — the filter does the filtering", () => {
    expect(listEvents("nodata")).toHaveLength(EVENTS.length);
    expect(listEvents("empty")).toHaveLength(0);
  });
});

describe("P5 — the header names the measure actually shown", () => {
  it("counter roles see capacity, remaining-only roles see availability", () => {
    expect(html(<EventsTable {...tableProps} events={EVENTS} filter={{}} />)).toContain("Sold of capacity");
    const member = html(<EventsTable {...tableProps} ctx={{ role: "org_member", state: "live" }} events={EVENTS} filter={{}} />);
    expect(member).toContain("Still available");
    expect(member).not.toContain("Sold of capacity");
  });
});

describe("W1 — the overview answers 'what needs me now?'", () => {
  it("orders signals worst-first and gives each one a consequence and one action", () => {
    const { signals } = buildSignals(input());
    expect(signals.length).toBeGreaterThan(0);
    const rank = { act_now: 0, soon: 1, worth_knowing: 2 } as const;
    const ranks = signals.map((s) => rank[s.severity]);
    expect(ranks).toEqual([...ranks].sort((a, b) => a - b));
    for (const s of signals) {
      expect(s.consequence.length).toBeGreaterThan(20);
      expect(s.action.href).toContain(base);
    }
  });

  it("a scanner that stopped syncing is an act-now signal, and a synced fleet is a clear check", () => {
    const stale = buildSignals(input());
    const staleSignal = stale.signals.find((s) => s.id === "device_stale");
    expect(staleSignal?.severity).toBe("act_now");
    expect(stale.clear.some((c) => c.id === "device_stale")).toBe(false);

    // Positive control: with every device fresh and online the signal disappears
    // and the check is reported clear, so an empty overview is evidence, not silence.
    const fresh = DEVICES.map((d) => ({ ...d, online: true, status: "active" as const, lastSyncAt: PREVIEW_NOW.toISOString() }));
    const good = buildSignals(input({ devices: fresh }));
    expect(good.signals.find((s) => s.id === "device_stale")).toBeUndefined();
    expect(good.clear.some((c) => c.id === "device_stale")).toBe(true);
  });

  it("every figure on the page is rendered with the sentence that defines it", () => {
    // Fresh devices so at least one check reports clear — the collapsed
    // "N other checks are clear" line is what makes an empty overview evidence.
    const fresh = DEVICES.map((d) => ({ ...d, online: true, status: "active" as const, lastSyncAt: PREVIEW_NOW.toISOString() }));
    const { signals, clear } = buildSignals(input({ devices: fresh }));
    expect(clear.length).toBeGreaterThan(0);
    const out = html(
      <Tonight
        signals={signals}
        clear={clear}
        door={doorSummary([{ event: EVENTS[0], session: EVENTS[0].sessions[0] }], SCANS, fresh)}
        events={EVENTS}
        available={stillAvailable(EVENTS, TICKET_TYPES, BATCHES)}
        ctx={vm}
        basePath={base}
        timeZone="America/New_York"
        now={PREVIEW_NOW}
      />,
    );
    expect(out).toContain("People inside");
    expect(out).toContain("Scanned in so far");
    expect(out).toContain("Scanners online");
    expect(out).toContain("Counted at this moment, not a total for the week.");
    expect(out).toContain("other checks are clear");
  });
});

describe("X0 — every font size scales with the reader's text setting", () => {
  it("no stylesheet or component pins a font size in px", () => {
    for (const f of ["src/app/globals.css", "src/app/globals-preview.css"]) {
      const css = readFileSync(new URL(`../${f}`, import.meta.url), "utf8");
      const pinned = css.match(/font-size:\s*\d+px/g);
      expect(pinned, `${f} pins a font size in px: ${pinned?.join(", ")}`).toBeNull();
    }
  });
});

/**
 * Plain-language guards added for the pitch-readiness pass (2026-10-06).
 *
 * The audit's §P3 fix covered panel eyebrows only; backend identifiers were
 * still sitting in body copy ("Add session → catalog.create_event_session",
 * "Preview: would call venue.close_door_manifest"). These assert the rule for
 * the whole rendered surface instead of one component at a time.
 */
import { DEVICES as DEV, EVENTS as EV, HOLDS as HLD, MANIFEST_EPISODES, ORDERS, PINS, ROSTER, SCANS as SC, TICKET_TYPES as TT, BATCHES as BT, FLAGS as FL, VENUE } from "@/fixtures/venue";
import { rosterIsSampled } from "@/lib/data";
import { Attendees } from "@/components/attendees/Attendees";
import { DoorStatus } from "@/components/door/DoorStatus";
import { CreateEventWizard } from "@/components/events/CreateEventWizard";
import { EventSetup } from "@/components/events/EventSetup";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";

/** Visible text only: a read name parked in title=… or data-read=… is review detail, not copy. */
function visibleText(markup: string): string {
  return markup
    .replace(/\stitle="[^"]*"/g, "")
    .replace(/\sdata-read="[^"]*"/g, "")
    .replace(/<[^>]+>/g, " ");
}

const liveEvent = EV[0];
const liveSession = liveEvent.sessions[0];
const tz = VENUE.timeZone;

const SURFACES: Record<string, () => string> = {
  "event setup (live)": () => html(<EventSetup event={liveEvent} types={TT} batches={BT} ctx={vm} basePath={base} timeZone={tz} openManifestSessionIds={new Set([liveSession.sessionId])} />),
  "event setup (blocked from on sale)": () => html(<EventSetup event={EV[2]} types={[]} batches={[]} ctx={vm} basePath={base} timeZone={tz} openManifestSessionIds={new Set()} />),
  inventory: () => html(<InventoryOverview event={liveEvent} types={TT.filter((t) => t.eventId === liveEvent.eventId)} batches={BT} holds={HLD} ctx={vm} basePath={base} timeZone={tz} now={PREVIEW_NOW} />),
  attendees: () => html(<Attendees event={liveEvent} session={liveSession} roster={ROSTER} orders={ORDERS} ctx={vm} basePath={base} timeZone={tz} filter={{}} totalUnfiltered={ROSTER.length} view="holders" />),
  door: () => html(<DoorStatus event={liveEvent} session={liveSession} pins={PINS} devices={DEV} episodes={MANIFEST_EPISODES} scans={SC} flags={FL} lookup={null} ctx={vm} basePath={base} timeZone={tz} now={PREVIEW_NOW} />),
  "create wizard": () => html(<CreateEventWizard ctx={vm} basePath={base} step={1} venueApproved venueName={VENUE.name} />),
  "tonight overview": () => {
    const built = buildSignals(input());
    return html(<Tonight signals={built.signals} clear={built.clear} door={doorSummary([{ event: liveEvent, session: liveSession }], SC, DEV)} events={EV} available={stillAvailable(EV, TT, BT)} ctx={vm} basePath={base} timeZone={tz} now={PREVIEW_NOW} />);
  },
};

describe("plain language — no backend identifier is visible copy", () => {
  it.each(Object.keys(SURFACES))("%s names no schema object in visible text", (name) => {
    const text = visibleText(SURFACES[name]());
    const hits = text.match(/\b(catalog|venue|kernel|ops|public)\.[a-z_]{3,}/g) ?? [];
    expect(hits, `${name} shows ${hits.join(", ")}`).toEqual([]);
  });

  it("the guard can fail: it catches an identifier it is given", () => {
    // Positive control — without this, an empty match above could mean the
    // regex never matches anything rather than that the copy is clean.
    expect(visibleText("<p>Add session → catalog.create_event_session</p>").match(/\b(catalog|venue)\.[a-z_]{3,}/g)).toEqual(["catalog.create_event_session"]);
    // …and that a read parked in an attribute is deliberately not a hit.
    expect(visibleText('<h2 title="Reads venue.scan">Live scan board</h2>').match(/\bvenue\.[a-z_]{3,}/g)).toBeNull();
  });

  it("no surface tells the reader what would be saved without saying nothing is", () => {
    for (const [name, render] of Object.entries(SURFACES)) {
      const text = visibleText(render());
      if (!text.includes("recorded in your venue")) continue;
      expect(text, `${name} promises a record without the demo caveat`).toMatch(/In this demo nothing is saved/);
    }
  });
});

describe("no dead ends", () => {
  it("the create-event wizard offers a way out on every step", () => {
    for (const step of [1, 2, 3] as const) {
      const out = html(<CreateEventWizard ctx={vm} basePath={base} step={step} venueApproved venueName={VENUE.name} />);
      expect(out, `step ${step}`).toContain("Cancel and go back to events");
      expect(out, `step ${step}`).toContain(`${base}/events`);
    }
  });

  it("a session with no sample guest list says so, instead of reporting that nobody bought", () => {
    const quiet = EV.find((e) => e.status === "completed")!;
    const quietSession = quiet.sessions[0];
    expect(rosterIsSampled(quietSession.sessionId)).toBe(false);
    expect(rosterIsSampled(liveSession.sessionId)).toBe(true);

    const out = html(<Attendees event={quiet} session={quietSession} roster={[]} orders={[]} ctx={vm} basePath={base} timeZone={tz} filter={{}} totalUnfiltered={0} rosterSampled={false} view="holders" />);
    expect(out).toContain("doesn&#x27;t include a guest list for this night");
    expect(out).not.toContain("No tickets sold for this session yet");

    // Discrimination: a session that genuinely sold nothing still says so.
    const empty = html(<Attendees event={liveEvent} session={liveSession} roster={[]} orders={[]} ctx={vm} basePath={base} timeZone={tz} filter={{}} totalUnfiltered={0} rosterSampled view="holders" />);
    expect(empty).toContain("No tickets sold for this session yet");
    expect(empty).not.toContain("doesn&#x27;t include a guest list");
  });
});
