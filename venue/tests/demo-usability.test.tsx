/**
 * The fixes this demo branch makes to the 2026-09-17 dashboard usability audit.
 * Each test names the finding it is the regression guard for.
 */
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, DEVICES, EVENTS, FLAGS, HOLDS, PREVIEW_NOW, SCANS, TICKET_TYPES } from "@/fixtures/venue";
import { listEvents } from "@/lib/data";
import { buildSignals, doorSummary, eventStage, stillAvailable, type SignalInput } from "@/lib/signals";
import { sessionTotals } from "@/lib/inventory";
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
    expect(html(<EventsTable {...tableProps} events={EVENTS} filter={{}} />)).toContain("411 of 520 sold");
    const member = html(<EventsTable {...tableProps} ctx={{ role: "org_member", state: "live" }} events={EVENTS} filter={{}} />);
    expect(member).toContain("still available");
    expect(member).not.toContain("411 of 520 sold");
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
        clear={clear} stageView={eventStage(EVENTS, [{ event: EVENTS[0], session: EVENTS[0].sessions[0] }], PREVIEW_NOW)}
        door={doorSummary([{ event: EVENTS[0], session: EVENTS[0].sessions[0] }], SCANS, fresh)}
        events={EVENTS}
        available={stillAvailable(EVENTS, TICKET_TYPES, BATCHES)}
        ctx={vm}
        basePath={base}
        timeZone="America/New_York"
        now={PREVIEW_NOW}
        sales={TICKET_TYPES.filter((t) => t.eventId === EVENTS[0].eventId).map((t) => {
          const tot = sessionTotals(BATCHES, t.ticketTypeId, EVENTS[0].sessions[0].sessionId);
          return { ticketTypeId: t.ticketTypeId, name: t.name, priceMinor: t.priceMinor, sold: tot.sold, capacity: tot.capacity, remaining: tot.remaining };
        })}
      />,
    );
    // v4 (approved concept): the figure reads "Checked in"; its definition sits under "How these are counted".
    expect(out).toContain("Checked in");
    expect(out).toMatch(/people inside\): scanned in so far/i);
    expect(out).toContain("Scanners online");
    expect(out).toContain("Counted at this moment, not a total for the week.");
    // Each ticket line says what its numbers are: sold of capacity, and what is left.
    expect(out).toMatch(/of \d+<\/span><span class="sr-only"> sold<\/span>/);
    expect(out).toMatch(/ left<\/span>|Sold out/);
    expect(out).toMatch(/other check(s)? ran and found nothing/);
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
    return html(<Tonight signals={built.signals} clear={built.clear} stageView={eventStage(EVENTS, [{ event: EVENTS[0], session: EVENTS[0].sessions[0] }], PREVIEW_NOW)} door={doorSummary([{ event: liveEvent, session: liveSession }], SC, DEV)} events={EV} available={stillAvailable(EV, TT, BT)} ctx={vm} basePath={base} timeZone={tz} now={PREVIEW_NOW} />);
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

/**
 * Bounded cleanup, 2026-10-06 (second pass).
 *   1. the manifest control is only offered where there is still a door
 *   2. no promise of an activity record the reader cannot open
 *   3. no backend identifier in a tooltip either — a tooltip is product UI
 */
import { manifestAction, manifestState } from "@/lib/door";
import { demoActionLabel, statesFor } from "@/lib/preview";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";

const openEpisode = MANIFEST_EPISODES.filter((e) => e.closedAt === null);
const closedEpisodes = MANIFEST_EPISODES.map((e) => ({ ...e, closedAt: e.closedAt ?? "2026-09-13T04:00:00Z" }));

describe("U1 — the door manifest is only operable while there is a door", () => {
  const live = { status: "live" as const };
  const scheduled = { status: "scheduled" as const };
  const done = { status: "completed" as const };
  const cancelled = { status: "cancelled" as const };

  it("offers Open on a session still to come or under way", () => {
    expect(manifestAction(scheduled, "closed")).toEqual({ kind: "open" });
    expect(manifestAction(live, "closed")).toEqual({ kind: "open" });
    // Doors genuinely reopen, and episodes are per-episode, so a closed
    // episode on a running night can be followed by another.
    expect(manifestAction(live, "closed_after_open")).toEqual({ kind: "open" });
  });

  it("never offers Open on a session that is over or cancelled", () => {
    expect(manifestAction(done, "closed").kind).toBe("none");
    expect(manifestAction(done, "closed_after_open").kind).toBe("none");
    expect(manifestAction(cancelled, "closed").kind).toBe("none");
    const overReason = manifestAction(done, "closed");
    const cancelledReason = manifestAction(cancelled, "closed");
    expect(overReason.kind === "none" && overReason.why).toMatch(/night is over/);
    expect(cancelledReason.kind === "none" && cancelledReason.why).toMatch(/cancelled/);
  });

  it("still offers Close on an episode left open, whatever the session status", () => {
    // An open episode is a loose end rather than a door, so closing it stays
    // available after the night ends.
    for (const sess of [scheduled, live, done, cancelled]) expect(manifestAction(sess, "open")).toEqual({ kind: "close" });
  });

  it("renders the difference: the completed sample night loses the Open button and says why", () => {
    const done = EV.find((e) => e.status === "completed")!;
    const doneSession = done.sessions[0];
    const props = { pins: PINS, devices: DEV, scans: SC, flags: [], lookup: null, ctx: vm, basePath: base, timeZone: tz, now: PREVIEW_NOW };

    const over = html(<DoorStatus {...props} event={done} session={doneSession} episodes={closedEpisodes.filter((e) => e.sessionId === doneSession.sessionId)} />);
    expect(over).not.toContain("Open the check-in list");
    expect(over).toContain("This night is over");

    // Discrimination: the live night still offers it, so the assertion above
    // is about the session status and not about the button having been deleted.
    expect(manifestState(liveSession, false)).not.toBe("open");
    const running = html(<DoorStatus {...props} event={liveEvent} session={liveSession} episodes={closedEpisodes.filter((e) => e.sessionId === liveSession.sessionId)} />);
    expect(running).toContain("Open the check-in list");
    expect(running).not.toContain("This night is over");

    // And an episode left open offers Close on both.
    const stillOpen = html(<DoorStatus {...props} event={liveEvent} session={liveSession} episodes={openEpisode} />);
    expect(stillOpen).toContain("Close the check-in list");
  });
});

describe("U2 — no promise of a record the reader cannot open", () => {
  it("no surface says an action is recorded in the venue's activity", () => {
    for (const [name, render] of Object.entries(SURFACES)) {
      expect(visibleText(render()), `${name}`).not.toMatch(/recorded in your venue/i);
    }
  });

  it("the confirm note still says nothing is saved, and qualifies attributability", () => {
    const out = visibleText(SURFACES["event setup (live)"]());
    expect(out).toMatch(/In this demo nothing is saved/);
    expect(out).toMatch(/no screen to read that history on yet/);
  });
});

describe("no backend identifier in a tooltip", () => {
  it.each(Object.keys(SURFACES))("%s has no schema object in any title or data attribute", (name) => {
    const markup = SURFACES[name]();
    const attrs = (markup.match(/\s(?:title|data-read|aria-label)="[^"]*"/g) ?? []).join(" ");
    const hits = attrs.match(/\b(catalog|venue|kernel|ops|public)\.[a-z_]{3,}/g) ?? [];
    expect(hits, `${name} tooltips show ${hits.join(", ")}`).toEqual([]);
  });

  it("the tooltip guard can fail", () => {
    // Positive control: fed a tooltip with an identifier, the same extraction
    // must find it — otherwise the empty results above prove nothing.
    const planted = '<h2 title="Reads venue.scan">Live scan board</h2>';
    const attrs = (planted.match(/\s(?:title|data-read|aria-label)="[^"]*"/g) ?? []).join(" ");
    expect(attrs.match(/\bvenue\.[a-z_]{3,}/g)).toEqual(["venue.scan"]);
  });

  it("the post-action message names the action in plain words, never the call", () => {
    const out = html(<PreviewOutcome did="venue.close_door_manifest" />);
    expect(out).toContain("Nothing was saved.");
    expect(out).toContain("closed this door manifest episode");
    expect(out).not.toContain("venue.close_door_manifest");

    // An unmapped value must still be truthful without naming an object.
    const unknown = html(<PreviewOutcome did="venue.some_future_rpc" />);
    expect(unknown).not.toContain("venue.some_future_rpc");
    expect(unknown).toContain("it does nothing at all");

    // Every did value the app actually posts is mapped.
    for (const did of ["catalog.create_event", "catalog.set_event_status", "venue.create_ticket_type", "venue.create_inventory_batch", "venue.release_inventory_hold", "venue.open_door_manifest", "venue.close_door_manifest", "venue.create_door_pin", "venue.revoke_door_pin", "venue.request_export (operations_v1)", "escalate (venue note on venue.scan; adjudication is platform_risk)"]) {
      expect(demoActionLabel(did), did).not.toBeNull();
    }
  });
});

/**
 * The overview follows the stage of the event (owner direction, 2026-10-06):
 * "Open check-in" is wrong six days a week.
 */
describe("the overview leads with where the event actually is", () => {
  const sessionsOf = (e: (typeof EV)[number]) => e.sessions;
  const liveEvent = EV.find((e) => e.sessions.some((s) => s.status === "live"))!;
  const liveSess = sessionsOf(liveEvent).find((s) => s.status === "live")!;

  it("picks during / before / after from the data, not from the page", () => {
    const during = eventStage(EV, [{ event: liveEvent, session: liveSess }], PREVIEW_NOW);
    expect(during.stage).toBe("during");
    expect(during.event?.eventId).toBe(liveEvent.eventId);

    // Nothing on tonight → the next thing still to come.
    const before = eventStage(EV, [], PREVIEW_NOW);
    expect(before.stage).toBe("before");
    expect(before.event).not.toBeNull();
    expect(new Date(before.session!.startsAt).getTime()).toBeGreaterThanOrEqual(PREVIEW_NOW.getTime());

    // Nothing on and nothing to come → the most recent finished event.
    const onlyDone = EV.filter((e) => e.status === "completed");
    const after = eventStage(onlyDone, [], PREVIEW_NOW);
    expect(after.stage).toBe("after");
    expect(after.event?.status).toBe("completed");
  });

  it("offers a different primary action in each stage", () => {
    const render = (stageView: ReturnType<typeof eventStage>) => {
      const built = buildSignals(input());
      return html(
        <Tonight
          signals={built.signals}
          clear={built.clear}
          stageView={stageView}
          door={doorSummary([{ event: liveEvent, session: liveSess }], SC, DEV)}
          events={EV}
          available={stillAvailable(EV, TT, BT)}
          ctx={vm}
          basePath={base}
          timeZone={tz}
          now={PREVIEW_NOW}
        />,
      );
    };
    const during = render(eventStage(EV, [{ event: liveEvent, session: liveSess }], PREVIEW_NOW));
    const before = render(eventStage(EV, [], PREVIEW_NOW));
    const after = render(eventStage(EV.filter((e) => e.status === "completed"), [], PREVIEW_NOW));

    expect(during).toContain("Open check-in");
    expect(during).toMatch(/happening now/i);
    expect(during).toContain("Tonight at");

    expect(before).toContain("Get this event ready");
    expect(before).toContain("Next up at");
    expect(before).not.toContain("Open check-in");

    expect(after).toContain("Review this event");
    expect(after).toContain("Last event at");
    expect(after).toContain("sales are closed");
    expect(after).not.toContain("Open check-in");
  });
});

/**
 * The forced-state control only offers states the surface can actually show.
 * "No matches" needs a filter to do the filtering; on a surface without one
 * the control did nothing, which reads as a broken demo.
 */
describe("the demo state control offers only what the surface supports", () => {
  it("includes no matches on the filtered surfaces and excludes it elsewhere", () => {
    for (const s of ["events", "attendees"] as const) expect(statesFor(s)).toContain("nodata");
    for (const s of ["overview", "setup", "inventory", "door"] as const) expect(statesFor(s)).not.toContain("nodata");
    // Everything else stays available everywhere — this narrows one option, not the control.
    for (const s of ["overview", "events", "setup", "inventory", "attendees", "door"] as const) {
      for (const keep of ["live", "loading", "empty", "error", "denied"] as const) expect(statesFor(s), s).toContain(keep);
    }
  });

  it("the rendered shell drops the option, and keeps it where it works", () => {
    const shell = (active: "overview" | "events") =>
      html(
        <Shell ctx={vm} event={null} active={active}>
          <p>x</p>
        </Shell>,
      );
    expect(shell("events")).toContain("no matches");
    expect(shell("overview")).not.toContain("no matches");
  });
});
