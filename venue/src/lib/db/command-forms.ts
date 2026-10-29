"use server";

import "server-only";

import { revalidatePath } from "next/cache";
import type { CommandReceipt } from "@/lib/db/commands";
import { createInventoryBatchAction, createTicketTypeAction, RELEASE_KINDS, setBatchCapacityAction, setTicketTypePriceAction, setTicketTypeRankAction, setTicketTypeSaleWindowAction, setTicketTypeVisibilityAction, type ReleaseKind } from "@/lib/db/commands";
import { toOffsetInstant } from "@/lib/events/instants";
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

/** "" → null (that side is open). Otherwise a wall clock in the venue's zone, resolved to an offset instant. */
function instantOrNull(local: string, timeZone: string, field: string): { value: string | null } | { field: string; message: string } {
  if (!local.trim()) return { value: null };
  if (!timeZone.trim()) return { field, message: "This venue has no time zone set, so a date and time cannot be resolved. Set the venue time zone first." };
  const r = toOffsetInstant(local, timeZone);
  if (r.ok) return { value: r.iso };
  if (r.reason === "nonexistent") return { field, message: "That local time does not exist on that date — the clocks move forward over it. Choose another time." };
  if (r.reason === "ambiguous") return { field, message: "That local time happens twice on that date — the clocks move back over it. Choose another time." };
  if (r.reason === "unknown_zone") return { field, message: "This venue's time zone is not one this server recognises." };
  return { field, message: "Give a date and a time." };
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

/**
 * The tier's sale window. The form posts a WALL CLOCK plus the venue's zone, never an instant: the
 * organizer types "8pm", and which 8pm that is depends on the zone and the date. `toOffsetInstant` resolves
 * it to an offset-bearing string and refuses the two cases a naive conversion gets silently wrong — a time
 * that does not exist (clocks sprang forward over it) and one that happens twice (fell back). The action
 * then refuses anything without an offset anyway, so a future caller that skips this step cannot smuggle a
 * naive literal past it.
 */
export async function setTicketTypeSaleWindowForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const zone = text(fd, "timeZone");
  const ends = instantOrNull(text(fd, "saleEndsLocal"), zone, "saleEndsAt");
  if ("field" in ends) return refused(ends.field, ends.message);
  const starts = instantOrNull(text(fd, "saleStartsLocal"), zone, "saleStartsAt");
  if ("field" in starts) return refused(starts.field, starts.message);
  return done(
    fd,
    await setTicketTypeSaleWindowAction({
      ticketTypeId: text(fd, "ticketTypeId"),
      saleStartsAt: starts.value,
      saleEndsAt: ends.value,
      reasonCode: text(fd, "reasonCode"),
      commandKey: text(fd, "commandKey"),
    }),
  );
}

/**
 * The first inventory release for a tier on a session.
 *
 * **E-33: never auto-retry this one, and re-read when the outcome is uncertain.** `venue.create_inventory_batch`
 * (081:320) reads the command key only to reject a blank one and then plainly inserts, with `batch_id` defaulting
 * to a fresh uuid and only NON-unique indexes on the table. So a resend after a timeout does not replay — it
 * creates a SECOND batch with the same capacity, which releases inventory twice. The generic transport copy
 * ("the same request is safe to resend") is true of the verbs that key their idempotency and WRONG here, so this
 * form replaces it, revalidates so the next paint is the server's state, and tells the operator to look before
 * acting again.
 */
export async function createInventoryBatchForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const kindRaw = text(fd, "releaseKind");
  if (!(RELEASE_KINDS as readonly string[]).includes(kindRaw)) return refused("releaseKind", "Choose a release kind.");
  const c = capacity(text(fd, "capacity"));
  if (!c.ok) return refused(c.field, c.message);
  const result = await createInventoryBatchAction({
    ticketTypeId: text(fd, "ticketTypeId"),
    sessionId: text(fd, "sessionId"),
    releaseKind: kindRaw as ReleaseKind,
    capacity: c.value,
    commandKey: text(fd, "commandKey"),
  });
  if (result.kind === "refused" && result.code === "transport") {
    revalidate(fd); // E-33: re-read, because we do not know whether the insert landed.
    return {
      result: {
        ...result,
        message:
          "Couldn't tell whether the release was created. Do NOT send it again — a second attempt would release the inventory twice. Reload this page and check whether the release is listed; add it only if it is not.",
      },
    };
  }
  return done(fd, result);
}

export async function setBatchCapacityForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const c = capacity(text(fd, "newCapacity"));
  if (!c.ok) return refused(c.field, c.message);
  return done(fd, await setBatchCapacityAction({ batchId: text(fd, "batchId"), newCapacity: c.value, reasonCode: text(fd, "reasonCode"), commandKey: text(fd, "commandKey") }));
}
