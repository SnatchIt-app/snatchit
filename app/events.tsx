/**
 * app/events.tsx — primary sessions on sale (CONTRACTS C1; D's 182 `list_primary_sessions_on_sale`,
 * anon + authenticated, DARK until applied). Public: works signed out.
 *
 * Each row's date/time comes from the row itself: 182 returns the venue `timezone` and the venue-local
 * `starts_at_local` / `doors_at_local` on every list row, so the list makes no per-row session read (D trace
 * DSC-C8; it used to read up to 20). The venue-local text is shown as sent and labelled with the venue zone
 * (EST/EDT), never converted; a row without it shows no time rather than a device-zone time (A's time rule).
 */
import { useFocusEffect } from '@react-navigation/native';
import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';

import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { discoveryRpc, readDiscovery, type DiscoveryLoad } from '@/src/lib/primary/discovery';
import { whenFromLocal, type WhenLine } from '@/src/lib/tickets/ticketWhen';
import { PrimaryEventsView } from '@/src/screens/primary/PrimaryEventsView';

export default function PrimaryEventsRoute() {
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(isOffline);
  useEffect(() => { offlineRef.current = isOffline; }, [isOffline]);

  const [load, setLoad] = useState<DiscoveryLoad>({ kind: 'loading' });
  const [whenBySession, setWhenBySession] = useState<Record<string, WhenLine | null>>({});
  const [refreshing, setRefreshing] = useState(false);
  const requestRef = useRef(0);

  const read = useCallback(async () => {
    const request = ++requestRef.current;
    const next = await readDiscovery(discoveryRpc, offlineRef.current);
    if (request !== requestRef.current) return;
    setLoad((prev) => (prev.kind === 'ready' && next.kind === 'failed' ? prev : next));
    if (next.kind !== 'ready') return;
    const map: Record<string, WhenLine | null> = {};
    // whenFromLocal answers null for a row without venue-local text.
    for (const r of next.rows) map[r.sessionId] = whenFromLocal({ startsAtLocal: r.startsAtLocal, doorsAtLocal: r.doorsAtLocal, timezone: r.timezone, startsAt: r.startsAt });
    setWhenBySession(map);
  }, []);

  useEffect(() => { void read(); }, [read]);
  useFocusEffect(useCallback(() => { void read(); }, [read]));

  async function onRefresh() {
    setRefreshing(true);
    await read();
    setRefreshing(false);
  }

  return (
    <PrimaryEventsView
      load={load}
      whenBySession={whenBySession}
      refreshing={refreshing}
      onRefresh={onRefresh}
      onOpen={(sessionId) => router.push(`/event/${sessionId}`)}
      onBack={() => (router.canGoBack() ? router.back() : router.replace('/(tabs)/home'))}
    />
  );
}
