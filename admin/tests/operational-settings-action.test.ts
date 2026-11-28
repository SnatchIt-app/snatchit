import { revalidatePath } from "next/cache";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ callOps: vi.fn() }));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

import { submitOperationalConfig } from "@/lib/actions";

const KEY = "11111111-2222-4333-8444-555555555555";

function form(over: Record<string, string> = {}): FormData {
  const fd = new FormData();
  fd.set("key", "feature.native_scanning_enabled");
  fd.set("value", "false");
  fd.set("reason", "Stage 8 remains off");
  fd.set("confirm", "feature.native_scanning_enabled");
  fd.set("idempotency_key", KEY);
  for (const [k, v] of Object.entries(over)) fd.set(k, v);
  return fd;
}

describe("submitOperationalConfig", () => {
  beforeEach(() => {
    mocks.callOps.mockReset();
    vi.mocked(revalidatePath).mockClear();
    mocks.callOps.mockResolvedValue({ ok: true, data: { status: "ok", version: 3 } });
  });

  it("calls ops.set_operational_config with the four RPC args and never execute_action", async () => {
    const state = await submitOperationalConfig({}, form());
    expect(mocks.callOps).toHaveBeenCalledTimes(1);
    const [fn, args] = mocks.callOps.mock.calls[0];
    expect(fn).toBe("set_operational_config");
    expect(args).toEqual({
      p_key: "feature.native_scanning_enabled",
      p_value: false,
      p_reason_code: "Stage 8 remains off",
      p_command_key: KEY,
    });
    expect(mocks.callOps.mock.calls.some(([f]) => f === "execute_action")).toBe(false);
    expect(state.submitted).toBe(true);
    expect(state.status).toBe("ok");
    expect(state.appliedVersion).toBe(3);
    expect(state.subjectKey).toBe("feature.native_scanning_enabled");
    expect(revalidatePath).toHaveBeenCalledWith("/system");
  });

  it("returns an invalid state and makes no RPC call for a wrong confirmation", async () => {
    const state = await submitOperationalConfig({}, form({ confirm: "wrong" }));
    expect(state.invalid).toMatch(/Type feature\.native_scanning_enabled exactly to confirm/);
    expect(state.subjectKey).toBe("feature.native_scanning_enabled");
    expect(mocks.callOps).not.toHaveBeenCalled();
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("returns an invalid state for a money key, before any RPC call", async () => {
    const state = await submitOperationalConfig({}, form({ key: "fee.buyer_service_bps" }));
    expect(state.invalid).toBe("Choose a setting.");
    expect(state.subjectKey).toBe("fee.buyer_service_bps");
    expect(mocks.callOps).not.toHaveBeenCalled();
  });

  it("turns a concurrent (key,version) collision into a validation message, not a failure", async () => {
    mocks.callOps.mockResolvedValueOnce({ ok: false, kind: "error", code: "23505", message: "duplicate key value violates unique constraint" });
    const state = await submitOperationalConfig({}, form());
    expect(state.invalid).toMatch(/concurrent or duplicate write was refused/);
    expect(state.subjectKey).toBe("feature.native_scanning_enabled");
    expect(state.failure).toBeUndefined();
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("propagates a denied/mfa/unavailable failure unchanged", async () => {
    for (const failure of [
      { ok: false as const, kind: "denied" as const },
      { ok: false as const, kind: "mfa" as const },
      { ok: false as const, kind: "error" as const, message: "RPC ops.set_operational_config not available yet", unavailable: true },
    ]) {
      mocks.callOps.mockResolvedValueOnce(failure);
      const state = await submitOperationalConfig({}, form());
      expect(state.failure).toEqual(failure);
      expect(state.subjectKey).toBe("feature.native_scanning_enabled");
      expect(revalidatePath).not.toHaveBeenCalled();
    }
  });
});
