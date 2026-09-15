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

export type SessionEndReason = 'user' | 'expired';

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
};

export function sessionEndNotice(reason: SessionEndReason | null): string | null {
  return reason ? SESSION_END_NOTICE[reason] : null;
}
