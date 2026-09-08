/**
 * src/lib/venue/types.ts — types for the venue-native (direct) ticketing surface.
 *
 * These mirror the deployed Phase-2 schema (migrations 076-092). They are inert
 * until the `venue` and `catalog` schemas are exposed through PostgREST and the
 * `feature.native_issuance_enabled` flag is turned on. Neither has happened, and
 * neither is authorized by this work.
 *
 * Vocabulary rule: the customer-facing words are "direct" (sold by the event) and
 * "marketplace" (sold by another fan), per snatchitapp.com. Internal schema words
 * (atom, batch, shard, rail) never reach a screen.
 */

/** Canonical venue staff roles (migration 080). There is no venue_door or venue_promoter. */
export type VenueRole =
  | 'venue_manager'
  | 'venue_finance'
  | 'venue_box_office'
  | 'venue_marketing'
  | 'venue_promoter_manager'
  | 'venue_scanner';

/** Canonical organization roles (migration 077). */
export type OrgRole =
  | 'org_owner'
  | 'org_admin'
  | 'org_finance'
  | 'org_marketing'
  | 'org_promoter_manager'
  | 'org_member';

export type EventStatus = 'draft' | 'published' | 'cancelled' | 'postponed';

/** venue.ticket_type.kind — CHECK (kind in ('admission','table')) at 081:37. */
export type TicketTypeKind = 'admission' | 'table';

/** venue.ticket_type.visibility — CHECK at 081:41-42. `door_only` is box-office inventory. */
export type TicketTypeVisibility = 'hidden' | 'public' | 'door_only';

/** venue.inventory_batch.release_kind — CHECK at 081:63-64. */
export type ReleaseKind = 'public_sale' | 'promoter_hold' | 'comp' | 'door' | 'presale';

export type OrderStatus = 'pending' | 'paid' | 'cancelled' | 'expired' | 'refunded';

export interface Organization {
  orgId: string;
  legalName: string;
  displayName: string;
  status: string;
}

export interface Venue {
  venueId: string;
  orgId: string;
  name: string;
  neighborhood: string | null;
  address: string | null;
  status: string;
}

export interface EventSession {
  sessionId: string;
  eventId: string;
  sessionLabel: string | null;
  startsAt: string;
  endsAt: string | null;
  doorsAt: string | null;
  status: string;
}

export interface VenueEvent {
  eventId: string;
  venueId: string;
  orgId: string;
  title: string;
  status: EventStatus;
  heroImageRef: string | null;
  sessions: EventSession[];
}

export interface TicketType {
  ticketTypeId: string;
  eventId: string;
  kind: TicketTypeKind;
  name: string;
  /** Minor units (cents). Money never travels as a float. */
  priceMinor: number;
  currency: string;
  visibility: TicketTypeVisibility;
}

/**
 * The columns a client may actually SELECT (081:1014-1016). Raw `capacity`,
 * `held` and `sold` are withheld from every client role by column grant; venue
 * staff read them through an RPC result, never a table read. `remaining` is a
 * generated column and IS granted, so it is the only count a client can see.
 */
export interface InventoryBatchRow {
  batchId: string;
  ticketTypeId: string;
  eventSessionId: string;
  releaseKind: ReleaseKind;
  isSharded: boolean;
  remaining: number;
}

/** A reservation returned by venue.reserve_primary_inventory. Expires on a TTL. */
export interface InventoryHold {
  holdId: string;
  batchId: string;
  quantity: number;
  expiresAt: string;
}

export interface CheckoutItem {
  ticketTypeId: string;
  quantity: number;
  unitPriceMinor: number;
}

export interface PrimaryOrder {
  orderId: string;
  sessionId: string;
  orgId: string;
  status: OrderStatus;
  totalMinor: number;
  currency: string;
  items: CheckoutItem[];
}

/**
 * Provenance is a first-class product concept, not a styling detail. Every
 * purchasable thing the app shows must declare which of these it is.
 */
export type Provenance = 'direct' | 'marketplace';

export interface PurchaseOption {
  provenance: Provenance;
  /** ticket_type_id for direct, listing id for marketplace. */
  refId: string;
  label: string;
  priceMinor: number;
  currency: string;
  /**
   * Coarse band for display. Note: the exact `remaining` count IS readable by
   * any authenticated client through the column grant (081:1014-1016), so this
   * band is a presentation choice, not a confidentiality control. Do not claim
   * inventory levels are private.
   */
  availability: 'available' | 'low' | 'sold_out';
}

/** Every Phase-2 RPC returns jsonb with a status discriminator. */
export interface RpcOk<T> {
  ok: true;
  data: T;
}

export interface RpcErr {
  ok: false;
  /** Normalized code, e.g. 'precondition_failed', 'insufficient_privilege'. */
  code: string;
  /** Safe to show a user. Never a raw Postgres string. */
  message: string;
}

export type RpcResult<T> = RpcOk<T> | RpcErr;
