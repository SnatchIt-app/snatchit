/**
 * src/lib/auth/recoveryHold.ts — the password-recovery hold, held for the whole process.
 *
 * The hold says "a recovery link is being handled; put the person on New password and keep the phase
 * router away". It used to be RootLayout's useState. On a cold start Expo Router can unmount and
 * replace the root layout while the first instance's deep-link dispatch is still in flight (production
 * T1, 2026-10-16: a replace issued before the Stack mounted). The link's claim is process-wide
 * (claimAuthParamOnce), so the replacement's dispatch is refused, and the first instance then raised the
 * hold into a dead component: the session arrived with no hold and the person landed on Home. Holding it
 * here gives the hold the same lifetime as the claim, so every root instance reads the same value.
 *
 * It grants nothing: it only routes. The session still comes only from the auth exchange.
 */
import { useSyncExternalStore } from 'react';

let held = false;
const listeners = new Set<() => void>();

export function getRecoveryHold(): boolean {
  return held;
}

export function setRecoveryHold(next: boolean): void {
  if (held === next) return;
  held = next;
  for (const listener of [...listeners]) listener();
}

export function subscribeRecoveryHold(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

/** RootLayout's view of the hold: the same [value, setter] shape the useState it replaces had. */
export function useRecoveryHold(): [boolean, (next: boolean) => void] {
  return [useSyncExternalStore(subscribeRecoveryHold, getRecoveryHold, getRecoveryHold), setRecoveryHold];
}
