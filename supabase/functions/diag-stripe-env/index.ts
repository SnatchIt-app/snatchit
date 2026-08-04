/**
 * diag-stripe-env — TEMPORARY production diagnostic (2026-07-30 incident).
 *
 * Reports the *shape* of STRIPE_SECRET_KEY and the result of a live
 * GET /v1/account probe. It NEVER returns key material: only the 8-char
 * prefix (sk_live_ / sk_test_ / pk_live_ …), the length, whitespace flags,
 * and Stripe's own response (account id or error type/message).
 *
 * Purpose: distinguish, with evidence, between
 *   (a) malformed env value (whitespace/quotes → header construction throws), and
 *   (b) a key Stripe does not recognise (401, no account attribution → no logs).
 *
 * DELETE after the incident is closed.
 */
const getResponseHeaders = (): Record<string, string> => ({
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
});

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: getResponseHeaders() });
  }

  const raw = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  const trimmed = raw.trim();

  const shape = {
    present:          raw.length > 0,
    length:           raw.length,
    trimmed_length:   trimmed.length,
    has_whitespace:   raw !== trimmed,
    has_trailing_nl:  /[\r\n]$/.test(raw),
    has_quotes:       /^["']|["']$/.test(raw),
    has_inner_space:  /\s/.test(trimmed),
    prefix:           trimmed.slice(0, 8),
    looks_like_secret: trimmed.startsWith('sk_'),
    mode:             trimmed.startsWith('sk_live_') ? 'live'
                    : trimmed.startsWith('sk_test_') ? 'test'
                    : 'unknown',
  };

  // Probe with the RAW value exactly as the app code uses it today.
  let raw_probe: Record<string, unknown>;
  try {
    const res = await fetch('https://api.stripe.com/v1/account', {
      headers: { Authorization: `Bearer ${raw}` },
    });
    const body = await res.json().catch(() => ({}));
    raw_probe = {
      transport: 'ok',
      status:    res.status,
      account:   (body as { id?: string }).id ?? null,
      error:     (body as { error?: { type?: string; message?: string } }).error
        ? {
            type:    (body as { error: { type?: string } }).error.type,
            message: (body as { error: { message?: string } }).error.message,
          }
        : null,
    };
  } catch (e) {
    // A throw here means the request never left the runtime — e.g. an
    // invalid header value caused by whitespace in the secret.
    raw_probe = {
      transport: 'threw',
      error:     e instanceof Error ? `${e.name}: ${e.message}` : String(e),
    };
  }

  // Probe with the TRIMMED value to prove whether trimming alone fixes it.
  let trimmed_probe: Record<string, unknown>;
  try {
    const res = await fetch('https://api.stripe.com/v1/account', {
      headers: { Authorization: `Bearer ${trimmed}` },
    });
    const body = await res.json().catch(() => ({}));
    trimmed_probe = {
      transport: 'ok',
      status:    res.status,
      account:   (body as { id?: string }).id ?? null,
      error:     (body as { error?: { type?: string; message?: string } }).error
        ? {
            type:    (body as { error: { type?: string } }).error.type,
            message: (body as { error: { message?: string } }).error.message,
          }
        : null,
    };
  } catch (e) {
    trimmed_probe = {
      transport: 'threw',
      error:     e instanceof Error ? `${e.name}: ${e.message}` : String(e),
    };
  }

  const whsec = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';
  const webhook_shape = {
    present:         whsec.length > 0,
    length:          whsec.length,
    has_whitespace:  whsec !== whsec.trim(),
    has_quotes:      /^["']|["']$/.test(whsec),
    prefix:          whsec.trim().slice(0, 6),
  };

  // ── Chain verification (only meaningful once the key authenticates) ──
  const authed = (trimmed_probe as { account?: string | null }).account != null;
  let webhook_endpoints: unknown = 'skipped — key not authenticating';
  let connect_accounts:  unknown = 'skipped — key not authenticating';

  if (authed) {
    const get = async (path: string) => {
      const r = await fetch(`https://api.stripe.com/v1${path}`, {
        headers: { Authorization: `Bearer ${trimmed}` },
      });
      return await r.json().catch(() => ({}));
    };

    const we = await get('/webhook_endpoints?limit=10');
    webhook_endpoints = (we as { data?: Array<Record<string, unknown>> }).data?.map((e) => ({
      url:            e.url,
      status:         e.status,
      livemode:       e.livemode,
      enabled_events: e.enabled_events,
      // secret is NEVER returned by this endpoint after creation — safe.
    })) ?? we;

    const ca = await get('/accounts?limit=10');
    connect_accounts = (ca as { data?: Array<Record<string, unknown>> }).data?.map((a) => ({
      id:               a.id,
      livemode:         a.livemode,
      charges_enabled:  a.charges_enabled,
      payouts_enabled:  a.payouts_enabled,
      details_submitted: a.details_submitted,
    })) ?? ca;
  }

  // Body is read exactly once and reused by both the lookup and cancel blocks.
  const reqBody: Record<string, unknown> = authed
    ? await req.json().catch(() => ({}))
    : {};

  // Optional: inspect a specific PaymentIntent (id only, via request body).
  // Returns only non-sensitive fields — never the client_secret.
  let payment_intent: unknown = null;
  if (authed) {
    try {
      const piId = (reqBody as { pi_id?: string }).pi_id;
      if (piId && /^pi_[A-Za-z0-9]+$/.test(piId)) {
        const r = await fetch(`https://api.stripe.com/v1/payment_intents/${piId}`, {
          headers: { Authorization: `Bearer ${trimmed}` },
        });
        const d = await r.json().catch(() => ({}));
        payment_intent = r.ok
          ? {
              id:        d.id,
              status:    d.status,
              amount:    d.amount,
              currency:  d.currency,
              livemode:  d.livemode,
              metadata:  d.metadata,
              created:   d.created,
            }
          : { error: (d as { error?: { message?: string } }).error?.message ?? `HTTP ${r.status}` };
      }
    } catch { /* ignore malformed body */ }
  }

  // Optional: cancel a stuck (never-confirmed) PaymentIntent, via request body.
  let cancel_result: unknown = null;
  if (authed) {
    try {
      const cancelId = (reqBody as { cancel_pi?: string }).cancel_pi;
      if (cancelId && /^pi_[A-Za-z0-9]+$/.test(cancelId)) {
        const r = await fetch(`https://api.stripe.com/v1/payment_intents/${cancelId}/cancel`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${trimmed}` },
        });
        const d = await r.json().catch(() => ({}));
        cancel_result = r.ok
          ? { id: d.id, status: d.status }
          : { error: (d as { error?: { message?: string } }).error?.message ?? `HTTP ${r.status}` };
      }
    } catch { /* ignore malformed body */ }
  }

  return new Response(
    JSON.stringify(
      { shape, raw_probe, trimmed_probe, webhook_shape, webhook_endpoints, connect_accounts, payment_intent, cancel_result },
      null,
      2,
    ),
    { headers: { 'Content-Type': 'application/json', ...getResponseHeaders() } },
  );
});
