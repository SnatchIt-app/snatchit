import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));

import { VenueDetailsForm, VenueTimezoneForm } from "@/components/venue/VenueSettingsForms";
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
