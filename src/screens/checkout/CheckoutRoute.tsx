/**
 * src/screens/checkout/CheckoutRoute.tsx
 *
 * The checkout route's component, one level removed from the bracketed route file
 * so the platform-split entry resolves for every tool. Metro picks
 * CheckoutEntry.native.tsx on native and CheckoutEntry.tsx elsewhere, which keeps
 * @stripe/stripe-react-native out of the web bundle.
 */
import CheckoutEntry from './CheckoutEntry';

export default function CheckoutRoute() {
  return <CheckoutEntry />;
}
