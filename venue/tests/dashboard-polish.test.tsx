import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }) }));

import { EventsTable } from "@/components/events/EventsTable";
import { CreateEventForm, PublishEventForm, EventDetailsForm } from "@/components/events/EventCommandForms";
import { EventSetup } from "@/components/events/EventSetup";
import { Shell } from "@/components/shell/Shell";
import { EVENTS, BATCHES, TICKET_TYPES, PREVIEW_NOW, VENUE } from "@/fixtures/venue";
import type { PreviewContext } from "@/lib/preview";

const ctx: PreviewContext = { source: "fixtures", role: "venue_manager", state: "live", countersAvailable: true, writesEnabled: true };
const basePath = "/o/sample/v/sample";
const props = { events: EVENTS, batches: BATCHES, types: TICKET_TYPES, holds: [], ctx, basePath, timeZone: VENUE.timeZone, now: PREVIEW_NOW, filter: {} };
const ids = { orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", venueId: "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75" };

describe("event presentation keeps the same filtered source data", () => {
  it("the status chart counts filtered events and includes a readable table", () => {
    const draft = EVENTS.find((event) => event.status === "draft")!;
    const out = renderToStaticMarkup(<EventsTable {...props} view="chart" filter={{ q: draft.title }} />);
    expect(out).toContain("1 matching events");
    expect(out).toContain("Event status counts for the current filters");
    expect(out).toContain("Draft");
    expect(out).not.toContain("On sale");
    expect(out).not.toContain("Revenue");
  });
  it.each(["cards", "table"] as const)("%s applies the search before rendering titles", (view) => {
    const selected = EVENTS[0];
    const out = renderToStaticMarkup(<EventsTable {...props} view={view} filter={{ q: selected.title }} />);
    expect(out).toContain(selected.title.replaceAll("&", "&amp;"));
    for (const other of EVENTS.filter((event) => event.eventId !== selected.eventId && !event.title.includes(selected.title))) expect(out).not.toContain(other.title);
    expect(out).toContain(`${basePath}/events/${selected.eventId}`);
  });
  it("table view never manufactures sold counts when only remaining is known", () => {
    const out = renderToStaticMarkup(<EventsTable {...props} view="table" ctx={{ ...ctx, source: "database", countersAvailable: false }} batches={BATCHES.map((batch) => ({ ...batch, countersKnown: false, sold: 0, held: 0 }))} />);
    expect(out).not.toMatch(/\d+ of \d+ sold/);
    expect(out).toContain("remaining, all releases");
  });
});

describe("the draft and publishing steps remain separate", () => {
  it("the onepage draft form retains all first-session fields and the original command key", () => {
    const out = renderToStaticMarkup(<CreateEventForm ids={ids} commandKey="original-command-key" timeZone="America/Phoenix" />);
    for (const field of ["title", "starts_local", "ends_local", "doors_local", "session_label", "timeZone"]) expect(out).toContain(`name="${field}"`);
    expect(out).toContain('name="commandKey" value="original-command-key"');
    expect(out).toContain("Save draft");
    expect(out).toContain("Preview draft");
    expect(out).toContain("astryx-button");
    expect(out).not.toContain('name="target_status"');
    expect(out).toContain("Each new save can create another draft.");
  });
  it("publishing an announcement never submits the sales transition", () => {
    const out = renderToStaticMarkup(<PublishEventForm ids={ids} commandKey="publish-key" target="announced" />);
    expect(out).toContain("Publish event");
    expect(out).toContain('name="target_status" value="announced"');
    expect(out).toContain("This does not open ticket sales");
    expect(out).not.toContain('value="on_sale"');
  });
  it("saved event setup composes details and tickets once within the same workspace", () => {
    const out = renderToStaticMarkup(<EventSetup event={EVENTS[0]} types={TICKET_TYPES.filter((ticket) => ticket.eventId === EVENTS[0].eventId)} batches={BATCHES} ctx={ctx} basePath={basePath} timeZone={VENUE.timeZone} openManifestSessionIds={null} commandsSlot={<p>Details editor marker</p>} ticketsSlot={<p>Ticket editor marker</p>} />);
    expect(out.match(/Details editor marker/g)).toHaveLength(1);
    expect(out.match(/Ticket editor marker/g)).toHaveLength(1);
    for (const anchor of ["#event-details", "#event-dates", "#types", "#event-preview", "#status"]) expect(out).toContain(`href="${anchor}"`);
    expect(out).toContain("Each section saves separately");
  });
});

it("settings navigation does not select All events", () => {
  const out = renderToStaticMarkup(<Shell ctx={ctx} event={null} active="settings"><h1>Venue settings</h1></Shell>);
  const currentLinks = [...out.matchAll(/<a[^>]*aria-current="page"[^>]*>.*?<\/a>/g)].map((match) => match[0]);
  expect(currentLinks).toHaveLength(2); // sidebar and phone navigation both show settings
  expect(currentLinks.every((link) => link.includes("Venue settings"))).toBe(true);
  expect(out.match(/<h1/g)).toHaveLength(1);
});


it("unread description, category and genres are excluded until individually selected", () => {
  const out = renderToStaticMarkup(<EventDetailsForm ids={ids} commandKey="keep-key" status="draft" currentTitle="Saved title" />);
  expect(out.match(/<fieldset disabled=""/g)).toHaveLength(3);
  for (const label of ["Change description", "Change category", "Change genres"]) expect(out).toContain(label);
  expect(out).toContain("Only the fields you choose to edit will change");
  expect(out).toContain('name="title"');
});
