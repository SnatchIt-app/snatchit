-- ============================================================================
-- 193_ops_console_refund_exactness.sql — migration 126.
--   The ops console states refunded MONEY exactly when, and only when, every
--   refund in the window is recorded in the append-only ledger
--   (public.payment_refunds, written only by public.record_payment_refund).
--   Acceptance cases A1–A8 (docs/release/CONVERGENCE_135_REPORT.md:541-548)
--   plus two found while taking 126 over (Claude B, 2026-09-15):
--   A9  a lost chargeback on an already fully refunded payment writes a second
--       ledger row capped at total, and an amount-less refund after a partial
--       one ledgers the full total again (writer: NULL = total); the ledger SUM
--       exceeds the payment, the system of record (payments.amount_refunded_cents)
--       does not. Reported money must equal the record, never the raw row sum.
--       (Found independently by Claude D as R126-1 and by B.)
--   A10 a refund with no ledger row (legacy rows — 7 in production
--       2026-03-29..08-04, never backfilled by 20260906120000 — or
--       settle_verified_payment's status-only branch when Stripe gives no refund
--       id) has an unknown amount: its window is certainty 'mixed' — exact cents
--       from the ledger, plus legacy_upper_bound_cents — never 'known'. A refund
--       counts as unrecorded when the payment's refunded_at precedes every ledger
--       row it has, so a legacy refund later followed by a lost chargeback stays
--       unrecorded. (R126-2, found independently by Claude D and B; contract per
--       A's CORRECTION 2026-09-14 in ISOLATED_WORK_126_L3_L4_F10.md §1.)
--   Surfaces: money_overview.value_cents is the page headline and is rendered
--   without a certainty check by the release admin client, so it is null unless
--   certainty is 'known'; the exact ledger part rides in known_cents.
--
-- VERSION-AGNOSTIC PROBE. Every call into a function 126 adds or changes goes
-- through tap._try193 / _build193 / _refresh193 (writer and reader in separate
-- statements, so a probe never reads the snapshot taken before its own write), which returns {"__error": …} instead of raising, so on
-- a database WITHOUT 126 the suite runs to completion and reports each case as
-- a failure rather than aborting at the first missing object.
--
-- FIXTURES are reachable states only: payments inserted as settled buy_now
-- rows on their own listings; every refund written THROUGH
-- public.record_payment_refund; the one unrecorded refund (A10) is the state
-- production already holds. now() is frozen per transaction, so each ledger
-- row's created_at (and the completing refunded_at) is shifted to an explicit
-- timestamp immediately after it is recorded — the state the same call would
-- have produced at that instant — using only owner-level trigger disabling and
-- the repo's app.bypass_payment_guard GUC, both available to CI's non-superuser
-- postgres role (never session_replication_role). Windows are fixed UTC days D-10..D+1 with
-- D = today - 3, disjoint from every seed_core timestamp.
-- ============================================================================
BEGIN;
SELECT plan(65);
SELECT tap.seed_core();

CREATE TABLE tap.memo_193 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._store193(p_k text, p_v jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER
  AS $m$ INSERT INTO tap.memo_193 VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._get193(p_k text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
  AS $m$ SELECT v FROM tap.memo_193 WHERE k = p_k $m$;
-- invoker: runs as the current (possibly logged-in) role; never raises.
CREATE FUNCTION tap._try193(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare r jsonb;
begin
  execute p_sql into r;
  return r;
exception when others then
  return jsonb_build_object('__error', sqlstate || ' ' || sqlerrm);
end $f$;
-- writer then reader in SEPARATE statements: a single statement reads the
-- snapshot taken before its own write, so it would return the previous row.
CREATE FUNCTION tap._build193(p_d date) RETURNS jsonb LANGUAGE plpgsql AS $f$
begin
  begin
    perform ops.build_daily_summary(p_d);
  exception when others then
    return jsonb_build_object('__error', sqlstate || ' ' || sqlerrm);
  end;
  return (select s.body #> '{money,live_24h}' from ops.daily_summary s where s.summary_date = p_d);
end $f$;
CREATE FUNCTION tap._refresh193() RETURNS jsonb LANGUAGE plpgsql AS $f$
begin
  begin
    perform ops.refresh_metrics();
  exception when others then
    return jsonb_build_object('__error', sqlstate || ' ' || sqlerrm);
  end;
  return (select m.value from ops.metric_snapshot m where m.key = 'money.refunded');
end $f$;
CREATE FUNCTION tap._aal2_193() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- D and explicit UTC instants.
CREATE FUNCTION tap._d193() RETURNS date LANGUAGE sql STABLE AS $m$ SELECT (now() AT TIME ZONE 'UTC')::date - 3 $m$;
CREATE FUNCTION tap._at193(p_day_offset int, p_time text) RETURNS timestamptz LANGUAGE sql STABLE
  AS $m$ SELECT ((tap._d193() + p_day_offset)::timestamp + p_time::interval) AT TIME ZONE 'UTC' $m$;
CREATE FUNCTION tap._pay193(n int) RETURNS uuid LANGUAGE sql IMMUTABLE
  AS $m$ SELECT ('19300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $m$;

-- record a refund through the one writer, then place it at p_at.
CREATE FUNCTION tap._refund193(p_n int, p_refund text, p_dispute text, p_amount int, p_source text, p_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql AS $f$
declare r jsonb; v_pi text;
begin
  select stripe_payment_intent_id into v_pi from public.payments where id = tap._pay193(p_n);
  r := public.record_payment_refund(v_pi, p_refund, p_dispute, p_amount, p_source);
  if (r ->> 'recorded')::boolean then
    -- Time placement only, never a state the writer cannot produce. Owner-level
    -- and transaction-local, so it runs as Supabase's non-superuser postgres
    -- role in CI (session_replication_role is superuser-only and must not be
    -- used): the append-only ledger guard has no bypass GUC, so it is disabled
    -- for this one UPDATE (the pattern of suites 142/143/177/178); the payments
    -- guard honours the repo's app.bypass_payment_guard (reset after the statement).
    execute 'alter table public.payment_refunds disable trigger trg_payment_refunds_append_only';
    update public.payment_refunds set created_at = p_at
     where payment_id = tap._pay193(p_n) and created_at = now()
       and stripe_refund_id is not distinct from nullif(p_refund, '')
       and stripe_dispute_id is not distinct from nullif(p_dispute, '');
    execute 'alter table public.payment_refunds enable trigger trg_payment_refunds_append_only';
    perform set_config('app.bypass_payment_guard', 'on', true);
    update public.payments set refunded_at = p_at where id = tap._pay193(p_n) and refunded_at = now();
  end if;
  return r;
end $f$;

-- ── FIXTURE — eleven $100 buy_now payments, each on its own listing ─────────
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
SELECT tap._pay193(n), tap.seller(), 'Fixture 193-' || n, 'Club 193', 'wynwood', current_date + 30, '21:00', 'GA', 2,
       'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/193.jpg', 'active'
  FROM generate_series(1, 12) n;
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, paid_at, stripe_livemode)
SELECT tap._pay193(n), tap._pay193(n), tap.buyer(), tap.seller(), 9091, 909, 909, 10000,
       'pi_193_' || n, 'succeeded', 'buy_now', tap._at193(-5, '08:00'), tap._at193(-5, '09:00'), false
  FROM generate_series(1, 12) n WHERE n NOT IN (9, 12);

SELECT tap._refund193(1, 're_193_1',  NULL, 1000,  'dashboard', tap._at193(0, '10:00'));      -- A1 partial $10
SELECT tap._refund193(2, 're_193_2',  NULL, NULL,  'dashboard', tap._at193(0, '11:00'));      -- A2 full (amount-less)
SELECT tap._refund193(3, 're_193_3a', NULL, 1000,  'dashboard', tap._at193(0, '12:00'));      -- A3 $10 …
SELECT tap._refund193(3, 're_193_3b', NULL, 1500,  'dashboard', tap._at193(0, '13:00'));      --    … then $15
SELECT tap._refund193(4, 're_193_4',  NULL, 3000,  'dashboard', tap._at193(0, '14:00'));      -- A8 refund $30 …
SELECT tap._refund193(4, NULL, 'du_193_4', 7000,  'dispute_lost', tap._at193(0, '15:00'));    --    … + chargeback $70
SELECT tap._store193('a8_replay', tap._refund193(4, NULL, 'du_193_4', 7000, 'dispute_lost', tap._at193(0, '15:30'))); -- replay
SELECT tap._refund193(5, 're_193_5',  NULL, NULL,  'dashboard', tap._at193(0, '16:00'));      -- A9 full refund …
SELECT tap._refund193(5, NULL, 'du_193_5', 10000, 'dispute_lost', tap._at193(0, '17:00'));    --    … then lost chargeback
SELECT tap._refund193(6, 're_193_6',  NULL, 2000,  'dashboard', tap._at193(-1, '12:00'));     -- A4 the day before
SELECT tap._refund193(11, 're_193_11a', NULL, 6000, 'dashboard', tap._at193(-1, '13:00'));    -- A9' $60 partial …
SELECT tap._refund193(11, 're_193_11b', NULL, NULL, 'dashboard', tap._at193(-1, '14:00'));    --     … then an amount-less full refund (writer: NULL = total)
SELECT tap._refund193(7, 're_193_7',  NULL, 700,   'dashboard', tap._at193(1, '00:00'));      -- boundary: exactly D+1 00:00
SELECT tap._refund193(8, 're_193_8',  NULL, 500,   'dashboard', tap._at193(0, '00:00'));      -- boundary: exactly D 00:00 …
SELECT tap._refund193(8, 're_193_8b', NULL, 300,   'dashboard', tap._at193(1, '00:00'));      --    … and the SAME payment again at exactly D+1 00:00
SELECT tap._refund193(10, 're_193_10', NULL, 1200, 'dashboard', tap._at193(-2, '10:00'));     -- recorded, on the A10 day

-- ── A. definition and grants ─────────────────────────────────────────────────
SELECT ok(to_regprocedure('ops.refund_facts(timestamptz,timestamptz)') IS NOT NULL, 'A.1: ops.refund_facts(timestamptz,timestamptz) exists');
SELECT ok(coalesce((SELECT p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']
                      FROM pg_proc p WHERE p.oid = to_regprocedure('ops.refund_facts(timestamptz,timestamptz)')), false),
  'A.2: refund_facts is SECURITY DEFINER, STABLE, search_path pinned to empty');
SELECT ok(coalesce((SELECT NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                       AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                       AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
                      FROM pg_proc p WHERE p.oid = to_regprocedure('ops.refund_facts(timestamptz,timestamptz)')), false),
  'A.3: refund_facts is internal — no EXECUTE for anon, authenticated or service_role');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.build_daily_summary(date)', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'ops.build_daily_summary(date)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'ops.refresh_metrics()', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'ops.refresh_metrics()', 'EXECUTE'),
  'A.4: build_daily_summary and refresh_metrics keep no client or service grant (unchanged)');
SELECT ok(has_function_privilege('authenticated', 'ops.money_overview(date,date)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'ops.money_overview(date,date)', 'EXECUTE'),
  'A.5: money_overview keeps authenticated EXECUTE (assert_reader in body) and no anon (unchanged)');

-- ── F. fixture sanity (so no case below passes vacuously) ────────────────────
SELECT is((SELECT count(*)::int FROM public.payment_refunds WHERE payment_id NOT IN (SELECT tap._pay193(n) FROM generate_series(1,12) n)), 0,
  'F.1: the only ledger rows are this suite''s fixtures');
SELECT is((SELECT count(*)::int FROM public.payments WHERE (status = 'refunded' OR refunded_at IS NOT NULL)
             AND id NOT IN (SELECT tap._pay193(n) FROM generate_series(1,12) n)), 0,
  'F.2: no refunded payment exists outside the fixtures');
SELECT is((SELECT string_agg(to_char(created_at AT TIME ZONE 'UTC', 'DD HH24:MI') || '=' || amount_cents, ',' ORDER BY created_at, amount_cents)
             FROM public.payment_refunds WHERE payment_id = tap._pay193(5)),
          to_char(tap._at193(0,'16:00') AT TIME ZONE 'UTC', 'DD HH24:MI') || '=10000,' || to_char(tap._at193(0,'17:00') AT TIME ZONE 'UTC', 'DD HH24:MI') || '=10000',
  'F.3: A9 is real — two ledger rows of 10000 on one $100 payment, at the placed instants');
SELECT is((SELECT amount_refunded_cents || '/' || status FROM public.payments WHERE id = tap._pay193(5)), '10000/refunded',
  'F.4: …while the system of record caps the payment at 10000 refunded');
SELECT is((SELECT count(*)::int FROM public.payment_refunds WHERE payment_id = tap._pay193(4)) || '/' || (tap._get193('a8_replay') ->> 'recorded'), '2/false',
  'F.5: A8 — one refund row and one chargeback row; the replayed chargeback is not recorded again');
SELECT is((SELECT sum(r.amount_cents) || '/' || p.amount_refunded_cents FROM public.payment_refunds r JOIN public.payments p ON p.id = r.payment_id WHERE p.id = tap._pay193(11) GROUP BY p.amount_refunded_cents), '16000/10000',
  'F.6: A9'' is real — $60 then an amount-less full refund ledgers 16000 against a record of 10000');

SELECT is((SELECT tgenabled::text FROM pg_trigger WHERE tgname = 'trg_payment_refunds_append_only' AND tgrelid = 'public.payment_refunds'::regclass), 'O',
  'F.7: the append-only ledger trigger disabled for the fixture time shift is enabled again (tgenabled = O)');
SELECT is(coalesce(current_setting('app.bypass_payment_guard', true), 'off'), 'off',
  'F.8: the payments guard bypass used by the fixture time shift is off again');

-- ── P9: the unrecorded refund (A10), inserted after the ledger fixtures ──────
-- Recorded AFTER a first refresh_metrics run below, so the snapshot is probed
-- both without and with an unrecorded refund.

-- ── R. ops.refund_facts over explicit windows ────────────────────────────────
SELECT tap._store193('rf_A1', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'10:00'), tap._at193(0,'11:00'))));
SELECT tap._store193('rf_A2', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'11:00'), tap._at193(0,'12:00'))));
SELECT tap._store193('rf_A3', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'12:00'), tap._at193(0,'14:00'))));
SELECT tap._store193('rf_A8', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'14:00'), tap._at193(0,'16:00'))));
SELECT tap._store193('rf_A9', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'16:00'), tap._at193(0,'18:00'))));
SELECT tap._store193('rf_A9b', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'17:00'), tap._at193(0,'18:00'))));
SELECT tap._store193('rf_D', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'00:00'), tap._at193(1,'00:00'))));
SELECT tap._store193('rf_Dm1', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(-1,'00:00'), tap._at193(0,'00:00'))));
SELECT tap._store193('rf_A9p', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(-1,'13:30'), tap._at193(-1,'15:00'))));
SELECT tap._store193('rf_Dp1', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(1,'00:00'), tap._at193(2,'00:00'))));
SELECT tap._store193('rf_edge', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(1,'00:00'), tap._at193(1,'00:00') + interval '1 microsecond')));
SELECT tap._store193('rf_A5', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(-10,'00:00'), tap._at193(-9,'00:00'))));

SELECT is(concat_ws('/', tap._get193('rf_A1')->>'cents', tap._get193('rf_A1')->>'count', tap._get193('rf_A1')->>'partial_count', tap._get193('rf_A1')->>'full_count', tap._get193('rf_A1')->>'certainty'),
  '1000/1/1/0/known', 'R.A1: $10 partial on $100 → 1000 cents, 1 payment, partial, known');
SELECT is(concat_ws('/', tap._get193('rf_A2')->>'cents', tap._get193('rf_A2')->>'count', tap._get193('rf_A2')->>'full_count', tap._get193('rf_A2')->>'partial_count'),
  '10000/1/1/0', 'R.A2: full refund → 10000 cents, full_count 1');
SELECT is(concat_ws('/', tap._get193('rf_A3')->>'cents', tap._get193('rf_A3')->>'count', tap._get193('rf_A3')->>'partial_count'),
  '2500/1/1', 'R.A3: $10 then $15 on one payment → 2500 cents, the payment counted ONCE');
SELECT is(concat_ws('/', tap._get193('rf_A8')->>'cents', tap._get193('rf_A8')->>'count', tap._get193('rf_A8')->>'full_count'),
  '10000/1/1', 'R.A8: $30 refund + $70 lost chargeback → 10000 once, not doubled; payment full');
SELECT is(concat_ws('/', tap._get193('rf_A9')->>'cents', tap._get193('rf_A9')->>'count', tap._get193('rf_A9')->>'full_count'),
  '10000/1/1', 'R.A9: full refund then lost chargeback → 10000 (the record), not the 20000 row sum');
SELECT is(concat_ws('/', tap._get193('rf_A9b')->>'cents', tap._get193('rf_A9b')->>'count', tap._get193('rf_A9b')->>'certainty'),
  '0/0/known', 'R.A9b: a window holding only the capped chargeback moves no money and counts no payment');
SELECT is(concat_ws('/', tap._get193('rf_D')->>'cents', tap._get193('rf_D')->>'count', tap._get193('rf_D')->>'full_count', tap._get193('rf_D')->>'partial_count', tap._get193('rf_D')->>'certainty'),
  '34000/6/3/3/known', 'R.D: day D → 34000 cents over 6 payments (3 full, 3 partial), known');
SELECT is(concat_ws('/', tap._get193('rf_Dm1')->>'cents', tap._get193('rf_Dm1')->>'count', tap._get193('rf_Dm1')->>'full_count', tap._get193('rf_Dm1')->>'partial_count'),
  '12000/2/1/1', 'R.A4: D-1 = the $20 refund (excluded from D) + the $100 of A9'' — 2 payments, 1 full, 1 partial');
SELECT is(tap._get193('rf_A9p')->>'cents', '4000', 'R.A9'': the amount-less completion contributes only the remaining 4000, never a second 10000');
SELECT is(tap._get193('rf_Dp1')->>'cents', '1000', 'R.edge1: refunds at exactly D+1 00:00 (700, and 300 on a payment also refunded inside D) belong to D+1, not D');
SELECT is(tap._get193('rf_edge')->>'cents', '1000', 'R.edge2: p_from is inclusive at the microsecond');
SELECT tap._store193('rf_P8D', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'00:00'), tap._at193(1,'00:00'))));
SELECT is(tap._get193('rf_P8D')->>'cents', '34000',
  'R.edge3: day D stays 34000 — P8 contributes only its 500; its 300 at exactly the window end is outside although the payment is inside');
SELECT is(concat_ws('/', tap._get193('rf_A5')->>'cents', tap._get193('rf_A5')->>'count', tap._get193('rf_A5')->>'certainty'),
  '0/0/known', 'R.A5: no refunds → a KNOWN zero, not an unknown');
SELECT ok(coalesce(tap._try193('SELECT ops.refund_facts(NULL, now())') ->> '__error', '') LIKE '%invalid_input%'
      AND coalesce(tap._try193('SELECT ops.refund_facts(now(), now() - interval ''1 day'')') ->> '__error', '') LIKE '%invalid_input%',
  'R.guard: a NULL or inverted window is refused, never read as a known zero');

-- ── S. ops.build_daily_summary live_24h ──────────────────────────────────────
SELECT tap._store193('bd_D', tap._build193(tap._d193()));
SELECT tap._store193('bd_Dp1', tap._build193(tap._d193() + 1));
SELECT tap._store193('bd_A5', tap._build193(tap._d193() - 10));

SELECT is(jsonb_typeof(tap._get193('bd_D') -> 'refunded_cents'), 'number', 'S.1: live_24h.refunded_cents is a number on a fully recorded day');
SELECT is(concat_ws('/', tap._get193('bd_D')->>'refunded_cents', tap._get193('bd_D')->>'refunded_count', tap._get193('bd_D')->>'refunded_certainty'),
  '34000/6/known', 'S.2: day D summary = refund_facts(D): 34000 over 6 payments, known');
SELECT is(concat_ws('/', tap._get193('bd_D')->>'refunded_full_count', tap._get193('bd_D')->>'refunded_partial_count'),
  '3/3', 'S.3: full/partial split carried into the summary');
SELECT is(tap._get193('bd_D')->>'refunded_upper_bound_cents', '34000', 'S.4: upper bound stays populated and equals the exact figure when known (continuity)');
SELECT is(tap._get193('bd_Dp1')->>'refunded_cents', '1000', 'S.5: the D+1 summary holds the boundary refund; adjacent days never count it twice');
SELECT is(concat_ws('/', tap._get193('bd_A5')->>'refunded_cents', tap._get193('bd_A5')->>'refunded_certainty'),
  '0/known', 'S.A5: empty day → refunded_cents 0 known ($0.00), never null');

-- ── M. ops.money_overview (founder, aal2) ────────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_193();
SELECT tap._store193('mo_D', tap._try193(format('SELECT ops.money_overview(%L::date, %L::date) #> ''{metrics,refunded_volume}''', tap._d193(), tap._d193())));
SELECT tap._store193('mo_3d', tap._try193(format('SELECT ops.money_overview(%L::date, %L::date) #> ''{metrics,refunded_volume}''', tap._d193() - 1, tap._d193() + 1)));
SELECT tap.logout();
SELECT is(concat_ws('/', tap._get193('mo_D')->>'value_cents', tap._get193('mo_D')->>'count', tap._get193('mo_D')->>'certainty'),
  '34000/6/known', 'M.1: refunded_volume for day D = 34000 over 6 payments, certainty known');
SELECT is(concat_ws('/', tap._get193('mo_D')->>'full_count', tap._get193('mo_D')->>'partial_count'), '3/3', 'M.2: full/partial split on the money page');
SELECT is(tap._get193('mo_3d')->>'value_cents', '47000', 'M.3: D-1..D+1 = 12000 + 34000 + 1000 — the range equals the sum of its days');
SELECT is(tap._get193('mo_D')->>'source', 'public.payment_refunds', 'M.4: source names the ledger');

-- ── K. ops.refresh_metrics money.refunded — fully recorded ───────────────────
SELECT tap._store193('rm1', tap._refresh193());
SELECT is(concat_ws('/', tap._get193('rm1')->>'certainty', tap._get193('rm1')->>'value_cents'), 'known/48200',
  'K.1: snapshot all-time = 48200, exact, while every refund is recorded');
SELECT is(concat_ws('/', tap._get193('rm1') #>> '{all_time,cents}', tap._get193('rm1') #>> '{all_time,count}', tap._get193('rm1') #>> '{window_30d,cents}'),
  '48200/10/48200', 'K.2: all_time and window_30d cents/count');
SELECT is((tap._get193('rm1') #>> '{all_time,cents}')::bigint,
          (SELECT sum(coalesce(amount_refunded_cents, 0)) FROM public.payments),
  'K.3: snapshot all-time equals Σ payments.amount_refunded_cents — the one definition agrees with the system of record');

-- ── U. A10 — a refund with no ledger row ─────────────────────────────────────
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, paid_at, refunded_at, stripe_livemode)
VALUES (tap._pay193(9), tap._pay193(9), tap.buyer(), tap.seller(), 9091, 909, 909, 10000,
        'pi_193_9', 'refunded', 'buy_now', tap._at193(-5,'08:00'), tap._at193(-5,'09:00'), tap._at193(-2,'09:00'), false),
       (tap._pay193(12), tap._pay193(12), tap.buyer(), tap.seller(), 9091, 909, 909, 10000,
        'pi_193_12', 'refunded', 'buy_now', tap._at193(-5,'08:00'), tap._at193(-5,'09:00'), tap._at193(-3,'09:00'), false);
SELECT tap._refund193(12, NULL, 'du_193_12', 3000, 'dispute_lost', tap._at193(-3, '12:00'));   -- legacy refund, then a recorded lost chargeback
SELECT tap._store193('rf_Dm3', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(-3,'00:00'), tap._at193(-2,'00:00'))));
SELECT tap._store193('rf_Dm2', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(-2,'00:00'), tap._at193(-1,'00:00'))));
SELECT tap._store193('rf_all', tap._try193('SELECT ops.refund_facts(''-infinity'', ''infinity'')'));
SELECT tap._store193('bd_Dm2', tap._build193(tap._d193() - 2));
SELECT tap._store193('bd_D_again', tap._build193(tap._d193()));
SELECT tap._store193('rm2', tap._refresh193());
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_193();
SELECT tap._store193('mo_Dm2', tap._try193(format('SELECT ops.money_overview(%L::date, %L::date) #> ''{metrics,refunded_volume}''', tap._d193() - 2, tap._d193() - 2)));
SELECT tap.logout();

SELECT is(concat_ws('/', tap._get193('rf_Dm2')->>'cents', tap._get193('rf_Dm2')->>'certainty'), '1200/mixed',
  'U.1: a day holding an unrecorded refund → the exact ledger cents (1200) with certainty mixed, never known');
SELECT is(concat_ws('/', tap._get193('rf_Dm2')->>'legacy_upper_bound_cents', tap._get193('rf_Dm2')->>'upper_bound_cents', tap._get193('rf_Dm2')->>'count', tap._get193('rf_Dm2')->>'legacy_count'),
  '10000/11200/2/1', 'U.2: …legacy bound = the unrecorded payment''s total, kept OUT of cents; overall bound 11200; 2 payments, 1 unrecorded');
SELECT is(concat_ws('/', tap._get193('rf_Dm3')->>'cents', tap._get193('rf_Dm3')->>'certainty', tap._get193('rf_Dm3')->>'legacy_upper_bound_cents', tap._get193('rf_Dm3')->>'legacy_count'),
  '3000/mixed/7000/1', 'U.3: a legacy refund later followed by a recorded $30 chargeback stays unrecorded: mixed, bound = total − recorded');
SELECT is(concat_ws('/', tap._get193('rf_Dm3')->>'full_count', tap._get193('rf_Dm3')->>'partial_count'), '0/0',
  'U.4: an unrecorded payment is never classified full or partial');
SELECT is(concat_ws('/', tap._get193('rf_all')->>'cents', tap._get193('rf_all')->>'certainty', tap._get193('rf_all')->>'legacy_count', tap._get193('rf_all')->>'legacy_upper_bound_cents'),
  '51200/mixed/2/17000', 'U.5: all-time is mixed once any refund is unrecorded; recorded part 51200, legacy bound 17000');
SELECT is((tap._get193('rf_all')->>'cents')::bigint, (SELECT sum(coalesce(amount_refunded_cents, 0)) FROM public.payments),
  'U.6: the exact part still equals Σ payments.amount_refunded_cents with unrecorded refunds present');
SELECT is(concat_ws('/', tap._get193('bd_Dm2')->>'refunded_cents', tap._get193('bd_Dm2')->>'refunded_certainty', tap._get193('bd_Dm2')->>'refunded_upper_bound_cents', tap._get193('bd_Dm2')->>'refunded_legacy_upper_bound_cents', tap._get193('bd_Dm2')->>'refunded_count'),
  '1200/mixed/11200/10000/2', 'U.7: the D-2 summary carries mixed with both bounds; the release summary view renders it as a bound, not a figure');
SELECT is(concat_ws('/', tap._get193('bd_D_again')->>'refunded_cents', tap._get193('bd_D_again')->>'refunded_certainty'), '34000/known',
  'U.8: an unrecorded refund on another day does not taint day D');
SELECT is(concat_ws('/', coalesce(jsonb_typeof(tap._get193('mo_Dm2')->'value_cents'), 'missing'), tap._get193('mo_Dm2')->>'known_cents', tap._get193('mo_Dm2')->>'certainty', tap._get193('mo_Dm2')->>'upper_bound_cents'),
  'null/1200/mixed/11200', 'U.9: money page for D-2 — headline value null (never a partial figure), exact part in known_cents, bound 11200');
SELECT is(concat_ws('/', coalesce(jsonb_typeof(tap._get193('rm2')->'value_cents'), 'missing'), tap._get193('rm2')->>'certainty', tap._get193('rm2') #>> '{all_time,upper_bound_cents}', tap._get193('rm2') #>> '{all_time,legacy_count}'),
  'null/mixed/68200/2', 'U.10: the snapshot turns mixed — value null, all-time bound 51200 + 17000');
SELECT is(tap._get193('rm2') #>> '{all_time,cents}', '51200', 'U.11: …and still carries the exact recorded part');

-- ── L. A6 — stored summaries: never re-labelled in either direction ──────────
SELECT tap._store193('legacy_in', '{"money":{"live_24h":{"captured_cents":20000,"refunded_cents":10000}},"currency":"USD"}'::jsonb);
SELECT tap._store193('known_in',  '{"money":{"live_24h":{"captured_cents":20000,"refunded_cents":1234,"refunded_count":2,"refunded_certainty":"known"}}}'::jsonb);
SELECT is(ops.normalize_summary_body(tap._get193('known_in')), tap._get193('known_in'), 'L.1: a stored KNOWN body passes through byte-identical');
SELECT is(concat_ws('/', ops.normalize_summary_body(tap._get193('legacy_in')) #>> '{money,live_24h,refunded_certainty}',
                         ops.normalize_summary_body(tap._get193('legacy_in')) #>> '{money,live_24h,legacy_normalized}',
                         coalesce(jsonb_typeof(ops.normalize_summary_body(tap._get193('legacy_in')) #> '{money,live_24h,refunded_cents}'), 'missing')),
  'uncertain/true/null', 'L.2: a legacy numeric body is normalised to uncertain + legacy_normalized, never promoted to known');
SELECT is((SELECT ops.normalize_summary_body(body) = body FROM ops.daily_summary WHERE summary_date = tap._d193()), true,
  'L.3: the body 126 wrote for day D is left exactly as written by the normaliser');
INSERT INTO ops.daily_summary (summary_date, generated_at, body, delivery_state)
VALUES (date '2099-12-30', now(), tap._get193('known_in'), 'portal_only');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_193();
SELECT tap._store193('latest_known', ops.latest_summary() -> 'body');
SELECT tap.logout();
INSERT INTO ops.daily_summary (summary_date, generated_at, body, delivery_state)
VALUES (date '2099-12-31', now(), tap._get193('legacy_in'), 'portal_only');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_193();
SELECT tap._store193('latest_legacy', ops.latest_summary() -> 'body');
SELECT tap.logout();
SELECT is(tap._get193('latest_known'), tap._get193('known_in'), 'L.4: latest_summary returns a stored known body unchanged');
SELECT is(concat_ws('/', tap._get193('latest_legacy') #>> '{money,live_24h,refunded_certainty}', tap._get193('latest_legacy') #>> '{money,live_24h,legacy_normalized}'),
  'uncertain/true', 'L.5: latest_summary still normalises a legacy body on read');

-- ── G. A7 — the ledger is absent (a database replayed before the RC) ─────────
ALTER TABLE public.payment_refunds RENAME TO payment_refunds_hidden_193;
SELECT tap._store193('g_rf', tap._try193(format('SELECT ops.refund_facts(%L, %L)', tap._at193(0,'00:00'), tap._at193(1,'00:00'))));
SELECT tap._store193('g_bd', tap._build193(tap._d193()));
SELECT tap._store193('g_rm', tap._refresh193());
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_193();
SELECT tap._store193('g_mo', tap._try193(format('SELECT ops.money_overview(%L::date, %L::date) #> ''{metrics,refunded_volume}''', tap._d193(), tap._d193())));
SELECT tap.logout();
ALTER TABLE public.payment_refunds_hidden_193 RENAME TO payment_refunds;
SELECT is(concat_ws('/', coalesce(tap._get193('g_rf')->>'__error', 'no-error'), coalesce(jsonb_typeof(tap._get193('g_rf')->'cents'), 'missing'), tap._get193('g_rf')->>'certainty'),
  'no-error/null/uncertain', 'G.1: refund_facts without the ledger → no error, cents null, uncertain');
SELECT is(concat_ws('/', tap._get193('g_rf')->>'count', tap._get193('g_rf')->>'upper_bound_cents'), '3/30000',
  'G.2: …falls back to status: 3 payments refunded on D, bound Σ total 30000 (120''s shape)');
SELECT is(concat_ws('/', coalesce(tap._get193('g_bd')->>'__error', 'no-error'), coalesce(jsonb_typeof(tap._get193('g_bd')->'refunded_cents'), 'missing'), tap._get193('g_bd')->>'refunded_certainty'),
  'no-error/null/uncertain', 'G.3: build_daily_summary without the ledger → 120''s uncertain shape, no error');
SELECT is(concat_ws('/', coalesce(tap._get193('g_mo')->>'__error', 'no-error'), coalesce(jsonb_typeof(tap._get193('g_mo')->'value_cents'), 'missing'), tap._get193('g_mo')->>'certainty'),
  'no-error/null/uncertain', 'G.4: money_overview without the ledger → no figure, uncertain, no error');
SELECT is(concat_ws('/', coalesce(tap._get193('g_rm')->>'__error', 'no-error'), coalesce(jsonb_typeof(tap._get193('g_rm')->'value_cents'), 'missing'), tap._get193('g_rm')->>'certainty'),
  'no-error/null/uncertain', 'G.5: refresh_metrics without the ledger → uncertain snapshot, no error');

-- ── X. unchanged neighbours ──────────────────────────────────────────────────
SELECT is((tap._get193('bd_D')->>'captured_cents')::bigint, 0::bigint,
  'X.1: captured volume is untouched by 126 (fixtures were paid on D-5, nothing captured on D)');
SELECT ok(tap._get193('mo_D') ? 'definition' AND tap._get193('mo_D') ? 'basis' AND tap._get193('mo_D') ? 'currency',
  'X.2: refunded_volume keeps the tile keys the money page renders (definition, basis, currency)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'ops' AND p.proname IN ('build_daily_summary','money_overview','refresh_metrics','normalize_summary_body','latest_summary','refund_facts')), 6,
  'X.3: one definition each — no overloads introduced');
SELECT ok(coalesce(obj_description(to_regprocedure('ops.refund_facts(timestamptz,timestamptz)'), 'pg_proc'), '') LIKE '126:%',
  'X.4: refund_facts comment records 126');

SELECT * FROM finish();
ROLLBACK;
