/**
 * tests/push-token-fetch-visibility.test.ts — F-611C-1 (Build 17 handset,
 * 2026-09-16): a cold launch that never reached register_push_token left no
 * trace anywhere. Two mechanisms, both closed here: an unbounded / throwing
 * Expo token fetch that the hook swallowed with console.warn only, and a
 * per-instance in-flight guard that a torn-down effect run could leave set,
 * so the live run's attempt returned at a dead-end early return.
 *
 * The gate is pure and driven here with the exact sequence; the hook is pinned
 * to it. What the pins cannot prove (a check missing after one specific await)
 * is a device row: DV-611C-2.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  beginRun, cancelRuns, createGate, endRun, isLive, PRE_REGISTER_REMEDY, preRegisterRetryDelayMs, recordPreRegisterFailure,
  TimeoutError, TOKEN_FETCH_TIMEOUT_MS, withTimeout,
} from '@/src/lib/push/runGate';
import { loadRegistrationState, REGISTRATION_STATE_KEY, saveRegistrationState, type KeyValueStore } from '@/src/lib/push/registrationStore';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('run gate: a torn-down run can never block the live one', () => {
  it("D's sequence: run 1 in flight, cleanup cancels, run 2 is admitted; run 1's late completion is ignored", () => {
    const g = createGate();
    const r1 = beginRun(g);
    expect(r1.admitted).toBe(true);
    expect(beginRun(g).admitted).toBe(false);        // same-effect concurrency → not admitted, rerun flagged
    cancelRuns(g);                                    // effect cleanup
    const r2 = beginRun(g);
    expect(r2.admitted).toBe(true);                   // the live effect is never blocked by the dead run
    expect(r1.admitted && isLive(g, r1.gen)).toBe(false);
    expect(r2.admitted && isLive(g, r2.gen)).toBe(true);
    // the dead run finishes later: it must not release the live run's flag
    const late = endRun(g, r1.admitted ? r1.gen : -1);
    expect(late).toEqual({ released: false, rerun: false });
    expect(beginRun(g).admitted).toBe(false);         // still in flight (run 2)
    const done = endRun(g, r2.admitted ? r2.gen : -1);
    expect(done.released).toBe(true);
    expect(done.rerun).toBe(true);                    // the not-admitted caller above asked for a rerun
    expect(beginRun(g).admitted).toBe(true);
  });

  it('a concurrent caller that finds a run in flight is re-attempted when it ends, and the flag clears after one rerun', () => {
    const g = createGate();
    const r = beginRun(g);
    expect(beginRun(g)).toEqual({ admitted: false });
    expect(endRun(g, r.admitted ? r.gen : -1)).toEqual({ released: true, rerun: true });
    const r2 = beginRun(g);
    expect(endRun(g, r2.admitted ? r2.gen : -1)).toEqual({ released: true, rerun: false });
  });

  it('cancel clears in-flight and any pending rerun', () => {
    const g = createGate();
    beginRun(g); beginRun(g);
    cancelRuns(g);
    const r = beginRun(g);
    expect(r.admitted).toBe(true);
    expect(endRun(g, r.admitted ? r.gen : -1)).toEqual({ released: true, rerun: false });
  });
});

describe('the token fetch is bounded', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('a hanging fetch rejects with TimeoutError after the budget; a resolving fetch resolves and clears the timer', async () => {
    expect(TOKEN_FETCH_TIMEOUT_MS).toBe(20_000);
    const hang = withTimeout(new Promise<string>(() => {}), TOKEN_FETCH_TIMEOUT_MS);
    const settled = hang.then(() => 'resolved', (e: unknown) => (e instanceof TimeoutError ? 'timeout' : 'other'));
    await vi.advanceTimersByTimeAsync(TOKEN_FETCH_TIMEOUT_MS - 1);
    await vi.advanceTimersByTimeAsync(1);
    expect(await settled).toBe('timeout');
    const ok = withTimeout(Promise.resolve('tok'), TOKEN_FETCH_TIMEOUT_MS);
    expect(await ok).toBe('tok');
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe('a pre-register failure is persisted, shown and retried', () => {
  it('records the kind and counts attempts; retry backs off from 30 s and caps at 10 min', () => {
    const f1 = recordPreRegisterFailure(null, 'token_fetch', 1_000);
    expect(f1).toEqual({ kind: 'token_fetch', at: 1_000, attempts: 1 });
    const f2 = recordPreRegisterFailure(f1, 'token_timeout', 2_000);
    expect(f2).toEqual({ kind: 'token_timeout', at: 2_000, attempts: 2 });
    expect(preRegisterRetryDelayMs(f1)).toBe(30_000);
    expect(preRegisterRetryDelayMs(f2)).toBe(60_000);
    expect(preRegisterRetryDelayMs({ kind: 'token_fetch', at: 0, attempts: 9 })).toBe(600_000);
  });

  it('remedy copy: one string per kind, each offers Try again, none claims the device is offline', () => {
    for (const k of ['token_fetch', 'token_timeout'] as const) {
      expect(PRE_REGISTER_REMEDY[k]).toMatch(/Try again/);
      expect(PRE_REGISTER_REMEDY[k]).not.toMatch(/offline|check your connection/i);
    }
  });

  it('the registration store keeps the pre-register failure beside the record', async () => {
    const mem = new Map<string, string>();
    const store: KeyValueStore = { getItem: async (k) => mem.get(k) ?? null, setItem: async (k, v) => { mem.set(k, v); } };
    await saveRegistrationState({ record: null, failure: null, preRegister: { kind: 'token_timeout', at: 5, attempts: 2 } }, store);
    expect(JSON.parse(mem.get(REGISTRATION_STATE_KEY) ?? '{}').preRegister.kind).toBe('token_timeout');
    expect(await loadRegistrationState(store)).toEqual({ record: null, failure: null, preRegister: { kind: 'token_timeout', at: 5, attempts: 2 } });
    await saveRegistrationState({ record: null, failure: null }, store);
    expect((await loadRegistrationState(store)).preRegister ?? null).toBeNull();
  });
});

describe('wiring (source contract) — what the pins buy is that the hook is wired to the gate, not that the order is right (DV-611C-2)', () => {
  it('the hook gates every attempt, checks liveness after each await, bounds the fetch, releases in finally, and never uses a per-instance running flag', () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    expect(h).not.toContain('runningRef');
    expect(h).toContain('const run = beginRun(gate);');
    expect(h).toMatch(/const run = beginRun\(gate\);\s*if \(!run\.admitted\) return;\s*try \{/);
    expect(h).toContain('withTimeout(obtainToken(), TOKEN_FETCH_TIMEOUT_MS)');
    expect((h.match(/if \(!isLive\(gate, run\.gen\)\) return;/g) ?? []).length).toBeGreaterThanOrEqual(2);
    expect(h).toContain('const end = endRun(gate, run.gen);');
    expect(h).toContain('if (end.rerun) void attempt();');
    // a token-fetch or storage failure is persisted and published, never console-only
    expect(h).toContain("preRegisterKind(err)");
    expect(h).toContain("publishRegistrationStatus({ state: 'failed', kind: pre.kind, at: pre.at })");
    expect(h).toContain('preRegister: pre');
    // cleanup cancels, so a dead run cannot block the live effect
    expect(h).toMatch(/return \(\) => \{[\s\S]*cancelRuns\(gate\);/);
  });

  it('Settings › Notifications offers Try again on a failed registration, including a pre-register failure', () => {
    const n = stripComments(read('app/settings/notifications.tsx'));
    const banner = n.slice(n.indexOf('{remedy ? ('), n.indexOf('<AccountSection title="Preferences">'));
    expect(banner).toContain("registration.state === 'failed'");
    expect(banner).toContain('requestRegistrationRetry');
    expect(banner).toContain('accessibilityLabel="Try again"');
  });
});
