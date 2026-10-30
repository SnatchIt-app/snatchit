/**
 * src/hooks/useSecurityNotices.ts — fetches the signed-in user's security
 * notices on sign-in and on every foreground (never polled), exposes the one
 * to show, and wires its two actions. Title and body come from the server.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

import { SIGN_OUT_FAILED_COPY, signOutAllDevices } from '@/src/lib/auth/signOut';
import { DISMISS_FAILED_COPY, isMissingRpc, MARK_NOTICES_READ_RPC, parseSecurityNotices, SECURITY_NOTICES_RPC, selectActionableNotice, type SecurityNotice } from '@/src/lib/security/notices';
import { supabase } from '@/src/lib/supabase';

export interface SecurityNoticesState {
  notice: SecurityNotice | null;
  busy: boolean;
  error: string | null;
  dismiss: () => Promise<void>;
  signOutAll: () => Promise<void>;
}

export function useSecurityNotices(userId: string | undefined): SecurityNoticesState {
  const [notice, setNotice] = useState<SecurityNotice | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inFlight = useRef(false);

  const load = useCallback(async () => {
    if (!userId || inFlight.current) return;
    inFlight.current = true;
    try {
      const { data, error: err } = await supabase.rpc(SECURITY_NOTICES_RPC);
      if (err) {
        // A missing 136 is "no notices"; any other failure stays quiet and retries on the next foreground.
        if (!isMissingRpc(err)) console.warn('[securityNotices] read failed:', err.code ?? err.message);
        setNotice(null);
        return;
      }
      setNotice(selectActionableNotice(parseSecurityNotices(data)));
    } finally {
      inFlight.current = false;
    }
  }, [userId]);

  useEffect(() => {
    setNotice(null);
    setError(null);
    if (!userId) return;
    void load();
    const sub = AppState.addEventListener('change', (st) => { if (st === 'active') void load(); });
    return () => sub.remove();
  }, [userId, load]);

  // F-SEC-1: `busy` is React state, so two presses in the SAME event loop both read `false` and both proceed —
  // and `disabled` cannot stop the second, because React has not re-rendered yet. On "Sign out of all devices"
  // that meant `signOutAllDevices()` ran twice. The lock is this ref; `busy` stays as what the UI SHOWS.
  //
  // ONE ref for both actions, deliberately: today they share `busy`, so dismissing already excludes signing out
  // and vice versa. Two refs would silently make them independent, which is a product change and not this fix.
  // Kept separate from `inFlight` above, which guards the foreground READ — sharing that one would let a
  // background refresh block a sign-out, or the reverse.
  const actionInFlight = useRef(false);

  /**
   * The single acquire and the single release for both actions, so a double release is impossible — and the
   * single place a THROWN failure is turned into something the user can see.
   *
   * F-SEC-2: only the `error` field a call returns was ever handled. A rejection — the session read or the
   * SecureStore work under `performSignOut`, or the RPC itself — propagated out of a handler the banner passes
   * straight to `onPress`, so it became an unhandled rejection and the screen said nothing. The lock released
   * and `busy` cleared, so nothing jammed; the user simply tapped a security action and was told nothing, which
   * is the silent tap `DISMISS_FAILED_COPY` exists to prevent.
   *
   * `failureCopy` is the caller's existing message, not a new one: a throw is the same thing to the user as the
   * returned error it sits beside — the action did not complete and they may try again.
   */
  const runExclusive = useCallback(async (action: () => Promise<void>, failureCopy: string) => {
    if (actionInFlight.current) return;
    actionInFlight.current = true;
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      console.warn('[securityNotices] action threw:', e instanceof Error ? e.message : e);
      setError(failureCopy);
    } finally {
      actionInFlight.current = false;
      setBusy(false);
    }
  }, []);

  const dismiss = useCallback(async () => {
    if (!notice) return;
    await runExclusive(async () => {
      const ids = [notice.id];
      const { error: err } = await supabase.rpc(MARK_NOTICES_READ_RPC, { p_ids: ids });
      if (err) {
        console.warn('[securityNotices] mark read failed:', err.code ?? err.message);
        setError(DISMISS_FAILED_COPY);   // the notice stays up; the tap is not silent
        return;
      }
      setNotice(null);
    }, DISMISS_FAILED_COPY);
  }, [notice, runExclusive]);

  const signOutAll = useCallback(async () => {
    await runExclusive(async () => {
      // K-2: ends every session and every push binding for THIS account (auth.uid()-scoped);
      // it does not undo the rebind. A failed SDK sign-out keeps the user signed in and says so.
      const out = await signOutAllDevices();
      if (!out.signedOut) { setError(SIGN_OUT_FAILED_COPY); return; }
      // F-SEC-2-A: past this line the sign-out HAPPENED — every session and push binding ended. A throw from
      // here must never be reported as a failed sign-out, or the screen tells the user the opposite of the
      // truth about their account security. A throw is an unknown outcome only while the outcome is unknown.
      // The navigation is belt-and-braces anyway: the global auth listener routes on sign-out.
      try {
        router.replace('/(auth)/login');
      } catch (e) {
        // Log only. This guard must NEVER clear `error`: today that would be a no-op — `runExclusive` clears it
        // each cycle and the only earlier `setError` here is on the `!out.signedOut` branch, which returns — so
        // `error` is necessarily null when this runs (D proved it as an equivalent mutant). That equivalence is
        // a property of the code as it stands: if that branch ever falls through, or anything sets an error on
        // the success path, clearing here would erase a real failure on a security surface.
        console.warn('[securityNotices] post-sign-out navigation failed:', e instanceof Error ? e.message : e);
      }
    }, SIGN_OUT_FAILED_COPY);
  }, [runExclusive]);

  return { notice, busy, error, dismiss, signOutAll };
}
