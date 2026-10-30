/**
 * app/checkout/index.tsx — the landing for a bare `snatchit://checkout` link.
 *
 * WHY THIS FILE EXISTS. `initPaymentSheet` was given `returnURL:
 * 'snatchit://checkout'`, but `app/checkout/` contained only `[id].tsx`. A 3-D
 * Secure challenge therefore redirected the device back into the app at a route
 * that MATCHED NOTHING, and expo-router rendered its default unmatched screen —
 * the one that says the page does not exist and offers a sitemap link. That is
 * the "404" a buyer saw after authorising a real, successful payment.
 *
 * The return URL now carries the listing id, so the normal path lands on
 * `checkout/[id]` and this file is never reached. It stays as the floor: a bare
 * or truncated link can no longer strand anyone on a developer screen, and it
 * NEVER claims a payment outcome it has not verified. Checkout owns settlement;
 * this screen only sends the person somewhere real.
 */

import { Redirect } from 'expo-router';

export default function CheckoutIndex() {
  // No listing in the URL means there is nothing to settle here. Home re-reads
  // the buyer's state from the server, so a payment that did land shows up as
  // a sold listing and an order rather than as a dead end.
  return <Redirect href="/(tabs)/home" />;
}
