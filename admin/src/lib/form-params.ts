/**
 * Typed `param.*` form fields for ConfirmForm → ops.execute_action.
 *
 * Every visible input is a string on the wire. A field named
 * `param.<key>:<type>` is coerced before it becomes a `p_params` entry, so a
 * jsonb-typed setting (boolean / number) or a cents amount arrives with the
 * right JSON type. Pure and unit-tested.
 */
export type ParamType = "string" | "number" | "integer" | "boolean" | "json";

export const PARAM_TYPES: ParamType[] = ["string", "number", "integer", "boolean", "json"];

export function parseParamField(name: string): { key: string; type: ParamType } | null {
  if (!name.startsWith("param.")) return null;
  const rest = name.slice("param.".length);
  const colon = rest.indexOf(":");
  if (colon === -1) return { key: rest, type: "string" };
  const key = rest.slice(0, colon);
  const type = rest.slice(colon + 1) as ParamType;
  if (!key || !PARAM_TYPES.includes(type)) return null;
  return { key, type };
}

export type Coerced = { ok: true; value: unknown } | { ok: false; error: string };

/** Empty string → null for every type ("clear" semantics), else coerce. */
export function coerceParam(type: ParamType, raw: string): Coerced {
  const s = raw.trim();
  if (s === "") return { ok: true, value: null };
  switch (type) {
    case "string":
      return { ok: true, value: raw };
    case "boolean":
      if (s === "true" || s === "1" || s === "on" || s === "yes") return { ok: true, value: true };
      if (s === "false" || s === "0" || s === "off" || s === "no") return { ok: true, value: false };
      return { ok: false, error: `"${raw}" is not a boolean` };
    case "number": {
      const n = Number(s);
      if (!Number.isFinite(n)) return { ok: false, error: `"${raw}" is not a number` };
      return { ok: true, value: n };
    }
    case "integer": {
      if (!/^-?\d+$/.test(s)) return { ok: false, error: `"${raw}" is not a whole number` };
      const n = Number(s);
      if (!Number.isSafeInteger(n)) return { ok: false, error: `"${raw}" is out of range` };
      return { ok: true, value: n };
    }
    case "json":
      try {
        return { ok: true, value: JSON.parse(s) };
      } catch {
        return { ok: false, error: `"${raw}" is not valid JSON` };
      }
  }
}

/** jsonb_typeof → which input to render for a setting value. */
export type SettingKind = "boolean" | "number" | "string" | "json";

export function settingKind(value: unknown): SettingKind {
  if (typeof value === "boolean") return "boolean";
  if (typeof value === "number") return "number";
  if (typeof value === "string") return "string";
  return "json";
}

/** Field name for a setting's value input so the server coerces to the current jsonb type. */
export function settingFieldName(value: unknown): string {
  const k = settingKind(value);
  return `param.value:${k === "json" ? "json" : k}`;
}
