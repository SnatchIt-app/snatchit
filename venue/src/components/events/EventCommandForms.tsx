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
      <Field label="Starts" name="starts_local" type="datetime-local" required defaultValue={defaults?.starts ?? ""} hint={`Entered in the venue's time zone (${timeZone}).`} />
      <Field label="Doors open (optional)" name="doors_local" type="datetime-local" defaultValue={defaults?.doors ?? ""} />
      <Field label="Ends (optional)" name="ends_local" type="datetime-local" defaultValue={defaults?.ends ?? ""} />
    </>
  );
}

export function CreateEventForm({ ids, commandKey, timeZone }: { ids: CommandIds; commandKey: string; timeZone: string }) {
  return (
    <section className="panel px-5 py-5" aria-labelledby="create-event">
      <h2 id="create-event" className="text-base font-semibold text-ink">Create an event</h2>
      <p className="mt-1 text-sm text-dim">It is born as a draft: your staff can see it, nobody else can, and it sells nothing until you publish it.</p>
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
      <Field label="Description" name="description" defaultValue={description ?? ""} maxLength={2000} />
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
          ? "Going on sale needs a ticket type with a release, an organization cleared to sell, Stripe confirming the payout account, ticket signing enabled and the platform's fee set. If any of those is missing the server says which."
          : "An event moves forward one step at a time, and never backwards."}
      </p>
    </CommandForm>
  );
}

export function CancelEventForm({ ids, commandKey }: { ids: CommandIds; commandKey: string }) {
  return (
    <CommandForm action={cancelEventForm} ids={ids} commandKey={commandKey} submitLabel="Cancel this event" busyLabel="Cancelling…" destructive>
      <p className="text-sm text-muted">Cancelling is recorded and cannot be undone from here. Nothing is deleted.</p>
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

export function SessionCapacityForm({ ids, commandKey, sessionId, capacity, allocated, capacityHint }: { ids: CommandIds; commandKey: string; sessionId: string; capacity?: number | null; allocated?: number | null; capacityHint?: number | null }) {
  const known = typeof allocated === "number";
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
            ? `Already allocated to releases: ${allocated}${typeof capacityHint === "number" ? ` · venue capacity ${capacityHint}` : ""}. Leave empty for unlimited.`
            : "Leave empty for unlimited. The server refuses a pool below what is already allocated, or above the venue's capacity, and says the numbers."
        }
      />
      <Field label="Reason" name="reason_code" required placeholder="opening_pool" maxLength={80} />
    </CommandForm>
  );
}

export function NeighborhoodSelect({ value, options }: { value?: string | null; options: readonly string[] }) {
  return <Select label="Neighbourhood" name="neighborhood" defaultValue={value ?? ""} options={[["", "Not set"], ...options.map((o) => [o, o.replace(/\b\w/g, (c) => c.toUpperCase())] as const)]} />;
}
