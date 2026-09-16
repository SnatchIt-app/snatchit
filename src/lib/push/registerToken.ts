/**
 * src/lib/push/registerToken.ts — the two ways to register a token, with the
 * network injected so both are testable and the non-takeover rule is provable.
 *
 * RPC path (migration 128): `register_push_token` with the device secret. The
 * `p_` names are what PostgREST sees; do not strip them.
 *
 * LEGACY path (every database today, 128 applied nowhere): Build 16's exact
 * behaviour — select the caller's own row by token (RLS shows only theirs),
 * touch it if present, otherwise insert; on conflict STOP. It is insert-only
 * on purpose: an upsert or an update-by-token would claim another account's
 * row without device proof and reintroduce F7 on every database without 128.
 * Never call `notify.register_push_token`: it rebinds on the token alone and
 * is unexposed by design (128 now also revokes it server-side).
 *
 * RECOVERY (A's delta, 128 @f7b31ad). The server never replaces a stored
 * hash, and a mismatched secret still returns `refreshed`, so the only signal
 * of a lost secret is the device itself finding none. Recovery is then:
 * DELETE the row this device owns (RLS permits deleting your own row), then
 * register with the fresh secret → `registered`. It is destructive, so it is
 * gated three ways in `registerRpcWithRecovery` and never runs speculatively:
 * the secret was generated fresh on this attempt, this device previously
 * registered THIS token for THIS user through the RPC (so the server's hash
 * was ours and is now unreachable), and the RLS-scoped select finds a row we
 * own. A legacy row (no hash) needs no recovery: the first RPC registration
 * binds our secret to it. A reinstall issues a new token, so nothing older is
 * touched.
 */

import { supabase } from '@/src/lib/supabase';

import type { ChallengeInfo } from './challenge';
import {
  ACCEPTED_REGISTER_CONTRACT_VERSIONS,
  classifyRegistrationError,
  EXPECTED_128_CONTRACT_VERSION,
  type ErrorLike,
  type RegistrationErrorKind,
  type RpcOutcome,
} from './registration';

export type PushPlatform = 'ios' | 'android';

export interface RpcArgs {
  p_token: string;
  p_platform: PushPlatform;
  p_device_secret: string;
  p_device_name?: string | null;
}

export interface RpcReply {
  token_id: string;
  outcome: RpcOutcome;
  platform: PushPlatform;
  /** v2 carries the contract version on every reply; v1 replies have none. */
  contract_version?: number;
  /** v3: present with `challenge_required` — the proof-of-possession challenge to complete. */
  challenge?: ChallengeInfo;
}

export interface RegisterDeps {
  rpc: (args: RpcArgs) => Promise<{ data: unknown; error: ErrorLike | null }>;
  /** The caller's own row for this token, if any (RLS-scoped). */
  legacySelect: (token: string) => Promise<{ data: { id: string } | null; error: ErrorLike | null }>;
  legacyTouch: (id: string, nowIso: string) => Promise<{ error: ErrorLike | null }>;
  legacyInsert: (row: { user_id: string; token: string; platform: PushPlatform; is_active: true }) => Promise<{ error: ErrorLike | null }>;
  /** Deletes the caller's own row by id (RLS DELETE own). Recovery only. (v3: the server turns it into a revoke with history.) */
  deleteOwn: (id: string) => Promise<{ error: ErrorLike | null }>;
  /** v3: echo the nonce (or the 6-digit code) for a challenge. */
  confirmChallenge: (challengeId: string, nonce: string) => Promise<{ data: unknown; error: ErrorLike | null }>;
  /** v3: ask for the visible-code form of the open challenge for this token (the device secret proves it is the same requester). */
  requestChallenge: (token: string, secret: string) => Promise<{ data: unknown; error: ErrorLike | null }>;
}

export type RegisterResult =
  | { ok: true; method: 'rpc'; outcome: RpcOutcome; tokenId: string | null; contractVersion: number | null; challenge?: ChallengeInfo }
  | { ok: true; method: 'legacy'; outcome: 'registered' | 'refreshed'; tokenId: string | null }
  | { ok: false; kind: RegistrationErrorKind };

function isRpcReply(v: unknown): v is RpcReply {
  if (!v || typeof v !== 'object') return false;
  const o = v as Record<string, unknown>;
  return typeof o.outcome === 'string' && ['registered', 'refreshed', 'rebound', 'rebound_legacy', 'challenge_required'].includes(o.outcome);
}

export async function registerWithRpc(
  deps: Pick<RegisterDeps, 'rpc'>,
  args: { token: string; platform: PushPlatform; secret: string; deviceName: string | null },
): Promise<RegisterResult> {
  let reply: { data: unknown; error: ErrorLike | null };
  try {
    reply = await deps.rpc({
      p_token: args.token,
      p_platform: args.platform,
      p_device_secret: args.secret,
      p_device_name: args.deviceName,
    });
  } catch (e) {
    return { ok: false, kind: classifyRegistrationError(e as ErrorLike) };
  }
  if (reply.error) return { ok: false, kind: classifyRegistrationError(reply.error) };
  if (!isRpcReply(reply.data)) return { ok: false, kind: 'unknown' };
  // A reply that names a contract this build was not written for is not a
  // success: the server may have changed what `refreshed` or `rebound` mean.
  const cv = reply.data.contract_version;
  const withChallenge = reply.data.outcome === 'challenge_required' || reply.data.challenge != null;
  // v3 stamping: a challenge is always version 3; plain outcomes may be 2 or 3.
  if (withChallenge ? cv !== EXPECTED_128_CONTRACT_VERSION : cv != null && !ACCEPTED_REGISTER_CONTRACT_VERSIONS.includes(cv)) {
    return { ok: false, kind: 'contract_mismatch' };
  }
  const ch = reply.data.challenge;
  const challenge: ChallengeInfo | undefined =
    reply.data.outcome === 'challenge_required' && ch && typeof ch === 'object' && typeof ch.id === 'string'
      ? { id: ch.id, mode: ch.mode === 'visible' ? 'visible' : 'silent', expires_in_s: typeof ch.expires_in_s === 'number' ? ch.expires_in_s : 300 }
      : undefined;
  return {
    ok: true, method: 'rpc', outcome: reply.data.outcome,
    tokenId: typeof reply.data.token_id === 'string' ? reply.data.token_id : null,
    contractVersion: cv ?? null,
    ...(challenge ? { challenge } : {}),
  };
}

export interface RecoveryContext {
  /** The secret was generated on this attempt because none was stored. */
  freshSecret: boolean;
  /** The device's own record says it registered this token for this user via the RPC. */
  previouslyRpcForThisBinding: boolean;
}

export type RecoveryResult = RegisterResult & { recovered?: boolean };

/**
 * RPC registration with the one recovery path, gated so the destructive step
 * can never run on a guess. Returns `recovered: true` when the own row was
 * deleted and re-registered.
 */
export async function registerRpcWithRecovery(
  deps: Pick<RegisterDeps, 'rpc' | 'legacySelect' | 'deleteOwn'>,
  args: { token: string; platform: PushPlatform; secret: string; deviceName: string | null },
  ctx: RecoveryContext,
): Promise<RecoveryResult> {
  if (ctx.freshSecret && ctx.previouslyRpcForThisBinding) {
    try {
      const own = await deps.legacySelect(args.token);
      if (own.error) return { ok: false, kind: classifyRegistrationError(own.error) };
      if (own.data) {
        const gone = await deps.deleteOwn(own.data.id);
        if (gone.error) return { ok: false, kind: classifyRegistrationError(gone.error) };
        const r = await registerWithRpc(deps, args);
        return r.ok ? { ...r, recovered: true } : r;
      }
    } catch (e) {
      return { ok: false, kind: classifyRegistrationError(e as ErrorLike) };
    }
  }
  return registerWithRpc(deps, args);
}

export async function registerLegacy(
  deps: Pick<RegisterDeps, 'legacySelect' | 'legacyTouch' | 'legacyInsert'>,
  args: { userId: string; token: string; platform: PushPlatform; nowIso: string },
): Promise<RegisterResult> {
  try {
    const own = await deps.legacySelect(args.token);
    if (own.error) return { ok: false, kind: classifyRegistrationError(own.error) };
    if (own.data) {
      const touched = await deps.legacyTouch(own.data.id, args.nowIso);
      if (touched.error) return { ok: false, kind: classifyRegistrationError(touched.error) };
      return { ok: true, method: 'legacy', outcome: 'refreshed', tokenId: own.data.id };
    }
    // Insert-only. A conflict means another account holds this token: stop.
    const inserted = await deps.legacyInsert({ user_id: args.userId, token: args.token, platform: args.platform, is_active: true });
    if (inserted.error) return { ok: false, kind: classifyRegistrationError(inserted.error) };
    return { ok: true, method: 'legacy', outcome: 'registered', tokenId: null };
  } catch (e) {
    return { ok: false, kind: classifyRegistrationError(e as ErrorLike) };
  }
}

/** The live bindings. */
export const supabaseRegisterDeps: RegisterDeps = {
  rpc: async (args) => {
    const { data, error } = await supabase.rpc('register_push_token', args);
    return { data, error };
  },
  legacySelect: async (token) => {
    const { data, error } = await supabase.from('push_tokens').select('id').eq('token', token).maybeSingle();
    return { data: data ? { id: String((data as { id: string }).id) } : null, error };
  },
  legacyTouch: async (id, nowIso) => {
    const { error } = await supabase.from('push_tokens').update({ last_used: nowIso, is_active: true }).eq('id', id);
    return { error };
  },
  legacyInsert: async (row) => {
    const { error } = await supabase.from('push_tokens').insert(row);
    return { error };
  },
  deleteOwn: async (id) => {
    const { error } = await supabase.from('push_tokens').delete().eq('id', id);
    return { error };
  },
  confirmChallenge: async (challengeId, nonce) => {
    const { data, error } = await supabase.rpc('confirm_push_token_challenge', { p_challenge_id: challengeId, p_nonce: nonce });
    return { data, error };
  },
  requestChallenge: async (token, secret) => {
    const { data, error } = await supabase.rpc('request_push_token_challenge', { p_token: token, p_device_secret: secret, p_mode: 'visible' });
    return { data, error };
  },
};
