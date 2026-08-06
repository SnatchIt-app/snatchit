/**
 * src/types/index.ts
 * TypeScript types mirroring the Supabase database schema.
 * Keep in sync with supabase/schema.sql.
 */

// ─── Profile ──────────────────────────────────────────────────────────────────
// Run the provided SQL block to add any missing columns to public.profiles.
export type Profile = {
  id:                  string;
  created_at:          string;
  // Legacy columns (may exist in older projects)
  full_name:           string | null;
  phone:               string | null;
  // Columns used by the Profile tab screen
  display_name:        string | null;   // ADD COLUMN IF NOT EXISTS
  phone_number:        string | null;   // ADD COLUMN IF NOT EXISTS
  avatar_url:          string | null;   // legacy full-URL column
  avatar_path:         string | null;   // storage path → getPublicUrl
  is_verified_buyer:   boolean;         // ADD COLUMN IF NOT EXISTS
  is_verified_seller:  boolean;         // ADD COLUMN IF NOT EXISTS
  wallet_balance:      number;          // ADD COLUMN IF NOT EXISTS
  bio:                 string | null;   // ADD COLUMN IF NOT EXISTS
  preferred_neighborhoods: string[];   // ADD COLUMN IF NOT EXISTS
  // Stripe Connect (seller side)
  stripe_connect_id:          string | null;   // migration 002
  stripe_onboarding_complete: boolean;         // migration 017
  // Stripe Customer (buyer side) — saved cards / PaymentSheet (migration 026)
  stripe_customer_id:         string | null;
};

/**
 * Return shape of the get_my_profile() RPC.
 *
 * The RPC is SECURITY DEFINER and returns the caller's own row only
 * (WHERE p.id = auth.uid()), which is why it is unaffected by the column
 * grants on public.profiles. Column privileges in Postgres are per-role, not
 * per-row, so once a sensitive column is revoked from `authenticated` a direct
 * `.from('profiles').select(...)` stops returning it even for your own row.
 * Every self-profile read goes through this instead.
 *
 * Exactly the 14 columns the function returns — deliberately NOT `Profile`.
 * Absent here and unread anywhere in the app: phone, stripe_customer_id,
 * is_admin, stripe_charges_enabled, stripe_payouts_enabled,
 * stripe_connect_status, trust_status_override.
 */
export type MyProfileRPC = Pick<
  Profile,
  | 'id'
  | 'full_name'
  | 'display_name'
  | 'phone_number'
  | 'is_verified_buyer'
  | 'is_verified_seller'
  | 'created_at'
  | 'avatar_path'
  | 'avatar_url'
  | 'bio'
  | 'wallet_balance'
  | 'stripe_connect_id'
  | 'stripe_onboarding_complete'
  | 'preferred_neighborhoods'
>;

// ─── Listing ──────────────────────────────────────────────────────────────────
// Areas + named venues. Stored as lowercase text in listings.neighborhood.
// Grouping/labels live in src/constants/neighborhoods.ts.
export type Neighborhood =
  // Areas (original 9)
  | 'south beach' | 'wynwood' | 'brickell' | 'downtown miami'
  | 'design district' | 'coconut grove' | 'little havana' | 'miami beach'
  | 'midtown'
  // Areas (migration 033 expansion)
  | 'little river' | 'little haiti' | 'hialeah' | 'doral' | 'kendall'
  | 'coral gables' | 'aventura' | 'sunny isles' | 'fort lauderdale' | 'hollywood'
  // Venues — clubs & nightlife
  | 'club space' | 'e11even' | 'liv' | 'm2 miami' | 'factory town'
  // Venues — arenas, stadiums & live music
  | 'kaseya center' | 'hard rock stadium' | 'loandepot park'
  | 'fpl solar amphitheater' | 'bayfront park' | 'hard rock live'
  | 'amerant bank arena' | 'chase stadium' | 'the fillmore miami beach'
  | 'miami beach bandshell';

export type TicketType     = 'GA' | 'VIP';
export type TransferMethod = 'mobile_transfer' | 'email';
export type DurationHours  = 1 | 3 | 6 | 12 | 24 | 48;

// ── Event category (migration 033) — Snatch It is a full event marketplace ──
export type EventCategory =
  | 'nightlife' | 'clubs' | 'concerts' | 'festivals'
  | 'sports' | 'music' | 'special_events' | 'other';

// ── Proof-of-ownership review state (migration 033) ─────────────────────────
export type ProofStatus = 'pending_review' | 'approved' | 'rejected';

// ── Phase A: V1 Transfer Enhancement types (migration 011) ──────────────────
// Expanded in migration 033 from official-source research
// (see TRANSFER_METHOD_RESEARCH.md — only confirmed platforms are listed).
export type TicketPlatform =
  | 'dice' | 'eventbrite' | 'posh' | 'axs' | 'ticketmaster' | 'other'
  | 'seatgeek' | 'tixr' | 'fever' | 'shotgun' | 'universe'
  | 'see_tickets' | 'mlb_ballpark' | 'stubhub' | 'vivid_seats' | 'gametime';

export type DisputeReason =
  | 'never_received'
  | 'wrong_tickets'
  | 'invalid_tickets'
  | 'partial_delivery';

export type DisputeResolution =
  | 'resolved_seller_paid'
  | 'resolved_buyer_refunded'
  | 'resolved_partial_refund';

// Reservation / sale lifecycle state for a listing.
export type ListingStatus = 'active' | 'reserved' | 'sold';

export type Listing = {
  id:               string;
  created_at:       string;
  seller_id:        string;

  event_name:       string;
  venue:            string;
  neighborhood:     Neighborhood;
  event_date:       string;   // "YYYY-MM-DD"
  event_time:       string;   // "HH:MM:SS"

  ticket_type:      TicketType;
  quantity:         number;
  transfer_method:  TransferMethod;
  restrictions:     string | null;

  starting_bid:     number;
  buy_now_enabled:  boolean;
  buy_now_price:    number | null;
  duration_hours:   DurationHours;

  starts_at:        string;   // ISO timestamptz
  ends_at:          string;   // ISO timestamptz
  current_bid:      number;

  cover_image_path: string;   // storage path, e.g. "uuid/covers/1715000000000.jpg"

  // ── Phase A: V1 Transfer Enhancement fields (migration 011) ───────────────
  ticket_platform:                TicketPlatform;              // required, defaults to 'other'
  proof_of_ownership_path:        string | null;               // storage path to proof screenshot
  seller_commitment_accepted_at:  string | null;               // ISO timestamptz, null = not accepted

  // ── Marketplace expansion (migration 033) ─────────────────────────────────
  category:                       EventCategory;               // defaults to 'nightlife'
  proof_status:                   ProofStatus;                 // admin review state; badge only when 'approved'

  // ── Reservation / sale fields (added by migration) ────────────────────────
  status:           ListingStatus;        // 'active' | 'reserved' | 'sold'
  reserved_by:      string | null;        // uuid of user holding reservation
  reserved_until:   string | null;        // ISO timestamptz, null when not reserved
  sold_at:          string | null;        // ISO timestamptz, null until sold
  updated_at:       string;               // auto-maintained by trigger

  // ── Bid tracking (denormalised for fast reads) ───────────────────────────
  bid_count:            number;                      // incremented by validate_and_apply_bid
  highest_bidder_id:    string | null;               // uuid of current highest bidder

  // ── Auction intelligence fields (added by finalize_auction migration) ─────
  auction_status:       'active' | 'ended' | 'sold' | 'cancelled'; // separate from buy-now status
  winner_user_id:       string | null;               // uuid of winning bidder
  winning_bid_amount:   number | null;               // winning bid in cents
  ended_at:             string | null;               // ISO timestamptz when finalized
};

// ─── Bid ──────────────────────────────────────────────────────────────────────
export type Bid = {
  id:         string;
  created_at: string;
  listing_id: string;
  bidder_id:  string;
  amount:     number;
  // Joined via select '*, profiles(display_name, avatar_url)'.
  // full_name is deliberately absent: bid history is visible to every bidder
  // on a listing, so embedding another user's legal name published it to
  // strangers. It is also being revoked from the `authenticated` role, and a
  // revoked column in a PostgREST embed fails the whole query with 42501.
  profiles?:  Pick<Profile, 'display_name' | 'avatar_url'> | null;
};

// ─── Push Notifications ────────────────────────────────────────────────────────

export type PushToken = {
  id:          string;
  user_id:     string;
  token:       string;
  platform:    'ios' | 'android';
  device_name: string | null;
  created_at:  string;
  last_used:   string | null;
  is_active:   boolean;
};

export type NotificationPreferences = {
  user_id:                string;
  notify_outbid:          boolean;
  notify_auction_ending:  boolean;
  notify_auction_won:     boolean;
  notify_auction_lost:    boolean;
  notify_reservation_exp: boolean;
  notify_listing_sold:    boolean;
  updated_at:             string;
};

// ─── Payments ────────────────────────────────────────────────────────────────

export type PaymentStatus = 'pending' | 'processing' | 'succeeded' | 'failed' | 'refunded';
export type PaymentMode = 'buy_now' | 'auction';

export type Payment = {
  id:                        string;
  listing_id:                string;
  buyer_id:                  string;
  seller_id:                 string;
  /** Listing price in cents (what seller listed). */
  amount:                    number;
  /** 10% buyer fee in cents — added on top of `amount`. (Renamed from
   *  service_fee in migration 022.) */
  buyer_fee:                 number;
  /** 10% seller fee in cents — withheld from seller payout at release. */
  seller_fee:                number;
  /** Card charge total in cents = amount + buyer_fee. */
  total:                     number;
  stripe_payment_intent_id:  string | null;
  stripe_client_secret:      string | null;
  status:                    PaymentStatus;
  payment_method:            string | null;    // 'card', 'apple_pay', 'google_pay'
  mode:                      PaymentMode;      // 'buy_now' | 'auction'
  created_at:                string;
  paid_at:                   string | null;
  failed_at:                 string | null;
  refunded_at:               string | null;
};

// ─── Transfer (migration 002 + 006–009 + 011) ──────────────────────────────

export type TransferStatus =
  | 'pending'
  | 'seller_sent'
  | 'buyer_confirmed'
  | 'disputed'
  | 'expired'
  | 'auto_released'
  | 'reversed';          // migration 024 — Stripe transfer reversal

// Risk-based payout (migration 039)
export type PayoutRiskTier = 'low' | 'medium' | 'high';
export type PayoutReviewStatus = 'held' | 'manual_review';

export type Transfer = {
  id:                     string;
  created_at:             string;

  // References
  listing_id:             string;
  payment_id:             string;
  seller_id:              string;
  buyer_id:               string;

  // Transfer details
  transfer_method:        TransferMethod;
  status:                 TransferStatus;

  // Core timestamps
  seller_sent_at:         string | null;
  buyer_confirmed_at:     string | null;
  expires_at:             string;
  expired_at:             string | null;     // migration 007
  disputed_at:            string | null;     // migration 009

  // Payout tracking (migration 006)
  payout_released_at:     string | null;
  stripe_transfer_id:     string | null;

  // Auto-release (migration 008)
  auto_release_at:        string | null;

  // ── Phase A: V1 Transfer Enhancement fields (migration 011) ───────────────
  delivery_email:         string | null;     // buyer-provided email for ticket delivery
  delivery_phone:         string | null;     // buyer-provided phone for ticket delivery
  transfer_evidence_path: string | null;     // storage path to seller's transfer proof
  dispute_reason:         DisputeReason | null;
  dispute_evidence_path:  string | null;     // storage path to buyer's dispute proof
  dispute_notes:          string | null;
  dispute_resolution:     DisputeResolution | null;
  dispute_resolved_at:    string | null;
  dispute_resolved_by:    string | null;     // admin user id

  // ── Risk-based payout (migration 039) ─────────────────────────────────────
  buyer_viewed_at:        string | null;     // buyer opened transfer screen
  payout_hold_until:      string | null;     // medium-risk hold deadline
  payout_risk_tier:       PayoutRiskTier | null;
  payout_reason_codes:    string[] | null;
  payout_review_status:   PayoutReviewStatus | null;
};

// Audit row for every payout decision (migration 039; service-role only).
export type PayoutDecision = {
  id:              string;
  transfer_id:     string;
  payment_id:      string | null;
  seller_id:       string | null;
  buyer_id:        string | null;
  risk_tier:       PayoutRiskTier;
  decision:        'release' | 'hold' | 'manual_review' | 'refund';
  reason_codes:    string[];
  evidence:        Record<string, unknown>;
  buyer_confirmed: boolean;
  dispute_open:    boolean;
  event_date:      string | null;
  hold_until:      string | null;
  actor:           string;
  decided_at:      string;
};

// ─── RPC Argument Types (migration 011) ─────────────────────────────────────
// These types mirror the Postgres function signatures so callsites get
// compile-time safety. Optional params match DEFAULT NULL in the SQL.

export type SetTransferDeliveryInfoArgs = {
  p_transfer_id:     string;
  p_delivery_email?: string | null;
  p_delivery_phone?: string | null;
};

export type MarkTransferSentArgs = {
  p_transfer_id:              string;
  p_user_id:                  string;
  p_transfer_evidence_path?:  string | null;
};

export type BuyerDisputeTransferArgs = {
  p_transfer_id:           string;
  p_user_id?:              string | null;
  p_dispute_reason?:       string | null;
  p_dispute_evidence_path?: string | null;
  p_dispute_notes?:        string | null;
};

export type AdminResolveDisputeArgs = {
  p_transfer_id: string;
  p_resolution:  string;
  p_admin_id:    string;
};

// ── Phase B: Anti-Fraud & Seller Risk types (migration 012) ────────────────

export type FlagType =
  | 'same_event_overload'
  | 'high_dispute_rate'
  | 'high_dispute_loss_rate'
  | 'duplicate_proof'
  | 'duplicate_evidence'
  | 'rapid_send'
  | 'new_account_high_value'
  | 'high_listing_velocity'
  | 'missing_payout_setup'
  | 'repeated_expiry';

export type FlagSeverity = 'info' | 'warning' | 'critical';

export type FlagResolution =
  | 'dismissed'
  | 'warned'
  | 'listing_blocked'
  | 'seller_suspended'
  | 'escalated';

export type RiskTier = 'low' | 'medium' | 'high' | 'critical';

export type SellerFlag = {
  id:               string;
  created_at:       string;
  seller_id:        string;
  flag_type:        FlagType;
  severity:         FlagSeverity;
  details:          string | null;
  listing_id:       string | null;
  transfer_id:      string | null;
  reviewed_at:      string | null;
  reviewed_by:      string | null;
  resolution:       FlagResolution | null;
  resolution_notes: string | null;
};

// ── Phase D: Soft Enforcement types (migration 013) ──────────────────────────

export type CanCreateListingReason =
  | 'ok'
  | 'medium_risk_warning'
  | 'high_risk_warning'
  | 'critical_risk'
  | 'listing_blocked';

export type CanCreateListingResponse = {
  allowed:   boolean;
  reason:    CanCreateListingReason;
  risk_tier: RiskTier | null;
};

export type SellerRiskScore = {
  seller_id:              string;
  updated_at:             string;
  account_age_days:       number;
  total_listings:         number;
  active_listings:        number;
  total_completed:        number;
  total_disputes:         number;
  total_dispute_losses:   number;
  total_expired:          number;
  rapid_send_count:       number;
  duplicate_proof_count:  number;
  duplicate_evidence_count: number;
  dispute_rate:           number;
  dispute_loss_rate:      number;
  expiry_rate:            number;
  risk_tier:              RiskTier;
  open_flags_count:       number;
  critical_flags_count:   number;
  is_listing_blocked:     boolean;
  listing_blocked_at:     string | null;
  listing_blocked_reason: string | null;
};

// ─── UGC moderation (migration 023) ──────────────────────────────────────────

export type ReportTargetType = 'listing' | 'user';

export type ReportReason =
  | 'fraud_or_scam'
  | 'counterfeit_or_invalid'
  | 'inappropriate_content'
  | 'misleading'
  | 'harassment'
  | 'other';

export type ReportStatus = 'pending' | 'reviewing' | 'actioned' | 'dismissed';

export type Report = {
  id:           string;
  reporter_id:  string;
  target_type:  ReportTargetType;
  target_id:    string;
  reason:       ReportReason;
  notes:        string | null;
  status:       ReportStatus;
  created_at:   string;
  resolved_at:  string | null;
};

export type UserBlock = {
  blocker_id: string;
  blocked_id: string;
  created_at: string;
};

// ─── Stripe disputes (migration 024) ──────────────────────────────────────────

export type DisputeStatus =
  | 'warning_needs_response'
  | 'warning_under_review'
  | 'warning_closed'
  | 'needs_response'
  | 'under_review'
  | 'won'
  | 'lost'
  | 'charge_refunded';

export type Dispute = {
  id:                  string;
  stripe_dispute_id:   string;
  stripe_charge_id:    string;
  stripe_pi_id:        string | null;
  payment_id:          string | null;
  transfer_id:         string | null;
  amount:              number;       // cents
  currency:            string;
  reason:              string;
  status:              DisputeStatus;
  evidence_due_by:     string | null;
  created_at:          string;
  updated_at:          string;
};

// ─── Stripe webhook event dedup (migration 025) ───────────────────────────────

export type StripeWebhookEvent = {
  event_id:     string;
  event_type:   string;
  received_at:  string;
  processed:    boolean;
  processed_at: string | null;
  last_error:   string | null;
  retry_count:  number;
};

// ─── Profile trust metrics (migration 029) ────────────────────────────────────
// One-row payload from get_profile_trust_stats RPC. Marketplace-safe — never
// includes email, phone, Stripe IDs, transaction amounts, or wallet data.

export type ProfileTrustStats = {
  completed_sales:            number;
  completed_purchases:        number;
  active_listings:            number;
  disputes_opened:            number;
  disputes_lost:              number;
  seller_terminal_total:      number;  // denominator for transfer success rate
  seller_terminal_successful: number;  // numerator   for transfer success rate
  member_since:               string | null;
};

export type SellerReputationTier =
  | 'new_seller'      // < 5 completed sales — insufficient marketplace history
  | 'trusted'         // 5+   sales, 95%+ success, 0 lost disputes
  | 'top'             // 25+  sales, 98%+ success, 0 lost disputes
  | 'elite'           // 100+ sales, 99%+ success, 0 lost disputes
  | 'needs_review';   // any lost dispute OR success rate below tier floor

