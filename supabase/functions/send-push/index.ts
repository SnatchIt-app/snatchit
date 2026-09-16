// READY TO DEPLOY
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const SUPABASE_URL             = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const EXPO_PUSH_URL            = Deno.env.get('EXPO_PUSH_URL') ?? 'https://exp.host/--/api/v2/push/send';

// ── Authorization ─────────────────────────────────────────────────────────────
// send-push is an internal-only function. It must only be called by trusted
// server-side callers (currently: stripe-webhook edge function).
// We verify the caller presents the service-role key as the Bearer token.
// Mobile clients hold only the anon key and cannot forge this value.
function isAuthorized(req: Request): boolean {
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return false;
  const token = authHeader.slice('Bearer '.length);
  // Constant-time comparison to prevent timing attacks
  if (token.length !== SUPABASE_SERVICE_ROLE_KEY.length) return false;
  let diff = 0;
  for (let i = 0; i < token.length; i++) {
    diff |= token.charCodeAt(i) ^ SUPABASE_SERVICE_ROLE_KEY.charCodeAt(i);
  }
  return diff === 0;
}

// ── b2: provider-side proof of possession (O-3 close-out) ────────────────────
// A push binding becomes deliverable for an account only after the provider
// proves the registering device holds the token: the server issues a one-time
// nonce, sends it TO THAT TOKEN, and the device echoes it back through
// confirm_push_token_challenge. This is the send half. A plant-then-claim or a
// delete-then-register from a second device never activates, because the nonce
// goes to the victim's phone.
//
// THE NONCE NEVER REACHES A LOG. Only the challenge id and the outcome are
// logged, and no response body carries the nonce. The challenge row stores only
// its hash, so the plaintext arrives in the request and leaves in the payload.
//
// Contract v3 (A, candidate ac716da) + 157 B9: notify tables carry NO
// service_role grants — the grant wall is service_role's wall — so the challenge
// is read through notify.get_push_token_challenge(p_challenge_id), which returns
// {id, token, token_id, requesting_user, platform, mode, expires_at,
// confirmed_at, consumed_at, attempts, dispatched_at}. The DB verb is the
// rate-limit AUTHORITY; the limits are re-checked here in their own namespace,
// so this edge cannot flood a device even if reached directly. The caller is
// notify.issue_push_token_challenge through pg_net.
//
// requesting_user and token_id (135 @ fb2fd68, closing B's CD-1/CD-2) exist here
// for exactly two purposes: refusing a caller that does not own the challenge,
// and naming the rate-limit namespace. Both are taken from the ROW, never from
// the body, so neither can be chosen by the caller — and NEITHER MAY REACH THE
// PAYLOAD OR A LOG LINE. The push is token-addressed: the row may belong to
// another account, and nothing about its owner may travel to the device or into
// the logs. The suite carries a mutant that logs requesting_user, which fails.
//
// TOKEN-ADDRESSED (D): the token may belong to ANOTHER account — that is the
// point, since the proof goes to the device that holds it. So nothing in the
// payload or the logs may reveal the row's current owner: no user id, no email,
// no device name. `user_id` in the request is the REQUESTER and is used only
// for the rate-limit namespace; it is never sent to the device.
//
// The delivery result is recorded on the challenge row through
// notify.record_push_token_challenge_delivery — a challenge is a control
// message, never an outbox notification, so notify.delivery is not involved.
const CHALLENGE_KIND = 'push_token_challenge';
const MAX_CHALLENGE_ATTEMPTS = 5;
const NEVER_SHARE = 'Snatch It will never ask for this code. Never share this code.';

type ChallengeRow = {
  id: string; token: string; token_id: string; requesting_user: string;
  platform: string | null; mode: 'silent' | 'visible';
  expires_at: string; confirmed_at: string | null; consumed_at: string | null;
  attempts: number | null; dispatched_at: string | null;
};

type RateVerdict = 'allowed' | 'over_limit' | 'error';

function getSecurityHeaders(): Record<string, string> {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'X-DNS-Prefetch-Control': 'off',
    'X-Download-Options': 'noopen',
    'X-Permitted-Cross-Domain-Policies': 'none',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  };
}

const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } });

async function sendChallenge(payload: Record<string, unknown>): Promise<Response> {
  const challengeId = typeof payload.challenge_id === 'string' ? payload.challenge_id : null;
  const nonce       = typeof payload.nonce === 'string' ? payload.nonce : null;
  const userId      = typeof payload.user_id === 'string' ? payload.user_id : null;
  if (!challengeId || !nonce || !userId) {
    return jsonResponse(400, { error: 'Missing challenge_id, nonce or user_id' });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const notify   = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { db: { schema: 'notify' } });

  // Closes over `supabase` so no client type has to be spelled out (the generic
  // parameters of SupabaseClient differ per construction — deno check TS2345).
  const checkRateLimit = async (action: string, max: number, windowSeconds: number): Promise<RateVerdict> => {
    try {
      const { data, error } = await supabase.rpc('check_rate_limit', {
        p_user_id: userId, p_action: action, p_max: max, p_window_seconds: windowSeconds,
      });
      // Never log the caller's payload here — only the verdict.
      if (error) return 'error';
      return data === true ? 'allowed' : 'over_limit';
    } catch {
      return 'error';
    }
  };

  const { data: row, error: rowErr } = await notify.rpc('get_push_token_challenge', { p_challenge_id: challengeId });
  if (rowErr) {
    console.error('send-push challenge: challenge read failed', { challenge_id: challengeId, code: rowErr.code ?? null });
    return jsonResponse(503, { error: 'Service temporarily unavailable' });
  }
  const challenge = (row ?? null) as ChallengeRow | null;
  if (!challenge) return jsonResponse(404, { error: 'Unknown challenge' });
  // Ownership: the body's user_id must BE the challenge's requester. The answer
  // names neither, so it tells a caller nothing about the row it guessed.
  if (challenge.requesting_user !== userId) return jsonResponse(409, { error: 'Challenge does not belong to this user' });
  if (challenge.confirmed_at) return jsonResponse(409, { error: 'Challenge already confirmed' });
  if (challenge.consumed_at) return jsonResponse(409, { error: 'Challenge already consumed' });
  if (new Date(challenge.expires_at).getTime() <= Date.now()) return jsonResponse(410, { error: 'Challenge expired' });
  if ((challenge.attempts ?? 0) >= MAX_CHALLENGE_ATTEMPTS) return jsonResponse(429, { error: 'Too many attempts' });
  if (!challenge.token) return jsonResponse(409, { error: 'Challenge has no token' });

  // The DB verb is the authority; this is the second line, in its own namespace,
  // so a direct call to this edge cannot flood a device. Per D: the token limit
  // is per (token, requesting user).
  // Both parts come from the row (identical to the body's user_id past the check
  // above): the namespace is never one the caller chose. The raw token is NOT a
  // key — token_id is — so no push token is written into public.rate_limits.
  const requester = challenge.requesting_user;
  for (const [action, max] of [
    [`push_challenge_edge_user:${requester}`, 5],
    [`push_challenge_edge_token:${challenge.token_id}:${requester}`, 3],
  ] as Array<[string, number]>) {
    const verdict = await checkRateLimit(action, max, 600);
    if (verdict === 'error') {
      console.warn('send-push challenge: rate limiter failed closed', { challenge_id: challengeId });
      return jsonResponse(503, { error: 'Service temporarily unavailable' });
    }
    if (verdict === 'over_limit') {
      console.warn('send-push challenge: over limit', { challenge_id: challengeId });
      return jsonResponse(429, { error: 'Too many challenge requests' });
    }
  }

  // Proof of possession: the push goes to THIS token, never to the user's others.
  const visible = challenge.mode === 'visible';
  const message = visible
    ? {
        to: challenge.token,
        title: 'Confirm this device',
        body: `Your Snatch It code is ${nonce}. ${NEVER_SHARE}`,
        data: { type: CHALLENGE_KIND, challenge_id: challenge.id },
        sound: 'default' as const,
      }
    : {
        to: challenge.token,
        // Expo's flag for an iOS silent push (it maps to APNs content-available).
        _contentAvailable: true,
        data: { type: CHALLENGE_KIND, challenge_id: challenge.id, nonce },
      };

  // The outcome is recorded on the challenge row; a failure to record is logged
  // and never changes the caller's answer (the push already happened or not).
  const recordDelivery = async (outcome: string, providerMessageId: string | null, error: string | null) => {
    const { error: recErr } = await notify.rpc('record_push_token_challenge_delivery', {
      p_challenge_id: challenge.id, p_outcome: outcome,
      p_provider_message_id: providerMessageId, p_error: error,
    });
    if (recErr) console.warn('send-push challenge: delivery not recorded', { challenge_id: challenge.id, code: recErr.code ?? null });
  };

  let providerOk = false;
  let providerId: string | null = null;
  try {
    const pushRes = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify([message]),
    });
    const pushData = await pushRes.json().catch(() => null);
    const first = (pushData as { data?: Array<{ status?: string; id?: string }> } | null)?.data?.[0] ?? null;
    providerOk = pushRes.ok && (first?.status ?? 'ok') === 'ok';
    providerId = first?.id ?? null;
  } catch (err) {
    // Never echo the payload: it carries the nonce.
    const detail = err instanceof Error ? err.message : 'unknown';
    console.error('send-push challenge: provider call failed', { challenge_id: challengeId, error: detail });
    await recordDelivery('error', null, detail);
    return jsonResponse(502, { error: 'Push provider unavailable' });
  }

  console.log('send-push challenge sent', { challenge_id: challenge.id, mode: challenge.mode, provider_ok: providerOk });
  await recordDelivery(providerOk ? 'sent' : 'rejected', providerId, providerOk ? null : 'provider rejected the message');
  if (!providerOk) return jsonResponse(502, { error: 'Push provider rejected the message' });
  return jsonResponse(200, { sent: 1, mode: challenge.mode, challenge_id: challenge.id, provider_message_id: providerId });
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: getSecurityHeaders() });
  }

  // Reject any caller that is not presenting the service-role key.
  if (!isAuthorized(req)) {
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } },
    );
  }

  // D review SP-1: the body is parsed in its OWN guard. A JSON parse error from
  // V8 quotes a snippet of the input, and a challenge body carries the nonce, so
  // the parse failure must never reach the shared catch that logs err.message.
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    console.warn('send-push: malformed request body');
    return new Response(
      JSON.stringify({ error: 'Malformed request body' }),
      { status: 400, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } },
    );
  }

  try {
    const { user_id, title, body, data } = payload as { user_id?: string; title?: string; body?: string; data?: unknown };

    if (payload?.kind === CHALLENGE_KIND) {
      return await sendChallenge(payload);
    }

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'Missing user_id, title, or body' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: tokens, error: tokensErr } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', user_id)
      .eq('is_active', true)
      .not('token', 'is', null);

    if (tokensErr || !tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0, reason: 'No push tokens found' }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } }
      );
    }

    const messages = tokens.map((t: { token: string }) => ({
      to: t.token,
      title,
      body,
      data: data ?? {},
      sound: 'default' as const,
    }));

    const pushRes = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(messages),
    });

    const pushData = await pushRes.json();

    return new Response(
      JSON.stringify({ sent: messages.length, results: pushData }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } }
    );
  } catch (err) {
    // The error is logged without the request payload: a challenge request
    // carries the nonce, and it must never reach a log line.
    console.error('send-push error:', err instanceof Error ? err.message : 'unknown');
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json', ...getSecurityHeaders() } }
    );
  }
});
