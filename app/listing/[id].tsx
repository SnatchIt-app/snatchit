/**
 * app/listing/[id].tsx — Route wrapper
 * Reads the dynamic [id] segment and passes it to ListingDetailScreen.
 */
import { useLocalSearchParams } from 'expo-router';
import ListingDetailScreen from '@/src/screens/ListingDetailScreen';

export default function ListingRoute() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <ListingDetailScreen id={id} />;
}
