/**
 * The two App Review seed accounts (the demo SELLER and BUYER created by scripts/seed-demo.ts, identified in
 * production by auth user_metadata `source: 'seed-demo'`; ids from A's production read, 2026-10-14).
 *
 * Owner instruction (relayed by A, 2026-10-14): take their 8 SOLD demo listings out of public discovery by
 * FILTERING, without changing any status or record. The only public read of sold listings is Home's
 * "Recently sold" chip, and that read is the only user of this constant. Every user-history surface — the
 * seller's My Listings, the own-profile sold stats, the buyer's Bids and purchases, the Tickets RPC — reads by
 * the user's own id and does NOT use this list, so the involved users still see their own history.
 * Pinned by tests/home-live-feed-filter.test.ts (LF6, LF7).
 */
export const APP_REVIEW_SEED_SELLER_IDS: readonly string[] = [
  '09f1ec06-2bd5-45de-8851-2dd8af08d4eb',
  'c0b2d630-b48e-43e2-b749-d5dcbc907067',
];
