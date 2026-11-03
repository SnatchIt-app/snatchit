"use server";

import "server-only";

import { revalidatePath } from "next/cache";
import type { CommandResult } from "@/lib/db/command-errors";
import {
  cancelEventAction,
  createEventAction,
  createEventSessionAction,
  publishEventAction,
  setSessionSalesCapacityAction,
  setVenueTimezoneAction,
  updateEventAction,
  updateEventSessionAction,
  updateVenueAction,
  type CommandReceipt,
} from "@/lib/db/event-commands";
import { buildEventPatch, buildSalesCapacity, buildSessionPayload, buildVenuePatch, PUBLISH_TARGETS, refusalCopy, type EventStatusName, type FieldProblem } from "@/lib/events/command-contract";
import { isUuid } from "@/lib/page";

/**
 * The `useActionState` face of the event/session/venue commands: one FormData
 * in, one result out. The pure layer builds and refuses payloads; these only
 * carry ids, mint nothing, and revalidate the pages a receipt changes.
 *
 * The command key travels as a hidden field minted when the form rendered, so
 * pressing "try again" on the same form re-sends the SAME key and the server
 * replays it as a no-op instead of making a second event.
 */
export type CommandFormState = { result: CommandResult<CommandReceipt> | null; problems?: FieldProblem[]; refusal?: string };

const refuse = (problems: FieldProblem[]): CommandFormState => ({ result: null, problems });

function text(fd: FormData, field: string): string {
  const v = fd.get(field);
  return typeof v === "string" ? v.trim() : "";
}
function optional(fd: FormData, field: string): string | undefined {
  const v = fd.get(field);
  return typeof v === "string" ? v : undefined;
}

/** Revalidate only paths built from ids the route itself would accept. */
function revalidate(fd: FormData) {
  const org = text(fd, "orgId");
  const venue = text(fd, "venueId");
  const event = text(fd, "eventId");
  if (![org, venue].every(isUuid)) return;
  const base = `/o/${org}/v/${venue}`;
  revalidatePath(base);
  revalidatePath(`${base}/events`);
  if (isUuid(event)) {
    revalidatePath(`${base}/events/${event}`);
    revalidatePath(`${base}/events/${event}/inventory`);
  }
}

/** A receipt revalidates; a refusal is passed through with the server's reason in the operator's words. */
function done(fd: FormData, result: CommandResult<CommandReceipt>): CommandFormState {
  if (result.kind === "ok") {
    revalidate(fd);
    return { result };
  }
  if (result.kind === "refused") return { result, refusal: refusalCopy(result.detail ?? result.message) };
  return { result };
}

export async function createEventForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const timeZone = text(fd, "timeZone");
  const session = buildSessionPayload(
    { label: optional(fd, "session_label"), startsLocal: text(fd, "starts_local"), endsLocal: optional(fd, "ends_local"), doorsLocal: optional(fd, "doors_local") },
    timeZone,
  );
  const title = text(fd, "title");
  const problems: FieldProblem[] = [];
  if (!title) problems.push({ field: "title", message: "An event needs a title." });
  if (!session.ok) problems.push(...session.problems);
  if (problems.length > 0) return refuse(problems);
  if (!session.ok) return refuse(problems);
  return done(fd, await createEventAction({ venueId: text(fd, "venueId"), title, firstSession: session.value, commandKey: text(fd, "commandKey") }));
}

export async function updateEventForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const patch = buildEventPatch(
    {
      title: optional(fd, "title"),
      description: optional(fd, "description"),
      category: optional(fd, "category"),
      genreTags: optional(fd, "genre_tags")?.split(",") ?? undefined,
      reasonCode: optional(fd, "reason_code"),
    },
    { status: (text(fd, "status") || "draft") as EventStatusName, currentTitle: optional(fd, "current_title") },
  );
  if (!patch.ok) return refuse(patch.problems);
  return done(fd, await updateEventAction({ eventId: text(fd, "eventId"), patch: patch.value, commandKey: text(fd, "commandKey") }));
}

export async function createSessionForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const session = buildSessionPayload(
    { label: optional(fd, "session_label"), startsLocal: text(fd, "starts_local"), endsLocal: optional(fd, "ends_local"), doorsLocal: optional(fd, "doors_local") },
    text(fd, "timeZone"),
  );
  if (!session.ok) return refuse(session.problems);
  return done(fd, await createEventSessionAction({ eventId: text(fd, "eventId"), session: session.value, commandKey: text(fd, "commandKey") }));
}

export async function updateSessionForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const built = buildSessionPayload(
    {
      label: optional(fd, "session_label"),
      startsLocal: text(fd, "starts_local"),
      endsLocal: optional(fd, "ends_local"),
      doorsLocal: optional(fd, "doors_local"),
      reasonCode: optional(fd, "reason_code"),
    },
    text(fd, "timeZone"),
  );
  if (!built.ok) return refuse(built.problems);
  return done(fd, await updateEventSessionAction({ sessionId: text(fd, "sessionId"), patch: built.value, commandKey: text(fd, "commandKey") }));
}

export async function publishEventForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const target = text(fd, "target_status");
  if (!(PUBLISH_TARGETS as readonly string[]).includes(target)) return refuse([{ field: "target_status", message: "An event moves to announced, on sale, live or completed." }]);
  return done(fd, await publishEventAction({ eventId: text(fd, "eventId"), targetStatus: target, commandKey: text(fd, "commandKey") }));
}

export async function cancelEventForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const reason = text(fd, "reason_code");
  if (!reason) return refuse([{ field: "reason_code", message: "Cancelling needs a reason; it is recorded." }]);
  // A typed confirmation, because cancelling voids tickets and refunds orders.
  if (text(fd, "confirm").toLowerCase() !== "cancel") return refuse([{ field: "confirm", message: 'Type "cancel" to confirm.' }]);
  return done(fd, await cancelEventAction({ eventId: text(fd, "eventId"), reasonCode: reason, commandKey: text(fd, "commandKey") }));
}

export async function updateVenueForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const patch = buildVenuePatch({
    name: optional(fd, "name"),
    neighborhood: optional(fd, "neighborhood"),
    address: optional(fd, "address"),
    capacityHint: optional(fd, "capacity_hint"),
    reasonCode: optional(fd, "reason_code"),
  });
  if (!patch.ok) return refuse(patch.problems);
  return done(fd, await updateVenueAction({ venueId: text(fd, "venueId"), patch: patch.value, commandKey: text(fd, "commandKey") }));
}

export async function setVenueTimezoneForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const tz = text(fd, "timezone");
  const reason = text(fd, "reason_code");
  const problems: FieldProblem[] = [];
  if (!tz) problems.push({ field: "timezone", message: "Choose the venue's time zone." });
  if (!reason) problems.push({ field: "reason_code", message: "A reason is required; it is recorded." });
  if (problems.length > 0) return refuse(problems);
  return done(fd, await setVenueTimezoneAction({ venueId: text(fd, "venueId"), timezone: tz, reasonCode: reason, commandKey: text(fd, "commandKey") }));
}

export async function setSessionCapacityForm(_prev: CommandFormState, fd: FormData): Promise<CommandFormState> {
  const built = buildSalesCapacity(text(fd, "capacity"), text(fd, "reason_code"));
  if (!built.ok) return refuse(built.problems);
  return done(fd, await setSessionSalesCapacityAction({ sessionId: text(fd, "sessionId"), capacity: built.value.capacity, reasonCode: built.value.reasonCode, commandKey: text(fd, "commandKey") }));
}
