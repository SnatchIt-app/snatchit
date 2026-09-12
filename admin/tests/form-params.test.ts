import { describe, expect, it } from "vitest";
import { coerceParam, parseParamField, settingFieldName, settingKind } from "../src/lib/form-params";

describe("parseParamField", () => {
  it("parses plain and typed param names", () => {
    expect(parseParamField("param.status")).toEqual({ key: "status", type: "string" });
    expect(parseParamField("param.value:boolean")).toEqual({ key: "value", type: "boolean" });
    expect(parseParamField("param.amount_cents:integer")).toEqual({ key: "amount_cents", type: "integer" });
  });
  it("rejects non-param fields and unknown types", () => {
    expect(parseParamField("reason")).toBeNull();
    expect(parseParamField("param.value:date")).toBeNull();
    expect(parseParamField("param.:number")).toBeNull();
  });
});

describe("coerceParam (settings value coercion)", () => {
  it("empty string means null for every type", () => {
    for (const t of ["string", "number", "integer", "boolean", "json"] as const) {
      expect(coerceParam(t, "")).toEqual({ ok: true, value: null });
      expect(coerceParam(t, "   ")).toEqual({ ok: true, value: null });
    }
  });
  it("booleans", () => {
    expect(coerceParam("boolean", "true")).toEqual({ ok: true, value: true });
    expect(coerceParam("boolean", "false")).toEqual({ ok: true, value: false });
    expect(coerceParam("boolean", "on")).toEqual({ ok: true, value: true });
    expect(coerceParam("boolean", "maybe").ok).toBe(false);
  });
  it("numbers and integers", () => {
    expect(coerceParam("number", "72")).toEqual({ ok: true, value: 72 });
    expect(coerceParam("number", "1.5")).toEqual({ ok: true, value: 1.5 });
    expect(coerceParam("number", "abc").ok).toBe(false);
    expect(coerceParam("integer", "8250")).toEqual({ ok: true, value: 8250 });
    expect(coerceParam("integer", "12.5").ok).toBe(false);
    expect(coerceParam("integer", "-3")).toEqual({ ok: true, value: -3 });
  });
  it("strings pass through untrimmed; json parses", () => {
    expect(coerceParam("string", " hello ")).toEqual({ ok: true, value: " hello " });
    expect(coerceParam("json", '{"a":1}')).toEqual({ ok: true, value: { a: 1 } });
    expect(coerceParam("json", "{nope").ok).toBe(false);
  });
});

describe("settingKind / settingFieldName", () => {
  it("derives the input type from the current jsonb value", () => {
    expect(settingKind(true)).toBe("boolean");
    expect(settingKind(72)).toBe("number");
    expect(settingKind("x")).toBe("string");
    expect(settingKind({ a: 1 })).toBe("json");
    expect(settingKind(null)).toBe("json");
    expect(settingFieldName(false)).toBe("param.value:boolean");
    expect(settingFieldName(15)).toBe("param.value:number");
    expect(settingFieldName("s")).toBe("param.value:string");
    expect(settingFieldName([1])).toBe("param.value:json");
  });
});
