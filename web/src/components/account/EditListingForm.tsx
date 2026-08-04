"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { PLATFORM_INSTRUCTIONS } from "@snatchit/core";
import { updateListingAction } from "@/lib/seller-listings-actions";
import { findBannedTerm } from "@/lib/content-moderation";
import { Field } from "@/components/ui/Field";
import { Input, Select, Textarea } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";

// All 16 platforms the DB check constraint allows. Mobile's edit screen only
// offers 6, which would silently narrow a seller's choice on re-save.
const PLATFORMS = Object.values(PLATFORM_INSTRUCTIONS);

/**
 * Only the four fields mobile's edit screen exposes are editable
 * (event_name, venue, restrictions, ticket_platform). Price, timing, and
 * quantity are deliberately not editable — the DB would allow them, but
 * changing price or the clock under live bidders is a trust problem.
 */
export function EditListingForm({
  listingId,
  eventName: initialEventName,
  venue: initialVenue,
  restrictions: initialRestrictions,
  ticketPlatform: initialPlatform,
}: {
  listingId: string;
  eventName: string;
  venue: string;
  restrictions: string;
  ticketPlatform: string;
}) {
  const router = useRouter();
  const [eventName, setEventName] = useState(initialEventName);
  const [venue, setVenue] = useState(initialVenue);
  const [restrictions, setRestrictions] = useState(initialRestrictions);
  const [ticketPlatform, setTicketPlatform] = useState(initialPlatform);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!eventName.trim()) return setError("Event name is required.");
    if (!venue.trim()) return setError("Venue is required.");
    if (findBannedTerm(`${eventName} ${venue} ${restrictions}`)) {
      return setError("Listing details can't mention prohibited content — please rephrase.");
    }

    startTransition(async () => {
      const result = await updateListingAction(listingId, {
        eventName,
        venue,
        restrictions: restrictions.trim() || null,
        ticketPlatform,
      });
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(`/account/listings/${listingId}/edit`)}`);
        return;
      }
      if (result.error) {
        setError(result.error);
        return;
      }
      router.push("/account/listings");
    });
  }

  return (
    <form onSubmit={handleSubmit} noValidate className="space-y-5">
      {error ? <Alert tone="error">{error}</Alert> : null}

      <Field label="Event name" htmlFor="eventName">
        <Input id="eventName" value={eventName} onChange={(e) => setEventName(e.target.value)} maxLength={120} required />
      </Field>
      <Field label="Venue" htmlFor="venue">
        <Input id="venue" value={venue} onChange={(e) => setVenue(e.target.value)} maxLength={120} required />
      </Field>
      <Field label="Ticket platform" htmlFor="ticketPlatform">
        <Select id="ticketPlatform" value={ticketPlatform} onChange={(e) => setTicketPlatform(e.target.value)}>
          {PLATFORMS.map((p) => (
            <option key={p.platform} value={p.platform}>
              {p.displayName}
            </option>
          ))}
        </Select>
      </Field>
      <Field label="Restrictions" htmlFor="restrictions" hint="Optional — age limits, dress code, etc.">
        <Textarea id="restrictions" value={restrictions} onChange={(e) => setRestrictions(e.target.value)} maxLength={500} />
      </Field>

      <p className="text-[12.5px] leading-relaxed text-white/45">
        Price, timing, and quantity can&apos;t be changed after a listing goes live. Cancel and
        relist if those need to change.
      </p>

      <div className="flex gap-3">
        <Button type="submit" variant="primary" disabled={isPending}>
          {isPending ? "Saving…" : "Save changes"}
        </Button>
        <Button type="button" variant="secondary" onClick={() => router.push("/account/listings")}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
