/**
 * src/lib/auth/recoveryMarker.ts — the recovery hold survives the app being killed on "New password".
 *
 * The hold is React state, and the exchange consumes the stored verifier that raised it (recoveryClaim).
 * If iOS killed the app on the reset screen — a switch to a password manager, or the force-quit that was
 * the only way off it — the next launch restored the recovery session and routed to Home, signed in with
 * the old password (review N7-1, 2026-10-15). This marker re-raises the hold on that launch, for the same
 * user only and only within 24 h, so nobody is ever stuck on the screen; it is cleared on sign-out, after
 * a successful password update and on expiry. It holds a user id and a time — no token, no secret.
 */
export const RECOVERY_MARKER_KEY = 'recovery-pending';
export const RECOVERY_MARKER_TTL_MS = 24 * 3_600_000;

export interface MarkerStore {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

export async function markRecoveryPending(store: MarkerStore, userId: string, now: number = Date.now()): Promise<void> {
  try { await store.setItem(RECOVERY_MARKER_KEY, JSON.stringify({ userId, at: now })); } catch { /* best effort */ }
}

export async function clearRecoveryPending(store: MarkerStore): Promise<void> {
  try { await store.removeItem(RECOVERY_MARKER_KEY); } catch { /* best effort */ }
}

/** True when this user's recovery was interrupted less than 24 h ago. A stale or foreign marker is cleared. */
export async function recoveryPendingFor(store: MarkerStore, userId: string | null | undefined, now: number = Date.now()): Promise<boolean> {
  if (!userId) return false;
  let raw: string | null = null;
  try { raw = await store.getItem(RECOVERY_MARKER_KEY); } catch { return false; }
  if (!raw) return false;
  let marker: { userId?: unknown; at?: unknown } | null = null;
  try { marker = JSON.parse(raw) as { userId?: unknown; at?: unknown }; } catch { marker = null; }
  const fresh = !!marker && marker.userId === userId && typeof marker.at === 'number'
    && now - marker.at >= 0 && now - marker.at < RECOVERY_MARKER_TTL_MS;
  if (!fresh) await clearRecoveryPending(store);
  return fresh;
}
