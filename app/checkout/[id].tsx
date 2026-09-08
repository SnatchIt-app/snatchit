/**
 * app/checkout/[id].tsx — Checkout route.
 *
 * Delegates to CheckoutRoute (a non-bracketed module) which selects the platform
 * entry. The indirection exists because the eslint TS import resolver does not
 * apply React Native platform suffixes when the importer is a bracketed route
 * file, so this file imports a plain .tsx and CheckoutRoute imports the split.
 * Metro and tsc resolve the split directly either way.
 */
export { default } from '@/src/screens/checkout/CheckoutRoute';
