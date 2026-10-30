import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));

import { VenueDetailsForm, VenueTimezoneForm } from "@/components/venue/VenueSettingsForms";
import { EventsTable } from "@/components/events/EventsTable";
import { Tonight } from "@/components/overview/Tonight";
import type { Event } from "@/lib/types";
import type { PreviewContext } from "@/lib/preview";
import { PLATFORM_DEFAULT_TIME_ZONE, renderTimeZone, venueTimeZone } from "@/lib/events/zone";
import { VENUE } from "@/fixtures/venue";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const ids = { orgId: "0b150d75-2a79-4f68-bdf8-5786c6a52406", venueId: "7a9430e9-4d6f-474c-92cc-99bc56ea0b1e" };

/**
 * The fixture zone used to drive EIGHT database-mode render sites via `p.timeZone`.
 *
 * Every one of them LOOKED right, because `VENUE.timeZone` and `PLATFORM_DEFAULT_TIME_ZONE` are both
 * America/New_York. A test written with a New York fixture would pass against the bug — so these use a
 * deliberately NON-New-York zone, which is the only way the two sources can be told apart.
 */
const NOT_NY = "America/Phoenix";

describe("the fixture time zone never reaches database mode (8 render sites)", () => {
  it("database mode takes the event's projected zone, never the fixture's", () => {
    expect(renderTimeZone("database", NOT_NY, "Pacific/Honolulu")).toBe(NOT_NY);
  });

  it("NEGATIVE CONTROL — with no event in scope it falls to the PLATFORM default, not the fixture", () => {
    // The discriminating fixture: if this returned the fixture zone the assertion would read
    // "Pacific/Honolulu", which is exactly the old behaviour.
    expect(renderTimeZone("database", null, "Pacific/Honolulu")).toBe(PLATFORM_DEFAULT_TIME_ZONE);
    expect(renderTimeZone("database", null, "Pacific/Honolulu")).not.toBe("Pacific/Honolulu");
    expect(renderTimeZone("database", "   ", "Pacific/Honolulu")).toBe(PLATFORM_DEFAULT_TIME_ZONE);
  });

  it("NEGATIVE CONTROL — fixtures mode still uses the fixture zone, so the fix did not break the demo", () => {
    expect(renderTimeZone("fixtures", null, "Pacific/Honolulu")).toBe("Pacific/Honolulu");
    expect(renderTimeZone("fixtures", NOT_NY, VENUE.timeZone)).toBe(VENUE.timeZone);
  });
});

describe("the venue's own stored zone is used once 195 exposes it", () => {
  it("a stored zone gives source 'venue'; null still gives 'default'", () => {
    expect(venueTimeZone("database", NOT_NY)).toEqual({ zone: NOT_NY, source: "venue" });
    expect(venueTimeZone("database", null)).toEqual({ zone: PLATFORM_DEFAULT_TIME_ZONE, source: "default" });
  });
});

describe("a stored zone outside the common list submits itself, not an empty value", () => {
  it("the 'keep' option carries the stored zone (E-F13)", () => {
    const h = html(<VenueTimezoneForm ids={ids} commandKey="k" timeZone="Europe/Lisbon" stored={true} />);
    expect(h).toContain('value="Europe/Lisbon" selected');
    expect(h).toContain("Europe/Lisbon (keep)");
    // The defect: the keep option used to carry value="" and was selected by default, so submitting
    // unchanged sent an EMPTY timezone while the label promised to preserve it.
    expect(h).not.toContain('value="" selected');
  });

  it("NEGATIVE CONTROL — an unreadable zone still preselects nothing and requires a choice", () => {
    const h = html(<VenueTimezoneForm ids={ids} commandKey="k" timeZone={PLATFORM_DEFAULT_TIME_ZONE} stored={false} />);
    expect(h).toContain('value="" selected');
    expect(h).toContain("Choose a time zone");
    expect(h).toContain("required");
    expect(h).not.toContain("(keep)");
  });

  it("a common stored zone preselects itself without a keep option", () => {
    const h = html(<VenueTimezoneForm ids={ids} commandKey="k" timeZone={NOT_NY} stored={true} />);
    expect(h).toContain(`value="${NOT_NY}" selected`);
    expect(h).not.toContain("(keep)");
  });
});

describe("the details form prefills the columns 195 adds", () => {
  it("address and capacity arrive from the venue row", () => {
    const h = html(<VenueDetailsForm ids={ids} commandKey="k" venue={{ name: "The Grand", neighborhood: "wynwood", address: "1 Example Ave", capacityHint: 450 }} />);
    expect(h).toContain('value="1 Example Ave"');
    expect(h).toContain('value="450"');
  });

  it("NEGATIVE CONTROL — absent values stay empty, never invented", () => {
    const h = html(<VenueDetailsForm ids={ids} commandKey="k" venue={{ name: null, neighborhood: null, address: null, capacityHint: null }} />);
    expect(h).not.toContain('value="0"');
    expect(h).toContain('value=""');
  });
});

/**
 * A list row and that event's own page must not disagree about what time the night starts.
 *
 * dbListEvents selected no `timezone`, so the events list and the venue overview rendered every row in
 * the PLATFORM DEFAULT while the event's own page used its projected zone (162). One event, two times —
 * and invisible in New York, which is why the fixture below is Honolulu.
 */
describe("every event row renders in its own zone (list and overview)", () => {
  // 2026-12-06T06:00:00Z is "Sat, Dec 5" in Honolulu and "Sun, Dec 6" in New York. The DATE is the
  // discriminator, so a wrong zone cannot hide behind a similar-looking time.
  const SESSION = { sessionId: "5e55e55e-0a0c-4b0d-8e0f-0000000000a2", eventId: "3fa7be1c-9d0e-4ab2-bf61-7c4de0a95fbb", label: null, startsAt: "2026-12-06T06:00:00Z", doorsAt: null, endsAt: null, status: "scheduled" as const, doorOpenAt: null };
  const honolulu: Event = { eventId: SESSION.eventId, orgId: ids.orgId, venueId: ids.venueId, title: "Island night", status: "on_sale", resaleMode: "off", promoterCount: null, timeZone: "Pacific/Honolulu", sessions: [SESSION] };
  const db: PreviewContext = { role: "org_owner", state: "live", source: "database", countersAvailable: false, writesEnabled: false, verifiedRole: true, scope: { orgId: ids.orgId, venueId: ids.venueId } };
  const NOW = new Date("2026-11-01T00:00:00Z");
  const base = `/o/${ids.orgId}/v/${ids.venueId}`;

  const table = (e: Event) =>
    html(<EventsTable events={[e]} batches={[]} types={[]} holds={[]} ctx={db} basePath={base} timeZone={PLATFORM_DEFAULT_TIME_ZONE} now={NOW} filter={{}} />);
  const overview = (e: Event) =>
    html(
      <Tonight
        signals={[]} clear={[]} door={null}
        stageView={{ stage: "before", event: e, session: e.sessions[0] }}
        events={[e]} available={0} ctx={db} basePath={base}
        timeZone={PLATFORM_DEFAULT_TIME_ZONE} now={NOW}
      />,
    );

  it("the events LIST renders the row in the event's own zone", () => {
    const h = table(honolulu);
    expect(h).toContain("Sat, Dec 5"); // Honolulu
    expect(h).not.toContain("Sun, Dec 6"); // the page zone, which it used to use for every row
  });

  it("NEGATIVE CONTROL — an event with no readable zone falls back to the page zone", () => {
    const h = table({ ...honolulu, timeZone: null });
    expect(h).toContain("Sun, Dec 6");
    expect(h).not.toContain("Sat, Dec 5");
  });

  it("the venue OVERVIEW renders the in-scope event in its own zone", () => {
    const h = overview(honolulu);
    expect(h).toContain("Sat, Dec 5"); // Honolulu
    expect(h).not.toContain("Sun, Dec 6"); // the page zone
  });

  it("NEGATIVE CONTROL — the overview falls back to the page zone when the event has none", () => {
    const h = overview({ ...honolulu, timeZone: null });
    expect(h).toContain("Sun, Dec 6");
    expect(h).not.toContain("Sat, Dec 5");
  });

  it("the list READ asks for the projection, so a row can have its own zone at all", async () => {
    const src = await import("node:fs").then((fs) => fs.readFileSync("src/lib/db/adapters.ts", "utf8"));
    expect(src.match(/from\("events"\)\.select\("([^"]+)"\)\.eq\("venue_id"/)?.[1]).toContain("timezone");
  });
});
