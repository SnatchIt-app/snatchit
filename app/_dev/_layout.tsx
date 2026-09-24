/**
 * app/_dev/_layout.tsx — ONE gate over every development gallery and rendering harness.
 *
 * Each `_dev` route has so far carried its own build-gate line, and a survey on 2026-09-24 found
 * the predictable result of per-file guards: three routes with the full sandbox-or-dev gate, one
 * with a dev-only variant, all present but none uniform. This layout puts the gate where a new
 * route cannot forget it — a production bundle (`__DEV__` false, and `IS_SANDBOX_BUILD` false
 * because the env guard's three conjuncts fail on a production pairing) redirects out of the
 * whole segment before any child renders. The per-route guards stay; they cost nothing and keep
 * each file honest on its own, but reachability no longer depends on them.
 *
 * D flagged the per-file pattern (2026-09-24). The specific claim that two routes were ungated
 * was wrong — foundation.tsx:206 and transfer-states.tsx:103 both redirect — but the structural
 * point was right, and this is the fix for the next file rather than the last one.
 */
import { Redirect, Slot } from 'expo-router';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';

declare const __DEV__: boolean;

export default function DevSegmentGate() {
  if (!(IS_SANDBOX_BUILD || __DEV__)) return <Redirect href="/(tabs)/home" />;
  return <Slot />;
}
