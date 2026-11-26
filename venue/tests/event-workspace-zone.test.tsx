import { renderToStaticMarkup } from "react-dom/server";
import { expect, it, vi } from "vitest";

const fixture = vi.hoisted(() => {
  const org = "11111111-1111-4111-8111-111111111111";
  const venue = "22222222-2222-4222-8222-222222222222";
  const event = "33333333-3333-4333-8333-333333333333";
  return { org, venue, event, record: {
    eventId: event, orgId: org, venueId: venue, title: "Island night", status: "draft", resaleMode: "off", promoterCount: null, timeZone: "Pacific/Honolulu",
    sessions: [{ sessionId: "44444444-4444-4444-8444-444444444444", eventId: event, label: "Saturday", startsAt: "2026-12-06T06:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }],
  }};
});
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }) }));
vi.mock("@/lib/env", async (original) => ({ ...await original<object>(), DATA_SOURCE: "database" }));
vi.mock("@/lib/page", async (original) => ({ ...await original<object>(), readPage: async () => ({
  params: { org: fixture.org, venue: fixture.venue, event: fixture.event }, sp: {},
  ctx: { source: "database", role: "org_owner", state: "live", countersAvailable: false, writesEnabled: true, verifiedRole: true, scope: { orgId: fixture.org, venueId: fixture.venue } },
  scope: { ok: true, orgId: fixture.org, venueId: fixture.venue, basePath: `/o/${fixture.org}/v/${fixture.venue}` },
  entry: { kind: "ok" }, event: fixture.record, eventFailure: null, signedInAs: "manager@example.test", timeZone: "Pacific/Honolulu",
}) }));
vi.mock("@/lib/db/adapters", async (original) => ({ ...await original<object>(), dbListTicketTypes: async () => ({ ok: true, data: [] }), dbListBatches: async () => ({ ok: true, data: [] }) }));
vi.mock("@/lib/db/command-gate", () => ({ commandsGateOpen: () => true }));
vi.mock("@/lib/db/session-capacity", () => ({ dbSessionCapacities: async () => ({ ok: true, data: {} }) }));
vi.mock("@/lib/db/event-commands", async (original) => ({ ...await original<object>(), mintCommandKey: async () => "synthetic-command" }));

import EventPage from "@/app/o/[org]/v/[venue]/events/[event]/page";

it("the real event workspace pre-fills edit times in the event's own projected zone", async () => {
  const out = renderToStaticMarkup(await EventPage({ params: Promise.resolve({ org: fixture.org, venue: fixture.venue, event: fixture.event }), searchParams: Promise.resolve({}) }));
  const input = out.match(/<input[^>]*name="starts_local"[^>]*>/)?.[0] ?? "";
  expect(input).toContain('value="2026-12-05T20:00"');
  expect(input).not.toContain('value="2026-12-06T01:00"');
  expect(out).toContain('name="timeZone" value="Pacific/Honolulu"');
});
