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

  // Optional: probe a specific Connect account id against the CURRENT key's
  // mode. 404/permission error here proves the id does not exist in this
  // mode (i.e. a test-mode account probed with the live key).
  let connect_account_probe: unknown = null;
  if (authed) {
    try {
      const acctId = (reqBody as { acct_id?: string }).acct_id;
      if (acctId && /^acct_[A-Za-z0-9]+$/.test(acctId)) {
        const r = await fetch(`https://api.stripe.com/v1/accounts/${acctId}`, {
          headers: { Authorization: `Bearer ${trimmed}` },
        });
        const d = await r.json().catch(() => ({})) as Record<string, unknown>;
        const req = (d.requirements ?? {}) as Record<string, unknown>;
        connect_account_probe = r.ok
          ? {
              id:                d.id,
              type:              d.type,
              charges_enabled:   d.charges_enabled,
              payouts_enabled:   d.payouts_enabled,
              details_submitted: d.details_submitted,
              capabilities:      d.capabilities ?? null,
              requirements: {
                currently_due:   req.currently_due ?? null,
                past_due:        req.past_due ?? null,
                disabled_reason: req.disabled_reason ?? null,
              },
            }
          : {
              http_status: r.status,
              error: (d as { error?: { message?: string } }).error?.message ?? `HTTP ${r.status}`,
            };
      }
    } catch { /* ignore malformed body */ }
  }

  // Optional: platform balance (read-only) — payout funding forensics.
  let balance: unknown = null;
  if (authed) {
    try {
      if ((reqBody as { balance?: boolean }).balance === true) {
        const r = await fetch('https://api.stripe.com/v1/balance', {
          headers: { Authorization: `Bearer ${trimmed}` },
        });
        const d = await r.json().catch(() => ({})) as Record<string, unknown>;
        balance = r.ok
          ? { available: d.available, pending: d.pending, livemode: d.livemode }
          : { error: `HTTP ${r.status}` };
      }
    } catch { /* ignore malformed body */ }
  }

  // Optional: PI funding forensics (read-only) — PI → latest charge →
  // balance transaction (status / available_on / net / fee) in one call.
  let pi_forensics: unknown = null;
  if (authed) {
    try {
      const fid = (reqBody as { pi_forensics?: string }).pi_forensics;
      if (fid && /^pi_[A-Za-z0-9]+$/.test(fid)) {
        const r = await fetch(
          `https://api.stripe.com/v1/payment_intents/${fid}?expand[]=latest_charge.balance_transaction`,
          { headers: { Authorization: `Bearer ${trimmed}` } },
        );
        const d = await r.json().catch(() => ({})) as Record<string, unknown>;
        const ch = (d.latest_charge ?? {}) as Record<string, unknown>;
        const bt = (ch.balance_transaction ?? {}) as Record<string, unknown>;
        pi_forensics = r.ok
          ? {
              pi: { id: d.id, status: d.status, amount: d.amount, livemode: d.livemode, created: d.created },
              charge: {
                id: ch.id, paid: ch.paid, amount: ch.amount, created: ch.created,
                application_fee_amount: ch.application_fee_amount ?? null,
              },
              balance_transaction: {
                id: bt.id, status: bt.status, amount: bt.amount, net: bt.net,
                fee: bt.fee, available_on: bt.available_on, currency: bt.currency,
              },
            }
          : { error: (d as { error?: { message?: string } }).error?.message ?? `HTTP ${r.status}` };
      }
    } catch { /* ignore malformed body */ }
  }

  // Optional: list live-mode Transfers (read-only) — duplicate-payout audit.
  let transfers_list: unknown = null;
  if (authed) {
    try {
      if ((reqBody as { list_transfers?: boolean }).list_transfers === true) {
        const r = await fetch('https://api.stripe.com/v1/transfers?limit=10', {
          headers: { Authorization: `Bearer ${trimmed}` },
        });
        const d = await r.json().catch(() => ({})) as { data?: Array<Record<string, unknown>> };
        transfers_list = r.ok
          ? (d.data ?? []).map((t) => ({
              id: t.id, amount: t.amount, currency: t.currency,
              destination: t.destination, created: t.created, reversed: t.reversed,
            }))
          : { error: `HTTP ${r.status}` };
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
      { shape, raw_probe, trimmed_probe, webhook_shape, webhook_endpoints, connect_accounts, payment_intent, connect_account_probe, balance, pi_forensics, transfers_list, cancel_result },
      null,
      2,
    ),
    { headers: { 'Content-Type': 'application/json', ...getResponseHeaders() } },
  );
});
