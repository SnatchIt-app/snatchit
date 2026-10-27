import { CancelEventForm, EventDetailsForm, PublishEventForm, SessionCapacityForm, SessionForm } from "@/components/events/EventCommandForms";
import { Detail } from "@/components/ui/Page";
import type { CommandIds } from "@/components/commands/CommandForm";
import { nextPublishTarget, type EventStatusName } from "@/lib/events/command-contract";
import { formatInZone } from "@/lib/events/instants";
import { zoneNote, type ZoneInfo } from "@/lib/events/zone";
import type { SessionCapacity } from "@/lib/db/session-capacity";
import type { Event } from "@/lib/types";

/**
 * The organizer's commands on the event page: details, the next forward step,
 * each night's times and pool, and cancelling — each a separate form carrying
 * its own command key, each disclosed rather than crowding the page. Rendered
 * only when the command gate is open and the role may edit; the server checks
 * both again on every call.
 */
export type EventCommandKeys = { details: string; publish: string; cancel: string; sessionNew: string; session: Record<string, string>; capacity: Record<string, string> };

export function EventCommandPanel({ ids, event, keys, zone, capacities }: { ids: CommandIds; event: Event; keys: EventCommandKeys; zone: ZoneInfo; capacities?: Record<string, SessionCapacity> }) {
  const status = event.status as EventStatusName;
  const target = nextPublishTarget(status);
  const terminal = status === "completed" || status === "cancelled";
  const local = (iso: string | null | undefined) => (iso ? (formatInZone(new Date(iso), zone.zone) ?? undefined) : undefined);

  return (
    <div className="space-y-4">
      <p className="text-xs text-dim">{zoneNote(zone)}</p>

      <Detail summary="Edit the event's details">
        <EventDetailsForm ids={ids} commandKey={keys.details} status={status} currentTitle={event.title} />
      </Detail>

      {target && !terminal ? <Detail summary={`Move this event forward (next: ${target.replace("_", " ")})`}>
        <PublishEventForm ids={ids} commandKey={keys.publish} target={target} />
      </Detail> : null}

      <Detail summary="The nights: times, doors and how many each may sell">
        <div className="space-y-6">
          {event.sessions.map((s) => (
            <div key={s.sessionId} className="space-y-3 border-t border-line pt-4 first:border-0 first:pt-0">
              <p className="text-sm font-semibold">{s.label ?? local(s.startsAt) ?? "Session"}</p>
              <SessionForm
                ids={ids}
                commandKey={keys.session[s.sessionId] ?? ""}
                timeZone={zone.zone}
                session={{ sessionId: s.sessionId, label: s.label, startsLocal: local(s.startsAt), endsLocal: local(s.endsAt), doorsLocal: local(s.doorsAt) }}
              />
              <SessionCapacityForm
                ids={ids}
                commandKey={keys.capacity[s.sessionId] ?? ""}
                sessionId={s.sessionId}
                capacity={capacities?.[s.sessionId]?.salesCapacity}
                allocated={capacities?.[s.sessionId]?.allocated}
                capacityHint={capacities?.[s.sessionId]?.capacityHint}
                remainingToAllocate={capacities?.[s.sessionId]?.remainingToAllocate}
              />
            </div>
          ))}
          <div className="border-t border-line pt-4">
            <p className="text-sm font-semibold">Add another night</p>
            <div className="mt-2">
              <SessionForm ids={ids} commandKey={keys.sessionNew} timeZone={zone.zone} />
            </div>
          </div>
        </div>
      </Detail>

      {!terminal ? <Detail summary="Cancel this event">
        <CancelEventForm ids={ids} commandKey={keys.cancel} />
      </Detail> : null}
    </div>
  );
}
