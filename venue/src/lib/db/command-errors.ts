/**
 * Command results and the refusal → plain-copy map for the venue_cmd server actions (S1, DARK).
 *
 * What arrives here:
 *   - venue_cmd.* are SECURITY INVOKER wrappers (provisional migration 161) over the venue.* definer
 *     functions. Authority, preconditions and audit live in those bodies. A refusal reaches the dashboard
 *     as a PostgREST error whose `code` is the SQLSTATE the body raised with (42501, P0002, or PostgreSQL's
 *     default P0001 for a bare `raise exception`) and whose `message` is the body's literal.
 *   - The literals are enumerated from 081:175 (create_ticket_type), 081:246 (set_ticket_type_price) and
 *     081:408 (set_batch_capacity); the provisional 160 setters reuse the same ones. A literal nobody
 *     mapped is `unknown`: still a refusal, with the raw code and message kept for the log and off the
 *     screen.
 *   - PGRST106 / PGRST202 mean the schema or function is not exposed — today's dark state.
 *
 * Nothing in this file can produce a success. An action is `ok` only when the server handed back a receipt.
 */

export type CommandErrorCode =
  | "not_allowed" // 42501 — not signed in, or the role has no authority at this venue
  | "auth" // PGRST301 / PGRST302 / HTTP 401 — no or expired session
  | "not_found" // P0002 — unknown id, or one the caller may not see (the server answers both alike)
  | "event_terminal" // precondition_failed: event_terminal
  | "below_committed" // precondition_failed: below_committed (C27 refusal floor)
  | "shard_distribution" // precondition_failed: shard_distribution_unsatisfiable
  | "duplicate_name" // precondition_failed: duplicate_name (unique (event_id, name))
  | "command_key_required" // precondition_failed: command key required
  | "reason_required" // precondition_failed: reason_required
  | "invalid_input" // invalid_input: …, bad_price, bad_capacity — and this module's own pre-call checks
  | "transport" // the request never completed; the same command key makes a resend safe
  | "unknown";

export type CommandUnavailableReason =
  | "fixtures_mode" // the app is not in database mode
  | "gate_unset" // VENUE_COMMANDS_ENABLED is not exactly "true" (the default, everywhere, today)
  | "not_exposed" // PGRST106 / PGRST202 — venue_cmd is not in the project's exposed schemas
  | "config"; // the client could not be built, or the venue_cmd objects do not exist

export type CommandOk<T> = { kind: "ok"; result: T };
export type CommandRefused = {
  kind: "refused";
  code: CommandErrorCode;
  /** Plain words for the operator. Never a schema, function or SQLSTATE. */
  message: string;
  /** The form field at fault, for pre-call validation failures. */
  field?: string;
  /** The raw SQLSTATE / PostgREST code, for the log. Never rendered. */
  sqlstate?: string;
  /** The raw server message, for the log. Never rendered. */
  detail?: string;
};
export type CommandUnavailable = { kind: "unavailable"; reason: CommandUnavailableReason; message: string; sqlstate?: string; detail?: string };
export type CommandFailure = CommandRefused | CommandUnavailable;
export type CommandResult<T> = CommandOk<T> | CommandFailure;

/** The dark state, in the words the operator reads. */
export const NOT_ENABLED_COPY = "Commands are not enabled for this project. Tiers and inventory are read-only here for now.";
/** The objects are missing (schema or function does not exist): the transport migration is not applied. */
export const NOT_INSTALLED_COPY = "Commands are not installed on this project yet. Tiers and inventory are read-only here for now.";
/** The server answered without a receipt and without an error: the outcome is not known, so it is not claimed. */
export const NO_RECEIPT_COPY = "The database didn't confirm the change. Reload to see the current state before trying again.";

export const COMMAND_COPY: Record<CommandErrorCode, string> = {
  not_allowed: "Your role can't make this change. It needs a venue manager, org owner or org admin.",
  auth: "Your sign-in has expired. Sign in again, then retry.",
  not_found: "That item isn't there, or isn't yours to change.",
  event_terminal: "This event is completed or cancelled, so its tiers and inventory can't change.",
  below_committed: "Capacity can't go below the seats already held or sold.",
  shard_distribution: "Capacity can't be reduced that far: the seats are already held or sold across its sections.",
  duplicate_name: "A tier with that name already exists for this event.",
  command_key_required: "This form lost its command key. Reload the page and try again.",
  reason_required: "Give a reason for this change.",
  invalid_input: "Check the highlighted fields and try again.",
  // Deliberately no "nothing was changed": the request may have landed and only the answer been lost.
  // The command key is re-sent unchanged, so the server replays it as a no-op.
  transport: "Couldn't reach the database. Try again — the same request is safe to resend.",
  unknown: "The change was refused for a reason this dashboard doesn't recognise, and nothing was changed.",
};

type PgError = { code?: string | null; message?: string | null; details?: string | null; hint?: string | null };

/** Message literals the 081 / 160 bodies raise with the default SQLSTATE (P0001); most specific first. */
const LITERALS: ReadonlyArray<readonly [needle: string, code: CommandErrorCode]> = [
  ["precondition_failed: event_terminal", "event_terminal"],
  ["below_committed", "below_committed"],
  ["shard_distribution_unsatisfiable", "shard_distribution"],
  ["duplicate_name", "duplicate_name"],
  ["command key required", "command_key_required"],
  ["reason_required", "reason_required"],
  ["bad_price", "invalid_input"],
  ["bad_capacity", "invalid_input"],
  ["invalid_input:", "invalid_input"],
];

/**
 * Maps a PostgREST / PostgreSQL error from a venue_cmd call to a typed failure. Codes first, then the
 * body literals, then transport, then unknown. There is no branch that returns `ok`.
 */
export function mapCommandError(e: PgError | null | undefined, status?: number): CommandFailure {
  const sqlstate = e?.code ?? undefined;
  const detail = e?.message ?? undefined;
  const message = e?.message ?? "";
  const refused = (code: CommandErrorCode): CommandRefused => ({ kind: "refused", code, message: COMMAND_COPY[code], sqlstate, detail });
  const unavailable = (reason: CommandUnavailableReason, copy: string): CommandUnavailable => ({ kind: "unavailable", reason, message: copy, sqlstate, detail });

  if (sqlstate === "PGRST106" || sqlstate === "PGRST202") return unavailable("not_exposed", NOT_ENABLED_COPY);
  if (sqlstate === "42P01" || sqlstate === "42883" || sqlstate === "3F000") return unavailable("config", NOT_INSTALLED_COPY);
  if (sqlstate === "PGRST301" || sqlstate === "PGRST302" || status === 401) return refused("auth");
  if (sqlstate === "42501") return refused("not_allowed");
  if (sqlstate === "P0002") return refused("not_found");
  for (const [needle, code] of LITERALS) if (message.includes(needle)) return refused(code);
  // postgrest-js reports a failed fetch as an error with an empty code and the thrown message.
  if (!sqlstate && /fetch failed|ECONNREFUSED|ECONNRESET|ENOTFOUND|network|TypeError/i.test(message)) return refused("transport");
  return refused("unknown");
}

/** The client threw (fetch rejected, aborted, …): the request did not complete. */
export function commandTransportFailure(e: unknown): CommandRefused {
  return { kind: "refused", code: "transport", message: COMMAND_COPY.transport, detail: e instanceof Error ? e.message : String(e) };
}

/** A pre-call validation failure: the field at fault and a sentence for it. Nothing was sent. */
export function invalidInput(field: string, message: string): CommandRefused {
  return { kind: "refused", code: "invalid_input", field, message };
}
