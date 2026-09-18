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

  /** The single acquire and the single release for both actions, so a double release is impossible. */
  const runExclusive = useCallback(async (action: () => Promise<void>) => {
    if (actionInFlight.current) return;
    actionInFlight.current = true;
    setBusy(true);
    setError(null);
    try {
      await action();
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
    });
  }, [notice, runExclusive]);

  const signOutAll = useCallback(async () => {
    await runExclusive(async () => {
      // K-2: ends every session and every push binding for THIS account (auth.uid()-scoped);
      // it does not undo the rebind. A failed SDK sign-out keeps the user signed in and says so.
      const out = await signOutAllDevices();
      if (!out.signedOut) { setError(SIGN_OUT_FAILED_COPY); return; }
      router.replace('/(auth)/login');
    });
  }, [runExclusive]);

  return { notice, busy, error, dismiss, signOutAll };
}
