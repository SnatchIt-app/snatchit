export const APP_CONFIG = {
  // Fees
  SERVICE_FEE_RATE: 0.05,           // 5% service fee on all transactions

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
