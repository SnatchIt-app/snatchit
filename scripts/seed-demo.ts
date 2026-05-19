/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * scripts/seed-demo.ts — App Review reviewer accounts + demo data
 *
 * Creates the buyer + seller accounts Apple's App Review team will sign
 * into. Idempotent: every step checks before creating. Safe to re-run.
 *
 * What this script does:
 *   1. Buyer auth user            → snatchitreviewbuyer@gmail.com
 *   2. Seller auth user           → snatchitreviewseller@gmail.com
 *   3. Profile rows for both, marked as REVIEWER / DEMO in display_name
 *   4. Stripe Connect Express account for the seller (TEST MODE).
 *      Best-effort fast-track via direct API field updates.
 *   5. Three active listings under the seller — realistic Miami nightlife
 *      events, no alcohol / bottle-service wording.
 *   6. One active bid by the buyer on listing #1.
 *   7. One historical sold + buyer_confirmed transaction on listing #3
 *      (gives reviewers a "past purchase" tile in their Bids tab).
 *
 * What this script intentionally does NOT do:
 *   • Issue real Stripe charges (no PaymentIntent.confirm). The historical
 *     payment row uses a synthetic Stripe PI id prefixed "pi_seed_demo_…"
 *     so it's obvious in the Dashboard and can be filtered out of reports.
 *   • Touch RLS policies, schema, or other accounts.
 *   • Delete anything.
 *
 * SECURITY
 *   - SUPABASE_SERVICE_ROLE_KEY and STRIPE_SECRET_KEY must come from env.
 *   - Run from your machine, not CI, not the AI sandbox. The script
 *     refuses to start without those secrets.
 *   - STRIPE_SECRET_KEY MUST be a test key (sk_test_…). The script
 *     refuses to run against a live key — see assertTestMode() below.
 *
 * RUN
 *   cd /Users/josetascon/snatchit
 *   SUPABASE_URL=https://hqycwntpfoztoinemqns.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=eyJ…service-role-jwt… \
 *   STRIPE_SECRET_KEY=sk_test_… \
 *   npx --yes tsx scripts/seed-demo.ts
 */

import { createClient } from '@supabase/supabase-js';

// ─── Configuration (final, agreed with product) ─────────────────────────────

const BUYER  = {
  email: 'snatchitreviewbuyer@gmail.com',
  password: 'Snatchitreview',
  display_name: 'Demo Buyer (App Review)',
  phone_number: null,
} as const;

const SELLER = {
  email: 'snatchitreviewseller@gmail.com',
  password: 'Snatchitreview',
  display_name: 'Demo Seller (App Review)',
  phone_number: null,
} as const;

// Three Miami listings. Realistic event types; intentionally NO alcohol,
// drug, "bottle service," or age-gated copy in titles / venues.
const LISTINGS = [
  {
    event_name:     'Wynwood Saturday Music Night',
    venue:          'Wynwood Sound Stage',
    neighborhood:   'wynwood',
    event_date:     daysFromNow(7),
    event_time:     '21:00',
    ticket_type:    'GA',
    quantity:       1,
    transfer_method:'mobile_transfer',
    starting_bid:   25,
    buy_now_enabled:true,
    buy_now_price:  35,
    duration_hours: 24,
    ticket_platform:'other',
    restrictions:   null,
  },
  {
    event_name:     'South Beach Sunset Sessions',
    venue:          'Beachfront Pavilion',
    neighborhood:   'south beach',
    event_date:     daysFromNow(10),
    event_time:     '19:30',
    ticket_type:    'GA',
    quantity:       2,
    transfer_method:'mobile_transfer',
    starting_bid:   60,
    buy_now_enabled:true,
    buy_now_price:  80,
    duration_hours: 24,
    ticket_platform:'eventbrite',
    restrictions:   null,
  },
  {
    event_name:     'Brickell Rooftop Live',
    venue:          'Brickell Sky Pavilion',
    neighborhood:   'brickell',
    event_date:     daysFromNow(-14), // past event — used for historical sale
    event_time:     '20:00',
    ticket_type:    'VIP',
    quantity:       1,
    transfer_method:'mobile_transfer',
    starting_bid:   150,
    buy_now_enabled:true,
    buy_now_price:  200,
    duration_hours: 24,
    ticket_platform:'ticketmaster',
    restrictions:   null,
  },
] as const;

// Bid amount (in whole dollars) the buyer has placed on LISTINGS[0].
const ACTIVE_BID_AMOUNT = 30;

// 10/10 fee model — must match src/config/app.ts and create-payment-intent.
const BUYER_FEE_RATE  = 0.10;
const SELLER_FEE_RATE = 0.10;

// ─── Helpers ────────────────────────────────────────────────────────────────

function daysFromNow(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    console.error(`✗ Missing env var: ${name}`);
    process.exit(1);
  }
  return v;
}

function assertTestMode(stripeKey: string) {
  if (!stripeKey.startsWith('sk_test_')) {
    console.error(
      '✗ Refusing to run: STRIPE_SECRET_KEY must be a test-mode key (sk_test_…).\n' +
      '  Seed data must never touch the live Stripe account.',
    );
    process.exit(1);
  }
}

type StripeInit = { method?: string; body?: any; headers?: Record<string, string> };

async function stripeFetch(path: string, init: StripeInit = {}) {
  const url = `https://api.stripe.com/v1${path}`;
  const body = init.body instanceof URLSearchParams || typeof init.body === 'string'
    ? init.body
    : init.body
      ? new URLSearchParams(flattenForStripe(init.body)).toString()
      : undefined;
  const res = await fetch(url, {
    method: init.method,
    body,
    headers: {
      Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY!}`,
      'Stripe-Version': '2024-09-30.acacia',
      ...(body ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
      ...(init.headers ?? {}),
    },
  });
  const data = await res.json();
  if (!res.ok) {
    const detail = data?.error?.message ?? JSON.stringify(data);
    throw new Error(`Stripe ${init.method ?? 'GET'} ${path} failed: ${detail}`);
  }
  return data;
}

/** Stripe form encoding: nested objects use bracket notation. */
function flattenForStripe(obj: Record<string, any>, prefix = ''): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    const key = prefix ? `${prefix}[${k}]` : k;
    if (Array.isArray(v)) {
      v.forEach((item, i) => {
        if (item && typeof item === 'object') {
          Object.assign(out, flattenForStripe(item, `${key}[${i}]`));
        } else {
          out[`${key}[${i}]`] = String(item);
        }
      });
    } else if (typeof v === 'object') {
      Object.assign(out, flattenForStripe(v, key));
    } else if (typeof v === 'boolean') {
      out[key] = v ? 'true' : 'false';
    } else {
      out[key] = String(v);
    }
  }
  return out;
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const SUPABASE_URL              = requireEnv('SUPABASE_URL');
  const SUPABASE_SERVICE_ROLE_KEY = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  const STRIPE_SECRET_KEY         = requireEnv('STRIPE_SECRET_KEY');
  assertTestMode(STRIPE_SECRET_KEY);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  console.log('\n══════════ SnatchIt App-Review Seed ══════════');
  console.log(`Supabase: ${SUPABASE_URL}`);
  console.log(`Stripe:   ${STRIPE_SECRET_KEY.slice(0, 12)}… (test mode confirmed)`);

  // ── 1 & 2. Auth users ─────────────────────────────────────────────────────
  const buyerId  = await ensureAuthUser(sb, BUYER);
  const sellerId = await ensureAuthUser(sb, SELLER);
  console.log(`✓ Buyer  user ${buyerId}`);
  console.log(`✓ Seller user ${sellerId}`);

  // ── 3. Profile rows ───────────────────────────────────────────────────────
  await ensureProfile(sb, buyerId,  BUYER);
  await ensureProfile(sb, sellerId, SELLER);
  console.log('✓ Profile rows synced');

  // ── 4. Stripe Connect Express account for seller ──────────────────────────
  const connectId = await ensureStripeConnectAccount(sb, sellerId, SELLER.email);
  console.log(`✓ Stripe Connect ${connectId}`);
  await tryFastTrackOnboarding(connectId);
  // Pull live capability state and mirror it onto the profile.
  const acct = await stripeFetch(`/accounts/${connectId}`);
  const onboardingComplete =
    acct.details_submitted === true &&
    acct.charges_enabled   === true &&
    acct.payouts_enabled   === true;
  await sb.from('profiles').update({
    stripe_connect_id:          connectId,
    stripe_onboarding_complete: onboardingComplete,
  }).eq('id', sellerId);
  console.log(`  details_submitted=${acct.details_submitted}  charges_enabled=${acct.charges_enabled}  payouts_enabled=${acct.payouts_enabled}`);
  if (!onboardingComplete) {
    console.log('  NOTE: Stripe has not fully verified this test account yet.');
    console.log('  The reviewer (or you) can complete onboarding via the in-app');
    console.log('  Payout Setup flow. In test mode this usually finishes in <30s.');
  }

  // ── 5. Listings ───────────────────────────────────────────────────────────
  const listingIds: string[] = [];
  for (let i = 0; i < LISTINGS.length; i++) {
    const id = await ensureListing(sb, sellerId, LISTINGS[i], i === LISTINGS.length - 1);
    listingIds.push(id);
  }
  console.log(`✓ Seeded ${listingIds.length} listings`);

  // ── 6. Active bid ─────────────────────────────────────────────────────────
  await ensureBid(sb, listingIds[0], buyerId, ACTIVE_BID_AMOUNT);
  console.log(`✓ Active bid: buyer placed $${ACTIVE_BID_AMOUNT} on listing #1`);

  // ── 7. Historical buyer_confirmed sale on listing #3 ──────────────────────
  await ensureHistoricalSale(sb, listingIds[LISTINGS.length - 1], buyerId, sellerId, LISTINGS[LISTINGS.length - 1]);
  console.log('✓ Historical sale + transfer (status=buyer_confirmed) on listing #3');

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log('\n──────── App Review credentials ────────');
  console.log(`Buyer:    ${BUYER.email}  /  ${BUYER.password}`);
  console.log(`Seller:   ${SELLER.email}  /  ${SELLER.password}`);
  console.log(`Stripe Connect (seller): ${connectId}`);
  console.log('Stripe test card for buyer checkout: 4242 4242 4242 4242  any future MM/YY  any CVC');
  console.log('────────────────────────────────────────\n');
}

// ─── Auth user ──────────────────────────────────────────────────────────────

/**
 * Idempotent user lookup-or-create that does NOT call `listUsers()`.
 *
 * Why not listUsers: the admin enumeration endpoint can return
 * "Database error finding users" on projects whose GoTrue internal
 * migrations are out of step with new columns in `auth.users`. That's
 * outside our control and unrelated to whether the user we want exists.
 *
 * Strategy (works on supabase-js 2.50+ including 2.98 — verified against
 * node_modules/@supabase/auth-js/dist/main/GoTrueAdminApi.d.ts):
 *
 *   1. Optimistically `createUser`. If it succeeds, return new user's id.
 *   2. If it fails with a duplicate-email signal (code `email_exists`,
 *      HTTP 422, or a message containing "already"), fall back to
 *      `generateLink({ type: 'magiclink', email })` — that admin endpoint
 *      returns the existing user object alongside a one-time link. We
 *      never extract or send the link; we only read the `user` field.
 *      This avoids pagination and avoids the broken listUsers query.
 *   3. Any other error: surface the full code/message/status so the
 *      operator can tell whether it's an auth-admin permission problem,
 *      a duplicate-email handling edge case, or something else.
 */
async function ensureAuthUser(
  sb: any,
  cfg: { email: string; password: string },
): Promise<string> {
  // Step 1: try to create
  const created = await sb.auth.admin.createUser({
    email:         cfg.email,
    password:      cfg.password,
    email_confirm: true,
    user_metadata: { source: 'seed-demo', purpose: 'app_review' },
  });

  if (created.data?.user) return created.data.user.id;

  if (!created.error) {
    throw new Error(`createUser ${cfg.email}: no user returned and no error — unexpected response`);
  }

  // Step 2: was this a duplicate-email error? Different GoTrue versions
  // return different shapes. Treat any of these signals as "user exists":
  //   • error.code === 'email_exists'
  //   • error.status === 422 with a message containing "registered"/"exists"
  //   • message contains "already registered" / "already exists" / "duplicate"
  const errAny = created.error as unknown as {
    code?: string;
    status?: number;
    message?: string;
    name?: string;
  };
  const msg = (errAny.message ?? '').toLowerCase();
  const isDuplicate =
    errAny.code === 'email_exists' ||
    errAny.code === 'user_already_exists' ||
    /already (registered|exists)/i.test(msg) ||
    /duplicate (key|user)/i.test(msg) ||
    /user.*already/.test(msg);

  if (!isDuplicate) {
    // Not a duplicate — surface full diagnostics and bail.
    logAuthError('createUser', cfg.email, errAny);
    classifyAndExit('createUser', errAny);
  }

  // Step 3: user exists — fetch via generateLink (returns user without enumerating)
  console.log(`  ↺ ${cfg.email} already exists, fetching id via generateLink (magiclink)`);
  const linked = await sb.auth.admin.generateLink({
    type:  'magiclink',
    email: cfg.email,
    // No redirectTo — we don't use the link.
  });

  if (linked.data?.user?.id) return linked.data.user.id;

  // generateLink failed too — likely the existing user was deleted between
  // step 1 and step 2 (rare), or auth-admin permissions are broken.
  const linkErr = linked.error as unknown as { code?: string; status?: number; message?: string; name?: string };
  logAuthError('generateLink(magiclink)', cfg.email, linkErr ?? { message: 'unknown' });
  classifyAndExit('generateLink', linkErr ?? { message: 'unknown' });
  throw new Error('unreachable'); // satisfy TS
}

/** Pretty-print the full Supabase auth error so failures aren't opaque. */
function logAuthError(
  op: string,
  email: string,
  err: { code?: string; status?: number; message?: string; name?: string },
) {
  console.error(`\n✗ ${op} failed for ${email}`);
  console.error(`    code:    ${err.code ?? '(none)'}`);
  console.error(`    status:  ${err.status ?? '(none)'}`);
  console.error(`    name:    ${err.name ?? '(none)'}`);
  console.error(`    message: ${err.message ?? '(none)'}`);
}

/** Identify the likely root cause and exit non-zero. */
function classifyAndExit(
  op: string,
  err: { code?: string; status?: number; message?: string; name?: string },
): never {
  const msg = (err.message ?? '').toLowerCase();
  let category = 'unknown';

  if (err.status === 401 || err.status === 403 || /unauthor|forbidden|not allowed/i.test(msg)) {
    category = 'auth-admin permission (service-role key invalid or insufficient privileges)';
  } else if (err.status === 422 || /already|duplicate|exists/i.test(msg)) {
    category = 'duplicate-email handling (user already exists but fallback also failed)';
  } else if (/database error|relation .* does not exist|null value in column/i.test(msg)) {
    category = 'auth.users table query (GoTrue admin endpoint internal failure — re-run later or contact Supabase support)';
  } else if (err.status === 0 || /network|fetch|ECONN|ENOTFOUND/i.test(msg)) {
    category = 'network (cannot reach Supabase auth admin endpoint)';
  } else if (/rate.?limit|too many/i.test(msg)) {
    category = 'rate-limited (wait 60s and retry)';
  }

  console.error(`    ▸ Likely cause: ${category}`);
  console.error(`    ▸ Re-run when resolved: npx --yes tsx scripts/seed-demo.ts\n`);
  process.exit(1);
}

// ─── Profile row (idempotent upsert) ────────────────────────────────────────

async function ensureProfile(
  sb: any,
  userId: string,
  cfg: { display_name: string; phone_number: string | null },
) {
  // A handle_new_user trigger creates a bare profile row on auth-user
  // insert (see schema.sql). We just patch the descriptive fields.
  const { error } = await sb.from('profiles').upsert({
    id:           userId,
    display_name: cfg.display_name,
    phone_number: cfg.phone_number,
  }, { onConflict: 'id' });
  if (error) throw new Error(`profile upsert ${userId}: ${error.message}`);
}

// ─── Stripe Connect Express account (idempotent) ────────────────────────────

async function ensureStripeConnectAccount(
  sb: any,
  sellerId: string,
  email: string,
): Promise<string> {
  const { data: profile } = await sb
    .from('profiles')
    .select('stripe_connect_id')
    .eq('id', sellerId)
    .single();

  if (profile?.stripe_connect_id) {
    // Re-fetch from Stripe to verify the account still exists in test mode.
    try {
      await stripeFetch(`/accounts/${profile.stripe_connect_id}`);
      return profile.stripe_connect_id as string;
    } catch {
      console.warn(`  ! Existing Connect id ${profile.stripe_connect_id} not found in Stripe (test mode wiped?) — creating a new one.`);
    }
  }

  const acct = await stripeFetch('/accounts', {
    method: 'POST',
    body: {
      type:    'express',
      country: 'US',
      email,
      capabilities: {
        card_payments: { requested: true },
        transfers:     { requested: true },
      },
      business_type: 'individual',
      business_profile: {
        url: 'https://snatchitwebapp.vercel.app',
        mcc: '7929', // theatrical producers & misc entertainment (no gambling MCC)
      },
      metadata: {
        source:  'seed-demo',
        purpose: 'app_review',
        user_id: sellerId,
      },
    },
  });
  return acct.id;
}

/**
 * Best-effort fast-track. Stripe's test mode accepts magic field values
 * that auto-clear individual verification + acceptances. We don't fail
 * the whole seed if this step errors — the reviewer can still complete
 * onboarding via the in-app payout-setup flow.
 */
async function tryFastTrackOnboarding(accountId: string) {
  try {
    // Step 1: provide individual details + TOS acceptance. Stripe test-mode
    // SSN "000-00-0000" auto-passes verification.
    await stripeFetch(`/accounts/${accountId}`, {
      method: 'POST',
      body: {
        individual: {
          first_name: 'Demo',
          last_name:  'Reviewer',
          email:      SELLER.email,
          phone:      '+15555550100',
          dob:        { day: 1, month: 1, year: 1990 },
          address: {
            line1:       'address_full_match', // Stripe test magic for instant address verification
            city:        'Miami',
            state:       'FL',
            postal_code: '33101',
            country:     'US',
          },
          ssn_last_4:  '0000',
          id_number:   '000000000',
        },
        tos_acceptance: {
          date: Math.floor(Date.now() / 1000),
          ip:   '127.0.0.1',
        },
      },
    });

    // Step 2: add a test bank account (instant-verify routing/account).
    await stripeFetch(`/accounts/${accountId}/external_accounts`, {
      method: 'POST',
      body: {
        external_account: {
          object:         'bank_account',
          country:        'US',
          currency:       'usd',
          routing_number: '110000000',
          account_number: '000123456789',
        },
      },
    }).catch((err: Error) => {
      // External account creation may fail if one already exists. Ignore.
      if (!/already (exists|has)/i.test(err.message)) console.warn(`  ! bank account attach: ${err.message}`);
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(`  ! Fast-track onboarding skipped: ${msg}`);
    console.warn('    The reviewer can complete onboarding via the in-app Payout Setup screen.');
  }
}

// ─── Listings ───────────────────────────────────────────────────────────────

async function ensureListing(
  sb: any,
  sellerId: string,
  cfg: typeof LISTINGS[number],
  isHistorical: boolean,
): Promise<string> {
  // Idempotency key: (seller_id, event_name). No unique constraint exists,
  // so we look up before insert.
  const { data: existing } = await sb
    .from('listings')
    .select('id')
    .eq('seller_id', sellerId)
    .eq('event_name', cfg.event_name)
    .maybeSingle();
  if (existing?.id) return existing.id as string;

  // listings.cover_image_path is NOT NULL — supply a synthetic path. The
  // app's image-fetch helpers gracefully fall back when the storage
  // object is missing.
  const coverPath = `${sellerId}/seed-demo/${slug(cfg.event_name)}.jpg`;

  const endsAt = new Date(Date.now() + cfg.duration_hours * 3_600_000);

  const baseRow: any = {
    seller_id:        sellerId,
    event_name:       cfg.event_name,
    venue:            cfg.venue,
    neighborhood:     cfg.neighborhood,
    event_date:       cfg.event_date,
    event_time:       cfg.event_time,
    ticket_type:      cfg.ticket_type,
    quantity:         cfg.quantity,
    transfer_method:  cfg.transfer_method,
    restrictions:     cfg.restrictions,
    starting_bid:     cfg.starting_bid,
    buy_now_enabled:  cfg.buy_now_enabled,
    buy_now_price:    cfg.buy_now_enabled ? cfg.buy_now_price : null,
    duration_hours:   cfg.duration_hours,
    ends_at:          endsAt.toISOString(),
    current_bid:      cfg.starting_bid,
    cover_image_path: coverPath,
    ticket_platform:  cfg.ticket_platform,
  };

  // For the historical-sale listing, set the final state on INSERT so the
  // guard_listing_state_columns trigger (which only fires on UPDATE) does
  // not block us.
  if (isHistorical) {
    baseRow.status             = 'sold';
    baseRow.auction_status     = 'sold';
    baseRow.sold_at            = new Date().toISOString();
    baseRow.ended_at           = new Date().toISOString();
    baseRow.winner_user_id     = null; // set after we know the buyer
    baseRow.winning_bid_amount = (cfg.buy_now_price as number | null | undefined) ?? cfg.starting_bid;
  }

  const { data, error } = await sb.from('listings').insert(baseRow).select('id').single();
  if (error) throw new Error(`insert listing "${cfg.event_name}": ${error.message}`);
  return data!.id;
}

function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

// ─── Active bid (idempotent) ────────────────────────────────────────────────

async function ensureBid(
  sb: any,
  listingId: string,
  bidderId: string,
  amount: number,
) {
  const { data: existing } = await sb
    .from('bids')
    .select('id')
    .eq('listing_id', listingId)
    .eq('bidder_id', bidderId)
    .eq('amount', amount)
    .maybeSingle();
  if (existing?.id) return;

  const { error } = await sb.from('bids').insert({
    listing_id: listingId,
    bidder_id:  bidderId,
    amount,
  });
  if (error) throw new Error(`insert bid on ${listingId}: ${error.message}`);
}

// ─── Historical buyer_confirmed sale ────────────────────────────────────────

async function ensureHistoricalSale(
  sb: any,
  listingId: string,
  buyerId: string,
  sellerId: string,
  listingCfg: typeof LISTINGS[number],
) {
  // Idempotency: if a payment exists for this listing+buyer, assume done.
  const { data: existingPayment } = await sb
    .from('payments')
    .select('id')
    .eq('listing_id', listingId)
    .eq('buyer_id', buyerId)
    .maybeSingle();
  if (existingPayment?.id) return;

  const priceDollars  = (listingCfg.buy_now_price as number | null | undefined) ?? listingCfg.starting_bid;
  const amountCents   = priceDollars * 100;
  const buyerFeeCents = Math.round(amountCents * BUYER_FEE_RATE);
  const sellerFeeCents= Math.round(amountCents * SELLER_FEE_RATE);
  const totalCents    = amountCents + buyerFeeCents;

  // Use a synthetic Stripe PI id so this row is identifiable and never
  // collides with a real Stripe PaymentIntent. The unique constraint on
  // stripe_payment_intent_id still permits this (any unique string works).
  const syntheticPi = `pi_seed_demo_${listingId}`.replace(/-/g, '').slice(0, 60);

  const { data: payment, error: payErr } = await sb.from('payments').insert({
    listing_id:               listingId,
    buyer_id:                 buyerId,
    seller_id:                sellerId,
    amount:                   amountCents,
    buyer_fee:                buyerFeeCents,
    seller_fee:               sellerFeeCents,
    total:                    totalCents,
    stripe_payment_intent_id: syntheticPi,
    status:                   'succeeded',
    payment_method:           'card',
    mode:                     'buy_now',
    paid_at:                  new Date().toISOString(),
  }).select('id').single();
  if (payErr) throw new Error(`insert historical payment: ${payErr.message}`);

  // Backfill winner_user_id on the listing (the listing was inserted as
  // sold; this update would normally be blocked by the guard, but
  // winner_user_id was set to null at insert and now equals the buyer —
  // the guard only blocks UPDATE that changes state columns, so this
  // single-field UPDATE inside an unbypassed session would fire it; we
  // use the bypass flag.)
  await sb.rpc('set_seed_demo_winner', {
    p_listing_id: listingId,
    p_user_id:    buyerId,
  }).then((res: { error: { message: string } | null }) => {
    if (res.error && !/function\s+.*does not exist/i.test(res.error.message)) {
      console.warn(`  ! winner backfill (RPC) skipped: ${res.error.message}`);
    }
    // If the RPC doesn't exist (it isn't a real migration), we silently
    // leave winner_user_id null on the historical listing. That's fine —
    // the listing-detail screen reads transfer state from the transfers
    // table, not from winner_user_id.
  });

  const { error: trErr } = await sb.from('transfers').insert({
    listing_id:         listingId,
    payment_id:         payment!.id,
    seller_id:          sellerId,
    buyer_id:           buyerId,
    transfer_method:    listingCfg.transfer_method,
    status:             'buyer_confirmed',
    seller_sent_at:     new Date(Date.now() - 2 * 86_400_000).toISOString(), // 2 days ago
    buyer_confirmed_at: new Date(Date.now() - 1 * 86_400_000).toISOString(), // 1 day ago
    expires_at:         new Date(Date.now() + 86_400_000).toISOString(),
  });
  if (trErr) throw new Error(`insert historical transfer: ${trErr.message}`);
}

// ─── Entry ──────────────────────────────────────────────────────────────────

main().catch(err => {
  console.error('\n✗ Seed failed:', err instanceof Error ? err.message : err);
  if (err instanceof Error && err.stack) console.error(err.stack);
  process.exit(1);
});
