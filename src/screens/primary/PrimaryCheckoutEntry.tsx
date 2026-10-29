/**
 * src/screens/primary/PrimaryCheckoutEntry.tsx — the base (non-native) primary checkout entry.
 *
 * Metro resolves PrimaryCheckoutEntry.native.tsx on native and THIS file everywhere else, so the web
 * bundle never imports @stripe/stripe-react-native (same split as src/screens/checkout/CheckoutEntry).
 * Primary checkout runs in the mobile app; web says so and sends the buyer back to the event.
 */
import { router, useLocalSearchParams } from 'expo-router';

import { EmptyState } from '@/src/components/ui';

export default function PrimaryCheckoutWeb() {
  const { session } = useLocalSearchParams<{ session?: string }>();
  return (
    <EmptyState
      title="Open the app to buy tickets"
      body="Ticket checkout runs in the Snatch It app."
      action={{ label: 'Back to event', onPress: () => router.replace(session ? `/event/${session}` : '/(tabs)/home') }}
    />
  );
}
