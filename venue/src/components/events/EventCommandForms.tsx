"use client";

import { useState } from "react";
import { Button } from "@astryxdesign/core/Button";
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
  const [preview, setPreview] = useState(false);
  const [draft, setDraft] = useState({ title: "", starts: "", doors: "", ends: "", label: "" });
  return (
    <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_20rem]">
      <section className="panel px-5 py-6 md:px-7" aria-labelledby="create-event">
        <p className="eyebrow-caps">Start with the essentials</p>
        <h2 id="create-event" className="serif mt-2 text-3xl">Make it a night to remember.</h2>
        <p className="mt-3 max-w-xl text-sm leading-relaxed text-muted">Add your event name and date, then save a draft. Your event workspace opens next, with details, dates, tickets and publishing together.</p>
        <div className="mt-6" onChange={(event) => {
          const form = (event.target as HTMLInputElement).form;
          if (!form) return;
          const data = new FormData(form);
          setDraft({ title: String(data.get("title") ?? ""), starts: String(data.get("starts_local") ?? ""), doors: String(data.get("doors_local") ?? ""), ends: String(data.get("ends_local") ?? ""), label: String(data.get("session_label") ?? "") });
        }}>
          <CommandForm action={createEventForm} ids={ids} commandKey={commandKey} submitLabel="Save draft" busyLabel="Saving draft…" openCreatedEvent>
            <Field label="Event name" name="title" required maxLength={200} placeholder="Give your event a name" />
            <input type="hidden" name="timeZone" value={timeZone} />
            <fieldset className="grid gap-4 border-t border-line pt-5 sm:grid-cols-2">
              <legend className="pb-3 pt-6 text-base font-semibold">Date and time</legend>
              <Field label="Event starts" name="starts_local" type="datetime-local" required />
              <Field label="Event ends (optional)" name="ends_local" type="datetime-local" />
              <Field label="Doors open (optional)" name="doors_local" type="datetime-local" />
              <Field label="Name for this night (optional)" name="session_label" placeholder="Friday night" maxLength={120} />
            </fieldset>
            <p className="text-xs text-muted">All times are in {timeZone}. Your draft stays private and cannot sell tickets.</p>
            <details className="rounded-xl border border-line px-3 py-2 text-xs text-muted">
              <summary className="cursor-pointer py-1">If saving takes too long</summary>
              <p className="mt-2 leading-relaxed">If no answer comes back, check your events list before starting again. Each new save can create another draft.</p>
            </details>
          </CommandForm>
        </div>
      </section>
      <aside className="panel px-5 py-6">
        <p className="eyebrow-caps">Your event</p>
        <div className="mt-4"><Button label={preview ? "Close preview" : "Preview draft"} clickAction={() => setPreview(!preview)} aria-expanded={preview} aria-controls="draft-preview" /></div>
        {preview ? <div id="draft-preview" className="mt-4 space-y-3 rounded-xl border border-line p-4">
          <p className="text-xs text-muted">Unsaved preview · only visible to you</p>
          <h3 className="serif break-words text-2xl">{draft.title || "Your event name"}</h3>
          <p className="text-sm">{draft.starts ? draft.starts.replace("T", " · ") : "Date and time to be added"}</p>
          {draft.label ? <p className="text-sm">{draft.label}</p> : null}
          {draft.doors ? <p className="text-xs text-muted">Doors: {draft.doors.replace("T", " · ")}</p> : null}
          {draft.ends ? <p className="text-xs text-muted">Ends: {draft.ends.replace("T", " · ")}</p> : null}
          <p className="text-xs text-muted">{timeZone}</p>
        </div> : null}
        <ol className="mt-6 space-y-4 border-t border-line pt-5 text-sm">
          <li><strong>1. Save draft</strong><p className="mt-1 text-muted">Start with a name and date.</p></li>
          <li><strong>2. Add tickets</strong><p className="mt-1 text-muted">Set ticket types, prices and availability.</p></li>
          <li><strong>3. Publish event</strong><p className="mt-1 text-muted">Announce your event when it is ready. Opening sales is a separate step.</p></li>
        </ol>
      </aside>
    </div>
  );
}

export function EventDetailsForm({ ids, commandKey, status, currentTitle, description, category, genreTags }: { ids: CommandIds; commandKey: string; status: EventStatusName; currentTitle: string; description?: string | null; category?: string | null; genreTags?: string[] }) {
  const needsReason = status !== "draft";
  const [editing, setEditing] = useState<Record<string, boolean>>({});
  return (
    <CommandForm action={updateEventForm} ids={ids} commandKey={commandKey} extra={{ status, current_title: currentTitle }} submitLabel="Save the details" busyLabel="Saving…" onSettled={() => setEditing({})}>
      <Field label="Title" name="title" defaultValue={currentTitle} maxLength={200} hint={needsReason ? "Changing the title now needs a reason, which is recorded." : undefined} />
      <p className="text-sm text-muted">Only the fields you choose to edit will change. Saved description, category and genres are not loaded here.</p>
      {[
        { name: "description", label: "Description", value: description ?? "", max: 2000 },
        { name: "category", label: "Category", value: category ?? "", max: 60 },
        { name: "genre_tags", label: "Genres", value: (genreTags ?? []).join(", "), max: undefined },
      ].map((field) => (
        <section key={field.name} className="rounded-xl border border-line p-3">
          <label className="flex min-h-8 items-center gap-2 text-sm">
            <input type="checkbox" checked={!!editing[field.name]} onChange={(event) => setEditing((previous) => ({ ...previous, [field.name]: event.target.checked }))} />
            Change {field.label.toLowerCase()}
          </label>
          <fieldset disabled={!editing[field.name]} className="mt-2 disabled:opacity-50">
            <legend className="sr-only">Replace {field.label.toLowerCase()}</legend>
            <Field label={field.label} name={field.name} defaultValue={field.value} maxLength={field.max} hint={field.name === "genre_tags" ? "Separate with commas. Leave empty only to clear saved genres." : `Leave empty only to clear the saved ${field.label.toLowerCase()}.`} />
          </fieldset>
        </section>
      ))}
      {needsReason ? <Field label="Reason for this change" name="reason_code" placeholder="Explain why the name is changing" maxLength={80} /> : null}
    </CommandForm>
  );
}

export function PublishEventForm({ ids, commandKey, target }: { ids: CommandIds; commandKey: string; target: (typeof PUBLISH_TARGETS)[number] }) {
  return (
    <CommandForm action={publishEventForm} ids={ids} commandKey={commandKey} extra={{ target_status: target }} submitLabel={target === "announced" ? "Publish event" : target === "on_sale" ? "Open ticket sales" : target === "live" ? "Start event" : `Mark ${STATUS_WORD[target] ?? target}`} busyLabel="Updating…">
      <p className="text-sm text-muted">
        {target === "on_sale"
          ? "Opening sales lets buyers purchase available tickets. We check ticket availability and payment setup first. If anything is missing, you will see what needs attention."
          : target === "announced" ? "Publish the event announcement. This does not open ticket sales. This step cannot be reversed here." : "This moves the event to its next stage and cannot be reversed here."}
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
