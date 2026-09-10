/**
 * src/lib/auth/sessionAutoRefresh.ts — keep the session alive across backgrounding.
 *
 * THE BUG THIS FIXES. The client is created with `autoRefreshToken: true`, which
 * on its own only starts a JS `setInterval`. iOS suspends JS timers the moment
 * the app leaves the foreground, so the refresh loop silently stops. Supabase's
 * React Native guidance is therefore explicit: an AppState listener must call
 * `startAutoRefresh()` on `active` and `stopAutoRefresh()` when the app leaves.
 * Nothing in this app did that — `startAutoRefresh` appeared nowhere in the
 * source.
 *
 * WHY IT SURFACED AT 3-D SECURE. The challenge hands off to a browser, which
 * backgrounds the app for as long as the buyer takes to authorise. The refresh
 * loop stops there. On return the access token can already be past its lifetime,
 * the refresh never fired, and `getSession()` fails; `useAuth` reads that as a
 * stale token and signs the person out. The visible result is exactly what was
 * reported: Home still showing a buyer it rendered while the session was alive,
 * `Buy Now` correctly refusing because `user?.id` is now null, and a relaunch
 * landing on the sign-in screen. Consistent with the auth log, which shows three
 * password logins in seven minutes and NOT ONE refresh-token grant.
 *
 * This does not weaken authentication. It does not extend a session, suppress an
 * expiry, or fabricate a user. It only lets the refresh the client was already
 * configured to perform actually run when the app is in front of the person.
 */

import { AppState, type AppStateStatus } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { isForeground } from './appForeground';

export { isForeground };

/**
 * Wire the refresh loop to the foreground. Returns the unsubscribe function.
 * Safe to call more than once; each call owns its own subscription.
 */
export function startSessionAutoRefresh(): () => void {
  // Start only if the app is actually in front. A push-launched shell can
  // mount while backgrounded; the loop then waits for the first 'active'.
  if (isForeground(AppState.currentState)) supabase.auth.startAutoRefresh();

  const sub = AppState.addEventListener('change', (state: AppStateStatus) => {
    if (isForeground(state)) supabase.auth.startAutoRefresh();
    else supabase.auth.stopAutoRefresh();
  });

  return () => {
    sub.remove();
    supabase.auth.stopAutoRefresh();
  };
}
