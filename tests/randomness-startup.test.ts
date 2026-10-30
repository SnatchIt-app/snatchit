/**
 * tests/randomness-startup.test.ts — the startup RNG check and the entry
 * import order, exercised as behaviour and as an import GRAPH.
 *
 * Build 14 died with a bare ReferenceError at first session write because the
 * polyfill import lived in a leaf module and a refactor dropped it. Now: the
 * entry imports it first, the store never reads a global, and startup fails
 * closed with a message that names the missing polyfill.
 */

import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { randomBytes as nodeRandom } from 'node:crypto';

import { assertDeviceRandomness, checkDeviceRandomness, deviceRandomBytes, randomnessFailureMessage } from '../src/lib/randomness';
import { RandomnessUnavailable } from '../src/lib/sessionCipher';

const root = resolve(__dirname, '..');
const goodRng = { getRandomValues: (a: Uint8Array) => { a.set(nodeRandom(a.length)); return a; } };

describe('startup check — fails closed with a named, legible error', () => {
  it('no crypto global → no_global, and the message names the polyfill', () => {
    const r = checkDeviceRandomness({} as never);
    expect(r).toEqual({ ok: false, reason: 'no_global' });
    expect(() => assertDeviceRandomness({} as never)).toThrow(RandomnessUnavailable);
    expect(() => assertDeviceRandomness({} as never)).toThrow(/react-native-get-random-values/);
  });

  it('global present but no native module → no_native_module', () => {
    expect(checkDeviceRandomness({ crypto: goodRng } as never, {})).toEqual({ ok: false, reason: 'no_native_module' });
  });

  it('the Math.random debugging fallback is refused', () => {
    const g = { crypto: goodRng, __DEV__: true } as never; // old bridge, no sync hook, no ExpoCrypto
    expect(checkDeviceRandomness(g, { RNGetRandomValues: {} })).toEqual({ ok: false, reason: 'insecure_fallback' });
    expect(randomnessFailureMessage('insecure_fallback')).toMatch(/Math\.random/);
  });

  it('a stuck source fails the self-test', () => {
    const stuck = { getRandomValues: (a: Uint8Array) => a.fill(7) };
    expect(checkDeviceRandomness({ crypto: stuck, nativeCallSyncHook: () => 0 } as never, {})).toEqual({ ok: false, reason: 'self_test_failed' });
  });

  it.each([
    ['ExpoCrypto', { crypto: goodRng, expo: { modules: { ExpoCrypto: { getRandomValues: () => 0 } } } }, {}],
    ['RNGetRandomValues', { crypto: goodRng, nativeCallSyncHook: () => 0 }, { RNGetRandomValues: {} }],
    ['platform', { crypto: goodRng, RN$Bridgeless: true }, {}],
  ])('%s is accepted', (source, g, nm) => {
    expect(checkDeviceRandomness(g as never, nm)).toEqual({ ok: true, source });
  });

  it('deviceRandomBytes never reaches an undefined global', () => {
    const saved = (globalThis as { crypto?: unknown }).crypto;
    delete (globalThis as { crypto?: unknown }).crypto;
    try { expect(() => deviceRandomBytes(24)).toThrow(RandomnessUnavailable); }
    finally { (globalThis as { crypto?: unknown }).crypto = saved; }
    expect(deviceRandomBytes(24)).toHaveLength(24);
  });
});

/** Minimal static import-graph walker over the app's own source. */
function importsOf(file: string): string[] {
  const src = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const specs: string[] = [];
  for (const m of src.matchAll(/^\s*import\s+(?:[^'"]*?\s+from\s+)?['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of src.matchAll(/require\(\s*['"]([^'"]+)['"]\s*\)/g)) specs.push(m[1]);
  return specs;
}
function resolveSpec(fromFile: string, spec: string): string | null {
  let base: string;
  if (spec.startsWith('@/')) base = resolve(root, spec.slice(2));
  else if (spec.startsWith('.')) base = resolve(dirname(fromFile), spec);
  else return null; // package — a leaf for this walk
  for (const ext of ['', '.ts', '.tsx', '.native.ts', '.native.tsx', '/index.ts', '/index.tsx']) {
    const p = base + ext; if (existsSync(p) && !p.endsWith('/')) return p;
  }
  return null;
}
function walk(entry: string) {
  const order: string[] = []; const seen = new Set<string>(); const pkgs = new Map<string, number>();
  let tick = 0;
  (function visit(f: string) {
    if (seen.has(f)) return; seen.add(f);
    for (const spec of importsOf(f)) {
      const r = resolveSpec(f, spec);
      if (r) visit(r); else if (!pkgs.has(spec)) pkgs.set(spec, tick++);
    }
    order.push(f);
  })(entry);
  return { order, pkgs, seen };
}

describe('import graph — the polyfill is evaluated before anything that reaches the cipher', () => {
  const entry = resolve(root, 'app/_layout.tsx');
  const cipher = resolve(root, 'src/lib/sessionCipher.ts');
  const g = walk(entry);

  it('the entry\'s first import statement is the polyfill', () => {
    expect(importsOf(entry)[0]).toBe('react-native-get-random-values');
  });

  it('the session cipher is reachable from the entry (so the ordering claim is about a real path)', () => {
    expect(g.seen.has(cipher)).toBe(true);
  });

  it('in depth-first evaluation order the polyfill is the first package touched from the entry', () => {
    // packages are recorded in the order the walk first meets them; the polyfill
    // must be index 0 — i.e. no module that could reach the cipher is entered first
    expect(g.pkgs.get('react-native-get-random-values')).toBe(0);
  });

  it('no module reachable from the entry reads the crypto global except the guarded randomness module', () => {
    for (const f of g.seen) {
      if (f.endsWith('src/lib/randomness.ts')) continue;
      const code = readFileSync(f, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
      expect(code, f).not.toMatch(/\bcrypto\.getRandomValues\b/);
    }
  });
});
