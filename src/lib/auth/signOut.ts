/**
 * src/lib/auth/signOut.ts — the one way this app signs out (CFT-611, A-08c).
 *
 * WHAT WAS WRONG. The privacy page said push tokens are "automatically marked
 * inactive when you sign out", and none of the five sign-out sites touched
 * `push_tokens`. Every path just called `supabase.auth.signOut()`.
 *
 * WHAT THIS DOES. Before the session is dropped — while the JWT is still
 * valid — it asks the server to mark THIS device's token signed out for the
 * account being signed out. Best-effort, bounded by a short timeout, and it
 * never blocks or fails the sign-out: an offline device still signs out.
 *
 * HOW (contract v2 §2.4, FROZEN 2026-09-15). The revoke is the server verb
 * `notify.revoke_push_token(p_token)` → `{ "revoked": 0|1 }`, called through
 * the `notify` schema. `revoked_at` / `revoked_reason` are NOT client-writable
 * on a 128 database (a client that could write `revoked_reason='signed_out'`
 * on its own row could forge rule 5's precondition), so there is no direct
 * table write here at all — not even as a fallback. Any verb error is a
 * failure that is logged and never blocks the sign-out. DEPENDENCY: the verb
 * is reachable only while `notify` is in PostgREST's exposed schemas (a
 * dashboard setting, not in git); A confirms it per environment.
 *
 * After the revoke — whatever its outcome — the device's registration record
 * is cleared, so the next sign-in registers again ('first') and re-activates
 * the row. Without this a same-process re-login found a fresh record and
 * skipped, leaving the row revoked until the next cold launch.
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

import { markSessionEnd } from '@/src/lib/auth/sessionEnd';
import { supabase } from '@/src/lib/supabase';
import { getRegisteredPushToken } from '@/src/lib/push/registeredToken';
import type { ErrorLike } from '@/src/lib/push/registration';
import { EMPTY_REGISTRATION_STATE, saveRegistrationState } from '@/src/lib/push/registrationStore';

export const SIGN_OUT_REVOKE_TIMEOUT_MS = 3_000;

/** Contract v2 §2.4: the revoke verb and the schema it lives in. */
export const REVOKE_RPC_SCHEMA = 'notify';
export const REVOKE_RPC = 'revoke_push_token';

export interface RevokeDeps {
  /** The server verb: marks the caller's row for this token signed out. */
  rpc: (token: string) => Promise<{ data: unknown; error: ErrorLike | null }>;
}

/** Rows the verb reports as revoked — `{ revoked: 0|1 }`; anything else asserts nothing, so 0. */
function revokedCount(data: unknown): number {
  if (typeof data === 'number') return data;
  if (data && typeof data === 'object') {
    const n = (data as Record<string, unknown>).revoked;
    if (typeof n === 'number') return n;
  }
  return 0;
}

/** The verb, and only the verb. Any error propagates as a failure. */
export async function revokeDeviceToken(deps: RevokeDeps, token: string): Promise<number> {
  const r = await deps.rpc(token);
  if (r.error) throw r.error;
  return revokedCount(r.data);
}

export type RevokeOutcome = 'revoked' | 'no_token' | 'no_session' | 'no_match' | 'failed' | 'timed_out';

export interface SignOutDeps {
  /** The device's registered Expo push token, if any. */
  getToken: () => string | null;
  /** Current user id, or null when there is no valid session. */
  getUserId: () => Promise<string | null>;
  /** Runs the deactivation; resolves to the number of rows updated. */
  revoke: (token: string, userId: string) => Promise<number>;
  /** Forgets this device's registration record so the next sign-in registers again. */
  clearRegistration?: () => Promise<void>;
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
  // Whatever the revoke did, the local record is stale once we sign out.
  try { await deps.clearRegistration?.(); } catch { /* never blocks */ }
  // The sign-out itself is never gated on the revoke.
  await deps.signOut();
  return { revoke: outcome };
}

/** The live revoke binding: the verb through the `notify` schema (contract v2 §2.4). */
const liveRevokeDeps: RevokeDeps = {
  rpc: async (token) => {
    const { data, error } = await supabase.schema(REVOKE_RPC_SCHEMA).rpc(REVOKE_RPC, { p_token: token });
    return { data, error };
  },
};

/** The app's sign-out. Every sign-out site calls this and nothing else. */
export async function signOutEverywhere(): Promise<{ revoke: RevokeOutcome }> {
  const result = await revokeThenSignOut({
    getToken: getRegisteredPushToken,
    getUserId: async () => {
      const { data: { session } } = await supabase.auth.getSession();
      return session?.user?.id ?? null;
    },
    revoke: (token) => revokeDeviceToken(liveRevokeDeps, token),
    clearRegistration: () => saveRegistrationState(EMPTY_REGISTRATION_STATE),
    signOut: async () => {
      // The user chose this; the login screen must not call it an expiry (CFT-607).
      markSessionEnd('user');
      await supabase.auth.signOut();
    },
  });
  if (result.revoke !== 'revoked' && result.revoke !== 'no_token') {
    console.warn('[signOut] push token not deactivated:', result.revoke);
  }
  return result;
}
