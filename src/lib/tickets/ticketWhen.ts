/**
 * src/lib/tickets/ticketWhen.ts — the event's date, doors and start as the ticket shows them.
 *
 * The server stores absolute instants (timestamptz). The ticket renders them in ONE zone — the
 * event's own when the session read supplies it, else the device's — and always names the zone, so
 * a buyer travelling from another time zone reads "11:00 PM EST", not a bare "11:00 PM". The zone
 * is display only; nothing here decides whether doors are open.
 */

export interface WhenLine {
  /** "Sat, Nov 30" */
  date: string;
  /** "Doors 10:00 PM · 11:00 PM EST" (doors only when known) */
  times: string;
  /** "EST" / "GMT-5" — whatever Intl names the zone; '' when it cannot be resolved */
  zone: string;
}

function fmt(d: Date, opts: Intl.DateTimeFormatOptions, timeZone?: string): string {
  try {
    return new Intl.DateTimeFormat(undefined, { ...opts, ...(timeZone ? { timeZone } : {}) }).format(d);
  } catch {
    return new Intl.DateTimeFormat(undefined, opts).format(d);
  }
}

function zoneName(d: Date, timeZone?: string): string {
  try {
    const parts = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short', ...(timeZone ? { timeZone } : {}) }).formatToParts(d);
    return parts.find((p) => p.type === 'timeZoneName')?.value ?? '';
  } catch {
    return '';
  }
}

export function whenLine(startsAt: string, doorsAt: string | null | undefined, timeZone?: string): WhenLine | null {
  const start = new Date(startsAt);
  if (Number.isNaN(start.getTime())) return null;
  const time = (d: Date) => fmt(d, { hour: 'numeric', minute: '2-digit' }, timeZone);
  const zone = zoneName(start, timeZone);
  const doors = doorsAt ? new Date(doorsAt) : null;
  const doorsText = doors && !Number.isNaN(doors.getTime()) ? `Doors ${time(doors)} · ` : '';
  return {
    date: fmt(start, { weekday: 'short', month: 'short', day: 'numeric' }, timeZone),
    times: `${doorsText}${time(start)}${zone ? ` ${zone}` : ''}`,
    zone,
  };
}

/** "21+" style line from the (pending) session read; null when the server said nothing. */
export function entryRestrictionLine(ageMin: number | null | undefined): string | null {
  if (typeof ageMin !== 'number' || !Number.isFinite(ageMin) || ageMin <= 0) return null;
  return `${Math.floor(ageMin)}+ · ID checked at the door`;
}
