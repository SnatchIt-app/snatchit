import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, EVENTS, HOLDS, PREVIEW_NOW, TICKET_TYPES, VENUE } from "@/fixtures/venue";
import type { PreviewContext } from "@/lib/preview";
import { showCounters } from "@/lib/roles";
import { DataSourceError, NotWiredState } from "@/components/ui/DataSourceError";
import { EventsTable } from "@/components/events/EventsTable";
import { EventSetup } from "@/components/events/EventSetup";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";

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

describe("counters gate follows the data source", () => {
  const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: false };
  it("a manager in database mode sees remaining only, never fabricated sold/capacity", () => {
    expect(showCounters("venue_manager", db)).toBe(false);
    expect(showCounters("venue_manager", {})).toBe(true);
    const batches = BATCHES.map((b) => ({ ...b, capacity: b.capacity - b.held - b.sold, held: 0, sold: 0, countersKnown: false }));
    const table = html(<EventsTable events={EVENTS} batches={batches} types={TICKET_TYPES} holds={[]} ctx={db} basePath={base} venueName="Venue" timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />);
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
  it("events with unknown promoter counts render a dash, not zero", () => {
    const table = html(<EventsTable events={EVENTS.map((e) => ({ ...e, promoterCount: null }))} batches={BATCHES} types={TICKET_TYPES} holds={[]} ctx={{ role: "venue_manager", state: "live" }} basePath={base} venueName="V" timeZone={VENUE.timeZone} now={PREVIEW_NOW} filter={{}} />);
    expect(table).toContain("Promoters are not readable");
  });
});
