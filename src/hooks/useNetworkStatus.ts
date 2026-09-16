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

// The classification itself is pure and lives with the state copy.
export { isNetworkError } from '@/src/lib/ui/loadState';
