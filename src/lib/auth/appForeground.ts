/**
 * src/lib/auth/appForeground.ts — is the app the foreground app?
 *
 * Kept free of every import (React Native included) so the rule can be tested
 * directly. `inactive` matters as much as `background` here: that is the state
 * iOS reports while a 3-D Secure challenge sits in front of the app, and it is
 * the window in which the token refresh must be treated as stopped.
 */

export type ForegroundState = 'active' | 'background' | 'inactive' | (string & {});

export function isForeground(state: ForegroundState | null | undefined): boolean {
  return state === 'active';
}
