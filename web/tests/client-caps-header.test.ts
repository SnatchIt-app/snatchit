import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// 156's old-build safeguard: the database refuses a bid or Buy Now reservation on a waived listing
// unless the request declares `x-snatchit-caps: proof-disclosure-v1` — a client that can't show the
// waiver can't buy it. This web build shows it (ProofWaiverNotice), so every server-side request
// carries the token. Real @supabase/ssr client, network mocked.

vi.mock("server-only", () => ({}));
vi.mock("@/lib/env", () => ({ SUPABASE_URL: "https://proj.supabase.test", SUPABASE_ANON_KEY: "anon-test-key" }));
vi.mock("next/headers", () => ({ cookies: async () => ({ getAll: () => [], set: () => {} }) }));

type Call = { url: URL; method: string; headers: Headers };
let calls: Call[] = [];

beforeEach(() => {
  calls = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      calls.push({ url, method: (init?.method ?? "GET").toUpperCase(), headers: new Headers(init?.headers) });
      return new Response("null", { status: 201, headers: { "Content-Type": "application/json" } });
    }),
  );
});
afterEach(() => vi.unstubAllGlobals());

const LISTING = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const USER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2";

describe("web declares proof-disclosure-v1 on purchase requests", () => {
  it("placing a bid", async () => {
    const { placeBid } = await import("@/lib/bids");
    await placeBid(LISTING, USER, 40);
    const c = calls.find((x) => x.url.pathname === "/rest/v1/bids" && x.method === "POST");
    expect(c).toBeDefined();
    expect(c!.headers.get("x-snatchit-caps")).toBe("proof-disclosure-v1");
  });

  it("reserving Buy Now", async () => {
    const { reserveBuyNow } = await import("@/lib/checkout");
    await reserveBuyNow(LISTING, USER);
    const c = calls.find((x) => x.url.pathname === "/rest/v1/rpc/reserve_buy_now");
    expect(c).toBeDefined();
    expect(c!.headers.get("x-snatchit-caps")).toBe("proof-disclosure-v1");
  });

  it("negative control: a client without the declaration sends no such header (the test can tell)", async () => {
    const { createClient } = await import("@supabase/supabase-js");
    const bare = createClient("https://proj.supabase.test", "anon-test-key", { auth: { persistSession: false } });
    await bare.from("bids").insert({ listing_id: LISTING, bidder_id: USER, amount: 40 });
    const c = calls.find((x) => x.url.pathname === "/rest/v1/bids" && x.method === "POST");
    expect(c).toBeDefined();
    expect(c!.headers.get("x-snatchit-caps")).toBeNull();
  });
});
