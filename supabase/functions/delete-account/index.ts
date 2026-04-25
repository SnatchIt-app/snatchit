/**
 * supabase/functions/delete-account/index.ts
 *
 * Deletes the authenticated user's account.
 *
 * Strategy (App Store compliant, marketplace safe):
 *   1. Block if user has active transfers (pending seller_sent / buyer needs to confirm)
 *   2. Cancel any active listings (set auction_status = 'cancelled')
 *   3. Anonymize user references in payments/transfers using sentinel UUID (legal/financial records kept)
 *   4. Delete bids placed by user
 *   5. Delete storage files (avatars, auction-media)
 *   6. Delete auth user (CASCADE handles profiles, push_tokens, notification_preferences)
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Sentinel UUID for anonymized financial records. Payments and transfers have
// NOT NULL constraints on buyer_id/seller_id, so we replace the real user ID
// with this placeholder rather than setting NULL. A matching row exists in
// auth.users and profiles (created by migration 019).
const ANONYMIZED_USER_ID = '00000000-0000-0000-0000-000000000000';

// ── CORS origin whitelist ────────────────────────────────────────────────────
// React Native apps don't send an Origin header, so CORS only affects
// browser-based requests. Restrict to known web domains.
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

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Returns true if the request is within limits (or if the DB check fails —
// fail-open so a DB hiccup never blocks a legitimate deletion).
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

function json(body: Record<string, unknown>, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: getResponseHeaders(req) });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing authorization' }, 401, getResponseHeaders(req));
    }

    const token = authHeader.replace('Bearer ', '');
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Verify token and get user
    const userClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user }, error: authErr } = await userClient.auth.getUser(token);

    if (authErr || !user) {
      return json({ error: 'Invalid or expired token' }, 401, getResponseHeaders(req));
    }

    const userId = user.id;

    // ── Rate limit ───────────────────────────────────────────────────────
    // 3 requests per 300 seconds (5 minutes). Account deletion is rare;
    // anything faster is likely abuse or a runaway retry loop.
    const withinLimit = await checkRateLimit(supabase, userId, 'delete_account', 3, 300);
    if (!withinLimit) {
      return json({ error: 'Too many requests. Please try again later.' }, 429, getResponseHeaders(req));
    }

    console.log('[delete-account] starting for user:', userId);

    // ── 1. Block if active transfers in progress ─────────────────────────
    const { data: activeTransfers } = await supabase
      .from('transfers')
      .select('id')
      .or(`seller_id.eq.${userId},buyer_id.eq.${userId}`)
      .in('status', ['pending', 'seller_sent'])
      .limit(1);

    if (activeTransfers && activeTransfers.length > 0) {
      return json({
        error: 'You have active ticket transfers in progress. Please complete or wait for them to expire before deleting your account.',
      }, 409, getResponseHeaders(req));
    }

    // ── 2 & 3. Cancel listings + anonymize financial records ────────────
    // Uses the delete_account_cleanup RPC (migration 020) which runs as
    // SECURITY DEFINER to bypass:
    //   - guard_listing_state_columns (blocks direct auction_status changes)
    //   - guard_listing_identity_columns (blocks ALL seller_id changes)
    // The RPC cancels active listings, anonymizes seller_id on all listings,
    // and anonymizes buyer_id/seller_id on payments and transfers using the
    // sentinel UUID (00000000-0000-0000-0000-000000000000).
    const { error: cleanupErr } = await supabase.rpc('delete_account_cleanup', {
      p_user_id: userId,
    });

    if (cleanupErr) {
      console.error('[delete-account] cleanup RPC error:', cleanupErr.message);
      return json({
        error: 'Failed to clean up account data. Please try again or contact support.',
      }, 500, getResponseHeaders(req));
    }

    console.log('[delete-account] listings cancelled and financial records anonymized');

    // ── 4. Delete bids ───────────────────────────────────────────────────
    await supabase
      .from('bids')
      .delete()
      .eq('bidder_id', userId);

    // ── 5. Delete storage files ──────────────────────────────────────────
    // Avatars
    try {
      const { data: avatarFiles } = await supabase.storage
        .from('avatars')
        .list(userId);
      if (avatarFiles && avatarFiles.length > 0) {
        const paths = avatarFiles.map(f => `${userId}/${f.name}`);
        await supabase.storage.from('avatars').remove(paths);
      }
    } catch {
      console.warn('[delete-account] avatar cleanup error (non-fatal)');
    }

    // Auction media
    try {
      const { data: mediaFiles } = await supabase.storage
        .from('auction-media')
        .list(userId);
      if (mediaFiles && mediaFiles.length > 0) {
        const paths = mediaFiles.map(f => `${userId}/${f.name}`);
        await supabase.storage.from('auction-media').remove(paths);
      }
    } catch {
      console.warn('[delete-account] media cleanup error (non-fatal)');
    }

    // ── 6. Delete auth user ──────────────────────────────────────────────
    // CASCADE handles: profiles, push_tokens, notification_preferences
    const { error: deleteErr } = await supabase.auth.admin.deleteUser(userId);

    if (deleteErr) {
      console.error('[delete-account] auth delete error:', deleteErr.message);
      return json({ error: 'Failed to delete account. Please contact support.' }, 500, getResponseHeaders(req));
    }

    console.log('[delete-account] completed for user:', userId);
    return json({ success: true }, 200, getResponseHeaders(req));

  } catch (err) {
    console.error('[delete-account] unexpected error:', err);
    return json({ error: 'Internal server error' }, 500, getResponseHeaders(req));
  }
});
