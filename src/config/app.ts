import { BUYER_FEE_RATE, SELLER_FEE_RATE } from '@/src/lib/money';

import { envValue } from './envValue';

export const APP_CONFIG = {
  // ── Marketplace fees (10/10 model) ──────────────────────────────────────
  // Buyer pays listing × (1 + BUYER_FEE_RATE) at checkout.
  // Seller receives listing × (1 − SELLER_FEE_RATE) on payout release.
  // Platform retains (BUYER_FEE_RATE + SELLER_FEE_RATE) × listing
  // (before Stripe processing fees).
  //
  // RE-EXPORTED, not restated (A's direction, 2026-09-24). These were a second pair of literals
  // beside `src/lib/money.ts`'s, which is what every fee CALCULATION reads and what the server's own
  // rate must agree with. Two literals for one rate can drift by one edit; a re-export cannot. The
  // value is unchanged at 0.10 — this changes where it comes from, not what it is.
  BUYER_FEE_RATE,
  SELLER_FEE_RATE,

  // Auction timing
  RESERVATION_MINUTES: 10,          // Buy Now reservation window
  BID_RATE_LIMIT_SECONDS: 3,        // Min seconds between bids (enforced server-side too)
  MIN_BID_INCREMENT: 5,             // Minimum bid increment in dollars

  // Upload limits (must match Supabase storage policies)
  MAX_IMAGE_SIZE_MB: 10,            // auction-media bucket
  MAX_AVATAR_SIZE_MB: 5,            // avatars bucket
  ALLOWED_IMAGE_TYPES: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],

  // envValue() strips whitespace and wrapping quotes, straight OR curly. A key
  // pasted with smart quotes is non-empty but malformed, which previously failed
  // silently at boot and only surfaced as a network timeout when the payment
  // sheet tried to load. See src/config/envValue.ts.
  STRIPE_PUBLISHABLE_KEY: envValue(process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY),
} as const;
