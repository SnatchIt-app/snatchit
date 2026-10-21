/**
 * src/hooks/useReturnToCapture.ts — the root layout's view of where the person is, for return after sign-in
 * (CFT-603, slice 1). It never navigates.
 *
 * 1. It writes the current pathname into the root's own ref. The root routing effect reads that ref when its
 *    decision navigates (to remember the screen a first signed-out route or an expiry is leaving), so the
 *    effect's dependency list stays exactly as pinned (K6) and a change of pathname never re-runs the root router.
 * 2. When a signed-out person ENTERS an allowlisted public screen — a link opened while signed out, or "Place a
 *    bid" from a listing — it remembers that screen with no owner. It runs on a change of pathname only, so the
 *    render in which a session expires (same screen, new phase) can never overwrite the expiry capture the
 *    routing effect makes for that user.
 * 3. It writes expo-router's navigation container into the root's own ref (review RAS-1), so a sign-in that
 *    returns to a remembered screen can open it with the tabs under it (returnToNav.ts) — again without adding
 *    to the pinned dependency list.
 *
 * Kept out of app/_layout.tsx so the root's pinned expo-router import line stays as it is.
 */
import { useNavigationContainerRef, usePathname } from 'expo-router';
import { useEffect, useRef } from 'react';

import { captureReturnTo, shouldCaptureOnEntry } from '@/src/lib/auth/returnTo';
import type { RootNavigation } from '@/src/lib/auth/returnToNav';
import type { AuthPhase } from '@/src/lib/auth/rootRoute';

export interface ReturnToCaptureInput {
  /** The phase this render sees. */
  phase: AuthPhase;
  /** Recovery or sign up is holding the root; nothing is remembered meanwhile. */
  held: boolean;
  /** The phase the root last navigated for (RootLayout's own ref), read when the pathname changes. */
  routedPhaseRef: { readonly current: AuthPhase | null };
  /** RootLayout's ref for the current pathname, written on every render. */
  pathnameRef: { current: string | null };
  /** RootLayout's ref for expo-router's navigation container, written on every render. */
  navigationRef: { current: RootNavigation | null };
}

export function useReturnToCapture(input: ReturnToCaptureInput): void {
  const pathname = usePathname();
  input.pathnameRef.current = pathname;
  input.navigationRef.current = useNavigationContainerRef();
  // The latest phase and hold, read by the entry effect without making them reasons to re-run it.
  const inputRef = useRef(input);
  inputRef.current = input;

  useEffect(() => {
    const { phase, held, routedPhaseRef } = inputRef.current;
    if (shouldCaptureOnEntry({ phase, held, routedPhase: routedPhaseRef.current })) captureReturnTo(pathname, null);
  }, [pathname]);
}
