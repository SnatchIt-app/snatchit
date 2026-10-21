/**
 * Guards for the production-readiness branch (venue/production-readiness, 2026-10-21): what a
 * database-mode host at venue.snatchitapp.com needs that the fixture demo never exercised.
 * Each block names the fix it guards; each was run against the unfixed code first and failed.
 */
import { existsSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);

// Database-mode page harness: the session probe and the venue_api adapters are replaced, so a
// page or readPage() can run as a signed-in caller without a Supabase client or a network.
const db = vi.hoisted(() => {
  const ORG = "5a4d0b0e-0000-4000-8000-00000000000a";
  const VEN = "5a4d0b0e-0000-4000-8000-0000000000aa";
  const fresh = () => ({
    session: { ok: true, user: { id: "u1", email: "m@example.test", aal: "aal1" } } as unknown,
    grants: { ok: true, data: { venueRoles: ["venue_manager"], orgRoles: [] } } as unknown,
    venue: { ok: true, data: { venue_id: VEN, org_id: ORG, name: "Room One" } } as unknown,
    events: { ok: true, data: [] } as unknown,
  });
  return { ORG, VEN, fresh, state: fresh() };
});
vi.mock("@/lib/auth/session", () => ({ probeSession: async () => db.state.session }));
vi.mock("@/lib/db/adapters", () => ({
  dbMyGrants: async () => db.state.grants,
  dbVenueScope: async () => db.state.venue,
  dbListEvents: async () => db.state.events,
  dbListTicketTypes: async () => ({ ok: true, data: [] }),
  dbListBatches: async () => ({ ok: true, data: [] }),
  dbGetEvent: async () => ({ ok: true, data: null }),
}));
// next/font is a compile-time transform; the root layout only needs the class names here.
vi.mock("next/font/google", () => ({ Inter: () => ({ variable: "font-inter" }), Newsreader: () => ({ variable: "font-newsreader" }) }));

async function inMode(source: "database" | "fixtures") {
  vi.resetModules();
  db.state = db.fresh();
  vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", source);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://localhost:3202");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "placeholder-anon-key");
}
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("database mode has a route loading state (loading.tsx under o/[org]/v/[venue])", () => {
  it("the segment ships a loading.tsx", () => {
    expect(existsSync(new URL("../src/app/o/[org]/v/[venue]/loading.tsx", import.meta.url))).toBe(true);
  });
  it("renders an accessible, mode-neutral skeleton with the main landmark", async () => {
    const { default: Loading } = await import("@/app/o/[org]/v/[venue]/loading");
    const out = html(<Loading />);
    expect(out).toContain('id="main"');
    expect(out).toContain('role="status"');
    expect(out).toContain('aria-live="polite"');
    expect(out).toContain("Loading");
    expect(out).toContain('class="skel"');
    // Shown in both modes before the page knows who is looking: no data, no mode, no role.
    expect(out).not.toMatch(/sample|demo|fixture|database|Venue manager|Org owner/i);
  });
});

describe("mode-aware copy: database mode never calls itself a demo", () => {
  it("root metadata in database mode has no DEMO / sample / preview wording", async () => {
    await inMode("database");
    const { metadata } = await import("@/app/layout");
    const text = JSON.stringify(metadata);
    expect(text).not.toMatch(/demo|sample|preview/i);
    expect(text).toContain("Venue dashboard");
    expect(metadata.robots).toEqual({ index: false, follow: false });
  });
  it("root metadata in fixture mode still says DEMO and sample data", async () => {
    await inMode("fixtures");
    const { metadata } = await import("@/app/layout");
    const text = JSON.stringify(metadata);
    expect(text).toContain("DEMO");
    expect(text).toMatch(/sample data/);
    expect(metadata.robots).toEqual({ index: false, follow: false });
  });
  it("the events page eyebrow shows the route venue's own name in database mode", async () => {
    await inMode("database");
    const { default: EventsPage } = await import("@/app/o/[org]/v/[venue]/events/page");
    const out = html(await EventsPage({ params: Promise.resolve({ org: db.ORG, venue: db.VEN }), searchParams: Promise.resolve({}) }));
    expect(out).toContain('<p class="eyebrow-caps">Room One</p>');
    expect(out).not.toContain("(sample)");
  });
  it("falls back to a neutral eyebrow when the venue row carries no name", async () => {
    await inMode("database");
    db.state.venue = { ok: true, data: { venue_id: db.VEN, org_id: db.ORG, name: null } };
    const { default: EventsPage } = await import("@/app/o/[org]/v/[venue]/events/page");
    const out = html(await EventsPage({ params: Promise.resolve({ org: db.ORG, venue: db.VEN }), searchParams: Promise.resolve({}) }));
    expect(out).toContain('<p class="eyebrow-caps">Venue</p>');
  });
  it("fixture mode keeps the sample venue's name", async () => {
    await inMode("fixtures");
    const { VENUE } = await import("@/fixtures/venue");
    const { default: EventsPage } = await import("@/app/o/[org]/v/[venue]/events/page");
    const out = html(await EventsPage({ params: Promise.resolve({ org: "smp_org_wynwood", venue: "smp_ven_room" }), searchParams: Promise.resolve({}) }));
    expect(out).toContain(`<p class="eyebrow-caps">${VENUE.name}</p>`);
  });
});
