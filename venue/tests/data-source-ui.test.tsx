import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, EVENTS, HOLDS, PREVIEW_NOW, TICKET_TYPES, VENUE } from "@/fixtures/venue";
import type { PreviewContext } from "@/lib/preview";
import { showCounters } from "@/lib/roles";
import { DataSourceError, NotWiredState } from "@/components/ui/DataSourceError";
import { EventsTable } from "@/components/events/EventsTable";
import { EventSetup } from "@/components/events/EventSetup";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { RESALE_LABEL, resaleLabel } from "@/lib/events";
import type { Event } from "@/lib/types";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const base = "/o/smp_org_wynwood/v/smp_ven_room";

describe("database-mode failures are explicit", () => {
  const kinds = ["auth", "permission", "config", "not_exposed", "transport", "error"] as const;
  it.each(kinds)("renders a distinct message for %s", (kind) => {
    const out = html(<DataSourceError failure={{ ok: false, kind, message: "detail-xyz", code: "C0DE", read: "venue_api.events" }} loginHref="/login" retryHref="/r" />);
    expect(out).toContain("C0DE");
    if (kind === "auth") expect(out).toContain("Sign in to continue");
    if (kind === "permission") expect(out).toContain("You don&#x27;t have access to this.");
    if (kind === "not_exposed") expect(out).toContain("does not expose the <code class=\"font-mono\">venue_api</code> schema");
    if (kind === "config") expect(out).toContain("Database mode is not configured");
    if (kind === "transport") expect(out).toContain("Couldn&#x27;t reach the database");
    if (kind === "error") expect(out).toContain("venue_api.events");
    expect(out).not.toMatch(/sample|fixture/i);
  });
  it("fixture-only surfaces say so instead of showing sample data", () => {
    const out = html(<NotWiredState surface="Door status" />);
    expect(out).toContain("Door status is not wired to the database yet");
    expect(out).toContain("sample data is never shown in database mode");
  });
});

describe("a draft's resale mode that RLS hides is shown as not readable", () => {
  const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false };
  const draft: Event = { ...EVENTS[0], status: "draft", resaleMode: "not_readable" };
  it("the label says it is not readable until published, and names no mode", () => {
    expect(RESALE_LABEL.not_readable).toMatch(/not readable until (the event is )?published/i);
    const modes = Object.entries(RESALE_LABEL).filter(([k]) => k !== "not_readable").map(([, v]) => v);
    for (const m of modes) expect(RESALE_LABEL.not_readable).not.toContain(m);
  });
  it("the events list and event setup show it, never a resale mode, for the draft", () => {
    const table = html(<EventsTable events={[draft]} batches={[]} types={[]} holds={[]} ctx={db} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />);
    expect(table).toContain(RESALE_LABEL.not_readable);
    const setup = html(<EventSetup event={draft} types={[]} batches={[]} ctx={db} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(setup).toContain(`Can tickets be passed on? ${RESALE_LABEL.not_readable}`);
    expect(setup).toContain("can&#x27;t be read until the event is published");
    for (const m of ["Buy now", "Auction", "Transfers only"]) expect(setup).not.toContain(`Can tickets be passed on? ${m}`);
  });
});

// The other RLS hide (rows.ts): every venue-wide policy of a venue that is not approved. Such an event is not a
// draft, so "until published" would be untrue; the line names the venue's approval instead.
describe("an event at a venue that is not approved shows its resale mode as not readable, with that reason", () => {
  const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false };
  const atPendingVenue: Event = { ...EVENTS[0], status: "announced", resaleMode: "not_readable" };
  it("the label names the venue's approval, not publishing, and no mode; drafts and readable modes are unchanged", () => {
    expect(resaleLabel(atPendingVenue)).toMatch(/not readable until the venue is approved/i);
    expect(resaleLabel(atPendingVenue)).not.toMatch(/publish/i);
    const modes = Object.entries(RESALE_LABEL).filter(([k]) => k !== "not_readable").map(([, v]) => v);
    for (const m of modes) expect(resaleLabel(atPendingVenue)).not.toContain(m);
    expect(resaleLabel({ ...atPendingVenue, status: "draft" })).toBe(RESALE_LABEL.not_readable);
    expect(resaleLabel({ ...atPendingVenue, resaleMode: "buy_now" })).toBe(RESALE_LABEL.buy_now);
  });
  it("the events list and event setup give the venue reason, never 'until published' or a mode", () => {
    const label = resaleLabel(atPendingVenue);
    const table = html(<EventsTable events={[atPendingVenue]} batches={[]} types={[]} holds={[]} ctx={db} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />);
    expect(table).toContain(label);
    expect(table).not.toContain(RESALE_LABEL.not_readable);
    const setup = html(<EventSetup event={atPendingVenue} types={[]} batches={[]} ctx={db} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(setup).toContain(`Can tickets be passed on? ${label}`);
    expect(setup).toContain("This venue isn&#x27;t approved yet");
    expect(setup).not.toContain("This event is a draft");
    for (const m of ["Off", "Buy now", "Auction", "Transfers only"]) expect(setup).not.toContain(`Can tickets be passed on? ${m}`);
  });
});

describe("counters gate follows the data source", () => {
  // As readPreviewContext returns it in database mode (lib/preview.ts): counters off, writes off.
  const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false };
  it("a manager in database mode sees remaining only, never fabricated sold/capacity", () => {
    expect(showCounters("venue_manager", db)).toBe(false);
    expect(showCounters("venue_manager", {})).toBe(true);
    const batches = BATCHES.map((b) => ({ ...b, capacity: b.capacity - b.held - b.sold, held: 0, sold: 0, countersKnown: false }));
    const table = html(<EventsTable events={EVENTS} batches={batches} types={TICKET_TYPES} holds={[]} ctx={db} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />);
    expect(table).toContain("available");
    expect(table).not.toMatch(/\d+ \/ \d+/);
    const setup = html(<EventSetup event={EVENTS[0]} types={TICKET_TYPES} batches={batches} ctx={db} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(setup).not.toContain("Sold / capacity");
    expect(setup).not.toContain("Gross");
    const inv = html(<InventoryOverview event={EVENTS[0]} types={TICKET_TYPES.filter((t) => t.eventId === EVENTS[0].eventId)} batches={batches} holds={HOLDS} ctx={db} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} />);
    expect(inv).not.toContain("Inventory warnings");
    expect(inv).not.toContain("Capacity change");
    expect(inv).toContain("available");
  });
  it("an unknown figure renders a dash with a reason, never a zero", () => {
    // The promoter column is gone (it could never show anything but a dash
    // here), but the rule it guarded still matters: a number this data source
    // cannot produce must not be rendered as 0. It now applies to sold/capacity.
    const noReleases = html(
      <EventsTable events={EVENTS} batches={[]} types={[]} holds={[]} ctx={{ role: "venue_manager", state: "live" }} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />,
    );
    expect(noReleases).toContain("No releases yet");
    expect(noReleases).not.toContain("0 of 0 sold");

    // Discrimination: with releases present, the real figure is shown.
    const withReleases = html(
      <EventsTable events={EVENTS} batches={BATCHES} types={TICKET_TYPES} holds={[]} ctx={{ role: "venue_manager", state: "live" }} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />,
    );
    expect(withReleases).toContain("411 of 520 sold");
  });
});
