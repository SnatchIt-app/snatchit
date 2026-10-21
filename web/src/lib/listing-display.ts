import { fmtEventTime, listingCardStatus } from "@/lib/format";

/**
 * Presentation helpers for listing rows and cards, mirroring the native
 * card state (src/lib/listing/cardState.ts, feedRowState.ts). Pure functions,
 * unit-tested in tests/listing-display.test.ts. They choose which figure and
 * which label to show; the figure itself is always a stored listing amount,
 * rendered all-in by PriceDisplay.
 */

type ListingLike = {
  status: string;
  auction_status: string;
  ends_at: string;
  bid_count: number;
  current_bid: number;
  starting_bid: number;
  winning_bid_amount?: number | null;
  event_date: string;
  event_time: string;
  quantity: number;
  ticket_type: string;
};

export type PriceLabel = "Current bid" | "Starting bid" | "Sold for" | "Final bid" | "Started at";

export function priceState(l: ListingLike, now: Date = new Date()): { label: PriceLabel; dollars: number } {
  const status = listingCardStatus(l, now);
  if (status === "SOLD") return { label: "Sold for", dollars: l.winning_bid_amount ?? l.current_bid };
  if (status === "ENDED") {
    return l.bid_count > 0 ? { label: "Final bid", dollars: l.current_bid } : { label: "Started at", dollars: l.starting_bid };
  }
  return l.bid_count > 0 ? { label: "Current bid", dollars: l.current_bid } : { label: "Starting bid", dollars: l.current_bid };
}

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "2026-10-24" → "Sat, Oct 24" (date-only, no timezone math — same rule as fmtEventDate). */
export function fmtEventDay(isoDate: string): string {
  const [y, m, d] = isoDate.split("-").map(Number);
  if (!y || !m || !d || m < 1 || m > 12 || d < 1 || d > 31) return isoDate;
  return `${DAYS[new Date(y, m - 1, d).getDay()]}, ${MONTHS[m - 1]} ${d}`;
}

/** "Sat, Oct 24 · 9:30 PM" */
export function eventWhen(l: Pick<ListingLike, "event_date" | "event_time">): string {
  return `${fmtEventDay(l.event_date)} · ${fmtEventTime(l.event_time)}`;
}

/** "2 × GA" · "1 × VIP" · "6 × Table" */
export function quantityLine(l: Pick<ListingLike, "quantity" | "ticket_type">): string {
  const type = l.ticket_type === "TABLE" ? "Table" : l.ticket_type;
  return `${l.quantity} × ${type}`;
}

export type ClockTone = "urgent" | "normal" | "muted";

/** Event dates and end times are Miami-local by product definition; the web server runs on UTC. */
export const MARKET_TIME_ZONE = "America/New_York";

function marketParts(d: Date): { y: number; m: number; d: number; wd: string; h: number; min: number } {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: MARKET_TIME_ZONE,
      year: "numeric",
      month: "numeric",
      day: "numeric",
      weekday: "short",
      hour: "numeric",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(d)
      .map((p) => [p.type, p.value]),
  );
  return { y: Number(parts.year), m: Number(parts.month), d: Number(parts.day), wd: parts.weekday, h: Number(parts.hour), min: Number(parts.minute) };
}

/**
 * Auction clock line (feedRowState.ts): "Ending in 7m" (amber, under an hour),
 * "2h 11m left" (under a day), otherwise the end time in Miami time
 * ("Ends Thu, 12:41 AM"). Closed listings say so plainly. An unreadable end
 * time reads as ended (listingCardStatus fails closed).
 */
export function clockState(l: ListingLike, now: Date = new Date()): { text: string; tone: ClockTone } {
  const status = listingCardStatus(l, now);
  if (status === "SOLD") return { text: "Sold", tone: "muted" };
  if (status === "ENDED") return { text: l.auction_status === "cancelled" ? "Cancelled" : "Ended", tone: "muted" };
  if (status === "RESERVED") return { text: "On hold", tone: "normal" };
  const ends = new Date(l.ends_at);
  const minutes = Math.max(1, Math.floor((ends.getTime() - now.getTime()) / 60_000));
  if (minutes < 60) return { text: `Ending in ${minutes}m`, tone: "urgent" };
  if (minutes < 24 * 60) return { text: `${Math.floor(minutes / 60)}h ${minutes % 60}m left`, tone: "normal" };
  const p = marketParts(ends);
  const time = `${p.h % 12 === 0 ? 12 : p.h % 12}:${String(p.min).padStart(2, "0")} ${p.h >= 12 ? "PM" : "AM"}`;
  return { text: `Ends ${p.wd}, ${time}`, tone: "normal" };
}

/**
 * Home sections — the native rule (src/lib/home/sections.ts), with "today"
 * taken in Miami rather than on the server:
 *   event today → "Tonight" · next 1–7 days → "This week" · later → "Later"
 *   already happened or unparseable → null (no heading: never a borrowed name)
 */
export type HomeSection = "Tonight" | "This week" | "Later";

export function homeSection(isoDate: string, now: Date = new Date()): HomeSection | null {
  const [y, m, d] = isoDate.split("-").map(Number);
  if (!y || !m || !d || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const t = marketParts(now);
  const days = Math.round((Date.UTC(y, m - 1, d) - Date.UTC(t.y, t.m - 1, t.d)) / 86_400_000);
  if (days === 0) return "Tonight";
  if (days >= 1 && days <= 7) return "This week";
  if (days > 7) return "Later";
  return null;
}

/**
 * A recorded owner waiver of ticket proof (migration 156: proof_waived_at is stamped by the
 * database, proof_status stays pending_review). It is stated plainly and never shown as
 * verified; who waived it and why stay private.
 */
export const PROOF_WAIVED_NOTE = "Ticket proof waived by Snatch It";

export function proofWaiverNote(l: { proof_waived_at?: string | null }): string | null {
  return l.proof_waived_at ? PROOF_WAIVED_NOTE : null;
}

/**
 * The seller badge. Next to a waiver note a bare "Verified" could read as a verified ticket, so
 * on a waived listing it names what is verified: the seller.
 */
export function sellerVerifiedLabel(
  isVerifiedSeller: boolean | null | undefined,
  proofWaived: boolean,
): "Verified" | "Verified seller" | null {
  if (!isVerifiedSeller) return null;
  return proofWaived ? "Verified seller" : "Verified";
}

/**
 * "From a fan" describes a peer listing. A proof-waived listing is the platform owner's own
 * inventory by construction (156 only lets an admin waive proof on their own listing), so it
 * doesn't get the pill.
 */
export function showsFanBadge(l: { proof_waived_at?: string | null }): boolean {
  return !l.proof_waived_at;
}

/**
 * ISO start for structured data, with Miami's offset for that date (EDT −04:00 / EST −05:00).
 * Without it, crawlers read the wall-clock time as UTC or guess.
 */
export function eventStartIso(eventDate: string, eventTime: string): string {
  const time = /^\d{2}:\d{2}$/.test(eventTime) ? `${eventTime}:00` : eventTime;
  // The offset at ~that wall-clock moment (events are never in the 1–3 AM switch-over window
  // that would make this ambiguous by an hour).
  const probe = new Date(`${eventDate}T${time}Z`);
  if (Number.isNaN(probe.getTime())) return `${eventDate}T${time}`;
  const name = new Intl.DateTimeFormat("en-US", { timeZone: MARKET_TIME_ZONE, timeZoneName: "shortOffset" })
    .formatToParts(new Date(probe.getTime() + 5 * 3_600_000))
    .find((p) => p.type === "timeZoneName")?.value; // "GMT-4" / "GMT-5"
  const m = name?.match(/^GMT([+-])(\d{1,2})(?::(\d{2}))?$/);
  if (!m) return `${eventDate}T${time}`;
  return `${eventDate}T${time}${m[1]}${m[2].padStart(2, "0")}:${m[3] ?? "00"}`;
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
}

/**
 * Whether the event name already names the venue: the venue's name before any "(…)" detail,
 * matched as whole words (a letter, digit or underscore may not touch either end), ignoring
 * case. A plain substring test read venue "LIV" into "Olivia Rodrigo Night" and "Delivery Boys
 * Live".
 */
function namesVenue(eventName: string, venue: string): boolean {
  const venueBase = venue.split(" (")[0].trim();
  if (venueBase.length === 0) return false;
  return new RegExp(`(?<![\\p{L}\\p{N}_])${escapeRegExp(venueBase)}(?![\\p{L}\\p{N}_])`, "iu").test(eventName);
}

/**
 * "ANOTR at Watson Island Park": the event and where it is, without repeating a venue the event
 * name already carries ("… at Jolene Sound Room at Jolene Sound Room (…)"). The one source for
 * the page title, the social title, poster alt text and card link labels.
 */
export function eventAtVenue(eventName: string, venue: string): string {
  return namesVenue(eventName, venue) ? eventName : `${eventName} at ${venue}`;
}

/** Page/social title: the event and venue, then the date. */
export function listingTitle(eventName: string, venue: string, dateLabel: string): string {
  return `${eventAtVenue(eventName, venue)} — ${dateLabel}`;
}
