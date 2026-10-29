"use client";

import { CommandForm, Field, Select, type CommandIds } from "@/components/commands/CommandForm";
import { setVenueTimezoneForm, updateVenueForm } from "@/lib/events/forms";
import { NEIGHBORHOODS } from "@/lib/events/command-contract";

/**
 * The venue's own details and its time zone (readiness row 2). The zone is not
 * cosmetic: every session time the dashboard sends is built by converting the
 * operator's wall clock with it, so it sits beside the times it governs and the
 * organizer can correct it here rather than waiting for a migration.
 *
 * `capacity_hint` is a planning number, not an approved occupancy and not the
 * oversell guard — the pool per night is what refuses an oversell. Moving a
 * venue to another organization is refused by the server and is not offered.
 */
const COMMON_ZONES = [
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Phoenix",
  "America/Anchorage",
  "Pacific/Honolulu",
  "America/Puerto_Rico",
  "UTC",
] as const;

export function VenueDetailsForm({ ids, commandKey, venue }: { ids: CommandIds; commandKey: string; venue: { name?: string | null; neighborhood?: string | null; address?: string | null; capacityHint?: number | null } }) {
  return (
    <CommandForm action={updateVenueForm} ids={ids} commandKey={commandKey} submitLabel="Save the venue" busyLabel="Saving…">
      <Field label="Name" name="name" defaultValue={venue.name ?? ""} maxLength={200} />
      <Select
        label="Neighbourhood"
        name="neighborhood"
        defaultValue={venue.neighborhood ?? ""}
        options={[["", "Not set"], ...NEIGHBORHOODS.map((n) => [n, n.replace(/\b\w/g, (c) => c.toUpperCase())] as const)]}
        hint="One of the areas Snatch It lists."
      />
      <Field label="Address" name="address" defaultValue={venue.address ?? ""} maxLength={300} />
      <Field
        label="Capacity"
        name="capacity_hint"
        type="number"
        min={1}
        step={1}
        defaultValue={typeof venue.capacityHint === "number" ? String(venue.capacityHint) : ""}
        hint="A planning number, not an approved occupancy. What a night may sell is set per night."
      />
      <Field label="Reason for this change (optional)" name="reason_code" placeholder="profile_fill" maxLength={80} />
    </CommandForm>
  );
}

export function VenueTimezoneForm({ ids, commandKey, timeZone }: { ids: CommandIds; commandKey: string; timeZone: string }) {
  const known = (COMMON_ZONES as readonly string[]).includes(timeZone);
  return (
    <CommandForm action={setVenueTimezoneForm} ids={ids} commandKey={commandKey} submitLabel="Set the time zone" busyLabel="Setting…">
      <Select
        label="Time zone"
        name="timezone"
        defaultValue={known ? timeZone : ""}
        options={[...(known ? [] : [["", timeZone ? `${timeZone} (keep)` : "Choose one"] as const]), ...COMMON_ZONES.map((z) => [z, z.replace(/_/g, " ")] as const)]}
        hint="Every time you enter for this venue's nights is read in this zone. Changing it does not move times already saved."
      />
      <Field label="Reason" name="reason_code" required placeholder="venue_moved" maxLength={80} />
    </CommandForm>
  );
}
