import { beforeEach, describe, expect, it, vi } from "vitest";

const mock = vi.hoisted(() => ({ result: vi.fn(), eq: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: async () => ({
  from: () => ({ select: () => ({ eq: mock.eq }) }),
}) }));
import { getMySales } from "@/lib/sales";

describe("seller amount preserves missing fee information", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mock.eq.mockImplementation(() => ({ order: mock.result }));
  });

  it.each([
    { amount: 200, seller_fee: null, expected: null },
    { amount: 200, seller_fee: undefined, expected: null },
    { amount: null, seller_fee: 20, expected: null },
    { amount: 200, seller_fee: 0, expected: 200 },
    { amount: 200, seller_fee: 20, expected: 180 },
  ])("amount=$amount fee=$seller_fee gives $expected", async ({ amount, seller_fee, expected }) => {
    mock.result.mockResolvedValue({ data: [{ id: "sale", payment: { amount, seller_fee } }], error: null });
    const rows = await getMySales("seller");
    expect(mock.eq).toHaveBeenCalledWith("seller_id", "seller");
    expect(rows[0].netCents).toBe(expected);
  });

  it("read errors remain errors, never an empty sales history", async () => {
    mock.result.mockResolvedValue({ data: null, error: { message: "unavailable" } });
    await expect(getMySales("seller")).rejects.toThrow("transfers query failed");
  });
});
