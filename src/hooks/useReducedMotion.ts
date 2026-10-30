/**
 * src/hooks/useReducedMotion.ts — the OS "reduce motion" setting, live.
 *
 * WHY NOT `useReducedMotion` FROM REANIMATED
 * That hook reads the system value ONCE at module load and never re-renders when
 * the setting changes — its own doc says so. A user who turns the setting on
 * while the app is backgrounded would keep getting animation until a cold start.
 * React Native's own `AccessibilityInfo` emits a change event, so this hook stays
 * correct for the life of the process. No dependency is added either way: this is
 * React Native core, and Reanimated remains installed and available.
 */

import { useEffect, useState } from 'react';
import { AccessibilityInfo } from 'react-native';

export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((v) => { if (alive) setReduced(v); })
      // A failed probe must not disable the interface. Assume motion is fine.
      .catch(() => {});
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduced);
    return () => { alive = false; sub.remove(); };
  }, []);

  return reduced;
}
