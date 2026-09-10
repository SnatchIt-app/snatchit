import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BATCHES, EVENTS, HOLDS, PREVIEW_NOW, TICKET_TYPES, VENUE } from "@/fixtures/venue";
import { mapGrants } from "@/lib/db/rows";
import type { PreviewContext } from "@/lib/preview";
import { derivePrincipal } from "@/lib/roles";
import { EntryGate } from "@/components/ui/EntryGate";
import { EventSetup } from "@/components/events/EventSetup";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { Shell } from "@/components/shell/Shell";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const base = "/o/smp_org_wynwood/v/smp_ven_room";
const VA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OA = "0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a0a";

describe("database-mode entry policy (spec §5: no grant → no dashboard)", () => {
  it("derives the display principal from verified grants with widest-capability precedence", () => {
    expect(derivePrincipal({ venueRoles: ["venue_manager"], orgRoles: [] })).toBe("venue_manager");
    expect(derivePrincipal({ venueRoles: ["venue_scanner", "venue_box_office"], orgRoles: [] })).toBe("venue_box_office");
    expect(derivePrincipal({ venueRoles: ["venue_manager"], orgRoles: ["org_owner"] })).toBe("org_owner");
    expect(derivePrincipal({ venueRoles: ["venue_finance"], orgRoles: ["org_member"] })).toBe("venue_finance");
    expect(derivePrincipal({ venueRoles: [], orgRoles: [] })).toBeNull();
  });
  it("only grants at the route's venue/org count; unknown labels are dropped, never guessed", () => {
    const g = mapGrants(
      [
        { venue_id: VA, role: "venue_finance" },
        { venue_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", role: "venue_manager" },
        { venue_id: VA, role: "venue_promoter" },
      ],
      [{ org_id: "other", role: "org_owner" }],
      VA,
      OA,
    );
    expect(g).toEqual({ venueRoles: ["venue_finance"], orgRoles: [] });
    expect(derivePrincipal(g)).toBe("venue_finance");
  });
  it("renders the denial with a sign-out and nothing about the venue for a grant-less caller", () => {
    const out = html(<EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />);
    expect(out).toContain("You don&#x27;t have access to this.");
    expect(out).toContain("holds no staff or organization role at this venue");
    expect(out).toContain('action="/logout"');
    expect(html(<EntryGate entry={{ kind: "failure", failure: { ok: false, kind: "auth", message: "No session", read: "auth.getClaims" } }} loginHref="/login?next=%2Fx" retryHref="/x" />)).toContain("Sign in to continue");
    expect(html(<EntryGate entry={{ kind: "ok", grants: { venueRoles: ["venue_manager"], orgRoles: [] } }} loginHref="/login" retryHref="/" />)).toBe("");
  });
});

describe("database mode offers no write control", () => {
  const db: PreviewContext = { role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false };
  it("event setup: no status form, no danger zone, an explicit not-wired note", () => {
    const out = html(<EventSetup event={EVENTS[1]} types={TICKET_TYPES} batches={BATCHES} ctx={db} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(out).toContain("Status changes are not available in database mode");
    expect(out).not.toContain('name="did"');
    expect(out).not.toContain("Danger zone");
    expect(out).not.toContain("would call");
  });
  it("inventory: no release form and no capacity edit banner", () => {
    const out = html(<InventoryOverview event={EVENTS[0]} types={TICKET_TYPES.filter((t) => t.eventId === EVENTS[0].eventId)} batches={BATCHES} holds={HOLDS} ctx={db} basePath={base} timeZone={VENUE.timeZone} now={PREVIEW_NOW} />);
    expect(out).not.toContain("venue.release_inventory_hold");
    expect(out).not.toContain("Open on a larger screen to edit");
  });
  it("fixture mode keeps its interactive preview forms", () => {
    const fx: PreviewContext = { role: "venue_manager", state: "live", source: "fixtures", countersAvailable: true, writesEnabled: true };
    const out = html(<EventSetup event={EVENTS[1]} types={TICKET_TYPES} batches={BATCHES} ctx={fx} basePath={base} timeZone={VENUE.timeZone} openManifestSessionIds={new Set()} />);
    expect(out).toContain('name="did"');
  });
  it("shell shows grant-derived capabilities and no role switch in database mode", () => {
    const out = html(
      <Shell ctx={{ role: "venue_finance", state: "live", source: "database", countersAvailable: false, writesEnabled: false }} event={null} active="events" signedInAs="fin@example.test">
        <p>x</p>
      </Shell>,
    );
    expect(out).toContain("Capabilities come from your grants");
    expect(out).toContain("Venue finance");
    expect(out).not.toContain('name="role"');
    expect(out).toContain("fin@example.test");
  });
});
