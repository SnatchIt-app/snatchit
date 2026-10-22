/**
 * app/(tabs)/create.tsx — Route wrapper
 * All UI lives in src/screens/CreateListingScreen.tsx
 *
 * The form is keyed by the signed-in account (A's integration review, 2026-10-21): when one account
 * signs out and another signs in on the same device, the key changes and React mounts a fresh screen,
 * so the previous account's unsaved text, cover and proof never carry over, and the draft autosave
 * never writes them under the next account's key. The persisted draft itself was already per-account.
 */
import { useAuth } from '@/src/hooks/useAuth';
import CreateListingScreen from '@/src/screens/CreateListingScreen';

export default function CreateRoute() {
  const { user } = useAuth();
  return <CreateListingScreen key={user?.id ?? 'signed-out'} />;
}
