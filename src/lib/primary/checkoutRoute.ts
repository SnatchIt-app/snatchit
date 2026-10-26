/**
 * src/lib/primary/checkoutRoute.ts — the primary checkout screen's params, its 3-D Secure return URL,
 * and the buyer hold reply (D's registry 167, `20261027015500`, DARK until applied).
 *
 * Return URL: the PaymentSheet needs a URL that resolves to a REAL route that owns this payment (the
 * resale checkout learned this: a dead URL dropped buyers on the sitemap after a charge). It carries the
 * attempt id so the remount after the challenge reuses the SAME command key — the edge then replays the
 * same order and PaymentIntent instead of creating new ones.
 *
 * Hold: `public.reserve_primary_tier(p_session_id, p_ticket_type_id, p_quantity, p_command_key)` →
 * {status: ok | idempotency_replay, hold_id, expires_at, quantity}; refusals carry the same message
 * families as `venue.reserve_primary_inventory` (`oversell_rejected`, `precondition_failed: …`) plus 185's
 * `tier_not_on_sale`. Until 167 is applied PostgREST answers PGRST202 — "checkout isn't available yet".
 */
import { supabase } from '@/src/lib/supabase';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ATTEMPT_RE = /^[A-Za-z0-9-]{6,64}$/;
export const MAX_PRIMARY_QUANTITY = 10;

export function buildPrimaryReturnURL(p: { sessionId: string; ticketTypeId: string; quantity: number; attemptId: string }): string {
  const q = new URLSearchParams({ tt: p.ticketTypeId, qty: String(p.quantity), attempt: p.attemptId });
  return `snatchit://primary-checkout/${p.sessionId}?${q.toString()}`;
}

export type PrimaryCheckoutParams =
  | { ok: true; sessionId: string; ticketTypeId: string; quantity: number; attemptId: string | null }
  | { ok: false };

export function parsePrimaryCheckoutParams(raw: { session?: unknown; tt?: unknown; qty?: unknown; attempt?: unknown }): PrimaryCheckoutParams {
  const session = typeof raw.session === 'string' ? raw.session : '';
  const tt = typeof raw.tt === 'string' ? raw.tt : '';
  const qtyText = typeof raw.qty === 'string' ? raw.qty : '';
  if (!UUID_RE.test(session) || !UUID_RE.test(tt) || !/^\d{1,2}$/.test(qtyText)) return { ok: false };
  const quantity = Number(qtyText);
  if (quantity < 1 || quantity > MAX_PRIMARY_QUANTITY) return { ok: false };
  let attemptId: string | null = null;
  if (raw.attempt !== undefined && raw.attempt !== null && raw.attempt !== '') {
    if (typeof raw.attempt !== 'string' || !ATTEMPT_RE.test(raw.attempt)) return { ok: false };
    attemptId = raw.attempt;
  }
  return { ok: true, sessionId: session, ticketTypeId: tt, quantity, attemptId };
}

export type HoldRefusal = 'sold_out' | 'not_on_sale' | 'hold_limit' | 'signed_out' | 'not_ready' | 'offline' | 'unavailable';
export type HoldResult =
  | { ok: true; holdId: string; expiresAt: string | null; quantity: number }
  | { ok: false; reason: HoldRefusal };

export type HoldRpcResult = { data: unknown; error: { code?: string | null; message?: string | null } | null };

export function parseHoldReply(res: HoldRpcResult): HoldResult {
  if (res.error) {
    const code = res.error.code ?? '';
    const msg = res.error.message ?? '';
    if (code === 'PGRST202') return { ok: false, reason: 'not_ready' };
    if (code === '42501' || code === '28000' || code === 'PGRST301') return { ok: false, reason: 'signed_out' };
    if (/oversell_rejected/.test(msg)) return { ok: false, reason: 'sold_out' };
    if (/tier_not_on_sale|not_on_sale/.test(msg)) return { ok: false, reason: 'not_on_sale' };
    if (/hold_limit|per_user_active_hold|hold_cap/.test(msg)) return { ok: false, reason: 'hold_limit' };
    if (/network request failed|failed to fetch/i.test(msg)) return { ok: false, reason: 'offline' };
    return { ok: false, reason: 'unavailable' };
  }
  const row = Array.isArray(res.data) ? res.data[0] : res.data;
  if (!row || typeof row !== 'object') return { ok: false, reason: 'unavailable' };
  const r = row as Record<string, unknown>;
  const status = r.status;
  if ((status !== 'ok' && status !== 'idempotency_replay') || typeof r.hold_id !== 'string' || !UUID_RE.test(r.hold_id)) {
    return { ok: false, reason: 'unavailable' };
  }
  const quantity = typeof r.quantity === 'number' && Number.isInteger(r.quantity) && r.quantity > 0 ? r.quantity : null;
  if (quantity === null) return { ok: false, reason: 'unavailable' };
  return { ok: true, holdId: r.hold_id, expiresAt: typeof r.expires_at === 'string' ? r.expires_at : null, quantity };
}

export type HoldReserver = (req: { sessionId: string; ticketTypeId: string; quantity: number; commandKey: string }) => Promise<HoldResult>;

/** The 167 call. Thrown transport errors are offline; everything else goes through `parseHoldReply`. */
export const reservePrimaryTier: HoldReserver = async (req) => {
  try {
    const res = (await supabase.rpc('reserve_primary_tier', {
      p_session_id: req.sessionId,
      p_ticket_type_id: req.ticketTypeId,
      p_quantity: req.quantity,
      p_command_key: req.commandKey,
    })) as unknown as HoldRpcResult;
    return parseHoldReply(res);
  } catch {
    return { ok: false, reason: 'offline' };
  }
};

export const HOLD_COPY: Record<HoldRefusal, string> = {
  sold_out: 'There aren’t enough tickets left for that quantity.',
  not_on_sale: 'These tickets aren’t on sale right now.',
  hold_limit: 'You already have tickets held. Finish or wait for that hold to end first.',
  signed_out: 'Sign in to buy tickets.',
  not_ready: 'Checkout isn’t available for this event yet.',
  offline: 'You’re offline. Connect and try again.',
  unavailable: 'We couldn’t hold your tickets. Try again.',
};
