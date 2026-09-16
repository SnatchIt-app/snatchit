/**
 * src/lib/push/runGate.ts — the registration attempt's in-flight gate and the
 * bounded token fetch, as pure state (F-611C-1, Build 17 handset 2026-09-16).
 *
 * Why a gate and not a ref: the hook's old `runningRef` belonged to one effect
 * run. A torn-down run (auth restored twice, effect re-ran) could leave it set
 * while its unbounded token fetch hung, and the live run's attempt returned
 * at a dead-end early return — nothing tried, nothing recorded. The gate is
 * generation-scoped: cleanup calls `cancelRuns`, so a dead run can never block
 * a live one and its late completion is ignored; a live caller that finds a
 * run in flight is re-attempted when that run ends instead of dropped.
 *
 * DELIBERATE: the gate the hook uses is module-level. It spans remounts and
 * serialises any two consumers of the hook, which is what we want for one
 * device with one token (D's review, 2026-09-16).
 */

export const TOKEN_FETCH_TIMEOUT_MS = 20_000;

export interface RunGate { inFlight: boolean; generation: number; rerun: boolean }

export function createGate(): RunGate {
  return { inFlight: false, generation: 0, rerun: false };
}

export type RunAdmission = { admitted: true; gen: number } | { admitted: false };

/** Admit a run, or flag that the in-flight run should be followed by another. */
export function beginRun(g: RunGate): RunAdmission {
  if (g.inFlight) { g.rerun = true; return { admitted: false }; }
  g.inFlight = true;
  g.rerun = false;
  return { admitted: true, gen: g.generation };
}

/** Only the run of the current generation may release the gate; a stale run is ignored. */
export function endRun(g: RunGate, gen: number): { released: boolean; rerun: boolean } {
  if (gen !== g.generation || !g.inFlight) return { released: false, rerun: false };
  g.inFlight = false;
  const rerun = g.rerun;
  g.rerun = false;
  return { released: true, rerun };
}

/** Effect cleanup: every run so far is dead; nothing is in flight for the next effect. */
export function cancelRuns(g: RunGate): void {
  g.generation += 1;
  g.inFlight = false;
  g.rerun = false;
}

export function isLive(g: RunGate, gen: number): boolean {
  return gen === g.generation;
}

export class TimeoutError extends Error {
  constructor(ms: number) { super(`timed out after ${ms} ms`); this.name = 'TimeoutError'; }
}

/** Bound a promise so `finally` always runs and a hang becomes a reported failure. */
export function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | null = null;
  const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new TimeoutError(ms)), ms); });
  return Promise.race([Promise.resolve(p), timeout]).finally(() => { if (timer) clearTimeout(timer); });
}

// ── A failure BEFORE the register call: persisted, shown, retried ──────────
export type PreRegisterKind = 'token_fetch' | 'token_timeout';
export interface PreRegisterFailure { kind: PreRegisterKind; at: number; attempts: number }

export function preRegisterKind(err: unknown): PreRegisterKind {
  return err instanceof TimeoutError ? 'token_timeout' : 'token_fetch';
}

export function recordPreRegisterFailure(prev: PreRegisterFailure | null, kind: PreRegisterKind, now: number): PreRegisterFailure {
  return { kind, at: now, attempts: (prev?.attempts ?? 0) + 1 };
}

const PRE_REGISTER_BACKOFF_BASE_MS = 30_000;
const PRE_REGISTER_BACKOFF_MAX_MS = 600_000;

export function preRegisterRetryDelayMs(f: PreRegisterFailure): number {
  return Math.min(PRE_REGISTER_BACKOFF_MAX_MS, PRE_REGISTER_BACKOFF_BASE_MS * 2 ** Math.max(0, Math.min(20, f.attempts) - 1));
}

/** Copy for Settings › Notifications. Says what failed and how to retry; claims nothing about the connection. */
export const PRE_REGISTER_REMEDY: Record<PreRegisterKind, string> = {
  token_fetch: "Couldn't get this device's push token. It's retried the next time the app opens; tap Try again to retry now.",
  token_timeout: "Getting this device's push token is taking too long. Tap Try again, or close and reopen the app.",
};
