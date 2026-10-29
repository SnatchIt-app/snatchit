/**
 * app/primary-checkout/[session].tsx — the primary ticket checkout route (CONTRACTS C3).
 * Params: tt (ticket type uuid), qty (1–10), attempt (set by the screen; carried by the 3-D Secure return URL).
 * Delegates to PrimaryCheckoutRoute, which selects the platform entry (see CheckoutRoute for why).
 */
export { default } from '@/src/screens/primary/PrimaryCheckoutRoute';
