import { CATEGORY_LABELS, NEIGHBORHOOD_LABELS, PLATFORM_INSTRUCTIONS } from "@snatchit/core";
import { STORAGE_BASE_URL } from "@/lib/env";
import type { EventCategory, Neighborhood, TicketPlatform } from "@snatchit/types";

/**
 * Listing display helpers. Pure functions — unit-tested in tests/format.test.ts.
 * Event dates/times are stored as plain "YYYY-MM-DD" / "HH:MM:SS" strings
 * (Miami-local by product definition), so they are formatted WITHOUT any
 * timezone conversion.
 */

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** "2026-10-17" → "Sat, Oct 17, 2026" (no TZ math on date-only values). */
export function fmtEventDate(isoDate: string): string {
  const [y, m, d] = isoDate.split("-").map(Number);
  if (!y || !m || !d) return isoDate;
  const date = new Date(y, m - 1, d);
  return `${DAYS[date.getDay()]}, ${MONTHS[m - 1]} ${d}, ${y}`;
}

/** "23:00:00" → "11:00 PM" · "02:00:00" → "2:00 AM". */
export function fmtEventTime(time: string): string {
  const [hStr, mStr] = time.split(":");
  const h = Number(hStr);
  if (Number.isNaN(h)) return time;
  const suffix = h >= 12 ? "PM" : "AM";
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}:${mStr ?? "00"} ${suffix}`;
}

/** Auction time remaining, coarse on purpose: "27d 3h" · "3h 12m" · "12m" · "Ended". */
export function fmtEndsIn(endsAtIso: string, now: Date = new Date()): string {
  const ms = new Date(endsAtIso).getTime() - now.getTime();
  if (Number.isNaN(ms) || ms <= 0) return "Ended";
  const totalMinutes = Math.floor(ms / 60_000);
  const days = Math.floor(totalMinutes / (60 * 24));
  const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${Math.max(minutes, 1)}m`;
}

export type CardStatus = "LIVE" | "ENDING SOON" | "RESERVED" | "SOLD" | "ENDED";

const ENDING_SOON_MS = 24 * 60 * 60 * 1000;

export function listingCardStatus(
  l: {
    status: string;
    auction_status: string;
    ends_at: string;
  },
  now: Date = new Date(),
): CardStatus {
  // A cancelled listing keeps status='active' (cancel_listing resets it so the
  // reservation is released), so this must be checked FIRST — otherwise it
  // falls through to LIVE and the card offers bidding on a withdrawn listing.
  if (l.auction_status === "cancelled") return "ENDED";
  if (l.status === "sold" || l.auction_status === "sold") return "SOLD";
  if (l.status === "reserved") return "RESERVED";
  const remaining = new Date(l.ends_at).getTime() - now.getTime();
  if (l.auction_status === "ended" || remaining <= 0) return "ENDED";
  if (remaining <= ENDING_SOON_MS) return "ENDING SOON";
  return "LIVE";
}

export function categoryLabel(category: string): string {
  return CATEGORY_LABELS[category as EventCategory] ?? capitalize(category);
}

export function neighborhoodLabel(neighborhood: string): string {
  return NEIGHBORHOOD_LABELS[neighborhood as Neighborhood] ?? capitalize(neighborhood);
}

export function platformLabel(platform: string): string {
  // Matches the core displayName for the unknown case ("Other Platform"), so
  // this fallback and deliveryLabel below stay consistent with the shared
  // package rather than drifting from it.
  return PLATFORM_INSTRUCTIONS[platform as TicketPlatform]?.displayName ?? "Other Platform";
}

/**
 * How the ticket reaches the buyer, as a sentence.
 *
 * Interpolating platformLabel() straight into `Official ${platform} transfer`
 * produced "Official Other Platform transfer" — and create-listing defaults
 * ticketPlatform to "other", so that was the DEFAULT string. It also produced
 * "Official StubHub (purchased there) transfer" for the parenthesised labels.
 * The same text feeds the public JSON-LD description, so it was search-visible.
 */
export function deliveryLabel(platform: string): string {
  const known = PLATFORM_INSTRUCTIONS[platform as TicketPlatform];
  // "other" IS a known key — its displayName is literally "Other Platform",
  // which is what produced the broken copy. It is a catch-all, not a brand,
  // so it takes the generic sentence like an unrecognised value does.
  if (!known || platform === "other") return "Official platform transfer";
  // Labels like "StubHub (purchased there)" carry a parenthetical that reads
  // as noise mid-sentence; the bare brand is what belongs here.
  const brand = known.displayName.replace(/\s*\(.*\)\s*$/, "");
  return `Official ${brand} transfer`;
}

function capitalize(s: string): string {
  return s.replace(/\b\w/g, (c) => c.toUpperCase());
}

/**
 * Public URL for a listing cover image.
 *
 * Lives here, not in lib/listings.ts, because that module pulls in
 * lib/supabase/server.ts -> next/headers, so a "use client" component
 * importing it dragged a server-only module into the client bundle and broke
 * the build. This is a pure string join and is safe on both sides.
 */
export function coverImageUrl(path: string): string {
  return `${STORAGE_BASE_URL}/auction-media/${path}`;
}
