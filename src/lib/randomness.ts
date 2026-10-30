/**
 * src/lib/randomness.ts — the single device randomness source, checked at startup.
 *
 * `react-native-get-random-values` installs `crypto.getRandomValues` from the
 * device RNG (ExpoCrypto on SDK 48+, else its own native module) and THROWS
 * 'Native module not found' when neither exists — except under legacy Chrome
 * remote debugging in a __DEV__ build, where it silently falls back to
 * Math.random. That fallback is forbidden for session keys, so this module
 * refuses it explicitly.
 *
 * `assertDeviceRandomness()` runs once at native startup and fails CLOSED with a
 * message that names the missing polyfill, instead of the ReferenceError that
 * surfaced deep inside session restore in build 14.
 */

import { RandomnessUnavailable, type RandomBytes } from './sessionCipher';

type G = typeof globalThis & {
  crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array };
  expo?: { modules?: { ExpoCrypto?: { getRandomValues?: unknown } } };
  ExpoModules?: { ExpoRandom?: unknown };
  nativeCallSyncHook?: unknown;
  RN$Bridgeless?: boolean;
  __DEV__?: boolean;
};

export type RandomnessCheck =
  | { ok: true; source: 'ExpoCrypto' | 'RNGetRandomValues' | 'ExpoRandom' | 'platform' }
  | { ok: false; reason: 'no_global' | 'no_native_module' | 'insecure_fallback' | 'self_test_failed' };

/**
 * Pure predicate over the globals the polyfill consults. `nativeModules` is
 * injected so the check is testable without React Native.
 */
export function checkDeviceRandomness(g: G, nativeModules: Record<string, unknown> = {}): RandomnessCheck {
  if (typeof g.crypto?.getRandomValues !== 'function') return { ok: false, reason: 'no_global' };

  const expoCrypto = !!g.expo?.modules?.ExpoCrypto?.getRandomValues;
  const rnModule = !!nativeModules.RNGetRandomValues;
  const expoRandom = !!nativeModules.ExpoRandom || !!g.ExpoModules?.ExpoRandom;
  const platformNative = typeof g.nativeCallSyncHook !== 'undefined' || g.RN$Bridgeless === true;

  // The polyfill's Math.random path: __DEV__, old bridge, no sync hook.
  if (g.__DEV__ === true && g.RN$Bridgeless !== true && typeof g.nativeCallSyncHook === 'undefined' && !expoCrypto) {
    return { ok: false, reason: 'insecure_fallback' };
  }
  if (!expoCrypto && !rnModule && !expoRandom && !platformNative) return { ok: false, reason: 'no_native_module' };

  // Self-test: two draws must differ and be the requested length.
  try {
    const a = g.crypto!.getRandomValues!(new Uint8Array(16));
    const b = g.crypto!.getRandomValues!(new Uint8Array(16));
    if (a.length !== 16 || b.length !== 16 || a.every((x, i) => x === b[i])) return { ok: false, reason: 'self_test_failed' };
  } catch {
    return { ok: false, reason: 'self_test_failed' };
  }
  return { ok: true, source: expoCrypto ? 'ExpoCrypto' : rnModule ? 'RNGetRandomValues' : expoRandom ? 'ExpoRandom' : 'platform' };
}

export function randomnessFailureMessage(reason: Exclude<RandomnessCheck, { ok: true }>['reason']): string {
  const why = {
    no_global: "no crypto.getRandomValues global — 'react-native-get-random-values' was not imported before app code",
    no_native_module: 'the randomness native module is missing from this binary',
    insecure_fallback: 'the runtime would fall back to Math.random (legacy remote debugging) — refused for session keys',
    self_test_failed: 'the randomness source failed its self-test',
  }[reason];
  return `Secure randomness unavailable: ${why}. Sessions cannot be stored safely; this build must not be used.`;
}

/** Throws a legible, named error at startup instead of a ReferenceError at first write. */
export function assertDeviceRandomness(g: G = globalThis as G, nativeModules: Record<string, unknown> = {}): void {
  const r = checkDeviceRandomness(g, nativeModules);
  if (!r.ok) throw new RandomnessUnavailable(randomnessFailureMessage(r.reason));
}

/** The only RNG handed to the session store. Never reads the global lazily elsewhere. */
export const deviceRandomBytes: RandomBytes = (n) => {
  const g = globalThis as G;
  if (typeof g.crypto?.getRandomValues !== 'function') throw new RandomnessUnavailable(randomnessFailureMessage('no_global'));
  return g.crypto.getRandomValues(new Uint8Array(n));
};
