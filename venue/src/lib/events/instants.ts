/**
 * Wall clock in a venue's timezone → an instant the database stores without
 * ambiguity. Pure, so every rule is a unit test.
 *
 * Why this exists (D's rule, 2026-10-26): `catalog.event_session.starts_at`,
 * `ends_at`, `doors_at` and the 162 sale windows are `timestamptz` INSTANTS. A
 * naive literal like "2026-11-30 19:00" is read in the PostgREST session's
 * TimeZone (UTC), which is 4–5 hours wrong for Miami. So the dashboard converts
 * the operator's local input using the venue's IANA zone and sends ISO-8601
 * WITH an offset, e.g. "2026-11-30T19:00:00-05:00". Display comes from the
 * `*_local` projections, never from a re-conversion here.
 *
 * No dependency: the offset is derived from the platform's own IANA database
 * through Intl, so it follows DST without a table of our own.
 */

/** The zone's UTC offset at a given instant, as ±HH:MM. Null if the zone is not one the platform knows. */
export function zoneOffsetAt(instant: Date, timeZone: string): string | null {
  if (!timeZone || Number.isNaN(instant.getTime())) return null;
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-US", { timeZone, timeZoneName: "longOffset" }).formatToParts(instant);
  } catch {
    return null; // RangeError: unknown time zone
  }
  const name = parts.find((p) => p.type === "timeZoneName")?.value ?? "";
  if (name === "GMT") return "+00:00";
  const m = /^GMT([+-])(\d{1,2})(?::(\d{2}))?$/.exec(name);
  if (!m) return null;
  const sign = m[1];
  const hh = m[2].padStart(2, "0");
  const mm = (m[3] ?? "00").padStart(2, "0");
  return `${sign}${hh}:${mm}`;
}

/** Minutes east of UTC for a ±HH:MM offset. */
function offsetMinutes(offset: string): number {
  const m = /^([+-])(\d{2}):(\d{2})$/.exec(offset);
  if (!m) return 0;
  const sign = m[1] === "-" ? -1 : 1;
  return sign * (Number(m[2]) * 60 + Number(m[3]));
}

export type WallClock = { date: string; time: string };

/** `<input type="datetime-local">` gives "YYYY-MM-DDTHH:MM" (optionally with seconds). */
export function parseWallClock(local: string): WallClock | null {
  const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})(?::\d{2})?$/.exec((local ?? "").trim());
  if (!m) return null;
  const [y, mo, d] = m[1].split("-").map(Number);
  const [h, mi] = m[2].split(":").map(Number);
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;
  // Reject a date that does not exist (31 February), which the regex allows.
  const probe = new Date(Date.UTC(y, mo - 1, d, h, mi));
  if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d) return null;
  return { date: m[1], time: m[2] };
}

export type InstantResult =
  | { ok: true; iso: string; offset: string; utc: string }
  /** The local time does not exist (clocks sprang forward over it) or occurs twice (fell back). */
  | { ok: false; reason: "nonexistent" | "ambiguous" | "bad_input" | "unknown_zone"; detail?: string };

/**
 * One local wall-clock reading in one zone → the offset-qualified literal to
 * send. Two passes: the offset at a first guess, then the offset at the instant
 * that guess implies. If the two disagree the local time sits on a DST
 * transition, and this refuses rather than silently choosing an hour — the
 * operator is told to pick a different time or state the offset.
 */
export function toOffsetInstant(local: string, timeZone: string): InstantResult {
  const wall = parseWallClock(local);
  if (!wall) return { ok: false, reason: "bad_input" };
  const naiveUtc = new Date(`${wall.date}T${wall.time}:00Z`);
  if (Number.isNaN(naiveUtc.getTime())) return { ok: false, reason: "bad_input" };
  const firstOffset = zoneOffsetAt(naiveUtc, timeZone);
  if (!firstOffset) return { ok: false, reason: "unknown_zone", detail: timeZone };
  // The instant that local reading means, if the first offset holds.
  const candidate = new Date(naiveUtc.getTime() - offsetMinutes(firstOffset) * 60_000);
  const settled = zoneOffsetAt(candidate, timeZone);
  if (!settled) return { ok: false, reason: "unknown_zone", detail: timeZone };
  if (settled !== firstOffset) {
    // Re-resolve with the settled offset; if THAT round trips, use it.
    const second = new Date(naiveUtc.getTime() - offsetMinutes(settled) * 60_000);
    const confirm = zoneOffsetAt(second, timeZone);
    if (confirm !== settled) return { ok: false, reason: "nonexistent", detail: `${local} does not exist in ${timeZone}` };
    return { ok: true, iso: `${wall.date}T${wall.time}:00${settled}`, offset: settled, utc: second.toISOString() };
  }
  // Does this local reading happen twice (fall back)? Then the instant an hour
  // later in UTC reads the same wall clock under a different offset.
  const hourLater = new Date(candidate.getTime() + 3_600_000);
  const laterOffset = zoneOffsetAt(hourLater, timeZone);
  if (laterOffset && laterOffset !== firstOffset) {
    const laterSame = formatInZone(hourLater, timeZone);
    if (laterSame === `${wall.date}T${wall.time}`) return { ok: false, reason: "ambiguous", detail: `${local} happens twice in ${timeZone}` };
  }
  return { ok: true, iso: `${wall.date}T${wall.time}:00${firstOffset}`, offset: firstOffset, utc: candidate.toISOString() };
}

/** An instant as the zone's own wall clock, "YYYY-MM-DDTHH:MM" — for comparing, not for display. */
export function formatInZone(instant: Date, timeZone: string): string | null {
  try {
    const p = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(instant);
    const get = (t: string) => p.find((x) => x.type === t)?.value ?? "";
    const hour = get("hour") === "24" ? "00" : get("hour");
    return `${get("year")}-${get("month")}-${get("day")}T${hour}:${get("minute")}`;
  } catch {
    return null;
  }
}

/** The order the server enforces: ends_at must be after starts_at. Compared as instants, never as strings. */
export function endsAfterStarts(startsIso: string, endsIso: string): boolean {
  const a = Date.parse(startsIso);
  const b = Date.parse(endsIso);
  return Number.isFinite(a) && Number.isFinite(b) && b > a;
}

/** Doors before (or at) the start: a doors time after the start is a mistake worth catching in the form. */
export function doorsNotAfterStart(startsIso: string, doorsIso: string): boolean {
  const a = Date.parse(startsIso);
  const b = Date.parse(doorsIso);
  return Number.isFinite(a) && Number.isFinite(b) && b <= a;
}
