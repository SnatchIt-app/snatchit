/**
 * src/screens/checkout/CheckoutEntry.native.tsx
 *
 * Native platform resolution target. Re-exports the real Stripe checkout, so
 * @stripe/stripe-react-native is reachable from the bundle ONLY on native.
 */
export { default } from './CheckoutNative';
