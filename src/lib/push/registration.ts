/**
 * src/lib/push/registration.ts — when to (re)register the push token, and what
 * to do when it fails. Pure; the hook owns the effects.
 *
 * The record of the last successful registration lives on the device (token,
 * user, method, time). Registration re-runs when the token changed, the account
 * changed (same device, next account — the rebind 128 exists for), the record
 * is stale, or the previous attempt failed and its backoff has elapsed.
 *
 * CONTRACT (A, 2026-09-14, migration 128 @4e29fde; an adversarial review is
 * still running and may amend it):
 *  - `register_push_token(p_token, p_platform, p_device_secret, p_device_name)`
 *    returns `{ token_id, outcome: registered|refreshed|rebound|rebound_legacy, platform }`.
 *  - 42501 `not_authenticated` — no session.
 *  - 42501 `insufficient_privilege: token is bound to another account` — ONE
 *    terminal branch, deliberately covering "bound to another account", "wrong
 *    secret" and "active legacy row owned by someone else"; the remedy is that
 *    the previous account signs out on this device, never a retry loop.
 *  - P0001 `precondition_failed: …` — a client bug (token/platform/secret
 *    shape); back off, do not spin.
 *  - Same token+secret+user repeated is `refreshed`: safe to retry on network
 *    failure. No rate limit.
 *  - PGRST202 (function not deployed — TRUE ON EVERY DATABASE TODAY) → the
 *    legacy path, which must stay insert-only and non-takeover.
 * Sign-out is unchanged (batch 1's direct UPDATE); it is what turns an
 * unclaimable active legacy row into a claimable revoked one.
 */

export type RegistrationMethod = 'rpc' | 'legacy';

export type RpcOutcome = 'registered' | 'refreshed' | 'rebound' | 'rebound_legacy';

export interface RegistrationRecord {
  token: string;
  userId: string;
  method: RegistrationMethod;
  /** Server outcome for the rpc method; the legacy path reports registered/refreshed. */
  outcome: RpcOutcome;
  /** Epoch ms of the last successful registration. */
  at: number;
}

export type RegistrationErrorKind =
  | 'rpc_missing'        // 128 not deployed here: PostgREST cannot find the function
  | 'bound_to_other'     // terminal: another account holds this token on the server (F7)
  | 'precondition'       // P0001 precondition_failed: a client-side shape bug
  | 'auth'               // no valid session
  | 'secret_unavailable' // Keychain or CSPRNG unavailable on this device
  | 'network'
  | 'unknown';

export interface RegistrationFailure {
  kind: RegistrationErrorKind;
  /** The attempt this failure belongs to; a different user or token starts fresh. */
  userId: string;
  token: string;
  method: RegistrationMethod;
  /** Epoch ms of the failure. */
  at: number;
  /** Consecutive failures of this kind, this one included. */
  attempts: number;
}

export interface DecisionInput {
  userId: string | null | undefined;
  token: string | null | undefined;
  record: RegistrationRecord | null;
  failure: RegistrationFailure | null;
  /** Whether the 128 RPC is known to exist here; undefined until probed. */
  rpcAvailable: boolean | undefined;
  now: number;
}

export type RegistrationAction = 'register' | 'skip' | 'wait';

export interface Decision {
  action: RegistrationAction;
  method: RegistrationMethod;
  reason:
    | 'signed_out' | 'no_token' | 'fresh'
    | 'first' | 'token_changed' | 'account_changed' | 'method_changed' | 'stale' | 'retry'
    | 'backoff' | 'bound_to_other';
  /** For `wait` with `backoff`: epoch ms when a retry may run. */
  retryAt?: number;
}

/** A successful registration is trusted for a day; after that, refresh last_used. */
export const REGISTRATION_TTL_MS = 24 * 60 * 60 * 1000;
/** Backoff: 30 s, 1 m, 2 m, … capped at 6 h. */
export const BACKOFF_BASE_MS = 30_000;
export const BACKOFF_MAX_MS = 6 * 60 * 60 * 1000;

export function backoffMs(attempts: number): number {
  const n = Math.max(1, Math.min(attempts, 20));
  return Math.min(BACKOFF_MAX_MS, BACKOFF_BASE_MS * 2 ** (n - 1));
}

/** A failure only counts against the same user, token and method it was recorded for. */
function relevantFailure(f: RegistrationFailure | null, userId: string, token: string, method: RegistrationMethod): RegistrationFailure | null {
  if (!f) return null;
  if (f.userId !== userId || f.token !== token) return null;
  // An rpc_missing failure is what switches the method; once switched it is spent.
  if (f.kind === 'rpc_missing' && method === 'legacy') return null;
  if (f.method !== method) return null;
  return f;
}

export function decideRegistration(i: DecisionInput): Decision {
  const method: RegistrationMethod = i.rpcAvailable === false ? 'legacy' : 'rpc';
  if (!i.userId) return { action: 'skip', method, reason: 'signed_out' };
  if (!i.token) return { action: 'skip', method, reason: 'no_token' };

  const failure = relevantFailure(i.failure, i.userId, i.token, method);
  if (failure) {
    // Terminal on both paths: the server told us another account holds this
    // token. Only a sign-out on that account, a new token, or a different user
    // changes the answer — all of which invalidate this failure record.
    if (failure.kind === 'bound_to_other') return { action: 'wait', method, reason: 'bound_to_other' };
    const retryAt = failure.at + backoffMs(failure.attempts);
    if (i.now < retryAt) return { action: 'wait', method, reason: 'backoff', retryAt };
    return { action: 'register', method, reason: 'retry' };
  }

  const r = i.record;
  if (!r) return { action: 'register', method, reason: 'first' };
  if (r.token !== i.token) return { action: 'register', method, reason: 'token_changed' };
  if (r.userId !== i.userId) return { action: 'register', method, reason: 'account_changed' };
  if (r.method !== method) return { action: 'register', method, reason: 'method_changed' };
  if (i.now - r.at > REGISTRATION_TTL_MS) return { action: 'register', method, reason: 'stale' };
  return { action: 'skip', method, reason: 'fresh' };
}

/** Shape of a PostgREST / supabase-js error, loosely. */
export interface ErrorLike {
  code?: string | null;
  message?: string | null;
  status?: number | null;
  details?: string | null;
  hint?: string | null;
}

/** Classify a failed registration against the contract's SQLSTATEs and messages. */
export function classifyRegistrationError(err: ErrorLike | null | undefined): RegistrationErrorKind {
  if (!err) return 'unknown';
  const code = (err.code ?? '').toString();
  const msg = (err.message ?? '').toLowerCase();
  // PostgREST: function not found in the schema cache; Postgres: undefined_function.
  if (code === 'PGRST202' || code === '42883' || /could not find the function/.test(msg)) return 'rpc_missing';
  if (code === '42501') {
    if (/not_authenticated/.test(msg)) return 'auth';
    // "insufficient_privilege: token is bound to another account" — the one terminal branch.
    return 'bound_to_other';
  }
  // Legacy path: unique_violation on push_tokens(token) is the same fact (F7).
  if (code === '23505' || /duplicate key/.test(msg)) return 'bound_to_other';
  if (code === 'P0001' && /precondition_failed/.test(msg)) return 'precondition';
  if (code === 'PGRST301' || err.status === 401 || /jwt|not authenticated|invalid claim/.test(msg)) return 'auth';
  if (/network request failed|failed to fetch|timeout|timed out|abort/.test(msg)) return 'network';
  return 'unknown';
}

export function recordFailure(
  prev: RegistrationFailure | null,
  kind: RegistrationErrorKind,
  ctx: { userId: string; token: string; method: RegistrationMethod; now: number },
): RegistrationFailure {
  const same = prev && prev.kind === kind && prev.userId === ctx.userId && prev.token === ctx.token && prev.method === ctx.method;
  return { kind, userId: ctx.userId, token: ctx.token, method: ctx.method, at: ctx.now, attempts: same ? prev.attempts + 1 : 1 };
}

/** What the user can be told when the device is not registered for this account. */
export const REGISTRATION_REMEDY: Partial<Record<RegistrationErrorKind, string>> = {
  bound_to_other:
    "Notifications aren't set up for this account on this device yet. The account that used this device before needs to sign out here first.",
  secret_unavailable:
    "Notifications can't be set up on this device right now because secure storage is unavailable.",
};
