/**
 * Domain vocabulary for the venue dashboard PREVIEW.
 *
 * Names follow docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md §1
 * (operator-facing words) and the physical objects it maps them to. Every
 * type here is a client-side projection of a spec'd table or read RPC; none
 * of it exists in production today (spec §0.1). The fixtures in
 * src/fixtures/venue.ts are the only source of instances.
 */

export type EventStatus = "draft" | "announced" | "on_sale" | "live" | "completed" | "cancelled";
export type SessionStatus = "scheduled" | "live" | "completed" | "cancelled";
export type ResaleMode = "off" | "transfers_only" | "fixed_cap" | "face_value_queue" | "buy_now" | "auction" | "offer";
export type TicketKind = "admission" | "table";
export type Visibility = "hidden" | "public" | "door_only";
export type ReleaseKind = "public_sale" | "promoter_hold" | "comp" | "door" | "presale";
export type HoldStatus = "active" | "converted" | "released" | "expired";
export type OrderStatus = "pending" | "paid" | "partially_refunded" | "refunded" | "cancelled";
export type OrderSource = "app" | "web" | "door" | "promoter_link";
export type AcquiredVia = "bought" | "transferred" | "comp";
export type ScanResult = "admitted" | "duplicate" | "invalid" | "frozen" | "fraud_review";
export type CheckIn = { kind: "not_scanned" } | { kind: "admitted"; at: string } | { kind: "already_used"; firstAt: string } | { kind: "refused"; result: Exclude<ScanResult, "admitted" | "duplicate">; at: string };
export type PinStatus = "active" | "revoked";
export type DeviceStatus = "active" | "retired";
export type DoorRejectReason = "version_stale" | "voided" | "listed_locked" | "refund_hold" | "duplicate" | "wrong_session";

export type Organization = { orgId: string; displayName: string };
export type Venue = { venueId: string; orgId: string; name: string; neighborhood: string; timeZone: string; approvalStatus: "draft" | "pending" | "approved" | "archived" };

export type EventSession = {
  sessionId: string;
  eventId: string;
  label: string | null;
  startsAt: string;
  doorsAt: string | null;
  endsAt: string | null;
  status: SessionStatus;
  /** catalog.event_session.door_open_at — the canonical door-freeze signal (spec §12.4). */
  doorOpenAt: string | null;
};

export type Event = {
  eventId: string;
  orgId: string;
  venueId: string;
  title: string;
  status: EventStatus;
  resaleMode: ResaleMode;
  /** null when the promoter table is not readable in the current data source. */
  promoterCount: number | null;
  sessions: EventSession[];
};

export type TicketType = {
  ticketTypeId: string;
  eventId: string;
  name: string;
  kind: TicketKind;
  /** Integer minor units (USD cents), spec §0.3 / §19.1. */
  priceMinor: number;
  visibility: Visibility;
};

/** venue.inventory_batch — one per (ticket type × session × release kind). */
export type InventoryBatch = {
  batchId: string;
  ticketTypeId: string;
  sessionId: string;
  releaseKind: ReleaseKind;
  capacity: number;
  held: number;
  sold: number;
  /** Low-inventory threshold for this batch (spec §22.8 leaves the source unresolved; fixture-supplied here). */
  lowThreshold: number;
  /** false when only `remaining` is known (database mode: capacity/held/sold are not client-readable, 081 E-29). */
  countersKnown?: boolean;
};

export type InventoryHold = {
  holdId: string;
  batchId: string;
  holder: string;
  quantity: number;
  kind: "staff" | "promoter" | "checkout";
  status: HoldStatus;
  expiresAt: string;
};

/** One row of the holder-keyed roster (spec §9.1). Column classes are enforced by lib/roles.ts. */
export type RosterRow = {
  customerRef: string; // IDENT — per-org pseudonym, never a global identity id
  name: string; // IDENT
  isPurchaser: boolean; // IDENT
  ticketsHeld: number; // IDENT
  ticketTypes: string[]; // OPS
  source: OrderSource; // OPS
  acquiredVia: AcquiredVia; // OPS
  checkIn: CheckIn; // OPS — finance roles are denied (D on venue.scan)
  promoter: { name: string; code: string } | null; // OPS
  email: string | null; // CONTACT — only where a per-order, per-org opt-in exists
  sessionId: string;
};

/** One row of the purchaser (money) view — the Refunds/orders surface (spec §9.1, §13.1). */
export type OrderRow = {
  orderRef: string;
  customerRef: string;
  buyerName: string;
  status: OrderStatus;
  totalMinor: number;
  refundedToDateMinor: number;
  items: { ticketType: string; qty: number; unitPriceMinor: number }[];
  ticketsVoided: number;
  paymentRefPresent: boolean;
  sessionId: string;
  paidAt: string;
};

export type DoorPin = { pinId: string; label: string; sessionId: string; expiresAt: string; status: PinStatus };
export type ScanDevice = {
  deviceId: string;
  label: string;
  status: DeviceStatus;
  online: boolean;
  lastSyncAt: string;
  offlineQueueDepth: number;
  lastScanAt: string | null;
  admittedTonight: number;
};
export type ManifestEpisode = { episodeId: string; sessionId: string; openedAt: string; closedAt: string | null; openedBy: string; reasonCode: string | null; entryCount: number; admittedCount: number };
export type ScanCounters = { issued: number; admitted: number; duplicate: number; invalid: number; frozen: number; fraudReview: number; lastScanAt: string | null; arrivalsPer5Min: number[] };
export type FlagRow = { scanId: string; at: string; deviceLabel: string; result: "duplicate" | "fraud_review"; note: string; escalated: boolean };
