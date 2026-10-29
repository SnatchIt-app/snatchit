import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// The forms call useRouter().refresh() after a receipt; outside Next's app router the hook needs a stub.
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));
import { TierCommands } from "@/components/inventory/TierCommands";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { mergeCounters } from "@/lib/db/counters-merge";
import type { CounterRow } from "@/lib/db/counters";
import type { PreviewContext } from "@/lib/preview";
import type { Event, InventoryBatch, TicketType } from "@/lib/types";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const EV: Event = { eventId: "9a000000-0000-4000-8000-000000000001", venueId: "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75", orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", title: "Pop-up", status: "on_sale", resaleMode: "off", sessions: [{ sessionId: "5e55e55e-0000-4000-8000-000000000001", eventId: "9a000000-0000-4000-8000-000000000001", label: "Doors", startsAt: "2026-11-30T03:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }] } as Event;
const TYPES: TicketType[] = [{ ticketTypeId: "7a000000-0000-4000-8000-000000000001", eventId: EV.eventId, name: "GA", kind: "admission", priceMinor: 2500, visibility: "public" }];
const B1 = "b1000000-0000-4000-8000-000000000001";
const BATCHES: InventoryBatch[] = [{ batchId: B1, ticketTypeId: TYPES[0].ticketTypeId, sessionId: EV.sessions[0].sessionId, releaseKind: "public_sale", capacity: 0, held: 0, sold: 0, lowThreshold: 5, countersKnown: false }];
const rows: CounterRow[] = [{ batch_id: B1, ticket_type_id: TYPES[0].ticketTypeId, event_session_id: EV.sessions[0].sessionId, release_kind: "public_sale", capacity: 50, held: 3, sold: 20, remaining: 27 }];

describe("mergeCounters — real numbers only where the staff read covered the batch", () => {
  it("merges by batch id, marks countersKnown, and says when the set is complete", () => {
    const m = mergeCounters(BATCHES, rows);
    expect(m.complete).toBe(true);
    expect(m.batches[0]).toMatchObject({ capacity: 50, held: 3, sold: 20, countersKnown: true });
  });
  it("a batch with no row keeps remaining-only and the set is incomplete; rows never invent batches; no batches = not complete", () => {
    const extra: InventoryBatch = { ...BATCHES[0], batchId: "b2000000-0000-4000-8000-000000000002" };
    const m = mergeCounters([...BATCHES, extra], rows);
    expect(m.complete).toBe(false);
    expect(m.batches[1]).toMatchObject({ countersKnown: false, capacity: 0 });
    expect(m.batches).toHaveLength(2);
    expect(mergeCounters([], rows)).toEqual({ batches: [], complete: false });
  });
});

describe("TierCommands — every form carries its own minted command key and names the server's refusal shape", () => {
  const ids = { orgId: EV.orgId, venueId: EV.venueId, eventId: EV.eventId };
  const keys = { create: "k-create", price: { [TYPES[0].ticketTypeId]: "k-price" }, visibility: { [TYPES[0].ticketTypeId]: "k-vis" }, rank: { [TYPES[0].ticketTypeId]: "k-rank" }, capacity: { [B1]: "k-cap" }, release: { "7a000000-0000-4000-8000-000000000001": "k-release" }, saleWindow: { "7a000000-0000-4000-8000-000000000001": "k-window" } };
  const merged = mergeCounters(BATCHES, rows).batches;
  it("renders price, visibility, rank, capacity and add forms, each with its hidden key and the event ids", () => {
    const h = html(createElement(TierCommands, { ids, types: TYPES, batches: merged, keys, sessionId: EV.sessions[0].sessionId, timeZone: "America/New_York" }));
    for (const k of ["k-create", "k-price", "k-vis", "k-rank", "k-cap"]) expect(h).toContain(`name="commandKey" value="${k}"`);
    expect((h.match(/<form /g) ?? []).length).toBe(7); // + release and sale window (P2)
    expect(h).toContain('name="reasonCode"');
    expect(h).toContain('min="0.01"');
    expect(h).toContain("floor 23"); // held + sold: the server's refusal floor, said before typing
    expect(h).toContain(`name="eventId" value="${EV.eventId}"`);
    expect(h).not.toContain("Saved");
  });

  it("binds the P2 release and sale-window controls, each carrying its own minted key", () => {
    const h = html(createElement(TierCommands, { ids, types: TYPES, batches: merged, keys, sessionId: EV.sessions[0].sessionId, timeZone: "America/New_York" }));
    // The release control: a kind, a capacity, the session it releases on — and NO shard field, because
    // 081:355 refuses any shard count above 0.
    expect(h).toContain('name="releaseKind"');
    expect(h).toContain('name="capacity"');
    expect(h).toContain(`name="sessionId" value="${EV.sessions[0].sessionId}"`);
    expect(h).not.toContain('name="shardCount"');
    expect(h).not.toContain('name="shard_count"');
    // The sale window: a wall clock each side plus the venue zone, never an instant from the browser.
    expect(h).toContain('name="saleStartsLocal"');
    expect(h).toContain('name="saleEndsLocal"');
    expect(h).toContain('name="timeZone" value="America/New_York"');
    expect(h).toContain('type="datetime-local"');
    // Both new keys reach their forms.
    for (const k of ["k-release", "k-window"]) expect(h).toContain(`name="commandKey" value="${k}"`);
    // The operator is told, at the control, that a resend is not a replay.
    expect(h).toContain("Releasing twice releases the inventory twice");
  });

  it("offers no release control when the event has no session to release on", () => {
    const h = html(createElement(TierCommands, { ids, types: TYPES, batches: merged, keys, sessionId: null, timeZone: "America/New_York" }));
    expect(h).not.toContain('name="releaseKind"');
    expect(h).toContain('name="saleStartsLocal"'); // the window does not need a session
  });
  it("a batch without counters gets no floor and no default capacity (nothing invented)", () => {
    const h = html(createElement(TierCommands, { ids, types: TYPES, batches: BATCHES, keys, sessionId: null, timeZone: "America/New_York" }));
    expect(h).not.toContain("floor");
    const tag = h.match(/<input[^>]*name="newCapacity"[^>]*>/)?.[0] ?? "";
    expect(tag, "the capacity input is rendered").not.toBe("");
    expect(tag).toContain('min="0"');
    expect(tag).not.toMatch(/value="\d/);
  });
});

describe("InventoryOverview — the commands slot replaces the demo capacity panel", () => {
  const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: true, writesEnabled: false };
  it("with a slot: the slot renders and the demo panel does not; without: the demo panel stays", () => {
    const merged = mergeCounters(BATCHES, rows).batches;
    const base = { event: EV, types: TYPES, batches: merged, holds: [], ctx: db, basePath: "/o/x/v/y", timeZone: "America/New_York", now: new Date("2026-11-29T00:00:00Z") };
    const withSlot = html(createElement(InventoryOverview, { ...base, commandsSlot: createElement("p", { id: "slot" }, "commands here") }));
    expect(withSlot).toContain('id="slot"');
    expect(withSlot).not.toContain("Not available in this demo");
    expect(withSlot).toContain("20"); // sold from the merged counters
    const without = html(createElement(InventoryOverview, base));
    expect(without).toContain("Not available in this demo");
  });
});
