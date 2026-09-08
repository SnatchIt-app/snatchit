/**
 * src/lib/auth/onboardingGate.ts — holds the root redirect while Sign up finishes.
 *
 * The root layout sends anyone with a session to Home. Sign up creates the account
 * at step 1, which means the session appears while there are still three steps to
 * go: without this the person would be thrown onto Home mid signup and their name,
 * number and answer would be lost.
 *
 * So Sign up raises this flag before it calls `signUp`, and lowers it when the flow
 * ends (finished, failed, or the screen unmounted). It gates NOTHING else: it does
 * not affect who is signed in, what they can reach, or any permission. It only says
 * "a screen is mid flow, do not navigate for it".
 *
 * A module-level flag rather than context, because the reader is the root layout,
 * which sits above every provider a screen could mount.
 */

import { useSyncExternalStore } from 'react';

let active = false;
const listeners = new Set<() => void>();

export function isOnboarding(): boolean {
  return active;
}

export function setOnboarding(next: boolean): void {
  if (active === next) return;
  active = next;
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

/** Reactive read for the root layout. */
export function useIsOnboarding(): boolean {
  return useSyncExternalStore(subscribe, isOnboarding, isOnboarding);
}
