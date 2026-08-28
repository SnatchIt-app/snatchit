/**
 * supabase/functions/delete-account/index.ts
 *
 * Deletes the authenticated user's account.
 *
 * Strategy (App Store compliant, marketplace safe):
 *   1. Block if user has active transfers (pending seller_sent / buyer needs to confirm)
 *   2. Cancel any active listings (set auction_status = 'cancelled')
 *   3. Anonymize user references in payments/transfers using sentinel UUID (legal/financial records kept),
 *      clear every NO ACTION reference to auth.users, delete the user's bids and
 *      reconcile the derived auction head — all inside delete_account_cleanup
 *   4. (bids: now handled in step 3's transaction)
 *   5. Delete storage files RECURSIVELY from avatars, auction-media AND proof-docs,
 *      verifying afterwards that nothing survived
 *   6. Delete auth user (CASCADE handles profiles, push_tokens, notification_preferences)
 *
 * WHAT THIS FUNCTION DOES NOT DO, AND MUST NOT BE DESCRIBED AS DOING:
 *   It does not erase the person. public.payments, public.transfers and
 *   public.listings are retained and repointed to a shared sentinel — which is
 *   PSEUDONYMIZATION, not anonymization: the counterparty, the Stripe payment
 *   intent and the listing's own authored text all remain re-identifying.
 *   Client copy must not claim "permanently deleted" or "all associated data"
 *   (see PHASE_2_CRM_EXPORT_SPEC.md §9.3 for the register that is accurate).
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';

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
// Fail-CLOSED: distinguishes 'allowed' / 'over_limit' / 'error' so callers
// can return 429 vs 503 instead of silently bypassing rate limits on RPC
// errors. Account deletion is irreversible; we will not let a DB hiccup
// open the door to abuse.
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await supabase.rpc('check_rate_limit', {
      p_user_id:        userId,
      p_action:         action,
      p_max:            maxRequests,
      p_window_seconds: windowSeconds,
    });
    if (error) {
      console.warn('Rate limit RPC error (failing closed):', error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn('Rate limit check threw (failing closed):', err);
    return 'error';
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
    // Fail-closed: any RPC failure returns 503 instead of bypassing limits.
    const rl = await checkRateLimit(supabase, userId, 'delete_account', 3, 300);
    if (rl === 'error') {
      return json(
        { error: 'Service temporarily unavailable. Please try again shortly.' },
        503,
        getResponseHeaders(req),
      );
    }
    if (rl === 'over_limit') {
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

    // ── 4. Bids ──────────────────────────────────────────────────────────
    // Deleted INSIDE delete_account_cleanup as of migration 20260828041500, so
    // that the delete and the auction-head reconciliation share one
    // transaction. Deleting them here, in a separate transaction, left
    // listings.current_bid / bid_count / highest_bidder_id describing bids that
    // no longer existed — a phantom high bid nobody could outbid or win. The
    // error return was also discarded, so a failure here silently guaranteed
    // that step 6 would fail on bids.bidder_id. Nothing to do here now.

    // ── 5. Delete storage files ──────────────────────────────────────────
    // Uploads are written TWO levels deep — `<userId>/<folder>/<ts>.<ext>`
    // (src/hooks/useImageUpload.ts:161) — so a non-recursive list(userId)
    // returns FOLDER entries, and remove() was then called on directory
    // prefixes, which is a silent no-op. The error was discarded. Every listing
    // cover, ticket-proof photo and transfer-evidence image therefore survived
    // account deletion permanently. Ticket proofs are screenshots carrying real
    // names, order numbers, barcodes, seat numbers and email addresses.
    //
    // Avatars were the one case that worked, because avatarImage.ts:115 writes
    // a FLAT path. That is why this went unnoticed.
    //
    // `proof-docs` was never listed here at all. It holds BOTH `proofs` and
    // `transfer-evidence` (CreateListingScreen.tsx:195-198,
    // app/transfer/send/[id].tsx:89-92) — the most sensitive of the three.
    const BUCKETS = ['avatars', 'auction-media', 'proof-docs'] as const;

    /** Recursively collect every object path under a prefix. */
    async function collectPaths(bucket: string, prefix: string): Promise<string[]> {
      const out: string[] = [];
      const { data, error } = await supabase.storage
        .from(bucket)
        .list(prefix, { limit: 1000 });
      if (error) throw new Error(`list ${bucket}/${prefix}: ${error.message}`);
      for (const entry of data ?? []) {
        const child = `${prefix}/${entry.name}`;
        // A storage "folder" is a synthetic entry with no id and no metadata.
        if (entry.id === null || entry.metadata === null) {
          out.push(...(await collectPaths(bucket, child)));
        } else {
          out.push(child);
        }
      }
      return out;
    }

    let storageFullyCleared = true;
    for (const bucket of BUCKETS) {
      try {
        const paths = await collectPaths(bucket, userId);
        if (paths.length === 0) continue;

        // remove() accepts at most 1000 keys per call.
        for (let i = 0; i < paths.length; i += 1000) {
          const { error: rmErr } = await supabase.storage
            .from(bucket)
            .remove(paths.slice(i, i + 1000));
          if (rmErr) throw new Error(`remove ${bucket}: ${rmErr.message}`);
        }

        // Verify rather than assume. The previous implementation "succeeded" on
        // every call while deleting nothing, for years.
        const leftover = await collectPaths(bucket, userId);
        if (leftover.length > 0) {
          storageFullyCleared = false;
          console.error(
            `[delete-account] ${bucket}: ${leftover.length} object(s) survived removal`,
          );
        } else {
          console.log(`[delete-account] ${bucket}: removed ${paths.length} object(s)`);
        }
      } catch (e) {
        storageFullyCleared = false;
        console.error(`[delete-account] storage cleanup failed for ${bucket}:`, e);
        captureException(e, { userId, bucket, step: 'storage-cleanup' });
      }
    }

    if (!storageFullyCleared) {
      // Do not delete the auth row while the user's uploaded files are still
      // there — that is the state that leaves ticket-proof photos with no owner
      // and no way to find them. The auth row is still present at this point,
      // so the whole operation is safely retryable.
      return json({
        error: 'Could not remove all of your uploaded files. Your account has not been deleted. Please try again, or contact support.',
      }, 500, getResponseHeaders(req));
    }

    // ── 6. Delete auth user ──────────────────────────────────────────────
    // CASCADE handles: profiles, push_tokens, notification_preferences
    const { error: deleteErr } = await supabase.auth.admin.deleteUser(userId);

    if (deleteErr) {
      // This is the branch that used to leave a half-deleted account behind: the
      // cleanup RPC had already committed, and a 23503 here returned a bare 500
      // with no Sentry event. It is now much harder to reach — the cleanup clears
      // every NO ACTION reference before we get here — but if it still fires,
      // the operator must find out, because the user's history is already
      // anonymized and their account is still live.
      console.error('[delete-account] auth delete error:', deleteErr.message);
      captureException(new Error(`auth.admin.deleteUser failed: ${deleteErr.message}`), {
        userId,
        step: 'auth-delete',
        note: 'cleanup RPC already committed — account is in a half-deleted state',
      });
      return json({ error: 'Failed to delete account. Please contact support.' }, 500, getResponseHeaders(req));
    }

    console.log('[delete-account] completed for user:', userId);
    return json({ success: true }, 200, getResponseHeaders(req));

  } catch (err) {
    // Account deletion is irreversible — every unexpected failure here
    // demands ops attention, so capture unconditionally.
    await captureException('delete-account', err);
    return json({ error: 'Internal server error' }, 500, getResponseHeaders(req));
  }
});
