import type { TicketKind, Visibility } from "@/lib/types";

/**
 * FormData → the typed inputs of D's S1 actions (lib/db/commands.ts). Pure, so the rules are unit tests:
 * dollars become integer cents (the server's unit, spec §0.3), ranks and capacities become integers,
 * and anything else is a named field problem BEFORE any call. Nothing here is a success or a receipt.
 */
export type ParsedField<T> = { ok: true; value: T } | { ok: false; field: string; message: string };

export function text(fd: FormData, field: string): string {
  const v = fd.get(field);
  return typeof v === "string" ? v.trim() : "";
}

/** "25", "25.00", "0.50" → 2500, 2500, 50. Refuses negatives, zero, more than two decimals, and non-numbers. */
export function dollarsToCents(raw: string, field = "price"): ParsedField<number> {
  const s = raw.trim().replace(/^\$/, "").replace(/,/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return { ok: false, field, message: "Enter a price in dollars with at most two decimals, for example 25.00." };
  const [whole, frac = ""] = s.split(".");
  const cents = Number(whole) * 100 + Number((frac + "00").slice(0, 2));
  if (!Number.isSafeInteger(cents) || cents < 1) return { ok: false, field, message: "The price must be at least $0.01." };
  return { ok: true, value: cents };
}

export function integer(raw: string, field: string, min: number, max: number, copy: string): ParsedField<number> {
  if (!/^-?\d+$/.test(raw.trim())) return { ok: false, field, message: copy };
  const n = Number(raw.trim());
  return n >= min && n <= max ? { ok: true, value: n } : { ok: false, field, message: copy };
}

const KINDS: readonly TicketKind[] = ["admission", "table"];
const VISIBILITIES: readonly Visibility[] = ["hidden", "public", "door_only"];

export function kind(raw: string): ParsedField<TicketKind> {
  return (KINDS as readonly string[]).includes(raw) ? { ok: true, value: raw as TicketKind } : { ok: false, field: "kind", message: "Choose admission or table." };
}
export function visibility(raw: string): ParsedField<Visibility> {
  return (VISIBILITIES as readonly string[]).includes(raw) ? { ok: true, value: raw as Visibility } : { ok: false, field: "visibility", message: "Choose hidden, public or door only." };
}
/** `display_rank smallint`, 0–999, or empty = unranked (NULL is not sent by this slice; empty is refused with a reason). */
export function rank(raw: string): ParsedField<number> {
  return integer(raw, "displayRank", 0, 999, "Enter a rank from 0 (first) to 999.");
}
export function capacity(raw: string): ParsedField<number> {
  return integer(raw, "newCapacity", 0, 2_147_483_647, "Enter a whole number of tickets, 0 or more.");
}
