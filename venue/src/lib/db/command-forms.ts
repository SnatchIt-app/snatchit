"use server";

import "server-only";

import { revalidatePath } from "next/cache";
import type { CommandReceipt } from "@/lib/db/commands";
import { createTicketTypeAction, setBatchCapacityAction, setTicketTypePriceAction, setTicketTypeRankAction, setTicketTypeVisibilityAction } from "@/lib/db/commands";
import type { CommandResult } from "@/lib/db/command-errors";
import { capacity, dollarsToCents, kind, rank, text, visibility, type ParsedField } from "@/lib/db/command-form-parse";
import { isUuid } from "@/lib/page";

/**
 * The `useActionState` face of D's S1 actions: one FormData in, one CommandResult out, for the tier and
 * capacity forms on the Tickets page. The command key is minted by the page when it renders the form and
 * travels as a hidden field, so a retry of the same form re-sends the same key (the server replays it as
 * a no-op). On `ok` the page is revalidated so the next paint is the server's state, not the form's.
 * Nothing here can succeed without D's action returning a receipt.
 */
export type CommandFormState = { result: CommandResult<CommandReceipt> | null };

const refused = (field: string, message: string): CommandFormState => ({ result: { kind: "refused", code: "invalid_input", message, field } });

function bad<T>(p: ParsedField<T>): CommandFormState | null {
  return p.ok ? null : refused(p.field, p.message);
}

/** The page to re-read after a change: only a path made of uuids the route already accepted. */
function revalidate(fd: FormData) {
  const org = text(fd, "orgId"), venue = text(fd, "venueId"), event = text(fd, "eventId");
  if ([org, venue, event].every(isUuid)) {
    revalidatePath(`/o/${org}/v/${venue}/events/${event}/inventory`);
    revalidatePath(`/o/${org}/v/${venue}/events/${event}`);
  }
}

function done(fd: FormData, result: CommandResult<CommandReceipt>): CommandFormState {
  if (result.kind === "ok") revalidate(fd);
  return { result };
}

export async function createTicketTypeForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const k = kind(text(fd, "kind")), price = dollarsToCents(text(fd, "price")), vis = visibility(text(fd, "visibility"));
  const name = text(fd, "name");
  if (!name) return refused("name", "Give the ticket type a name (unique within the event).");
  const problem = bad(k) ?? bad(price) ?? bad(vis);
  if (problem) return problem;
  if (!k.ok || !price.ok || !vis.ok) return refused("kind", "Invalid input.");
  return done(fd, await createTicketTypeAction({ eventId: text(fd, "eventId"), kind: k.value, name, priceMinor: price.value, visibility: vis.value, commandKey: text(fd, "commandKey") }));
}

export async function setTicketTypePriceForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const price = dollarsToCents(text(fd, "price"));
  if (!price.ok) return refused(price.field, price.message);
  return done(fd, await setTicketTypePriceAction({ ticketTypeId: text(fd, "ticketTypeId"), priceMinor: price.value, reasonCode: text(fd, "reasonCode"), commandKey: text(fd, "commandKey") }));
}

export async function setTicketTypeVisibilityForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const vis = visibility(text(fd, "visibility"));
  if (!vis.ok) return refused(vis.field, vis.message);
  return done(fd, await setTicketTypeVisibilityAction({ ticketTypeId: text(fd, "ticketTypeId"), visibility: vis.value, reasonCode: text(fd, "reasonCode"), commandKey: text(fd, "commandKey") }));
}

export async function setTicketTypeRankForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const r = rank(text(fd, "displayRank"));
  if (!r.ok) return refused(r.field, r.message);
  return done(fd, await setTicketTypeRankAction({ ticketTypeId: text(fd, "ticketTypeId"), displayRank: r.value, commandKey: text(fd, "commandKey") }));
}

export async function setBatchCapacityForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const c = capacity(text(fd, "newCapacity"));
  if (!c.ok) return refused(c.field, c.message);
  return done(fd, await setBatchCapacityAction({ batchId: text(fd, "batchId"), newCapacity: c.value, reasonCode: text(fd, "reasonCode"), commandKey: text(fd, "commandKey") }));
}
