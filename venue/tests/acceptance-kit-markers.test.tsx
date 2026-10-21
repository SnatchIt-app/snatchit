/**
 * The acceptance kit (scripts/acceptance/accept.mjs) decides PASS/FAIL by looking for fixed
 * strings in the rendered page text. If the app's copy moves and the kit's markers do not,
 * every denial check false-FAILs (or, worse, a check that expects "not denied" false-PASSes).
 * This reads the kit's own marker constants and renders the v2 components that must carry them.
 */
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { EntryGate } from "@/components/ui/EntryGate";
import { DeniedState } from "@/components/ui/State";
import { DataSourceError, NotWiredState } from "@/components/ui/DataSourceError";
import { Shell } from "@/components/shell/Shell";
import VenueLoading from "@/app/o/[org]/v/[venue]/loading";
import { EventsTable } from "@/components/events/EventsTable";
import { mapBatches } from "@/lib/db/rows";
import type { Event, TicketType } from "@/lib/types";
import { roleLabelClaimed } from "../scripts/acceptance/lib/checks.mjs";

const kit = readFileSync(new URL("../scripts/acceptance/accept.mjs", import.meta.url), "utf8");
function marker(name: string): string {
  const m = kit.match(new RegExp(`^const ${name} = (["'])(.+)\\1;$`, "m"));
  if (!m) throw new Error(`kit constant ${name} not found in accept.mjs`);
  return m[2];
}
/** Roughly what CDP innerText gives the kit: tags gone, entities decoded. */
const text = (el: React.ReactElement) =>
  renderToStaticMarkup(el)
    .replace(/<[^>]+>/g, " ")
    .replace(/&#x27;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ");

const DENIED = marker("DENIED");
const NO_GRANT = marker("NO_GRANT");
const SIGN_IN = marker("SIGN_IN");

describe("acceptance kit markers match the v2 copy", () => {
  it("grant-less entry (C5, H5, H7, C3, revocation) carries DENIED and NO_GRANT", () => {
    const t = text(<EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />);
    expect(t).toContain(DENIED);
    expect(t).toContain(NO_GRANT);
  });
  it("a malformed or foreign route (C4, C6 standalone) carries DENIED", () => {
    expect(text(<DeniedState standalone surface="This venue" reason="This account holds no role at the venue in this link." />)).toContain(DENIED);
  });
  it("an unreadable or foreign event (C4 event paths) carries DENIED and Back to events", () => {
    const t = text(<DeniedState surface="This event" reason="x" alternative={{ label: "Back to events", href: "/e" }} />);
    expect(t).toContain(DENIED);
    expect(t).toContain("Back to events");
  });
  it("signed out (H1, H2, H6) carries SIGN_IN and not DENIED", () => {
    const t = text(<EntryGate entry={{ kind: "failure", failure: { ok: false, kind: "auth", message: "No session", read: "auth.getClaims" } }} loginHref="/login" retryHref="/" />);
    expect(t).toContain(SIGN_IN);
    expect(t).not.toContain(DENIED);
  });
  it("an entered dashboard (C7 'not denied') does not carry DENIED", () => {
    const t = text(
      <Shell ctx={{ role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false, verifiedRole: true, scope: { orgId: "5a4d0b0e-0000-4000-8000-00000000000a", venueId: "5a4d0b0e-0000-4000-8000-0000000000cc" } }} event={null} active="events" signedInAs="m@example.com">
        <NotWiredState surface="Door status" />
      </Shell>,
    );
    expect(t).not.toContain(DENIED);
    expect(t).toContain("Capabilities come from your grants");
    expect(t).toContain("Venue manager");
    expect(t).toContain("not wired to the database yet");
  });
  it("a database permission refusal is a different screen from the entry denial", () => {
    const t = text(<DataSourceError failure={{ ok: false, kind: "permission", message: "denied", code: "42501", read: "venue_api.events" }} loginHref="/login" retryHref="/" />);
    expect(t).not.toContain(NO_GRANT);
  });
});

describe("the kit waits out the route loading state before reading a page", () => {
  // A client-side navigation (the redirect after sign-in) commits the URL while loading.tsx is
  // showing; a kit that reads innerText then sees "Loading this screen" and false-FAILs.
  it("loading.tsx carries the attribute the kit's ROUTE_LOADING selector waits on", () => {
    const selector = marker("ROUTE_LOADING");
    const attr = selector.match(/^\[([a-z-]+)\]$/)?.[1];
    expect(attr).toBeTruthy();
    expect(renderToStaticMarkup(<VenueLoading />)).toMatch(new RegExp(`<[^>]+ ${attr}=`));
  });
  it("the kit's P1 grant-less check does not trip on the denial's own 'a venue manager … can give you access' line", () => {
    const t = text(<EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />);
    expect(t).toMatch(/a venue manager or an organization owner/i);
    expect(kit).toMatch(/!roleLabelClaimed\(to\)/);
    expect(roleLabelClaimed(t)).toBe(false);
    expect(roleLabelClaimed("Capabilities come from your grants: Venue manager")).toBe(true);
    expect(roleLabelClaimed("Signed in as x · Venue manager")).toBe(true);
  });
});

describe("the kit's database-mode events checks match the v2 list", () => {
  const VA = "5a4d0b0e-0000-4000-8000-0000000000aa";
  const db = { role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false, verifiedRole: true, scope: { orgId: "5a4d0b0e-0000-4000-8000-00000000000a", venueId: VA } } as const;
  it("a remaining-only batch of 174 reads as the kit's REMAINING_A", () => {
    const ev: Event = { eventId: "e1", orgId: db.scope.orgId, venueId: VA, title: "Night A", status: "on_sale", resaleMode: "off", promoterCount: null, sessions: [{ sessionId: "f1", eventId: "e1", label: null, startsAt: "2030-01-01T03:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }] };
    const types: TicketType[] = [{ ticketTypeId: "t1", eventId: "e1", name: "GA", kind: "admission", priceMinor: 2500, visibility: "public" }];
    const batches = mapBatches([{ batch_id: "b1", ticket_type_id: "t1", event_session_id: "f1", release_kind: "public_sale", remaining: 174 }]);
    const t = text(<EventsTable events={[ev]} batches={batches} types={types} holds={[]} ctx={{ ...db }} basePath={`/o/x/v/${VA}`} timeZone="America/New_York" now={new Date("2029-12-01T00:00:00Z")} filter={{}} />);
    expect(t).toContain(marker("REMAINING_A"));
  });
  it("Sign out is offered as the form the kit's SIGN_OUT selector targets", () => {
    const out = renderToStaticMarkup(
      <Shell ctx={{ ...db }} event={null} active="events" signedInAs="m@example.com">
        <p>x</p>
      </Shell>,
    );
    expect(marker("SIGN_OUT")).toBe('form[action="/logout"] button');
    expect(out).toMatch(/<form[^>]*action="\/logout"[^>]*>\s*<button/);
  });
});
