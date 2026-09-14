/**
 * src/lib/auth/signOut.ts — the one way this app signs out (CFT-611, A-08c).
 *
 * WHAT WAS WRONG. The privacy page said push tokens are "automatically marked
 * inactive when you sign out", and none of the five sign-out sites touched
 * `push_tokens`. Every path just called `supabase.auth.signOut()`.
 *
 * WHAT THIS DOES. Before the session is dropped — while the JWT is still
 * valid, because RLS lets a user update only their own token rows — it asks
 * the server to deactivate THIS device's token for the account being signed
 * out: `is_active=false`, `revoked_at=now()`, `revoked_reason='sign_out'`.
 * Best-effort, bounded by a short timeout, and it never blocks or fails the
 * sign-out: an offline device still signs out.
 *
 * WHAT THIS CANNOT DO (A-08d, server side, owner's decision). A token already
 * bound to a DIFFERENT account (reinstall, expired session, deleted account)
 * is invisible to this user under RLS, so the update matches nothing and the
 * other account keeps the device. Rebinding needs the server-side registration
 * contract exposed through a public RPC; it is not attempted here.
 *
 * VERIFICATION STATUS. Unverified on a physical device until a build carrying
 * this helper runs there; the privacy copy therefore describes an attempt, not
 * a guarantee.
 */

import { supabase } from '@/src/lib/supabase';
import { getRegisteredPushToken } from '@/src/lib/push/registeredToken';

export const SIGN_OUT_REVOKE_TIMEOUT_MS = 3_000;

export type RevokeOutcome = 'revoked' | 'no_token' | 'no_session' | 'no_match' | 'failed' | 'timed_out';

export interface SignOutDeps {
  /** The device's registered Expo push token, if any. */
  getToken: () => string | null;
  /** Current user id, or null when there is no valid session. */
  getUserId: () => Promise<string | null>;
  /** Runs the deactivation; resolves to the number of rows updated. */
  revoke: (token: string, userId: string) => Promise<number>;
  /** The actual sign-out. */
  signOut: () => Promise<void>;
  timeoutMs?: number;
  now?: () => Date;
}

/**
 * Deactivate this device's token for this user, then sign out. Pure over its
 * dependencies so the sequencing and the never-blocks rule are testable.
 */
export async function revokeThenSignOut(deps: SignOutDeps): Promise<{ revoke: RevokeOutcome }> {
  let outcome: RevokeOutcome = 'failed';
  try {
    const token = deps.getToken();
    if (!token) outcome = 'no_token';
    else {
      const userId = await deps.getUserId();
      if (!userId) outcome = 'no_session';
      else {
        let timer: ReturnType<typeof setTimeout> | undefined;
        const timeout = new Promise<'timed_out'>((res) => {
          timer = setTimeout(() => res('timed_out'), deps.timeoutMs ?? SIGN_OUT_REVOKE_TIMEOUT_MS);
        });
        try {
          const result = await Promise.race([deps.revoke(token, userId).then((n) => n), timeout]);
          outcome = result === 'timed_out' ? 'timed_out' : result > 0 ? 'revoked' : 'no_match';
        } finally {
          if (timer) clearTimeout(timer);
        }
      }
    }
  } catch {
    outcome = 'failed';
  }
  // The sign-out itself is never gated on the revoke.
  await deps.signOut();
  return { revoke: outcome };
}

/** The app's sign-out. Every sign-out site calls this and nothing else. */
export async function signOutEverywhere(): Promise<{ revoke: RevokeOutcome }> {
  const result = await revokeThenSignOut({
    getToken: getRegisteredPushToken,
    getUserId: async () => {
      const { data: { session } } = await supabase.auth.getSession();
      return session?.user?.id ?? null;
    },
    revoke: async (token, userId) => {
      const { data, error } = await supabase
        .from('push_tokens')
        .update({ is_active: false, revoked_at: new Date().toISOString(), revoked_reason: 'sign_out' })
        .eq('token', token)
        .eq('user_id', userId)
        .select('id');
      if (error) throw error;
      return data?.length ?? 0;
    },
    signOut: async () => {
      await supabase.auth.signOut();
    },
  });
  if (result.revoke !== 'revoked' && result.revoke !== 'no_token') {
    console.warn('[signOut] push token not deactivated:', result.revoke);
  }
  return result;
}
