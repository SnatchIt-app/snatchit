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
};

// ─── Listing ──────────────────────────────────────────────────────────────────
export type Neighborhood =
  | 'south beach' | 'wynwood'       | 'brickell'     | 'downtown miami'
  | 'design district' | 'coconut grove' | 'little havana' | 'miami beach'
  | 'midtown';

export type TicketType     = 'GA' | 'VIP';
export type TransferMethod = 'mobile_transfer' | 'email';
export type DurationHours  = 1 | 3 | 6 | 12 | 24 | 48;

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
  amount:                    number;           // in cents
  service_fee:               number;           // in cents
  total:                     number;           // in cents
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

