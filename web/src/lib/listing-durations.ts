/**
 * Auction lengths a seller can pick, in hours. Shared by the /sell form and the server-side
 * check in createListing, and must match the database's listings_duration_hours_check (A's
 * migration adds 72 h; web must not offer a length the database refuses).
 */
export const LISTING_DURATION_HOURS = [1, 3, 6, 12, 24, 48, 72] as const;

export type ListingDurationHours = (typeof LISTING_DURATION_HOURS)[number];

export function isListingDuration(hours: unknown): hours is ListingDurationHours {
  return typeof hours === "number" && (LISTING_DURATION_HOURS as readonly number[]).includes(hours);
}

/** "6h", "1d", "3d" — compact, matching the pill row on /sell. */
export function durationLabel(hours: number): string {
  return hours < 24 ? `${hours}h` : `${hours / 24}d`;
}
