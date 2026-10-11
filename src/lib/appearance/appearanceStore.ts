/**
 * src/lib/appearance/appearanceStore.ts — the appearance preference (owner 2026-09-23).
 *
 * Three values: 'system' (default — follow the phone), 'light', 'dark'. An explicit choice
 * overrides the phone until 'system' is chosen again, and persists locally across restarts.
 * Pure and dependency-free like dockAvatar: the persistence adapter is injected (AsyncStorage
 * in the app, a fake in tests), so nothing here imports a native module. No backend
 * preference, no migration — this never leaves the device.
 */

export type AppearancePreference = 'system' | 'light' | 'dark';
export type ResolvedScheme = 'light' | 'dark';

export const APPEARANCE_KEY = 'snatchit.appearance.v1';

export interface KeyValueStore {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
}

const PREFERENCES: readonly AppearancePreference[] = ['system', 'light', 'dark'];

export function isAppearancePreference(v: unknown): v is AppearancePreference {
  return typeof v === 'string' && (PREFERENCES as readonly string[]).includes(v);
}

/**
 * The scheme to render. 'system' follows the phone; when the phone reports nothing (null on
 * some platforms during startup) the approved dark appearance — Midnight — is the fallback.
 */
export function resolveScheme(
  preference: AppearancePreference,
  system: 'light' | 'dark' | null | undefined,
): ResolvedScheme {
  if (preference !== 'system') return preference;
  return system === 'light' ? 'light' : 'dark';
}

/** Never throws: an unreadable or unknown stored value is simply "follow the phone". */
export async function loadAppearancePreference(store: KeyValueStore): Promise<AppearancePreference> {
  try {
    const raw = await store.getItem(APPEARANCE_KEY);
    return isAppearancePreference(raw) ? raw : 'system';
  } catch {
    return 'system';
  }
}

/** Never throws: a failed save must not break the screen that made the choice. */
export async function saveAppearancePreference(pref: AppearancePreference, store: KeyValueStore): Promise<void> {
  try {
    await store.setItem(APPEARANCE_KEY, pref);
  } catch {
    // The in-memory choice still applies for this session.
  }
}

// ─── In-memory current value + subscription (the hooks read this) ──────────────

let current: AppearancePreference = 'system';
const listeners = new Set<() => void>();

export function getAppearancePreference(): AppearancePreference {
  return current;
}

export function setAppearancePreference(pref: AppearancePreference): void {
  if (pref === current) return;
  current = pref;
  listeners.forEach((l) => l());
}

export function subscribeAppearance(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}
