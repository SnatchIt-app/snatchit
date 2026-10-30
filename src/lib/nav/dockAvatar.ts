/**
 * src/lib/nav/dockAvatar.ts — the one shared source for the "You" item's photo (V3, owner 2026-09-22).
 *
 * The dock must never fetch: there is no polling and no per-render read anywhere here. Screens that
 * ALREADY hold the signed-in user's avatar (`get_my_profile` on the profile tab and Home, the
 * edit-profile pick, the profile-tab upload) publish it; the dock only subscribes.
 *
 * The stale-photo rule is structural, not procedural: the store keeps `{ userId, path }`, and
 * `dockAvatarPathFor(currentUserId)` answers ONLY when the stored owner is the CURRENT
 * signed-in user. So even if a clear were missed, a previous account's photo cannot render after
 * the account changes (V3 acceptance 10). Sign-out clears the store as well, in `performSignOut`'s
 * post-success cleanup, exactly like the push-registration record.
 */

// Deliberately DEPENDENCY-FREE: sign-out and Home import this module, so it must never pull the
// media/URL stack (or anything with React Native or Supabase in its import graph) behind them.
// URL construction stays with the dock, the only renderer.

type DockAvatar = { userId: string; path: string | null };

let current: DockAvatar | null = null;
const listeners = new Set<() => void>();

function emit(): void {
  for (const l of listeners) l();
}

/** Publish the signed-in user's avatar path (or null when they have none). */
export function setDockAvatar(userId: string, path: string | null | undefined): void {
  if (!userId) return;
  const next = { userId, path: path ?? null };
  if (current && current.userId === next.userId && current.path === next.path) return;
  current = next;
  emit();
}

/** Sign-out (and tests): forget everything. */
export function clearDockAvatar(): void {
  if (current === null) return;
  current = null;
  emit();
}

export function subscribeDockAvatar(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

/**
 * The avatar PATH the dock may render for the CURRENT user, or null — null means "show the person
 * icon". A stored entry belonging to any other user answers null: the render-time guard that makes
 * acceptance 10 hold even when a clear was missed. The dock turns the path into a 28pt URL itself.
 */
export function dockAvatarPathFor(currentUserId: string | null | undefined): string | null {
  if (!currentUserId || !current || current.userId !== currentUserId) return null;
  return current.path;
}

/** Test-only visibility. */
export function _dockAvatarState(): DockAvatar | null {
  return current;
}
