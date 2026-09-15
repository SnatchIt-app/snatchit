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
 * HOW (128 G-2, A 2026-09-15 — PROVISIONAL until A's freeze names the verb).
 * On a database with migration 128, `revoked_at` / `revoked_reason` are
 * deliberately NOT client-writable: a client that could write
 * `revoked_reason='signed_out'` on its own row could forge rule 5's
 * precondition. So the revoke goes through the server verb first
 * (`REVOKE_RPC`, which writes the one spelling 'signed_out' itself). Only when
 * the verb does not exist (PGRST202: a database without 128, i.e. every
 * database today) does it fall back to Build 16's direct update, which the
 * owner-update policy still permits there. Any other error from the verb —
 * a 42501 included — is a failure, never a reason to try the table write.
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
import { classifyRegistrationError, type ErrorLike } from '@/src/lib/push/registration';

export const SIGN_OUT_REVOKE_TIMEOUT_MS = 3_000;

/**
 * The client-callable revoke verb. PROVISIONAL: `notify.revoke_push_token` is
 * not reachable from the client (the `notify` schema is unexposed), so this
 * names a `public` wrapper; A's frozen 128 text decides the final name/schema.
 */
export const REVOKE_RPC = 'revoke_push_token';

export interface RevokeDeps {
  /** The server verb: marks the caller's row for this token signed out. */
  rpc: (token: string) => Promise<{ data: unknown; error: ErrorLike | null }>;
  /** Pre-128 databases only: Build 16's direct update through the owner-update policy. */
  legacyUpdate: (token: string, userId: string) => Promise<number>;
}

/** Rows the verb reports as revoked; a bare success without a count is taken as one. */
function revokedCount(data: unknown): number {
  if (typeof data === 'number') return data;
  if (typeof data === 'boolean') return data ? 1 : 0;
  if (data && typeof data === 'object') {
    const o = data as Record<string, unknown>;
    for (const k of ['revoked', 'count', 'rows']) if (typeof o[k] === 'number') return o[k] as number;
  }
  return 1;
}

/**
 * Verb first; the direct table write only when the verb is absent (no 128
 * here). A 42501 or any other verb error propagates as a failure.
 */
export async function revokeDeviceToken(deps: RevokeDeps, token: string, userId: string): Promise<number> {
  const r = await deps.rpc(token);
  if (!r.error) return revokedCount(r.data);
  if (classifyRegistrationError(r.error) !== 'rpc_missing') throw r.error;
  return deps.legacyUpdate(token, userId);
}

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

/** The live revoke bindings: the verb, then Build 16's direct update as the pre-128 fallback. */
const liveRevokeDeps: RevokeDeps = {
  rpc: async (token) => {
    const { data, error } = await supabase.rpc(REVOKE_RPC, { p_token: token });
    return { data, error };
  },
  // Legacy fallback only (see header): on a 128 database this write is refused
  // for the revoked columns, and it is never reached there.
  legacyUpdate: async (token, userId) => {
    const { data, error } = await supabase
      .from('push_tokens')
      .update({ is_active: false, revoked_at: new Date().toISOString(), revoked_reason: 'signed_out' })
      .eq('token', token)
      .eq('user_id', userId)
      .select('id');
    if (error) throw error;
    return data?.length ?? 0;
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
    revoke: (token, userId) => revokeDeviceToken(liveRevokeDeps, token, userId),
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
