"use server";

import "server-only";

import { COMMAND_COPY, commandTransportFailure, invalidInput, mapCommandError, NO_RECEIPT_COPY, NOT_ENABLED_COPY, type CommandRefused, type CommandResult, type CommandUnavailable } from "@/lib/db/command-errors";
import { DATA_SOURCE } from "@/lib/env";
import { isUuid } from "@/lib/page";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * Event, session and venue commands (readiness row 2), DARK.
 *
 * Same two locks as D's tier commands: database mode AND the server-only
 * VENUE_COMMANDS_ENABLED exactly "true". Nothing sets the second today, so
 * every action here answers `unavailable` in every environment.
 *
 * Transport: `.schema("venue_cmd").rpc(name, args)` under the operator's own
 * session. The `venue_cmd.*` wrappers (migration 164) are SECURITY INVOKER
 * shims over the `catalog.*` bodies, which hold the authority check, the
 * preconditions and the audit row — `authenticated` already carries EXECUTE on
 * those bodies (078/079/081 grant loops); the wrapper exists only because
 * `catalog` is not PostgREST-exposed. The dashboard adds nothing and bypasses
 * nothing.
 *
 * RPC contract coded against (names and parameter names are the server's):
 *   create_event(p_venue_id uuid, p_title text, p_first_session jsonb, p_command_key text)
 *   update_event(p_event_id uuid, p_patch jsonb, p_command_key text)
 *   create_event_session(p_event_id uuid, p_session jsonb, p_command_key text)
 *   update_event_session(p_session_id uuid, p_patch jsonb, p_command_key text)
 *   publish_event(p_event_id uuid, p_target_status text, p_command_key text)
 *   cancel_event(p_event_id uuid, p_reason_code text, p_command_key text)
 *   update_venue(p_venue_id uuid, p_patch jsonb, p_command_key text)
 *   set_venue_timezone(p_venue_id uuid, p_timezone text, p_reason_code text, p_command_key text)   (162)
 *   set_session_sales_capacity(p_session_id uuid, p_capacity integer, p_reason_code text, p_command_key text)  (162)
 *
 * Every payload is built by the pure layer in lib/events/command-contract.ts,
 * which refuses keys the server would reject — or, for the session verbs, keys
 * the server would silently ignore.
 */
const SCHEMA = "venue_cmd";

export type CommandReceipt = { status: string } & Record<string, unknown>;

export type CreateEventInput = { venueId: string; title: string; firstSession: Record<string, unknown>; commandKey: string };
export type UpdateEventInput = { eventId: string; patch: Record<string, unknown>; commandKey: string };
export type CreateSessionInput = { eventId: string; session: Record<string, unknown>; commandKey: string };
export type UpdateSessionInput = { sessionId: string; patch: Record<string, unknown>; commandKey: string };
export type PublishEventInput = { eventId: string; targetStatus: string; commandKey: string };
export type CancelEventInput = { eventId: string; reasonCode: string; commandKey: string };
export type UpdateVenueInput = { venueId: string; patch: Record<string, unknown>; commandKey: string };
export type SetVenueTimezoneInput = { venueId: string; timezone: string; reasonCode: string; commandKey: string };
export type SetSessionCapacityInput = { sessionId: string; capacity: number | null; reasonCode: string; commandKey: string };

const PUBLISH_TARGETS = ["announced", "on_sale", "live", "completed"];
const INT4_MAX = 2_147_483_647;

export async function mintCommandKey(): Promise<string> {
  return crypto.randomUUID();
}

export async function createEventAction(input: CreateEventInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(needUuid(input?.venueId, "venueId"), needText(input?.title, "title", "An event needs a title."), needSession(input?.firstSession), needKey(input?.commandKey));
  if (bad) return bad;
  return send("create_event", { p_venue_id: input.venueId, p_title: input.title.trim(), p_first_session: input.firstSession, p_command_key: input.commandKey });
}

export async function updateEventAction(input: UpdateEventInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(needUuid(input?.eventId, "eventId"), needPatch(input?.patch, "patch"), needKey(input?.commandKey));
  if (bad) return bad;
  return send("update_event", { p_event_id: input.eventId, p_patch: input.patch, p_command_key: input.commandKey });
}

export async function createEventSessionAction(input: CreateSessionInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(needUuid(input?.eventId, "eventId"), needSession(input?.session), needKey(input?.commandKey));
  if (bad) return bad;
  return send("create_event_session", { p_event_id: input.eventId, p_session: input.session, p_command_key: input.commandKey });
}

export async function updateEventSessionAction(input: UpdateSessionInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(needUuid(input?.sessionId, "sessionId"), needPatch(input?.patch, "patch"), needKey(input?.commandKey));
  if (bad) return bad;
  return send("update_event_session", { p_session_id: input.sessionId, p_patch: input.patch, p_command_key: input.commandKey });
}

export async function publishEventAction(input: PublishEventInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(
    needUuid(input?.eventId, "eventId"),
    PUBLISH_TARGETS.includes(input?.targetStatus) ? null : invalidInput("targetStatus", "An event moves to announced, on sale, live or completed. Cancelling is a separate action."),
    needKey(input?.commandKey),
  );
  if (bad) return bad;
  return send("publish_event", { p_event_id: input.eventId, p_target_status: input.targetStatus, p_command_key: input.commandKey });
}

export async function cancelEventAction(input: CancelEventInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(needUuid(input?.eventId, "eventId"), needText(input?.reasonCode, "reasonCode", COMMAND_COPY.reason_required), needKey(input?.commandKey));
  if (bad) return bad;
  return send("cancel_event", { p_event_id: input.eventId, p_reason_code: input.reasonCode.trim(), p_command_key: input.commandKey });
}

export async function updateVenueAction(input: UpdateVenueInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(needUuid(input?.venueId, "venueId"), needPatch(input?.patch, "patch"), needKey(input?.commandKey));
  if (bad) return bad;
  // The server refuses an org move (operatorship_transfer_frozen); never send it, whatever the caller built.
  if ("org_id" in (input.patch ?? {})) return invalidInput("patch", "Moving a venue to another organization is not something this dashboard does.");
  return send("update_venue", { p_venue_id: input.venueId, p_patch: input.patch, p_command_key: input.commandKey });
}

export async function setVenueTimezoneAction(input: SetVenueTimezoneInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const bad = firstProblem(
    needUuid(input?.venueId, "venueId"),
    needText(input?.timezone, "timezone", "Choose the venue's time zone."),
    needText(input?.reasonCode, "reasonCode", COMMAND_COPY.reason_required),
    needKey(input?.commandKey),
  );
  if (bad) return bad;
  return send("set_venue_timezone", { p_venue_id: input.venueId, p_timezone: input.timezone.trim(), p_reason_code: input.reasonCode.trim(), p_command_key: input.commandKey });
}

export async function setSessionSalesCapacityAction(input: SetSessionCapacityInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const capacity = input?.capacity;
  const capacityProblem =
    capacity === null || (typeof capacity === "number" && Number.isInteger(capacity) && capacity > 0 && capacity <= INT4_MAX)
      ? null
      : invalidInput("capacity", "Enter a whole number above zero, or leave it empty for unlimited.");
  const bad = firstProblem(needUuid(input?.sessionId, "sessionId"), capacityProblem, needText(input?.reasonCode, "reasonCode", COMMAND_COPY.reason_required), needKey(input?.commandKey));
  if (bad) return bad;
  return send("set_session_sales_capacity", { p_session_id: input.sessionId, p_capacity: capacity, p_reason_code: input.reasonCode.trim(), p_command_key: input.commandKey });
}

// ---------------------------------------------------------------------------
// Module-private (a "use server" file may only export async functions).
// ---------------------------------------------------------------------------

function gate(): CommandUnavailable | null {
  if (DATA_SOURCE !== "database") return { kind: "unavailable", reason: "fixtures_mode", message: NOT_ENABLED_COPY };
  if (process.env.VENUE_COMMANDS_ENABLED !== "true") return { kind: "unavailable", reason: "gate_unset", message: NOT_ENABLED_COPY };
  return null;
}

function firstProblem(...checks: Array<CommandRefused | null>): CommandRefused | null {
  return checks.find((c) => c !== null) ?? null;
}
function needUuid(v: unknown, field: string): CommandRefused | null {
  return typeof v === "string" && isUuid(v) ? null : invalidInput(field, "Missing or malformed id.");
}
function needText(v: unknown, field: string, copy: string): CommandRefused | null {
  return typeof v === "string" && v.trim().length > 0 ? null : invalidInput(field, copy);
}
function needKey(v: unknown): CommandRefused | null {
  return needText(v, "commandKey", COMMAND_COPY.command_key_required);
}
/** A patch must be a non-empty plain object: an empty one would be a write of nothing. */
function needPatch(v: unknown, field: string): CommandRefused | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return invalidInput(field, "Nothing to change.");
  const keys = Object.keys(v as object).filter((k) => k !== "reason_code");
  return keys.length > 0 ? null : invalidInput(field, "Nothing to change.");
}
/** A session payload must at least carry starts_at: the server refuses `starts_at required`. */
function needSession(v: unknown): CommandRefused | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return invalidInput("session", "A session needs a start time.");
  const rec = v as Record<string, unknown>;
  return typeof rec.starts_at === "string" && rec.starts_at.length > 0 ? null : invalidInput("starts_at", "A session needs a start time.");
}

type PgError = { code?: string | null; message?: string | null; details?: string | null; hint?: string | null };
type RpcResponse = { data: unknown; error: PgError | null; status?: number };
type CmdClient = { rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse> };

function isReceipt(d: unknown): d is CommandReceipt {
  return typeof d === "object" && d !== null && !Array.isArray(d) && typeof (d as { status?: unknown }).status === "string";
}

async function send(fn: string, args: Record<string, unknown>): Promise<CommandResult<CommandReceipt>> {
  let c: CmdClient;
  try {
    c = (await createSupabaseServerClient()).schema(SCHEMA) as unknown as CmdClient;
  } catch (e) {
    return { kind: "unavailable", reason: "config", message: NOT_ENABLED_COPY, detail: e instanceof Error ? e.message : String(e) };
  }
  let res: RpcResponse;
  try {
    res = await c.rpc(fn, args);
  } catch (e) {
    return commandTransportFailure(e);
  }
  if (res.error) return mapCommandError(res.error, res.status);
  if (!isReceipt(res.data)) return { kind: "refused", code: "unknown", message: NO_RECEIPT_COPY, detail: "no receipt in the response" };
  return { kind: "ok", result: res.data };
}
