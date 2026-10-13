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
