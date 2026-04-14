import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── CORS origin whitelist ────────────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  'https://snatchitapp.com',
  'https://www.snatchitapp.com',
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

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

function getResponseHeaders(req: Request): Record<string, string> {
  return {
    ...getCorsHeaders(req),
    ...getSecurityHeaders(),
  };
}

async function getAuthenticatedUserId(req: Request): Promise<string> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    throw new Error('Missing or invalid Authorization header');
  }

  const token = authHeader.replace('Bearer ', '');

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    throw new Error('Invalid or expired token');
  }

  return user.id;
}

// ── Rate limiting ─────────────────────────────────────────────────────────────
async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('check_rate_limit', {
      p_user_id:        userId,
      p_action:         action,
      p_max:            maxRequests,
      p_window_seconds: windowSeconds,
    });
    if (error) {
      console.warn('Rate limit RPC error (failing open):', error.message);
      return true;
    }
    return data === true;
  } catch (err) {
    console.warn('Rate limit check threw (failing open):', err);
    return true;
  }
}

const STRIPE_API_BASE = 'https://api.stripe.com/v1/';
const REFRESH_URL = 'https://project-tsnbr.vercel.app/payout-refresh';
const RETURN_URL = 'https://project-tsnbr.vercel.app/payout-return';

function stripeUrl(path: string): string {
  const url = new URL(path.replace(/^\//, ''), STRIPE_API_BASE).toString();
  return url;
}

async function stripeGet(path: string) {
  const url = stripeUrl(path);
  console.log('[stripeGet] url:', url, 'path:', path);
  const res = await fetch(url, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
    },
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? 'Stripe API error');
  return data;
}

async function stripePost(path: string, body: Record<string, string>) {
  const url = stripeUrl(path);
  console.log('[stripePost] url:', url, 'path:', path, 'bodyKeys:', Object.keys(body));
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(body).toString(),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? 'Stripe API error');
  return data;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  try {
    const userId = await getAuthenticatedUserId(req);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const reqBody = await req.json();
    const { status_only } = reqBody;

    // Rate limit only mutating calls (account creation, link generation).
    // status_only is a read-only check and must never be rate-limited —
    // the client fires it on mount, focus, and foreground.
    if (!status_only) {
      const allowed = await checkRateLimit(supabase, userId, 'create-connect-account', 5, 600);
      if (!allowed) {
        return new Response(
          JSON.stringify({ error: 'Too many requests. Please try again later.' }),
          {
            status: 429,
            headers: {
              'Content-Type': 'application/json',
              'Retry-After': '600',
              ...getResponseHeaders(req),
            },
          },
        );
      }
    }

    // Validate redirect URLs at startup — fail fast if misconfigured
    if (!REFRESH_URL.startsWith('https://') || !RETURN_URL.startsWith('https://')) {
      throw new Error('Invalid Stripe redirect URLs');
    }

    console.log('[create-connect-account] URLs:', { refresh_url: REFRESH_URL, return_url: RETURN_URL, status_only });

    // Check if user already has a Connect account
    const { data: profile, error: profileErr } = await supabase
      .from('profiles')
      .select('stripe_connect_id')
      .eq('id', userId)
      .single();

    if (profileErr) {
      return new Response(
        JSON.stringify({ error: 'Profile not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    let accountId = profile.stripe_connect_id;

    console.log('[create-connect-account] accountId:', accountId, 'status_only:', status_only);

    // status_only + no account = not_connected, skip account creation
    if (status_only && !accountId) {
      return new Response(
        JSON.stringify({ status: 'not_connected' }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    if (!accountId) {
      // Create new Express account
      const account = await stripePost('accounts', {
        'type': 'express',
        'metadata[user_id]': userId,
      });
      accountId = account.id;

      // Save to profile
      const { error: updateErr } = await supabase
        .from('profiles')
        .update({ stripe_connect_id: accountId })
        .eq('id', userId);

      if (updateErr) {
        console.error('Failed to save stripe_connect_id:', updateErr);
        return new Response(
          JSON.stringify({ error: 'Failed to save account' }),
          { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
    }

    // Check whether the account has completed onboarding
    const account = await stripeGet(`accounts/${accountId}`);
    const detailsSubmitted = !!account.details_submitted;

    // If onboarding is complete, persist that in our DB so the client can
    // display the correct state without calling this function every time.
    if (detailsSubmitted) {
      await supabase
        .from('profiles')
        .update({ stripe_onboarding_complete: true })
        .eq('id', userId);
    }

    // ── status_only mode: return state without generating a link ──────────
    if (status_only) {
      const status = !accountId
        ? 'not_connected'
        : detailsSubmitted
          ? 'connected'
          : 'onboarding_required';
      return new Response(
        JSON.stringify({ status, account_id: accountId }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    if (detailsSubmitted) {
      // Already onboarded — create an Express Dashboard login link
      const loginLink = await stripePost(`accounts/${accountId}/login_links`, {});
      const dashboardUrl = loginLink?.url;

      if (!dashboardUrl || typeof dashboardUrl !== 'string' || !dashboardUrl.startsWith('https://')) {
        console.error('create-connect-account: invalid login_link URL from Stripe:', dashboardUrl);
        return new Response(
          JSON.stringify({ error: 'Unable to generate payout dashboard link. Please try again.', status: 'connected' }),
          { status: 502, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }

      return new Response(
        JSON.stringify({ url: dashboardUrl, account_id: accountId, status: 'connected' }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Not yet onboarded — create an onboarding account link
    console.log('[create-connect-account] onboarding link params:', JSON.stringify({
      account: accountId,
      refresh_url: REFRESH_URL,
      return_url: RETURN_URL,
    }));
    const accountLink = await stripePost('account_links', {
      'account': accountId,
      'refresh_url': REFRESH_URL,
      'return_url': RETURN_URL,
      'type': 'account_onboarding',
    });

    const onboardingUrl = accountLink?.url;

    if (!onboardingUrl || typeof onboardingUrl !== 'string' || !onboardingUrl.startsWith('https://')) {
      console.error('create-connect-account: invalid account_link URL from Stripe:', onboardingUrl);
      return new Response(
        JSON.stringify({ error: 'Unable to generate onboarding link. Please try again.', status: 'onboarding_required' }),
        { status: 502, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    return new Response(
      JSON.stringify({ url: onboardingUrl, account_id: accountId, status: 'onboarding_required' }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  } catch (err) {
    console.error('Connect account error:', err);
    const message = err instanceof Error ? err.message : '';
    const isAuthError = /authorization|token/i.test(message);
    return new Response(
      JSON.stringify({ error: message || 'Internal server error' }),
      { status: isAuthError ? 401 : 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});
