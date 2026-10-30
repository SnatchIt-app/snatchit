import type { DataSource } from "@/lib/env";
import { VENUE } from "@/fixtures/venue";

/**
 * Which time zone the dashboard reads an operator's wall clock in, and whether
 * it actually knows it.
 *
 * `catalog.venue.timezone` exists with a NOT NULL default of America/New_York.
 * Migration 162 (20261026100000) IS applied and projects it into
 * `venue_api.events` and `venue_api.event_sessions` — corrected 2026-10-30; the
 * previous comment claimed 162 was "not applied anywhere yet", which was stale.
 *
 * `venue_api.venues` still does NOT expose `timezone`, so the VENUE's own stored
 * zone is not readable yet (registry 195). Until it is, database mode returns the
 * platform default and says `source: "default"`, and every screen that converts a
 * time says which zone it used. Guessing silently would put a Miami door time
 * four or five hours out — which is also why a form must never PRESELECT this
 * default as if it were the stored value.
 */
export const PLATFORM_DEFAULT_TIME_ZONE = "America/New_York";

export type ZoneInfo = { zone: string; source: "venue" | "default" | "sample" };

export function venueTimeZone(dataSource: DataSource, projected?: string | null): ZoneInfo {
  if (dataSource !== "database") return { zone: VENUE.timeZone, source: "sample" };
  const z = (projected ?? "").trim();
  if (z) return { zone: z, source: "venue" };
  return { zone: PLATFORM_DEFAULT_TIME_ZONE, source: "default" };
}

export function zoneNote(info: ZoneInfo): string {
  switch (info.source) {
    case "venue":
      return `Times are read in this venue's time zone (${info.zone}).`;
    case "default":
      return `Times are read in ${info.zone}, the platform default, because this project does not publish the venue's own time zone yet. Set the venue's time zone if that is wrong.`;
    case "sample":
      return `Times are read in ${info.zone} (sample data).`;
  }
}
