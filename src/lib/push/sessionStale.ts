/**
 * src/lib/push/sessionStale.ts — 131 (PROVISIONAL, A's session-bound design,
 * not frozen). When registration is refused with
 * `insufficient_privilege: session predates a credential change`, this
 * session can never register again: the user's password changed, or a
 * sign-out everywhere ran, after it was created (or its session row is gone).
 * The only remedy is a new session, so the app forgets its registration
 * record, marks why the session ended, and signs THIS device out (scope
 * 'local' — other devices are the server's business). Once per process: a
 * second refusal in the same run means the sign-out is already under way.
 */

export interface SessionStaleDeps {
  clearRegistration: () => Promise<void>;
  markEnd: (reason: 'credential_change') => void;
  /** Resolves true when the device is signed out; false when the SDK kept the session (offline). */
  signOutLocal: () => Promise<boolean>;
}

let handled = false;

/** Returns true when it acted; false when a prior call in this process already did. */
export async function handleSessionStale(deps: SessionStaleDeps): Promise<boolean> {
  if (handled) return false;
  handled = true;
  try { await deps.clearRegistration(); } catch { /* the sign-out still proceeds */ }
  deps.markEnd('credential_change');
  const done = await deps.signOutLocal();
  // F-K2-3: a failed sign-out keeps the session; let the next refusal retry.
  if (!done) handled = false;
  return true;
}

export function resetSessionStaleForTests(): void {
  handled = false;
}
