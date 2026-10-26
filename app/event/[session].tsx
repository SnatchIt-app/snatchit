/**
 * app/event/[session].tsx — one primary event session (CONTRACTS C1; D's 182 `get_primary_session`,
 * anon + authenticated, DARK until applied). Public: works signed out (deep link `snatchit://event/<id>`).
 *
 * One read, quiet on focus once something is on screen. 0 rows is "not available" (no existence
 * leak); a failure is the failure screen. A failed re-read keeps the event on screen.
 */
import { useFocusEffect } from '@react-navigation/native';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';

import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { primarySessionRpc, readPrimarySessionDetail, type SessionDetailLoad } from '@/src/lib/primary/discovery';
import { PrimarySessionView } from '@/src/screens/primary/PrimarySessionView';

export default function PrimaryEventRoute() {
  const { session } = useLocalSearchParams<{ session?: string }>();
  const sessionId = typeof session === 'string' ? session : '';
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(isOffline);
  useEffect(() => { offlineRef.current = isOffline; }, [isOffline]);

  const [load, setLoad] = useState<SessionDetailLoad>({ kind: 'loading' });
  const [refreshing, setRefreshing] = useState(false);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const requestRef = useRef(0);

  const read = useCallback(async () => {
    const request = ++requestRef.current;
    const next = await readPrimarySessionDetail(primarySessionRpc, sessionId, offlineRef.current);
    if (request !== requestRef.current) return;
    setNowMs(Date.now());
    // A failed re-read keeps the event on screen; only a first read becomes the failure screen.
    setLoad((prev) => (prev.kind === 'ready' && next.kind === 'failed' ? prev : next));
  }, [sessionId]);

  useEffect(() => { setLoad({ kind: 'loading' }); void read(); }, [read]);
  useFocusEffect(useCallback(() => { void read(); }, [read]));

  async function onRefresh() {
    setRefreshing(true);
    await read();
    setRefreshing(false);
  }

  return (
    <PrimarySessionView
      load={load}
      nowMs={nowMs}
      refreshing={refreshing}
      onRefresh={onRefresh}
      onBack={() => (router.canGoBack() ? router.back() : router.replace('/(tabs)/home'))}
    />
  );
}
