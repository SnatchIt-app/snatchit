/**
 * useNetworkStatus — live connectivity state via expo-network.
 *
 * `isOffline` is true only when the OS explicitly reports no connection
 * (null/undefined = unknown → treated as online so we never false-positive
 * the offline screen). Subscribes once per mount; safe on simulators.
 */

import { useEffect, useState } from 'react';
import * as Network from 'expo-network';

export function useNetworkStatus(): { isOffline: boolean } {
  const [isOffline, setIsOffline] = useState(false);

  useEffect(() => {
    let active = true;

    Network.getNetworkStateAsync()
      .then(s => { if (active) setIsOffline(s.isConnected === false); })
      .catch(() => { /* unknown → assume online */ });

    const sub = Network.addNetworkStateListener(s => {
      if (active) setIsOffline(s.isConnected === false);
    });

    return () => { active = false; sub.remove(); };
  }, []);

  return { isOffline };
}

/**
 * True when an error smells like a connectivity failure rather than a
 * server/application error (fetch throws before any HTTP response exists).
 */
export function isNetworkError(err: unknown): boolean {
  const msg =
    typeof err === 'string' ? err
    : err instanceof Error ? err.message
    : (err as { message?: string } | null)?.message ?? '';
  return /network request failed|failed to fetch|fetch failed|network error|abort/i.test(msg);
}
