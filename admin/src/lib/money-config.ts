/**
 * Money settings (registry 196): the kernel's dual-control flow for money-key
 * changes, surfaced on /system.
 *
 *   request  ops.request_platform_config  — platform_admin + aal2; a loosening
 *            is parked for a second founder, a tightening applies at once
 *            (catalog.set_platform_config decides which, not the console).
 *   list     ops.list_config_approvals    — platform_admin + aal2.
 *   decide   kernel.approve_refund_request — a DIFFERENT platform_admin, aal2
 *            to approve; the requester can never decide their own request.
 *
 * Pure parsing / validation only (no `server-only`), so it is unit-testable.
 * Every rule here is UX: the database re-checks all of it.
 */
import { asRecords, bool, isRecord, num, parseApprovalDecision, str, type ApprovalDecision, type Json } from "@/lib/types";
import { isIdempotencyKey } from "@/lib/idempotency";

export type MoneyKey = { key: string; version: number | null; value: Json };

export type MoneyConfigRequest = {
  request_id: string;
  key: string | null;
  proposed_value: Json;
  value_at_request: Json;
  version_at_request: number | null;
  live_version: number | null;
  live_value: Json;
  key_changed_since_request: boolean | null;
  state: string | null;
  is_expired: boolean | null;
  reason_code: string | null;
  requested_by: string | null;
  decided_by: string | null;
  requested_by_me: boolean | null;
  can_decide: boolean | null;
  expires_at: string | null;
  created_at: string | null;
  updated_at: string | null;
};

export type MoneyConfigList = { items: MoneyConfigRequest[]; money_keys: MoneyKey[]; state: string | null };

function json(v: unknown): Json {
  return v === undefined ? null : (v as Json);
}

export function toMoneyConfigRequest(v: unknown): MoneyConfigRequest | null {
  if (!isRecord(v)) return null;
  const id = str(v.request_id);
  if (!id) return null;
  return {
    request_id: id,
    key: str(v.key),
    proposed_value: json(v.proposed_value),
    value_at_request: json(v.value_at_request),
    version_at_request: num(v.version_at_request),
    live_version: num(v.live_version),
    live_value: json(v.live_value),
    key_changed_since_request: bool(v.key_changed_since_request),
    state: str(v.state),
    is_expired: bool(v.is_expired),
    reason_code: str(v.reason_code),
    requested_by: str(v.requested_by),
    decided_by: str(v.decided_by),
    requested_by_me: bool(v.requested_by_me),
    can_decide: bool(v.can_decide),
    expires_at: str(v.expires_at),
    created_at: str(v.created_at),
    updated_at: str(v.updated_at),
  };
}

export function toMoneyConfigList(v: unknown): MoneyConfigList {
  const r = isRecord(v) ? v : {};
  return {
    items: asRecords(r.items).map(toMoneyConfigRequest).filter((x): x is MoneyConfigRequest => x !== null),
    money_keys: asRecords(r.money_keys)
      .map((k) => (str(k.key) ? { key: str(k.key) as string, version: num(k.version), value: json(k.value) } : null))
      .filter((k): k is MoneyKey => k !== null),
    state: str(r.state),
  };
}

/** A key name as catalog.platform_config spells them (lower-case dotted). */
const KEY_RE = /^[a-z0-9_]+(\.[a-z0-9_]+)+$/;
const REQUEST_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const REASON_MAX = 2000;

/**
 * The new value is typed as JSON so its type is explicit: 2500 (number),
 * "24 hours" (string — interval keys need the quotes), true, null. A bare
 * word is refused rather than guessed: catalog.set_platform_config keeps
 * each key's JSON type and reads a bare number as SECONDS on interval keys.
 */
export function parseConfigValue(raw: string): { ok: true; value: Json } | { ok: false; error: string } {
  const t = raw.trim();
  if (t === "") return { ok: false, error: 'Enter a JSON value, e.g. 2500, "24 hours", true or null.' };
  try {
    return { ok: true, value: JSON.parse(t) as Json };
  } catch {
    return { ok: false, error: 'Not valid JSON — a text value needs double quotes, e.g. "24 hours".' };
  }
}

export type RequestArgs = { p_key: string; p_value: Json; p_reason_code: string; p_command_key: string };

export function buildConfigRequestArgs(input: {
  key: unknown;
  value: unknown;
  reason: unknown;
  commandKey: unknown;
}): { ok: true; args: RequestArgs } | { ok: false; invalid: string } {
  if (!isIdempotencyKey(input.commandKey)) return { ok: false, invalid: "Missing form key — reload the page and try again." };
  const key = typeof input.key === "string" ? input.key.trim() : "";
  if (!KEY_RE.test(key)) return { ok: false, invalid: "Choose a money key." };
  const value = parseConfigValue(typeof input.value === "string" ? input.value : "");
  if (!value.ok) return { ok: false, invalid: value.error };
  const reason = typeof input.reason === "string" ? input.reason.trim() : "";
  if (!reason) return { ok: false, invalid: "A reason is required." };
  if (reason.length > REASON_MAX) return { ok: false, invalid: `Reason is too long (${REASON_MAX} characters max).` };
  return { ok: true, args: { p_key: key, p_value: value.value, p_reason_code: reason, p_command_key: input.commandKey } };
}

export type DecisionArgs = { p_request_id: string; p_decision: ApprovalDecision; p_reason_code: string; p_command_key: string };

export function buildDecisionArgs(input: {
  requestId: unknown;
  decision: unknown;
  reason: unknown;
  commandKey: unknown;
}): { ok: true; args: DecisionArgs } | { ok: false; invalid: string } {
  if (!isIdempotencyKey(input.commandKey)) return { ok: false, invalid: "Missing form key — reload the page and try again." };
  const requestId = typeof input.requestId === "string" ? input.requestId : "";
  if (!REQUEST_ID_RE.test(requestId)) return { ok: false, invalid: "This form is missing its request id. Reload and try again." };
  // Never default a decision: an unrecognised value must not approve.
  const decision = parseApprovalDecision(input.decision);
  if (!decision) return { ok: false, invalid: "invalid decision" };
  const reason = typeof input.reason === "string" ? input.reason.trim() : "";
  if (!reason) return { ok: false, invalid: "A reason is required." };
  if (reason.length > REASON_MAX) return { ok: false, invalid: `Reason is too long (${REASON_MAX} characters max).` };
  return { ok: true, args: { p_request_id: requestId, p_decision: decision, p_reason_code: reason, p_command_key: input.commandKey } };
}

/** What the request call answered (catalog.set_platform_config's status). */
export function requestOutcomeText(status: string | null | undefined): { tone: "success" | "warning" | "info"; title: string } | null {
  switch (status) {
    case "parked":
      return { tone: "warning", title: "Requested — nothing has changed yet. A different founder must approve it." };
    case "ok":
      return { tone: "success", title: "Applied now — a tightening takes effect with one founder." };
    case "noop_replay":
      return { tone: "info", title: "No change — that is already the current value." };
    default:
      return null;
  }
}

/** What kernel.approve_refund_request answered. */
export function decisionOutcomeText(status: string | null | undefined): { tone: "success" | "info"; title: string } | null {
  switch (status) {
    case "approved":
      return { tone: "success", title: "Approved — the new value is now the live version of the key." };
    case "denied":
      return { tone: "info", title: "Denied — the key keeps its current value." };
    case "noop_replay":
      return { tone: "info", title: "Already decided — nothing changed." };
    default:
      return null;
  }
}

/** One-line JSON for display; undefined/absent renders as an em dash. */
export function showValue(v: Json | undefined): string {
  return v === undefined ? "—" : JSON.stringify(v);
}
