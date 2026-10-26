/**
 * src/screens/primary/PrimaryCheckoutRoute.tsx — the primary checkout route's component, one level
 * removed from the bracketed route file so the platform-split entry resolves for every tool (the same
 * indirection as src/screens/checkout/CheckoutRoute.tsx).
 */
import PrimaryCheckoutEntry from './PrimaryCheckoutEntry';

export default function PrimaryCheckoutRoute() {
  return <PrimaryCheckoutEntry />;
}
