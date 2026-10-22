"use server";

import "server-only";

import { COMMAND_COPY, commandTransportFailure, invalidInput, mapCommandError, NO_RECEIPT_COPY, NOT_ENABLED_COPY, type CommandRefused, type CommandResult, type CommandUnavailable } from "@/lib/db/command-errors";
import { DATA_SOURCE } from "@/lib/env";
import { isUuid } from "@/lib/page";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { TicketKind, Visibility } from "@/lib/types";

/**
 * Server actions for slice S1 (tiers + inventory), DARK.
 *
 * Every action answers `unavailable` unless BOTH hold:
 *   - the app is in database mode (lib/env.ts DATA_SOURCE, from NEXT_PUBLIC_VENUE_DATA_SOURCE), and
 *   - the server-only VENUE_COMMANDS_ENABLED is exactly "true" (never NEXT_PUBLIC_; unset by default).
 * Nothing sets it today, so in every environment every action is unavailable and the client is never built.
 * F flips preview.ts writesEnabled only after the owner exposes venue_cmd; this gate is the second lock.
 *
 * Transport: createSupabaseServerClient() (anon key + the caller's session cookie; no privileged client
 * exists in this app) .schema("venue_cmd").rpc(name, args). venue_cmd.* are SECURITY INVOKER wrappers
 * (provisional migration 161) with the same arguments as the venue.* definer bodies, which hold the
 * authority check, the preconditions and the audit row. The dashboard adds nothing and bypasses nothing.
 *
 * Inputs are validated here before any call so a malformed form never reaches the database, but the
 * server re-checks everything; a refusal from it is mapped by command-errors.ts and never read as success.
 *
 * RPC contract coded against (names and parameter names are the server's, verbatim):
 *   create_ticket_type(p_event_id uuid, p_kind text, p_name text, p_price_minor integer, p_visibility text, p_command_key text) → jsonb   (081:175)
 *   set_ticket_type_price(p_ticket_type_id uuid, p_price_minor integer, p_reason_code text, p_command_key text) → jsonb                 (081:246)
 *   set_ticket_type_visibility(p_ticket_type_id uuid, p_visibility text, p_reason_code text, p_command_key text) → jsonb                (160, provisional)
 *   set_ticket_type_rank(p_ticket_type_id uuid, p_display_rank smallint, p_command_key text) → jsonb                                   (160, provisional)
 *   set_batch_capacity(p_batch_id uuid, p_new_capacity integer, p_reason_code text, p_command_key text) → jsonb                         (081:408)
 */
const SCHEMA = "venue_cmd";

/** The jsonb a definer body returns: `status` is "ok", or "noop_replay" / "noop" when the value or command key was already applied. */
export type CommandReceipt = { status: string } & Record<string, unknown>;

export type CreateTicketTypeInput = { eventId: string; kind: TicketKind; name: string; priceMinor: number; visibility: Visibility; commandKey: string };
export type SetTicketTypePriceInput = { ticketTypeId: string; priceMinor: number; reasonCode: string; commandKey: string };
export type SetTicketTypeVisibilityInput = { ticketTypeId: string; visibility: Visibility; reasonCode: string; commandKey: string };
export type SetTicketTypeRankInput = { ticketTypeId: string; displayRank: number; commandKey: string };
export type SetBatchCapacityInput = { batchId: string; newCapacity: number; reasonCode: string; commandKey: string };

/**
 * One key per form render, minted by the caller and RE-SENT UNCHANGED on every retry of that form. The
 * server treats a replayed key as a no-op (081 p_command_key), which is what makes "try again" after a lost
 * answer safe. Async because a "use server" file may only export async functions.
 */
export async function mintCommandKey(): Promise<string> {
  return crypto.randomUUID();
}

export async function createTicketTypeAction(input: CreateTicketTypeInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const i = (input ?? {}) as Partial<CreateTicketTypeInput>;
  const bad = firstProblem(
    needUuid(i.eventId, "eventId"),
    needOneOf(i.kind, KINDS, "kind", "Choose admission or table."),
    needText(i.name, "name", "Give the tier a name."),
    needCents(i.priceMinor, "priceMinor"),
    needOneOf(i.visibility, VISIBILITIES, "visibility", "Choose hidden, public or door only."),
    needKey(i.commandKey),
  );
  if (bad) return bad;
  const v = i as CreateTicketTypeInput;
  return send("create_ticket_type", { p_event_id: v.eventId, p_kind: v.kind, p_name: v.name.trim(), p_price_minor: v.priceMinor, p_visibility: v.visibility, p_command_key: v.commandKey });
}

export async function setTicketTypePriceAction(input: SetTicketTypePriceInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const i = (input ?? {}) as Partial<SetTicketTypePriceInput>;
  const bad = firstProblem(needUuid(i.ticketTypeId, "ticketTypeId"), needCents(i.priceMinor, "priceMinor"), needReason(i.reasonCode), needKey(i.commandKey));
  if (bad) return bad;
  const v = i as SetTicketTypePriceInput;
  return send("set_ticket_type_price", { p_ticket_type_id: v.ticketTypeId, p_price_minor: v.priceMinor, p_reason_code: v.reasonCode, p_command_key: v.commandKey });
}

export async function setTicketTypeVisibilityAction(input: SetTicketTypeVisibilityInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const i = (input ?? {}) as Partial<SetTicketTypeVisibilityInput>;
  const bad = firstProblem(needUuid(i.ticketTypeId, "ticketTypeId"), needOneOf(i.visibility, VISIBILITIES, "visibility", "Choose hidden, public or door only."), needReason(i.reasonCode), needKey(i.commandKey));
  if (bad) return bad;
  const v = i as SetTicketTypeVisibilityInput;
  return send("set_ticket_type_visibility", { p_ticket_type_id: v.ticketTypeId, p_visibility: v.visibility, p_reason_code: v.reasonCode, p_command_key: v.commandKey });
}

export async function setTicketTypeRankAction(input: SetTicketTypeRankInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const i = (input ?? {}) as Partial<SetTicketTypeRankInput>;
  const bad = firstProblem(needUuid(i.ticketTypeId, "ticketTypeId"), needInt(i.displayRank, "displayRank", 0, 999, "Display order is a whole number from 0 to 999."), needKey(i.commandKey));
  if (bad) return bad;
  const v = i as SetTicketTypeRankInput;
  return send("set_ticket_type_rank", { p_ticket_type_id: v.ticketTypeId, p_display_rank: v.displayRank, p_command_key: v.commandKey });
}

export async function setBatchCapacityAction(input: SetBatchCapacityInput): Promise<CommandResult<CommandReceipt>> {
  const dark = gate();
  if (dark) return dark;
  const i = (input ?? {}) as Partial<SetBatchCapacityInput>;
  const bad = firstProblem(needUuid(i.batchId, "batchId"), needInt(i.newCapacity, "newCapacity", 1, INT4_MAX, "Capacity is a whole number of tickets, at least 1."), needReason(i.reasonCode), needKey(i.commandKey));
  if (bad) return bad;
  const v = i as SetBatchCapacityInput;
  return send("set_batch_capacity", { p_batch_id: v.batchId, p_new_capacity: v.newCapacity, p_reason_code: v.reasonCode, p_command_key: v.commandKey });
}

// ---------------------------------------------------------------------------------------------------------
// Module-private: the gate, the validators, the transport. (A "use server" file may only export async
// functions, so none of this is exported; tests reach it through the actions.)
// ---------------------------------------------------------------------------------------------------------

function gate(): CommandUnavailable | null {
  if (DATA_SOURCE !== "database") return { kind: "unavailable", reason: "fixtures_mode", message: NOT_ENABLED_COPY };
  if (process.env.VENUE_COMMANDS_ENABLED !== "true") return { kind: "unavailable", reason: "gate_unset", message: NOT_ENABLED_COPY };
  return null;
}

const KINDS: readonly TicketKind[] = ["admission", "table"];
const VISIBILITIES: readonly Visibility[] = ["hidden", "public", "door_only"];
/** PostgreSQL integer: the server would raise numeric_value_out_of_range past this; refuse it here instead. */
const INT4_MAX = 2_147_483_647;

function firstProblem(...checks: Array<CommandRefused | null>): CommandRefused | null {
  return checks.find((c) => c !== null) ?? null;
}
/** The id rule is lib/page.ts isUuid — the same one the route uses — so an id the route accepts, the action accepts. */
function needUuid(v: unknown, field: string): CommandRefused | null {
  return typeof v === "string" && isUuid(v) ? null : invalidInput(field, "Missing or malformed id.");
}
function needText(v: unknown, field: string, copy: string): CommandRefused | null {
  return typeof v === "string" && v.trim().length > 0 ? null : invalidInput(field, copy);
}
function needInt(v: unknown, field: string, min: number, max: number, copy: string): CommandRefused | null {
  return typeof v === "number" && Number.isInteger(v) && v >= min && v <= max ? null : invalidInput(field, copy);
}
/** Integer minor units (USD cents, spec §0.3), at least 1: the server's `price_minor > 0` check, said before the call. */
function needCents(v: unknown, field: string): CommandRefused | null {
  return needInt(v, field, 1, INT4_MAX, "Enter a whole number of cents, at least 1.");
}
function needOneOf<T extends string>(v: unknown, allowed: readonly T[], field: string, copy: string): CommandRefused | null {
  return typeof v === "string" && (allowed as readonly string[]).includes(v) ? null : invalidInput(field, copy);
}
function needReason(v: unknown): CommandRefused | null {
  return needText(v, "reasonCode", COMMAND_COPY.reason_required);
}
function needKey(v: unknown): CommandRefused | null {
  return needText(v, "commandKey", COMMAND_COPY.command_key_required);
}

type PgError = { code?: string | null; message?: string | null; details?: string | null; hint?: string | null };
type RpcResponse = { data: unknown; error: PgError | null; status?: number };
/** The two calls this module makes on the client, structurally — the generated schema types do not cover venue_cmd. */
type CmdClient = { rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse> };

function isReceipt(d: unknown): d is CommandReceipt {
  return typeof d === "object" && d !== null && !Array.isArray(d) && typeof (d as { status?: unknown }).status === "string";
}

async function send(fn: string, args: Record<string, unknown>): Promise<CommandResult<CommandReceipt>> {
  let c: CmdClient;
  try {
    c = (await createSupabaseServerClient()).schema(SCHEMA) as unknown as CmdClient;
  } catch (e) {
    // SupabaseConfigError (no URL / key, or a privileged key in the public slot) or no request scope: not a refusal, not an outcome.
    return { kind: "unavailable", reason: "config", message: NOT_ENABLED_COPY, detail: e instanceof Error ? e.message : String(e) };
  }
  let res: RpcResponse;
  try {
    res = await c.rpc(fn, args);
  } catch (e) {
    return commandTransportFailure(e);
  }
  // An error wins over any data beside it; a missing receipt is not a success either.
  if (res.error) return mapCommandError(res.error, res.status);
  if (!isReceipt(res.data)) return { kind: "refused", code: "unknown", message: NO_RECEIPT_COPY, detail: "no receipt in the response" };
  return { kind: "ok", result: res.data };
}
