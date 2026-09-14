import { renderToStaticMarkup } from "react-dom/server";
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { PreviewContext } from "@/lib/preview";
import { eventInScope } from "@/lib/page";
import { Shell } from "@/components/shell/Shell";
import type { Event } from "@/lib/types";

const ORG_A = "5a4d0b0e-0000-4000-8000-00000000000a";
const VEN_A = "5a4d0b0e-0000-4000-8000-0000000000aa";
const VEN_B = "5a4d0b0e-0000-4000-8000-0000000000bb";

// ---------------------------------------------------------------------------
// F1 — a session refreshed on the server must be written back to the browser.
// Hosted Supabase rotates refresh tokens and revokes a reused one after the
// reuse interval, so a refresh that only lives inside one render signs the
// staff member out on a later request.
// ---------------------------------------------------------------------------
const ssr = vi.hoisted(() => ({
  setAllArgs: null as null | {
    cookies: { name: string; value: string; options: object }[];
    headers: Record<string, string>;
  },
  getClaims: vi.fn(),
}));
vi.mock("@supabase/ssr", () => ({
  createServerClient: (
    _url: string,
    _key: string,
    opts: { cookies: { setAll: (c: unknown, h: unknown) => void } },
  ) => ({
    auth: {
      getClaims: async () => {
        ssr.getClaims();
        if (ssr.setAllArgs)
          opts.cookies.setAll(ssr.setAllArgs.cookies, ssr.setAllArgs.headers);
        return { data: { claims: { sub: "u1" } }, error: null };
      },
    },
  }),
}));

describe("F1 session refresh is persisted by the proxy", () => {
  beforeEach(() => {
    ssr.setAllArgs = null;
    ssr.getClaims.mockReset();
    vi.resetModules();
  });

  async function loadProxy(source: "database" | "fixtures") {
    vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", source);
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://localhost:3202");
    vi.stubEnv(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.x",
    );
    return import("@/lib/supabase/proxy");
  }

  it("writes refreshed auth cookies and the no-store headers onto the response", async () => {
    const { refreshSession } = await loadProxy("database");
    ssr.setAllArgs = {
      cookies: [
        {
          name: "sb-localhost-auth-token",
          value: "base64-NEW",
          options: { path: "/", sameSite: "lax" },
        },
      ],
      headers: {
        "Cache-Control":
          "private, no-cache, no-store, must-revalidate, max-age=0",
      },
    };
    const res = await refreshSession(
      new NextRequest("http://localhost:3300/o/x/v/y/events", {
        headers: { cookie: "sb-localhost-auth-token=base64-OLD" },
      }),
    );
    expect(ssr.getClaims).toHaveBeenCalledTimes(1);
    expect(res.cookies.get("sb-localhost-auth-token")?.value).toBe(
      "base64-NEW",
    );
    expect(res.headers.get("cache-control")).toContain("no-store");
  });

  it("does nothing in fixture mode (no Supabase client is created)", async () => {
    const { refreshSession } = await loadProxy("fixtures");
    const res = await refreshSession(
      new NextRequest(
        "http://localhost:3300/o/smp_org_wynwood/v/smp_ven_room/events",
      ),
    );
    expect(ssr.getClaims).not.toHaveBeenCalled();
    expect(res.cookies.getAll()).toEqual([]);
  });

  it("refuses a service-role key in the public slot rather than using it", async () => {
    vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", "database");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://localhost:3202");
    vi.stubEnv(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      `x.${Buffer.from(JSON.stringify({ role: "service_role" })).toString("base64url")}.y`,
    );
    const { refreshSession } = await import("@/lib/supabase/proxy");
    await refreshSession(new NextRequest("http://localhost:3300/login"));
    expect(ssr.getClaims).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// F2 — an event id in the URL is only valid under its own venue (spec §4.4
// rule 5). RLS keeps other venues' drafts hidden, but a public event from
// Venue B must not render inside Venue A's dashboard.
// ---------------------------------------------------------------------------
describe("F2 event must belong to the route's venue", () => {
  const ev = (venueId: string, orgId = ORG_A) =>
    ({ eventId: "e", venueId, orgId }) as unknown as Event;
  it("accepts an event at the route venue", () => {
    expect(eventInScope(ev(VEN_A), { venueId: VEN_A, orgId: ORG_A })).toBe(
      true,
    );
  });
  it("rejects an event from another venue (fails closed as not found)", () => {
    expect(eventInScope(ev(VEN_B), { venueId: VEN_A, orgId: ORG_A })).toBe(
      false,
    );
  });
  it("compares ids case-insensitively", () => {
    expect(
      eventInScope(ev(VEN_A.toUpperCase()), { venueId: VEN_A, orgId: ORG_A }),
    ).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// F3 — database mode never claims a role it did not verify, never shows the
// sample fixture names, and links navigation to the route's own scope.
// ---------------------------------------------------------------------------
describe("F3 database-mode presentation", () => {
  const html = (ctx: PreviewContext) =>
    renderToStaticMarkup(
      <Shell
        ctx={ctx}
        event={null}
        active="events"
        signedInAs="someone@example.com"
      >
        <p>body</p>
      </Shell>,
    );
  const base: PreviewContext = {
    role: "venue_manager",
    state: "live",
    source: "database",
    countersAvailable: false,
    writesEnabled: false,
  };

  it("a caller without a verified grant gets no role label and no navigation", () => {
    const out = html({
      ...base,
      verifiedRole: false,
      scope: { orgId: ORG_A, venueId: VEN_A },
    });
    expect(out).not.toContain("Venue manager");
    expect(out).not.toContain("Capabilities come from your grants");
    expect(out).toContain("No verified role at this venue");
    expect(out).not.toContain('href="/o/');
    expect(out).not.toContain("Menu ·");
  });

  it("never renders the sample fixture organization or venue names", () => {
    const out = html({
      ...base,
      verifiedRole: true,
      scope: { orgId: ORG_A, venueId: VEN_A },
    });
    expect(out).not.toContain("(sample)");
    expect(out).not.toContain("smp_");
  });

  it("links navigation to the route's own org and venue", () => {
    const out = html({
      ...base,
      verifiedRole: true,
      scope: { orgId: ORG_A, venueId: VEN_A },
    });
    expect(out).toContain(`href="/o/${ORG_A}/v/${VEN_A}/events"`);
    expect(out).toContain("Capabilities come from your grants");
    expect(out).toContain("Venue manager");
  });

  it("the database banner never mentions a role switch that does not exist", async () => {
    vi.resetModules();
    vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", "database");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://localhost:3202");
    const { sourceInfo } = await import("@/lib/source");
    expect(sourceInfo().label).not.toMatch(/role switch/i);
    vi.unstubAllEnvs();
  });

  it("fixture mode is unchanged: sample names and the role switch stay", () => {
    const out = html({
      role: "venue_manager",
      state: "live",
      source: "fixtures",
      countersAvailable: true,
      writesEnabled: true,
    });
    expect(out).toContain("(sample)");
    expect(out).toContain('name="role"');
  });
});
