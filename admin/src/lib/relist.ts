/**
 * listing_relist contract with migration 158 (ops.execute_action + ops.action_dispatch):
 * the console states the listing version the operator saw and the server compares it
 * under the listing row lock. Pure (no server-only) so the page, ConfirmForm's outcome
 * view and the unit tests share one definition.
 *
 * Before 158 the server ignores expected for listing_relist (it is stored and audited
 * only), so sending these keys is harmless on the current production server.
 */
import { isRecord, type ActionOutcome, type JsonRecord } from "@/lib/types";

/** The listing fields 158 compares (and returns as result.before / result.current), in contract order. */
export const RELIST_FIELDS = ["status", "auction_status", "ends_at", "ended_at", "updated_at"] as const;
export type RelistField = (typeof RELIST_FIELDS)[number];

export type RelistExpected = {
  status: "active";
  auction_status: "cancelled";
  ends_at: string | null;
  ended_at: string | null;
  updated_at: string;
};

/** 158's stale_state message, byte for byte. */
export const RELIST_STALE_MESSAGE = "listing changed since you loaded it — reload and try again";

function stringOrNull(v: unknown): v is string | null {
  return typeof v === "string" || v === null;
}

/**
 * p_expected for listing_relist, copied from the raw ops.listing_detail(id).listing record
 * (to_jsonb of the row). Values are COPIED, never parsed or reformatted: a Date /
 * toISOString round trip truncates updated_at's microseconds and 158 answers stale_state.
 * JSON null stays null (SQL NULL).
 *
 * null means "render no relist form": the listing is not status 'active' with auction
 * 'cancelled', or its version (updated_at as a string; ends_at / ended_at as a string or
 * null) was not returned, so the console cannot state exactly what the operator saw.
 */
export function relistExpected(listing: unknown): RelistExpected | null {
  if (!isRecord(listing)) return null;
  const { status, auction_status, ends_at, ended_at, updated_at } = listing;
  if (status !== "active" || auction_status !== "cancelled" || typeof updated_at !== "string") return null;
  if (!stringOrNull(ends_at) || !stringOrNull(ended_at)) return null;
  return { status, auction_status, ends_at, ended_at, updated_at };
}

export type RelistFieldRow = { key: RelistField; value: string | null };

/** A server-locked row's five fields (result.before / result.current), raw, in contract order. */
export function relistFieldRows(v: unknown): RelistFieldRow[] | null {
  if (!isRecord(v)) return null;
  return RELIST_FIELDS.map((key) => ({ key, value: typeof v[key] === "string" ? (v[key] as string) : null }));
}

export type RelistOutcomeDetail =
  | { kind: "succeeded"; relisted: JsonRecord | null; before: RelistFieldRow[] | null }
  | { kind: "stale"; current: RelistFieldRow[] | null };

/**
 * What a listing_relist answer adds (ops.action_run puts the dispatch answer in `result`):
 * succeeded → result.result (admin_relist_listing's answer) + result.before (158 only);
 * rejected/stale_state → result.current. Everything else renders as for any action.
 */
export function relistOutcomeDetail(outcome: ActionOutcome): RelistOutcomeDetail | null {
  const result = isRecord(outcome.raw.result) ? outcome.raw.result : null;
  if (outcome.status === "succeeded") {
    return { kind: "succeeded", relisted: result && isRecord(result.result) ? result.result : null, before: relistFieldRows(result?.before) };
  }
  if (outcome.status === "rejected" && outcome.reason === "stale_state") {
    return { kind: "stale", current: relistFieldRows(result?.current) };
  }
  return null;
}
