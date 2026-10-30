import type { ReactElement, ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// The command forms call useRouter().refresh() after a receipt; outside Next's app router the hook needs a stub.
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));

import { EventSetup } from "@/components/events/EventSetup";
import { EventCommandPanel, type EventCommandKeys } from "@/components/events/EventCommandPanel";
import { PublishEventForm } from "@/components/events/EventCommandForms";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { TierCommands, type TierCommandKeys } from "@/components/inventory/TierCommands";
import { nextPublishTarget } from "@/lib/events/command-contract";
import { venueTimeZone } from "@/lib/events/zone";
import { PREVIEW_PRINCIPALS, canChangeCapacity, canEditEvents } from "@/lib/roles";
import type { PreviewContext } from "@/lib/preview";
import type { Event } from "@/lib/types";

/**
 * The two blockers the owner hit on the sandbox dashboard on 2026-10-29, both rendering faults rather
 * than missing commands:
 *
 *  1. The event page told him "the publish command (catalog.publish_event) has no dashboard wrapper in
 *     this slice" while PublishEventForm was wired and buried in a disclosure further down the page.
 *  2. The Tickets page of a brand-new event showed no controls at all: InventoryOverview returned its
 *     empty state early and dropped commandsSlot, so the control that creates the first tier — the only
 *     thing that clears that empty state — could never be reached.
 */

const ORG = "24232848-0bcf-4fa9-8040-c8bd2dc38ed2";
const VEN = "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75";
const EVT = "3fa7be1c-9d0e-4ab2-bf61-7c4de0a95fbb";
const SES = "8cd1fa73-4e2b-4df0-9a6c-1be7d3fa0c49";

const html = (el: ReactElement) => renderToStaticMarkup(el);
const base = `/o/${ORG}/v/${VEN}`;
const TZ = "America/New_York";

const draft = {
  eventId: EVT,
  venueId: VEN,
  orgId: ORG,
  title: "First night",
  status: "draft",
  resaleMode: "off",
  sessions: [{ sessionId: SES, eventId: EVT, label: "Doors", startsAt: "2026-12-06T01:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }],
} as Event;

const ids = { orgId: ORG, venueId: VEN, eventId: EVT };
// As readPreviewContext returns it in database mode (lib/preview.ts): counters off, preview writes off.
const db: PreviewContext = { role: "org_owner", state: "live", source: "database", countersAvailable: false, writesEnabled: false };
const fixtures: PreviewContext = { role: "org_owner", state: "live", source: "fixtures", countersAvailable: true, writesEnabled: true };

const setup = (ctx: PreviewContext, publishSlot?: ReactNode) =>
  html(<EventSetup event={draft} types={[]} batches={[]} ctx={ctx} basePath={base} timeZone={TZ} openManifestSessionIds={null} publishSlot={publishSlot} />);

const publishSlot = <PublishEventForm ids={ids} commandKey="k-publish" target="announced" />;

describe("the event status block carries the real publish command, never a claim that none exists", () => {
  it("database mode puts the command in the status block, with its minted key and target", () => {
    const h = setup(db, publishSlot);
    expect(h).toContain('name="commandKey" value="k-publish"');
    expect(h).toContain('name="target_status" value="announced"');
    expect(h).toContain(`name="eventId" value="${EVT}"`);
    expect(h).toContain("Move to Announced");
    // The fault itself: the stale sentence, and the dead preview form it sat under.
    expect(h).not.toContain("no dashboard wrapper");
    expect(h).not.toContain("catalog.publish_event");
    // Demo copy must not reach a surface that really writes.
    expect(h).not.toContain("In this demo nothing is saved");
  });

  it("with the gate shut the copy says commands are not enabled, and offers no control", () => {
    const h = setup(db);
    expect(h).toContain("aren&#x27;t enabled on this project yet");
    expect(h).not.toContain("no dashboard wrapper");
    expect(h).not.toContain('name="commandKey"');
    expect(h).not.toContain("Move to Announced");
  });

  it("the demo keeps its preview form, and never a command key", () => {
    const h = setup(fixtures);
    expect(h).toContain('value="catalog.publish_event announced"');
    expect(h).not.toContain('name="commandKey"');
    expect(h).not.toContain("aren&#x27;t enabled on this project yet");
  });

  it("one minted publish key is rendered once: the panel no longer offers a second control", () => {
    const keys: EventCommandKeys = { details: "k-details", publish: "k-publish", cancel: "k-cancel", sessionNew: "k-new", session: { [SES]: "k-session" }, capacity: { [SES]: "k-capacity" } };
    const panel = html(<EventCommandPanel ids={ids} event={draft} keys={keys} zone={venueTimeZone("database", TZ)} capacities={{}} />);
    expect(panel).toContain('name="commandKey" value="k-details"');
    expect(panel).not.toContain("k-publish");
    expect(panel).not.toContain("Move this event forward");
    // Both halves of the page together, as the route renders them.
    const page = setup(db, publishSlot) + panel;
    expect((page.match(/value="k-publish"/g) ?? []).length).toBe(1);
  });

  it("no control is offered where publish_event would refuse the move", () => {
    expect(nextPublishTarget("draft")).toBe("announced");
    expect(nextPublishTarget("completed")).toBeNull();
    expect(nextPublishTarget("cancelled")).toBeNull();
  });
});

describe("a new event's Tickets page can create its first tier", () => {
  const tierKeys: TierCommandKeys = { create: "k-create", price: {}, visibility: {}, rank: {}, capacity: {}, release: {}, saleWindow: {} };
  const tiers = <TierCommands ids={ids} types={[]} batches={[]} keys={tierKeys} sessionId={SES} timeZone={TZ} />;
  const overview = (commandsSlot?: ReactNode) =>
    html(<InventoryOverview event={draft} types={[]} batches={[]} holds={[]} ctx={db} basePath={base} timeZone={TZ} now={new Date("2026-11-01T00:00:00Z")} commandsSlot={commandsSlot} />);

  it("the empty state keeps the commands, so the one control that clears it is reachable", () => {
    const h = overview(tiers);
    expect(h).toContain("No ticket types yet");
    expect(h).toContain("Add a ticket type");
    expect(h).toContain('name="commandKey" value="k-create"');
    expect(h).toContain(`name="eventId" value="${EVT}"`);
  });

  it("negative control — with no commands minted, the same empty state offers nothing", () => {
    const h = overview(undefined);
    expect(h).toContain("No ticket types yet");
    expect(h).not.toContain("Add a ticket type");
    expect(h).not.toContain('name="commandKey"');
  });

  it("negative control — only the three full operators are minted commands at all", () => {
    // The predicate the Tickets route gates on (inventory/page.tsx): a narrower role gets no slot to drop.
    const full = ["org_owner", "org_admin", "venue_manager"];
    for (const p of PREVIEW_PRINCIPALS) expect(canEditEvents(p) || canChangeCapacity(p)).toBe(full.includes(p));
  });
});
