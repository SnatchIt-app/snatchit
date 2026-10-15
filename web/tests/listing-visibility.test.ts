import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Listing cleanup (owner, 2026-10-15): only approved listings are public. RLS on listings hides the
// rest from non-participants, so the public catalog (home, browse, related, /api/public/events,
// sitemap) must read as an anonymous visitor would: a cookie-client read gave a signed-in seller or
// bidder their hidden rows, and the feed's `Cache-Control: public` body would then be served to
// everyone. Seller mutations must not read a failed or filtered result as "0 bids" / "done".

const h = vi.hoisted(() => ({
  cookiesCalled: 0,
  serverCalled: 0,
  resolve: ((): unknown => ({ data: null, error: null })) as (target: string) => unknown,
  removed: [] as string[][],
  ops: [] as string[],
}));

vi.mock("server-only", () => ({}));
vi.mock("@/lib/env", () => ({
  SUPABASE_URL: "https://proj.supabase.test",
  SUPABASE_ANON_KEY: "anon-test-key",
  SITE_URL: "https://app.example.test",
  hasSupabaseEnv: true,
}));
vi.mock("next/headers", () => ({
  cookies: async () => {
    h.cookiesCalled++;
    return { getAll: () => [{ name: "sb-proj-auth-token", value: "signed-in-user" }], set: () => {} };
  },
}));
vi.mock("@/lib/observability", () => ({ captureException: () => {} }));
// The cookie client: a recording fake for the seller paths, counted so the catalog can prove it
// never touches it.
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => {
    h.serverCalled++;
    return {
      from(table: string) {
        const ops: string[] = [];
        const builder: unknown = new Proxy(
          {},
          {
            get(_t, prop) {
              if (prop === "then") {
                const target = `${table}.${ops.join(".")}`;
                h.ops.push(target);
                return (ok: (v: unknown) => unknown, fail: (e: unknown) => unknown) =>
                  Promise.resolve(h.resolve(target)).then(ok, fail);
              }
              return () => {
                ops.push(String(prop));
                return builder;
              };
            },
          },
        );
        return builder;
      },
      storage: { from: () => ({ remove: async (paths: string[]) => (h.removed.push(paths), { error: null }) }) },
    };
  },
}));

type Call = { url: URL; headers: Headers };
let calls: Call[] = [];

beforeEach(() => {
  h.cookiesCalled = 0;
  h.serverCalled = 0;
  h.removed = [];
  h.ops = [];
  calls = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      calls.push({ url, headers: new Headers(init?.headers) });
      return new Response("[]", { status: 200, headers: { "Content-Type": "application/json" } });
    }),
  );
});
afterEach(() => vi.unstubAllGlobals());

const listingReads = () => calls.filter((c) => c.url.pathname === "/rest/v1/listings");

describe("the public catalog reads as an anonymous visitor", () => {
  it("getActiveListings: cookieless anon request, hidden rows excluded explicitly", async () => {
    const { getActiveListings } = await import("@/lib/listings");
    await getActiveListings({ category: "clubs" }, 24);
    expect(h.serverCalled).toBe(0);
    expect(h.cookiesCalled).toBe(0);
    const [c] = listingReads();
    expect(c).toBeDefined();
    // The anon key is the only credential: no user JWT reaches PostgREST.
    expect(c.headers.get("authorization")).toBe("Bearer anon-test-key");
    expect(c.url.searchParams.get("public_hidden_at")).toBe("is.null");
    expect(c.url.searchParams.get("status")).toBe("eq.active");
    expect(c.url.searchParams.get("auction_status")).toBe("eq.active");
    expect(c.url.searchParams.get("category")).toBe("eq.clubs");
  });

  it("/api/public/events never reads the viewer's session (its body is CDN-cached as public)", async () => {
    const { GET } = await import("@/app/api/public/events/route");
    const res = await GET(new Request("https://app.example.test/api/public/events", { headers: { cookie: "sb-proj-auth-token=x" } }));
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toContain("public");
    expect(h.serverCalled).toBe(0);
    expect(h.cookiesCalled).toBe(0);
    expect(listingReads()[0].headers.get("authorization")).toBe("Bearer anon-test-key");
    expect(listingReads()[0].url.searchParams.get("public_hidden_at")).toBe("is.null");
  });

  it("sitemap: rendered per request (not frozen at build) from the anonymous catalog", async () => {
    const mod = await import("@/app/sitemap");
    expect(mod.dynamic).toBe("force-dynamic");
    await mod.default();
    expect(h.serverCalled).toBe(0);
    expect(listingReads()[0].headers.get("authorization")).toBe("Bearer anon-test-key");
  });

  it("related listings come from the same anonymous catalog", async () => {
    const { getRelatedListings } = await import("@/lib/listings");
    await getRelatedListings({ id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1", category: "clubs" } as never, 4);
    expect(h.serverCalled).toBe(0);
    expect(listingReads().length).toBeGreaterThan(0);
    for (const c of listingReads()) expect(c.url.searchParams.get("public_hidden_at")).toBe("is.null");
  });
});

// --- seller mutations -------------------------------------------------------------------------

const SELLER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2";
const LISTING = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const FUTURE = new Date(Date.now() + 6 * 3_600_000).toISOString();
const ROW = {
  id: LISTING,
  seller_id: SELLER,
  status: "active",
  auction_status: "active",
  ends_at: FUTURE,
  cover_image_path: `${SELLER}/covers/1.png`,
  bid_count: 0,
};

/** Scripted results for the cookie client, keyed by the PostgREST chain. */
function script(over: Record<string, unknown>) {
  const base: Record<string, unknown> = {
    "listings.select.eq.order": { data: [ROW], error: null },
    "transfers.select.eq": { data: [], error: null },
    "bids.select.in": { data: [], error: null },
    "bids.select.eq": { count: 0, error: null },
    "listings.update.eq.eq.select": { data: [{ id: LISTING }], error: null },
    "listings.delete.eq.eq.select": { data: [{ id: LISTING }], error: null },
  };
  const table = { ...base, ...over };
  h.resolve = (target: string) => {
    if (!(target in table)) throw new Error(`unscripted query ${target}`);
    return table[target];
  };
}

const FIELDS = { eventName: "Night", venue: "Club", restrictions: null, ticketPlatform: "dice" };

describe("seller mutations fail closed", () => {
  it("an unreadable bid count blocks edit — never treated as zero bids", async () => {
    script({ "bids.select.eq": { count: null, error: { message: "permission denied for table bids" } } });
    const { updateSellerListing } = await import("@/lib/seller-listings");
    const out = await updateSellerListing(SELLER, LISTING, FIELDS);
    expect(out).toEqual({ error: expect.stringMatching(/couldn't check this listing's bids/) });
    expect(h.ops).not.toContain("listings.update.eq.eq.select");
  });

  it("an unreadable bid count blocks delete — the cascade would wipe the bids", async () => {
    script({ "bids.select.eq": { count: null, error: { message: "permission denied for table bids" } } });
    const { deleteSellerListing } = await import("@/lib/seller-listings");
    const out = await deleteSellerListing(SELLER, LISTING);
    expect(out).toEqual({ error: expect.stringMatching(/couldn't check this listing's bids/) });
    expect(h.ops).not.toContain("listings.delete.eq.eq.select");
    expect(h.removed).toEqual([]);
  });

  it("Your listings errors instead of showing 0 bids when the bid list can't be read", async () => {
    script({ "bids.select.in": { data: null, error: { message: "permission denied for table bids" } } });
    const { getMyListings } = await import("@/lib/seller-listings");
    await expect(getMyListings(SELLER)).rejects.toThrow(/seller bids query failed/);
  });

  it("an update RLS filtered to zero rows is reported, not 'saved'", async () => {
    script({ "listings.update.eq.eq.select": { data: [], error: null } });
    const { updateSellerListing } = await import("@/lib/seller-listings");
    expect(await updateSellerListing(SELLER, LISTING, FIELDS)).toEqual({ error: "This listing no longer exists." });
  });

  it("a delete that removed nothing keeps the cover image", async () => {
    script({ "listings.delete.eq.eq.select": { data: [], error: null } });
    const { deleteSellerListing } = await import("@/lib/seller-listings");
    expect(await deleteSellerListing(SELLER, LISTING)).toEqual({ error: "This listing no longer exists." });
    expect(h.removed).toEqual([]);
  });

  it("control: a real delete still succeeds and removes the cover", async () => {
    script({});
    const { deleteSellerListing } = await import("@/lib/seller-listings");
    expect(await deleteSellerListing(SELLER, LISTING)).toEqual({ ok: true });
    expect(h.removed).toEqual([[ROW.cover_image_path]]);
  });

  it("control: a real edit still succeeds", async () => {
    script({});
    const { updateSellerListing } = await import("@/lib/seller-listings");
    expect(await updateSellerListing(SELLER, LISTING, FIELDS)).toEqual({ ok: true });
  });
});
