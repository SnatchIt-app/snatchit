import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  create: vi.fn(),
  price: vi.fn(),
  visibility: vi.fn(),
  rank: vi.fn(),
  capacity: vi.fn(),
  revalidatePath: vi.fn(),
}));
vi.mock("@/lib/db/commands", () => ({
  createTicketTypeAction: mocks.create,
  setTicketTypePriceAction: mocks.price,
  setTicketTypeVisibilityAction: mocks.visibility,
  setTicketTypeRankAction: mocks.rank,
  setBatchCapacityAction: mocks.capacity,
  mintCommandKey: async () => "minted",
}));
vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidatePath }));

import { createTicketTypeForm, setBatchCapacityForm, setTicketTypePriceForm, setTicketTypeRankForm, setTicketTypeVisibilityForm } from "@/lib/db/command-forms";

const ORG = "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", VEN = "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75", EV = "9a000000-0000-4000-8000-000000000001", TT = "7a000000-0000-4000-8000-000000000001";
const fd = (o: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries({ orgId: ORG, venueId: VEN, eventId: EV, commandKey: "k-1", ...o })) f.append(k, v);
  return f;
};
const ok = { kind: "ok", result: { status: "ok", ticket_type_id: TT } } as const;

beforeEach(() => {
  for (const m of Object.values(mocks)) m.mockReset();
  mocks.create.mockResolvedValue(ok);
  mocks.price.mockResolvedValue(ok);
  mocks.visibility.mockResolvedValue(ok);
  mocks.rank.mockResolvedValue(ok);
  mocks.capacity.mockResolvedValue(ok);
});

describe("FormData → D's typed inputs, verbatim parameter mapping", () => {
  it("price: dollars become cents, the reason and the SAME command key travel through; ok revalidates both event pages", async () => {
    const s = await setTicketTypePriceForm({ result: null }, fd({ ticketTypeId: TT, price: "30.00", reasonCode: "early_bird_over" }));
    expect(s.result?.kind).toBe("ok");
    expect(mocks.price).toHaveBeenCalledWith({ ticketTypeId: TT, priceMinor: 3000, reasonCode: "early_bird_over", commandKey: "k-1" });
    expect(mocks.revalidatePath).toHaveBeenCalledWith(`/o/${ORG}/v/${VEN}/events/${EV}/inventory`);
    expect(mocks.revalidatePath).toHaveBeenCalledWith(`/o/${ORG}/v/${VEN}/events/${EV}`);
  });
  it("visibility, rank, capacity and create map one to one", async () => {
    await setTicketTypeVisibilityForm({ result: null }, fd({ ticketTypeId: TT, visibility: "public", reasonCode: "opening_ga" }));
    expect(mocks.visibility).toHaveBeenCalledWith({ ticketTypeId: TT, visibility: "public", reasonCode: "opening_ga", commandKey: "k-1" });
    await setTicketTypeRankForm({ result: null }, fd({ ticketTypeId: TT, displayRank: "2" }));
    expect(mocks.rank).toHaveBeenCalledWith({ ticketTypeId: TT, displayRank: 2, commandKey: "k-1" });
    await setBatchCapacityForm({ result: null }, fd({ batchId: TT, newCapacity: "120", reasonCode: "bigger_room" }));
    expect(mocks.capacity).toHaveBeenCalledWith({ batchId: TT, newCapacity: 120, reasonCode: "bigger_room", commandKey: "k-1" });
    await createTicketTypeForm({ result: null }, fd({ kind: "table", name: " Booth ", price: "500", visibility: "hidden" }));
    expect(mocks.create).toHaveBeenCalledWith({ eventId: EV, kind: "table", name: "Booth", priceMinor: 50000, visibility: "hidden", commandKey: "k-1" });
  });
  it("a bad field is refused by name before any call, and nothing is revalidated", async () => {
    const s = await setTicketTypePriceForm({ result: null }, fd({ ticketTypeId: TT, price: "0", reasonCode: "x" }));
    expect(s.result).toMatchObject({ kind: "refused", code: "invalid_input", field: "price" });
    expect(mocks.price).not.toHaveBeenCalled();
    const c = await createTicketTypeForm({ result: null }, fd({ kind: "admission", name: "", price: "10", visibility: "public" }));
    expect(c.result).toMatchObject({ kind: "refused", field: "name" });
    expect(mocks.create).not.toHaveBeenCalled();
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
  it("a refusal or an unavailable answer from D's action is passed through untouched and does not revalidate", async () => {
    mocks.price.mockResolvedValue({ kind: "unavailable", reason: "gate_unset", message: "Commands are not enabled for this project. Tiers and inventory are read-only here for now." });
    const s = await setTicketTypePriceForm({ result: null }, fd({ ticketTypeId: TT, price: "30", reasonCode: "r" }));
    expect(s.result?.kind).toBe("unavailable");
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
  it("ids that are not uuids never reach revalidatePath", async () => {
    const f = fd({ ticketTypeId: TT, price: "30", reasonCode: "r" });
    f.set("eventId", "../../admin");
    await setTicketTypePriceForm({ result: null }, f);
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
});
