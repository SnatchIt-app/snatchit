import { beforeEach, describe, expect, it, vi } from "vitest";
import { startPrivatePilotCheckout } from "@/lib/private-pilot-actions";

const mocks = vi.hoisted(() => ({
  auth: vi.fn(),
  rpc: vi.fn(),
  anonymousRpc: vi.fn(),
  checkout: vi.fn(),
}));
vi.mock("server-only", () => ({}));
vi.mock("@supabase/supabase-js", () => ({ createClient: () => ({ rpc: mocks.anonymousRpc }) }));
vi.mock("@/lib/auth/session", () => ({ getAuthedUser: mocks.auth }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({ rpc: mocks.rpc }),
}));
vi.mock("@/lib/edge-functions", () => ({ callEdgeFunction: mocks.checkout }));
vi.mock("@/lib/env", () => ({
  SUPABASE_URL: "https://test.invalid",
  SUPABASE_ANON_KEY: "test",
  STRIPE_PUBLISHABLE_KEY: "pk_test_fixture",
}));

const session = "27800000-0000-0000-0000-000000000006";
const tier = "27800000-0000-0000-0000-000000000008";
const hold = "27800000-0000-0000-0000-000000000009";
const attempt = "27800000-0000-0000-0000-000000000010";
const detail = {
  session: { session_id: session },
  event: { title: "Private pilot" },
  venue: { name: "Test venue" },
  ticket_types: [{
    ticket_type_id: tier, name: "Admission", currency: "USD", on_sale_now: true,
    price_minor: 100, buyer_fee_minor: 10, all_in_price_minor: 110,
  }],
};

beforeEach(() => {
  vi.resetAllMocks();
  vi.stubEnv("PRIVATE_PRIMARY_SESSION_ID", session);
  mocks.auth.mockResolvedValue({ id: "buyer" });
  mocks.anonymousRpc.mockReturnValue({ maybeSingle: async () => ({ data: null, error: null }) });
  mocks.rpc.mockImplementation((name: string) => name === "get_primary_session"
    ? { maybeSingle: async () => ({ data: detail, error: null }) }
    : Promise.resolve({ data: { hold_id: hold, quantity: 1, expires_at: "2999-01-01T00:00:00Z" }, error: null }));
  mocks.checkout.mockResolvedValue({ clientSecret: "pi_fixture_secret_test", total: 110, currency: "USD" });
});

describe("private pilot checkout", () => {
  it("rejects a different session and a signed-out request before querying inventory", async () => {
    await expect(startPrivatePilotCheckout(hold, attempt, 110)).resolves.toHaveProperty("error");
    mocks.auth.mockResolvedValue(null);
    await expect(startPrivatePilotCheckout(session, attempt, 110)).resolves.toHaveProperty("error");
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.checkout).not.toHaveBeenCalled();
  });

  it("rejects a publicly readable session before making a reservation", async () => {
    mocks.anonymousRpc.mockReturnValue({ maybeSingle: async () => ({ data: detail, error: null }) });
    await expect(startPrivatePilotCheckout(session, attempt, 110)).resolves.toHaveProperty("error");
    expect(mocks.rpc.mock.calls.map(([name]) => name)).toEqual(["get_primary_session"]);
    expect(mocks.checkout).not.toHaveBeenCalled();
  });

  it("refuses a changed price or inaccessible private session before making a reservation", async () => {
    await expect(startPrivatePilotCheckout(session, attempt, 100)).resolves.toHaveProperty("error");
    mocks.rpc.mockReturnValue({ maybeSingle: async () => ({ data: null, error: null }) });
    await expect(startPrivatePilotCheckout(session, attempt, 110)).resolves.toHaveProperty("error");
    expect(mocks.rpc.mock.calls.map(([name]) => name)).toEqual(["get_primary_session", "get_primary_session"]);
    expect(mocks.checkout).not.toHaveBeenCalled();
  });

  it("passes the exact one-ticket hold and total through the primary checkout on a retry", async () => {
    for (let i = 0; i < 2; i++) {
      await expect(startPrivatePilotCheckout(session, attempt, 110)).resolves.toEqual({
        clientSecret: "pi_fixture_secret_test",
      });
    }
    expect(mocks.rpc.mock.calls.filter(([name]) => name === "reserve_primary_tier")).toEqual(
      Array(2).fill(["reserve_primary_tier", {
        p_session_id: session, p_ticket_type_id: tier, p_quantity: 1,
        p_command_key: `private-pilot:${session}:${attempt}:hold`,
      }]),
    );
    expect(mocks.checkout.mock.calls).toEqual(Array(2).fill(["primary-checkout", {
      session_id: session,
      items: [{ ticket_type_id: tier, quantity: 1 }],
      hold_ids: [hold],
      command_key: `private-pilot:${session}:${attempt}:order`,
      expected_total_cents: 110,
    }]));
  });

  it("withholds the payment form when the checkout response disagrees with the reviewed total", async () => {
    mocks.checkout.mockResolvedValue({ clientSecret: "pi_fixture_secret_test", total: 111, currency: "USD" });
    const result = await startPrivatePilotCheckout(session, attempt, 110);
    expect(result).toHaveProperty("error");
    expect(result).not.toHaveProperty("clientSecret");
  });
});
