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
 * HOW (contract v2 §2.4 with the 2026-09-15 erratum). The revoke is the
 * server verb `public.revoke_push_token(p_token)` → `{ "revoked": 0|1 }`
 * (migration 129: a SECURITY DEFINER wrapper over notify's writer, EXECUTE for
 * authenticated only, so nothing depends on which schemas PostgREST exposes).
 * `revoked_at` / `revoked_reason` are NOT client-writable on a 128 database (a
 * client that could write `revoked_reason='signed_out'` on its own row could
 * forge rule 5's precondition), so there is no direct table write here at all
 * — not even as a fallback. Any verb error (PGRST202 where 129 is absent,
 * 42501, network) is a failure that is logged and never blocks the sign-out.
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

import { consumeSessionEnd, markSessionEnd, type SessionEndReason } from '@/src/lib/auth/sessionEnd';
import { supabase } from '@/src/lib/supabase';
import { getRegisteredPushToken } from '@/src/lib/push/registeredToken';
import type { ErrorLike } from '@/src/lib/push/registration';
import { EMPTY_REGISTRATION_STATE, saveRegistrationState } from '@/src/lib/push/registrationStore';

export const SIGN_OUT_REVOKE_TIMEOUT_MS = 3_000;

/**
 * K-2 (owner-approved 2026-09-15). Two sign-outs, named for what they do:
 *  - `signOutThisDevice`: scope 'local'. Before this change the app used
 *    auth-js's default `{ scope: 'global' }`, which ended every session of the
 *    user on every sign-out and left the other devices with live push rows and
 *    no session. A user who suspects their account is used elsewhere now uses
 *    the other act.
 *  - `signOutAllDevices`: asks the server to revoke every push binding of this
 *    user first (`public.revoke_all_push_bindings`, migration 131 — on a
 *    database without it the call fails with PGRST202, is logged and ignored),
 *    then ends every session (scope 'global', which auth-js enforces today).
 *    Used by "Sign out of all devices", by account deletion (D's K-1) and after
 *    a password change. A and D verify the server-side invalidation contract.
 * NOT in the pinned candidate build (aabe029): shipping it needs a new pin.
 */
export type SignOutScope = 'local' | 'global';
export interface SignOutOptions {
  scope?: SignOutScope;
  /** Why, for the login screen (default 'user'). */
  reason?: SessionEndReason;
}
export function resolveSignOutOptions(opts: SignOutOptions = {}): Required<SignOutOptions> {
  return { scope: opts.scope ?? 'local', reason: opts.reason ?? 'user' };
}
/** 131 §2c: `public.revoke_all_push_bindings()` → `{ revoked, contract_version }`, own user only; not pinned (additive). */
export const REVOKE_ALL_RPC = 'revoke_all_push_bindings';

/** Contract v2 §2.4 (erratum 2026-09-15): the public revoke verb, migration 129. */
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

/**
 * F-K2-3 (D, verified by A against auth-js): `supabase.auth.signOut` keeps the
 * local session on a network error (it discards it only on 401/403/404), so
 * a sign-out can FAIL while the user is still signed in. The result says so;
 * callers keep the user on the screen with this exact copy and a retry, and
 * the registration record is cleared only after the sign-out succeeded.
 */
export const SIGN_OUT_FAILED_COPY = "Couldn't sign out — check your connection and try again.";

export type SignOutResult =
  | { signedOut: true; revoke: RevokeOutcome }
  | { signedOut: false; revoke: RevokeOutcome; error: string };

export interface SignOutDeps {
  /** The device's registered Expo push token, if any. */
  getToken: () => string | null;
  /** Current user id, or null when there is no valid session. */
  getUserId: () => Promise<string | null>;
  /** Runs the deactivation; resolves to the number of rows updated. */
  revoke: (token: string, userId: string) => Promise<number>;
  /** Forgets this device's registration record so the next sign-in registers again (after success only). */
  clearRegistration?: () => Promise<void>;
  /** The actual sign-out; resolves to the SDK's error, null on success. */
  signOut: () => Promise<{ error: ErrorLike | null } | void>;
  timeoutMs?: number;
  now?: () => Date;
}

/**
 * Deactivate this device's token for this user, then sign out. Pure over its
 * dependencies so the sequencing and the never-blocks rule are testable.
 */
export async function revokeThenSignOut(deps: SignOutDeps): Promise<SignOutResult> {
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
  let signOutError: ErrorLike | null = null;
  try {
    const r = await deps.signOut();
    signOutError = r && r.error ? r.error : null;
  } catch (e) {
    signOutError = { message: e instanceof Error ? e.message : String(e) };
  }
  if (signOutError) {
    // Still signed in (auth-js kept the session). Nothing local changes.
    return { signedOut: false, revoke: outcome, error: signOutError.message ?? 'sign_out_failed' };
  }
  // Signed out: the local record is stale now, and only now.
  try { await deps.clearRegistration?.(); } catch { /* never blocks */ }
  return { signedOut: true, revoke: outcome };
}

/** The live revoke binding: the public verb (contract v2 §2.4, erratum). */
const liveRevokeDeps: RevokeDeps = {
  rpc: async (token) => {
    const { data, error } = await supabase.rpc(REVOKE_RPC, { p_token: token });
    return { data, error };
  },
};

/** The one sign-out implementation; the two exported acts below choose the scope. */
async function performSignOut(opts: SignOutOptions): Promise<SignOutResult> {
  const { scope, reason } = resolveSignOutOptions(opts);
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
      markSessionEnd(reason);
      const { error } = await supabase.auth.signOut({ scope });
      // No sign-out happened: the mark must not describe one later.
      if (error) consumeSessionEnd();
      return { error };
    },
  });
  if (result.revoke !== 'revoked' && result.revoke !== 'no_token') {
    console.warn('[signOut] push token not deactivated:', result.revoke);
  }
  if (!result.signedOut) console.warn('[signOut] sign-out failed, session kept:', result.error);
  return result;
}

/** Sign out THIS device only. Every ordinary sign-out site calls this and nothing else. */
export function signOutThisDevice(opts: { reason?: SessionEndReason } = {}): Promise<SignOutResult> {
  return performSignOut({ scope: 'local', reason: opts.reason });
}

/**
 * The all-devices revoke, raced against the same budget as the per-device one
 * (A's F-K2-1): a hang is not a failure, and a dead network must not leave the
 * user stuck on "Sign out of all devices". Timeout or error → null (logged);
 * the caller signs out regardless. `{ revoked }` is the only count read.
 */
export async function revokeAllBindings(
  rpc: () => Promise<{ data: unknown; error: ErrorLike | null }>,
  timeoutMs: number = SIGN_OUT_REVOKE_TIMEOUT_MS,
): Promise<number | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<'timed_out'>((res) => { timer = setTimeout(() => res('timed_out'), timeoutMs); });
  try {
    // F-K2-2 (A): when the timeout wins, the losing call must not surface a
    // later rejection as unhandled; the race still sees an early rejection.
    const call = rpc();
    call.catch(() => {});
    const r = await Promise.race([call, timeout]);
    if (r === 'timed_out') {
      console.warn('[signOut] revoke_all_push_bindings timed out');
      return null;
    }
    if (r.error) throw r.error;
    const n = r.data && typeof r.data === 'object' ? (r.data as Record<string, unknown>).revoked : undefined;
    return typeof n === 'number' ? n : null;
  } catch (e) {
    console.warn('[signOut] revoke_all_push_bindings failed:', e instanceof Error ? e.message : e);
    return null;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * Sign out of ALL devices: revoke every push binding of this user on the
 * server (bounded; failure or timeout is logged and never blocks), then end
 * every session.
 */
export async function signOutAllDevices(opts: { reason?: SessionEndReason } = {}): Promise<SignOutResult & { revokedAll: number | null }> {
  const revokedAll = await revokeAllBindings(async () => {
    const { data, error } = await supabase.rpc(REVOKE_ALL_RPC);
    return { data, error };
  });
  const result = await performSignOut({ scope: 'global', reason: opts.reason });
  return { ...result, revokedAll };
}
