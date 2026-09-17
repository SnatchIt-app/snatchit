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

  const dismiss = useCallback(async () => {
    if (!notice || busy) return;
    setBusy(true);
    setError(null);
    try {
      const ids = [notice.id];
      const { error: err } = await supabase.rpc(MARK_NOTICES_READ_RPC, { p_ids: ids });
      if (err) {
        console.warn('[securityNotices] mark read failed:', err.code ?? err.message);
        setError(DISMISS_FAILED_COPY);   // the notice stays up; the tap is not silent
        return;
      }
      setNotice(null);
    } finally {
      setBusy(false);
    }
  }, [notice, busy]);

  const signOutAll = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      // K-2: ends every session and every push binding for THIS account (auth.uid()-scoped);
      // it does not undo the rebind. A failed SDK sign-out keeps the user signed in and says so.
      const out = await signOutAllDevices();
      if (!out.signedOut) { setError(SIGN_OUT_FAILED_COPY); return; }
      router.replace('/(auth)/login');
    } finally {
      setBusy(false);
    }
  }, [busy]);

  return { notice, busy, error, dismiss, signOutAll };
}
