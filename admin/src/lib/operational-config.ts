/**
 * Operational settings (registry 197): the four single-admin platform keys.
 * One platform_admin at aal2 changes them at once — no second founder (they
 * are not dual-control money keys).
 *
 *   list  ops.list_operational_config — live version + value per key.
 *   set   ops.set_operational_config  — INVOKER passthrough to
 *         catalog.set_platform_config, which validates the value and writes
 *         the audit row. aal2 is enforced on THIS path only.
 *
 * Pure parsing / validation (no `server-only`) so it is unit-testable. These
 * rules are UX. The database re-checks the value type/parseability; the console
 * additionally caps the hold max at int4 because a larger value breaks the
 * consumer. The database does NOT enforce interval positivity/finiteness; the
 * 197 wrapper enforces role, aal2 and the four-key allow-list.
 */
import { asRecords, isRecord, num, str, type Json } from "@/lib/types";
import { isIdempotencyKey } from "@/lib/idempotency";

export type OperationalKind = "integer" | "interval" | "boolean";

export type OperationalKeySpec = { key: string; label: string; kind: OperationalKind; help: string };

/** The allow-list, in the order ops.list_operational_config returns it. */
export const OPERATIONAL_KEYS: readonly OperationalKeySpec[] = [
  {
    key: "inventory.per_user_active_hold_max",
    label: "Hold max per buyer",
    kind: "integer",
    help: "Active holds one buyer may have at once. A whole number of at least 1. Unset = every reserve is refused.",
  },
  {
    key: "inventory.hold_ttl_interval",
    label: "Hold lifetime",
    kind: "interval",
    help: 'How long a hold lasts, as an interval such as "10 minutes". Unset = holds are refused (hold_ttl_unset).',
  },
  {
    key: "feature.native_issuance_enabled",
    label: "Native ticket issuance",
    kind: "boolean",
    help: "The Stage 8 flip and the sales kill switch: false stops native issuance.",
  },
  {
    key: "feature.native_scanning_enabled",
    label: "Native door scanning",
    kind: "boolean",
    help: "The Stage 8 scanning flip.",
  },
];

export function specFor(key: unknown): OperationalKeySpec | null {
  return OPERATIONAL_KEYS.find((s) => s.key === key) ?? null;
}

export type OperationalSetting = { key: string; version: number | null; value: Json; effective_from: string | null; created_at: string | null };

export function toOperationalSettings(v: unknown): OperationalSetting[] | null {
  // A successful read must carry an items array. Anything else is a malformed
  // payload, never an empty "all unset" list that would enable a blind write.
  if (!isRecord(v) || !Array.isArray(v.items)) return null;
  const out = asRecords(v.items)
    .map((i) =>
      str(i.key)
        ? { key: str(i.key) as string, version: num(i.version), value: (i.value === undefined ? null : i.value) as Json, effective_from: str(i.effective_from), created_at: str(i.created_at) }
        : null,
    )
    .filter((x): x is OperationalSetting => x !== null);
  // 197 always emits exactly the four keys (197:144-158). A partial/empty list is
  // a foreign payload, not "all unset": never enable a blind write from it.
  if (out.length !== OPERATIONAL_KEYS.length) return null;
  return OPERATIONAL_KEYS.every((k) => out.some((o) => o.key === k.key)) ? out : null;
}

/**
 * The value in the type the key keeps (catalog.set_platform_config's type
 * witness). The database requires a JSON string for an interval; a JSON
 * numeric value (600) is refused there. The console additionally refuses a
 * bare-number STRING such as "600" as UX, because it would silently mean 600
 * seconds. This is not a complete PostgreSQL interval parser; it validates
 * only the documented UX forms below. The database remains the authority for
 * parseability, and it does NOT enforce positivity or a maximum.
 */
const PLAIN_INTERVAL_RE = /^(?:\d+(?:\.\d+)?\s*(?:s|sec|secs|seconds?|m|min|mins|minutes?|h|hr|hrs|hours?|d|day|days|w|wk|wks|weeks?)\s*)+$/i;
const ISO_DURATION_RE = /^P(?=\d|T\d)(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)W)?(?:(\d+(?:\.\d+)?)D)?(?:T(?=\d)(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$/;

/** Supported UX syntax only: repeated "<positive number> <unit>" or an ISO-8601 duration. */
function positiveInterval(t: string): "ok" | "zero" | "invalid" {
  if (PLAIN_INTERVAL_RE.test(t)) {
    const nums = [...t.matchAll(/\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));
    if (nums.length === 0 || !nums.every(Number.isFinite)) return "invalid";
    return nums.some((n) => n > 0) ? "ok" : "zero";
  }
  const m = ISO_DURATION_RE.exec(t);
  if (m) {
    const nums = m.slice(1).filter((x): x is string => typeof x === "string").map(Number);
    if (nums.length === 0 || !nums.every(Number.isFinite)) return "invalid";
    return nums.some((n) => n > 0) ? "ok" : "zero";
  }
  return "invalid";
}

export function parseOperationalValue(kind: OperationalKind, raw: string): { ok: true; value: Json } | { ok: false; error: string } {
  const t = raw.trim();
  switch (kind) {
    case "integer": {
      if (!/^\d+$/.test(t)) return { ok: false, error: "Enter a whole number of at least 1." };
      const n = Number(t);
      if (!Number.isSafeInteger(n) || n < 1) return { ok: false, error: "Enter a whole number of at least 1." };
      if (n > 2147483647) return { ok: false, error: "Enter a whole number no larger than 2147483647." };
      return { ok: true, value: n };
    }
    case "interval": {
      if (t === "") return { ok: false, error: 'Enter an interval such as "10 minutes".' };
      if (/^\d+(\.\d+)?$/.test(t)) return { ok: false, error: 'A bare number would be read as seconds — write it with a unit, e.g. "10 minutes".' };
      if (/^[+-]/.test(t) || /\bago\b/i.test(t) || /\binf(inity)?\b/i.test(t)) return { ok: false, error: 'A hold lifetime must be a positive, finite interval, e.g. "10 minutes" or "PT0.5S".' };
      const pos = positiveInterval(t);
      if (pos === "zero") return { ok: false, error: "A hold lifetime must be greater than zero." };
      if (pos === "invalid") return { ok: false, error: 'Use a positive, finite interval such as "10 minutes", "0.5 minutes", "PT0.5S" or "P0Y1D".' };
      return { ok: true, value: t };
    }
    case "boolean":
      if (t === "true") return { ok: true, value: true };
      if (t === "false") return { ok: true, value: false };
      return { ok: false, error: "Choose true or false." };
  }
}

export type OperationalArgs = { p_key: string; p_value: Json; p_reason_code: string; p_command_key: string };

export const REASON_MAX = 2000;

/** The typed confirmation is the key name itself, so the operator names exactly what they are changing. */
export function buildOperationalArgs(input: {
  key: unknown;
  value: unknown;
  reason: unknown;
  confirm: unknown;
  commandKey: unknown;
}): { ok: true; args: OperationalArgs } | { ok: false; invalid: string } {
  if (!isIdempotencyKey(input.commandKey)) return { ok: false, invalid: "Missing form key — reload the page and try again." };
  const spec = specFor(input.key);
  if (!spec) return { ok: false, invalid: "Choose a setting." };
  const value = parseOperationalValue(spec.kind, typeof input.value === "string" ? input.value : "");
  if (!value.ok) return { ok: false, invalid: value.error };
  const reason = typeof input.reason === "string" ? input.reason.trim() : "";
  if (!reason) return { ok: false, invalid: "A reason is required." };
  if (reason.length > REASON_MAX) return { ok: false, invalid: `Reason is too long (${REASON_MAX} characters max).` };
  const confirm = typeof input.confirm === "string" ? input.confirm.trim() : "";
  if (confirm !== spec.key) return { ok: false, invalid: `Type ${spec.key} exactly to confirm.` };
  return { ok: true, args: { p_key: spec.key, p_value: value.value, p_reason_code: reason, p_command_key: input.commandKey } };
}

/** What catalog.set_platform_config answered. */
export function operationalOutcomeText(status: string | null | undefined): { tone: "success" | "info"; title: string } | null {
  switch (status) {
    case "ok":
      return { tone: "success", title: "Applied — the new value is live now." };
    case "noop_replay":
      return { tone: "info", title: "No change — that is already the live value." };
    case "parked":
      return { tone: "info", title: "Parked — nothing has been applied yet." };
    default:
      return null;
  }
}

/** A live value for display: JSON null is "unset" in words, never a blank. */
export function showSetting(v: Json | undefined): string {
  return v === undefined || v === null ? "unset" : (JSON.stringify(v) ?? "unset");
}
