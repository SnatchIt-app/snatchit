-- ============================================================================
-- 149_phase2_kernel_money_native.sql — Phase-2 package 085 suite.
--
-- Frozen sources: plan §8/085 · schema §1.8-§1.10a/§1.12.1 · RPC §6.3/§7.3/
-- §11.1-11.4/§17.1-17.9/§17.14/§20.7.x/§20.11.3/.5 · RLS §7.8-§7.10a + §11 ·
-- MONEY spec · OR-17/OR-21 · PFA-15/PFA-21/PFA-22 (owner-signed). D-3 keys are
-- ALL NULL-seeded: the suite proves the tier ladder FAILS CLOSED over NULL and
-- then sets values (as the owner will) to walk the dual-control loop.
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(130);

SELECT tap.seed_core();

CREATE TABLE tap.memo_149 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store149(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_149 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch149(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_149 WHERE k = $1 $m$;
-- phase-0 allows ONE succeeded payment per listing — mint a fresh listing per payment
CREATE FUNCTION tap._newlisting149() RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time,
      ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
    VALUES (tap.seller(), 'Money Night ' || gen_random_uuid()::text, 'Money Hall', 'wynwood',
      (now()+interval '15 days')::date, '20:00', 'GA', 2, 'mobile_transfer', 5000, 5000, 24,
      now()+interval '1 day', 'covers/fixture.jpg')
    RETURNING id $m$;

-- ============================================================================
-- SECTION A — THE 085 CLOSED WORLD
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relkind='r'), 26,
  'A1: kernel holds 26 tables — 22 post-084 + the four money ledgers');
SELECT has_table('kernel'::name,'payment_native'::name, 'A2: kernel.payment_native (the R-34 link ledger)');
SELECT has_table('kernel'::name,'refund'::name, 'A3: kernel.refund');
SELECT has_table('kernel'::name,'payout'::name, 'A4: kernel.payout');
SELECT has_table('kernel'::name,'identity_obligation'::name, 'A5: kernel.identity_obligation (OR-21)');
SELECT has_function('venue'::name,'finalize_primary_order'::name, ARRAY['uuid','uuid','text','text']::name[],
  'A6: venue.finalize_primary_order is authored HERE (R2B/C111 — not 082)');
SELECT has_function('venue'::name,'resolve_order_attribution'::name, ARRAY['uuid']::name[],
  'A7: the resolve_order_attribution SEAM-2 stub (body 090)');
SELECT has_function('venue'::name,'on_payout_settled'::name, ARRAY['uuid']::name[],
  'A8: the on_payout_settled SEAM-2 stub (body 087)');
-- market's FIRST routine — three p_-prefixed params (C117/S2-B canonical)
SELECT is((SELECT p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='market' AND p.proname='on_atom_voided'),
  ARRAY['p_atom_id','p_refund_id','p_cause'],
  'A9: market.on_atom_voided — THREE params, p_-prefixed (SEAM-2a frozen; the 2-param summaries are stale)');
SELECT has_function('kernel'::name,'void_ticket_atom'::name, ARRAY['uuid','uuid','text']::name[],
  'A10: the void engine (SSCAS #3; FR-4 — born here with kernel.refund)');
SELECT hasnt_function('kernel'::name,'request_org_payout'::name, 'A11: request_org_payout is NOT here (087)');
SELECT hasnt_function('kernel'::name,'transfer_ticket_ownership'::name, 'A12: the transfer engine is NOT here (088)');
SELECT hasnt_table('market'::name,'market_sale'::name, 'A13: market.market_sale is NOT here (088)');
SELECT is((SELECT count(*)::int FROM pg_constraint WHERE conrelid='kernel.payment_native'::regclass
            AND contype='f' AND conname LIKE '%sale%'), 0,
  'A14: payment_native.sale_id carries NO FK — that is 089''s adopt step');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname='sweep-expired-refund-requests'), 1,
  'A15: the refund-TTL tick is scheduled (P0-1 — not optional)');
SELECT is((SELECT value FROM catalog.platform_config
            WHERE key='deletion.refund_possible_window_hours' AND version=1), 'null'::jsonb,
  'A16: PFA-22 — the dedicated BP-12 operand is seeded NULL / owner-unset');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 48,
  -- 2026-09-01 (package 086): 39 -> 48 (+9 venue door/scan policies). 085 itself
  -- added ZERO — its four money tables are deny-all (GP-3a); this register census
  -- tracks the whole five-schema total, which 086 grew.
  'A17: 085 added ZERO policies (money tables deny-all, GP-3a); register now 48 after 086''s nine venue policies');

-- ============================================================================
-- SECTION B — GRANTS & CUSTODY WALLS (PFA-15/PFA-21; RLS §7.8-§7.10a)
-- ============================================================================
SELECT ok(has_schema_privilege('service_role','venue','USAGE'),
  'B1: PFA-15 — service_role holds venue USAGE (the webhook path to finalize/cancel)');
SELECT ok(has_schema_privilege('service_role','kernel','USAGE'),
  'B2: PFA-21 — service_role holds kernel USAGE (the state-sync path)');
SELECT ok(NOT has_schema_privilege('anon','venue','USAGE') AND NOT has_schema_privilege('anon','kernel','USAGE'),
  'B3: anon is NOT widened by either ruling (PFA-14 intact)');
SELECT ok(NOT has_function_privilege('authenticated','venue.finalize_primary_order(uuid,uuid,text,text)','EXECUTE')
       AND NOT has_function_privilege('anon','venue.finalize_primary_order(uuid,uuid,text,text)','EXECUTE')
       AND has_function_privilege('service_role','venue.finalize_primary_order(uuid,uuid,text,text)','EXECUTE'),
  'B4: finalize is service_role-ONLY — "an authenticated grant here is the single highest-severity migration defect available in this schema"');
SELECT ok(NOT has_function_privilege('service_role','kernel.record_money_denial(text,text,uuid,text)','EXECUTE')
       AND has_function_privilege('authenticated','kernel.record_money_denial(text,text,uuid,text)','EXECUTE'),
  'B5: R-28 — the denial witness is authenticated-ONLY, never service_role');
SELECT ok(NOT has_table_privilege('authenticated','kernel.payment_native','SELECT')
       AND NOT has_column_privilege('authenticated','kernel.payment_native','instrument_fingerprint','SELECT'),
  'B6: the fingerprint column is unreachable by any client (C112/PROMO §1.8)');
SELECT ok(NOT has_table_privilege('authenticated','kernel.payout','SELECT'),
  'B7: kernel.payout has NO direct client read — list_org_payouts is the only path (¹⁵ᵇ)');
SELECT ok(NOT has_table_privilege('service_role','kernel.identity_obligation','DELETE'),
  'B8: identity_obligation: no DELETE ever (GP-2)');
SELECT ok((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
           WHERE n.nspname='kernel' AND c.relname='payment_native'
             AND p.proname='raise_append_only' AND NOT t.tgisinternal) = 1,
  'B9: payment_native carries the append-only guard (schema §1.8 "effectively AO" — E-50)');
SELECT ok(NOT has_function_privilege('authenticated','kernel.void_ticket_atom(uuid,uuid,text)','EXECUTE')
       AND NOT has_function_privilege('service_role','kernel.void_ticket_atom(uuid,uuid,text)','EXECUTE'),
  'B10: the void engine is definer-only — NO grant to any client or machine role');

-- ============================================================================
-- FIXTURE — org → venue → event → session → tt → batch → key → order+payment
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store149('org', (kernel.create_organization('Money Co','Money Co','ck85-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch149('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store149('venue', (catalog.create_venue(tap._fetch149('org')::uuid,'Money Hall','wynwood',NULL,'ck85-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch149('venue')::uuid,'approved','miami_gate','ck85-a');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store149('event', (catalog.create_event(tap._fetch149('venue')::uuid,'Money Night',
  jsonb_build_object('starts_at',(now()+interval '15 days')::text,'ends_at',(now()+interval '15 days 5 hours')::text),'ck85-e') ->> 'event_id'));
SELECT tap._store149('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch149('event')::uuid));
SELECT tap._store149('tt', (venue.create_ticket_type(tap._fetch149('event')::uuid,'admission','GA',5000,'public','ck85-tt') ->> 'ticket_type_id'));
SELECT tap._store149('batch', (venue.create_inventory_batch(tap._fetch149('tt')::uuid, tap._fetch149('session')::uuid, 'public_sale', 100, 0, 'ck85-b') ->> 'batch_id'));
SELECT tap.logout();
WITH insk AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch149('event')::uuid, 'PUBKEY-85', 'kms-85', 'active', now())
  RETURNING key_id
)
SELECT tap._store149('key', (SELECT key_id::text FROM insk));
-- the pending order + its item (direct facts; 082's checkout is not under test)
WITH inso AS (
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'pending', 'web', 10000, 'ck85-ord-1')
  RETURNING order_id
)
SELECT tap._store149('order', (SELECT order_id::text FROM inso));
WITH insi AS (
  INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor)
  VALUES (tap._fetch149('order')::uuid, tap._fetch149('tt')::uuid, 2, 5000)
  RETURNING id
)
SELECT tap._store149('item', (SELECT id::text FROM insi));
-- the buyer's live hold (E-40/E-47(b) substrate) + the batch counter
WITH insh AS (
  INSERT INTO venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  VALUES (tap._fetch149('batch')::uuid, tap.buyer(), 2, 'active', now() + interval '1 hour', 'ck85-h-1')
  RETURNING hold_id
)
SELECT tap._store149('hold', (SELECT hold_id::text FROM insh));
UPDATE venue.inventory_batch SET held = 2 WHERE batch_id = tap._fetch149('batch')::uuid;
-- the frozen public rail: a listing + a SUCCEEDED payment for the buyer
WITH insl AS (
  INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time,
                               ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
  VALUES (tap.seller(), 'Money Night', 'Money Hall', 'wynwood', (now()+interval '15 days')::date, '20:00',
          'GA', 2, 'mobile_transfer', 5000, 5000, 24, now()+interval '1 day', 'covers/fixture.jpg')
  RETURNING id
)
SELECT tap._store149('listing', (SELECT id::text FROM insl));
WITH insp AS (
  INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
  VALUES (tap._fetch149('listing')::uuid, tap.buyer(), tap.seller(), 9000, 1000, 10000, 'succeeded', 'buy_now')
  RETURNING id
)
SELECT tap._store149('payment', (SELECT id::text FROM insp));

-- ============================================================================
-- SECTION C — FINALIZE (SSCAS #1): darkness, refusals, the E-40/E-47(b) draw
-- ============================================================================
SELECT throws_ok(format($$SELECT venue.finalize_primary_order(%L, %L, 'ck85-f-1', 'fp-1')$$,
    tap._fetch149('order'), tap._fetch149('payment')),
  NULL, 'precondition_failed: feature_disabled',
  'C1: while native issuance is DARK the money path cannot mint (the 083 gate holds through finalize)');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
-- E-23 (085 arm): an ERASED buyer acquires NOTHING — the defensive twin
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.other_user(), 'ERASED')
ON CONFLICT (identity_id) DO UPDATE SET deletion_state = 'ERASED';
WITH inso2 AS (
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.other_user(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'pending', 'web', 5000, 'ck85-ord-erased')
  RETURNING order_id
)
SELECT tap._store149('order_erased', (SELECT order_id::text FROM inso2));
SELECT throws_ok(format($$SELECT venue.finalize_primary_order(%L, %L, 'ck85-f-e', NULL)$$,
    tap._fetch149('order_erased'), tap._fetch149('payment')),
  NULL, 'precondition_failed: buyer identity is erased — no acquisition',
  'C2: E-23 — an ERASED buyer is refused BEFORE any payment logic (the F-6 defensive twin)');
-- an unverified payment is refused
WITH insp2 AS (
  INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
  VALUES (tap._fetch149('listing')::uuid, tap.buyer(), tap.seller(), 9000, 1000, 10000, 'pending', 'buy_now')
  RETURNING id
)
SELECT tap._store149('payment_pending', (SELECT id::text FROM insp2));
SELECT throws_ok(format($$SELECT venue.finalize_primary_order(%L, %L, 'ck85-f-2', NULL)$$,
    tap._fetch149('order'), tap._fetch149('payment_pending')),
  NULL, NULL, 'C3: a non-succeeded payment is payment_unverified — money is the authority, and it must be real');
-- the happy path: money → tickets
SELECT is((venue.finalize_primary_order(tap._fetch149('order')::uuid, tap._fetch149('payment')::uuid,
           'ck85-f-3', 'fp-1') ->> 'status'), 'ok',
  'C4: finalize DRAWS — the only function that turns money into tickets');
SELECT is((SELECT count(*)::int FROM kernel.tickets t
            WHERE t.event_session_id = tap._fetch149('session')::uuid), 2,
  'C5: two atoms minted');
SELECT is((SELECT sold::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid), 2,
  'C6: sold += 2 (the mint leg)');
SELECT is((SELECT held::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid), 0,
  'C7: held -= 2 BEFORE the mint (E-47(b) — C27 never saw held+sold exceed capacity)');
SELECT is((SELECT status FROM venue.inventory_hold WHERE hold_id = tap._fetch149('hold')::uuid), 'converted',
  'C8: the live hold converted WHOLE (E-40 — no blind decrement, no split row)');
SELECT ok((SELECT pn.instrument_fingerprint = 'fp-1' AND pn.amount_minor = 10000 AND pn.order_id = tap._fetch149('order')::uuid
             FROM kernel.payment_native pn WHERE pn.payment_id = tap._fetch149('payment')::uuid),
  'C9: the payment link carries the fingerprint (C112 — written by its contracted writer)');
SELECT is((SELECT status FROM venue."order" WHERE order_id = tap._fetch149('order')::uuid), 'paid',
  'C10: order → paid');
SELECT is((venue.finalize_primary_order(tap._fetch149('order')::uuid, tap._fetch149('payment')::uuid,
           'ck85-f-3', 'fp-1') ->> 'status'), 'idempotency_replay',
  'C11: webhook redelivery returns the ORIGINAL atom set — no second mint');
SELECT ok((SELECT count(*)::int FROM kernel.tickets t WHERE t.event_session_id = tap._fetch149('session')::uuid) = 2
       AND (SELECT sold::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid) = 2,
  'C12: …and the replay moved NOTHING (atoms 2, sold 2)');
SELECT ok(to_regclass('venue.attribution') IS NULL,
  'C13: T-SCHEMA-ISSUE-02/-03 — the purchase COMMITTED with NO attribution substrate: the stub never raised and could not have written (table+body are 090''s)');

-- ============================================================================
-- HELPERS for the money sections — clean per-test orders (superuser/definer).
-- ============================================================================
CREATE FUNCTION tap._neworder149(p_qty int, p_amount int) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_lst uuid; v_pay uuid; v_ord uuid;
begin
  insert into public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time,
     ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
   values (tap.seller(),'N '||gen_random_uuid()::text,'Money Hall','wynwood',(now()+interval '15 days')::date,'20:00',
     'GA',p_qty,'mobile_transfer',p_amount,p_amount,24,now()+interval '1 day','covers/x.jpg') returning id into v_lst;
  insert into public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
   values (v_lst, tap.buyer(), tap.seller(), p_amount, 0, p_amount, 'succeeded', 'buy_now') returning id into v_pay;
  insert into venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
   values (tap.buyer(), (select v from tap.memo_149 where k='session')::uuid,
           (select v from tap.memo_149 where k='org')::uuid, 'pending','web',p_amount,'ck-no-'||gen_random_uuid()::text)
   returning order_id into v_ord;
  insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor)
   values (v_ord, (select v from tap.memo_149 where k='tt')::uuid, p_qty, (p_amount/p_qty));
  insert into venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
   values ((select v from tap.memo_149 where k='batch')::uuid, tap.buyer(), p_qty, 'active', now()+interval '1 hour','ck-nh-'||gen_random_uuid()::text);
  update venue.inventory_batch set held = held + p_qty where batch_id=(select v from tap.memo_149 where k='batch')::uuid;
  perform venue.finalize_primary_order(v_ord, v_pay, 'ck-nf-'||gen_random_uuid()::text, null);
  return v_ord;
end $f$;
CREATE FUNCTION tap._atomsof149(p_order uuid) RETURNS uuid[]
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$
  select array_agg(t.ticket_atom_id order by t.ticket_atom_id) from kernel.tickets t
   join kernel.ticket_ownership_log l1 on l1.ticket_atom_id=t.ticket_atom_id and l1.sequence=1
   where l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id=p_order) $f$;
CREATE FUNCTION tap._payof149(p_order uuid) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$
  select payment_id from kernel.payment_native where order_id=p_order $f$;
CREATE FUNCTION tap._ordstatus149(p_order uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$ select status from venue."order" where order_id=p_order $f$;
CREATE FUNCTION tap._atomstate149(p_atom uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$ select state from kernel.tickets where ticket_atom_id=p_atom $f$;
CREATE FUNCTION tap._aal2() RETURNS void
LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- ============================================================================
-- SECTION D — THE REFUND PATH (PFA-23): direct executor is EXEC DEF; humans go
--   through request_order_refund (auto-exec for platform) / approve.
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.refund_primary_order(gen_random_uuid(), 100, 'buyer_request', 'x')$$,
  '42501', NULL, 'D1: PFA-23 — refund_primary_order is EXEC DEF; a plain authenticated caller cannot reach it');
SELECT tap.logout();
-- a full platform refund flows through the request auto-exec tier (admin/risk)
SELECT tap._store149('od', tap._neworder149(2, 10000)::text);
SELECT tap._store149('od_atoms', tap._atomsof149(tap._fetch149('od')::uuid)::text);
SELECT tap.login(tap.admin_user());
SELECT is((kernel.request_order_refund(tap._fetch149('od')::uuid, tap._fetch149('od_atoms')::uuid[],
    10000, 'admin_action', 'ck-d-1') ->> 'status'), 'executed',
  'D2: platform_admin refund auto-executes through request_order_refund (PFA-23 delegated key)');
SELECT tap.logout();
SELECT ok((SELECT bool_and(t.state='voided' AND t.current_owner_id='00000000-0000-0000-0000-0000000000f0'
                           AND t.credential_version=1)
             FROM kernel.tickets t WHERE t.ticket_atom_id = any(tap._fetch149('od_atoms')::uuid[])),
  'D3: both atoms voided — SN-VOID + credential bump (S-18/C107)');
SELECT is(tap._ordstatus149(tap._fetch149('od')::uuid), 'refunded', 'D4: order → refunded (full coverage)');
SELECT is((SELECT count(*)::int FROM kernel.refund r WHERE r.payment_id = tap._payof149(tap._fetch149('od')::uuid)), 1,
  'D5: exactly one refund ledger row');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action='refund.issue'
            AND subject_id = tap._fetch149('od')::uuid), 1, 'D6: the refund is admin-audited in-txn');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.request_order_refund(tap._fetch149('od')::uuid, tap._fetch149('od_atoms')::uuid[],
    10000, 'admin_action', 'ck-d-1') ->> 'status'), 'idempotency_replay',
  'D7: the request replays by command key — no double refund');
SELECT tap.logout();
-- PFA-23 single-use: a stranger who learns an approved request_id cannot re-drain
SELECT tap._store149('od_req', (SELECT request_id::text FROM kernel.approval_request
  WHERE command_idempotency_key='ck-d-1'));
SELECT ok(NOT has_function_privilege('authenticated','kernel.refund_primary_order(uuid,integer,text,text)','EXECUTE')
       AND NOT has_function_privilege('anon','kernel.refund_primary_order(uuid,integer,text,text)','EXECUTE')
       AND has_function_privilege('service_role','kernel.refund_primary_order(uuid,integer,text,text)','EXECUTE'),
  'D8: PFA-23 — the executor is EXEC DEF (service_role only; not authenticated/anon) — the drain surface is gone');

-- ── PARTIAL refund + the Σ over-refund guard (R5 P0-1) ──────────────────────
SELECT tap._store149('op', tap._neworder149(2, 10000)::text);
SELECT tap._store149('op_atoms', tap._atomsof149(tap._fetch149('op')::uuid)::text);
SELECT tap.login(tap.admin_user());
SELECT is((kernel.request_order_refund(tap._fetch149('op')::uuid,
    ARRAY[(tap._fetch149('op_atoms')::uuid[])[1]], 5000, 'admin_action', 'ck-p-1') ->> 'status'), 'executed',
  'DP1: a PARTIAL refund (one atom, 5000 of 10000) executes');
SELECT tap.logout();
SELECT is(tap._atomstate149((tap._fetch149('op_atoms')::uuid[])[1]), 'voided', 'DP2: only the targeted atom voided');
SELECT is(tap._atomstate149((tap._fetch149('op_atoms')::uuid[])[2]), 'active', 'DP3: the untargeted atom stays live');
SELECT is(tap._ordstatus149(tap._fetch149('op')::uuid), 'partially_refunded', 'DP4: order → partially_refunded');
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT kernel.request_order_refund(%L, ARRAY[%L]::uuid[], 6000, 'admin_action', 'ck-p-2')$$,
    tap._fetch149('op'), (tap._fetch149('op_atoms')::uuid[])[2]),
  NULL, 'precondition_failed: over_refund (cumulative 11000 > payment total 10000)',
  'DP5: R5 P0-1 — a further refund exceeding the remaining balance is over_refund (the Σ-guard FIRES)');
SELECT is((kernel.request_order_refund(tap._fetch149('op')::uuid,
    ARRAY[(tap._fetch149('op_atoms')::uuid[])[2]], 5000, 'admin_action', 'ck-p-3') ->> 'status'), 'executed',
  'DP6: exactly the remaining 5000 executes');
SELECT tap.logout();
SELECT is(tap._ordstatus149(tap._fetch149('op')::uuid), 'refunded', 'DP7: …and the order is now fully refunded');

-- ── force_void (E-56 replay) ────────────────────────────────────────────────
SELECT tap._store149('ofv', tap._neworder149(1, 4000)::text);
SELECT tap._store149('ofv_atom', ((tap._atomsof149(tap._fetch149('ofv')::uuid))[1])::text);
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.force_void_ticket(%L,'r','ck-fv-x')$$, tap._fetch149('ofv_atom')),
  '42501', NULL, 'DF1: force_void refuses a non-platform caller');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT is((kernel.force_void_ticket(tap._fetch149('ofv_atom')::uuid, 'leak', 'ck-fv-1') ->> 'status'), 'ok',
  'DF2: platform force-voids a LIVE atom');
SELECT is((kernel.force_void_ticket(tap._fetch149('ofv_atom')::uuid, 'leak', 'ck-fv-1') ->> 'status'), 'noop_replay',
  'DF3: E-56 — a replayed force_void returns noop_replay (deterministic synthetic ref), not state_conflict');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action='ticket.force_void'
            AND subject_id=tap._fetch149('ofv_atom')::uuid), 1, 'DF4: the force-void is audited');

-- ============================================================================
-- SECTION E — DUAL CONTROL (§17.2): NULL keys fail closed; approve needs aal2.
-- ============================================================================
SELECT tap._store149('oe', tap._neworder149(2, 10000)::text);
SELECT tap._store149('oe_atoms', tap._atomsof149(tap._fetch149('oe')::uuid)::text);
-- E1: all amount keys NULL AND no TTL → the parked branch refuses config_unset
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.request_order_refund(%L, %L::uuid[], 10000, 'buyer_request', 'ck-e-0')$$,
    tap._fetch149('oe'), tap._fetch149('oe_atoms')),
  NULL, 'precondition_failed: config_unset refund.request_ttl_hours — parked requests need a bounded life (C61 fail-closed)',
  'E1: NULL keys + no TTL → config_unset (nothing auto-executes, nothing parks unbounded)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('refund.request_ttl_hours', 2, '24'::jsonb, 'restricted');
SELECT tap.login(tap.buyer());
SELECT tap._store149('e_req1', (kernel.request_order_refund(tap._fetch149('oe')::uuid, tap._fetch149('oe_atoms')::uuid[],
    10000, 'buyer_request', 'ck-e-1') ->> 'request_id'));
SELECT tap.logout();
SELECT is((SELECT required_approver_class FROM kernel.approval_request WHERE request_id=tap._fetch149('e_req1')::uuid), 'platform',
  'E2: NULL amount keys → the buyer request PARKS to the STRICTEST class (platform)');
SELECT ok((SELECT bool_and(t.resale_state='refund_hold') FROM kernel.tickets t
            WHERE t.ticket_atom_id = any(tap._fetch149('oe_atoms')::uuid[])),
  'E3: the refund_hold overlay landed on the targeted atoms');
-- SoD-2 + step-up
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L,'approve','r','ck-e-ap0')$$, tap._fetch149('e_req1')),
  NULL, 'self_approval: the requester cannot decide their own request', 'E4: SoD-2 — the requester cannot approve');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L,'approve','r','ck-e-ap1')$$, tap._fetch149('e_req1')),
  NULL, 'step_up_unavailable: the session carries no aal claim', 'E5: AUTHZ-M4 — approve with NO aal claim is step_up_unavailable');
SELECT set_config('request.jwt.claims', (current_setting('request.jwt.claims',true)::jsonb||'{"aal":"aal1"}'::jsonb)::text, true);
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L,'approve','r','ck-e-ap2')$$, tap._fetch149('e_req1')),
  NULL, 'step_up_required: a step-up (aal2) session is required to approve money', 'E6: aal1 is step_up_required');
-- deny needs no step-up (S-3 spirit) and no reason → precondition
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L,'deny','','ck-e-ap3')$$, tap._fetch149('e_req1')),
  NULL, NULL, 'E7: a denial without a reason is refused');
SELECT is((kernel.approve_refund_request(tap._fetch149('e_req1')::uuid,'deny','not_warranted','ck-e-ap4') ->> 'status'),
  'denied', 'E8: platform denies WITHOUT a step-up (refusing money is not moving it)');
SELECT tap.logout();
SELECT ok((SELECT bool_and(t.resale_state='none') FROM kernel.tickets t
            WHERE t.ticket_atom_id = any(tap._fetch149('oe_atoms')::uuid[])),
  'E9: …the refund_hold overlays released on denial');
-- ORG dual-control arm + maturity + aal2
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('refund.org_dual_control_max_minor', 2, '50000'::jsonb, 'restricted');
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by)
VALUES (tap._fetch149('org')::uuid, tap.other_user(), 'org_finance', tap.seller()) ON CONFLICT DO NOTHING;
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.other_user();
SELECT tap._store149('oe2', tap._neworder149(2, 10000)::text);
SELECT tap._store149('oe2_atoms', tap._atomsof149(tap._fetch149('oe2')::uuid)::text);
SELECT tap.login(tap.buyer());
SELECT tap._store149('e_req2', (kernel.request_order_refund(tap._fetch149('oe2')::uuid, tap._fetch149('oe2_atoms')::uuid[],
    10000, 'buyer_request', 'ck-e-2') ->> 'request_id'));
SELECT tap.logout();
SELECT is((SELECT required_approver_class FROM kernel.approval_request WHERE request_id=tap._fetch149('e_req2')::uuid), 'org',
  'E10: with org_dual set (50000), a 10000 request parks to the ORG class');
-- immature org approver (even with aal2) → sod_violation
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L,'approve','ok','ck-e-3')$$, tap._fetch149('e_req2')),
  NULL, 'sod_violation: org money grant not yet matured', 'E11: an IMMATURE org grant fails as sod_violation (C58)');
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now() - interval '100 hours'
 WHERE org_id=tap._fetch149('org')::uuid AND identity_id=tap.other_user();
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is((kernel.approve_refund_request(tap._fetch149('e_req2')::uuid,'approve','ok','ck-e-4') ->> 'status'), 'approved',
  'E12: the MATURED org approver + aal2 completes dual control — the refund EXECUTES');
SELECT tap.logout();
SELECT is(tap._ordstatus149(tap._fetch149('oe2')::uuid), 'refunded', 'E13: …order2 refunded via the approved request (delegated, single-use)');
-- P0-3: an atom SCANNED while parked re-tiers to platform at approve (live read)
SELECT tap._store149('oe3', tap._neworder149(2, 10000)::text);
SELECT tap._store149('oe3_atoms', tap._atomsof149(tap._fetch149('oe3')::uuid)::text);
SELECT tap.login(tap.buyer());
SELECT tap._store149('e_req3', (kernel.request_order_refund(tap._fetch149('oe3')::uuid, tap._fetch149('oe3_atoms')::uuid[],
    10000, 'buyer_request', 'ck-e-5') ->> 'request_id'));
SELECT tap.logout();
UPDATE kernel.tickets SET state='scanned' WHERE ticket_atom_id = (tap._fetch149('oe3_atoms')::uuid[])[1];
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is((kernel.approve_refund_request(tap._fetch149('e_req3')::uuid,'approve','ok','ck-e-6') ->> 'status'), 'stale',
  'E14: P0-3 — an atom scanned while parked re-tiers from LIVE state to platform ⇒ stale (not the payload snapshot)');
SELECT tap.logout();
-- the expiry sweep releases a REAL hold (R5 P0-2)
SELECT tap._store149('oe4', tap._neworder149(1, 4000)::text);
SELECT tap._store149('oe4_atoms', tap._atomsof149(tap._fetch149('oe4')::uuid)::text);
SELECT tap.login(tap.buyer());
SELECT tap._store149('e_req4', (kernel.request_order_refund(tap._fetch149('oe4')::uuid, tap._fetch149('oe4_atoms')::uuid[],
    4000, 'buyer_request', 'ck-e-7') ->> 'request_id'));
SELECT tap.logout();
SELECT is((SELECT resale_state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch149('oe4_atoms')::uuid[])[1]), 'refund_hold',
  'E15: the parked request holds the atom');
UPDATE kernel.approval_request SET created_at = now()-interval '2 hours', expires_at = now()-interval '1 minute'
 WHERE request_id = tap._fetch149('e_req4')::uuid;
SELECT ok(((kernel.sweep_expired_refund_requests()) ->> 'holds_released')::int >= 1,
  'E16: R5 P0-2 — the sweep releases a REAL refund_hold (holds_released >= 1)');
SELECT is((SELECT resale_state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch149('oe4_atoms')::uuid[])[1]), 'none',
  'E17: …the atom overlay is cleared');
SELECT is((SELECT state FROM kernel.approval_request WHERE request_id=tap._fetch149('e_req4')::uuid), 'expired', 'E18: …and the request is expired');
-- cancel
SELECT tap._store149('oe5', tap._neworder149(1, 4000)::text);
SELECT tap.login(tap.buyer());
SELECT tap._store149('e_req5', (kernel.request_order_refund(tap._fetch149('oe5')::uuid,
    tap._atomsof149(tap._fetch149('oe5')::uuid), 4000, 'buyer_request', 'ck-e-8') ->> 'request_id'));
SELECT is((kernel.cancel_refund_request(tap._fetch149('e_req5')::uuid,'changed_mind','ck-e-9') ->> 'status'), 'cancelled',
  'E19: the requester cancels their own pending request (no maturity/step-up — S-3)');
SELECT tap.logout();
-- reason-code caller policy (R7 P2)
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.request_order_refund(%L, %L::uuid[], 100, 'dispute', 'ck-e-rc')$$,
    tap._fetch149('oe5'), tap._atomsof149(tap._fetch149('oe5')::uuid)),
  NULL, 'policy_violation: reason_code dispute is platform-only', 'E20: R7 P2 — a buyer cannot cite a platform-only reason code');
SELECT tap.logout();

-- ============================================================================
-- SECTION M — admin_refund (§20.7.1): linkage + authority (R5 P1)
-- ============================================================================
SELECT tap._store149('om', tap._neworder149(2, 10000)::text);
SELECT tap._store149('om_atoms', tap._atomsof149(tap._fetch149('om')::uuid)::text);
SELECT tap._store149('om_pay', tap._payof149(tap._fetch149('om')::uuid)::text);
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.admin_refund(%L, %L::uuid[], 100, 'dispute', 'ck-m-x')$$,
    tap._fetch149('om_pay'), tap._fetch149('om_atoms')),
  '42501', NULL, 'M1: admin_refund refuses a non-platform caller');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT kernel.admin_refund(%L, ARRAY[gen_random_uuid()]::uuid[], 100, 'dispute', 'ck-m-y')$$,
    tap._fetch149('om_pay')),
  NULL, NULL, 'M2: E-57 — atoms that do not belong to the payment are rejected (linkage)');
SELECT is((kernel.admin_refund(tap._fetch149('om_pay')::uuid, tap._fetch149('om_atoms')::uuid[], 10000, 'dispute', 'ck-m-1') ->> 'status'),
  'ok', 'M3: admin_refund voids the payment''s own atoms');
SELECT throws_ok(format($$SELECT kernel.admin_refund(%L, %L::uuid[], 1, 'dispute', 'ck-m-2')$$,
    tap._fetch149('om_pay'), tap._fetch149('om_atoms')),
  NULL, NULL, 'M4: one more cent is over_refund (Σ-guard under the payment lock)');
SELECT tap.logout();
SELECT is(tap._ordstatus149(tap._fetch149('om')::uuid), 'refunded', 'M5: …and admin_refund reflected the linked order → refunded (R1 P2)');

-- ============================================================================
-- SECTION N — platform_support cap ladder (R5 P1; AUTHZ-M3)
-- ============================================================================
INSERT INTO kernel.platform_role (identity_id, role) VALUES (tap.other_user(), 'platform_support') ON CONFLICT DO NOTHING;
SELECT tap._store149('on1', tap._neworder149(1, 4000)::text);
SELECT tap.login(tap.other_user());   -- support, support cap key still NULL
SELECT is((kernel.request_order_refund(tap._fetch149('on1')::uuid, tap._atomsof149(tap._fetch149('on1')::uuid),
    4000, 'oversell_correction', 'ck-n-1') ->> 'status'), 'parked',
  'N1: support with a NULL cap key auto-executes NOTHING — it PARKS (AUTHZ-M3 unset=ZERO)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('refund.platform_support_max_minor', 2, '500000'::jsonb, 'restricted');
SELECT tap._store149('on2', tap._neworder149(1, 4000)::text);
SELECT tap.login(tap.other_user());
SELECT is((kernel.request_order_refund(tap._fetch149('on2')::uuid, tap._atomsof149(tap._fetch149('on2')::uuid),
    4000, 'oversell_correction', 'ck-n-2') ->> 'status'), 'executed',
  'N2: with the support cap set above the amount, support auto-executes (capped tier)');
SELECT tap.logout();
DELETE FROM kernel.platform_role WHERE identity_id=tap.other_user() AND role='platform_support';

-- ============================================================================
-- SECTION O — the scoped reads (§17.5/6/8): scope walls + PII (R5 P1)
-- ============================================================================
WITH inspo AS (INSERT INTO kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, status, stripe_transfer_ref, idempotency_key)
  VALUES ('organization', tap._fetch149('org')::uuid, 'settlement', gen_random_uuid(), 20000, 'paid', 'tr_secret', 'ck-o-po') RETURNING payout_id)
SELECT tap._store149('o_payout', (SELECT payout_id::text FROM inspo));
SELECT tap.login(tap.seller());   -- org_owner of the org
SELECT is((kernel.list_org_payouts(tap._fetch149('org')::uuid, NULL, '{}'::jsonb, NULL) ->> 'status'), 'ok',
  'O1: an org role lists its own payouts');
SELECT ok((kernel.list_org_payouts(tap._fetch149('org')::uuid, NULL, '{}'::jsonb, NULL) -> 'payouts') @> '[{"has_transfer_ref":true}]'::jsonb
       AND NOT ((kernel.list_org_payouts(tap._fetch149('org')::uuid, NULL, '{}'::jsonb, NULL))::text LIKE '%tr_secret%'),
  'O2: the stripe transfer ref surfaces as a PRESENCE boolean, never the raw value (no PII)');
SELECT throws_ok($$SELECT kernel.list_org_payouts(NULL, NULL, '{}'::jsonb, NULL)$$, NULL, NULL,
  'O3: no scope-free form (an org or venue scope is required)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.list_org_refunds(%L, NULL, '{}'::jsonb, NULL)$$, tap._fetch149('org')),
  '42501', NULL, 'O4: a non-member cannot list an org''s refunds');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — PAYOUT HOLDS + STATE SYNC (MB-2; §20.7.6)
-- ============================================================================
WITH inspo AS (INSERT INTO kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('organization', tap._fetch149('org')::uuid, 'settlement', gen_random_uuid(), 20000, 'submitted', 'ck-f-po') RETURNING payout_id)
SELECT tap._store149('payout', (SELECT payout_id::text FROM inspo));
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.hold_payout(%L,'risk','ck-f-x')$$, tap._fetch149('payout')),
  '42501', NULL, 'F1: hold_payout refuses non-platform callers');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT is((kernel.hold_payout(tap._fetch149('payout')::uuid, 'risk_review', 'ck-f-1') ->> 'status'), 'ok', 'F2: platform holds the payout');
SELECT tap.logout();
SELECT ok((SELECT p.hold_state='held' AND p.status='submitted' AND p.held_by IS NOT NULL
             FROM kernel.payout p WHERE p.payout_id=tap._fetch149('payout')::uuid),
  'F3: the hold is the FOUR-COLUMN overlay — status untouched (S-15/C105)');
SELECT throws_ok(format($$SELECT kernel.mark_payout_transfer_state(%L,'paid','tr_1',NULL,'ck-f-2')$$, tap._fetch149('payout')),
  NULL, 'precondition_failed: payout_held', 'F4: a HELD payout refuses the webhook sync (Control-4)');
SELECT ok((SELECT p.status='submitted' AND p.stripe_transfer_ref IS NULL FROM kernel.payout p WHERE p.payout_id=tap._fetch149('payout')::uuid),
  'F5: …and BOTH columns untouched (T-SCHEMA-PAYOUT-06 — zero mutation on refusal)');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.release_payout(tap._fetch149('payout')::uuid, 'ck-f-3') ->> 'status'), 'ok', 'F6: platform releases the hold');
SELECT tap.logout();
SELECT ok((SELECT p.hold_state='none' AND p.hold_reason_code IS NULL AND p.held_by IS NULL AND p.held_at IS NULL
             FROM kernel.payout p WHERE p.payout_id=tap._fetch149('payout')::uuid),
  'F7: …all four hold columns cleared together');
SELECT is((kernel.mark_payout_transfer_state(tap._fetch149('payout')::uuid,'paid','tr_1',NULL,'ck-f-4') ->> 'status'), 'ok',
  'F8: the executor syncs paid (form (a), O16) — the settlement hook fires as a no-op stub');
SELECT is((kernel.mark_payout_transfer_state(tap._fetch149('payout')::uuid,'paid','tr_1',NULL,'ck-f-5') ->> 'status'), 'noop_replay',
  'F9: the same sync replays as noop');
SELECT throws_ok(format($$SELECT kernel.mark_payout_transfer_state(%L,'failed','tr_1','x','ck-f-6')$$, tap._fetch149('payout')),
  NULL, 'precondition_failed: payout_state_backwards (paid → failed)', 'F10: paid → failed is BACKWARDS');
SELECT is((kernel.mark_payout_transfer_state(tap._fetch149('payout')::uuid,'reversed','tr_1',NULL,'ck-f-7') ->> 'status'), 'ok',
  'F11: paid → reversed is the one legal terminal-to-terminal edge');

-- ============================================================================
-- SECTION G — REFUND STATE SYNC (§20.7.7; S-24) on a real refund
-- ============================================================================
SELECT tap._store149('g_refund', (SELECT r.refund_id::text FROM kernel.refund r
  WHERE r.payment_id=tap._payof149(tap._fetch149('od')::uuid) LIMIT 1));
SELECT is((kernel.mark_refund_state(tap._fetch149('g_refund')::uuid,'submitted','re_1',NULL,'ck-g-1') ->> 'status'), 'ok',
  'G1: pending → submitted (the ref is mandatory)');
SELECT throws_ok(format($$SELECT kernel.mark_refund_state(%L,'succeeded','re_DIFF',NULL,'ck-g-2')$$, tap._fetch149('g_refund')),
  NULL, 'conflict_locked: stripe_refund_ref is write-once', 'G2: the stripe ref is WRITE-ONCE');
SELECT is((kernel.mark_refund_state(tap._fetch149('g_refund')::uuid,'succeeded','re_1',NULL,'ck-g-3') ->> 'status'), 'ok',
  'G3: submitted → succeeded');
SELECT throws_ok(format($$SELECT kernel.mark_refund_state(%L,'submitted','re_1',NULL,'ck-g-4')$$, tap._fetch149('g_refund')),
  NULL, 'precondition_failed: refund_state_backwards (succeeded → submitted)', 'G4: succeeded → submitted is BACKWARDS');
SELECT throws_ok(format($$UPDATE kernel.refund SET stripe_refund_ref=NULL WHERE refund_id=%L$$, tap._fetch149('g_refund')),
  '23514', NULL, 'G5: the S-24 pairing CHECK makes a ref-less non-pending row UNSTORABLE');

-- ============================================================================
-- SECTION H — OBLIGATIONS (OR-21) + BP-10
-- ============================================================================
SELECT tap._store149('oref', gen_random_uuid()::text);
SELECT is((kernel.record_identity_obligation(tap.buyer(), 'chargeback', tap._fetch149('oref')::uuid, 'dp_1', 500, 'cb', 'ck-h-1') ->> 'status'),
  'ok', 'H1: the machine records an obligation');
SELECT is((kernel.record_identity_obligation(tap.buyer(), 'chargeback', tap._fetch149('oref')::uuid, 'dp_1', 500, 'cb', 'ck-h-1') ->> 'status'),
  'noop_replay', 'H2: (origin_kind, origin_ref) replays as noop');
SELECT is(kernel.has_outstanding_obligations(tap.buyer()), true, 'H3: BP-10 — the REAL body sees the debt (STABLE)');
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.resolve_identity_obligation(gen_random_uuid(),'recovered','r','ck-h-x')$$,
  '42501', NULL, 'H4: resolve refuses non-platform callers');
SELECT tap.logout();
SELECT tap._store149('oblig', (SELECT o.obligation_id::text FROM kernel.identity_obligation o WHERE o.origin_ref=tap._fetch149('oref')::uuid));
SELECT tap.login(tap.admin_user());
SELECT is((kernel.resolve_identity_obligation(tap._fetch149('oblig')::uuid,'recovered','paid_back','ck-h-2') ->> 'status'), 'ok', 'H5: platform resolves it');
SELECT throws_ok(format($$SELECT kernel.resolve_identity_obligation(%L,'written_off','w','ck-h-3')$$, tap._fetch149('oblig')),
  NULL, 'state_conflict: obligation '||tap._fetch149('oblig')||' already recovered — terminals are exclusive', 'H6: a different terminal is state_conflict');
SELECT tap.logout();
SELECT is(kernel.has_outstanding_obligations(tap.buyer()), false, 'H7: …and BP-10 clears');

-- ============================================================================
-- SECTION I — DELETION BLOCKERS (BP-5 in-flight; PFA-22 window)
-- ============================================================================
WITH inspi AS (INSERT INTO kernel.payout (payee_kind, payee_identity_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('identity', tap.other_user(), 'refund_void', gen_random_uuid(), 700, 'submitted', 'ck-i-po') RETURNING payout_id)
SELECT tap._store149('i_payout', (SELECT payout_id::text FROM inspi));
SELECT ok(kernel.deletion_blockers_money(tap.other_user()) LIKE 'BP-5%', 'I1: an IN-FLIGHT identity payout blocks (BP-5)');
SELECT kernel.mark_payout_transfer_state(tap._fetch149('i_payout')::uuid,'failed','tr_x','net_fail','ck-i-1');
SELECT is(kernel.deletion_blockers_money(tap.other_user()), NULL,
  'I2: R1 P3 — a TERMINAL failed payout does NOT block forever (BP-5 is in-flight only)');
-- PFA-22 window arm, tested on other_user (clean: their only money fact was the
-- now-failed payout above — no in-flight refunds/requests to mask the window arm,
-- unlike the refund-polluted buyer). A bare paid order is enough for arm 2.
INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
VALUES (tap.other_user(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'paid', 'web', 4000, 'ck-i-cand');
SELECT ok(kernel.deletion_blockers_money(tap.other_user()) LIKE 'BP-12%window unset%',
  'I3: PFA-22 — a candidate paid order + NULL window ⇒ BLOCKED (fail-closed exactly when it must be)');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('deletion.refund_possible_window_hours', 2, '0'::jsonb, 'restricted');
SELECT is(kernel.deletion_blockers_money(tap.other_user()), NULL,
  'I4: …the owner sets the window (0h); the candidate falls outside it — unblocked');
SELECT is(kernel.deletion_blockers_money(tap.admin_user()), NULL,
  'I5: an identity with NO candidates + NO money facts is never blocked by the NULL key (owner scoping verbatim)');

-- ============================================================================
-- SECTION J — Q5 RELEASE (OR-17 / DSM §3.1): keyed on requested_by (P0-5)
-- ============================================================================
SELECT tap._store149('oj', tap._neworder149(1, 4000)::text);
SELECT tap._store149('oj_atoms', tap._atomsof149(tap._fetch149('oj')::uuid)::text);
SELECT tap.login(tap.buyer());
SELECT tap._store149('j_req', (kernel.request_order_refund(tap._fetch149('oj')::uuid, tap._fetch149('oj_atoms')::uuid[],
    4000, 'buyer_request', 'ck-j-1') ->> 'request_id'));
SELECT tap.logout();
SELECT is((SELECT resale_state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch149('oj_atoms')::uuid[])[1]), 'refund_hold',
  'J1: the buyer''s own request holds the atom');
SELECT lives_ok(format($$SELECT kernel.on_deletion_q5_release(%L)$$, tap.buyer()), 'J2: the Q5 release runs');
SELECT is((SELECT state FROM kernel.approval_request WHERE request_id=tap._fetch149('j_req')::uuid), 'expired',
  'J3: …the request the deleter AUTHORED (requested_by) is expired');
SELECT is((SELECT resale_state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch149('oj_atoms')::uuid[])[1]), 'none',
  'J4: R5 P0-2 — …and its refund_hold overlay is really released');

-- ============================================================================
-- SECTION K — THE DENIAL WITNESS (§17.9; R-28; T-SCHEMA-AUDIT-01/-02)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT is((kernel.record_money_denial('refund.request','order', tap._fetch149('od')::uuid, 'insufficient_privilege') ->> 'status'),
  'ok', 'K1: an authenticated human records their denial');
SELECT throws_ok($$SELECT kernel.record_money_denial('rm -rf','order', gen_random_uuid(),'x')$$, NULL, NULL,
  'K2: the action vocabulary is CLOSED');
SELECT tap.logout();
SELECT throws_ok(format($$SELECT kernel.record_money_denial('refund.request','order',%L,'x')$$, tap._fetch149('od')),
  '42501', NULL, 'K3: T-SCHEMA-AUDIT-01 — with NO principal (auth.uid() NULL) the witness RAISES');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action='refund.request.denied' AND actor_identity=tap.buyer()), 1,
  'K4: the denial is attributed to auth.uid() and nothing else');

-- ============================================================================
-- SECTION L — PAYOUT DESTINATION (§17.7; SoD-1; AUTHZ-M4)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.set_org_payout_destination(%L,'acct_X1','r','ck-l-x')$$, tap._fetch149('org')),
  '42501', NULL, 'L1: only org_owner may touch the destination (SoD-1)');
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now()-interval '100 hours'
 WHERE org_id=tap._fetch149('org')::uuid AND identity_id=tap.seller();
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT kernel.set_org_payout_destination(%L,'acct_X1','r','ck-l-0')$$, tap._fetch149('org')),
  NULL, 'step_up_unavailable: the session carries no aal claim', 'L2: a session with NO aal claim is step_up_unavailable');
SELECT tap._aal2();
SELECT is((kernel.set_org_payout_destination(tap._fetch149('org')::uuid, 'acct_NEW1', 'rotation', 'ck-l-1') ->> 'status'), 'ok',
  'L3: matured org_owner + aal2 changes the destination');
SELECT tap.logout();
SELECT ok((SELECT o.stripe_connect_account_ref='acct_NEW1' AND o.payout_destination_set_by=tap.seller()
             FROM kernel.organization o WHERE o.org_id=tap._fetch149('org')::uuid),
  'L4: …the setter is recorded (the §8.2 SoD exclusion now binds them at approval time)');


SELECT finish();
ROLLBACK;
