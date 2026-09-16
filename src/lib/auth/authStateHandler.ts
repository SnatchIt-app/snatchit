/**
 * src/lib/auth/authStateHandler.ts — what the app does on every Supabase auth
 * state change, as a pure function of injected deps so it can run against the
 * real GoTrueClient in a test.
 *
 * Why this is synchronous (Build 17 blocking finding, 2026-09-16): auth-js runs
 * `signOut()` inside its lock and awaits every onAuthStateChange callback
 * before releasing it. A callback that awaits `getSession()` queues behind the
 * sign-out that is waiting on it, the lock is never released, and every later
 * data request (which awaits the session for its bearer token) hangs until the
 * process is killed — Home and Profile "loading forever" after sign-out →
 * sign-in. So the callback returns before anything is awaited; the stale-token
 * diagnostic runs deferred, after the lock is gone.
 */

import type { AuthChangeEvent, Session } from '@supabase/supabase-js';

export interface AuthStateDeps {
  setSession(session: Session | null): void;
  /** A SIGNED_OUT the user did not ask for is an expiry for the login screen (CFT-607). */
  markExpired(): void;
  /** The auth error message from `getSession()`, or null. */
  getSessionError(): Promise<string | null>;
  isStaleTokenError(message: string): boolean;
  clearStaleSession(reason: string): Promise<void>;
  staleHandled: { current: boolean };
  warnEmitted(): boolean;
  /** Run `fn` after the current auth operation has released its lock. */
  defer(fn: () => void): void;
}

export function handleAuthStateChange(event: AuthChangeEvent, session: Session | null, deps: AuthStateDeps): void {
  deps.setSession(session);
  if (event === 'SIGNED_OUT' && session === null) deps.markExpired();
  if (event === 'SIGNED_OUT' && session === null && !deps.staleHandled.current && !deps.warnEmitted()) {
    // Never awaited here: see the header. Runs after the auth lock is released.
    deps.defer(() => { void runStaleDiagnostic(deps); });
  }
}

/** Best-effort stale-token diagnostic; safe to run at any time after the callback returned. */
export async function runStaleDiagnostic(deps: AuthStateDeps): Promise<void> {
  try {
    const msg = await deps.getSessionError();
    if (msg && deps.isStaleTokenError(msg)) {
      deps.staleHandled.current = true;
      await deps.clearStaleSession(msg);
    }
  } catch {
    // Ignore — user may already be deleted (account deletion flow).
  }
}
