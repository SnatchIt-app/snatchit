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
import { authCookie, roleLabelClaimed, sessionCookieHolds, waitSettled } from "../scripts/acceptance/lib/checks.mjs";

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
  // lib/cdp.mjs waitFor resolves false on timeout. If settled() ignored that, a page stuck on the skeleton
  // would be read as rendered, and a negative-only check (`!t.includes(TITLE.e1)`) would pass vacuously.
  it("settled() fails when the loading state never clears, instead of reading the skeleton", async () => {
    const selector = marker("ROUTE_LOADING");
    expect(kit).toMatch(/^const settled = \(page\) => waitSettled\(page, ROUTE_LOADING, \d+\);$/m);
    const stuck = { waitFor: async () => false, url: async () => "http://localhost:3300/o/a/v/b/events" };
    await expect(waitSettled(stuck, selector, 20)).rejects.toThrow(/still showing after 20 ms at http:\/\/localhost:3300\/o\/a\/v\/b\/events/);
    let waitedOn = "";
    const rendered = {
      waitFor: async (js: string) => {
        waitedOn = js;
        return true;
      },
      url: async () => "",
    };
    await expect(waitSettled(rendered, selector, 20)).resolves.toBe(true);
    expect(waitedOn).toBe(`!document.querySelector(${JSON.stringify(selector)})`);
  });
  it("the kit's P1 grant-less check does not trip on the denial's own 'a venue manager … can give you access' line", () => {
    const t = text(<EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />);
    expect(t).toMatch(/a venue manager or an organization owner/i);
    expect(kit).toMatch(/!roleLabelClaimed\(to\)/);
    expect(roleLabelClaimed(t)).toBe(false);
    expect(roleLabelClaimed("Capabilities come from your grants: Venue manager")).toBe(true);
    expect(roleLabelClaimed("Signed in as x · Venue manager")).toBe(true);
  });
  // The kit reads innerText, which applies CSS text-transform (.eyebrow-caps, .col-head, table heads are
  // uppercase), so a leaked label can arrive as "VENUE MANAGER". Only the denial's own sentence is exempt.
  it("P1 matches a role label in any case, and exempts only the denial's own sentence", () => {
    expect(roleLabelClaimed("VENUE MANAGER")).toBe(true);
    expect(roleLabelClaimed("org owner")).toBe(true);
    expect(roleLabelClaimed("CAPABILITIES COME FROM YOUR GRANTS: VENUE FINANCE")).toBe(true);
    const denial = text(<EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />);
    expect(roleLabelClaimed(denial.toUpperCase())).toBe(false);
    expect(roleLabelClaimed(`${denial} Signed in as x · VENUE MANAGER`)).toBe(true);
    expect(roleLabelClaimed(`${denial.toUpperCase()} Org owner`)).toBe(true);
    // P1 signed out, P1 grant-less, and C6 at /o/A/v/B.
    expect(kit.match(/!roleLabelClaimed\(t\)|!roleLabelClaimed\(to\)/g)).toHaveLength(3);
  });
  // C6 ("Org A owner at /o/A/v/B: … no role claimed") used to test only /Capabilities come from your grants/,
  // case-sensitively: an "Org owner" label, or an uppercase-styled strip, on that denied page passed.
  it("C6 at /o/A/v/B uses the same any-case matcher as P1", () => {
    const c6 = kit.split("\n").find((l) => l.includes('"C6 Org A owner at /o/A/v/B: denied, no Venue B rows, no role claimed"'));
    expect(c6).toBeTruthy();
    expect(c6).toContain("!roleLabelClaimed(t)");
    expect(c6).not.toMatch(/Capabilities come from your grants\/\.test/);
  });
  it("P1 catches a planted verifiedRole leak on a grant-less database-mode page", () => {
    const page = (verifiedRole: boolean) =>
      text(
        <Shell ctx={{ role: "venue_manager", state: "live", source: "database", countersAvailable: false, writesEnabled: false, verifiedRole, scope: { orgId: "5a4d0b0e-0000-4000-8000-00000000000a", venueId: "5a4d0b0e-0000-4000-8000-0000000000aa" } }} event={null} active="events" signedInAs="outsider@example.com">
          <EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />
        </Shell>,
      );
    expect(roleLabelClaimed(page(false))).toBe(false);
    expect(roleLabelClaimed(page(true))).toBe(true);
    expect(roleLabelClaimed(page(true).toUpperCase())).toBe(true);
  });
  it("C6: the Org A owner's denied page at /o/A/v/B claims no role, and a planted leak there is caught", () => {
    // readPage: the route venue (B) is not in the route org (A), so entry is denied with verifiedRole false.
    const page = (verifiedRole: boolean) =>
      text(
        <Shell ctx={{ role: "org_owner", state: "live", source: "database", countersAvailable: false, writesEnabled: false, verifiedRole, scope: { orgId: "5a4d0b0e-0000-4000-8000-00000000000a", venueId: "5a4d0b0e-0000-4000-8000-0000000000bb" } }} event={null} active="events" signedInAs="owner@example.com">
          <EntryGate entry={{ kind: "denied" }} loginHref="/login" retryHref="/" />
        </Shell>,
      );
    expect(page(false)).toContain(DENIED);
    expect(roleLabelClaimed(page(false))).toBe(false);
    expect(roleLabelClaimed(page(true))).toBe(true);
    expect(roleLabelClaimed(page(true).toUpperCase())).toBe(true);
    expect(/Capabilities come from your grants/.test(page(true).toUpperCase())).toBe(false); // what the old C6 test missed
  });
});

// H2/H3 rewrite the session cookie through CDP (writeAuthCookie). Chrome can refuse the write, e.g. a Secure cookie
// for a plain-http host other than localhost; H2 would then see no cookie at all and pass on "Sign in to continue"
// without ever presenting the tampered token. The kit reads the cookie back and records whether it holds the write.
describe("the kit proves the browser holds the session it wrote before H2/H3 rely on it", () => {
  const enc = (o: unknown) => `base64-${Buffer.from(JSON.stringify(o)).toString("base64url")}`;
  const good = { access_token: "a.b.good", refresh_token: "r1", expires_at: 2000000000, user: { id: "u1" } };
  const bad = { ...good, access_token: "a.b.bAAA", expires_at: 2000000100 };
  const jar = (name: string, value: string) => [{ name, value, httpOnly: true, secure: true, sameSite: "Lax", expires: -1 }];
  it("authCookie parses one cookie, joins chunks in order, and ignores the PKCE verifier", () => {
    expect(authCookie([])).toBeNull();
    expect(authCookie(jar("sb-x-auth-token", enc(good)))?.session).toEqual(good);
    const v = enc(good);
    const chunked = [
      { name: "sb-x-auth-token.1", value: v.slice(20) },
      { name: "sb-x-auth-token-code-verifier", value: "pkce" },
      { name: "sb-x-auth-token.0", value: v.slice(0, 20) },
    ];
    const ck = authCookie(chunked);
    expect(ck?.base).toBe("sb-x-auth-token");
    expect(ck?.parts.map((c: { name: string }) => c.name)).toEqual(["sb-x-auth-token.0", "sb-x-auth-token.1"]);
    expect(ck?.session).toEqual(good);
  });
  it("sessionCookieHolds is true only when the cookie read back is exactly the session written", () => {
    expect(sessionCookieHolds(null, bad)).toBe(false); // write refused, cookie gone
    expect(sessionCookieHolds(authCookie(jar("sb-x-auth-token", enc(good))), bad)).toBe(false); // old cookie kept
    expect(sessionCookieHolds(authCookie(jar("sb-x-auth-token", enc({ ...good, expires_at: 1 }))), { ...good, expires_at: 2 })).toBe(false);
    expect(sessionCookieHolds(authCookie(jar("sb-x-auth-token", enc(bad))), bad)).toBe(true);
  });
  it("writeAuthCookie returns the read-back result, and H2 and H3 check it before their visit and gate on it", () => {
    expect(kit).toMatch(/^ {2}return sessionCookieHolds\(authCookie\(await page\.cookies\(opts\.app\)\), session\);\n\}$/m);
    expect(kit).not.toMatch(/^function authCookie\(/m); // one parser, the tested one
    const h2 = kit.slice(kit.indexOf("// H2 tampered access token is rejected."), kit.indexOf("// H3 refresh:"));
    expect(h2).toMatch(/const heldBad = await writeAuthCookie\(m, ck, bad\);\s*check\(P, "H2 [^"]+\(read back\)", heldBad,[^\n]*\n\s*t = await visit\(m, `\$\{A\}\/events`\);\s*check\(P, "H2 tampered token -> Sign in to continue, no data", heldBad && /);
    const h3 = kit.slice(kit.indexOf("// H3 refresh:"), kit.indexOf("// H6 logout."));
    expect(h3).toMatch(/const heldExpired = await writeAuthCookie\(m2, ck, [^;]+\);\s*check\(P, "H3 [^"]+\(read back\)", heldExpired,[^\n]*\n\s*t = await visit\(m2, `\$\{A\}\/events`\);\s*check\(P, "H3 expired session still renders data \(refreshed\)", heldExpired && /);
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
