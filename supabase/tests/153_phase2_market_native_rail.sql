-- ============================================================================
-- 153_phase2_market_native_rail.sql — Phase-2 package 088 suite.
-- Frozen sources: plan §8/088 · schema §4.1-§4.5/§1.10b · RPC §1.2/§1.4/§4.4/
-- §7.2/§7.4/§8.1-8.3/§12.2-12.3/§20.7.13-15/§20.8.1-12/§20.11.1/§20.11.3/§17.10a/
-- §20.17.3 · RLS §11/§16.10 · R-37/R-40 · E-22/E-23 · PFA-13 · OR-17/OR-24 ·
-- ODR-16 · PFA-29 (O-C, owner-signed) · E-90 · PFA-30 (split PARKED fail-closed,
-- owner-signed) · PFA-31 (dispute resolution PARKED fail-closed, owner-signed) ·
-- E-89..E-103 · P2P_TRANSFER_TTL / PAID_PENDING_DWELL_SLO parks (PFA-9/X-12).
-- Native resale stays DARK (flag false at seed; flipped in-suite under ROLLBACK).
-- BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(367);

SELECT tap.seed_core();

CREATE TABLE tap.memo_153 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store153(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_153 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch153(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_153 WHERE k=$1 $m$;
CREATE FUNCTION tap._u153(k text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_153 WHERE k=$1 $m$;
CREATE FUNCTION tap._audit153(p_subject uuid, p_action text, p_reason text DEFAULT NULL) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = p_subject AND a.action = p_action AND (p_reason IS NULL OR a.reason_code = p_reason) $m$;
CREATE FUNCTION tap._outbox153(p_type text, p_agg uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM notify.outbox o WHERE o.event_type = p_type AND o.aggregate_id = p_agg $m$;
CREATE FUNCTION tap._atom153(p_atom uuid) RETURNS kernel.tickets LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT t FROM kernel.tickets t WHERE t.ticket_atom_id = p_atom $m$;
CREATE FUNCTION tap._sale153(p_sale uuid) RETURNS market.market_sale LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT s FROM market.market_sale s WHERE s.sale_id = p_sale $m$;
CREATE FUNCTION tap._listing153(p_l uuid) RETURNS market.listing_native LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT l FROM market.listing_native l WHERE l.listing_id = p_l $m$;
CREATE FUNCTION tap._cfg153(p_key text, p_val jsonb, p_vis text DEFAULT 'restricted') RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.platform_config (key, version, value, visibility)
    SELECT p_key, coalesce(max(version),0)+1, p_val, p_vis FROM catalog.platform_config WHERE key = p_key $m$;
CREATE FUNCTION tap._refund153(p_pay uuid, p_key text) RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO kernel.refund (payment_id, reason_code, amount_minor, idempotency_key) VALUES (p_pay, 'admin_action', 1, p_key) RETURNING refund_id $m$;
-- lock_ticket is definer-internal (no client EXECUTE): the suite reaches it through a
-- definer wrapper; auth.uid() still resolves to the logged-in owner (the 079 owner check).
CREATE FUNCTION tap._lock153(p_atom uuid, p_reason text, p_key text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT kernel.lock_ticket(p_atom, p_reason, p_key) $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- phase-0 allows ONE succeeded payment per listing — a fresh listing per payment
CREATE FUNCTION tap._newlisting153(p_seller uuid) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time,
      ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
    VALUES (p_seller, 'Rail Night ' || gen_random_uuid()::text, 'Rail Hall', 'wynwood',
      (now()+interval '15 days')::date, '20:00', 'GA', 2, 'mobile_transfer', 5000, 5000, 24,
      now()+interval '1 day', 'covers/fixture.jpg')
    RETURNING id $m$;
CREATE FUNCTION tap._newpayment153(p_buyer uuid, p_seller uuid, p_total int, p_pi text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
    VALUES (tap._newlisting153(p_seller), p_buyer, p_seller, (p_total * 9) / 10, p_total - (p_total * 9) / 10, p_total, 'succeeded', 'buy_now', p_pi)
    RETURNING id $m$;
-- two extra personas: the transfer recipient (a plain fan) and a platform_risk operator
CREATE FUNCTION tap.fan153()  RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '55555555-5555-5555-5555-555555555555'::uuid $$;
CREATE FUNCTION tap.risk153() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '66666666-6666-6666-6666-666666666666'::uuid $$;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (tap.fan153(),  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan153@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.risk153(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'risk153@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.risk153(), 'platform_risk', tap.admin_user());

-- ============================================================================
-- SECTION A — THE 088 CLOSED WORLD (parity: EXTRA = 0, MISSING = 0)
-- ============================================================================
SELECT has_table('market'::name,'listing_native'::name, 'A1: market.listing_native');
SELECT has_table('market'::name,'auction'::name, 'A2: market.auction (dormant substrate, OR-11)');
SELECT has_table('market'::name,'offer'::name, 'A3: market.offer');
SELECT has_table('market'::name,'market_sale'::name, 'A4: market.market_sale (C26 terminal SM)');
SELECT has_table('market'::name,'p2p_transfer'::name, 'A5: market.p2p_transfer');
SELECT has_table('kernel'::name,'dispute_native'::name, 'A6: kernel.dispute_native (R-40)');
SELECT is((SELECT string_agg(p.proname, ',' ORDER BY p.proname COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market'),
  'accept_p2p_transfer,bind_checkout_payment_ref,cancel_buy_now_sale,cancel_listing,cancel_p2p_transfer,checkout_buy_now,create_auction,create_listing,'
  || 'create_p2p_transfer,door_freeze_drain_preview,finalize_market_sale,get_market_sale_status,get_ticket_history,list_lapsed_checkouts,make_offer,'
  || 'mark_sale_paid_state,on_atom_voided,on_door_freeze_engaged,place_bid,respond_offer,sweep_expired_p2p_transfers,sweep_paid_pending_sales',
  'A7: market holds EXACTLY the twenty-two contracted routines (19 verbs/reads/sweeps + 3 SEAM-2 hooks)');
SELECT has_function('kernel'::name,'transfer_ticket_ownership'::name, ARRAY['uuid','uuid','text','uuid','uuid','text']::name[], 'A8: the transfer engine (RPC §7.2; SSCAS #2)');
SELECT has_function('kernel'::name,'record_dispute_native'::name, ARRAY['text','text','text','integer','text','text','text','timestamptz','text']::name[], 'A9: record_dispute_native (9 params, §20.7.13)');
SELECT has_function('kernel'::name,'mark_dispute_state'::name, ARRAY['text','text','text']::name[], 'A10: mark_dispute_state (§20.7.14)');
SELECT has_function('kernel'::name,'resolve_dispute_native'::name, ARRAY['uuid','text','text','text']::name[], 'A11: resolve_dispute_native (§20.7.15; PFA-31 parked)');
SELECT has_function('catalog'::name,'cancel_event'::name, ARRAY['uuid','text','text']::name[], 'A12: catalog.cancel_event (§4.4; FR-2b)');
SELECT has_function('market'::name,'accept_p2p_transfer'::name, ARRAY['uuid','text','text']::name[], 'A13: accept_p2p_transfer carries the DEFAULTED p_decision third parameter (E-99)');
SELECT ok((SELECT p.pronargdefaults = 1 AND p.proargnames = ARRAY['p_transfer_id','p_command_key','p_decision'] FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='accept_p2p_transfer'),
  'A14: …exactly one default, so the two-argument §8.2 shape stays callable');
-- SEAM-2a: the seven body-only replacements keep their frozen signatures
SELECT ok((SELECT p.proargnames = ARRAY['p_settlement_id'] AND p.proretset AND p.prorettype = 'kernel.settlement_line_candidate'::regtype AND p.provolatile = 'v'
             AND p.prosrc LIKE '%pg_advisory_xact_lock%'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'A15: settlement_royalty_lines — signature frozen from 087 (p_settlement_id → SETOF candidate); VOLATILE + per-org xact advisory lock (E-104: race-safe dedupe)');
SELECT ok((SELECT count(*)=1 FROM pg_indexes WHERE schemaname='market' AND indexname='market_sale_payment_uq' AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%payment_id IS NOT NULL%'),
  'A15a: E-105 — one succeeded payment settles ONE sale (partial UNIQUE on market_sale.payment_id)');
SELECT ok((SELECT p.proargnames = ARRAY['p_atom_id','p_refund_id','p_cause'] AND p.prorettype = 'void'::regtype
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='on_atom_voided'),
  'A16: on_atom_voided — signature frozen from 085');
SELECT ok((SELECT p.proargnames = ARRAY['p_event_session_id','p_cause_ref','drained_transfers','drained_listings','atoms_unlocked']
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='on_door_freeze_engaged'),
  'A17: on_door_freeze_engaged — signature + OUT columns frozen from 086');
SELECT ok((SELECT p.proargnames = ARRAY['p_event_session_id','pending_transfers','active_listings','excluded_paid_pending','atoms_to_unlock']
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='door_freeze_drain_preview'),
  'A18: door_freeze_drain_preview — signature + OUT columns frozen from 086');
SELECT ok((SELECT p.proargnames = ARRAY['p_identity'] AND p.prorettype = 'text'::regtype
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='deletion_blockers_market'),
  'A19: deletion_blockers_market — signature frozen from 077');
SELECT ok((SELECT p.proargnames = ARRAY['p_identity'] AND p.prorettype = 'void'::regtype
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_market'),
  'A20: on_identity_erased_market — signature frozen from 077');
SELECT ok((SELECT p.proargnames = ARRAY['p_atom_id','p_command_key'] AND p.prorettype = 'jsonb'::regtype
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='unlock_ticket'),
  'A21: unlock_ticket — signature frozen from 079 (PFA-13 body-only)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE (n.nspname,p.proname) IN (('kernel','settlement_royalty_lines'),('market','on_atom_voided'),('market','on_door_freeze_engaged'),
                    ('market','door_freeze_drain_preview'),('kernel','deletion_blockers_market'),('kernel','on_identity_erased_market'),
                    ('kernel','unlock_ticket'),('market','accept_p2p_transfer'))), 8,
  'A22: exactly ONE overload of each replaced/defaulted routine (SEAM-2a; no accidental second signature)');
-- ODR-16 SEAM state: exactly the six owed hooks became REAL; the others stay byte-neutral
SELECT ok((SELECT p.prosrc LIKE '%chargeback%' AND p.prosrc LIKE '%venue_royalty_minor%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'A23: ODR-16 — settlement_royalty_lines is REAL (royalty + chargeback arms; PFA-29 O-C)');
SELECT ok((SELECT btrim(p.prosrc) <> 'select' AND p.prosrc LIKE '%compensated%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='on_atom_voided'),
  'A24: ODR-16 — on_atom_voided is REAL (C26 compensate arm)');
SELECT ok((SELECT btrim(p.prosrc) <> 'select 0, 0, 0' AND p.prosrc LIKE '%door_freeze%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='on_door_freeze_engaged'),
  'A25: ODR-16 — on_door_freeze_engaged is REAL (the drain)');
SELECT ok((SELECT btrim(p.prosrc) <> 'select 0, 0, 0, 0' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='door_freeze_drain_preview'),
  'A26: ODR-16 — door_freeze_drain_preview is REAL');
SELECT ok((SELECT btrim(p.prosrc) <> 'select null::text' AND p.prosrc LIKE '%BP-3%' AND p.prosrc LIKE '%BP-7%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='deletion_blockers_market'),
  'A27: ODR-16 — deletion_blockers_market is REAL (BP-3/BP-4/BP-7/BP-8 twins)');
SELECT ok((SELECT btrim(p.prosrc) <> 'select' AND p.prosrc LIKE '%delete from market.listing_native%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_market'),
  'A28: ODR-16 — on_identity_erased_market is REAL (16d allowance only)');
SELECT ok((SELECT p.prosrc LIKE '%dispute_hold%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='unlock_ticket'),
  'A29: PFA-13 — unlock_ticket carries the R-40 re-arm');
-- 2026-09-02 (package 090): both 090 seams are now REAL (the flip this assertion was written to catch).
SELECT ok((SELECT p.prosrc NOT LIKE '%where false%' AND p.prosrc LIKE '%pay_promoter_commission%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_commission_lines')
       AND (SELECT btrim(p.prosrc) <> 'select' AND p.prosrc LIKE '%status_changed_by%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_promoter'),
  'A30: ODR-16 — the 090 seams are REAL (commission_lines → pay_promoter_commission; on_identity_erased_promoter INV #36 SET NULL)');
SELECT ok((SELECT p.prosrc LIKE '%cause%settlement%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='on_payout_settled'),
  'A31: ODR-16 — 087''s on_payout_settled body is untouched by 088');
-- CHECK sets (E-92 verified, never re-added)
SELECT ok((SELECT pg_get_constraintdef(c.oid) LIKE '%dispute_hold%' FROM pg_constraint c WHERE c.conrelid='kernel.tickets'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) LIKE '%resale_state%')
       AND (SELECT pg_get_constraintdef(c.oid) LIKE '%dispute_hold%' FROM pg_constraint c WHERE c.conrelid='venue.door_manifest_entry'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) LIKE '%resale_state%'),
  'A32: E-92 — both resale_state CHECKs carry dispute_hold (079/086 bytes; 088 verified, not re-added)');
SELECT ok((SELECT pg_get_constraintdef(c.oid) LIKE '%warning_needs_response%' AND pg_get_constraintdef(c.oid) LIKE '%charge_refunded%'
             FROM pg_constraint c WHERE c.conrelid='kernel.dispute_native'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) LIKE '%status%' AND pg_get_constraintdef(c.oid) LIKE '%won%'),
  'A33: dispute_native.status is the eight-label Stripe set');
SELECT ok((SELECT count(*) = 2 FROM pg_constraint c WHERE c.conrelid='market.market_sale'::regclass AND c.conname IN ('market_sale_split_ck','market_sale_cancelled_ck')),
  'A34: market_sale carries the exact-sum split CHECK and the cancelled-is-never-paid CHECK');
SELECT ok((SELECT count(*) = 3 FROM pg_indexes WHERE schemaname='market' AND indexname IN ('listing_native_atom_active_uq','market_sale_listing_initiated_uq','p2p_transfer_atom_initiated_uq')),
  'A35: the three partial UNIQUE indexes (one active listing per atom; one initiated sale per listing; one initiated transfer per atom)');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname IN ('market-sweep-expired-p2p-transfers','market-sweep-paid-pending-sales')), 2,
  'A36: two 088 cron rows (the pure-DB sweeps, 2-minute cadence)');
SELECT is((SELECT count(*)::int FROM cron.job WHERE command LIKE '%resale-checkout%'), 0,
  'A37: NO resale-checkout /sweep-lapsed pg_net tick is armed (RESALE_CHECKOUT_SWEEP_TICK — no Vault name in any byte)');
SELECT ok(NOT has_table_privilege('service_role','kernel.dispute_native','DELETE'), 'A38: dispute_native — DELETE revoked even from service_role (GP-2: no DELETE ever)');
SELECT ok((SELECT c.confdeltype = 'r' FROM pg_constraint c WHERE c.conrelid='kernel.dispute_native'::regclass AND c.contype='f'
            AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='kernel.dispute_native'::regclass AND attname='resolved_by')]),
  'A39: E-93 — dispute_native.resolved_by is ON DELETE RESTRICT (TOMBSTONED identity FK)');

-- ============================================================================
-- SECTION B — GRANTS / RLS (RLS §11 · §16.10 · PFA-1)
-- ============================================================================
SELECT is((SELECT string_agg(p.proname, ',' ORDER BY p.proname COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='market' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'accept_p2p_transfer,cancel_listing,cancel_p2p_transfer,checkout_buy_now,create_auction,create_listing,create_p2p_transfer,get_market_sale_status,get_ticket_history,make_offer,place_bid,respond_offer',
  'B1: market authenticated EXECUTE = exactly the twelve caller-authorized verbs/reads');
SELECT is((SELECT string_agg(p.proname, ',' ORDER BY p.proname COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='market' AND has_function_privilege('service_role', p.oid, 'EXECUTE')),
  'bind_checkout_payment_ref,cancel_buy_now_sale,cancel_p2p_transfer,finalize_market_sale,list_lapsed_checkouts,mark_sale_paid_state,sweep_expired_p2p_transfers,sweep_paid_pending_sales',
  'B2: market service_role EXECUTE = exactly the eight EXEC-DEF verbs (cancel_p2p_transfer is dual: sender AND the sweep)');
SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE') AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE'))
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE (n.nspname,p.proname) IN (('market','on_atom_voided'),('market','on_door_freeze_engaged'),('market','door_freeze_drain_preview'),
                    ('kernel','settlement_royalty_lines'),('kernel','unlock_ticket'))),
  'B3: the three market hooks, the royalty seam and unlock_ticket are definer-internal — no client or machine grant');
SELECT ok(has_function_privilege('service_role','kernel.transfer_ticket_ownership(uuid,uuid,text,uuid,uuid,text)','EXECUTE')
       AND NOT has_function_privilege('authenticated','kernel.transfer_ticket_ownership(uuid,uuid,text,uuid,uuid,text)','EXECUTE'),
  'B4: the engine is service_role-only (reached by the market definers by ownership)');
SELECT ok(has_function_privilege('service_role','kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text)','EXECUTE')
       AND has_function_privilege('service_role','kernel.mark_dispute_state(text,text,text)','EXECUTE')
       AND NOT has_function_privilege('authenticated','kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text)','EXECUTE')
       AND NOT has_function_privilege('authenticated','kernel.mark_dispute_state(text,text,text)','EXECUTE'),
  'B5: record/mark dispute are service_role-only (the stripe-webhook native branch)');
SELECT ok(has_function_privilege('authenticated','kernel.resolve_dispute_native(uuid,text,text,text)','EXECUTE')
       AND NOT has_function_privilege('service_role','kernel.resolve_dispute_native(uuid,text,text,text)','EXECUTE')
       AND has_function_privilege('authenticated','catalog.cancel_event(uuid,text,text)','EXECUTE')
       AND NOT has_function_privilege('service_role','catalog.cancel_event(uuid,text,text)','EXECUTE'),
  'B6: resolve_dispute_native and cancel_event are authenticated-only (in-body authz), never service_role');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE a.privilege_type='EXECUTE' AND (n.nspname='market' OR (n.nspname='kernel' AND p.proname IN ('transfer_ticket_ownership','record_dispute_native','mark_dispute_state','resolve_dispute_native','unlock_ticket','deletion_blockers_market','on_identity_erased_market','settlement_royalty_lines')) OR (n.nspname='catalog' AND p.proname='cancel_event'))
              AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname='anon'))), 0,
  'B7: PFA-1 sweep — zero PUBLIC/anon EXECUTE on any of the 088 routines');
SELECT ok(NOT has_table_privilege('authenticated','market.market_sale','SELECT') AND NOT has_table_privilege('anon','market.market_sale','SELECT')
       AND NOT has_table_privilege('authenticated','kernel.dispute_native','SELECT') AND NOT has_table_privilege('anon','kernel.dispute_native','SELECT'),
  'B8: market_sale and dispute_native hold NO client grant (RLS §16.10 / §7.10b)');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE (schemaname='market' AND tablename='market_sale') OR (schemaname='kernel' AND tablename='dispute_native')), 0,
  'B9: …and ZERO policies (reads only via get_market_sale_status; disputes never client-readable)');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname='market'), 5, 'B10: market carries exactly five read policies');
SELECT ok((SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname='market' AND c.relkind='r') OR (n.nspname='kernel' AND c.relname='dispute_native')),
  'B11: RLS is ENABLED on all six 088 tables');
SELECT ok(NOT has_column_privilege('anon','market.listing_native','seller_id','SELECT') AND has_column_privilege('authenticated','market.listing_native','seller_id','SELECT'),
  'B12: listing_native.seller_id is NOT in anon''s column grant (authenticated reads it)');
SELECT ok(NOT has_column_privilege('anon','market.listing_native','command_idempotency_key','SELECT') AND NOT has_column_privilege('authenticated','market.listing_native','command_idempotency_key','SELECT'),
  'B13: the idempotency key is in NOBODY''s column grant');
SELECT ok(has_column_privilege('authenticated','market.offer','offer_id','SELECT') AND has_column_privilege('authenticated','market.p2p_transfer','transfer_id','SELECT')
       AND NOT has_column_privilege('authenticated','market.offer','command_idempotency_key','SELECT') AND NOT has_column_privilege('authenticated','market.p2p_transfer','command_idempotency_key','SELECT')
       AND NOT has_table_privilege('anon','market.offer','SELECT'),
  'B14: offer / p2p_transfer are COLUMN-scoped owner-policy reads for authenticated — the idempotency keys are in nobody''s grant');

-- ============================================================================
-- FIXTURE — org1 (seller = org_owner + venue_manager) → venue1 → event1 (session1)
--   + event2 (session2). other_user = org_finance (matured). Orders: order1
--   (buyer, 3 × 5000, pay1) → atoms a1,a2,a3; order3 (other_user, 1 × 5000, pay7)
--   → atom a4; event2: order2 (other_user, 1 × 5000, pay6) → atom a5 + a comp
--   mint a6. Extra succeeded payments pay2/pay4 (fan153), pay3/pay5 (other_user).
-- ============================================================================
SELECT is((SELECT (value #>> '{}') FROM catalog.platform_config WHERE key='feature.native_issuance_enabled' ORDER BY version DESC LIMIT 1), 'false',
  'DARK-1: native issuance is DARK at seed (flipped only inside this rolled-back transaction)');
SELECT is((SELECT (value #>> '{}') FROM catalog.platform_config WHERE key='feature.native_resale_enabled' ORDER BY version DESC LIMIT 1), 'false',
  'DARK-2: native resale is DARK at seed (078 seed; Gate M + 2C)');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key='retention.backup_window_days' AND value IS NOT NULL AND value <> 'null'::jsonb), 0,
  'DARK-3: retention.backup_window_days stays NULL (no 088 seed touches it)');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key ILIKE 'resale.%fee%' OR key ILIKE 'resale.%royalt%' OR key ILIKE 'resale.%split%' OR key ILIKE 'p2p.%' OR key ILIKE 'resale.%dwell%'), 0,
  'DARK-4: PFA-30 / PFA-9 — no split, royalty, p2p-TTL or dwell key was invented (the corpus names none)');

SELECT tap.login(tap.seller());
SELECT tap._store153('org1', (kernel.create_organization('Rail Co','Rail Co','ck88-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u153('org1');
SELECT tap.login(tap.seller());
SELECT tap._store153('venue1', (catalog.create_venue(tap._u153('org1'),'Rail Hall','wynwood',NULL,'ck88-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._u153('venue1'),'approved','miami_gate','ck88-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store153('event1', (catalog.create_event(tap._u153('venue1'),'Rail Night',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck88-e1') ->> 'event_id'));
SELECT tap._store153('session1', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u153('event1')));
SELECT tap._store153('tt1', (venue.create_ticket_type(tap._u153('event1'),'admission','GA',5000,'public','ck88-tt1') ->> 'ticket_type_id'));
SELECT tap._store153('batch1', (venue.create_inventory_batch(tap._u153('tt1'), tap._u153('session1'), 'public_sale', 100, 0, 'ck88-b1') ->> 'batch_id'));
SELECT tap._store153('event2', (catalog.create_event(tap._u153('venue1'),'Rail Night II',
  jsonb_build_object('starts_at',(now()+interval '12 days')::text,'ends_at',(now()+interval '12 days 4 hours')::text),'ck88-e2') ->> 'event_id'));
SELECT tap._store153('session2', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u153('event2')));
SELECT tap._store153('tt2', (venue.create_ticket_type(tap._u153('event2'),'admission','GA',5000,'public','ck88-tt2') ->> 'ticket_type_id'));
SELECT tap._store153('batch2', (venue.create_inventory_batch(tap._u153('tt2'), tap._u153('session2'), 'public_sale', 100, 0, 'ck88-b2') ->> 'batch_id'));
SELECT tap._store153('batch2c', (venue.create_inventory_batch(tap._u153('tt2'), tap._u153('session2'), 'comp', 10, 0, 'ck88-b2c') ->> 'batch_id'));
SELECT tap.logout();
-- roles + maturity
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._u153('org1'), tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id = tap._u153('org1') AND identity_id = tap.seller();
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._u153('venue1'), tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap._cfg153('authn.money_role_maturity_hours', '24'::jsonb);
-- signing keys
WITH k1 AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._u153('event1'), 'PUBKEY-88-1', 'kms-88-1', 'active', now()) RETURNING key_id)
SELECT tap._store153('key1', (SELECT key_id::text FROM k1));
WITH k2 AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._u153('event2'), 'PUBKEY-88-2', 'kms-88-2', 'active', now()) RETURNING key_id)
SELECT tap._store153('key2', (SELECT key_id::text FROM k2));
-- order1: buyer, 3 × 5000 on batch1
WITH o AS (INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), tap._u153('session1'), tap._u153('org1'), 'pending', 'web', 15000, 'ck88-ord-1') RETURNING order_id)
SELECT tap._store153('order1', (SELECT order_id::text FROM o));
WITH i AS (INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) VALUES (tap._u153('order1'), tap._u153('tt1'), 3, 5000) RETURNING id)
SELECT tap._store153('item1', (SELECT id::text FROM i));
INSERT INTO venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
VALUES (tap._u153('batch1'), tap.buyer(), 3, 'active', now() + interval '1 hour', 'ck88-h-1');
-- order3: other_user, 1 × 5000 on batch1
WITH o AS (INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.other_user(), tap._u153('session1'), tap._u153('org1'), 'pending', 'web', 5000, 'ck88-ord-3') RETURNING order_id)
SELECT tap._store153('order3', (SELECT order_id::text FROM o));
WITH i AS (INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) VALUES (tap._u153('order3'), tap._u153('tt1'), 1, 5000) RETURNING id)
SELECT tap._store153('item3', (SELECT id::text FROM i));
INSERT INTO venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
VALUES (tap._u153('batch1'), tap.other_user(), 1, 'active', now() + interval '1 hour', 'ck88-h-3');
UPDATE venue.inventory_batch SET held = 4 WHERE batch_id = tap._u153('batch1');
-- order2: other_user, 1 × 5000 on batch2 (event2)
WITH o AS (INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.other_user(), tap._u153('session2'), tap._u153('org1'), 'pending', 'web', 5000, 'ck88-ord-2') RETURNING order_id)
SELECT tap._store153('order2', (SELECT order_id::text FROM o));
WITH i AS (INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) VALUES (tap._u153('order2'), tap._u153('tt2'), 1, 5000) RETURNING id)
SELECT tap._store153('item2', (SELECT id::text FROM i));
INSERT INTO venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
VALUES (tap._u153('batch2'), tap.other_user(), 1, 'active', now() + interval '1 hour', 'ck88-h-2');
UPDATE venue.inventory_batch SET held = 1 WHERE batch_id = tap._u153('batch2');
-- the frozen public rail: succeeded payments (one listing each)
SELECT tap._store153('pay1', tap._newpayment153(tap.buyer(),      tap.seller(), 15000, 'pi_88_1')::text);
SELECT tap._store153('pay2', tap._newpayment153(tap.fan153(),     tap.buyer(),   5000, 'pi_88_2')::text);
SELECT tap._store153('pay3', tap._newpayment153(tap.other_user(), tap.buyer(),   5000, 'pi_88_3')::text);
SELECT tap._store153('pay4', tap._newpayment153(tap.fan153(),     tap.buyer(),   5000, 'pi_88_4')::text);
SELECT tap._store153('pay5', tap._newpayment153(tap.other_user(), tap.seller(),  5000, 'pi_88_5')::text);
SELECT tap._store153('pay6', tap._newpayment153(tap.other_user(), tap.seller(),  5000, 'pi_88_6')::text);
SELECT tap._store153('pay7', tap._newpayment153(tap.other_user(), tap.seller(),  5000, 'pi_88_7')::text);
-- mint through the money path (issuance flag ON inside the txn only)
SELECT tap._cfg153('feature.native_issuance_enabled', 'true'::jsonb);
SELECT is((venue.finalize_primary_order(tap._u153('order1'), tap._u153('pay1'), 'ck88-f1', NULL) ->> 'status'), 'ok', 'FIX-1: order1 finalized (3 atoms minted to buyer)');
SELECT is((venue.finalize_primary_order(tap._u153('order3'), tap._u153('pay7'), 'ck88-f3', NULL) ->> 'status'), 'ok', 'FIX-2: order3 finalized (1 atom minted to other_user)');
SELECT is((venue.finalize_primary_order(tap._u153('order2'), tap._u153('pay6'), 'ck88-f2', NULL) ->> 'status'), 'ok', 'FIX-3: order2 finalized (1 atom minted to other_user on event2)');
SELECT tap._store153('a1', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u153('session1') AND current_owner_id=tap.buyer() ORDER BY ticket_atom_id LIMIT 1));
SELECT tap._store153('a2', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u153('session1') AND current_owner_id=tap.buyer() ORDER BY ticket_atom_id OFFSET 1 LIMIT 1));
SELECT tap._store153('a3', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u153('session1') AND current_owner_id=tap.buyer() ORDER BY ticket_atom_id OFFSET 2 LIMIT 1));
SELECT tap._store153('a4', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u153('session1') AND current_owner_id=tap.other_user()));
SELECT tap._store153('a5', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u153('session2') AND current_owner_id=tap.other_user()));
SELECT is((kernel.issue_ticket_atoms(jsonb_build_object('session_id',tap._u153('session2'),'org_id',tap._u153('org1'),'ticket_type_id',tap._u153('tt2'),
  'batch_id',tap._u153('batch2c'),'owner_id',tap.buyer(),'quantity',1,'cause','comp','cause_ref',gen_random_uuid(),'signing_key_id',tap._u153('key2')),'ck88-comp') ->> 'status'), 'ok',
  'FIX-4: a comp atom minted on event2 (no order lineage — E-102 operand)');
SELECT tap._store153('a6', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u153('session2') AND current_owner_id=tap.buyer()));
SELECT ok(tap._u153('a1') IS NOT NULL AND tap._u153('a2') IS NOT NULL AND tap._u153('a3') IS NOT NULL AND tap._u153('a4') IS NOT NULL AND tap._u153('a5') IS NOT NULL AND tap._u153('a6') IS NOT NULL,
  'FIX-5: six atoms resolved (a1-a3 buyer/session1, a4 other_user/session1, a5 other_user/session2, a6 comp/session2)');
SELECT ok((SELECT bool_and(t.state='active' AND t.resale_state='none' AND t.credential_version=0) FROM kernel.tickets t WHERE t.ticket_atom_id IN (tap._u153('a1'),tap._u153('a2'),tap._u153('a3'),tap._u153('a4'))),
  'FIX-6: every minted atom is active / resale none / credential_version 0');

-- ============================================================================
-- SECTION C — DARK RAILS (before the resale flag flips)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-dark-1')$$, tap._u153('a1')), NULL, 'precondition_failed: feature_disabled',
  'C1: create_listing is feature_disabled while native resale is DARK (X-12: NULL/false ⇒ dark)');
SELECT throws_ok($$SELECT market.checkout_buy_now(gen_random_uuid(), 'ck88-dark-2')$$, NULL, 'precondition_failed: feature_disabled',
  'C2: checkout_buy_now is feature_disabled while DARK (the ① check precedes existence)');
SELECT throws_ok($$SELECT market.make_offer(gen_random_uuid(), 100, now()+interval '1 hour', 'ck88-dark-3')$$, NULL, 'precondition_failed: feature_disabled',
  'C3: make_offer is feature_disabled while DARK');
SELECT throws_ok($$SELECT market.place_bid(gen_random_uuid(), 100, 'ck88-dark-4')$$, NULL, 'precondition_failed: native_auction_not_offered',
  'C4: place_bid — native auctions are NOT offered (OR-11)');
SELECT tap.logout();
-- a directly-seeded ACTIVE listing is invisible to the public arm while the flag is off; the owner arm sees it
WITH rp AS (INSERT INTO catalog.resale_policy (scope_kind, venue_id, mode, price_cap_bps, version) VALUES ('venue', tap._u153('venue1'), 'off', NULL, 1) RETURNING policy_id)
INSERT INTO market.listing_native (listing_id, ticket_atom_id, seller_id, event_session_id, listing_mode, price_minor, resale_policy_id, resale_policy_version, status, command_idempotency_key)
SELECT '00000000-0000-0000-0000-00000000c001', tap._u153('a1'), tap.buyer(), tap._u153('session1'), 'buy_now', 5000, rp.policy_id, 1, 'active', 'ck88-seed-c' FROM rp;
SELECT ok(NOT has_schema_privilege('anon','market','USAGE') AND NOT has_table_privilege('anon','market.listing_native','SELECT'),
  'C5: anon holds NO USAGE on market and no listing grant — the 076 wall; anonymous discovery is not 088''s to open');
SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*)::int FROM market.listing_native), 0, 'C6: another authenticated fan sees ZERO listings while DARK');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM market.listing_native), 1, 'C7: the OWNER arm is unconditional — the seller sees their own listing');
SELECT throws_ok($$SELECT market.create_auction('00000000-0000-0000-0000-00000000c001', NULL, 100, 0, now()+interval '1 day', 'ck88-dark-5')$$, NULL, 'precondition_failed: native_auction_not_offered',
  'C8: create_auction refuses every native listing (OR-11) — after the seller check, zero mutation');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM market.auction), 0, 'C9: …no auction row exists');
DELETE FROM market.listing_native WHERE listing_id = '00000000-0000-0000-0000-00000000c001';
SELECT is((market.sweep_paid_pending_sales() ->> 'status'), 'inert', 'C10: sweep_paid_pending_sales is INERT — the dwell SLO is unnamed (PAID_PENDING_DWELL_SLO)');
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.resolve_dispute_native(gen_random_uuid(), 'buyer_win', 'x', 'ck88-dark-6')$$, '42501', NULL,
  'C11: a fan cannot reach resolve_dispute_native (authority is checked before the park)');
SELECT tap.logout();

-- ============================================================================
-- SECTION D — LISTING LIFECYCLE (flag ON; event policy buy_now, cap 100% of face)
-- ============================================================================
SELECT tap._cfg153('feature.native_resale_enabled', 'true'::jsonb, 'public');
SELECT tap.login(tap.seller());
SELECT tap._store153('pol1', (catalog.set_resale_policy('event', tap._u153('event1'), '{"mode":"buy_now","price_cap_bps":10000}'::jsonb, 'ck88-pol1') ->> 'policy_id'));
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-l-x1')$$, tap._u153('a1')), '42501', NULL,
  'D1: T-RPC-MARKET-01 — a non-owner cannot list');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-l-x2')$$, tap._u153('a1')), '42501', NULL,
  'D2: T-RPC-MARKET-01 — the issuing venue_manager / org_owner cannot list a fan''s atom');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.create_listing(%L, 5001, 'buy_now', 'ck88-l-x3')$$, tap._u153('a1')), '%policy_violation%exceeds cap 5000%',
  'D3: E-98 — price 5001 exceeds the cap floor(5000 × 10000 / 10000) = 5000 (integer minor units)');
SELECT throws_ok(format($$SELECT market.create_listing(%L, 5000, 'auction', 'ck88-l-x4')$$, tap._u153('a1')), NULL, 'precondition_failed: native_auction_not_offered',
  'D4: listing_mode auction is refused at creation (OR-11)');
SELECT throws_like(format($$SELECT market.create_listing(%L, 5000, 'bogus', 'ck88-l-x5')$$, tap._u153('a1')), '%invalid_input%', 'D5: an unknown listing_mode is invalid_input');
SELECT tap._store153('l1', (market.create_listing(tap._u153('a1'), 5000, 'buy_now', 'ck88-l1') ->> 'listing_id'));
SELECT ok(tap._u153('l1') IS NOT NULL, 'D6: the owner lists at face — listing created');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*)::int FROM market.listing_native WHERE listing_id = tap._u153('l1')), 1, 'D6a: the PUBLIC arm surfaces the active listing to another fan while the flag is ON (plan §8/088 Tests)');
SELECT is((SELECT count(*)::int FROM market.listing_native WHERE listing_id = tap._u153('l1') AND seller_id IS NOT NULL), 1, 'D6b: …with seller_id readable (display resolves via 068 profile columns)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((market.create_listing(tap._u153('a1'), 5000, 'buy_now', 'ck88-l1') ->> 'status'), 'noop_replay', 'D7: C16 — the same command key replays the original listing');
SELECT throws_like(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-l1b')$$, tap._u153('a1')), '%conflict_locked%',
  'D8: double-listing the same atom raises conflict_locked (partial UNIQUE + lock_ticket)');
SELECT tap.logout();
SELECT ok((SELECT l.status='active' AND l.listing_mode='buy_now' AND l.price_minor=5000 AND l.resale_policy_id=tap._u153('pol1') AND l.resale_policy_version=1 AND l.seller_id=tap.buyer()
             FROM tap._listing153(tap._u153('l1')) l), 'D9: the listing is active and SNAPSHOTS the governing policy (id + version 1; O3/C11)');
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'listed', 'D10: the atom overlay is listed (SSCAS #6: Listing INSERT → lock_ticket)');
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT market.make_offer(%L, 5001, now()+interval '1 hour', 'ck88-o-x1')$$, tap._u153('l1')), '%above_cap%',
  'D11: §20.8.5 — an offer above the listing''s SNAPSHOT cap is policy_violation(above_cap)');
SELECT is((market.make_offer(tap._u153('l1'), 4000, now()+interval '1 hour', 'ck88-o-bn') ->> 'status'), 'ok', 'D11a: an offer on a buy_now listing is contracted (listing_mode ∈ {buy_now, offer})');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.cancel_listing(%L, 'door_freeze', 'ck88-c-rsv')$$, tap._u153('l1')), '%system reason%', 'D11b: a client may not write a SYSTEM reason (door_freeze / event_cancelled)');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT market.cancel_listing(%L, 'x', 'ck88-c-x1')$$, tap._u153('l1')), '42501', NULL, 'D12: a non-seller, non-platform actor cannot cancel a listing');
SELECT tap.logout();
SELECT tap.login(tap.risk153());
SELECT is((market.cancel_listing(tap._u153('l1'), 'fraud_review', 'ck88-c1') ->> 'final_state'), 'cancelled', 'D13: platform_risk may cancel (RPC §20.8.2 platform arm)');
SELECT is((market.cancel_listing(tap._u153('l1'), 'fraud_review', 'ck88-c1') ->> 'status'), 'noop_replay', 'D14: a re-cancel is noop_replay');
SELECT tap.logout();
SELECT ok((SELECT l.status='cancelled' AND l.reason_code='fraud_review' FROM tap._listing153(tap._u153('l1')) l), 'D15: cancelled with the reason recorded');
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'none', 'D16: the atom overlay is released (unlock_ticket; no dispute ⇒ none)');
SELECT is(tap._audit153(tap._u153('l1'), 'listing.cancel', 'fraud_review'), 1, 'D17: the platform arm writes a listing.cancel audit row (the seller arm does not)');
SELECT is((SELECT status FROM market.offer WHERE command_idempotency_key = 'ck88-o-bn'), 'withdrawn', 'D17a: the cancel withdrew the pending buy-now offer');
-- get_ticket_history (§1.2): current owner only; plain verbs; no PII columns
SELECT tap.login(tap.buyer());
SELECT is((SELECT string_agg(h.verb, ',' ORDER BY h.sequence) FROM market.get_ticket_history(tap._u153('a1')) h), 'bought',
  'D18: the owner''s history is plain verbs (the mint reads as "bought")');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT * FROM market.get_ticket_history(%L)$$, tap._u153('a1')), '42501', NULL, 'D19: a non-owner cannot read the history');
SELECT tap.logout();
SELECT is((SELECT string_agg(a, ',' ORDER BY a) FROM unnest((SELECT p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='get_ticket_history')) a WHERE a <> 'p_ticket_atom_id'),
  'occurred_at,sequence,verb', 'D20: the history exposes ONLY (sequence, verb, occurred_at) — no cause-codes, keys, versions or counterpart ids');

-- ============================================================================
-- SECTION E — BUY NOW: PFA-30 FAIL-CLOSED PARK (owner tests G/H)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT tap._store153('l2', (market.create_listing(tap._u153('a1'), 5000, 'buy_now', 'ck88-l2') ->> 'listing_id'));
SELECT throws_like(format($$SELECT market.checkout_buy_now(%L, 'ck88-cb-self')$$, tap._u153('l2')), '%self_purchase%', 'E1: ④ the seller cannot buy their own listing');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT market.checkout_buy_now(%L, 'ck88-cb-1')$$, tap._u153('l2')), '%resale_split_unavailable%',
  'E2: OWNER TEST G — a valid buy-now checkout FAILS CLOSED at ⑦: resale_split_unavailable (PFA-30)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM market.market_sale), 0, 'E3: OWNER TEST H — ZERO market_sale rows: no guessed split, no partial row, no reservation');
SELECT is((tap._listing153(tap._u153('l2'))).status, 'active', 'E4: the listing is still active (never reserved)');
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'listed', 'E5: the atom is still listed (custody untouched)');
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l2');
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-l2-dup')$$, tap._u153('a1')), '%conflict_locked%',
  'E5a: a RESERVED listing (checkout in flight) blocks a second listing on the atom — one listing at a time, active|reserved');
SELECT tap.logout();
SELECT throws_ok(format($$INSERT INTO market.listing_native (ticket_atom_id, seller_id, event_session_id, listing_mode, price_minor, resale_policy_id, resale_policy_version, status, command_idempotency_key)
  VALUES (%L, %L, %L, 'buy_now', 5000, %L, 1, 'active', 'ck88-l2-dup2')$$, tap._u153('a1'), tap.buyer(), tap._u153('session1'), tap._u153('pol1')), '23505', NULL,
  'E5b: …structurally (the partial UNIQUE spans active AND reserved)');
UPDATE market.listing_native SET status='active' WHERE listing_id = tap._u153('l2');
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.other_user(), 'DELETION_PENDING') ON CONFLICT (identity_id) DO UPDATE SET deletion_state='DELETION_PENDING';
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT market.checkout_buy_now(%L, 'ck88-cb-2')$$, tap._u153('l2')), NULL, 'precondition_failed: deletion_pending',
  'E6: OR-17 F-2 rider — a DELETION_PENDING caller is refused before ① (no acquisition)');
SELECT tap.logout();
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.other_user();
SELECT throws_ok($$SELECT market.bind_checkout_payment_ref(gen_random_uuid(), 'pi_x', 'ck88-b-x')$$, 'P0002', NULL, 'E7: bind on an unknown sale is not_found');
SELECT throws_ok($$SELECT market.finalize_market_sale(gen_random_uuid(), 'ck88-fz-x')$$, 'P0002', NULL, 'E8: finalize on an unknown sale is not_found');
SELECT throws_ok($$SELECT market.cancel_buy_now_sale(gen_random_uuid(), 'buyer_released', 'ck88-cx-x')$$, 'P0002', NULL, 'E9: cancel on an unknown sale is not_found');

-- ============================================================================
-- SECTION F — OFFERS + the PFA-30 park on ACCEPT
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT is((catalog.set_resale_policy('event', tap._u153('event1'), '{"mode":"offer"}'::jsonb, 'ck88-pol2') ->> 'version'), '2', 'F1: a tightening/mode change INSERTS version 2 (never mutates v1)');
SELECT tap.logout();
SELECT ok((SELECT l.resale_policy_version = 1 FROM tap._listing153(tap._u153('l2')) l), 'F2: T-RPC-CFG-05 — the live listing stays governed by its SNAPSHOT (v1)');
SELECT tap.login(tap.buyer());
SELECT tap._store153('l3', (market.create_listing(tap._u153('a2'), 5000, 'offer', 'ck88-l3') ->> 'listing_id'));
SELECT throws_like(format($$SELECT market.make_offer(%L, 4000, now()+interval '1 hour', 'ck88-o-self')$$, tap._u153('l3')), '%self_offer%', 'F3: the seller cannot offer on their own listing');
SELECT tap.logout();
SELECT ok((SELECT l.resale_policy_version = 2 AND l.listing_mode = 'offer' FROM tap._listing153(tap._u153('l3')) l), 'F4: a new listing snapshots the CURRENT policy (v2, offer)');
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT market.make_offer(%L, 4000, now()-interval '1 minute', 'ck88-o-past')$$, tap._u153('l3')), '%invalid_input%future%',
  'F5: PFA-9 — the expiry is caller-supplied and must be future (no TTL is invented)');
SELECT tap._store153('o1', (market.make_offer(tap._u153('l3'), 4000, now()+interval '1 hour', 'ck88-o1') ->> 'offer_id'));
SELECT tap._store153('o2r', market.make_offer(tap._u153('l3'), 4500, now()+interval '1 hour', 'ck88-o2')::text);
SELECT is((tap._fetch153('o2r')::jsonb ->> 'replaced_offer_id'), tap._fetch153('o1'), 'F6: S-12 — a second offer REPLACES the buyer''s prior pending offer');
SELECT tap._store153('o2', (tap._fetch153('o2r')::jsonb ->> 'offer_id'));
SELECT throws_ok(format($$SELECT market.respond_offer(%L, 'accept', NULL, 'ck88-r-x')$$, tap._u153('o2')), '42501', NULL, 'F7: only the listing seller responds');
SELECT tap.logout();
SELECT ok((SELECT status='withdrawn' FROM market.offer WHERE offer_id = tap._u153('o1')) AND (SELECT status='pending' FROM market.offer WHERE offer_id = tap._u153('o2')),
  'F8: the replaced offer is withdrawn; the new one pending');
SELECT tap.login(tap.buyer());
SELECT is((market.respond_offer(tap._u153('o2'), 'decline', NULL, 'ck88-r1') ->> 'final_state'), 'declined', 'F9: decline → declined');
SELECT is((market.respond_offer(tap._u153('o2'), 'decline', NULL, 'ck88-r1b') ->> 'status'), 'noop_replay', 'F10: a repeated decline is noop_replay');
SELECT throws_like(format($$SELECT market.respond_offer(%L, 'accept', NULL, 'ck88-r1c')$$, tap._u153('o2')), '%state_conflict%', 'F11: accepting a declined offer is a state_conflict');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._store153('o3', (market.make_offer(tap._u153('l3'), 4000, now()+interval '1 hour', 'ck88-o3') ->> 'offer_id'));
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.respond_offer(%L, 'accept', NULL, 'ck88-r2')$$, tap._u153('o3')), '%payment_unverified%', 'F12: an accept without the buyer''s payment is payment_unverified');
SELECT throws_like(format($$SELECT market.respond_offer(%L, 'accept', %L, 'ck88-r3')$$, tap._u153('o3'), tap._u153('pay2')), '%payment_unverified%',
  'F13: C35 — a payment belonging to ANOTHER identity is payment_unverified');
SELECT throws_like(format($$SELECT market.respond_offer(%L, 'accept', %L, 'ck88-r4')$$, tap._u153('o3'), tap._u153('pay3')), '%resale_split_unavailable%',
  'F14: OWNER TEST G — a fully valid ACCEPT fails closed at the split INSERT point (PFA-30)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM market.market_sale), 0, 'F15: OWNER TEST H — still ZERO sale rows');
SELECT ok((SELECT status='pending' FROM market.offer WHERE offer_id = tap._u153('o3')), 'F16: the offer stays pending (nothing terminalized)');
SELECT is((tap._atom153(tap._u153('a2'))).resale_state, 'listed', 'F17: custody untouched (atom still listed to its seller)');
-- arithmetic expiry (T-RPC-MARKET-07)
INSERT INTO market.offer (offer_id, listing_id, buyer_id, amount_minor, status, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000f001', tap._u153('l3'), tap.fan153(), 3000, 'pending', now() - interval '1 minute', 'ck88-o-exp');
SELECT tap.login(tap.buyer());
SELECT throws_like($$SELECT market.respond_offer('00000000-0000-0000-0000-00000000f001', 'accept', NULL, 'ck88-r5')$$, '%offer_expired%',
  'F18: T-RPC-MARKET-07 — expiry is ARITHMETIC (expires_at <= now()), the sweep is presentational');
SELECT tap.logout();
-- F-2: an accept of a DELETION_PENDING buyer's offer is refused; a decline stays allowed
UPDATE kernel.identity_ext SET deletion_state='DELETION_PENDING' WHERE identity_id = tap.other_user();
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.respond_offer(%L, 'accept', %L, 'ck88-r6')$$, tap._u153('o3'), tap._u153('pay3')), '%deletion_pending%',
  'F19: OR-17 F-2 — the OFFER''s buyer is DELETION_PENDING ⇒ accept refused');
SELECT tap.logout();
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.other_user();
UPDATE kernel.identity_ext SET deletion_state='DELETION_PENDING' WHERE identity_id = tap.other_user();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT market.make_offer(%L, 100, now()+interval '1 hour', 'ck88-o-dp')$$, tap._u153('l3')), NULL, 'precondition_failed: deletion_pending',
  'F20: OR-17 F-3 — a DELETION_PENDING caller cannot make an offer');
SELECT tap.logout();
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.other_user();

-- ============================================================================
-- SECTION G — THE TRANSFER ENGINE (E-22 / E-23 / R-40) + sale completion
--   The split is parked, so the consummation fact is SEEDED (the un-parked
--   world's row: NULL split, paid_pending_transfer) and completed for real.
-- ============================================================================
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l2');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, payment_id, sale_state, paid_pending_since, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a1', tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, tap._u153('pay2'), 'paid_pending_transfer', now(), 'ck88-s1');
SELECT tap._store153('s1', '00000000-0000-0000-0000-0000000000a1');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'gift', %L, NULL, 'ck88-x1')$$, tap._u153('a1'), tap.fan153(), tap._u153('s1')), '%invalid_input%transfer cause%',
  'G1: an unknown cause is invalid_input (D3 set)');
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.fan153(), 'ERASED') ON CONFLICT (identity_id) DO UPDATE SET deletion_state='ERASED';
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'market_sale', %L, %L, 'ck88-x2')$$, tap._u153('a1'), tap.fan153(), tap._u153('s1'), tap._u153('pay2')), '%erased — no acquisition%',
  'G2: E-23 — an ERASED recipient acquires NOTHING (the engine''s own check)');
UPDATE kernel.identity_ext SET deletion_state='DELETION_PENDING' WHERE identity_id = tap.fan153();
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'market_sale', %L, %L, 'ck88-x3')$$, tap._u153('a1'), tap.fan153(), tap._u153('s1'), tap._u153('pay2')), '%deletion_pending — no acquisition%',
  'G3: E-23 — a DELETION_PENDING recipient is refused by the engine independently of any caller F-clause');
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.fan153();
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'market_sale', %L, %L, 'ck88-x4')$$, tap._u153('a1'), tap.fan153(), tap._u153('s1'), tap._u153('pay3')), '%payment_unverified%',
  'G4: C35 — a payment that is not the recipient''s is payment_unverified');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'market_sale', %L, %L, 'ck88-x5')$$, tap._u153('a1'), tap.other_user(), tap._u153('s1'), tap._u153('pay3')), '%sale does not bind%',
  'G5: the sale must bind THIS atom and THIS recipient');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'p2p_transfer', %L, NULL, 'ck88-x6')$$, tap._u153('a1'), tap.fan153(), gen_random_uuid()), '%conflict_locked%',
  'G6: a p2p cause requires the locked overlay — a listed atom is conflict_locked for p2p');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log WHERE ticket_atom_id = tap._u153('a1')), 1, 'G7: every refusal left the ledger untouched (seq 1 only)');
-- the one completer body
SELECT tap._store153('fz1', market.finalize_market_sale(tap._u153('s1'), 'ck88-fz1')::text);
SELECT is((tap._fetch153('fz1')::jsonb ->> 'status'), 'ok', 'G8: finalize_market_sale completes the paid sale');
SELECT ok((SELECT t.current_owner_id = tap.fan153() AND t.credential_version = 1 AND t.resale_state = 'none' AND t.state = 'active' AND t.signing_key_id = tap._u153('key1')
             FROM tap._atom153(tap._u153('a1')) t),
  'G9: head — owner fan153, credential_version 0 → 1, resale none, signing key pinned unchanged (E-97)');
SELECT ok((SELECT l.sequence=2 AND l.from_identity=tap.buyer() AND l.to_identity=tap.fan153() AND l.cause='market_sale' AND l.cause_ref=tap._u153('s1')
                  AND l.credential_version_after=1 AND l.command_idempotency_key = 'ck88-fz1:' || tap._fetch153('a1')
                  AND l.state_transition = '{"to":"active","from":"active","resale_to":"none","resale_from":"listed"}'::jsonb
             FROM kernel.ticket_ownership_log l WHERE l.ticket_atom_id = tap._u153('a1') AND l.sequence = 2),
  'G10: ledger — seq 2 appended with cause/cause_ref/credential_version_after/key/state_transition (FR-3)');
SELECT ok((SELECT pn.sale_id = tap._u153('s1') AND pn.order_id IS NULL AND pn.instrument_fingerprint IS NULL AND pn.amount_minor = 5000
             FROM kernel.payment_native pn WHERE pn.payment_id = tap._u153('pay2')),
  'G11: R-34 — payment_native link born at transfer (sale arm, fingerprint NULL)');
SELECT ok((SELECT s.terminal_state='completed' AND s.sale_state='settled' FROM tap._sale153(tap._u153('s1')) s), 'G12: sale terminal completed / settled (C26)');
SELECT is((tap._listing153(tap._u153('l2'))).status, 'sold', 'G13: listing → sold');
SELECT is(tap._outbox153('ownership_changed', tap._u153('a1')), 1, 'G14: R2 row 1 — ownership_changed REQUIRED-emitted exactly once');
SELECT is(tap._outbox153('purchase_confirmed', tap._u153('s1')), 1, 'G15: purchase_confirmed BE-emitted');
SELECT is((market.finalize_market_sale(tap._u153('s1'), 'ck88-fz1b') ->> 'status'), 'noop_replay', 'G16: a re-finalize is noop_replay');
SELECT is((kernel.transfer_ticket_ownership(tap._u153('a1'), tap.fan153(), 'market_sale', tap._u153('s1'), tap._u153('pay2'), 'ck88-fz1c') ->> 'status'), 'noop_replay',
  'G17: the engine''s own replay arm (cause, cause_ref, atom) returns noop_replay');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log WHERE ticket_atom_id = tap._u153('a1')), 2, 'G18: no second ledger row on replay');
SELECT ok((SELECT position('for update' in lower(p.prosrc)) > 0
              AND position('for update' in lower(p.prosrc)) < position('insert into kernel.ticket_ownership_log' in lower(p.prosrc))
              AND position('insert into kernel.ticket_ownership_log' in lower(p.prosrc)) < position('update kernel.tickets' in lower(p.prosrc))
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='transfer_ticket_ownership'),
  'G19: E-22 structural — the atom row is locked FOR UPDATE before the ledger append, and the head write follows the append in the same body');
SELECT ok((SELECT p.prosrc LIKE '%is_transfer_frozen(p_atom_id)%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='transfer_ticket_ownership'),
  'G20: §12.4 — THE freeze enforcement point re-checks is_transfer_frozen under the atom lock');
-- get_market_sale_status (§1.4)
SELECT tap.login(tap.fan153());
SELECT is((SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(market.get_market_sale_status(tap._u153('s1'))) k), 'paid_pending_since,sale_state,terminal_state',
  'G21: the buyer reads EXACTLY {terminal_state, sale_state, paid_pending_since} — no cause-codes, no split, no counterpart');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((market.get_market_sale_status(tap._u153('s1')) ->> 'terminal_state'), 'completed', 'G22: the seller reads it too');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT market.get_market_sale_status(%L)$$, tap._u153('s1')), '42501', NULL, 'G23: anyone else is refused');
SELECT tap.logout();
-- the buy-now reservation machinery over a seeded INITIATED sale (R-37/OR-22)
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l3');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, reservation_expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a2', tap._u153('l3'), tap._u153('a2'), tap.fan153(), tap.buyer(), 5000, 'initiated', now() - interval '1 minute', 'ck88-s2');
SELECT tap._store153('s2', '00000000-0000-0000-0000-0000000000a2');
SELECT is((market.bind_checkout_payment_ref(tap._u153('s2'), 'pi_88_res', 'ck88-bind1') ->> 'status'), 'ok', 'G24: bind_checkout_payment_ref binds the PI ref');
SELECT is((market.bind_checkout_payment_ref(tap._u153('s2'), 'pi_88_res', 'ck88-bind2') ->> 'status'), 'noop_replay', 'G25: the same ref replays');
SELECT throws_like(format($$SELECT market.bind_checkout_payment_ref(%L, 'pi_88_other', 'ck88-bind3')$$, tap._u153('s2')), '%conflict_locked%', 'G26: a DIFFERENT ref is conflict_locked (write-once, §20.8.9)');
SELECT is((SELECT count(*)::int FROM market.list_lapsed_checkouts(10) x WHERE x.sale_id = tap._u153('s2') AND x.payment_intent_ref = 'pi_88_res'), 1,
  'G27: list_lapsed_checkouts surfaces the lapsed reservation with its ref');
SELECT throws_like(format($$SELECT market.cancel_buy_now_sale(%L, 'bogus', 'ck88-cx1')$$, tap._u153('s2')), '%invalid_input%', 'G28: cancel reasons are the closed four-label set');
SELECT is((market.cancel_buy_now_sale(tap._u153('s2'), 'reservation_expired', 'ck88-cx2') ->> 'sale_state'), 'cancelled', 'G29: initiated → cancelled');
SELECT is((tap._listing153(tap._u153('l3'))).status, 'active', 'G30: the listing returns reserved → active');
SELECT is((market.cancel_buy_now_sale(tap._u153('s2'), 'reservation_expired', 'ck88-cx3') ->> 'status'), 'noop_replay', 'G31: a re-cancel is noop_replay');
SELECT ok((SELECT r ->> 'status' = 'state_conflict' AND r ->> 'action' = 'reverse_payment' FROM market.mark_sale_paid_state(tap._u153('s2'), tap._u153('pay4'), 'ck88-mp1') r),
  'G32: money landing on a CANCELLED sale returns state_conflict / reverse_payment (non-raising — the webhook acks, never retries forever)…');
SELECT is(tap._audit153(tap._u153('s2'), 'market_sale.alert', 'late_payment_on_cancelled'), 1, 'G33: …and a money alert is recorded for reversal');
SELECT lives_ok(format($$SELECT market.mark_sale_paid_state(%L, %L, 'ck88-mp1b')$$, tap._u153('s2'), tap._u153('pay4')), 'G33a: the webhook replay is harmless…');
SELECT is(tap._audit153(tap._u153('s2'), 'market_sale.alert', 'late_payment_on_cancelled'), 1, 'G33b: …and the alert is recorded ONCE per sale+payment');
SELECT is((SELECT count(*)::int FROM market.list_lapsed_checkouts(10) x WHERE x.sale_id = tap._u153('s2')), 0, 'G34: a cancelled sale is no longer lapsed');
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l3');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, reservation_expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a3', tap._u153('l3'), tap._u153('a2'), tap.fan153(), tap.buyer(), 5000, 'initiated', now() + interval '10 minutes', 'ck88-s2b');
SELECT tap._store153('s2b', '00000000-0000-0000-0000-0000000000a3');
SELECT throws_like(format($$SELECT market.mark_sale_paid_state(%L, %L, 'ck88-mp2')$$, tap._u153('s2b'), tap._u153('pay3')), '%payment_unverified%',
  'G35: mark_sale_paid_state re-verifies the payment as the SALE BUYER''s succeeded row');
SELECT throws_like(format($$SELECT market.finalize_market_sale(%L, 'ck88-fz2x')$$, tap._u153('s2b')), '%not_paid%', 'G36: finalize refuses an unpaid (initiated) sale');
SELECT is((market.mark_sale_paid_state(tap._u153('s2b'), tap._u153('pay4'), 'ck88-mp3') ->> 'sale_state'), 'paid_pending_transfer', 'G37: initiated → paid_pending_transfer');
SELECT is((market.mark_sale_paid_state(tap._u153('s2b'), tap._u153('pay4'), 'ck88-mp4') ->> 'status'), 'noop_replay', 'G38: the webhook replay is noop_replay');
SELECT ok((SELECT s.paid_pending_since IS NOT NULL AND s.payment_id = tap._u153('pay4') FROM tap._sale153(tap._u153('s2b')) s), 'G39: the dwell clock and the payment are recorded');
SELECT throws_like(format($$SELECT market.cancel_buy_now_sale(%L, 'buyer_released', 'ck88-cx4')$$, tap._u153('s2b')), '%state_conflict%', 'G40: a PAID sale cannot be released (money wins)');
SELECT tap._store153('pay4b', tap._newpayment153(tap.fan153(), tap.buyer(), 5000, 'pi_88_4b')::text);
SELECT ok((SELECT r ->> 'status' = 'conflict_locked' AND r ->> 'reason' = 'second_payment_on_paid_sale' AND r ->> 'action' = 'reverse_payment'
             FROM market.mark_sale_paid_state(tap._u153('s2b'), tap._u153('pay4b'), 'ck88-mp5') r),
  'G41: §20.8.7 write-once — a DIFFERENT payment on a paid sale is conflict_locked (non-raising, E-107) with a reversal action…');
SELECT is(tap._audit153(tap._u153('s2b'), 'market_sale.alert', 'second_payment_on_paid_sale'), 1, 'G42: …and the second charge is alerted for reversal');
SELECT ok((SELECT s.payment_id = tap._u153('pay4') FROM tap._sale153(tap._u153('s2b')) s), 'G43: the stored payment is unchanged (never re-pointed)');
SELECT is(tap._audit153(tap._u153('s2b'), 'market_sale.state_sync'), 1, 'G44: the successful mark wrote ONE state_sync audit row');
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l2');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a4', tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, 'initiated', 'ck88-s4');
SELECT ok((SELECT r ->> 'status' = 'conflict_locked' AND r ->> 'reason' = 'payment_reused' FROM market.mark_sale_paid_state('00000000-0000-0000-0000-0000000000a4', tap._u153('pay4'), 'ck88-mp6') r),
  'G45: a payment already carried by another sale is payment_reused (one payment, one sale — E-105)');
SELECT is((market.bind_checkout_payment_ref('00000000-0000-0000-0000-0000000000a4', 'pi_88_other', 'ck88-bind4') ->> 'status'), 'ok', 'G46: bind a PI ref on the fresh reservation…');
SELECT ok((SELECT r ->> 'status' = 'conflict_locked' AND r ->> 'reason' = 'payment_intent_mismatch' FROM market.mark_sale_paid_state('00000000-0000-0000-0000-0000000000a4', tap._u153('pay4b'), 'ck88-mp7') r),
  'G47: …a payment whose PI is not the bound ref is payment_intent_mismatch (§20.8.9 binding)');
SELECT throws_ok($$INSERT INTO market.market_sale (listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, payment_id, sale_state, command_idempotency_key)
  VALUES (tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, tap._u153('pay4'), 'initiated', 'ck88-s-dup')$$, '23505', NULL,
  'G48: E-105 structural — a second sale row carrying the same payment is unstorable');
DELETE FROM market.market_sale WHERE sale_id = '00000000-0000-0000-0000-0000000000a4';
UPDATE market.listing_native SET status='sold' WHERE listing_id = tap._u153('l2');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'market_sale', %L, %L, 'ck88-x10')$$, tap._u153('a2'), tap.fan153(), tap._u153('s2b'), tap._u153('pay2')), '%already settled another custody move%',
  'G49: the engine refuses a payment already linked to ANOTHER sale (R-34 one link; C35)');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'admin_action', %L, NULL, 'ck88-fz1')$$, tap._u153('a1'), tap.buyer(), gen_random_uuid()), '%idempotency_conflict%',
  'G50: a command key reused on the same atom for a DIFFERENT custody move is idempotency_conflict, never a raw 23505');
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l2');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a7', tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, 'initiated', 'ck88-s7');
UPDATE market.listing_native SET status='cancelled', reason_code='door_freeze' WHERE listing_id = tap._u153('l2');   -- the reservation died under a drain
SELECT ok((SELECT r ->> 'status' = 'conflict_locked' AND r ->> 'reason' = 'listing_not_reserved' AND r ->> 'action' = 'reverse_payment'
             FROM market.mark_sale_paid_state('00000000-0000-0000-0000-0000000000a7', tap._u153('pay4b'), 'ck88-mp8') r)
       AND tap._audit153('00000000-0000-0000-0000-0000000000a7', 'market_sale.alert', 'listing_not_reserved') = 1,
  'G51: money landing on a reservation whose listing was drained/cancelled is alerted for reversal, never advanced to paid_pending');
DELETE FROM market.market_sale WHERE sale_id = '00000000-0000-0000-0000-0000000000a7';
UPDATE market.listing_native SET status='sold', reason_code=NULL WHERE listing_id = tap._u153('l2');

-- ============================================================================
-- SECTION H — DISPUTES (R-40; PFA-13; PFA-31 park; PFA-29 chargeback seam; E-90)
-- ============================================================================
-- a closed settlement over order1 → a pending payout (the payout-leg operand)
SELECT tap.login(tap.seller());
SELECT tap._store153('st1', (venue.open_settlement(tap._u153('org1'), tap._u153('venue1'), tap._u153('event1'), '{}'::jsonb, 'ck88-st1') ->> 'settlement_id'));
SELECT tap.logout();
INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (tap._u153('st1'), 'primary_sale', tap._u153('order1'), 15000);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT tap._store153('cl1', kernel.close_settlement(tap._u153('st1'), 'ck88-cl1')::text);
SELECT tap.logout();
SELECT is((tap._fetch153('cl1')::jsonb ->> 'net_minor'), '15000', 'H1: settlement 1 closes at net 15000 (OWNER TEST C operand: the PRIOR settlement)');
SELECT tap._store153('po1', ((tap._fetch153('cl1')::jsonb -> 'payout_ids') ->> 0));
SELECT ok((SELECT p.status='pending' AND p.hold_state='none' FROM kernel.payout p WHERE p.payout_id = tap._u153('po1')), 'H2: its payout is pending and unheld');
-- record (service path; the webhook branch)
SELECT throws_ok($$SELECT kernel.record_dispute_native('dp_x', 'ch_x', 'pi_nope', 100, 'USD', 'fraudulent', 'needs_response', NULL, 'ck88-d-x')$$, 'P0002', NULL,
  'H3: an unknown payment intent is not_found (the webhook retries)');
SELECT throws_like($$SELECT kernel.record_dispute_native('dp_x', 'ch_x', 'pi_88_1', 100, 'USD', 'fraudulent', 'bogus', NULL, 'ck88-d-x')$$, '%invalid_input%dispute status%',
  'H4: the status is the closed eight-label set');
SELECT tap._store153('d1r', kernel.record_dispute_native('dp_88_1', 'ch_88_1', 'pi_88_1', 15000, 'USD', 'fraudulent', 'needs_response', now()+interval '7 days', 'ck88-d1')::text);
SELECT tap._store153('d1', (tap._fetch153('d1r')::jsonb ->> 'dispute_id'));
SELECT is((tap._fetch153('d1r')::jsonb ->> 'status'), 'ok', 'H5: the native dispute is recorded');
SELECT ok((tap._fetch153('d1r')::jsonb ->> 'atoms_held')::int = 1 AND (tap._fetch153('d1r')::jsonb ->> 'atoms_skipped')::int = 2 AND (tap._fetch153('d1r')::jsonb ->> 'payouts_held')::int = 1,
  'H6: atom leg: 1 held (a3: buyer still holds, no overlay), 2 skipped (a1 custody moved; a2 overlay occupied); payout leg: 1 held');
SELECT is((tap._atom153(tap._u153('a3'))).resale_state, 'dispute_hold', 'H7: a3 → dispute_hold');
SELECT is((tap._atom153(tap._u153('a2'))).resale_state, 'listed', 'H8: a2 keeps its live market overlay (never mutated; alerted)');
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'none', 'H9: a1 (custody moved to fan153) is untouched (alerted)');
SELECT is(tap._audit153(tap._u153('a1'), 'dispute.alert', 'custody_moved') + tap._audit153(tap._u153('a2'), 'dispute.alert', 'overlay_occupied'), 2, 'H10: both skips are audited to platform_risk');
SELECT ok((SELECT p.status='pending' AND p.hold_state='held' AND p.hold_reason_code='dispute' AND p.held_at IS NOT NULL AND p.held_by IS NULL FROM kernel.payout p WHERE p.payout_id = tap._u153('po1')),
  'H11: the reachable payout is HELD (status untouched — MB-2; held_by NULL — the platform)');
SELECT is(tap._outbox153('payout_on_hold', tap._u153('po1')), 1, 'H12: payout_on_hold BE-emitted');
SELECT is(tap._audit153(tap._u153('d1'), 'dispute.record'), 1, 'H13: dispute.record audited');
SELECT is((kernel.record_dispute_native('dp_88_1', 'ch_88_1', 'pi_88_1', 15000, 'USD', 'fraudulent', 'needs_response', NULL, 'ck88-d1b') ->> 'status'), 'noop_replay',
  'H14: the same Stripe dispute replays (no second row, no second freeze pass)');
SELECT is((SELECT count(*)::int FROM kernel.dispute_native), 1, 'H15: one dispute row');
SELECT is(tap._audit153(tap._u153('d1'), 'dispute.record'), 1, 'H16: no second audit row');
-- the no-link arm
SELECT tap._store153('d5r', kernel.record_dispute_native('dp_88_5', 'ch_88_5', 'pi_88_5', 5000, 'usd', 'product_not_received', 'needs_response', NULL, 'ck88-d5')::text);
SELECT tap._store153('d5', (tap._fetch153('d5r')::jsonb ->> 'dispute_id'));
SELECT ok((tap._fetch153('d5r')::jsonb ->> 'linked')::boolean = false AND (tap._fetch153('d5r')::jsonb ->> 'atoms_held')::int = 0 AND (tap._fetch153('d5r')::jsonb ->> 'payouts_held')::int = 0,
  'H17: NO-LINK ARM — a payment with no payment_native row is recorded with zero freeze legs');
SELECT is(tap._audit153(tap._u153('d5'), 'dispute.alert', 'no_link'), 1, 'H18: …and alerted');
SELECT is((SELECT currency FROM kernel.dispute_native WHERE dispute_id = tap._u153('d5')), 'USD', 'H18a: a lowercase Stripe currency is normalized to the ISO uppercase the seam compares on');
SELECT throws_like($$SELECT kernel.record_dispute_native('dp_x2', 'ch_x2', 'pi_88_5', 1, 'US', 'x', 'won', NULL, 'ck88-d-x2')$$, '%invalid_input%currency%', 'H18b: a non-ISO currency is refused');
SELECT throws_like($$SELECT kernel.record_dispute_native('dp_x3', 'ch_x3', 'pi_88_5', 1, 'USD', 'x', 'won', NULL, 'bad key!')$$, '%invalid_input%command_key%', 'H18c: E-80 — a command key that would land in the audit is bounded');
-- BP-7 native twin while open
SELECT is(kernel.deletion_blockers_market(tap.other_user()), 'BP-7: open native dispute', 'H19: BP-7 twin — the disputed payment''s buyer (d5: other_user) is deletion-blocked while the dispute is OPEN');
SELECT is(kernel.deletion_blockers_market(tap.buyer()), 'BP-3: unsettled native sale', 'H19a: the ordered predicate — BP-3 (the seller''s unsettled s2b) precedes BP-7 for the buyer');
-- PFA-31 park: authority first, then the fail-closed raise, ZERO mutation
SELECT tap.login(tap.risk153());
SELECT throws_like(format($$SELECT kernel.resolve_dispute_native(%L, 'bogus', 'x', 'ck88-rs-x')$$, tap._u153('d1')), '%invalid_input%outcome%', 'H20: the outcome is validated before the park');
SELECT throws_ok($$SELECT kernel.resolve_dispute_native(gen_random_uuid(), 'buyer_win', 'x', 'ck88-rs-y')$$, 'P0002', NULL, 'H21: an unknown dispute is not_found');
SELECT throws_ok(format($$SELECT kernel.resolve_dispute_native(%L, 'buyer_win', 'fraud_confirmed', 'ck88-rs1')$$, tap._u153('d1')), NULL,
  'precondition_failed: dual_control_unavailable — dispute resolution requires a dual-control mechanism the immutable approval substrate cannot park (PFA-31); the dispute stays held, nothing is resolved or released',
  'H22: OWNER TEST I — platform_risk''s resolve FAILS CLOSED: dual_control_unavailable (PFA-31)');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_like(format($$SELECT kernel.resolve_dispute_native(%L, 'seller_win', 'x', 'ck88-rs2')$$, tap._u153('d1')), '%dual_control_unavailable%',
  'H23: platform_admin alone is NOT a control path either (no single-control downgrade)');
SELECT tap.logout();
SELECT ok((SELECT d.status='needs_response' AND d.resolution_outcome IS NULL AND d.resolution_reason_code IS NULL AND d.resolved_by IS NULL AND d.resolved_at IS NULL FROM kernel.dispute_native d WHERE d.dispute_id = tap._u153('d1')),
  'H24: OWNER TEST J — zero mutation: status unchanged, resolution quadruple NULL');
SELECT ok((tap._atom153(tap._u153('a3'))).resale_state = 'dispute_hold' AND (SELECT p.hold_state='held' FROM kernel.payout p WHERE p.payout_id = tap._u153('po1')),
  'H25: OWNER TEST J — the atom stays dispute_hold and the payout stays held (no release while parked)');
-- PFA-13: the unlock re-arm while the dispute is open
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT tap._lock153(%L, 'listed', 'ck88-lk-x')$$, tap._u153('a3')), '%conflict_locked%', 'H26: a dispute_hold atom cannot be locked for listing');
SELECT tap.logout();
UPDATE kernel.tickets SET resale_state='listed' WHERE ticket_atom_id = tap._u153('a3');   -- a listing that pre-dated the dispute
SELECT is((kernel.unlock_ticket(tap._u153('a3'), 'ck88-ul1') ->> 'resale_state'), 'dispute_hold', 'H27: PFA-13 — the release RE-ARMS to dispute_hold while the dispute is open');
SELECT is((tap._atom153(tap._u153('a3'))).resale_state, 'dispute_hold', 'H28: …persisted on the head');
SELECT is((kernel.unlock_ticket(tap._u153('a1'), 'ck88-ul2') ->> 'status'), 'noop_replay', 'H29: unlock on a ''none'' atom is noop_replay (079 semantics kept)');
UPDATE kernel.tickets SET resale_state='listed' WHERE ticket_atom_id = tap._u153('a1');
SELECT is((kernel.unlock_ticket(tap._u153('a1'), 'ck88-ul3') ->> 'resale_state'), 'none', 'H30: E-103 — a1''s CURRENT holder (fan153) did not pay the disputed payment ⇒ release resolves to none');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'admin_action', %L, NULL, 'ck88-x7')$$, tap._u153('a3'), tap.fan153(), gen_random_uuid()), '%conflict_locked%',
  'H31: the engine refuses a dispute_hold atom (overlay check) — R-40 custody freeze');
UPDATE kernel.tickets SET resale_state='listed' WHERE ticket_atom_id = tap._u153('a3');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'admin_action', %L, NULL, 'ck88-x8a')$$, tap._u153('a3'), tap.fan153(), gen_random_uuid()), '%conflict_locked%',
  'H32a: admin_action never moves an atom under a LIVE market overlay (the listing/transfer must be cancelled first)');
UPDATE kernel.tickets SET resale_state='none' WHERE ticket_atom_id = tap._u153('a3');
SELECT throws_like(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'admin_action', %L, NULL, 'ck88-x8')$$, tap._u153('a3'), tap.fan153(), gen_random_uuid()), '%open_dispute%',
  'H32: …and refuses on the open-dispute predicate even when the overlay would allow (the R-40 mirror)');
UPDATE kernel.tickets SET resale_state='dispute_hold' WHERE ticket_atom_id = tap._u153('a3');
-- mark_dispute_state: forward-only, terminal absorbing
SELECT throws_ok($$SELECT kernel.mark_dispute_state('dp_nope', 'won', 'ck88-m-x')$$, 'P0002', NULL, 'H33: an unknown ref is not_found (the handler records at terminal instead)');
SELECT throws_like($$SELECT kernel.mark_dispute_state('dp_88_1', 'bogus', 'ck88-m-y')$$, '%invalid_input%', 'H34: an unknown status is invalid_input');
SELECT is((kernel.mark_dispute_state('dp_88_1', 'under_review', 'ck88-m1') ->> 'dispute_status'), 'under_review', 'H35: open → open');
SELECT is((kernel.mark_dispute_state('dp_88_1', 'under_review', 'ck88-m1b') ->> 'status'), 'noop_replay', 'H36: same status replays');
SELECT is(tap._audit153(tap._u153('d1'), 'dispute.state_sync'), 1, 'H37: exactly one state_sync audit row so far');
SELECT is((kernel.mark_dispute_state('dp_88_5', 'won', 'ck88-m2') ->> 'dispute_status'), 'won', 'H38: open → terminal (won)');
SELECT is((kernel.mark_dispute_state('dp_88_5', 'won', 'ck88-m2b') ->> 'status'), 'noop_replay', 'H39: terminal → same terminal is noop_replay');
SELECT throws_like($$SELECT kernel.mark_dispute_state('dp_88_5', 'lost', 'ck88-m2c')$$, '%state_conflict%terminal%', 'H40: terminal → a different terminal is a state_conflict (absorbing)');
SELECT is(kernel.deletion_blockers_market(tap.other_user()), NULL, 'H40a: BP-7 releases once the dispute is terminal (won)');
SELECT is((kernel.mark_dispute_state('dp_88_1', 'lost', 'ck88-m3') ->> 'dispute_status'), 'lost', 'H41: dispute 1 → LOST (the chargeback fact)');
SELECT is((tap._atom153(tap._u153('a3'))).resale_state, 'dispute_hold', 'H42: PFA-31 — a Stripe-reported terminal is a STATE fact: the atom stays held');
SELECT is((kernel.unlock_ticket(tap._u153('a3'), 'ck88-ul4') ->> 'resale_state'), 'dispute_hold', 'H42a: a market release NEVER clears dispute_hold — only resolution does (PFA-31), even after the dispute is terminal');
SELECT ok((SELECT p.hold_state='held' FROM kernel.payout p WHERE p.payout_id = tap._u153('po1')), 'H43: …and the payout stays held');
SELECT is(kernel.deletion_blockers_market(tap.buyer()), 'BP-3: unsettled native sale', 'H44: a LOST dispute no longer blocks its buyer under BP-7; the buyer''s remaining blocker is BP-3 (the unsettled s2b)');
-- the chargeback seam (OWNER TESTS B, C, D)
SELECT tap.login(tap.seller());
SELECT tap._store153('st2', (venue.open_settlement(tap._u153('org1'), tap._u153('venue1'), NULL, '{}'::jsonb, 'ck88-st2') ->> 'settlement_id'));
SELECT tap._store153('st3', (venue.open_settlement(tap._u153('org1'), tap._u153('venue1'), NULL, '{}'::jsonb, 'ck88-st3') ->> 'settlement_id'));
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.settlement_royalty_lines(tap._u153('st2')) c WHERE c.cause='chargeback' AND c.cause_ref=tap._u153('d1') AND c.amount_minor=-15000 AND c.payee_kind='organization' AND c.payee_id=tap._u153('org1')), 1,
  'H45: the seam offers the lost dispute as a NEGATIVE chargeback candidate (cause_ref = dispute id, org payee)');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT tap._store153('cl2', kernel.close_settlement(tap._u153('st2'), 'ck88-cl2')::text);
SELECT tap._store153('cl3', kernel.close_settlement(tap._u153('st3'), 'ck88-cl3')::text);
SELECT tap.logout();
SELECT ok((SELECT s.status='closed' AND s.gross_minor=0 AND s.fees_minor=0 AND s.refunds_minor=15000 AND s.net_minor=-15000 FROM venue.settlement s WHERE s.settlement_id=tap._u153('st2')),
  'H46: OWNER TEST B — chargeback −15000 lands in the org''s NEXT settlement: refunds 15000, net −15000');
SELECT ok((SELECT l.amount_minor=-15000 AND l.cause='chargeback' FROM venue.settlement_line l WHERE l.settlement_id=tap._u153('st2') AND l.cause_ref=tap._u153('d1')),
  'H47: …as an append-only negative line with cause_ref = the dispute');
SELECT is((tap._fetch153('cl2')::jsonb -> 'payout_ids'), '[]'::jsonb, 'H48: NEGATIVE_SETTLEMENT_CARRY — a negative net mints NO payout (no carry account invented)');
SELECT ok((SELECT s.gross_minor=15000 AND s.net_minor=15000 FROM venue.settlement s WHERE s.settlement_id=tap._u153('st1'))
       AND (SELECT count(*)=0 FROM venue.settlement_line l WHERE l.settlement_id=tap._u153('st1') AND l.cause='chargeback'),
  'H49: OWNER TEST C — the PRIOR (closed) settlement is unchanged: no clawback, no mutation');
SELECT is((SELECT count(*)::int FROM venue.settlement_line l WHERE l.cause='chargeback' AND l.cause_ref=tap._u153('d1')), 1,
  'H50: OWNER TEST D — the same dispute is lined ONCE across settlements (NOT EXISTS under the settlement lock)');
SELECT ok((SELECT s.net_minor=0 FROM venue.settlement s WHERE s.settlement_id=tap._u153('st3')), 'H51: the following settlement carries no duplicate line');
-- royalty (OWNER TESTS A, E): a stored split on the completed sale + a second lost dispute
SELECT tap._store153('d7r', kernel.record_dispute_native('dp_88_7', 'ch_88_7', 'pi_88_7', 5000, 'USD', 'fraudulent', 'lost', NULL, 'ck88-d7')::text);
SELECT tap._store153('d7', (tap._fetch153('d7r')::jsonb ->> 'dispute_id'));
SELECT ok((tap._fetch153('d7r')::jsonb ->> 'atoms_held')::int = 0 AND (tap._atom153(tap._u153('a4'))).resale_state = 'none',
  'H52: a dispute recorded already TERMINAL takes no freeze leg (a4 stays free)');
UPDATE market.market_sale SET platform_fee_minor=0, venue_royalty_minor=100, seller_proceeds_minor=4900 WHERE sale_id = tap._u153('s1');
SELECT tap.login(tap.seller());
SELECT tap._store153('st5', (venue.open_settlement(tap._u153('org1'), tap._u153('venue1'), tap._u153('event1'), '{}'::jsonb, 'ck88-st5') ->> 'settlement_id'));
SELECT tap.logout();
SELECT is((SELECT string_agg(c.cause || ':' || c.amount_minor::text, ',' ORDER BY c.cause, c.cause_ref) FROM kernel.settlement_royalty_lines(tap._u153('st5')) c), 'chargeback:-5000,market_sale:100',
  'H53: OWNER TEST E — ONE seam call yields BOTH classes: the royalty (+100, cause market_sale) and the chargeback (−5000)');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT tap._store153('cl5', kernel.close_settlement(tap._u153('st5'), 'ck88-cl5')::text);
SELECT tap.logout();
SELECT ok((SELECT s.gross_minor=100 AND s.fees_minor=0 AND s.refunds_minor=5000 AND s.net_minor=-4900 FROM venue.settlement s WHERE s.settlement_id=tap._u153('st5')),
  'H54: OWNER TEST A (E-90) — the royalty is a POSITIVE venue earning: +100 → GROSS +100; the chargeback → refunds 5000; net −4900');
SELECT ok((SELECT l.amount_minor=100 AND l.cause='market_sale' FROM venue.settlement_line l WHERE l.settlement_id=tap._u153('st5') AND l.cause_ref=tap._u153('s1')),
  'H55: the royalty line names the sale (cause_ref = sale_id, amount +100)');
SELECT tap.login(tap.seller());
SELECT tap._store153('st6', (venue.open_settlement(tap._u153('org1'), tap._u153('venue1'), tap._u153('event1'), '{}'::jsonb, 'ck88-st6') ->> 'settlement_id'));
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.settlement_royalty_lines(tap._u153('st6'))), 0, 'H56: OWNER TEST D — a re-run of the seam offers NOTHING already lined (royalty AND chargeback)');
SELECT is((SELECT count(*)::int FROM kernel.settlement_royalty_lines(gen_random_uuid())), 0, 'H57: an unknown settlement yields zero rows — the seam never raises (087 close-safety)');
SELECT ok((SELECT p.prosrc !~* 'numeric|float|double|real' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'H58: integer minor units only — no float/numeric arithmetic in the seam');

-- ============================================================================
-- SECTION K — P2P (§8.1-8.3, §12.2): create PARKED (TTL unnamed); accept/decline/
--   cancel/sweep real over seeded rows; E-23 F-4; E-99 decline shape
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT market.create_p2p_transfer(%L, 'fan', NULL, 'ck88-t-x1')$$, tap._u153('a1')), '42501', NULL, 'K1: only the current owner may open a transfer');
SELECT tap.logout();
SELECT tap.login(tap.fan153());
SELECT throws_ok(format($$SELECT market.create_p2p_transfer(%L, 'buyer', NULL, 'ck88-t-x2')$$, tap._u153('a1')), NULL,
  'precondition_failed: p2p_ttl_unavailable — the p2p transfer TTL is unnamed in the frozen corpus (PFA-9/X-12); no transfer is opened',
  'K2: P2P_TRANSFER_TTL — after full validation the verb FAILS CLOSED (no TTL key is invented)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM market.p2p_transfer), 0, 'K3: zero transfer rows');
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'none', 'K4: the atom was not locked');
SELECT tap.login(tap.seller());
SELECT is((catalog.set_resale_policy('event', tap._u153('event1'), '{"mode":"off"}'::jsonb, 'ck88-pol3') ->> 'version'), '3', 'K5: policy v3 = off');
SELECT tap.logout();
SELECT tap.login(tap.fan153());
SELECT throws_like(format($$SELECT market.create_p2p_transfer(%L, 'buyer', NULL, 'ck88-t-x3')$$, tap._u153('a1')), '%policy_violation%resale off%',
  'K6: mode off refuses a transfer BEFORE the TTL park (policy precedes)');
SELECT throws_like(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-l-off')$$, tap._u153('a1')), '%policy_violation%mode off%', 'K7: …and a listing');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((catalog.set_resale_policy('event', tap._u153('event1'), '{"mode":"buy_now","price_cap_bps":10000}'::jsonb, 'ck88-pol4') ->> 'version'), '4', 'K8: policy v4 = buy_now again');
SELECT tap.logout();
-- seeded transfers (the un-parked world's rows): the owner locks, the row is inserted
SELECT tap.login(tap.fan153());
SELECT is((tap._lock153(tap._u153('a1'), 'locked', 'ck88-lk1') ->> 'status'), 'ok', 'K9: the owner locks a1 for a transfer');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, price_minor, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b1', tap._u153('a1'), tap.fan153(), tap.buyer(), NULL, now()+interval '1 hour', 'ck88-t1');
SELECT tap.login(tap.other_user());
SELECT throws_ok($$SELECT market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b1', 'ck88-acc-x')$$, '42501', NULL, 'K10: only the addressed recipient accepts');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_like($$SELECT market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b1', 'ck88-acc-y', 'bogus')$$, '%invalid_input%', 'K11: p_decision is accept | decline');
SELECT is((market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b1', 'ck88-dec1', 'decline') ->> 'final_state'), 'declined', 'K12: E-99 — the recipient DECLINES through the accept endpoint');
SELECT tap.logout();
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'none', 'K13: decline unlocks the atom');
SELECT tap.login(tap.fan153());
SELECT is((tap._lock153(tap._u153('a1'), 'locked', 'ck88-lk2') ->> 'status'), 'ok', 'K14: locked again');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, price_minor, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b2', tap._u153('a1'), tap.fan153(), tap.buyer(), 100, now()+interval '1 hour', 'ck88-t2');
SELECT tap.login(tap.buyer());
SELECT throws_like($$SELECT market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b2', 'ck88-acc1')$$, '%payment_unverified%',
  'K15: E-101 — a PRICED acceptance has no contracted payment binding: refused');
SELECT tap.logout();
UPDATE market.p2p_transfer SET price_minor = NULL WHERE transfer_id = '00000000-0000-0000-0000-0000000000b2';
UPDATE kernel.identity_ext SET deletion_state='DELETION_PENDING' WHERE identity_id = tap.buyer();
INSERT INTO kernel.identity_ext (identity_id, deletion_state) SELECT tap.buyer(), 'DELETION_PENDING' WHERE NOT EXISTS (SELECT 1 FROM kernel.identity_ext WHERE identity_id = tap.buyer());
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b2', 'ck88-acc2')$$, NULL, 'precondition_failed: deletion_pending',
  'K16: OR-17 F-4 — a DELETION_PENDING recipient may not accept');
SELECT tap.logout();
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.buyer();
SELECT tap.login(tap.buyer());
SELECT tap._store153('acc3', market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b2', 'ck88-acc3')::text);
SELECT is((tap._fetch153('acc3')::jsonb ->> 'final_state'), 'completed', 'K17: a gift acceptance completes through the engine');
SELECT is((market.accept_p2p_transfer('00000000-0000-0000-0000-0000000000b2', 'ck88-acc3b') ->> 'status'), 'noop_replay', 'K18: a re-accept is noop_replay');
SELECT tap.logout();
SELECT ok((SELECT t.current_owner_id = tap.buyer() AND t.credential_version = 2 AND t.resale_state = 'none' FROM tap._atom153(tap._u153('a1')) t),
  'K19: custody moved back to buyer, credential_version 1 → 2, overlay none');
SELECT ok((SELECT l.cause='p2p_transfer' AND l.cause_ref='00000000-0000-0000-0000-0000000000b2' AND l.from_identity=tap.fan153() AND l.to_identity=tap.buyer()
             FROM kernel.ticket_ownership_log l WHERE l.ticket_atom_id = tap._u153('a1') AND l.sequence = 3),
  'K20: ledger seq 3: cause p2p_transfer / cause_ref transfer_id');
SELECT is(tap._outbox153('ownership_changed', tap._u153('a1')), 2, 'K21: a second ownership_changed envelope');
-- cancel: sender only; the definer arm only expires
SELECT tap.login(tap.buyer());
SELECT is((tap._lock153(tap._u153('a1'), 'locked', 'ck88-lk3') ->> 'status'), 'ok', 'K22: buyer locks a1');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b4', tap._u153('a1'), tap.buyer(), tap.fan153(), now()+interval '1 hour', 'ck88-t4');
SELECT tap.login(tap.fan153());
SELECT throws_ok($$SELECT market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b4', 'changed_mind', 'ck88-cn-x')$$, '42501', NULL, 'K23: the recipient cannot cancel (they decline)');
SELECT tap.logout();
SELECT throws_ok($$SELECT market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b4', 'changed_mind', 'ck88-cn-y')$$, '42501', NULL, 'K24: the definer arm (no auth.uid) may ONLY expire');
SELECT tap.login(tap.buyer());
SELECT throws_like($$SELECT market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b4', 'expired', 'ck88-cn-z')$$, '%system reason%', 'K25: a sender cannot write ''expired'' / a system reason (the sweep''s transition)');
SELECT is((market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b4', 'changed_mind', 'ck88-cn1') ->> 'final_state'), 'cancelled', 'K26: the sender cancels');
SELECT is((market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b4', 'changed_mind', 'ck88-cn1b') ->> 'status'), 'noop_replay', 'K27: a re-cancel replays');
SELECT tap.logout();
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'none', 'K28: cancel unlocks');
-- the sweep: expired transfers + the offer second statement
SELECT tap.login(tap.buyer());
SELECT is((tap._lock153(tap._u153('a1'), 'locked', 'ck88-lk5') ->> 'status'), 'ok', 'K29: buyer locks a1 again');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b5', tap._u153('a1'), tap.buyer(), tap.fan153(), now()-interval '1 minute', 'ck88-t5');
SELECT tap._store153('sw1', market.sweep_expired_p2p_transfers()::text);
SELECT is((tap._fetch153('sw1')::jsonb ->> 'swept_count')::int, 1, 'K30: §12.2 — the lapsed transfer is swept');
SELECT ok((SELECT status='expired' AND reason_code='expired' FROM market.p2p_transfer WHERE transfer_id='00000000-0000-0000-0000-0000000000b5'), 'K31: → expired (first-class state)');
SELECT is((tap._atom153(tap._u153('a1'))).resale_state, 'none', 'K32: …and unlocked');
SELECT tap.login(tap.buyer());
SELECT is((market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b5', 'changed_mind', 'ck88-cn5') ->> 'final_state'), 'expired', 'K32a: the sender''s cancel after the sweep expired it is an idempotent close (noop_replay/expired)');
SELECT tap.logout();
SELECT is((tap._fetch153('sw1')::jsonb ->> 'offers_expired')::int, 1, 'K33: the tick''s SECOND statement expired the lapsed pending offer (presentational)');
SELECT ok((SELECT status='expired' FROM market.offer WHERE offer_id='00000000-0000-0000-0000-00000000f001'), 'K34: …the F18 offer is now expired');
SELECT is((market.sweep_expired_p2p_transfers() ->> 'swept_count')::int, 0, 'K35: a re-run sweeps nothing (re-entrant)');
SELECT tap.login(tap.buyer());
SELECT is((tap._lock153(tap._u153('a1'), 'locked', 'ck88-lk8') ->> 'status'), 'ok', 'K35a: buyer locks a1 for an unlapsed transfer');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b8', tap._u153('a1'), tap.buyer(), tap.fan153(), now()+interval '1 hour', 'ck88-t8');
SELECT throws_like($$SELECT market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b8', 'expired', 'ck88-cn8')$$, '%has not lapsed%', 'K35b: §8.3 — the definer arm expires ONLY TTL-lapsed rows');
SELECT ok((SELECT status='initiated' FROM market.p2p_transfer WHERE transfer_id='00000000-0000-0000-0000-0000000000b8'), 'K35c: …the live transfer is untouched');
SELECT tap.login(tap.buyer());
SELECT is((market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b8', 'changed_mind', 'ck88-cn8b') ->> 'final_state'), 'cancelled', 'K35d: cleaned up by the sender');
SELECT tap.logout();
-- BP-4 twin
SELECT tap.login(tap.buyer());
SELECT is((tap._lock153(tap._u153('a1'), 'locked', 'ck88-lk6') ->> 'status'), 'ok', 'K36: buyer locks a1 for a transfer to risk153');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b6', tap._u153('a1'), tap.buyer(), tap.risk153(), now()+interval '1 hour', 'ck88-t6');
SELECT is(kernel.deletion_blockers_market(tap.risk153()), 'BP-4: open native transfer', 'K37: BP-4 twin — the recipient of an open transfer is deletion-blocked');
SELECT tap.login(tap.buyer());
SELECT is((market.cancel_p2p_transfer('00000000-0000-0000-0000-0000000000b6', 'changed_mind', 'ck88-cn6') ->> 'final_state'), 'cancelled', 'K38: cleaned up');
SELECT tap.logout();
SELECT is(kernel.deletion_blockers_market(tap.risk153()), NULL, 'K39: …and the blocker clears');

-- ============================================================================
-- SECTION I — THE DOOR HOOKS (§17.10a): preview, drain, exclusion, freeze
-- ============================================================================
SELECT tap.login(tap.other_user());
SELECT is((tap._lock153(tap._u153('a4'), 'locked', 'ck88-lk7') ->> 'status'), 'ok', 'I1: other_user locks a4 for a transfer');
SELECT tap.logout();
INSERT INTO market.p2p_transfer (transfer_id, ticket_atom_id, from_identity, to_identity, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b7', tap._u153('a4'), tap.other_user(), tap.fan153(), now()+interval '1 hour', 'ck88-t7');
SELECT ok((SELECT p.pending_transfers=1 AND p.active_listings=0 AND p.excluded_paid_pending=1 AND p.atoms_to_unlock=1 FROM market.door_freeze_drain_preview(tap._u153('session1')) p),
  'I2: preview — 1 transfer, 0 drainable listings, 1 EXCLUDED (l3 reserved under the paid s2b), 1 atom to unlock');
SELECT tap.login(tap.seller());
SELECT is((venue.open_door_manifest(tap._u153('session1'), 'doors_open', 'ck88-door1') ->> 'status'), 'ok', 'I3: the venue_manager opens the door (engages the freeze; runs the drain)');
SELECT tap.logout();
SELECT ok((SELECT status='cancelled' AND reason_code='door_freeze' FROM market.p2p_transfer WHERE transfer_id='00000000-0000-0000-0000-0000000000b7'), 'I4: the transfer is drained (cancelled, reason door_freeze)');
SELECT is((tap._atom153(tap._u153('a4'))).resale_state, 'none', 'I5: its atom is unlocked');
SELECT is((tap._listing153(tap._u153('l3'))).status, 'reserved', 'I6: T-RPC-DOOR-12 — the paid_pending listing is EXCLUDED (money taken; §12.3 owns it)');
SELECT is((tap._atom153(tap._u153('a2'))).resale_state, 'listed', 'I7: …its atom keeps the overlay');
SELECT ok(kernel.is_transfer_frozen(tap._u153('a1')), 'I8: the session is frozen (door_open_at engaged)');
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.create_listing(%L, 5000, 'buy_now', 'ck88-l-frz')$$, tap._u153('a1')), '%frozen%', 'I9: T-RPC-MARKET-01 — a frozen session refuses a new listing');
SELECT tap.logout();
SELECT throws_ok(format($$SELECT kernel.transfer_ticket_ownership(%L, %L, 'admin_action', %L, NULL, 'ck88-x9')$$, tap._u153('a1'), tap.fan153(), gen_random_uuid()), NULL, 'precondition_failed: frozen',
  'I10: THE freeze enforcement point — the engine refuses ''frozen'' under the atom lock (§12.4)');
SELECT throws_ok(format($$SELECT market.finalize_market_sale(%L, 'ck88-fz2')$$, tap._u153('s2b')), NULL, 'precondition_failed: frozen',
  'I11: the COMPLETE branch is frozen (the paid sale stays pending for C25; nothing moved)');
SELECT ok((SELECT s.terminal_state='pending' AND s.sale_state='paid_pending_transfer' FROM tap._sale153(tap._u153('s2b')) s), 'I12: …s2b untouched');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log WHERE ticket_atom_id = tap._u153('a2')), 1, 'I13: …no ledger row for a2');

-- ============================================================================
-- SECTION J — market.on_atom_voided (C26 compensate arm; E-95)
-- ============================================================================
SELECT lives_ok(format($$SELECT market.on_atom_voided(%L, %L, 'refund_void')$$, tap._u153('a2'), gen_random_uuid()), 'J1: the hook runs on the paid-pending atom');
SELECT ok((SELECT s.terminal_state='pending' AND s.sale_state='paid_pending_transfer' FROM tap._sale153(tap._u153('s2b')) s),
  'J2: a PAID sale whose buyer''s payment carries NO refund is NEVER terminalized (money would be stranded) — stays pending…');
SELECT is(tap._audit153(tap._u153('s2b'), 'market_sale.alert', 'compensation_refund_missing'), 1, 'J3: …and platform_risk is alerted');
SELECT tap._store153('rf4', tap._refund153(tap._u153('pay4'), 'ck88-rf4')::text);
SELECT lives_ok(format($$SELECT market.on_atom_voided(%L, %L, 'refund_void')$$, tap._u153('a2'), tap._u153('rf4')), 'J4: with a refund intent on the buyer''s payment the hook runs again…');
SELECT ok((SELECT s.terminal_state='compensated' FROM tap._sale153(tap._u153('s2b')) s), 'J4a: …pending → COMPENSATED (compensated ⇔ refunded; C26)');
SELECT is(tap._audit153(tap._u153('s2b'), 'market_sale.compensated'), 1, 'J5: audited once');
SELECT lives_ok(format($$SELECT market.on_atom_voided(%L, %L, 'refund_void')$$, tap._u153('a2'), tap._u153('rf4')), 'J5a: a third void is a no-op');
SELECT is(tap._audit153(tap._u153('s2b'), 'market_sale.compensated'), 1, 'J5b: …no second audit row');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a5', tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, 'initiated', 'ck88-s5');
SELECT lives_ok(format($$SELECT market.on_atom_voided(%L, %L, 'refund_void')$$, tap._u153('a1'), gen_random_uuid()), 'J5c: an UNPAID reservation on a voided atom…');
SELECT ok((SELECT s.sale_state='cancelled' AND s.terminal_state='pending' FROM tap._sale153('00000000-0000-0000-0000-0000000000a5') s) AND tap._audit153('00000000-0000-0000-0000-0000000000a5', 'market_sale.cancelled', 'refund_void') = 1,
  'J5d: …dies with the atom (cancelled; a late payment then meets the cancelled arm)');
DELETE FROM market.market_sale WHERE sale_id = '00000000-0000-0000-0000-0000000000a5';
-- a charged-back sale payment: finalize refuses; the void hook compensates (money returned by the chargeback)
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l2');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, payment_id, sale_state, paid_pending_since, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a8', tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, tap._u153('pay4b'), 'paid_pending_transfer', now(), 'ck88-s8');
SELECT is((kernel.record_dispute_native('dp_88_4b', 'ch_88_4b', 'pi_88_4b', 5000, 'USD', 'fraudulent', 'lost', NULL, 'ck88-d4b') ->> 'status'), 'ok', 'J6a: the sale''s payment is charged back (lost)…');
SELECT throws_like(format($$SELECT market.finalize_market_sale(%L, 'ck88-fz8')$$, '00000000-0000-0000-0000-0000000000a8'), '%payment_charged_back%', 'J6b: …finalize can never move custody on returned money');
SELECT lives_ok(format($$SELECT market.on_atom_voided(%L, %L, 'refund_void')$$, tap._u153('a1'), gen_random_uuid()), 'J6c: the void hook runs…');
SELECT ok((SELECT s.terminal_state='compensated' FROM tap._sale153('00000000-0000-0000-0000-0000000000a8') s), 'J6d: …and compensates the charged-back sale (the chargeback IS the money return)');
UPDATE market.listing_native SET status='sold' WHERE listing_id = tap._u153('l2');
SELECT lives_ok(format($$SELECT market.on_atom_voided(%L, %L, 'refund_void')$$, tap._u153('a1'), gen_random_uuid()), 'J6: E-95 — a void of a COMPLETED sale''s atom does not raise…');
SELECT ok((SELECT s.terminal_state='completed' FROM tap._sale153(tap._u153('s1')) s), 'J7: …and never flips completed → compensated (C26 XOR holds)');
SELECT throws_like(format($$SELECT market.finalize_market_sale(%L, 'ck88-fz3')$$, tap._u153('s2b')), '%state_conflict%compensated%', 'J8: a compensated sale can never be completed');

-- ============================================================================
-- SECTION L — catalog.cancel_event (§4.4) on event2: authz, cascade, refunds
--   per order, E-102 skip, REQUIRED emits, re-entrancy
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store153('pol-e2', (catalog.set_resale_policy('event', tap._u153('event2'), '{"mode":"buy_now","price_cap_bps":10000}'::jsonb, 'ck88-pol-e2') ->> 'policy_id'));
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._store153('l5', (market.create_listing(tap._u153('a5'), 5000, 'buy_now', 'ck88-l5') ->> 'listing_id'));
SELECT tap.logout();
-- a PAID, untransferred resale of a5 (the P0 operand): fan153 paid pay8; the atom is about to be voided
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u153('l5');
SELECT tap._store153('pay8', tap._newpayment153(tap.fan153(), tap.other_user(), 5000, 'pi_88_8')::text);
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, payment_id, sale_state, paid_pending_since, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a6', tap._u153('l5'), tap._u153('a5'), tap.fan153(), tap.other_user(), 5000, tap._u153('pay8'), 'paid_pending_transfer', now(), 'ck88-s6');
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT catalog.cancel_event(%L, 'weather', 'ck88-ce-x')$$, tap._u153('event2')), '42501', NULL, 'L1: a fan cannot cancel an event');
SELECT tap.logout();
-- E-76: a venue_manager of a venue whose CURRENT operator is another org may not cancel
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES (tap._u153('venue1'), tap.fan153(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.other_user());
SELECT tap._store153('org2', (kernel.create_organization('Other Op','Other Op','ck88-o2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u153('org2');
UPDATE catalog.venue SET org_id = tap._u153('org2') WHERE venue_id = tap._u153('venue1');
SELECT tap.login(tap.fan153());
SELECT throws_ok(format($$SELECT catalog.cancel_event(%L, 'weather', 'ck88-ce-x2')$$, tap._u153('event2')), '42501', NULL,
  'L1a: E-76 — a venue_manager arm requires the venue''s CURRENT operator to be the event''s org (re-operated venue ⇒ refused)');
SELECT tap.logout();
UPDATE catalog.venue SET org_id = tap._u153('org1') WHERE venue_id = tap._u153('venue1');
SELECT tap.login(tap.fan153());
SELECT throws_like(format($$SELECT catalog.cancel_event(%L, 'bad reason!', 'ck88-ce-x3')$$, tap._u153('event2')), '%invalid_input%reason_code%', 'L1b: E-80 — a reason that lands in the audit is bounded');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store153('ce1', catalog.cancel_event(tap._u153('event2'), 'weather', 'ck88-ce1')::text);
SELECT tap.logout();
SELECT ok((tap._fetch153('ce1')::jsonb ->> 'status')='ok' AND (tap._fetch153('ce1')::jsonb ->> 'atoms_voided')::int=1 AND (tap._fetch153('ce1')::jsonb ->> 'refunds_created')::int=2 AND (tap._fetch153('ce1')::jsonb ->> 'atoms_skipped')::int=1,
  'L2: the org_owner cancels: 1 atom voided, TWO refunds created (the order''s buyer AND the resale buyer), 1 skipped (the comp mint — E-102)');
SELECT ok((SELECT r.reason_code='event_cancelled' AND r.amount_minor=5000 AND r.idempotency_key='ck88-ce1:sale:00000000-0000-0000-0000-0000000000a6' FROM kernel.refund r WHERE r.payment_id = tap._u153('pay8')),
  'L2a: P0 — the RESALE BUYER''s payment gets its own refund intent (one per paid sale, deterministic key)');
SELECT ok((SELECT s.terminal_state='compensated' FROM tap._sale153('00000000-0000-0000-0000-0000000000a6') s), 'L2b: …and the sale is compensated (compensated ⇔ refunded)');
SELECT is((SELECT count(*)::int FROM notify.outbox o WHERE o.event_type='refund_requested' AND o.aggregate_id = (SELECT r.refund_id FROM kernel.refund r WHERE r.payment_id = tap._u153('pay8'))), 1, 'L2c: refund_requested REQUIRED-emitted for it');
SELECT ok((SELECT r.reason_code='event_cancelled' AND r.amount_minor=5000 AND r.status='pending' AND r.idempotency_key='ck88-ce1:order:'||tap._fetch153('order2')
             FROM kernel.refund r WHERE r.payment_id = tap._u153('pay6')),
  'L3: ONE refund per originating order (amount = the voided item price; deterministic key)');
SELECT ok((SELECT t.state='voided' AND t.current_owner_id='00000000-0000-0000-0000-0000000000f0' FROM tap._atom153(tap._u153('a5')) t), 'L4: a5 voided to SN-VOID');
SELECT ok((SELECT l.cause='refund_void' AND l.cause_ref = (SELECT r.refund_id FROM kernel.refund r WHERE r.payment_id = tap._u153('pay6'))
             FROM kernel.ticket_ownership_log l WHERE l.ticket_atom_id = tap._u153('a5') AND l.sequence = 2),
  'L5: the void ledger row names the refund (refund_void, refund_id, atom)');
SELECT ok((SELECT l.status='cancelled' AND l.reason_code='event_cancelled' FROM tap._listing153(tap._u153('l5')) l), 'L6: the open listing is cancelled (reason event_cancelled) before the void');
SELECT ok((SELECT t.state='active' FROM tap._atom153(tap._u153('a6')) t) AND tap._audit153(tap._u153('a6'), 'event.cancel_skip', 'no_refund_lineage') = 1,
  'L7: E-102 — the comp atom (no refund lineage) is NOT voided and is audited');
SELECT ok((SELECT status='cancelled' FROM catalog.event WHERE event_id=tap._u153('event2')) AND (SELECT status='cancelled' FROM catalog.event_session WHERE session_id=tap._u153('session2')),
  'L8: event + session → cancelled');
SELECT is(tap._outbox153('event_cancelled', tap._u153('event2')), 1, 'L9: event_cancelled REQUIRED-emitted once');
SELECT is((SELECT count(*)::int FROM notify.outbox o WHERE o.event_type='refund_requested' AND o.aggregate_id = (SELECT r.refund_id FROM kernel.refund r WHERE r.payment_id = tap._u153('pay6'))), 1,
  'L10: refund_requested REQUIRED-emitted per refund');
SELECT is(tap._audit153(tap._u153('event2'), 'event.cancel', 'weather'), 1, 'L11: event.cancel audited');
SELECT tap.login(tap.seller());
SELECT is((catalog.cancel_event(tap._u153('event2'), 'weather', 'ck88-ce1') ->> 'status'), 'noop_replay', 'L12: a re-run is re-entrant: nothing left to void ⇒ noop_replay');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.refund r WHERE r.payment_id = tap._u153('pay6')), 1, 'L13: …and no second refund');
SELECT ok((SELECT sold = 0 FROM venue.inventory_batch WHERE batch_id = tap._u153('batch2')), 'L14: capacity returned (void_return)');
SELECT ok((SELECT position('inventory_batch b where b.event_session_id' in p.prosrc) < position('kernel.void_ticket_atom(' in p.prosrc)
              AND position('kernel.void_ticket_atom(' in p.prosrc) < position('insert into kernel.refund (refund_id' in p.prosrc)
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='catalog' AND p.proname='cancel_event'),
  'L15: §14.2 structural — Inventory (2) is locked before the atom voids (5), and the order refund row is inserted after them (6)');
SELECT ok((SELECT p.prosrc LIKE '%dispute_native d%lost%charge_refunded%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='catalog' AND p.proname='cancel_event'),
  'L16: E-102 — the §11.4 sum guard counts lost/charge_refunded disputes as money already returned');
SELECT ok((SELECT position('for share' in p.prosrc) < position('for update;' in p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='finalize_market_sale'),
  'L17: §20.8.10 structural — finalize takes Session FOR SHARE (1) before the Listing (4)');
SELECT ok((SELECT position('from market.market_sale ms where ms.sale_id = p_cause_ref for update' in p.prosrc) < position('from kernel.tickets t where t.ticket_atom_id = p_atom_id for update' in p.prosrc)
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='transfer_ticket_ownership'),
  'L18: §14.2 structural — the engine takes the Sale (4) before the Atom (5)');
-- the LAST act: cancel event1, whose payments were fully charged back — nothing is refunded twice
SELECT tap.login(tap.seller());
SELECT tap._store153('ce2', catalog.cancel_event(tap._u153('event1'), 'venue_closed', 'ck88-ce2')::text);
SELECT tap.logout();
SELECT ok((tap._fetch153('ce2')::jsonb ->> 'refunds_created')::int = 1 AND (tap._fetch153('ce2')::jsonb ->> 'atoms_voided')::int = 1,
  'L19: cancelling event1 — pay1 (lost 15000 = total) and pay7 (lost 5000 = total) refund NOTHING; the one refund/void is a1''s RESOLD arm');
SELECT ok(tap._audit153(tap._u153('order1'), 'event.cancel_skip', 'money_already_returned') = 1 AND tap._audit153(tap._u153('order3'), 'event.cancel_skip', 'money_already_returned') = 1,
  'L20: …each charged-back order is audited money_already_returned, its atoms left as they are (held / disputed)');
SELECT is((SELECT count(*)::int FROM kernel.refund r WHERE r.payment_id IN (tap._u153('pay1'), tap._u153('pay7'))), 0, 'L21: no refund intent on a charged-back payment (§12.3: the refund leg is satisfied by the chargeback)');
SELECT ok((SELECT r.amount_minor=5000 AND r.reason_code='event_cancelled' AND r.idempotency_key='ck88-ce2:sale:'||tap._fetch153('s1') FROM kernel.refund r WHERE r.payment_id = tap._u153('pay2')),
  'L21a: a1 was RESOLD (s1, completed): the refund goes to the LATEST native sale''s payer (fan153''s pay2), never to the reseller''s order');
SELECT ok((SELECT t.state='voided' FROM tap._atom153(tap._u153('a1')) t) AND (SELECT s.terminal_state='completed' FROM tap._sale153(tap._u153('s1')) s),
  'L21b: …the atom is voided against that refund; the completed sale is never flipped (E-95)');
SELECT ok((SELECT status='cancelled' FROM catalog.event WHERE event_id=tap._u153('event1')), 'L22: the event is still cancelled (the cascade is money-safe, not money-blind)');

-- ============================================================================
-- SECTION M — DELETION (BP-3 twin; the 16d erase allowance; composition)
-- ============================================================================
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000a9', tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), 5000, 'initiated', 'ck88-s9');
SELECT is(kernel.deletion_blockers_market(tap.fan153()), 'BP-3: unsettled native sale', 'M1: BP-3 — an in-flight native sale blocks its buyer');
DELETE FROM market.market_sale WHERE sale_id = '00000000-0000-0000-0000-0000000000a9';
SELECT is(kernel.deletion_blockers_market(tap.fan153()), NULL, 'M2: …cleared');
INSERT INTO market.listing_native (listing_id, ticket_atom_id, seller_id, event_session_id, listing_mode, price_minor, resale_policy_id, resale_policy_version, status, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000c002', tap._u153('a1'), tap.fan153(), tap._u153('session1'), 'buy_now', 5000, tap._u153('pol1'), 1, 'draft', 'ck88-seed-m');
INSERT INTO market.offer (offer_id, listing_id, buyer_id, amount_minor, status, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000f002', tap._u153('l2'), tap.fan153(), 3000, 'withdrawn', now()+interval '1 hour', 'ck88-o-m1'),
       ('00000000-0000-0000-0000-00000000f003', tap._u153('l2'), tap.other_user(), 3000, 'withdrawn', now()+interval '1 hour', 'ck88-o-m2');
SELECT lives_ok(format($$SELECT kernel.on_identity_erased_market(%L)$$, tap.fan153()), 'M3: the erase hook runs');
SELECT is((SELECT count(*)::int FROM market.listing_native WHERE listing_id='00000000-0000-0000-0000-00000000c002'), 0, 'M4: 16d — the never-sold (draft) listing is hard-deleted');
SELECT is((SELECT count(*)::int FROM market.offer WHERE offer_id='00000000-0000-0000-0000-00000000f002'), 0, 'M5: 16d — the erased identity''s non-accepted offer is hard-deleted');
SELECT ok((SELECT count(*)=1 FROM market.offer WHERE offer_id='00000000-0000-0000-0000-00000000f003') AND (SELECT count(*)=1 FROM market.market_sale WHERE sale_id=tap._u153('s1')),
  'M6: CUSTODY-DEL-1 — another identity''s offer and the consummated sale are RETAINED (never repointed)');
SELECT ok((SELECT p.prosrc LIKE '%kernel.deletion_blockers_market(%' AND p.prosrc LIKE '%kernel.on_identity_erased_market(%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='sweep_deletion_pending'),
  'M7: composition — the 077 deletion sweep calls BOTH market hooks (ODR-16 seam wired, no new caller)');

-- ============================================================================
-- SECTION P — the split CHECK is INTEGER and EXACT (PFA-30: proven without a policy)
-- ============================================================================
CREATE TABLE tap.split153 (price int, ok_exact boolean, rejected_off boolean);
DO $d$
DECLARE p int; ok1 boolean; rej boolean;
BEGIN
  FOREACH p IN ARRAY ARRAY[1,2,3,7,10,99,100,101,997,2147483647] LOOP
    BEGIN
      INSERT INTO market.market_sale (listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, platform_fee_minor, venue_royalty_minor, seller_proceeds_minor, sale_state, terminal_state, command_idempotency_key)
      VALUES (tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), p, p - (p/2), 0, p/2, 'settled', 'completed', 'ck88-split-ok-' || p::text);
      ok1 := true;
    EXCEPTION WHEN check_violation THEN ok1 := false; END;
    BEGIN
      INSERT INTO market.market_sale (listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, platform_fee_minor, venue_royalty_minor, seller_proceeds_minor, sale_state, terminal_state, command_idempotency_key)
      VALUES (tap._u153('l2'), tap._u153('a1'), tap.fan153(), tap.buyer(), p, p - (p/2), 0, p/2 - 1, 'settled', 'completed', 'ck88-split-off-' || p::text);
      rej := false;
    EXCEPTION WHEN check_violation THEN rej := true; END;
    INSERT INTO tap.split153 VALUES (p, ok1, rej);
  END LOOP;
END $d$;
SELECT ok((SELECT bool_and(ok_exact) FROM tap.split153), 'P1: an EXACT integer split sums for every adversarial total (1,2,3,7,10,99,100,101,997,max)');
SELECT ok((SELECT bool_and(rejected_off) FROM tap.split153), 'P2: a split off by ONE minor unit is rejected for every total (no float, no residual leaves the triple)');
SELECT throws_ok(format($$UPDATE market.market_sale SET platform_fee_minor=-1, venue_royalty_minor=1, seller_proceeds_minor=5000 WHERE sale_id=%L$$, tap._u153('s1')), '23514', NULL,
  'P3: a negative component is unstorable');
SELECT throws_ok(format($$UPDATE market.market_sale SET platform_fee_minor=NULL WHERE sale_id=%L$$, tap._u153('s1')), '23514', NULL,
  'P4: a PARTIAL split (one NULL) is unstorable — all three or none');

-- ============================================================================
-- SECTION N — preserved rulings / byte facts
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE (n.nspname='market' OR (n.nspname='kernel' AND p.proname IN ('transfer_ticket_ownership','record_dispute_native','mark_dispute_state','resolve_dispute_native','settlement_royalty_lines','unlock_ticket','deletion_blockers_market','on_identity_erased_market')) OR (n.nspname='catalog' AND p.proname='cancel_event'))
              AND p.prosrc ~* 'pgcrypto|hmac\(|digest\(|gen_salt|pgp_sym'), 0,
  'N1: PFA-28 preserved — no 088 routine touches a pgcrypto symbol');
SELECT ok((SELECT bool_and(p.prosecdef AND coalesce(array_to_string(p.proconfig, ','), '') LIKE '%search_path=%')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='market' OR (n.nspname='kernel' AND p.proname IN ('transfer_ticket_ownership','record_dispute_native','mark_dispute_state','resolve_dispute_native')) OR (n.nspname='catalog' AND p.proname='cancel_event')),
  'N2: every 088 routine is SECURITY DEFINER with search_path pinned');
SELECT ok((SELECT p.prosrc !~* 'numeric|float|double|real' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='catalog' AND p.proname='cancel_event')
       AND (SELECT p.prosrc !~* 'numeric|float|double|real' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND p.proname='create_listing'),
  'N3: integer minor units in the refund and cap arithmetic (no float/numeric)');
SELECT is((SELECT count(*)::int FROM kernel.approval_request ar WHERE ar.subject_kind ILIKE '%dispute%' OR ar.action ILIKE '%dispute%'), 0,
  'N4: PFA-31 — no approval_request row names a dispute (no shadow approval, no overloaded action)');

SELECT * FROM finish();
ROLLBACK;
