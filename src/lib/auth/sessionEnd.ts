/**
 * src/lib/auth/sessionEnd.ts — why the session ended, so the login screen can
 * say so (CFT-607, item 48: session expiry needs an understandable status and
 * a next step).
 *
 * The SDK fires the same SIGNED_OUT for a tap on "Sign out" and for a refresh
 * that failed on a stale token. The helper that performs a user sign-out marks
 * 'user' first; anything else that lands on the login screen with no mark is
 * treated as 'expired'. The mark is consumed once, so a later visit to the
 * login screen says nothing stale. Process memory only; nothing persisted.
 */

/**
 * 'password_changed' = this device just set a new password and signed out
 * everywhere on purpose (K-2). 131 (PROVISIONAL — session-bound push bindings,
 * A's design, not frozen): 'credential_change' = the server refused push
 * registration because this session predates a credential change OR a
 * sign-out everywhere from another device (or its session row is gone), so
 * the app signed this device out. The notice is deliberately neutral (D's
 * K-4): naming a password change would be false in the other cases and would
 * train users to ignore real notices.
 */
export type SessionEndReason = 'user' | 'expired' | 'password_changed' | 'credential_change';

let pending: SessionEndReason | null = null;

export function markSessionEnd(reason: SessionEndReason): void {
  pending = reason;
}

/** Marks a reason only when no earlier, more specific mark exists. */
export function markSessionEndIfUnmarked(reason: SessionEndReason): void {
  if (pending === null) pending = reason;
}

/** Read and clear. Null when nothing was marked (a normal first visit). */
export function consumeSessionEnd(): SessionEndReason | null {
  const r = pending;
  pending = null;
  return r;
}

/** Calm, exact: what the login screen shows for each reason. */
export const SESSION_END_NOTICE: Record<SessionEndReason, string | null> = {
  user: null,
  expired: 'Your session expired. Sign in to pick up where you left off.',
  password_changed: 'Password updated. Sign in with your new password.',
  credential_change: 'You were signed out on this device. Sign in again to keep notifications on.',
};

export function sessionEndNotice(reason: SessionEndReason | null): string | null {
  return reason ? SESSION_END_NOTICE[reason] : null;
}
