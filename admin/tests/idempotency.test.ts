import { describe, expect, it } from "vitest";
import { IDEMPOTENCY_FIELD, idempotencyField, isIdempotencyKey, newIdempotencyKey } from "../src/lib/idempotency";

describe("idempotency keys", () => {
  it("mints unique v4 UUIDs", () => {
    const a = newIdempotencyKey();
    const b = newIdempotencyKey();
    expect(isIdempotencyKey(a)).toBe(true);
    expect(isIdempotencyKey(b)).toBe(true);
    expect(a).not.toBe(b);
  });

  it("rejects non-UUID keys so a tampered form cannot pick its own key shape", () => {
    for (const v of ["", "abc", 123, null, undefined, "00000000-0000-0000-0000-000000000000"]) {
      expect(isIdempotencyKey(v)).toBe(false);
    }
  });

  it("produces hidden-input props that carry the same key", () => {
    const key = newIdempotencyKey();
    expect(idempotencyField(key)).toEqual({ type: "hidden", name: IDEMPOTENCY_FIELD, value: key });
    expect(() => idempotencyField("not-a-uuid")).toThrow();
    const generated = idempotencyField();
    expect(isIdempotencyKey(generated.value)).toBe(true);
  });
});
