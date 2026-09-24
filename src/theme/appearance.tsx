/**
 * src/theme/appearance.tsx — the appearance hooks and the one provider (owner 2026-09-23).
 *
 * `useTheme()` is what screens read: the resolved scheme and its palette. It subscribes to the
 * preference store and to the phone's own scheme, so a phone change under "System" re-renders
 * live and an explicit choice overrides it — no restart, no context plumbing, and testable
 * through the same hook harness the dock uses.
 *
 * `AppearanceProvider` mounts once at the root and does the two side effects: it loads the
 * persisted choice, and it tells the OS about an explicit override through
 * `Appearance.setColorScheme`, so native surfaces — the keyboard, alerts, the action sheet —
 * follow the app rather than the phone. Under "System" it hands control back (null).
 */

import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Appearance, useColorScheme } from 'react-native';

import {
  getAppearancePreference,
  loadAppearancePreference,
  resolveScheme,
  saveAppearancePreference,
  setAppearancePreference,
  subscribeAppearance,
  type AppearancePreference,
  type KeyValueStore,
} from '@/src/lib/appearance/appearanceStore';
import { paletteFor, type Palette, type Scheme } from './palette';

let persistence: KeyValueStore | null = null;

function defaultStore(): KeyValueStore {
  // Loaded lazily so nothing native is touched until the app actually persists a choice.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  return require('@react-native-async-storage/async-storage').default as KeyValueStore;
}

function usePreference(): AppearancePreference {
  const [pref, setPref] = useState<AppearancePreference>(getAppearancePreference());
  useEffect(() => subscribeAppearance(() => setPref(getAppearancePreference())), []);
  return pref;
}

export function useTheme(): { scheme: Scheme; palette: Palette } {
  const system = useColorScheme();
  const pref = usePreference();
  const scheme = resolveScheme(pref, system);
  return useMemo(() => ({ scheme, palette: paletteFor(scheme) }), [scheme]);
}

export function useAppearancePreference(): {
  preference: AppearancePreference;
  setPreference: (p: AppearancePreference) => void;
} {
  const preference = usePreference();
  return {
    preference,
    setPreference: (p) => {
      setAppearancePreference(p);
      void saveAppearancePreference(p, persistence ?? defaultStore());
    },
  };
}

/**
 * How long startup waits for the persisted choice before rendering under System anyway. The
 * read is one AsyncStorage key and normally settles in a few milliseconds; the bound only
 * exists so a wedged store can never hold the whole app behind the splash.
 */
export const APPEARANCE_LOAD_BOUND_MS = 400;

export function AppearanceProvider({
  children,
  store,
  maxWaitMs = APPEARANCE_LOAD_BOUND_MS,
}: {
  children: ReactNode;
  store?: KeyValueStore;
  maxWaitMs?: number;
}) {
  const pref = usePreference();
  // Nothing under the provider paints until the stored choice is read (or the bound passes):
  // painting first under System and then flipping to the person's explicit Light/Dark is the
  // startup flash B's package 8 §6 asks to rule out. The root holds the native splash meanwhile.
  const [ready, setReady] = useState(false);

  useEffect(() => {
    persistence = store ?? persistence ?? defaultStore();
    let alive = true;
    void loadAppearancePreference(persistence).then((loaded) => {
      if (!alive) return;
      // A late answer (after the bound) still applies: the choice is not lost for this launch.
      setAppearancePreference(loaded);
      setReady(true);
    });
    const bound = setTimeout(() => { if (alive) setReady(true); }, maxWaitMs);
    return () => { alive = false; clearTimeout(bound); };
  }, [store, maxWaitMs]);

  // An explicit Light/Dark is told to the OS so native surfaces match; System hands it back.
  useEffect(() => {
    Appearance.setColorScheme(pref === 'system' ? null : pref);
  }, [pref]);

  return ready ? <>{children}</> : null;
}
