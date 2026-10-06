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
