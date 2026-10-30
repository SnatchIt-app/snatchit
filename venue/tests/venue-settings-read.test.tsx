import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));

import { VenueDetailsForm, VenueTimezoneForm } from "@/components/venue/VenueSettingsForms";
import { venueTimeZone, PLATFORM_DEFAULT_TIME_ZONE } from "@/lib/events/zone";

/**
 * The owner's finding: venue settings said "Venue settings is not wired to the database yet" on a
 * production venue. Writes being off there is deliberate; the misleading copy and the MISSING READ were
 * the gap.
 *
 * The second half is the one that could have cost money: with commands on, the timezone form prefilled
 * `venueTimeZone(DATA_SOURCE, null)` — the PLATFORM DEFAULT — so an operator pressing save would have
 * written America/New_York over whatever the venue had stored. A Phoenix or Honolulu venue would have had
 * every door time wrong by hours, silently.
 */
const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const ids = { orgId: "0b150d75-2a79-4f68-bdf8-5786c6a52406", venueId: "7a9430e9-4d6f-474c-92cc-99bc56ea0b1e" };

describe("the venue time zone form fails closed when the stored zone is unreadable", () => {
  it("database mode has no readable venue zone yet, so the source is 'default', not 'venue'", () => {
    const z = venueTimeZone("database", null);
    expect(z.source).toBe("default");
    expect(z.zone).toBe(PLATFORM_DEFAULT_TIME_ZONE);
  });

  it("NEGATIVE CONTROL — with the zone unreadable, nothing is preselected and a choice is required", () => {
    const h = html(<VenueTimezoneForm ids={ids} commandKey="k-zone" timeZone={PLATFORM_DEFAULT_TIME_ZONE} stored={false} />);
    // The platform default must NOT arrive pre-chosen: submitting unchanged would overwrite the stored zone.
    expect(h).toContain('value=""');
    expect(h).toContain("Choose a time zone");
    expect(h).toContain("required");
    expect(h).toContain("isn&#x27;t readable yet");
    // and it must not claim the default is this venue's zone
    expect(h).not.toContain("(keep)");
  });

  it("with a genuinely stored zone the form does preselect it, so the fix did not just break the control", () => {
    const h = html(<VenueTimezoneForm ids={ids} commandKey="k-zone" timeZone="America/Phoenix" stored={true} />);
    expect(h).toContain("America/Phoenix");
    expect(h).not.toContain("Choose a time zone");
    expect(h).not.toContain("isn&#x27;t readable yet");
  });

  it("a stored zone outside the common list is offered as 'keep' rather than silently replaced", () => {
    const h = html(<VenueTimezoneForm ids={ids} commandKey="k-zone" timeZone="Europe/Lisbon" stored={true} />);
    expect(h).toContain("Europe/Lisbon (keep)");
  });
});

describe("the details form shows the stored values it can read", () => {
  it("prefills name and neighbourhood from the venue row", () => {
    const h = html(<VenueDetailsForm ids={ids} commandKey="k-details" venue={{ name: "The Grand", neighborhood: "wynwood" }} />);
    expect(h).toContain('value="The Grand"');
    expect(h).toContain('value="wynwood" selected');
  });

  it("NEGATIVE CONTROL — an unread value is empty, never invented", () => {
    const h = html(<VenueDetailsForm ids={ids} commandKey="k-details" venue={{ name: null, neighborhood: null }} />);
    expect(h).toContain('value=""');
    expect(h).not.toContain("Not set</option> <option");
  });
});
