/**
 * app/bid/[id].tsx — Route wrapper
 * Reads the dynamic [id] segment (listing id) and passes it to PlaceBidScreen.
 */
import { useLocalSearchParams } from 'expo-router';
import PlaceBidScreen from '@/src/screens/PlaceBidScreen';

export default function BidRoute() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <PlaceBidScreen id={id} />;
}
