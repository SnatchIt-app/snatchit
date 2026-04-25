/**
 * src/hooks/useAuth.ts
 * Subscribes to Supabase auth state and exposes { session, user, loading }.
 *
 * Usage:
 *   const { session, user, loading } = useAuth();
 *
 * - `loading` is true only during the initial session check.
 * - `session` is null when the user is logged out.
 * - `user`    is a shortcut to session?.user ?? null.
 *
 * Stale-token safety:
 *   If Supabase returns "Invalid Refresh Token" or "Refresh Token Not Found"
 *   (e.g. token revoked server-side or AsyncStorage had a leftover session),
 *   we call signOut() to wipe storage, set session to null, and emit a
 *   one-time console.warn so the app never gets stuck in a broken auth state.
 */

import { Session, User } from '@supabase/supabase-js';
import { useEffect, useRef, useState } from 'react';

import { supabase } from '@/src/lib/supabase';

type AuthState = {
  session: Session | null;
  user: User | null;
  loading: boolean;
};

// ─── Stale-token helpers ──────────────────────────────────────────────────────

/** Error substrings that identify a revoked / missing refresh token. */
const STALE_TOKEN_PHRASES = [
  'Invalid Refresh Token',
  'Refresh Token Not Found',
] as const;

/**
 * Module-level flag — the warn fires at most once per app-process lifetime,
 * regardless of how many times the hook mounts.
 */
let _staleWarnEmitted = false;

function isStaleTokenError(message: string): boolean {
  return STALE_TOKEN_PHRASES.some((p) => message.includes(p));
}

/**
 * Clears the stale session from AsyncStorage and emits a one-time warn.
 * Safe to call multiple times — only warns once.
 */
async function clearStaleSession(reason: string): Promise<void> {
  if (!_staleWarnEmitted) {
    _staleWarnEmitted = true;
    console.warn(
      '[useAuth] Stale refresh token detected — signing out automatically.',
      reason,
    );
  }
  // Best-effort: wipe the stored tokens so the next getSession() returns null.
  // Ignore any network / auth error from signOut itself.
  await supabase.auth.signOut().catch(() => {});
}

// ─────────────────────────────────────────────────────────────────────────────

export function useAuth(): AuthState {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  // Tracks whether we've already handled a stale-token event in THIS hook
  // instance so we don't double-call clearStaleSession if both paths fire.
  const staleHandledRef = useRef(false);

  useEffect(() => {
    // Step 1: Read the cached session (may trigger a token refresh if the
    //         access token is already expired).  If the stored refresh token
    //         is stale, Supabase returns an AuthApiError here; we sign out to
    //         clear storage and resolve loading=false so the app can continue.
    supabase.auth.getSession().then(async ({ data: { session }, error }) => {
      if (error && isStaleTokenError(error.message)) {
        if (!staleHandledRef.current) {
          staleHandledRef.current = true;
          await clearStaleSession(error.message);
        }
        setSession(null);
      } else {
        setSession(session ?? null);
      }
      setLoading(false);
    });

    // Step 2: Keep state in sync whenever the user signs in/out or the token
    //         is refreshed automatically.
    //         When background auto-refresh fails with a stale token, the SDK
    //         internally calls signOut() and fires SIGNED_OUT with session=null.
    //         We mirror the session change and emit our one-time warn so there
    //         is a clear, actionable message in the console instead of the raw
    //         AuthApiError that the SDK logs.
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (event, newSession) => {
      // Update session state FIRST so navigation reacts immediately.
      // The stale-token check below is a diagnostic side-effect that should
      // never delay the UI transition to the login screen.
      setSession(newSession);

      if (
        event === 'SIGNED_OUT' &&
        newSession === null &&
        !staleHandledRef.current &&
        !_staleWarnEmitted
      ) {
        // Best-effort stale-token diagnostic — runs after state is already
        // updated so it can't block navigation.
        try {
          const { error: chk } = await supabase.auth.getSession();
          if (chk && isStaleTokenError(chk.message)) {
            staleHandledRef.current = true;
            await clearStaleSession(chk.message);
          }
        } catch {
          // Ignore — user may already be deleted (account deletion flow).
        }
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  return {
    session,
    user: session?.user ?? null,
    loading,
  };
}
