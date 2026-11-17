import { describe, expect, it } from "vitest";
import {
  OPERATIONAL_KEYS,
  buildOperationalArgs,
  operationalOutcomeText,
  parseOperationalValue,
  showSetting,
  specFor,
  toOperationalSettings,
} from "@/lib/operational-config";

const KEY = "11111111-2222-4333-8444-555555555555";

describe("operational key allow-list", () => {
  it("is exactly the four single-admin keys, in list order", () => {
    expect(OPERATIONAL_KEYS.map((k) => k.key)).toEqual([
      "inventory.per_user_active_hold_max",
      "inventory.hold_ttl_interval",
      "feature.native_issuance_enabled",
      "feature.native_scanning_enabled",
    ]);
    expect(specFor("fee.buyer_service_bps")).toBeNull();
    expect(specFor("inventory.per_user_active_hold_max")?.kind).toBe("integer");
    expect(specFor("inventory.hold_ttl_interval")?.kind).toBe("interval");
    expect(specFor("feature.native_scanning_enabled")?.kind).toBe("boolean");
  });
});

describe("parseOperationalValue", () => {
  it("accepts a whole integer >= 1 and rejects zero, negatives, fractions and strings", () => {
    expect(parseOperationalValue("integer", "6")).toEqual({ ok: true, value: 6 });
    expect(parseOperationalValue("integer", "2147483647")).toEqual({ ok: true, value: 2147483647 });
    for (const raw of ["0", "-1", "1.5", "abc", "", "  ", "2147483648"]) {
      expect(parseOperationalValue("integer", raw).ok, raw).toBe(false);
    }
  });

  it("interval refuses a bare number and accepts a unit string", () => {
    expect(parseOperationalValue("interval", "10 minutes")).toEqual({ ok: true, value: "10 minutes" });
    for (const raw of ["600", "1.5", "", "  ", "-5 minutes", "+5 minutes", "0 seconds", "infinity", "-infinity", "00:00:00", "PT0S", "P0D", "5 minutes ago", "infinity days"]) {
      expect(parseOperationalValue("interval", raw).ok, raw).toBe(false);
    }
    for (const raw of ["0.5 minutes", "0 days 5 minutes", "PT0.5S", "P0Y1D"]) {
      expect(parseOperationalValue("interval", raw), raw).toEqual({ ok: true, value: raw });
    }
  });

  it("refuses zero, unsupported zero-like, and numeric overflow in plain, ISO and mixed components", () => {
    expect(parseOperationalValue("interval", "PT0S")).toEqual({ ok: false, error: "A hold lifetime must be greater than zero." });
    expect(parseOperationalValue("interval", "P0D")).toEqual({ ok: false, error: "A hold lifetime must be greater than zero." });
    expect(parseOperationalValue("interval", "00:00:00")).toEqual({
      ok: false,
      error: 'Use a positive, finite interval such as "10 minutes", "0.5 minutes", "PT0.5S" or "P0Y1D".',
    });
    const huge = "9".repeat(400);
    const overflowError = 'Use a positive, finite interval such as "10 minutes", "0.5 minutes", "PT0.5S" or "P0Y1D".';
    expect(parseOperationalValue("interval", `${huge} minutes`)).toEqual({ ok: false, error: overflowError });
    expect(parseOperationalValue("interval", `P${huge}D`)).toEqual({ ok: false, error: overflowError });
    expect(parseOperationalValue("interval", `10 minutes ${huge} seconds`)).toEqual({ ok: false, error: overflowError });
    expect(parseOperationalValue("interval", `P1Y${huge}D`)).toEqual({ ok: false, error: overflowError });
  });

  it("boolean accepts only the literal strings true/false", () => {
    expect(parseOperationalValue("boolean", "true")).toEqual({ ok: true, value: true });
    expect(parseOperationalValue("boolean", "false")).toEqual({ ok: true, value: false });
    for (const raw of ["True", "1", "yes", "", " true "]) {
      // true with surrounding whitespace is trimmed and accepted; the others are not
      if (raw === " true ") expect(parseOperationalValue("boolean", raw)).toEqual({ ok: true, value: true });
      else expect(parseOperationalValue("boolean", raw).ok, raw).toBe(false);
    }
  });
});

describe("buildOperationalArgs", () => {
  const base = {
    key: "feature.native_scanning_enabled",
    value: "false",
    reason: "Stage 8 remains off",
    confirm: "feature.native_scanning_enabled",
    commandKey: KEY,
  };

  it("builds exactly the RPC argument names and the typed value", () => {
    expect(buildOperationalArgs(base)).toEqual({
      ok: true,
      args: {
        p_key: "feature.native_scanning_enabled",
        p_value: false,
        p_reason_code: "Stage 8 remains off",
        p_command_key: KEY,
      },
    });
  });

  it("refuses an unknown or money key, a bad value, a missing reason, a bad command key and a wrong confirmation", () => {
    expect(buildOperationalArgs({ ...base, key: "fee.buyer_service_bps" }).ok).toBe(false);
    expect(buildOperationalArgs({ ...base, value: "yes" }).ok).toBe(false);
    expect(buildOperationalArgs({ ...base, reason: "  " }).ok).toBe(false);
    expect(buildOperationalArgs({ ...base, reason: "x".repeat(2001) }).ok).toBe(false);
    expect(buildOperationalArgs({ ...base, commandKey: "not-a-key" }).ok).toBe(false);
    expect(buildOperationalArgs({ ...base, confirm: "inventory.hold_ttl_interval" }).ok).toBe(false);
  });

  it("trims the confirmation and the reason", () => {
    const built = buildOperationalArgs({ ...base, confirm: "  feature.native_scanning_enabled  ", reason: "  off  " });
    expect(built.ok).toBe(true);
    if (built.ok) expect(built.args.p_reason_code).toBe("off");
  });
});

describe("display helpers", () => {
  it("renders JSON null/undefined as unset, strings quoted, numbers/booleans as JSON", () => {
    expect(showSetting(null)).toBe("unset");
    expect(showSetting(undefined)).toBe("unset");
    expect(showSetting("10 minutes")).toBe('"10 minutes"');
    expect(showSetting(6)).toBe("6");
    expect(showSetting(false)).toBe("false");
  });

  it("maps ok/noop_replay/parked, and leaves other statuses unknown", () => {
    expect(operationalOutcomeText("ok")?.tone).toBe("success");
    expect(operationalOutcomeText("noop_replay")?.tone).toBe("info");
    expect(operationalOutcomeText("parked")?.title).toBe("Parked — nothing has been applied yet.");
    expect(operationalOutcomeText("other")).toBeNull();
    expect(operationalOutcomeText(null)).toBeNull();
  });

  it("requires exactly the four keys and tolerates extra fields", () => {
    const full = OPERATIONAL_KEYS.map((k, i) => ({
      key: k.key,
      version: i + 1,
      value: i === 0 ? 6 : i === 1 ? "10 minutes" : null,
      effective_from: "2026-10-31T00:00:00Z",
      created_at: "2026-10-31T00:00:00Z",
      extra: "ignored",
    }));
    expect(toOperationalSettings({ items: full, next_cursor: null, count_hint: 4 })).toEqual(
      full.map(({ key, version, value, effective_from, created_at }) => ({ key, version, value, effective_from, created_at })),
    );
    expect(toOperationalSettings({ items: full.slice(0, 3) })).toBeNull();
    expect(toOperationalSettings({ items: [] })).toBeNull();
    expect(toOperationalSettings(null)).toBeNull();
    expect(toOperationalSettings({ items: "nope" })).toBeNull();
  });
});
