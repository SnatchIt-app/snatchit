"use client";

import { CommandForm, Field, Select, type CommandIds } from "@/components/commands/CommandForm";
import { cancelEventForm, createEventForm, createSessionForm, publishEventForm, setSessionCapacityForm, updateEventForm, updateSessionForm } from "@/lib/events/forms";
import { PUBLISH_TARGETS, type EventStatusName } from "@/lib/events/command-contract";

/**
 * The organizer's event commands (readiness row 2), rendered only when the
 * command gate is open and the role may edit. Every time field is a local wall
 * clock; the server action converts it with the venue's zone into an
 * offset-qualified instant, so what the operator types is what the door sees.
 */
const STATUS_WORD: Record<string, string> = { announced: "Announced", on_sale: "On sale", live: "Live", completed: "Completed" };

export function TimeFields({ timeZone, defaults }: { timeZone: string; defaults?: { starts?: string; ends?: string; doors?: string; label?: string } }) {
  return (
    <>
      <input type="hidden" name="timeZone" value={timeZone} />
      <Field label="Name for this night (optional)" name="session_label" defaultValue={defaults?.label ?? ""} placeholder="Doors" maxLength={120} />
      <Field label="Starts" name="starts_local" type="datetime-local" required defaultValue={defaults?.starts ?? ""} hint={`Entered in the ${timeZone} time zone.`} />
      <Field label="Doors open (optional)" name="doors_local" type="datetime-local" defaultValue={defaults?.doors ?? ""} />
      <Field label="Ends (optional)" name="ends_local" type="datetime-local" defaultValue={defaults?.ends ?? ""} />
    </>
  );
}

export function CreateEventForm({ ids, commandKey, timeZone }: { ids: CommandIds; commandKey: string; timeZone: string }) {
  return (
    <section className="panel px-5 py-5" aria-labelledby="create-event">
      <h2 id="create-event" className="text-base font-semibold text-ink">Create an event</h2>
      <p className="mt-1 text-sm text-dim">It starts as a draft. Buyers cannot see a draft, and it sells nothing. If no answer comes back, check the events list before you send it again. Each send creates a new draft.</p>
      <div className="mt-4">
        <CommandForm action={createEventForm} ids={ids} commandKey={commandKey} submitLabel="Create the draft" busyLabel="Creating…">
          <Field label="Title" name="title" required maxLength={200} placeholder="Snatch It pop-up" />
          <TimeFields timeZone={timeZone} />
        </CommandForm>
      </div>
    </section>
  );
}

export function EventDetailsForm({ ids, commandKey, status, currentTitle, description, category, genreTags }: { ids: CommandIds; commandKey: string; status: EventStatusName; currentTitle: string; description?: string | null; category?: string | null; genreTags?: string[] }) {
  const needsReason = status !== "draft";
  return (
    <CommandForm action={updateEventForm} ids={ids} commandKey={commandKey} extra={{ status, current_title: currentTitle }} submitLabel="Save the details" busyLabel="Saving…">
      <Field label="Title" name="title" defaultValue={currentTitle} maxLength={200} hint={needsReason ? "Changing the title now needs a reason, which is recorded." : undefined} />
      <Field label="Description" name="description" defaultValue={description ?? ""} maxLength={2000} hint="This form does not show the saved description, category or genres. Saving sets all three from these boxes. An empty box clears what was saved." />
      <Field label="Category" name="category" defaultValue={category ?? ""} maxLength={60} />
      <Field label="Genres" name="genre_tags" defaultValue={(genreTags ?? []).join(", ")} hint="Separate with commas." />
      {needsReason ? <Field label="Reason for this change" name="reason_code" placeholder="renamed_for_promo" maxLength={80} /> : null}
    </CommandForm>
  );
}

export function PublishEventForm({ ids, commandKey, target }: { ids: CommandIds; commandKey: string; target: (typeof PUBLISH_TARGETS)[number] }) {
  return (
    <CommandForm action={publishEventForm} ids={ids} commandKey={commandKey} extra={{ target_status: target }} submitLabel={`Move to ${STATUS_WORD[target] ?? target}`} busyLabel="Moving…">
      <p className="text-sm text-muted">
        {target === "on_sale"
          ? "Before the event can go on sale, the server checks for a ticket type with a release, an organization cleared to sell, a payout account Stripe has confirmed, ticket signing turned on, and the Snatch It fee set. If one is missing, the server names the first one it finds."
          : "An event moves forward one step at a time, and never backwards."}
      </p>
    </CommandForm>
  );
}

export function CancelEventForm({ ids, commandKey }: { ids: CommandIds; commandKey: string }) {
  return (
    <CommandForm action={cancelEventForm} ids={ids} commandKey={commandKey} submitLabel="Cancel this event" busyLabel="Cancelling…" destructive>
      <p className="text-sm text-muted">Cancelling voids the paid tickets for this event and creates refunds for them. It also cancels open resale listings and transfers. It is recorded and cannot be undone here. Nothing is deleted.</p>
      <Field label="Reason" name="reason_code" required placeholder="venue_lost" maxLength={80} />
      <Field label='Type "cancel" to confirm' name="confirm" required autoComplete="off" />
    </CommandForm>
  );
}

export function SessionForm({ ids, commandKey, timeZone, session }: { ids: CommandIds; commandKey: string; timeZone: string; session?: { sessionId: string; label?: string | null; startsLocal?: string; endsLocal?: string; doorsLocal?: string } }) {
  const editing = !!session;
  return (
    <CommandForm
      action={editing ? updateSessionForm : createSessionForm}
      ids={ids}
      commandKey={commandKey}
      extra={editing ? { sessionId: session.sessionId } : undefined}
      submitLabel={editing ? "Save this night" : "Add a night"}
      busyLabel="Saving…"
    >
      <TimeFields timeZone={timeZone} defaults={editing ? { label: session.label ?? "", starts: session.startsLocal, ends: session.endsLocal, doors: session.doorsLocal } : undefined} />
      {editing ? <Field label="Reason (needed once tickets exist)" name="reason_code" placeholder="moved_later" maxLength={80} /> : null}
    </CommandForm>
  );
}

export function SessionCapacityForm({
  ids,
  commandKey,
  sessionId,
  capacity,
  allocated,
  capacityHint,
  remainingToAllocate,
}: {
  ids: CommandIds;
  commandKey: string;
  sessionId: string;
  capacity?: number | null;
  allocated?: number | null;
  capacityHint?: number | null;
  remainingToAllocate?: number | null;
}) {
  const known = typeof allocated === "number";
  const unlimited = known && capacity === null;
  return (
    <CommandForm action={setSessionCapacityForm} ids={ids} commandKey={commandKey} extra={{ sessionId }} submitLabel="Set the pool" busyLabel="Setting…">
      <Field
        label="Tickets this night may sell"
        name="capacity"
        type="number"
        min={1}
        step={1}
        defaultValue={typeof capacity === "number" ? String(capacity) : ""}
        hint={
          known
            ? [
                unlimited ? "No limit set: this night may sell as much as its releases hold." : `Pool now: ${capacity}.`,
                `Already allocated to releases: ${allocated}${typeof remainingToAllocate === "number" ? ` · ${remainingToAllocate} left to allocate` : ""}.`,
                typeof capacityHint === "number" ? `Venue capacity ${capacityHint}.` : null,
                "Leave empty for unlimited.",
              ]
                .filter(Boolean)
                .join(" ")
            : "Leave empty for unlimited. The current numbers could not be read. The server refuses a pool below what is already allocated to releases, or above the venue's capacity."
        }
      />
      <Field label="Reason" name="reason_code" required placeholder="opening_pool" maxLength={80} />
    </CommandForm>
  );
}

export function NeighborhoodSelect({ value, options }: { value?: string | null; options: readonly string[] }) {
  return <Select label="Neighborhood" name="neighborhood" defaultValue={value ?? ""} options={[["", "Not set"], ...options.map((o) => [o, o.replace(/\b\w/g, (c) => c.toUpperCase())] as const)]} />;
}
