export const APP_CONFIG = {
  // ── Marketplace fees (10/10 model) ──────────────────────────────────────
  // Buyer pays listing × (1 + BUYER_FEE_RATE) at checkout.
  // Seller receives listing × (1 − SELLER_FEE_RATE) on payout release.
  // Platform retains (BUYER_FEE_RATE + SELLER_FEE_RATE) × listing
  // (before Stripe processing fees).
  BUYER_FEE_RATE:  0.10,
  SELLER_FEE_RATE: 0.10,

  // Auction timing
  RESERVATION_MINUTES: 10,          // Buy Now reservation window
  BID_RATE_LIMIT_SECONDS: 3,        // Min seconds between bids (enforced server-side too)
  MIN_BID_INCREMENT: 5,             // Minimum bid increment in dollars

  // Upload limits (must match Supabase storage policies)
  MAX_IMAGE_SIZE_MB: 10,            // auction-media bucket
  MAX_AVATAR_SIZE_MB: 5,            // avatars bucket
  ALLOWED_IMAGE_TYPES: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],

  STRIPE_PUBLISHABLE_KEY: process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? '',
} as const;
