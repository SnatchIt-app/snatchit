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

// ─── Listing ──────────────────────────────────────────────────────────────────
export type Neighborhood =
  | 'south beach' | 'wynwood'       | 'brickell'     | 'downtown miami'
  | 'design district' | 'coconut grove' | 'little havana' | 'miami beach'
  | 'midtown';

export type TicketType     = 'GA' | 'VIP';
export type TransferMethod = 'mobile_transfer' | 'email';
export type DurationHours  = 1 | 3 | 6 | 12 | 24 | 48;

// ── Phase A: V1 Transfer Enhancement types (migration 011) ──────────────────
export type TicketPlatform = 'dice' | 'eventbrite' | 'posh' | 'axs' | 'ticketmaster' | 'other';

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
  // Joined via select '*, profiles(full_name, display_name, avatar_url)'
  profiles?:  Pick<Profile, 'full_name' | 'display_name' | 'avatar_url'> | null;
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
  | 'auto_released';

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
  | 'new_seller'      // < 1 terminal transfer — insufficient data
  | 'excellent'       // 0 lost disputes AND success rate >= 95%
  | 'good'            // success rate >= 85%
  | 'fair'            // success rate >= 70%
  | 'needs_review';   // success rate < 70%

