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

/**
 * "Sat, Oct 24 · 9:30 PM EDT". The seller enters the event's date and time as a wall clock, and the sell form
 * says it is Eastern Time. So the label is the EST/EDT that applies at that wall clock. The stored values are
 * never converted or rewritten (A, 2026-11-02; the app does the same).
 */
export function eventWhen(l: Pick<ListingLike, "event_date" | "event_time">): string {
  const zone = marketWallClockZone(l.event_date, l.event_time);
  return `${fmtEventDay(l.event_date)} · ${fmtEventTime(l.event_time)}${zone ? ` ${zone}` : ""}`;
}

/**
 * The EST/EDT label for an Eastern wall clock (date "YYYY-MM-DD", time "HH:MM[:SS]"). A time that happens twice
 * (the fall-back hour) or does not exist (the spring-forward hour) gets "ET": it is not known which one the seller
 * meant. An unreadable date or time gets no label.
 */
export function marketWallClockZone(date: string, time: string): string | null {
  const dm = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date ?? "");
  const tm = /^(\d{2}):(\d{2})/.exec(time ?? "");
  if (!dm || !tm) return null;
  const [y, mo, d, h, mi] = [dm[1], dm[2], dm[3], tm[1], tm[2]].map(Number);
  if (h > 23 || mi > 59) return null;
  const asUtc = Date.UTC(y, mo - 1, d, h, mi);
  // Eastern is UTC−4 (EDT) or UTC−5 (EST): keep each candidate instant whose Eastern wall clock reads back as entered.
  const zones = [4, 5]
    .map((hours) => marketParts(new Date(asUtc + hours * 3_600_000)))
    .filter((p) => p.y === y && p.m === mo && p.d === d && p.h === h && p.min === mi)
    .map((p) => p.tz);
  return zones.length === 1 ? zones[0] : "ET";
}

/** "2 × GA" · "1 × VIP" · "6 × Table" */
export function quantityLine(l: Pick<ListingLike, "quantity" | "ticket_type">): string {
  const type = l.ticket_type === "TABLE" ? "Table" : l.ticket_type;
  return `${l.quantity} × ${type}`;
}

export type ClockTone = "urgent" | "normal" | "muted";

/** Event dates and end times are Miami-local by product definition; the web server runs on UTC. */
export const MARKET_TIME_ZONE = "America/New_York";

function marketParts(d: Date): { y: number; m: number; d: number; wd: string; h: number; min: number; tz: string } {
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
      timeZoneName: "short",
    })
      .formatToParts(d)
      .map((p) => [p.type, p.value]),
  );
  return { y: Number(parts.year), m: Number(parts.month), d: Number(parts.day), wd: parts.weekday, h: Number(parts.hour), min: Number(parts.minute), tz: parts.timeZoneName };
}

/*
 * Snatch It operates in Eastern Time (owner decision, 2026-11-02). These read an instant in MARKET_TIME_ZONE,
 * never in the runtime zone: the web server runs on UTC and a buyer's browser can run anywhere, so a bare
 * toLocaleDateString() or getFullYear() gives a different day on each side.
 */
const pad2 = (n: number) => String(n).padStart(2, "0");

/** The Miami (Eastern) calendar date at an instant: 2026-11-02T04:59:59Z → "2026-11-01". */
export function marketDateISO(now: Date): string {
  const p = marketParts(now);
  return `${p.y}-${pad2(p.m)}-${pad2(p.d)}`;
}

/** The Miami (Eastern) year at an instant: 2027-01-01T04:59:59Z → 2026. */
export function marketYear(now: Date): number {
  return marketParts(now).y;
}

/** "November 2026" in Miami time. */
export function marketMonthYear(iso: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone: MARKET_TIME_ZONE, month: "long", year: "numeric" }).format(new Date(iso));
}

/** "Nov 1" in Miami time. */
export function marketShortDate(iso: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone: MARKET_TIME_ZONE, month: "short", day: "numeric" }).format(new Date(iso));
}

/**
 * Auction clock line (feedRowState.ts): "Ending in 7m" (amber, under an hour),
 * "2h 11m left" (under a day), otherwise the end time in Miami time with its
 * EST/EDT label ("Ends Thu, 12:41 AM EDT"). Closed listings say so plainly. An unreadable end
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
  return { text: `Ends ${p.wd}, ${time} ${p.tz}`, tone: "normal" };
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
