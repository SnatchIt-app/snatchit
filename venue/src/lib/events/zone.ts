import type { DataSource } from "@/lib/env";
import { VENUE } from "@/fixtures/venue";

/**
 * Which time zone the dashboard reads an operator's wall clock in, and whether
 * it actually knows it.
 *
 * `catalog.venue.timezone` exists with a NOT NULL default of America/New_York
 * and is projected into `venue_api.events` / `event_sessions` by migration 162,
 * which is not applied anywhere yet. Until it is, database mode has no readable
 * venue zone, so this returns the platform default and says `source: "default"`
 * — and every screen that converts a time says which zone it used. Guessing
 * silently would put a Miami door time four or five hours out.
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
