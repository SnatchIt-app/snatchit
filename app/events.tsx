/**
 * app/events.tsx — primary sessions on sale (CONTRACTS C1; D's 182 `list_primary_sessions_on_sale`,
 * anon + authenticated, DARK until applied). Public: works signed out.
 *
 * The list rows carry instants only, so each row's date/time comes from that session's
 * `get_primary_session` facts (venue-local strings, zone named) — read in parallel for at most
 * `FACTS_LIMIT` rows; a row whose facts fail shows no time rather than a device-zone time
 * (A's time rule). The pop-up has one session; the limit only bounds a longer list. A request to
 * append `timezone` / `starts_at_local` to the list rows is with D/A.
 */
import { useFocusEffect } from '@react-navigation/native';
import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';

import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { discoveryRpc, readDiscovery, type DiscoveryLoad } from '@/src/lib/primary/discovery';
import { readPrimarySession, sessionRpc } from '@/src/lib/tickets/entitlementReads';
import { whenFromLocal, type WhenLine } from '@/src/lib/tickets/ticketWhen';
import { PrimaryEventsView } from '@/src/screens/primary/PrimaryEventsView';

const FACTS_LIMIT = 20;

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
    const ids = next.rows.slice(0, FACTS_LIMIT).map((r) => r.sessionId);
    const facts = await Promise.all(ids.map((id) => readPrimarySession(sessionRpc, id)));
    if (request !== requestRef.current) return;
    const map: Record<string, WhenLine | null> = {};
    ids.forEach((id, i) => {
      const f = facts[i];
      map[id] = f ? whenFromLocal({ startsAtLocal: f.startsAtLocal, doorsAtLocal: f.doorsAtLocal, timezone: f.timezone, startsAt: f.startsAt }) : null;
    });
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
