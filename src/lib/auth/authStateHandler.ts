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
 *
 * Why the callback's RETURN VALUE matters (D's review, 2026-09-16): auth-js
 * awaits whatever the subscriber returns. If a future change makes this
 * handler async again, wrapping the call in `void` at the hook would hide the
 * deadlock from the library while leaving every data request hung — that is
 * exactly how the first draft of the regression test failed to reproduce the
 * bug. Keep the handler synchronous, keep the hook returning its value, and
 * keep tests/auth-signout-deadlock.test.ts driving the real client: those
 * tests, not the source pin, are what catch the async + void regression pair.
 */

import type { AuthChangeEvent, Session } from '@supabase/supabase-js';
import { clearDockAvatar } from '@/src/lib/nav/dockAvatar';

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
  // EVERY sign-out drops the dock's published avatar, including the SIGNED_OUT events auth-js
  // originates itself (a failed background refresh), which never pass through performSignOut's
  // own clear. The store's render guard already refuses a mismatched user id, so this closes a
  // retention residue, not a rendering hole (avatar diagnosis, 2026-09-24). `dockAvatar` is
  // dependency-free by design, so this import adds nothing behind the auth path.
  if (event === 'SIGNED_OUT' && session === null) clearDockAvatar();
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
