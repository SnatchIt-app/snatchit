/**
 * SAMPLE DATA — the only data this preview ever renders.
 *
 * Nothing here comes from, or goes to, Supabase. Names are invented; ids are
 * prefixed `smp_` so they can never collide with a real row. The clock is
 * frozen at PREVIEW_NOW so "tonight", countdowns and staleness are
 * deterministic for reviewers and tests.
 */
import type {
  DoorPin,
  Event,
  FlagRow,
  InventoryBatch,
  InventoryHold,
  ManifestEpisode,
  OrderRow,
  Organization,
  RosterRow,
  ScanCounters,
  ScanDevice,
  TicketType,
  Venue,
} from "@/lib/types";

/** Saturday 12 Sep 2026, 22:30 in Miami (02:30Z Sunday). */
export const PREVIEW_NOW = new Date("2026-09-13T02:30:00Z");

export const ORG: Organization = { orgId: "smp_org_wynwood", displayName: "Wynwood Nights LLC (sample)" };
export const VENUE: Venue = {
  venueId: "smp_ven_room",
  orgId: ORG.orgId,
  name: "The Wynwood Room (sample)",
  neighborhood: "Wynwood, Miami",
  timeZone: "America/New_York",
  approvalStatus: "approved",
};

export const PREVIEW = { orgId: ORG.orgId, venueId: VENUE.venueId } as const;

// ---------------------------------------------------------------------------
// Events & sessions
// ---------------------------------------------------------------------------
export const EVENTS: Event[] = [
  {
    eventId: "smp_evt_sat_music",
    orgId: ORG.orgId,
    venueId: VENUE.venueId,
    title: "Saturday Music Night (sample)",
    status: "live",
    resaleMode: "face_value_queue",
    promoterCount: 2,
    sessions: [
      {
        sessionId: "smp_ses_sat_0912",
        eventId: "smp_evt_sat_music",
        label: null,
        startsAt: "2026-09-13T02:00:00Z", // 22:00 local
        doorsAt: "2026-09-13T01:00:00Z", // 21:00 local
        endsAt: "2026-09-13T08:00:00Z",
        status: "live",
        doorOpenAt: "2026-09-13T00:55:00Z", // manifest opened 20:55 local, before doors
      },
    ],
  },
  {
    eventId: "smp_evt_basel",
    orgId: ORG.orgId,
    venueId: VENUE.venueId,
    title: "Art Basel Warm-up (sample)",
    status: "on_sale",
    resaleMode: "off",
    promoterCount: 1,
    sessions: [
      { sessionId: "smp_ses_basel_1", eventId: "smp_evt_basel", label: "Friday", startsAt: "2026-12-05T03:00:00Z", doorsAt: "2026-12-05T02:00:00Z", endsAt: null, status: "scheduled", doorOpenAt: null },
      { sessionId: "smp_ses_basel_2", eventId: "smp_evt_basel", label: "Saturday", startsAt: "2026-12-06T03:00:00Z", doorsAt: "2026-12-06T02:00:00Z", endsAt: null, status: "scheduled", doorOpenAt: null },
    ],
  },
  {
    eventId: "smp_evt_reggaeton",
    orgId: ORG.orgId,
    venueId: VENUE.venueId,
    title: "Reggaeton Sundays (sample)",
    status: "announced",
    resaleMode: "off",
    promoterCount: 0,
    sessions: [{ sessionId: "smp_ses_regg_1", eventId: "smp_evt_reggaeton", label: null, startsAt: "2026-09-21T01:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }],
  },
  {
    eventId: "smp_evt_draft",
    orgId: ORG.orgId,
    venueId: VENUE.venueId,
    title: "Halloween Ball (sample draft)",
    status: "draft",
    resaleMode: "off",
    promoterCount: 0,
    sessions: [{ sessionId: "smp_ses_draft_1", eventId: "smp_evt_draft", label: null, startsAt: "2026-11-01T02:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }],
  },
  {
    eventId: "smp_evt_done",
    orgId: ORG.orgId,
    venueId: VENUE.venueId,
    title: "Labor Day Rooftop (sample)",
    status: "completed",
    resaleMode: "transfers_only",
    promoterCount: 3,
    sessions: [{ sessionId: "smp_ses_done_1", eventId: "smp_evt_done", label: null, startsAt: "2026-09-07T02:00:00Z", doorsAt: "2026-09-07T01:00:00Z", endsAt: "2026-09-07T07:00:00Z", status: "completed", doorOpenAt: "2026-09-07T01:02:00Z" }],
  },
  {
    eventId: "smp_evt_cancelled",
    orgId: ORG.orgId,
    venueId: VENUE.venueId,
    title: "Pop-up Comedy (sample, cancelled)",
    status: "cancelled",
    resaleMode: "off",
    promoterCount: 0,
    sessions: [{ sessionId: "smp_ses_cancel_1", eventId: "smp_evt_cancelled", label: null, startsAt: "2026-09-26T01:00:00Z", doorsAt: null, endsAt: null, status: "cancelled", doorOpenAt: null }],
  },
];

// ---------------------------------------------------------------------------
// Ticket types & inventory (Saturday Music Night is the fully populated event)
// ---------------------------------------------------------------------------
export const TICKET_TYPES: TicketType[] = [
  { ticketTypeId: "smp_tt_ga", eventId: "smp_evt_sat_music", name: "General admission", kind: "admission", priceMinor: 2500, visibility: "public" },
  { ticketTypeId: "smp_tt_early", eventId: "smp_evt_sat_music", name: "Early bird", kind: "admission", priceMinor: 1800, visibility: "hidden" },
  { ticketTypeId: "smp_tt_table", eventId: "smp_evt_sat_music", name: "VIP table (deposit)", kind: "table", priceMinor: 50000, visibility: "public" },
  { ticketTypeId: "smp_tt_door", eventId: "smp_evt_sat_music", name: "Door admission", kind: "admission", priceMinor: 3000, visibility: "door_only" },
  { ticketTypeId: "smp_tt_basel_ga", eventId: "smp_evt_basel", name: "General admission", kind: "admission", priceMinor: 4000, visibility: "public" },
  { ticketTypeId: "smp_tt_done_ga", eventId: "smp_evt_done", name: "General admission", kind: "admission", priceMinor: 2000, visibility: "public" },
];

export const BATCHES: InventoryBatch[] = [
  // GA: 300 public — 12 left → LOW
  { batchId: "smp_b_ga_pub", ticketTypeId: "smp_tt_ga", sessionId: "smp_ses_sat_0912", releaseKind: "public_sale", capacity: 300, held: 6, sold: 282, lowThreshold: 20 },
  // GA promoter hold: 40 all held, none sold → ALL HELD (not sold out)
  { batchId: "smp_b_ga_promo", ticketTypeId: "smp_tt_ga", sessionId: "smp_ses_sat_0912", releaseKind: "promoter_hold", capacity: 40, held: 40, sold: 0, lowThreshold: 5 },
  // Early bird: sold out (remaining 0 via sold)
  { batchId: "smp_b_early_pub", ticketTypeId: "smp_tt_early", sessionId: "smp_ses_sat_0912", releaseKind: "presale", capacity: 100, held: 0, sold: 100, lowThreshold: 10 },
  // VIP tables: 10, 7 sold, 1 held
  { batchId: "smp_b_table_pub", ticketTypeId: "smp_tt_table", sessionId: "smp_ses_sat_0912", releaseKind: "public_sale", capacity: 10, held: 1, sold: 7, lowThreshold: 2 },
  // Comps: 30, 22 issued
  { batchId: "smp_b_ga_comp", ticketTypeId: "smp_tt_ga", sessionId: "smp_ses_sat_0912", releaseKind: "comp", capacity: 30, held: 0, sold: 22, lowThreshold: 5 },
  // Door stock: 40 held back, 0 sold while live → DOOR UNTOUCHED
  { batchId: "smp_b_door", ticketTypeId: "smp_tt_door", sessionId: "smp_ses_sat_0912", releaseKind: "door", capacity: 40, held: 0, sold: 0, lowThreshold: 5 },
  // Art Basel Friday/Saturday
  { batchId: "smp_b_basel_1", ticketTypeId: "smp_tt_basel_ga", sessionId: "smp_ses_basel_1", releaseKind: "public_sale", capacity: 500, held: 12, sold: 143, lowThreshold: 50 },
  { batchId: "smp_b_basel_2", ticketTypeId: "smp_tt_basel_ga", sessionId: "smp_ses_basel_2", releaseKind: "public_sale", capacity: 500, held: 3, sold: 61, lowThreshold: 50 },
  // Completed event
  { batchId: "smp_b_done", ticketTypeId: "smp_tt_done_ga", sessionId: "smp_ses_done_1", releaseKind: "public_sale", capacity: 250, held: 0, sold: 231, lowThreshold: 25 },
];

export const HOLDS: InventoryHold[] = [
  { holdId: "smp_h_1", batchId: "smp_b_ga_pub", holder: "Checkout · cart 8f2c", quantity: 2, kind: "checkout", status: "active", expiresAt: "2026-09-13T02:38:00Z" },
  { holdId: "smp_h_2", batchId: "smp_b_ga_pub", holder: "Checkout · cart 1a9e", quantity: 4, kind: "checkout", status: "active", expiresAt: "2026-09-13T02:41:00Z" },
  { holdId: "smp_h_3", batchId: "smp_b_ga_promo", holder: "Promoter · Maya T.", quantity: 25, kind: "promoter", status: "active", expiresAt: "2026-09-13T03:00:00Z" },
  { holdId: "smp_h_4", batchId: "smp_b_ga_promo", holder: "Promoter · Dee K.", quantity: 15, kind: "promoter", status: "active", expiresAt: "2026-09-13T05:00:00Z" },
  { holdId: "smp_h_5", batchId: "smp_b_table_pub", holder: "Staff · box office", quantity: 1, kind: "staff", status: "active", expiresAt: "2026-09-13T04:00:00Z" },
  { holdId: "smp_h_6", batchId: "smp_b_ga_pub", holder: "Checkout · cart 77b1", quantity: 2, kind: "checkout", status: "expired", expiresAt: "2026-09-13T02:10:00Z" },
];

// ---------------------------------------------------------------------------
// Attendees — holder-keyed roster for tonight's session (spec §9.1)
// A six-ticket table order (purchaser "Camila R.") shows as six holders.
// ---------------------------------------------------------------------------
const S = "smp_ses_sat_0912";
export const ROSTER: RosterRow[] = [
  { customerRef: "WYN-0413", name: "Camila R.", isPurchaser: true, ticketsHeld: 1, ticketTypes: ["VIP table (deposit)"], source: "app", acquiredVia: "bought", checkIn: { kind: "admitted", at: "2026-09-13T01:22:00Z" }, promoter: null, email: "camila@example.test", sessionId: S },
  { customerRef: "WYN-0921", name: "Andrés P.", isPurchaser: false, ticketsHeld: 1, ticketTypes: ["VIP table (deposit)"], source: "app", acquiredVia: "transferred", checkIn: { kind: "admitted", at: "2026-09-13T01:23:00Z" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-0922", name: "Lucía M.", isPurchaser: false, ticketsHeld: 1, ticketTypes: ["VIP table (deposit)"], source: "app", acquiredVia: "transferred", checkIn: { kind: "not_scanned" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-0923", name: "Tomás V.", isPurchaser: false, ticketsHeld: 1, ticketTypes: ["VIP table (deposit)"], source: "app", acquiredVia: "transferred", checkIn: { kind: "admitted", at: "2026-09-13T01:40:00Z" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-0924", name: "Sofía A.", isPurchaser: false, ticketsHeld: 1, ticketTypes: ["VIP table (deposit)"], source: "app", acquiredVia: "transferred", checkIn: { kind: "not_scanned" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-0925", name: "Diego L.", isPurchaser: false, ticketsHeld: 1, ticketTypes: ["VIP table (deposit)"], source: "app", acquiredVia: "transferred", checkIn: { kind: "already_used", firstAt: "2026-09-13T01:41:00Z" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-1102", name: "Jordan K.", isPurchaser: true, ticketsHeld: 2, ticketTypes: ["General admission"], source: "promoter_link", acquiredVia: "bought", checkIn: { kind: "admitted", at: "2026-09-13T01:35:00Z" }, promoter: { name: "Maya T.", code: "MAYA10" }, email: "jordan@example.test", sessionId: S },
  { customerRef: "WYN-1188", name: "Priya S.", isPurchaser: true, ticketsHeld: 1, ticketTypes: ["Early bird"], source: "web", acquiredVia: "bought", checkIn: { kind: "refused", result: "frozen", at: "2026-09-13T01:50:00Z" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-1203", name: "Marcus B.", isPurchaser: false, ticketsHeld: 1, ticketTypes: ["General admission"], source: "app", acquiredVia: "comp", checkIn: { kind: "not_scanned" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-1240", name: "Elena G.", isPurchaser: true, ticketsHeld: 1, ticketTypes: ["General admission"], source: "door", acquiredVia: "bought", checkIn: { kind: "admitted", at: "2026-09-13T02:05:00Z" }, promoter: null, email: null, sessionId: S },
  { customerRef: "WYN-1301", name: "Noah W.", isPurchaser: true, ticketsHeld: 1, ticketTypes: ["General admission"], source: "promoter_link", acquiredVia: "bought", checkIn: { kind: "refused", result: "fraud_review", at: "2026-09-13T02:12:00Z" }, promoter: { name: "Dee K.", code: "DEEK" }, email: "noah@example.test", sessionId: S },
  { customerRef: "WYN-1355", name: "Ava C.", isPurchaser: true, ticketsHeld: 1, ticketTypes: ["General admission"], source: "web", acquiredVia: "bought", checkIn: { kind: "not_scanned" }, promoter: null, email: null, sessionId: S },
];

export const ORDERS: OrderRow[] = [
  { orderRef: "ORD-7A21", customerRef: "WYN-0413", buyerName: "Camila R.", status: "paid", totalMinor: 300000, refundedToDateMinor: 0, items: [{ ticketType: "VIP table (deposit)", qty: 6, unitPriceMinor: 50000 }], ticketsVoided: 0, paymentRefPresent: true, sessionId: S, paidAt: "2026-09-02T18:11:00Z" },
  { orderRef: "ORD-7B04", customerRef: "WYN-1102", buyerName: "Jordan K.", status: "paid", totalMinor: 5000, refundedToDateMinor: 0, items: [{ ticketType: "General admission", qty: 2, unitPriceMinor: 2500 }], ticketsVoided: 0, paymentRefPresent: true, sessionId: S, paidAt: "2026-09-08T22:40:00Z" },
  { orderRef: "ORD-7B77", customerRef: "WYN-1188", buyerName: "Priya S.", status: "paid", totalMinor: 1800, refundedToDateMinor: 0, items: [{ ticketType: "Early bird", qty: 1, unitPriceMinor: 1800 }], ticketsVoided: 0, paymentRefPresent: true, sessionId: S, paidAt: "2026-08-20T15:02:00Z" },
  { orderRef: "ORD-7C10", customerRef: "WYN-1240", buyerName: "Elena G.", status: "paid", totalMinor: 3000, refundedToDateMinor: 0, items: [{ ticketType: "Door admission", qty: 1, unitPriceMinor: 3000 }], ticketsVoided: 0, paymentRefPresent: true, sessionId: S, paidAt: "2026-09-13T02:04:00Z" },
  { orderRef: "ORD-7C11", customerRef: "WYN-1301", buyerName: "Noah W.", status: "paid", totalMinor: 2500, refundedToDateMinor: 0, items: [{ ticketType: "General admission", qty: 1, unitPriceMinor: 2500 }], ticketsVoided: 0, paymentRefPresent: true, sessionId: S, paidAt: "2026-09-10T01:15:00Z" },
  { orderRef: "ORD-7C12", customerRef: "WYN-1355", buyerName: "Ava C.", status: "paid", totalMinor: 2500, refundedToDateMinor: 0, items: [{ ticketType: "General admission", qty: 1, unitPriceMinor: 2500 }], ticketsVoided: 0, paymentRefPresent: true, sessionId: S, paidAt: "2026-09-11T20:30:00Z" },
  { orderRef: "ORD-6F90", customerRef: "WYN-0808", buyerName: "Ben O.", status: "refunded", totalMinor: 2500, refundedToDateMinor: 2500, items: [{ ticketType: "General admission", qty: 1, unitPriceMinor: 2500 }], ticketsVoided: 1, paymentRefPresent: true, sessionId: S, paidAt: "2026-09-05T12:00:00Z" },
  { orderRef: "ORD-6F91", customerRef: "WYN-0809", buyerName: "Rae T.", status: "partially_refunded", totalMinor: 5000, refundedToDateMinor: 2500, items: [{ ticketType: "General admission", qty: 2, unitPriceMinor: 2500 }], ticketsVoided: 1, paymentRefPresent: false, sessionId: S, paidAt: "2026-09-06T12:00:00Z" },
];

// ---------------------------------------------------------------------------
// Door — tonight's session
// ---------------------------------------------------------------------------
export const PINS: DoorPin[] = [
  { pinId: "smp_pin_1", label: "Main door iPad", sessionId: S, expiresAt: "2026-09-13T09:00:00Z", status: "active" },
  { pinId: "smp_pin_2", label: "Patio scanner", sessionId: S, expiresAt: "2026-09-13T09:00:00Z", status: "active" },
  { pinId: "smp_pin_3", label: "Temp — Chris (revoked)", sessionId: S, expiresAt: "2026-09-13T09:00:00Z", status: "revoked" },
];

export const DEVICES: ScanDevice[] = [
  { deviceId: "smp_dev_1", label: "Main door iPad", status: "active", online: true, lastSyncAt: "2026-09-13T02:28:30Z", offlineQueueDepth: 0, lastScanAt: "2026-09-13T02:29:10Z", admittedTonight: 233 },
  { deviceId: "smp_dev_2", label: "Patio scanner", status: "active", online: false, lastSyncAt: "2026-09-13T02:11:00Z", offlineQueueDepth: 7, lastScanAt: "2026-09-13T02:27:00Z", admittedTonight: 58 },
  { deviceId: "smp_dev_3", label: "Old Android (retired)", status: "retired", online: false, lastSyncAt: "2026-08-30T03:00:00Z", offlineQueueDepth: 0, lastScanAt: null, admittedTonight: 0 },
];

export const MANIFEST_EPISODES: ManifestEpisode[] = [
  { episodeId: "smp_ep_1", sessionId: S, openedAt: "2026-09-13T00:55:00Z", closedAt: null, openedBy: "Sam (venue manager)", reasonCode: null, entryCount: 411, admittedCount: 291 },
];

export const SCANS: ScanCounters = {
  issued: 411,
  admitted: 291,
  duplicate: 4,
  invalid: 3,
  frozen: 2,
  fraudReview: 1,
  lastScanAt: "2026-09-13T02:29:10Z",
  arrivalsPer5Min: [3, 8, 14, 22, 31, 28, 35, 40, 33, 26, 19, 14, 11, 7],
};

export const FLAGS: FlagRow[] = [
  { scanId: "smp_scan_9001", at: "2026-09-13T01:41:00Z", deviceLabel: "Main door iPad", result: "duplicate", note: "Second presentation of a table pass, 18 min after first admit", escalated: false },
  { scanId: "smp_scan_9002", at: "2026-09-13T02:12:00Z", deviceLabel: "Patio scanner", result: "fraud_review", note: "Pass flagged by risk rules; holder waited at the rope", escalated: true },
];

/** Recent operational activity — venue view (spec §17): plain sentences, no payloads. */
export const ACTIVITY: { at: string; who: string; what: string; reason: string | null }[] = [
  { at: "2026-09-13T02:04:00Z", who: "Box office (Ana)", what: "sold 1 × Door admission", reason: null },
  { at: "2026-09-13T00:55:00Z", who: "Sam (venue manager)", what: "opened the door manifest for tonight", reason: null },
  { at: "2026-09-12T23:10:00Z", who: "Sam (venue manager)", what: "issued door PIN “Patio scanner”", reason: null },
  { at: "2026-09-12T22:55:00Z", who: "Sam (venue manager)", what: "revoked door PIN “Temp — Chris”", reason: "staff_change" },
  { at: "2026-09-11T16:20:00Z", who: "Maya T. (promoter manager)", what: "allocated 25 comps", reason: "press" },
];
