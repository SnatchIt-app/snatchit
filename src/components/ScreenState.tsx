/**
 * ScreenState — full-screen fallback states for network-dependent screens.
 *
 * Distinct states (never one screen for every failure):
 *   loading — the Spinner (Reduce Motion aware)
 *   offline — StateView 'offline' + Retry (auto-retries when connection returns)
 *   error   — StateView 'error' + Retry
 *
 * Empty and no-match states are StateView 'empty' / 'noMatch' (EmptyState keeps
 * its screen-specific copy). Screens render this only with nothing cached to
 * show; a failed quiet refresh keeps the rows.
 */

import { useEffect, useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { Spinner, StateView } from '@/src/components/ui';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { STATE_COPY } from '@/src/lib/ui/loadState';

export type ScreenStateKind = 'loading' | 'offline' | 'error';

type Props = {
  state: ScreenStateKind;
  /** Called on Retry tap — and automatically when connectivity returns. */
  onRetry?: () => void | Promise<void>;
};

export default function ScreenState({ state, onRetry }: Props) {
  const { isOffline } = useNetworkStatus();
  const [retrying, setRetrying] = useState(false);
  const wasOffline = useRef(isOffline);

  async function retry() {
    if (!onRetry || retrying) return;
    setRetrying(true);
    try { await onRetry(); } finally { setRetrying(false); }
  }

  // Auto-retry the moment the connection comes back.
  useEffect(() => {
    if (state === 'offline' && wasOffline.current && !isOffline) retry();
    wasOffline.current = isOffline;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOffline, state]);

  if (state === 'loading') {
    return (
      <View style={s.wrap}>
        <Spinner />
      </View>
    );
  }

  return (
    <View style={s.wrap}>
      <StateView
        kind={state}
        action={onRetry ? { label: STATE_COPY[state].retry, onPress: retry, busy: retrying } : undefined}
      />
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
