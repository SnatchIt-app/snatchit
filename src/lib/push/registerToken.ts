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
 * is unexposed by design.
 */

import { supabase } from '@/src/lib/supabase';

import { classifyRegistrationError, type ErrorLike, type RegistrationErrorKind, type RpcOutcome } from './registration';

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
}

export interface RegisterDeps {
  rpc: (args: RpcArgs) => Promise<{ data: unknown; error: ErrorLike | null }>;
  /** The caller's own row for this token, if any (RLS-scoped). */
  legacySelect: (token: string) => Promise<{ data: { id: string } | null; error: ErrorLike | null }>;
  legacyTouch: (id: string, nowIso: string) => Promise<{ error: ErrorLike | null }>;
  legacyInsert: (row: { user_id: string; token: string; platform: PushPlatform; is_active: true }) => Promise<{ error: ErrorLike | null }>;
}

export type RegisterResult =
  | { ok: true; method: 'rpc'; outcome: RpcOutcome; tokenId: string | null }
  | { ok: true; method: 'legacy'; outcome: 'registered' | 'refreshed'; tokenId: string | null }
  | { ok: false; kind: RegistrationErrorKind };

function isRpcReply(v: unknown): v is RpcReply {
  if (!v || typeof v !== 'object') return false;
  const o = v as Record<string, unknown>;
  return typeof o.outcome === 'string' && ['registered', 'refreshed', 'rebound', 'rebound_legacy'].includes(o.outcome);
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
  return { ok: true, method: 'rpc', outcome: reply.data.outcome, tokenId: typeof reply.data.token_id === 'string' ? reply.data.token_id : null };
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
};
