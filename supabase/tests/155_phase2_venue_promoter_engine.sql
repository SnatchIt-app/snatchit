-- ============================================================================
-- 155_phase2_venue_promoter_engine.sql — Phase-2 package 090 suite.
-- Frozen sources: plan §8/090 · schema §3.17/§3.17.1/§3.17.2/§3.14.1 ·
-- PROMOTER_CODES_SPEC §1–§10/§12 · RPC §1.1c/§17.14–§17.19/§20.7.2/§20.9.1–5/
-- §20.11.2/§20.11.4/§20.17.5 · RLS §9.17 (AUTHZ-M9/M10)/§11.5/§11.8/§17 X-13 ·
-- OR-13 (ODR-16 INV #35–#38) · OR-17 F-7 · OR-14 · G-25 #31/#32 · E-73/E-80/
-- E-104 · E-120..E-131 (090 errata). The promoter engine ships INERT: no config
-- key, no cron, no client bytes; every path here runs under ROLLBACK.
-- BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(366);   -- 2026-09-02 (package 093): 363 -> 366 (+G10c, the org settlement payout minted once net turns positive under ruling A3/A5; +G41c/+G41d, ruling A4's partially_refunded commission exclusion)

SELECT tap.seed_core();

CREATE TABLE tap.memo_155 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store155(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_155 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch155(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_155 WHERE k=$1 $m$;
CREATE FUNCTION tap._u155(k text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_155 WHERE k=$1 $m$;
CREATE FUNCTION tap._audit155(p_subject uuid, p_action text, p_reason text DEFAULT NULL) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = p_subject AND a.action = p_action AND (p_reason IS NULL OR a.reason_code = p_reason) $m$;
CREATE FUNCTION tap._outbox155(p_type text, p_agg uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM notify.outbox o WHERE o.event_type = p_type AND o.aggregate_id = p_agg $m$;
CREATE FUNCTION tap._attr155(p_order uuid) RETURNS venue.attribution LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT a FROM venue.attribution a WHERE a.order_id = p_order $m$;
CREATE FUNCTION tap._attrcount155(p_order uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM venue.attribution a WHERE a.order_id = p_order $m$;
CREATE FUNCTION tap._lines155(p_settlement uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM venue.settlement_line l WHERE l.settlement_id = p_settlement AND l.cause = 'promoter_commission' $m$;
CREATE FUNCTION tap._line155(p_attr uuid) RETURNS venue.settlement_line LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT l FROM venue.settlement_line l WHERE l.cause = 'promoter_commission' AND l.cause_ref = p_attr $m$;
CREATE FUNCTION tap._payout155(p_attr uuid) RETURNS kernel.payout LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT po FROM kernel.payout po WHERE po.cause = 'promoter_commission' AND po.cause_ref = p_attr $m$;
CREATE FUNCTION tap._cfg155(p_key text, p_val jsonb, p_vis text DEFAULT 'restricted') RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.platform_config (key, version, value, visibility)
    SELECT p_key, coalesce(max(version),0)+1, p_val, p_vis FROM catalog.platform_config WHERE key = p_key $m$;
CREATE FUNCTION tap._newpayment155(p_buyer uuid, p_seller uuid, p_total int, p_pi text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ WITH l AS (INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                 starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
               VALUES (p_seller, 'Promo Night ' || gen_random_uuid()::text, 'Promo Hall', 'wynwood', (now()+interval '15 days')::date, '20:00', 'GA', 2,
                 'mobile_transfer', 5000, 5000, 24, now()+interval '1 day', 'covers/fixture.jpg') RETURNING id)
    INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
    SELECT id, p_buyer, p_seller, (p_total * 9) / 10, p_total - (p_total * 9) / 10, p_total, 'succeeded', 'buy_now', p_pi FROM l RETURNING id $m$;
-- a pending order with one item + a live hold (the shape finalize_primary_order consumes)
CREATE FUNCTION tap._neworder155(p_key text, p_buyer uuid, p_session uuid, p_org uuid, p_tt uuid, p_batch uuid, p_qty int, p_unit int, p_source text DEFAULT 'web') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
declare v_o uuid;
begin
  insert into venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  values (p_buyer, p_session, p_org, 'pending', p_source, p_qty * p_unit, 'ck90-ord-' || p_key) returning order_id into v_o;
  insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) values (v_o, p_tt, p_qty, p_unit);
  insert into venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch, p_buyer, p_qty, 'active', now() + interval '1 hour', 'ck90-h-' || p_key);
  update venue.inventory_batch set held = held + p_qty where batch_id = p_batch;
  perform tap._store155(p_key, v_o::text);
  return v_o;
end $m$;
-- direct candidate binding as table owner (the 082 columns; used where the RPC's advisory
-- eligibility filter would refuse a deliberately-ineligible candidate)
CREATE FUNCTION tap._setcand155(p_order uuid, p_code uuid, p_link uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ UPDATE venue."order" SET attribution_candidate_code_id = p_code, attribution_candidate_link_id = p_link WHERE order_id = p_order $m$;
CREATE FUNCTION tap._resetlimit155(p_uid uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ DELETE FROM public.rate_limits r WHERE r.user_id = p_uid $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- personas: promoter P (other_user), promoter Q (fan155), a rival org's owner (fan2), a promoter-manager (pm155), a risk operator
CREATE FUNCTION tap.fan155()  RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '55555555-5555-5555-5555-555555555555'::uuid $$;
CREATE FUNCTION tap.fan2155() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '56565656-5656-5656-5656-565656565656'::uuid $$;
CREATE FUNCTION tap.pm155()   RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '57575757-5757-5757-5757-575757575757'::uuid $$;
CREATE FUNCTION tap.risk155() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '66666666-6666-6666-6666-666666666666'::uuid $$;
CREATE FUNCTION tap.buyer2155() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '58585858-5858-5858-5858-585858585858'::uuid $$;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (tap.fan155(),  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan155@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.fan2155(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan2155@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.pm155(),   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pm155@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.risk155(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'risk155@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.buyer2155(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'buyer2155@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;
UPDATE public.profiles SET display_name = 'Jordy Q' WHERE id = tap.fan155();
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.risk155(), 'platform_risk', tap.admin_user());

-- ============================================================================
-- FIXTURE — org1 (seller owner) → venue1 → event1/session1 (tt1 5000, batch1) and
--   event2/session2 (tt2 4000, batch2); org2 (fan2 owner) → venue2 → event3.
--   Promoter P (other_user, 10% bps) org-wide; promoter Q (fan155, flat 300/ticket)
--   single-event (event1); affiliate A (no identity). Codes: JORDY (P), QCODE (Q,
--   scoped event1), P2 generated. Links: jordy-night (P, event1), q-night (Q, event1).
--   pm155 = venue_promoter_manager at venue1; admin_user = org_finance (matured).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store155('org1', (kernel.create_organization('Promo Co','Promo Co','ck90-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u155('org1');
SELECT tap.login(tap.seller());
SELECT tap._store155('venue1', (catalog.create_venue(tap._u155('org1'),'Promo Hall','wynwood',NULL,'ck90-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._u155('venue1'),'approved','miami_gate','ck90-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store155('event1', (catalog.create_event(tap._u155('venue1'),'Promo Night',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck90-e1') ->> 'event_id'));
SELECT tap._store155('session1', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u155('event1')));
SELECT tap._store155('tt1', (venue.create_ticket_type(tap._u155('event1'),'admission','GA',5000,'public','ck90-tt1') ->> 'ticket_type_id'));
SELECT tap._store155('batch1', (venue.create_inventory_batch(tap._u155('tt1'), tap._u155('session1'), 'public_sale', 100, 0, 'ck90-b1') ->> 'batch_id'));
SELECT tap._store155('event2', (catalog.create_event(tap._u155('venue1'),'Promo Night II',
  jsonb_build_object('starts_at',(now()+interval '20 days')::text,'ends_at',(now()+interval '20 days 4 hours')::text),'ck90-e2') ->> 'event_id'));
SELECT tap._store155('session2', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u155('event2')));
SELECT tap._store155('tt2', (venue.create_ticket_type(tap._u155('event2'),'admission','GA',4000,'public','ck90-tt2') ->> 'ticket_type_id'));
SELECT tap._store155('batch2', (venue.create_inventory_batch(tap._u155('tt2'), tap._u155('session2'), 'public_sale', 100, 0, 'ck90-b2') ->> 'batch_id'));
SELECT tap.logout();
SELECT tap.login(tap.fan2155());
SELECT tap._store155('org2', (kernel.create_organization('Rival Co','Rival Co','ck90-o2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u155('org2');
SELECT tap.login(tap.fan2155());
SELECT tap._store155('venue2', (catalog.create_venue(tap._u155('org2'),'Rival Hall','brickell',NULL,'ck90-v2') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._u155('venue2'),'approved','miami_gate','ck90-a2');
SELECT tap.logout();
SELECT tap.login(tap.fan2155());
SELECT tap._store155('event3', (catalog.create_event(tap._u155('venue2'),'Rival Night',
  jsonb_build_object('starts_at',(now()+interval '11 days')::text,'ends_at',(now()+interval '11 days 4 hours')::text),'ck90-e3') ->> 'event_id'));
SELECT tap._store155('session3', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u155('event3')));
SELECT tap.logout();
-- roles + maturity + flags + keys (direct fixture writes as table owner)
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._u155('org1'), tap.admin_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id IN (tap._u155('org1'), tap._u155('org2'));
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES (tap._u155('venue1'), tap.pm155(), 'venue_promoter_manager', tap.seller());
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES (tap._u155('venue1'), tap.buyer2155(), 'venue_box_office', tap.seller());
SELECT tap._cfg155('authn.money_role_maturity_hours', '24'::jsonb);
SELECT tap._cfg155('feature.native_issuance_enabled', 'true'::jsonb);
INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
VALUES ('per_event', tap._u155('event1'), 'PUBKEY-90-1', 'kms-90-1', 'active', now()), ('per_event', tap._u155('event2'), 'PUBKEY-90-2', 'kms-90-2', 'active', now());
-- promoters / codes / links (seller = org_owner issues)
SELECT tap.login(tap.seller());
SELECT tap._store155('promP', (venue.create_promoter(tap._u155('org1'), tap.other_user()::text, '{"commission_kind":"bps","commission_bps":1000}', 'ck90-pP') ->> 'promoter_id'));
SELECT tap._store155('promQ', (venue.create_promoter(tap._u155('org1'), 'fan155@test.local', jsonb_build_object('commission_kind','flat_per_ticket','commission_flat_minor',300,'event_id',tap._u155('event1')), 'ck90-pQ') ->> 'promoter_id'));
SELECT tap._store155('promA', (venue.create_promoter(tap._u155('org1'), NULL, '{"party_kind":"affiliate","commission_kind":"bps","commission_bps":500}', 'ck90-pA') ->> 'promoter_id'));
SELECT tap._store155('codeP', (venue.create_promoter_code(tap._u155('promP'), 'JORDY', NULL, NULL, NULL, 'vanity', 'ck90-cP') ->> 'code_id'));
SELECT tap._store155('codeQ', (venue.create_promoter_code(tap._u155('promQ'), 'QCODE', ARRAY[tap._u155('event1')], NULL, NULL, 'vanity', 'ck90-cQ') ->> 'code_id'));
SELECT tap._store155('codeA', (venue.create_promoter_code(tap._u155('promA'), 'AFFIL', NULL, NULL, NULL, 'vanity', 'ck90-cA') ->> 'code_id'));
SELECT tap._store155('linkP', (venue.create_promoter_link(tap._u155('promP'), tap._u155('event1'), 'jordy-night', 'ck90-lP') ->> 'link_id'));
SELECT tap._store155('linkQ', (venue.create_promoter_link(tap._u155('promQ'), tap._u155('event1'), 'q-night', 'ck90-lQ') ->> 'link_id'));
SELECT tap.logout();

-- ============================================================================
-- SECTION A — THE 090 CLOSED WORLD (plan §8/090; parity EXTRA = 0, MISSING = 0)
-- ============================================================================
SELECT has_table('venue'::name,'promoter'::name, 'A1: venue.promoter');
SELECT has_table('venue'::name,'promoter_link'::name, 'A2: venue.promoter_link');
SELECT has_table('venue'::name,'promoter_code'::name, 'A3: venue.promoter_code');
SELECT has_table('venue'::name,'promoter_code_scope'::name, 'A4: venue.promoter_code_scope');
SELECT has_table('venue'::name,'attribution'::name, 'A5: venue.attribution (AO)');
SELECT has_table('venue'::name,'attribution_review'::name, 'A6: venue.attribution_review (AO)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname IN (
  'normalize_promoter_code','create_promoter','update_promoter','create_promoter_link','set_promoter_link_status','check_promoter_slug_available',
  'create_promoter_code','create_promoter_codes_bulk','set_promoter_code_status','set_promoter_code_scope','set_promoter_code_window',
  'preview_promoter_code','bind_order_attribution','review_attribution_flag','get_my_promoter_summary','list_my_attributions','list_promoter_attributions',
  'guard_promoter_engine_immutable','assert_promoter_engine_consistency')), 19,
  'A7: venue holds EXACTLY the nineteen 090 routines (17 RPCs/reads + the normalizer + 2 trigger fns) — each once');
SELECT has_function('kernel'::name,'is_promoter_for_event'::name, ARRAY['uuid']::name[], 'A8: kernel.is_promoter_for_event (§1.1c)');
SELECT has_function('kernel'::name,'pay_promoter_commission'::name, ARRAY['uuid','uuid[]','text']::name[], 'A9: kernel.pay_promoter_commission (§20.7.2 — authored HERE, SEAM-1)');
-- SEAM-2a: the three body-only replacements keep their frozen signatures, one overload each
SELECT ok((SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='resolve_order_attribution')
       AND (SELECT p.proargnames = ARRAY['p_order_id'] AND p.prorettype='void'::regtype AND btrim(p.prosrc) <> 'select' AND p.prosrc LIKE '%code_over_link%'
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='resolve_order_attribution'),
  'A10: T-SCHEMA-SEAM-04 — resolve_order_attribution: ONE overload, (p_order_id) RETURNS void frozen from 085, body REAL (the precedence table)');
SELECT ok((SELECT p.prosrc !~ '\m(v_[a-z_]+)\s+record\M' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='resolve_order_attribution'),
  'A10b: the resolver declares NO record variable — a record never assigned in a session cannot be type-resolved on first use, and the never-raise rule would swallow it (race harness finding; scalars only)');
SELECT ok((SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_commission_lines')
       AND (SELECT p.proargnames = ARRAY['p_settlement_id'] AND p.proretset AND p.prorettype='kernel.settlement_line_candidate'::regtype AND p.provolatile='v'
                   AND p.prosrc LIKE '%pg_advisory_xact_lock%' AND p.prosrc LIKE '%pay_promoter_commission%'
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_commission_lines'),
  'A11: settlement_commission_lines: ONE overload, signature frozen from 087; VOLATILE + per-org xact advisory lock (E-104); reaches pay_promoter_commission');
SELECT ok((SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_promoter')
       AND (SELECT p.proargnames = ARRAY['p_identity'] AND p.prorettype='void'::regtype AND p.prosrc LIKE '%status_changed_by%'
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_promoter'),
  'A12: on_identity_erased_promoter: ONE overload, (p_identity) RETURNS void frozen from 077; body = INV #36 SET NULL');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('deletion_blockers_custody','deletion_blockers_orders','deletion_blockers_wallet','deletion_blockers_money',
              'deletion_blockers_market','on_identity_erased_staff','on_identity_erased_door','on_identity_erased_market','on_identity_erased_promoter',
              'has_outstanding_obligations','on_deletion_q5_release','settlement_royalty_lines','settlement_commission_lines')
            ) + (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE (n.nspname,p.proname) IN (('venue','resolve_order_attribution'),('venue','on_payout_settled'),('market','on_atom_voided'),
              ('market','on_door_freeze_engaged'),('market','door_freeze_drain_preview'),('venue','append_door_manifest_delta'))), 19,
  'A13: the SEAM register still counts 13 + 6 = 19 hooks (no hook added, none removed)');
SELECT ok((SELECT p.provolatile='i' AND p.proisstrict FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='normalize_promoter_code'),
  'A14: normalize_promoter_code is IMMUTABLE STRICT (a generated column and a unique index depend on it)');
SELECT is((SELECT a.attgenerated FROM pg_attribute a WHERE a.attrelid='venue.promoter_code'::regclass AND a.attname='code_normalized'), 's',
  'A15: code_normalized is GENERATED ALWAYS … STORED');
-- money constraint + adopted FKs
SELECT ok((SELECT count(*)=1 FROM pg_indexes WHERE schemaname='venue' AND tablename='settlement_line' AND indexname='attribution_one_commission_line_ever'
            AND indexdef LIKE 'CREATE UNIQUE INDEX%' AND indexdef LIKE '%(cause_ref)%' AND indexdef LIKE '%promoter_commission%'),
  'A16: §3.14.1 / §4.2(2) — UNIQUE INDEX ON venue.settlement_line (cause_ref) WHERE cause = ''promoter_commission''');
SELECT ok((SELECT bool_and(c.convalidated AND c.confdeltype='r' AND NOT c.condeferrable) FROM pg_constraint c
            WHERE c.conrelid='venue."order"'::regclass AND c.conname IN ('fk_order_attr_cand_code','fk_order_attr_cand_link'))
       AND (SELECT count(*)=2 FROM pg_constraint c WHERE c.conrelid='venue."order"'::regclass AND c.conname IN ('fk_order_attr_cand_code','fk_order_attr_cand_link')),
  'A17: the two candidate FKs are ADOPTED: RESTRICT, VALIDATED, not deferrable (NOT VALID → VALIDATE)');
SELECT ok((SELECT c.confrelid='venue.promoter_code'::regclass FROM pg_constraint c WHERE c.conname='fk_order_attr_cand_code')
       AND (SELECT c.confrelid='venue.promoter_link'::regclass FROM pg_constraint c WHERE c.conname='fk_order_attr_cand_link'),
  'A18: …pointing at promoter_code / promoter_link respectively');
SELECT col_is_unique('venue'::name,'attribution'::name, ARRAY['order_id']::name[], 'A19: attribution UNIQUE(order_id) — §4.2(1)');
SELECT col_is_unique('venue'::name,'promoter_link'::name, ARRAY['slug']::name[], 'A20: promoter_link UNIQUE(slug) — GLOBAL');
SELECT col_is_unique('venue'::name,'promoter_code'::name, ARRAY['code_normalized']::name[], 'A21: promoter_code UNIQUE(code_normalized) — GLOBAL');
SELECT col_is_unique('venue'::name,'attribution_review'::name, ARRAY['attribution_id','seq']::name[], 'A22: attribution_review UNIQUE(attribution_id, seq)');
SELECT is((SELECT count(*)::int FROM pg_indexes WHERE schemaname='venue' AND indexname IN ('attribution_promoter_paid_idx','attribution_org_event_paid_idx',
            'attribution_code_idx','attribution_link_idx','attribution_self_deal_idx','promoter_code_promoter_status_idx','promoter_code_org_status_created_idx',
            'promoter_code_normalized_pattern_idx','promoter_link_promoter_active_idx','promoter_code_scope_event_idx')), 10,
  'A23: the §10.3/§10.4/§10.5 index set is present by name (the partials included)');
SELECT ok((SELECT indexdef LIKE '%WHERE (self_deal_flag)%' OR indexdef LIKE '%WHERE self_deal_flag%' FROM pg_indexes WHERE indexname='attribution_self_deal_idx')
       AND (SELECT indexdef LIKE '%text_pattern_ops%' FROM pg_indexes WHERE indexname='promoter_code_normalized_pattern_idx')
       AND (SELECT indexdef LIKE '%status = ''active''%' FROM pg_indexes WHERE indexname='promoter_link_promoter_active_idx'),
  'A24: the self-deal queue index is partial; the confusable index is text_pattern_ops; the live-links index is partial on status');
SELECT is((SELECT count(*)::int FROM pg_constraint c WHERE c.conrelid='venue.promoter'::regclass AND c.conname IN ('promoter_terms_xor_ck','promoter_identity_for_promoter_ck')), 2,
  'A25: §3.17.1 XOR CHECK + the affiliate-only NULL identity CHECK');
SELECT is((SELECT count(*)::int FROM pg_constraint c WHERE c.conrelid='venue.promoter_code'::regclass AND c.conname IN ('promoter_code_window_ck','promoter_code_length_ck','promoter_code_alphabet_ck')), 3,
  'A26: §1.1 window / length / Crockford-alphabet CHECKs');
SELECT is((SELECT count(*)::int FROM pg_constraint c WHERE c.conrelid='venue.attribution'::regclass AND c.conname IN ('attribution_method_ck','attribution_terms_xor_ck')), 2,
  'A27: attribution method↔column CHECK + applied-terms XOR CHECK');
-- triggers
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
            WHERE n.nspname='venue' AND c.relname IN ('attribution','attribution_review','promoter_code_scope') AND p.proname='raise_append_only' AND NOT t.tgisinternal), 3,
  'A28: raise_append_only guards attribution (UPD/DEL), attribution_review (UPD/DEL) and scope rows (UPD)');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
            WHERE n.nspname='venue' AND c.relname IN ('promoter_link','promoter_code') AND p.proname='guard_promoter_engine_immutable' AND NOT t.tgisinternal), 2,
  'A29: the immutability guard sits on promoter_link (PL-1) and promoter_code (no reassignment)');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
            WHERE n.nspname='venue' AND p.proname='assert_promoter_engine_consistency' AND NOT t.tgisinternal), 5,
  'A30: org/event/order consistency asserted on promoter, promoter_link, promoter_code, promoter_code_scope, attribution');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
            WHERE n.nspname='venue' AND c.relname IN ('promoter','promoter_link','promoter_code') AND p.proname='set_updated_at' AND NOT t.tgisinternal), 3,
  'A31: set_updated_at on promoter, promoter_link, promoter_code (R-35 census)');
-- inert: no cron, no config key, no edge bytes here
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname ILIKE '%promoter%' OR jobname ILIKE '%attribution%' OR jobname ILIKE '%commission%'), 0, 'A32: 090 schedules NO cron row');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key ILIKE '%promoter%' OR key ILIKE '%commission%' OR key ILIKE '%attribution%'), 0, 'A33: PFA-9 — 090 fabricates NO config key');

-- ============================================================================
-- SECTION B — GRANTS, RLS, EXEC POSTURE (RLS §9.17 AUTHZ-M9 / §11.5 / PFA-1)
-- ============================================================================
SELECT ok(has_table_privilege('authenticated','venue.promoter','SELECT') AND has_table_privilege('authenticated','venue.promoter_link','SELECT')
       AND has_table_privilege('authenticated','venue.promoter_code','SELECT') AND has_table_privilege('authenticated','venue.promoter_code_scope','SELECT'),
  'B1: promoter / link / code / scope are policy-gated reads for authenticated');
SELECT ok(NOT has_table_privilege('authenticated','venue.attribution','SELECT') AND NOT has_table_privilege('authenticated','venue.attribution_review','SELECT'),
  'B2: AUTHZ-M9 — attribution and attribution_review carry NO client SELECT (every read is an RPC projection)');
SELECT is((SELECT count(*)::int FROM information_schema.role_column_grants g WHERE g.grantee='authenticated' AND g.table_schema='venue' AND g.table_name IN ('attribution','attribution_review')), 0,
  'B3: T-RLS-ATTR-06 — authenticated holds ZERO role_column_grants rows on venue.attribution / attribution_review');
SELECT ok((SELECT bool_and(NOT has_table_privilege('anon', 'venue.'||t, 'SELECT') AND NOT has_table_privilege('service_role', 'venue.'||t, 'SELECT')
                       AND NOT has_table_privilege('authenticated', 'venue.'||t, 'INSERT') AND NOT has_table_privilege('authenticated', 'venue.'||t, 'UPDATE')
                       AND NOT has_table_privilege('authenticated', 'venue.'||t, 'DELETE'))
             FROM unnest(ARRAY['promoter','promoter_link','promoter_code','promoter_code_scope','attribution','attribution_review']) t),
  'B4: anon / service_role hold NO table grant on the six tables; authenticated holds no INSERT/UPDATE/DELETE anywhere (GP-1/GP-2)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relname IN ('promoter','promoter_link','promoter_code','promoter_code_scope')), 10,
  'B5: ten read policies (3 + 3 + 3 + 1) — org back office / venue staff / the promoter''s OWN rows');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relname IN ('promoter','promoter_link','promoter_code','promoter_code_scope','attribution','attribution_review') AND p.polcmd <> 'r'), 0,
  'B6: every 090 policy is SELECT-only; attribution / attribution_review carry ZERO policies (deny-all)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relname IN ('promoter','promoter_link','promoter_code','promoter_code_scope','attribution','attribution_review')
              AND pg_get_expr(p.polqual, p.polrelid) ~ 'promoter_id\s*=\s*auth\.uid\(\)'), 0,
  'B7: T-RLS-ATTR-05 (AUTHZ-M10) — no policy compares promoter_id = auth.uid()');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('venue','kernel')
            AND p.prosrc ~ 'promoter_id\s*=\s*auth\.uid\(\)'), 0,
  'B8: T-RPC-AUTHZ-10 — no venue/kernel function body contains promoter_id = auth.uid()');
SELECT ok((SELECT bool_and(has_function_privilege('authenticated', f, 'EXECUTE') AND NOT has_function_privilege('anon', f, 'EXECUTE') AND NOT has_function_privilege('service_role', f, 'EXECUTE'))
  FROM unnest(ARRAY['venue.create_promoter(uuid,text,jsonb,text)','venue.update_promoter(uuid,jsonb,text,text)','venue.create_promoter_link(uuid,uuid,text,text)',
    'venue.set_promoter_link_status(uuid,text,text,text)','venue.check_promoter_slug_available(text)',
    'venue.create_promoter_code(uuid,text,uuid[],timestamptz,timestamptz,text,text)','venue.create_promoter_codes_bulk(uuid,integer,text,uuid[],timestamptz,timestamptz,text)',
    'venue.set_promoter_code_status(uuid,text,text)','venue.set_promoter_code_scope(uuid,uuid[],uuid[],text)','venue.set_promoter_code_window(uuid,timestamptz,timestamptz,text)',
    'venue.bind_order_attribution(uuid,text,text,text)','venue.review_attribution_flag(uuid,text,text,text,text)',
    'venue.get_my_promoter_summary(uuid,uuid,jsonb)','venue.list_my_attributions(uuid,jsonb,jsonb)','venue.list_promoter_attributions(text,uuid,jsonb,jsonb)',
    'kernel.is_promoter_for_event(uuid)']) f),
  'B9: the fifteen caller-authorized verbs/reads + is_promoter_for_event are authenticated-only (in-body authz) — never anon, never service_role');
SELECT ok(has_function_privilege('authenticated','venue.preview_promoter_code(text,uuid)','EXECUTE') AND has_function_privilege('service_role','venue.preview_promoter_code(text,uuid)','EXECUTE')
       AND NOT has_function_privilege('anon','venue.preview_promoter_code(text,uuid)','EXECUTE'),
  'B10: preview_promoter_code: authenticated + service_role (the edge wrapper''s unauthenticated path) — never anon (§11.5/§11.8)');
SELECT ok(NOT has_function_privilege('authenticated','kernel.pay_promoter_commission(uuid,uuid[],text)','EXECUTE') AND NOT has_function_privilege('anon','kernel.pay_promoter_commission(uuid,uuid[],text)','EXECUTE')
       AND NOT has_function_privilege('service_role','kernel.pay_promoter_commission(uuid,uuid[],text)','EXECUTE'),
  'B11: pay_promoter_commission is EXEC DEF — definer-internal, no client or machine grant (087''s seam treatment; E-129)');
SELECT ok(NOT has_function_privilege('authenticated','venue.resolve_order_attribution(uuid)','EXECUTE') AND NOT has_function_privilege('anon','venue.resolve_order_attribution(uuid)','EXECUTE'),
  'B12: T-RPC-PROMO §12.57 — the resolver has NO EXECUTE for anon or authenticated (085''s revoke survives the body replace)');
SELECT ok(NOT has_function_privilege('authenticated','venue.normalize_promoter_code(text)','EXECUTE') AND NOT has_function_privilege('anon','venue.normalize_promoter_code(text)','EXECUTE'),
  'B13: the normalizer holds no client grant (the client reimplements the pure ASCII fold)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE a.privilege_type='EXECUTE' AND n.nspname IN ('venue','kernel')
              AND p.proname IN ('normalize_promoter_code','create_promoter','update_promoter','create_promoter_link','set_promoter_link_status','check_promoter_slug_available',
                'create_promoter_code','create_promoter_codes_bulk','set_promoter_code_status','set_promoter_code_scope','set_promoter_code_window','preview_promoter_code',
                'bind_order_attribution','review_attribution_flag','get_my_promoter_summary','list_my_attributions','list_promoter_attributions',
                'guard_promoter_engine_immutable','assert_promoter_engine_consistency','is_promoter_for_event','pay_promoter_commission',
                'resolve_order_attribution','settlement_commission_lines','on_identity_erased_promoter')
              AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname='anon'))), 0,
  'B14: PFA-1 sweep — zero PUBLIC/anon EXECUTE on any of the twenty-four 090 routines/hooks');
SELECT ok((SELECT bool_and(p.prosecdef AND p.proconfig::text LIKE '%search_path=%') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('venue','kernel') AND p.proname IN ('create_promoter','update_promoter','create_promoter_link','set_promoter_link_status','check_promoter_slug_available',
                'create_promoter_code','create_promoter_codes_bulk','set_promoter_code_status','set_promoter_code_scope','set_promoter_code_window','preview_promoter_code',
                'bind_order_attribution','review_attribution_flag','get_my_promoter_summary','list_my_attributions','list_promoter_attributions','is_promoter_for_event',
                'pay_promoter_commission','resolve_order_attribution','settlement_commission_lines','on_identity_erased_promoter')),
  'B15: every 090 RPC/hook is SECURITY DEFINER with search_path pinned');
SELECT ok((SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='review_attribution_flag' AND p.prosrc ~ 'insert into venue\.attribution_review')
       AND (SELECT count(*)=0 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('venue','kernel','market','catalog') AND p.proname <> 'review_attribution_flag' AND p.prosrc ~ 'insert into venue\.attribution_review'),
  'B16: T-RPC-AUTHZ-09 — exactly ONE function writes venue.attribution_review');
SELECT ok((SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('venue','kernel','market','catalog') AND p.prosrc ~ 'insert into venue\.attribution\s*\(')
       AND (SELECT p.proname='resolve_order_attribution' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('venue','kernel','market','catalog') AND p.prosrc ~ 'insert into venue\.attribution\s*\('),
  'B17: the resolver is the SOLE writer of venue.attribution (writer fence)');
SELECT ok((SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('venue','kernel','market','catalog') AND p.prosrc ~ 'promoter_commission'' *,' AND p.prosrc ~ 'insert into kernel\.payout')
       AND (SELECT p.proname='pay_promoter_commission' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('venue','kernel','market','catalog') AND p.prosrc ~ 'promoter_commission'' *,' AND p.prosrc ~ 'insert into kernel\.payout'),
  'B18: pay_promoter_commission is the ONLY minter of a promoter_commission payout (writer fence)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='create_promoter'
            AND (p.prosrc ~ 'venue\.staff_role' OR p.prosrc ~ 'kernel\.org_member' OR p.prosrc ~ 'kernel\.platform_role')), 0,
  'B19: T-RPC-PROMO-12 — create_promoter writes/reads none of the three authz tables (a promoter is not a role)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='pay_promoter_commission'
            AND (p.prosrc ~ 'net\.http' OR p.prosrc ~ 'stripe' OR p.prosrc ~ 'insert into venue\.settlement_line')), 0,
  'B20: T-RPC-MONEY-18 — pay_promoter_commission performs no external I/O and does not itself insert lines (087''s close inserts the candidates it returns)');

-- ============================================================================
-- SECTION C — NORMALIZATION, UNIQUENESS, IMMUTABILITY (PROMOTER §1.1/§1.3/§10.2; §12 A/B)
-- ============================================================================
SELECT ok(venue.normalize_promoter_code('JORDY') = 'J0RDY' AND venue.normalize_promoter_code('jordy') = 'J0RDY'
       AND venue.normalize_promoter_code('J0RDY') = 'J0RDY' AND venue.normalize_promoter_code('J-0-R-D-Y ') = 'J0RDY' AND venue.normalize_promoter_code(' j o r d y') = 'J0RDY',
  'C1: JORDY / jordy / J0RDY / J-0-R-D-Y  / " j o r d y" all normalize to J0RDY');
SELECT is(venue.normalize_promoter_code(E'J​O‍RDY\U0001F389'), 'J0RDY', 'C2: zero-width joiners and emoji are stripped before the fold');
SELECT is(venue.normalize_promoter_code('ILLo1'), '11101', 'C3: the Crockford fold: I→1, L→1, O→0 (case-insensitive)');
SELECT is(venue.normalize_promoter_code(NULL), NULL, 'C4: STRICT — NULL in, NULL out');
SELECT ok(venue.normalize_promoter_code(repeat('ÜñÎçødé-🎫', 5)) ~ '^[0-9A-Z]*$', 'C5: any input lands inside [0-9A-Z] (fuzz corpus incl. RTL/accents)');
SELECT is((SELECT code_normalized FROM venue.promoter_code WHERE code_id = tap._u155('codeP')), 'J0RDY', 'C6: the fixture code JORDY is stored normalized as J0RDY');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, kind, created_by) VALUES (%L, %L, 'j0rdy', 'vanity', %L)$$,
  tap._u155('promQ'), tap._u155('org1'), tap.seller()), '23505', NULL, 'C7: JORDY then j0rdy raises unique_violation — the confusable pair is ONE code');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, code_normalized, kind, created_by) VALUES (%L, %L, 'ZZZZ', 'ZZZZ', 'vanity', %L)$$,
  tap._u155('promP'), tap._u155('org1'), tap.seller()), '428C9', NULL, 'C8: code_normalized cannot be written directly — not even as the table owner');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, kind, created_by) VALUES (%L, %L, 'ABC', 'vanity', %L)$$,
  tap._u155('promP'), tap._u155('org1'), tap.seller()), '23514', NULL, 'C9: a 3-symbol code is rejected by the length CHECK');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, kind, created_by) VALUES (%L, %L, 'ABCDEFGHJKMNPQRST', 'vanity', %L)$$,
  tap._u155('promP'), tap._u155('org1'), tap.seller()), '23514', NULL, 'C10: a 17-symbol code is rejected by the length CHECK');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, kind, created_by) VALUES (%L, %L, 'UUUU', 'vanity', %L)$$,
  tap._u155('promP'), tap._u155('org1'), tap.seller()), '23514', NULL, 'C11: U is outside the alphabet — rejected by the alphabet CHECK');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, kind, created_by, valid_from, valid_until) VALUES (%L, %L, 'WNDW', 'vanity', %L, now(), now() - interval '1 day')$$,
  tap._u155('promP'), tap._u155('org1'), tap.seller()), '23514', NULL, 'C12: valid_until <= valid_from is rejected by the window CHECK');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code (promoter_id, org_id, code_display, kind, created_by) VALUES (%L, %L, 'XORG', 'vanity', %L)$$,
  tap._u155('promP'), tap._u155('org2'), tap.seller()), 'P0001', NULL, 'C13: promoter_code.org_id must equal promoter.org_id (consistency trigger)');
-- immutability (no reassignment) — as the table OWNER
SELECT throws_ok(format($$UPDATE venue.promoter_code SET promoter_id = %L WHERE code_id = %L$$, tap._u155('promQ'), tap._u155('codeP')), 'P0001', NULL, 'C14: UPDATE promoter_id on a code raises (no reassignment — as postgres)');
SELECT throws_ok(format($$UPDATE venue.promoter_code SET code_display = 'JORDY2' WHERE code_id = %L$$, tap._u155('codeP')), 'P0001', NULL, 'C15: UPDATE code_display raises');
SELECT throws_ok(format($$UPDATE venue.promoter_code SET kind = 'generated' WHERE code_id = %L$$, tap._u155('codeP')), 'P0001', NULL, 'C16: UPDATE kind raises');
SELECT throws_ok(format($$UPDATE venue.promoter_code SET org_id = %L WHERE code_id = %L$$, tap._u155('org2'), tap._u155('codeP')), 'P0001', NULL, 'C17: UPDATE org_id raises');
SELECT lives_ok(format($$UPDATE venue.promoter_code SET valid_until = now() + interval '30 days' WHERE code_id = %L$$, tap._u155('codeP')), 'C18: UPDATE of the window succeeds (mutable column)');
SELECT lives_ok(format($$UPDATE venue.promoter_code SET valid_until = NULL WHERE code_id = %L$$, tap._u155('codeP')), 'C18b: …and back');
-- PL-1 on promoter_link (T-SCHEMA-PROMO-01, both directions)
SELECT throws_ok(format($$UPDATE venue.promoter_link SET slug = 'jordy-nite' WHERE link_id = %L$$, tap._u155('linkP')), 'P0001', NULL, 'C19: PL-1 — UPDATE slug raises');
SELECT throws_ok(format($$UPDATE venue.promoter_link SET promoter_id = %L WHERE link_id = %L$$, tap._u155('promQ'), tap._u155('linkP')), 'P0001', NULL, 'C20: PL-1 — UPDATE promoter_id raises');
SELECT throws_ok(format($$UPDATE venue.promoter_link SET event_id = %L WHERE link_id = %L$$, tap._u155('event2'), tap._u155('linkP')), 'P0001', NULL, 'C20b: PL-1 — UPDATE event_id raises (a link is per event, IMM)');
SELECT lives_ok(format($$UPDATE venue.promoter_link SET status = 'inactive' WHERE link_id = %L$$, tap._u155('linkQ')), 'C21: PL-1 — an UPDATE touching only status succeeds');
SELECT lives_ok(format($$UPDATE venue.promoter_link SET status = 'active' WHERE link_id = %L$$, tap._u155('linkQ')), 'C21b: …and back');
SELECT throws_ok(format($$INSERT INTO venue.promoter_link (promoter_id, event_id, slug) VALUES (%L, %L, 'Bad Slug!')$$, tap._u155('promP'), tap._u155('event1')), '23514', NULL, 'C22: E-123 — the slug format CHECK rejects spaces/punctuation/upper-case');
SELECT throws_ok(format($$INSERT INTO venue.promoter_link (promoter_id, event_id, slug) VALUES (%L, %L, 'rival-link')$$, tap._u155('promP'), tap._u155('event3')), 'P0001', NULL, 'C23: a link cannot bind another org''s event (consistency trigger)');
SELECT throws_ok(format($$INSERT INTO venue.promoter_code_scope (code_id, event_id, added_by) VALUES (%L, %L, %L)$$, tap._u155('codeP'), tap._u155('event3'), tap.seller()), 'P0001', NULL, 'C24: §12.15 — a code can never be scoped to another org''s event');
SELECT throws_ok(format($$UPDATE venue.promoter_code_scope SET event_id = %L WHERE code_id = %L$$, tap._u155('event2'), tap._u155('codeQ')), 'P0001', NULL, 'C25: a scope row is never UPDATEd (append/remove only)');
SELECT throws_ok(format($$INSERT INTO venue.promoter (identity_id, org_id, commission_kind, commission_bps, commission_flat_minor) VALUES (%L, %L, 'bps', 1000, 500)$$, tap.buyer(), tap._u155('org1')), '23514', NULL, 'C26: the terms XOR rejects both arms present');
SELECT throws_ok(format($$INSERT INTO venue.promoter (identity_id, org_id, commission_kind) VALUES (%L, %L, 'bps')$$, tap.buyer(), tap._u155('org1')), '23514', NULL, 'C27: …and no terms at all');
SELECT throws_ok(format($$INSERT INTO venue.promoter (identity_id, org_id, commission_kind, commission_bps, tier) VALUES (%L, %L, 'bps', 100, 'vip')$$, tap.buyer(), tap._u155('org1')), '23514', NULL, 'C28: tier accepts only its ratified label set');
SELECT throws_ok(format($$INSERT INTO venue.promoter (identity_id, org_id, commission_kind, commission_bps, party_kind) VALUES (NULL, %L, 'bps', 100, 'promoter')$$, tap._u155('org1')), '23514', NULL, 'C29: a promoter (party_kind=promoter) requires an identity; NULL is admissible only for an affiliate');
SELECT throws_ok(format($$INSERT INTO venue.promoter (identity_id, org_id, event_id, commission_kind, commission_bps) VALUES (%L, %L, %L, 'bps', 100)$$, tap.buyer(), tap._u155('org1'), tap._u155('event3')), 'P0001', NULL, 'C30: promoter.event_id must belong to the promoter''s org');
-- GP-2: DELETE denied to client roles (as org_owner)
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$DELETE FROM venue.promoter_code WHERE code_id = %L$$, tap._u155('codeP')), '42501', NULL, 'C31: GP-2 — org_owner cannot DELETE a code');
SELECT throws_ok(format($$DELETE FROM venue.promoter WHERE promoter_id = %L$$, tap._u155('promP')), '42501', NULL, 'C32: GP-2 — …nor a promoter');
SELECT throws_ok(format($$DELETE FROM venue.promoter_link WHERE link_id = %L$$, tap._u155('linkP')), '42501', NULL, 'C33: GP-2 — …nor a link');
SELECT throws_ok(format($$UPDATE venue.promoter_code SET status = 'inactive' WHERE code_id = %L$$, tap._u155('codeP')), '42501', NULL, 'C34: GP-1 — no direct client UPDATE either (RPC-only)');
SELECT throws_ok($$DELETE FROM venue.attribution$$, '42501', NULL, 'C35: GP-2 — attribution DELETE denied to clients (and AO for everyone else — E-section)');
SELECT tap.logout();

-- ============================================================================
-- SECTION D — PROMOTER RECORDS / LINKS / SLUGS / CODES: the RPC contracts
--   (RPC §20.9.1–§20.9.5, §17.15; RLS §11.5; OR-17 F-7; E-23 class)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100}', 'ck90-d1')$$, tap._u155('org1'), tap.fan155()::text),
  '42501', NULL, 'D1: a fan cannot create a promoter');
SELECT tap.logout();
SELECT tap.login(tap.other_user());   -- promoter P: an attribution identity, never an administrator (O-2)
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'MYOWN', NULL, NULL, NULL, 'vanity', 'ck90-d2')$$, tap._u155('promP')), '42501', NULL, 'D2: T-RPC-PROMO-01 — a promoter cannot mint their own code');
SELECT throws_ok(format($$SELECT venue.create_promoter_link(%L, %L, 'my-own', 'ck90-d3')$$, tap._u155('promP'), tap._u155('event1')), '42501', NULL, 'D3: …nor their own link');
SELECT throws_ok(format($$SELECT venue.set_promoter_code_status(%L, 'inactive', 'ck90-d4')$$, tap._u155('codeP')), '42501', NULL, 'D4: …nor flip a code''s status');
SELECT throws_ok(format($$SELECT venue.create_promoter_codes_bulk(%L, 5, 'generated', NULL, NULL, NULL, 'ck90-d4b')$$, tap._u155('promP')), '42501', NULL, 'D4b: …nor bulk-issue');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100}', 'ck90-d4c')$$, tap._u155('org1'), tap.fan155()::text), '42501', NULL, 'D4c: a promoter creating another promoter is refused');
SELECT tap.logout();
SELECT tap.login(tap.pm155());   -- venue_promoter_manager at venue1 (§11.5 allow-list)
SELECT tap._store155('codePM', (venue.create_promoter_code(tap._u155('promP'), 'PMCODE', NULL, NULL, NULL, 'vanity', 'ck90-d6') ->> 'code_id'));
SELECT ok(tap._u155('codePM') IS NOT NULL, 'D6: venue_promoter_manager CAN issue a code for the venue''s org promoter (§11.5)');
SELECT tap._store155('promM', (venue.create_promoter(tap._u155('org1'), 'buyer2155@test.local', '{"commission_kind":"bps","commission_bps":1000,"terms_version":7,"tier":"public_ambassador"}', 'ck90-d7') ->> 'promoter_id'));
SELECT tap._store155('linkM', (venue.create_promoter_link(tap._u155('promM'), tap._u155('event1'), 'amb-night', 'ck90-d7c') ->> 'link_id'));
SELECT tap.logout();
SELECT is((SELECT terms_version FROM venue.promoter WHERE promoter_id = tap._u155('promM')), 1, 'D7: create_promoter — terms_version is SERVER-assigned (a client-supplied 7 is ignored); the identity resolved from an email');
SELECT is((SELECT tier||'/'||party_kind||'/'||status FROM venue.promoter WHERE promoter_id = tap._u155('promM')), 'public_ambassador/promoter/active', 'D7b: tier honoured; party_kind defaults to promoter; born active');
SELECT tap.login(tap.pm155());
SELECT is((SELECT count(*)::int FROM venue.promoter WHERE promoter_id = tap._u155('promM')), 0, 'D7c: E-124 — the venue_promoter_manager who created the row holds NO direct SELECT cell (deny-by-default; the RPCs are their surface)');
SELECT tap.logout();
SELECT tap.login(tap.fan2155());   -- org2's owner
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'RIVAL1', NULL, NULL, NULL, 'vanity', 'ck90-d8')$$, tap._u155('promP')), '42501', NULL, 'D8: another org''s owner cannot mint a code for org1''s promoter (scoped to the promoter''s org)');
SELECT tap._store155('promR', (venue.create_promoter(tap._u155('org2'), NULL, '{"party_kind":"affiliate","commission_kind":"bps","commission_bps":250}', 'ck90-d9') ->> 'promoter_id'));
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'jordy', NULL, NULL, NULL, 'vanity', 'ck90-d10')$$, tap._u155('promR')), '23505', NULL, 'D10: T-RPC-PROMO-02 — the same normalized code in ANOTHER org is code_taken (global scope proven, not assumed)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((venue.create_promoter_code(tap._u155('promP'), 'JORDY', NULL, NULL, NULL, 'vanity', 'ck90-cP') ->> 'status'), 'idempotency_replay', 'D11: a replay of the issuing command key returns the same code');
SELECT is((venue.create_promoter_code(tap._u155('promP'), 'JORDY', NULL, NULL, NULL, 'vanity', 'ck90-cP') ->> 'code_id'), tap._fetch155('codeP'), 'D11b: …the SAME code_id');
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'J0RDY', NULL, NULL, NULL, 'vanity', 'ck90-cP2')$$, tap._u155('promP')), '23505', NULL, 'D12: a DIFFERENT command key with the same normalized code is code_taken — never a silent second code');
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'ZZZZTEST', NULL, NULL, NULL, 'vanity', 'ck90-cP')$$, tap._u155('promQ')), 'P0001', NULL, 'D12b: the SAME command key with DIFFERENT parameters → idempotency_conflict (never a silent replay of another promoter''s code)');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":9000}', 'ck90-pP')$$, tap._u155('org1'), tap.other_user()::text), 'P0001', NULL, 'D12c: create_promoter — same key, different terms → idempotency_conflict');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{}', 'ck90-d13')$$, tap._u155('org1'), tap.fan155()::text), 'P0001', NULL, 'D13: a promoter with no terms at all is rejected (terms_xor_violation)');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100,"commission_flat_minor":200}', 'ck90-d14')$$, tap._u155('org1'), tap.fan155()::text), 'P0001', NULL, 'D14: both arms present → terms_xor_violation');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100,"tier":"vip"}', 'ck90-d15')$$, tap._u155('org1'), tap.fan155()::text), 'P0001', NULL, 'D15: bad_tier');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100,"party_kind":"agency"}', 'ck90-d16')$$, tap._u155('org1'), tap.fan155()::text), 'P0001', NULL, 'D16: bad_party_kind');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, NULL, '{"commission_kind":"bps","commission_bps":100}', 'ck90-d17')$$, tap._u155('org1')), 'P0001', NULL, 'D17: a promoter (party_kind=promoter) without an identity is refused');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, 'nobody@nowhere.test', '{"commission_kind":"bps","commission_bps":100}', 'ck90-d18')$$, tap._u155('org1')), 'P0002', NULL, 'D18: an identity_ref that does not resolve is not_found');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"flat_per_ticket","commission_bps":100}', 'ck90-d18c')$$, tap._u155('org1'), tap.fan155()::text), 'P0001', NULL, 'D18c: flat_per_ticket with a bps amount → terms_xor_violation');
SELECT tap.logout();
-- F-7 / E-23: no NEW commission entitlement for a deleting or erased identity
CREATE FUNCTION tap.dp155() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '59595959-5959-5959-5959-595959595959'::uuid $$;
CREATE FUNCTION tap.er155() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '60606060-6060-6060-6060-606060606060'::uuid $$;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (tap.dp155(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dp155@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.er155(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'er155@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.dp155(), 'DELETION_PENDING') ON CONFLICT (identity_id) DO UPDATE SET deletion_state = 'DELETION_PENDING';
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.er155(), 'ERASED') ON CONFLICT (identity_id) DO UPDATE SET deletion_state = 'ERASED';
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100}', 'ck90-d19')$$, tap._u155('org1'), tap.dp155()::text), 'P0001', 'precondition_failed: identity_ineligible', 'D19: OR-17 F-7 — a DELETION_PENDING identity cannot be enrolled as a promoter (ONE message for every ineligible state — no third-party state disclosure)');
SELECT throws_ok(format($$SELECT venue.create_promoter(%L, %L, '{"commission_kind":"bps","commission_bps":100}', 'ck90-d20')$$, tap._u155('org1'), tap.er155()::text), 'P0001', 'precondition_failed: identity_ineligible', 'D20: E-23 class — an ERASED identity cannot be enrolled either (identical message)');
-- update_promoter: versioned terms, never overwritten
SELECT throws_ok(format($$SELECT venue.update_promoter(%L, '{"org_id":"%s"}', 'r', 'ck90-d22')$$, tap._u155('promM'), tap._u155('org2')), '22023', NULL, 'D22: org_id is an unwritable key (re-pointing a promoter record is impossible)');
SELECT throws_ok(format($$SELECT venue.update_promoter(%L, '{"identity_id":"%s"}', 'r', 'ck90-d22b')$$, tap._u155('promM'), tap.buyer()), '22023', NULL, 'D22b: identity_id is an unwritable key (no reassignment of earnings)');
SELECT throws_ok(format($$SELECT venue.update_promoter(%L, '{"commission_bps":1500}', NULL, 'ck90-d23')$$, tap._u155('promM')), 'P0001', NULL, 'D23: a terms change without a reason code → reason_required');
SELECT is((venue.update_promoter(tap._u155('promM'), '{"commission_bps":1500}', 'renegotiated', 'ck90-d24') ->> 'terms_version'), '2', 'D24: a terms change writes terms_version 2 (VERSIONED — never overwritten)');
SELECT is((venue.update_promoter(tap._u155('promM'), '{"commission_bps":1500}', 'again', 'ck90-d25') ->> 'status'), 'noop_replay', 'D25: a no-change patch is noop_replay…');
SELECT is((SELECT terms_version FROM venue.promoter WHERE promoter_id = tap._u155('promM')), 2, 'D25b: …and issues NO new terms_version (no version churn)');
SELECT is((venue.update_promoter(tap._u155('promM'), '{"status":"inactive"}', NULL, 'ck90-d26') ->> 'terms_version'), '2', 'D26: a status-only patch needs no reason and keeps terms_version');
SELECT is((SELECT status FROM venue.promoter WHERE promoter_id = tap._u155('promM')), 'inactive', 'D26b: …status is inactive');
SELECT is((venue.update_promoter(tap._u155('promM'), '{"status":"active"}', NULL, 'ck90-d27') ->> 'status'), 'ok', 'D27: …and back to active');
SELECT throws_ok(format($$SELECT venue.update_promoter(%L, '{"commission_flat_minor":300}', 'x', 'ck90-d28')$$, tap._u155('promM')), 'P0001', NULL, 'D28: adding the flat arm under kind=bps → terms_xor_violation');
SELECT is((venue.update_promoter(tap._u155('promM'), '{"commission_kind":"flat_per_ticket","commission_flat_minor":300}', 'switch', 'ck90-d28b') ->> 'terms_version'), '3', 'D28b: an explicit kind switch replaces the amount arm (bps → flat 300) at terms_version 3');
SELECT ok((SELECT commission_kind='flat_per_ticket' AND commission_flat_minor=300 AND commission_bps IS NULL FROM venue.promoter WHERE promoter_id = tap._u155('promM')), 'D28c: …the XOR holds after the switch');
SELECT is(tap._audit155(tap._u155('promM'), 'promoter.update'), 4, 'D28d: four promoter.update audit rows (three terms/status changes + the switch); the noop wrote none');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.update_promoter(%L, '{"status":"inactive"}', NULL, 'ck90-d29')$$, tap._u155('promM')), '42501', NULL, 'D29: a fan cannot update a promoter');
SELECT tap.logout();
-- links
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.create_promoter_link(%L, %L, 'Bad Slug', 'ck90-d30')$$, tap._u155('promP'), tap._u155('event1')), 'P0001', NULL, 'D30: invalid_slug_format');
SELECT throws_ok(format($$SELECT venue.create_promoter_link(%L, %L, 'rival-night', 'ck90-d31')$$, tap._u155('promP'), tap._u155('event3')), 'P0001', NULL, 'D31: event_out_of_org');
SELECT throws_ok(format($$SELECT venue.create_promoter_link(%L, %L, 'jordy-night', 'ck90-d32')$$, tap._u155('promM'), tap._u155('event1')), '23505', NULL, 'D32: slug_taken from the index (never a silent second link)');
SELECT is((venue.create_promoter_link(tap._u155('promP'), tap._u155('event1'), 'jordy-night', 'ck90-lP') ->> 'status'), 'idempotency_replay', 'D33: a replay of the issuing key returns the same link');
SELECT is((venue.create_promoter_link(tap._u155('promP'), tap._u155('event1'), 'jordy-night', 'ck90-lP') ->> 'link_id'), tap._fetch155('linkP'), 'D33b: …the SAME link_id');
SELECT throws_ok(format($$SELECT venue.create_promoter_link(%L, %L, 'q-night-2', 'ck90-d34')$$, tap._u155('promQ'), tap._u155('event2')), 'P0001', NULL, 'D34: a single-event promoter''s link binds only their event (event_out_of_org)');
SELECT throws_ok(format($$SELECT venue.create_promoter_link(%L, %L, 'other-slug', 'ck90-lP')$$, tap._u155('promP'), tap._u155('event1')), 'P0001', NULL, 'D34b: create_promoter_link — same key, different slug → idempotency_conflict');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.set_promoter_link_status(%L, 'inactive', 'r', 'ck90-d35')$$, tap._u155('linkM')), '42501', NULL, 'D35: a fan cannot change a link''s status');
SELECT tap.logout();
SELECT tap.login(tap.pm155());
SELECT is((venue.set_promoter_link_status(tap._u155('linkM'), 'inactive', 'campaign_over', 'ck90-d36') ->> 'link_status'), 'inactive', 'D36: venue_promoter_manager deactivates a link');
SELECT is((venue.set_promoter_link_status(tap._u155('linkM'), 'inactive', 'campaign_over', 'ck90-d37') ->> 'status'), 'noop_replay', 'D37: the same terminal state is a noop_replay');
SELECT throws_ok(format($$SELECT venue.set_promoter_link_status(%L, 'active', NULL, 'ck90-d38')$$, tap._u155('linkM')), 'P0001', NULL, 'D38: a status change without a reason → reason_required');
SELECT tap.logout();
SELECT ok((SELECT status_changed_by = tap.pm155() AND status_changed_at IS NOT NULL FROM venue.promoter_link WHERE link_id = tap._u155('linkM')), 'D39: status_changed_by/at are server-derived (C35)');
-- slug availability (§20.9.5): {available} and nothing else; allow-list; rate-limited fail-closed
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT venue.check_promoter_slug_available('jordy-night')$$, '42501', NULL, 'D40: T-RPC-PROMO-14 — a fan is refused (a global namespace is a cross-tenant oracle)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is(venue.check_promoter_slug_available('JORDY-NIGHT'), '{"available": false}'::jsonb, 'D41: a taken slug → {available:false} (case-folded)');
SELECT is(venue.check_promoter_slug_available('free-slug-155'), '{"available": true}'::jsonb, 'D42: a free slug → {available:true}');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(venue.check_promoter_slug_available('free-slug-156')) k), ARRAY['available'], 'D42b: the payload carries EXACTLY one field (field-list comparison — no oracle creeps back in)');
SELECT throws_ok($$SELECT venue.check_promoter_slug_available('Bad Slug!')$$, '22023', NULL, 'D43: bad_slug_format');
SELECT tap._resetlimit155(tap.seller());
SELECT is((SELECT count(*)::int FROM generate_series(1,30) g, LATERAL venue.check_promoter_slug_available('probe-' || g::text) r), 30, 'D44: the limiter admits 30 probes per minute…');
SELECT throws_ok($$SELECT venue.check_promoter_slug_available('probe-31')$$, 'P0001', NULL, 'D44b: …and refuses the 31st (rate_limited, fail-closed)');
-- bulk issuance (§7.2)
SELECT tap._store155('bulk1', venue.create_promoter_codes_bulk(tap._u155('promP'), 5, 'generated', ARRAY[tap._u155('event2')], NULL, NULL, 'ck90-bulk1')::text);
SELECT is((tap._fetch155('bulk1')::jsonb ->> 'count')::int, 5, 'D45: bulk issues exactly the requested count');
SELECT ok((SELECT count(DISTINCT c.code_normalized) = 5 AND bool_and(length(c.code_normalized) = 8 AND c.code_normalized ~ '^[0-9A-HJKMNP-TV-Z]+$' AND c.kind='generated' AND c.status='active')
             FROM venue.promoter_code c WHERE c.code_id IN (SELECT (x)::uuid FROM jsonb_array_elements_text(tap._fetch155('bulk1')::jsonb -> 'code_ids') x)),
  'D46: five DISTINCT generated codes at the 8-symbol entropy floor, inside the alphabet');
SELECT is((SELECT count(*)::int FROM venue.promoter_code_scope s WHERE s.code_id IN (SELECT (x)::uuid FROM jsonb_array_elements_text(tap._fetch155('bulk1')::jsonb -> 'code_ids') x) AND s.event_id = tap._u155('event2')), 5, 'D46b: each generated code carries the requested scope row');
SELECT is(tap._audit155(tap._u155('promP'), 'promoter_code.issue_bulk', 'ck90-bulk1'), 1, 'D47: ONE audit row for the program (not N)');
SELECT is((SELECT sum(tap._audit155((x)::uuid, 'promoter_code.issue'))::int FROM jsonb_array_elements_text(tap._fetch155('bulk1')::jsonb -> 'code_ids') x), 0, 'D47b: …and no per-code issue rows');
SELECT is((venue.create_promoter_codes_bulk(tap._u155('promP'), 5, 'generated', ARRAY[tap._u155('event2')], NULL, NULL, 'ck90-bulk1') ->> 'status'), 'idempotency_replay', 'D48: a bulk replay returns the original program');
SELECT throws_ok(format($$SELECT venue.create_promoter_codes_bulk(%L, 5, 'generated', ARRAY[%L::uuid], now(), NULL, 'ck90-bulk1')$$, tap._u155('promP'), tap._u155('event2')), 'P0001', NULL, 'D48b: the same bulk key with a different window → idempotency_conflict (bound to all six parameters)');
SELECT throws_ok(format($$SELECT venue.create_promoter_codes_bulk(%L, 1001, 'generated', NULL, NULL, NULL, 'ck90-d49')$$, tap._u155('promP')), 'P0001', NULL, 'D49: count_exceeds_cap (1,000 per call)');
SELECT throws_ok(format($$SELECT venue.create_promoter_codes_bulk(%L, 2, 'vanity', NULL, NULL, NULL, 'ck90-d50')$$, tap._u155('promP')), '22023', NULL, 'D50: bulk issuance is kind=generated only');
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'SHORT7A', NULL, NULL, NULL, 'generated', 'ck90-d51')$$, tap._u155('promP')), 'P0001', NULL, 'D51: a generated code below the 8-symbol floor → entropy_below_floor');
SELECT throws_ok(format($$SELECT venue.create_promoter_code(%L, 'UUUUUUUU', NULL, NULL, NULL, 'vanity', 'ck90-d52')$$, tap._u155('promP')), 'P0001', NULL, 'D52: an alphabet violation through the RPC → invalid_code_format');
-- scope / window (never retroactive)
SELECT is((venue.set_promoter_code_scope(tap._u155('codeP'), ARRAY[tap._u155('event2')], NULL, 'ck90-d53') ->> 'added')::int, 1, 'D53: scope add');
SELECT is((venue.set_promoter_code_scope(tap._u155('codeP'), NULL, ARRAY[tap._u155('event2')], 'ck90-d54') ->> 'removed')::int, 1, 'D54: scope remove (future eligibility only)');
SELECT throws_ok(format($$SELECT venue.set_promoter_code_scope(%L, ARRAY[%L::uuid], NULL, 'ck90-d55')$$, tap._u155('codeP'), tap._u155('event3')), 'P0001', NULL, 'D55: scoping to another org''s event → event_out_of_org');
SELECT throws_ok(format($$SELECT venue.set_promoter_code_window(%L, now(), now() - interval '1 day', 'ck90-d56')$$, tap._u155('codeP')), 'P0001', NULL, 'D56: invalid_window');
SELECT is((venue.set_promoter_code_window(tap._u155('codeP'), now() - interval '1 day', NULL, 'ck90-d57') ->> 'status'), 'ok', 'D57: window set');
SELECT is(tap._audit155(tap._u155('codeP'), 'promoter_code.window', 'ck90-d57'), 1, 'D57b: …audited');
SELECT is((venue.set_promoter_code_window(tap._u155('codeP'), NULL, NULL, 'ck90-d58') ->> 'status'), 'ok', 'D58: window cleared');
SELECT is((venue.create_promoter_code(tap._u155('promP'), 'J0RDX', NULL, NULL, NULL, 'vanity', 'ck90-d59') -> 'confusable_with'), '["JORDY"]'::jsonb, 'D59: the issue-time confusable warning lists JORDY (edit distance 1 from J0RDX)');
SELECT tap.logout();
SELECT tap.login(tap.fan2155());
SELECT is((venue.create_promoter_code(tap._u155('promR'), 'JORDZ', NULL, NULL, NULL, 'vanity', 'ck90-d60') -> 'confusable_with'), '[]'::jsonb, 'D60: another org''s issuer sees NO confusable from org1 (JORDY / J0RDX are one edit away) — the roster of another tenant is never disclosed');
SELECT tap.logout();

-- ============================================================================
-- SECTION E — ELIGIBILITY (§1.2 E1–E7) THROUGH PREVIEW + BINDING (§7.5/§7.6, §9.4)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT is(venue.preview_promoter_code('jordy', tap._u155('session1')), '{"status":"eligible","promoter_display_name":"Other O","method_hint":"code"}'::jsonb, 'E1: an eligible code previews with the promoter''s display name (E7: unscoped org-wide code)');
SELECT is(venue.preview_promoter_code('QCODE', tap._u155('session1')), '{"status":"eligible","promoter_display_name":"Jordy Q","method_hint":"code"}'::jsonb, 'E2: a scoped code previews on its event (E6)');
SELECT tap._store155('na', venue.preview_promoter_code('NOPE99', tap._u155('session1'))::text);
SELECT is(tap._fetch155('na')::jsonb, '{"status":"not_applicable"}'::jsonb, 'E3: an unknown code → not_applicable');
SELECT is(venue.preview_promoter_code('QCODE', tap._u155('session2')), tap._fetch155('na')::jsonb, 'E4: out of scope (E6) → the IDENTICAL payload');
SELECT is(venue.preview_promoter_code('jordy', tap._u155('session3')), tap._fetch155('na')::jsonb, 'E5: another org''s event (E4) → identical');
SELECT is(venue.preview_promoter_code('QCODE', tap._u155('session2')), tap._fetch155('na')::jsonb, 'E5b: a single-event promoter''s code on a second event (E5 precedes E6) → identical');
SELECT is(venue.preview_promoter_code('AFFIL', tap._u155('session1')), '{"status":"eligible","promoter_display_name":"Promoter","method_hint":"code"}'::jsonb, 'E6: an affiliate''s code (no identity) previews with a neutral label — never the caller''s input echoed back');
SELECT is(venue.preview_promoter_code('jordy', gen_random_uuid()), tap._fetch155('na')::jsonb, 'E7: an unknown session → identical');
SELECT is(venue.preview_promoter_code('', tap._u155('session1')), tap._fetch155('na')::jsonb, 'E7b: malformed input → identical');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.set_promoter_code_status(tap._u155('codeQ'), 'inactive', 'ck90-e8');
SELECT tap.logout();
SELECT tap._resetlimit155(tap.buyer());
SELECT tap.login(tap.buyer());
SELECT is(venue.preview_promoter_code('QCODE', tap._u155('session1')), tap._fetch155('na')::jsonb, 'E8: an inactive code (E2) → identical');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.set_promoter_code_status(tap._u155('codeQ'), 'active', 'ck90-e8b');
SELECT venue.set_promoter_code_window(tap._u155('codeQ'), NULL, now(), 'ck90-e9');
SELECT tap.logout();
SELECT tap._resetlimit155(tap.buyer());
SELECT tap.login(tap.buyer());
SELECT is(venue.preview_promoter_code('QCODE', tap._u155('session1')), tap._fetch155('na')::jsonb, 'E9: valid_until = now() is INELIGIBLE (half-open interval) → identical');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.set_promoter_code_window(tap._u155('codeQ'), now(), NULL, 'ck90-e10');
SELECT tap.logout();
SELECT tap._resetlimit155(tap.buyer());
SELECT tap.login(tap.buyer());
SELECT is((venue.preview_promoter_code('QCODE', tap._u155('session1')) ->> 'status'), 'eligible', 'E10: valid_from = now() is ELIGIBLE (half-open interval)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.set_promoter_code_window(tap._u155('codeQ'), NULL, NULL, 'ck90-e10b');
SELECT venue.update_promoter(tap._u155('promQ'), '{"status":"inactive"}', NULL, 'ck90-e11');
SELECT tap.logout();
SELECT tap._resetlimit155(tap.buyer());
SELECT tap.login(tap.buyer());
SELECT is(venue.preview_promoter_code('QCODE', tap._u155('session1')), tap._fetch155('na')::jsonb, 'E11: an inactive PROMOTER (E1) → identical');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.update_promoter(tap._u155('promQ'), '{"status":"active"}', NULL, 'ck90-e11b');
SELECT tap.logout();
SELECT tap.login_service();
SELECT is((venue.preview_promoter_code('jordy', tap._u155('session1')) ->> 'status'), 'eligible', 'E12: the edge wrapper''s service_role path previews (unauthenticated buyers reach it ONLY through the wrapper)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok(format($$SELECT venue.preview_promoter_code('jordy', %L)$$, tap._u155('session1')), '42501', NULL, 'E13: anon holds no EXECUTE on the preview');
SELECT tap.logout();
SELECT tap.login(tap.fan2155());
SELECT is((SELECT count(*)::int FROM generate_series(1,10) g, LATERAL venue.preview_promoter_code('probe' || g::text, tap._u155('session1')) r), 10, 'E14: E-125 — an authenticated direct caller gets 10 previews per minute…');
SELECT throws_ok(format($$SELECT venue.preview_promoter_code('probe11', %L)$$, tap._u155('session1')), 'P0001', NULL, 'E14b: …and the 11th is rate_limited (fail-closed)');
SELECT tap.logout();
-- binding (§7.6): the candidate on a PENDING order
SELECT tap._neworder155('o1', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 3, 5000);
SELECT tap.login(tap.buyer());
SELECT is((venue.bind_order_attribution(tap._u155('o1'), 'j-0-r-d-y ', NULL, 'ck90-b1') ->> 'bound'), 'true', 'E15: the buyer binds a code (normalized on the way in)');
SELECT is((SELECT attribution_candidate_code_id FROM venue."order" WHERE order_id = tap._u155('o1')), tap._u155('codeP'), 'E15b: the candidate column names the code');
SELECT is(tap._audit155(tap._u155('o1'), 'attribution.candidate_changed'), 1, 'E15c: attribution.candidate_changed audited (old → new)');
SELECT is((venue.bind_order_attribution(tap._u155('o1'), 'QCODE', NULL, 'ck90-b2') ->> 'bound'), 'true', 'E16: M3 — a rebind while pending is last-write-wins, not an error');
SELECT is((SELECT attribution_candidate_code_id FROM venue."order" WHERE order_id = tap._u155('o1')), tap._u155('codeQ'), 'E16b: exactly one candidate — the latest');
SELECT is(tap._audit155(tap._u155('o1'), 'attribution.candidate_changed'), 2, 'E16c: …and a second audit row');
SELECT is(venue.bind_order_attribution(tap._u155('o1'), 'NOPE99', NULL, 'ck90-b3'), jsonb_build_object('status','ok','bound',false,'reason','not_applicable','order_id',tap._u155('o1')), 'E17: an unresolvable code NEVER fails the order — bound:false, reason not_applicable');
SELECT ok((SELECT attribution_candidate_code_id IS NULL AND attribution_candidate_link_id IS NULL FROM venue."order" WHERE order_id = tap._u155('o1')), 'E17b: …and the candidate is cleared');
SELECT is((venue.bind_order_attribution(tap._u155('o1'), NULL, 'JORDY-NIGHT', 'ck90-b4') ->> 'bound'), 'true', 'E18: a link slug binds (case-folded)');
SELECT is((SELECT attribution_candidate_link_id FROM venue."order" WHERE order_id = tap._u155('o1')), tap._u155('linkP'), 'E18b: the link candidate names the link');
SELECT is((venue.bind_order_attribution(tap._u155('o1'), 'jordy', 'q-night', 'ck90-b5') ->> 'bound'), 'true', 'E19: a code AND a link bind together (both candidates set)');
SELECT ok((SELECT attribution_candidate_code_id = tap._u155('codeP') AND attribution_candidate_link_id = tap._u155('linkQ') FROM venue."order" WHERE order_id = tap._u155('o1')), 'E19b: code P + link Q');
SELECT is((venue.bind_order_attribution(tap._u155('o1'), 'jordy', 'q-night', 'ck90-b5') ->> 'status'), 'idempotency_replay', 'E20: a command-key replay is idempotency_replay');
SELECT is((venue.bind_order_attribution(tap._u155('o1'), 'NOPE99', NULL, 'ck90-b5b') ->> 'bound'), 'false', 'E20b: a code-only call with an unresolvable code clears the CODE channel only…');
SELECT ok((SELECT attribution_candidate_code_id IS NULL AND attribution_candidate_link_id = tap._u155('linkQ') FROM venue."order" WHERE order_id = tap._u155('o1')), 'E20c: …the bound link SURVIVES (a NULL argument never wipes the other channel — P5/P9 stay reachable)');
SELECT is((venue.bind_order_attribution(tap._u155('o1'), 'jordy', NULL, 'ck90-b5c') ->> 'bound'), 'true', 'E20d: a code-only rebind restores code P…');
SELECT ok((SELECT attribution_candidate_code_id = tap._u155('codeP') AND attribution_candidate_link_id = tap._u155('linkQ') FROM venue."order" WHERE order_id = tap._u155('o1')), 'E20e: …with link Q still bound');
SELECT tap.logout();
SELECT tap.login(tap.fan155());
SELECT throws_ok(format($$SELECT venue.bind_order_attribution(%L, 'jordy', NULL, 'ck90-b6')$$, tap._u155('o1')), '42501', NULL, 'E21: another user cannot bind the buyer''s order');
SELECT tap.logout();
SELECT tap.login(tap.buyer2155());   -- venue_box_office at venue1
SELECT throws_ok(format($$SELECT venue.bind_order_attribution(%L, 'jordy', NULL, 'ck90-b7')$$, tap._u155('o1')), '42501', NULL, 'E22: box office cannot bind a WEB order');
SELECT tap.logout();
SELECT tap._neworder155('odoor', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000, 'door');
SELECT tap.login(tap.buyer2155());
SELECT is((venue.bind_order_attribution(tap._u155('odoor'), 'jordy', NULL, 'ck90-b8') ->> 'bound'), 'true', 'E23: …but binds an on-behalf DOOR order');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — THE PRECEDENCE TABLE (§2.3 P0–P10, M4), THE FREEZE (§3), THE
--   RESOLVER'S NEVER-RAISE RULE (§7.11), SELF-DEAL (§9.5), TERMS SNAPSHOT (§6.2)
--   Each order is finalized through venue.finalize_primary_order (the ONLY call
--   site — T-SCHEMA-SEAM-04's behavioural half); the resolver is never called directly.
-- ============================================================================
-- P2: o1 carries code P + link Q (bound in E19)
SELECT is(tap._attrcount155(tap._u155('o1')), 0, 'F0: §12.39 — NO attribution row exists while the order is pending, even with both candidates bound (the §14.4 correction is implemented)');
SELECT tap._store155('pay1', tap._newpayment155(tap.buyer(), tap.seller(), 15000, 'pi_90_1')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o1'), tap._u155('pay1'), 'ck90-f1', 'fp-buyer') ->> 'status'), 'ok', 'F1: o1 finalized (3 atoms) with code P + link Q presented');
SELECT ok((SELECT a.promoter_id = tap._u155('promP') AND a.method = 'code' AND a.touch_corroborated = false AND a.resolution_reason = 'code_over_link'
              AND a.displaced_promoter_id = tap._u155('promQ') AND a.code_id = tap._u155('codeP') AND a.link_id IS NULL FROM tap._attr155(tap._u155('o1')) a),
  'F2: P2 — code beats link: credited to P, method code, touch_corroborated FALSE, displaced_promoter_id = Q, reason code_over_link');
SELECT ok((SELECT a.basis_minor = 15000 AND a.credited_amount_minor = 1500 AND a.commission_kind = 'bps' AND a.commission_bps_applied = 1000 AND a.commission_flat_minor_applied IS NULL
              AND a.terms_version = 1 AND a.currency = 'USD' AND a.org_id = tap._u155('org1') AND a.event_id = tap._u155('event1') AND a.self_deal_flag = false AND a.self_deal_reasons = '{}'
              FROM tap._attr155(tap._u155('o1')) a),
  'F3: basis = face subtotal 15000 (§6.1); credited = floor(15000 × 1000 / 10000) = 1500 (§6.2); terms SNAPSHOTTED (kind/bps/version); org/event denormalized; no self-deal');
SELECT ok((SELECT a.order_paid_at = o.updated_at AND a.occurred_at IS NOT NULL FROM tap._attr155(tap._u155('o1')) a JOIN venue."order" o ON o.order_id = a.order_id),
  'F4: order_paid_at is the order''s paid timestamp (the freeze point — §3.2)');
SELECT is(tap._outbox155('attribution_recorded', tap._u155('o1')), 1, 'F5: G-25 #31 AttributionRecorded BE-emitted once, keyed on order_id (§14.5)');
-- P0: a replayed finalize returns the winner's row — exactly one attribution
SELECT is((venue.finalize_primary_order(tap._u155('o1'), tap._u155('pay1'), 'ck90-f1', 'fp-buyer') ->> 'status'), 'idempotency_replay', 'F6: webhook redelivery → idempotency_replay');
SELECT is(tap._attrcount155(tap._u155('o1')), 1, 'F7: P0 — exactly ONE attribution after the replay');
-- M4: binding after the freeze
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.bind_order_attribution(%L, 'QCODE', NULL, 'ck90-f8')$$, tap._u155('o1')), 'P0001', NULL, 'F8: M4 — a rebind on a paid order → attribution_frozen');
SELECT tap.logout();
SELECT throws_ok(format($$UPDATE venue."order" SET attribution_candidate_code_id = NULL WHERE order_id = %L$$, tap._u155('o1')), 'P0001', NULL, 'F9: the 082 candidate-freeze guard raises once the order left pending (regression on 082''s trigger)');
-- P1: code + corroborating link (same promoter)
SELECT tap._neworder155('o2', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o2'), 'jordy', 'jordy-night', 'ck90-b-o2'); SELECT tap.logout();
SELECT tap._store155('pay2', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_2')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o2'), tap._u155('pay2'), 'ck90-f-o2', NULL) ->> 'status'), 'ok', 'F10: o2 finalized with code P + link P');
SELECT ok((SELECT a.promoter_id = tap._u155('promP') AND a.method = 'code' AND a.touch_corroborated AND a.resolution_reason = 'code_corroborated_by_link'
              AND a.code_id = tap._u155('codeP') AND a.link_id = tap._u155('linkP') AND a.displaced_promoter_id IS NULL FROM tap._attr155(tap._u155('o2')) a),
  'F11: P1 — code corroborated by link: method code, touch_corroborated TRUE, both ids recorded, no displacement');
-- P3: code E + link X (the link is inactive at resolve time — set as the table owner, past the advisory filter)
SELECT tap._neworder155('o3', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap._setcand155(tap._u155('o3'), tap._u155('codeP'), tap._u155('linkM'));
SELECT tap._store155('pay3', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_3')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o3'), tap._u155('pay3'), 'ck90-f-o3', NULL) ->> 'status'), 'ok', 'F12: o3 finalized with code P + an INACTIVE link');
SELECT ok((SELECT a.promoter_id = tap._u155('promP') AND a.method = 'code' AND NOT a.touch_corroborated AND a.resolution_reason = 'code_only_link_ineligible' AND a.link_id IS NULL AND a.displaced_promoter_id IS NULL FROM tap._attr155(tap._u155('o3')) a),
  'F13: P3 — code only, link ineligible: displaced_promoter_id NULL (an ineligible link displaces nobody)');
-- P4: code only
SELECT tap._neworder155('o4', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o4'), 'jordy', NULL, 'ck90-b-o4'); SELECT tap.logout();
SELECT tap._store155('pay4', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_4')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o4'), tap._u155('pay4'), 'ck90-f-o4', NULL) ->> 'status'), 'ok', 'F14: o4 finalized with code P only');
SELECT ok((SELECT a.method = 'code' AND NOT a.touch_corroborated AND a.resolution_reason = 'code_only' FROM tap._attr155(tap._u155('o4')) a), 'F15: P4 — code_only');
-- P5: code X (deactivated before finalize) + link E
SELECT tap._neworder155('o5', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o5'), 'QCODE', 'jordy-night', 'ck90-b-o5'); SELECT tap.logout();
SELECT tap.login(tap.seller()); SELECT venue.set_promoter_code_status(tap._u155('codeQ'), 'inactive', 'ck90-f16'); SELECT tap.logout();
SELECT tap._store155('pay5', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_5')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o5'), tap._u155('pay5'), 'ck90-f-o5', NULL) ->> 'status'), 'ok', 'F16: o5 finalized after code Q was deactivated (§3.5 deactivate-then-commit)');
SELECT ok((SELECT a.promoter_id = tap._u155('promP') AND a.method = 'link' AND a.touch_corroborated AND a.resolution_reason = 'link_after_code_ineligible' AND a.link_id = tap._u155('linkP') AND a.code_id IS NULL FROM tap._attr155(tap._u155('o5')) a),
  'F17: P5 — the link wins when the code is ineligible: method link, touch_corroborated TRUE');
-- P6: link only
SELECT tap._neworder155('o6', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o6'), NULL, 'jordy-night', 'ck90-b-o6'); SELECT tap.logout();
SELECT tap._store155('pay6', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_6')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o6'), tap._u155('pay6'), 'ck90-f-o6', NULL) ->> 'status'), 'ok', 'F18: o6 finalized with link P only');
SELECT ok((SELECT a.method = 'link' AND a.touch_corroborated AND a.resolution_reason = 'link_only' AND a.link_id = tap._u155('linkP') FROM tap._attr155(tap._u155('o6')) a), 'F19: P6 — link_only');
-- P7 · P8 · P9 · P10: no row, and the sale completes
SELECT tap._neworder155('o7', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap._setcand155(tap._u155('o7'), tap._u155('codeQ'), tap._u155('linkM'));   -- both inactive
SELECT tap._neworder155('o8', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap._setcand155(tap._u155('o8'), tap._u155('codeQ'), NULL);
SELECT tap._neworder155('o9', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap._setcand155(tap._u155('o9'), NULL, tap._u155('linkM'));
SELECT tap._neworder155('o10', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap._store155('pay7', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_7')::text);
SELECT tap._store155('pay8', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_8')::text);
SELECT tap._store155('pay9', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_9')::text);
SELECT tap._store155('pay10', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_10')::text);
SELECT ok((venue.finalize_primary_order(tap._u155('o7'), tap._u155('pay7'), 'ck90-f-o7', NULL) ->> 'status') = 'ok' AND tap._attrcount155(tap._u155('o7')) = 0, 'F20: P7 — code X + link X: the order completes, NO attribution row');
SELECT ok((venue.finalize_primary_order(tap._u155('o8'), tap._u155('pay8'), 'ck90-f-o8', NULL) ->> 'status') = 'ok' AND tap._attrcount155(tap._u155('o8')) = 0, 'F21: P8 — code X only: no row');
SELECT ok((venue.finalize_primary_order(tap._u155('o9'), tap._u155('pay9'), 'ck90-f-o9', NULL) ->> 'status') = 'ok' AND tap._attrcount155(tap._u155('o9')) = 0, 'F22: P9 — link X only: no row');
SELECT ok((venue.finalize_primary_order(tap._u155('o10'), tap._u155('pay10'), 'ck90-f-o10', NULL) ->> 'status') = 'ok' AND tap._attrcount155(tap._u155('o10')) = 0, 'F23: P10 — nothing presented: no row');
SELECT is((SELECT count(*)::int FROM kernel.tickets t WHERE t.event_session_id = tap._u155('session1')), 3+1+1+1+1+1+1+1+1+1, 'F24: every one of the ten orders minted its atoms — an attribution outcome never fails a sale');
SELECT is(tap._outbox155('attribution_recorded', tap._u155('o7')) + tap._outbox155('attribution_recorded', tap._u155('o10')), 0, 'F25: no AttributionRecorded for a no-row outcome');
SELECT is((SELECT count(DISTINCT a.resolution_reason)::int FROM venue.attribution a WHERE a.order_id IN (tap._u155('o1'),tap._u155('o2'),tap._u155('o3'),tap._u155('o4'),tap._u155('o5'),tap._u155('o6'))), 6,
  'F26: exhaustiveness — the six positive P-rows each fired exactly once across the six attributed orders (totality asserted, not claimed)');
-- the freeze forbids (§3.4)
SELECT tap._store155('a1_before', to_jsonb(tap._attr155(tap._u155('o1')))::text);
SELECT tap.login(tap.seller());
SELECT venue.set_promoter_code_status(tap._u155('codeP'), 'inactive', 'ck90-f27');
SELECT venue.set_promoter_link_status(tap._u155('linkP'), 'inactive', 'season_over', 'ck90-f27b');
SELECT is((venue.update_promoter(tap._u155('promP'), '{"commission_bps":2000}', 'raise', 'ck90-f27c') ->> 'terms_version'), '2', 'F27: P''s terms move to version 2 (bps 2000) after the sales');
SELECT tap.logout();
SELECT is(to_jsonb(tap._attr155(tap._u155('o1'))), tap._fetch155('a1_before')::jsonb, 'F28: deactivating the code AND the link AND changing the terms leaves the frozen attribution BYTE-IDENTICAL (T-SCHEMA-PROMO-02; §12.41/42)');
SELECT throws_ok(format($$UPDATE venue.attribution SET credited_amount_minor = 1 WHERE order_id = %L$$, tap._u155('o1')), 'P0001', NULL, 'F29: AO — UPDATE of an attribution raises even for the table owner');
SELECT throws_ok(format($$DELETE FROM venue.attribution WHERE order_id = %L$$, tap._u155('o1')), 'P0001', NULL, 'F30: AO — DELETE raises for the owner');
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$UPDATE venue.attribution SET promoter_id = %L WHERE order_id = %L$$, tap._u155('promQ'), tap._u155('o1')), '42501', NULL, 'F31: platform_admin holds no UPDATE either');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.set_promoter_code_status(tap._u155('codeP'), 'active', 'ck90-f32');
SELECT venue.set_promoter_link_status(tap._u155('linkP'), 'active', 'season_back', 'ck90-f32b');
SELECT tap.logout();
-- new sales bind the NEW terms only
SELECT tap._neworder155('o11', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o11'), 'jordy', NULL, 'ck90-b-o11'); SELECT tap.logout();
SELECT tap._store155('pay11', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_11')::text);
SELECT venue.finalize_primary_order(tap._u155('o11'), tap._u155('pay11'), 'ck90-f-o11', NULL);
SELECT ok((SELECT a.terms_version = 2 AND a.commission_bps_applied = 2000 AND a.credited_amount_minor = 1000 FROM tap._attr155(tap._u155('o11')) a), 'F33: a sale after the terms change snapshots version 2 / bps 2000 → 1000 on 5000');
-- self-deal detectors (§9.5): flag, never block
SELECT tap._neworder155('o12', tap.other_user(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 2, 5000);
SELECT tap.login(tap.other_user()); SELECT venue.bind_order_attribution(tap._u155('o12'), 'jordy', NULL, 'ck90-b-o12'); SELECT tap.logout();
SELECT tap._store155('pay12', tap._newpayment155(tap.other_user(), tap.seller(), 10000, 'pi_90_12')::text);
SELECT is((venue.finalize_primary_order(tap._u155('o12'), tap._u155('pay12'), 'ck90-f-o12', 'fp-promoterP') ->> 'status'), 'ok', 'F34: promoter P buys with their own code — the sale completes');
SELECT ok((SELECT a.self_deal_flag AND a.self_deal_reasons = ARRAY['same_identity'] AND a.promoter_id = tap._u155('promP') AND a.credited_amount_minor = 2000 FROM tap._attr155(tap._u155('o12')) a),
  'F35: …flagged same_identity, still credited (flag, never block; payability is withheld — G-section)');
SELECT tap._neworder155('o13', tap.fan2155(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.fan2155()); SELECT venue.bind_order_attribution(tap._u155('o13'), 'jordy', NULL, 'ck90-b-o13'); SELECT tap.logout();
SELECT tap._store155('pay13', tap._newpayment155(tap.fan2155(), tap.seller(), 5000, 'pi_90_13')::text);
SELECT venue.finalize_primary_order(tap._u155('o13'), tap._u155('pay13'), 'ck90-f-o13', 'fp-promoterP');
SELECT ok((SELECT a.self_deal_flag AND a.self_deal_reasons = ARRAY['same_instrument'] FROM tap._attr155(tap._u155('o13')) a),
  'F36: a different buyer on the promoter''s previously-used instrument → same_instrument');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname IN ('list_my_attributions','get_my_promoter_summary','list_promoter_attributions','preview_promoter_code') AND p.prosrc LIKE '%instrument_fingerprint%'), 0,
  'F37: instrument_fingerprint is read ONLY by the detector — no read RPC touches it');
-- flat_per_ticket terms (promoter Q, single-event)
SELECT tap.login(tap.seller()); SELECT venue.set_promoter_code_status(tap._u155('codeQ'), 'active', 'ck90-f38'); SELECT tap.logout();
SELECT tap._neworder155('o14', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o14'), 'QCODE', NULL, 'ck90-b-o14'); SELECT tap.logout();
SELECT tap._store155('pay14', tap._newpayment155(tap.buyer(), tap.seller(), 10000, 'pi_90_14')::text);
SELECT venue.finalize_primary_order(tap._u155('o14'), tap._u155('pay14'), 'ck90-f-o14', NULL);
SELECT ok((SELECT a.commission_kind = 'flat_per_ticket' AND a.commission_flat_minor_applied = 300 AND a.commission_bps_applied IS NULL AND a.basis_minor = 10000 AND a.credited_amount_minor = 600 FROM tap._attr155(tap._u155('o14')) a),
  'F38: flat_per_ticket: credited = 300 × 2 tickets = 600; basis still recorded (10000)');
-- E-126: a promoter whose identity is DELETION_PENDING / ERASED is ineligible (fail-to-safe)
UPDATE kernel.identity_ext SET deletion_state = 'DELETION_PENDING' WHERE identity_id = tap.other_user();
SELECT tap._neworder155('o15', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap._setcand155(tap._u155('o15'), tap._u155('codeP'), NULL);
SELECT tap._store155('pay15', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_15')::text);
SELECT ok((venue.finalize_primary_order(tap._u155('o15'), tap._u155('pay15'), 'ck90-f-o15', NULL) ->> 'status') = 'ok' AND tap._attrcount155(tap._u155('o15')) = 0,
  'F39: E-126 — a code of a DELETION_PENDING promoter attracts no attribution (the sale completes; the org keeps the commission)');
UPDATE kernel.identity_ext SET deletion_state = 'ACTIVE' WHERE identity_id = tap.other_user();
-- §6.2: the order's currency must be the promoter's terms currency
SELECT tap._neworder155('o19', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
UPDATE venue."order" SET currency = 'EUR' WHERE order_id = tap._u155('o19');
SELECT tap._setcand155(tap._u155('o19'), tap._u155('codeP'), NULL);
SELECT tap._store155('pay19', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_19')::text);
SELECT ok((venue.finalize_primary_order(tap._u155('o19'), tap._u155('pay19'), 'ck90-f-o19', NULL) ->> 'status') = 'ok' AND tap._attrcount155(tap._u155('o19')) = 0,
  'F39b: §6.2 — an order in a currency other than the promoter''s terms currency (EUR vs USD) attributes NOTHING (the sale completes; no cross-currency commission is ever minted)');
-- §7.11 / T-RPC-ATTR-02: a deliberately faulted resolver still commits the money and the tickets
CREATE FUNCTION tap._boom155() RETURNS trigger LANGUAGE plpgsql AS $t$ begin raise exception 'injected resolver fault'; end $t$;
CREATE TRIGGER tg_boom155 BEFORE INSERT ON venue.attribution FOR EACH ROW EXECUTE FUNCTION tap._boom155();
SELECT tap._neworder155('o16', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o16'), 'jordy', NULL, 'ck90-b-o16'); SELECT tap.logout();
SELECT tap._store155('pay16', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_16')::text);
SELECT tap._store155('f16', venue.finalize_primary_order(tap._u155('o16'), tap._u155('pay16'), 'ck90-f-o16', NULL)::text);
SELECT is((tap._fetch155('f16')::jsonb ->> 'status'), 'ok', 'F40: T-RPC-ATTR-02 — with the resolver''s insert FAULTED, finalize still returns ok');
SELECT ok((SELECT status = 'paid' FROM venue."order" WHERE order_id = tap._u155('o16')) AND jsonb_array_length(tap._fetch155('f16')::jsonb -> 'atom_ids') = 1
       AND (SELECT count(*) = 1 FROM kernel.payment_native pn WHERE pn.order_id = tap._u155('o16')) AND tap._attrcount155(tap._u155('o16')) = 0,
  'F41: …the order is paid, the atom minted, the payment linked, and NO attribution row exists');
SELECT ok((SELECT count(*) = 1 AND bool_and(a.actor_identity = '00000000-0000-0000-0000-0000000000f1' AND a.reason_code ~ '^[A-Za-z0-9._:-]{1,64}$' AND (a.after ->> 'message') LIKE '%injected resolver fault%')
             FROM kernel.admin_audit a WHERE a.action = 'attribution.resolver_error' AND a.subject_id = tap._u155('o16')),
  'F42: …and exactly one attribution.resolver_error landed (system actor; E-80-bounded reason; the message in `after`)');
DROP TRIGGER tg_boom155 ON venue.attribution;

-- ============================================================================
-- SECTION G — THE MONEY (§4 no-double-commission, §5 refunds/cancel, §6.3 payable
--   at close, RPC §20.7.2/§20.11.2 hold semantics, AUTHZ-H10, E-73 sign, E-128)
-- ============================================================================
-- basis changes BEFORE close: void ONE of o1's three atoms (platform_risk) and fully refund o2
SELECT tap._store155('o1atom', (SELECT t.ticket_atom_id::text FROM kernel.tickets t JOIN kernel.ticket_ownership_log l ON l.ticket_atom_id = t.ticket_atom_id AND l.sequence = 1
                                 WHERE l.cause_ref IN (SELECT id FROM venue.order_item WHERE order_id = tap._u155('o1')) ORDER BY t.ticket_atom_id LIMIT 1));
SELECT tap.login(tap.risk155()); SELECT tap._aal2();
SELECT is((kernel.force_void_ticket(tap._u155('o1atom'), 'admin_action', 'ck90-g1') ->> 'status'), 'ok', 'G1: platform_risk voids one of o1''s three atoms');
SELECT tap.logout();
UPDATE venue."order" SET status = 'refunded' WHERE order_id = tap._u155('o2');
SELECT tap._store155('o2atom', (SELECT t.ticket_atom_id::text FROM kernel.tickets t JOIN kernel.ticket_ownership_log l ON l.ticket_atom_id = t.ticket_atom_id AND l.sequence = 1
                                 WHERE l.cause_ref IN (SELECT id FROM venue.order_item WHERE order_id = tap._u155('o2')) LIMIT 1));
SELECT tap.login(tap.risk155()); SELECT tap._aal2();
SELECT kernel.force_void_ticket(tap._u155('o2atom'), 'admin_action', 'ck90-g2');
SELECT tap.logout();
SELECT tap._store155('a1_pre_close', to_jsonb(tap._attr155(tap._u155('o1')))::text);
-- the seam is definer-internal and pay_promoter_commission is unreachable outside the close
SELECT throws_ok(format($$SELECT kernel.pay_promoter_commission(gen_random_uuid(), ARRAY[%L::uuid], 'x')$$, (tap._attr155(tap._u155('o1'))).id), '42501', NULL,
  'G3: pay_promoter_commission refuses a caller that is not kernel.close_settlement via the seam (call-stack assertion — even as the owner)');
SELECT is((SELECT count(*)::int FROM kernel.settlement_commission_lines(gen_random_uuid())), 0, 'G4: the seam over an unknown settlement emits nothing and never raises');
-- s1: an event settlement over event1
SELECT tap.login(tap.seller());
SELECT tap._store155('s1', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), tap._u155('event1'), '{}'::jsonb, 'ck90-s1') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());   -- org_finance (matured)
SELECT tap._store155('c1', kernel.close_settlement(tap._u155('s1'), 'ck90-close1')::text);
SELECT tap.logout();
SELECT is((tap._fetch155('c1')::jsonb ->> 'status'), 'ok', 'G5: the settlement closes through 087''s frozen close_settlement');
SELECT is(tap._lines155(tap._u155('s1')), 7, 'G6: SEVEN promoter_commission lines — o1 (partial), o3, o4, o5, o6, o11, o14; o2 (refunded) none; o12/o13 (flagged, unreviewed) HELD — no line');
SELECT is((tap._line155((tap._attr155(tap._u155('o1'))).id)).amount_minor, -1000, 'G7: o1''s payable is recomputed from SURVIVING atoms: floor(10000 × 1000/10000) = 1000, booked as an org DEBIT (−1000; E-73)');
SELECT ok((SELECT bool_and(l.amount_minor < 0 AND l.currency = 'USD') FROM venue.settlement_line l WHERE l.settlement_id = tap._u155('s1') AND l.cause = 'promoter_commission'), 'G8: every commission line is negative, USD');
SELECT is((SELECT sum(l.amount_minor)::int FROM venue.settlement_line l WHERE l.settlement_id = tap._u155('s1') AND l.cause = 'promoter_commission'), -(1000+500+500+500+500+1000+600), 'G9: Σ lines = −4600');
-- 2026-09-02 (package 093): gross 0 -> 100000, net −4600 -> +95400. RATIFIED CONTRACT CHANGE —
-- PRIMARY_TICKETING_OWNER_RATIFICATION.md rulings A3/A5: kernel.settlement_primary_lines is
-- unioned into close_settlement as a third seam and credits venue entitlement at the CONFIGURED
-- TICKET FACE VALUE (ruling A5: "the venue-side entitlement begins with the configured ticket
-- face value"; no platform fee and no Stripe processing cost is subtracted). Until 093 gross was
-- structurally zero and every commission was a debit against nothing — this is the activation
-- the migration exists for, and the number is RECOMPUTED, not suppressed.
--
-- GROSS 100000 = sixteen +face_value lines over s1's event1 scope, enumerated exactly:
--   o1 15000 · o12 10000 · o14 10000 · and 5000 each for o2 o3 o4 o5 o6 o7 o8 o9 o10 o11 o13 o15 o16
-- DELIBERATELY ABSENT, and each absence is a seam property worth having asserted here:
--   o19  — currency EUR (155:741) vs the settlement's USD: the seam DROPS a currency mismatch
--          rather than raising, so 087:314-316 cannot roll the whole close back (088:346's idiom).
--   odoor— status 'pending' with no kernel.payment_native row: no money was received.
--   o2 IS present at +5000 even though it is 'refunded' (155:772): it was paid and its face value
--          WAS credited. The offsetting debit is a SEPARATE negative refund_void line keyed on the
--          kernel.refund row — and this fixture writes none, it pokes order.status directly.
-- FEES 4600 is unchanged, byte for byte: the seven commission debits of G9. The waterfall claim
-- this row exists to prove — commissions land in FEES, not REFUNDS — is asserted identically.
SELECT ok((SELECT gross_minor = 100000 AND fees_minor = 4600 AND refunds_minor = 0 AND net_minor = 95400 AND status = 'closed' FROM venue.settlement WHERE settlement_id = tap._u155('s1')),
  'G10: the E-73 waterfall: primary face value lands in GROSS (100000), commissions in the FEES bucket (4600), refunds 0; net = 95400');
-- 2026-09-02 (package 093): payout_ids [] -> ONE org payout. RATIFIED CONTRACT CHANGE (A3/A5):
-- net is now POSITIVE, so 087's unmodified `if v_net > 0` arm mints the settlement payout it
-- always would have. This is ruling A4 working as written — "eligible primary promoter commission
-- … reduces venue distributable BEFORE venue money is released": 100000 − 4600 = 95400.
-- THE ROW IS STRENGTHENED, NOT RELAXED. The old assertion pinned one fact (no payout). This pins
-- five: exactly one payout id, and that payout is the ORGANIZATION settlement payout for s1 at the
-- exact net, pending, and UNHELD — so a stray second payout, a wrong payee, a wrong amount or a
-- mis-set hold all fail here. The "no org payout on a NEGATIVE net" property that this row used to
-- carry is not lost: 153's H48 (NEGATIVE_SETTLEMENT_CARRY) still asserts payout_ids = [] on a
-- negative close, and it is unaffected by 093.
SELECT is((SELECT jsonb_array_length(tap._fetch155('c1')::jsonb -> 'payout_ids')), 1, 'G10b: …a POSITIVE net mints exactly ONE org payout (A4: commission funded out of gross before venue money is released)');
-- 2026-09-02 (package 093, second money pass): the payout is minted HELD here, and that is the
-- ratified contract rather than a defect. 155 never sets 'settlement.refund_window_interval', which
-- ships seeded 'null'::jsonb, so close_settlement mints
-- hold_state='held' / hold_reason_code='unbounded_refund_exposure': a refund succeeding after this
-- close could never be collected, so the obligation is recorded in full and only the MONEY is
-- immobilised. That is the point worth asserting HERE, because 155 is the file that proves ruling
-- A4's funding order — the venue's 95400 is what remains after the promoter's 4600 is deducted, and
-- it does not move. Both arms of the gate, and kernel.release_payout as the contracted exit, are
-- proved at 151 C20i..C20n / C28a/C28b. Every other fact below is pinned exactly as before.
SELECT ok((SELECT po.payee_kind = 'organization' AND po.payee_org_id = tap._u155('org1') AND po.cause = 'settlement' AND po.cause_ref = tap._u155('s1')
                  AND po.amount_minor = 95400 AND po.currency = 'USD' AND po.status = 'pending'
                  AND po.hold_state = 'held' AND po.hold_reason_code = 'unbounded_refund_exposure' AND po.held_by IS NULL AND po.held_at IS NOT NULL
             FROM kernel.payout po WHERE po.payout_id = ((tap._fetch155('c1')::jsonb -> 'payout_ids') ->> 0)::uuid),
  'G10c: …and it is the org settlement payout: organization/org1, cause settlement:s1, 95400 USD, pending, and HELD unbounded_refund_exposure by the platform (held_by NULL) — the obligation is durable, the money is not released');
SELECT is((SELECT count(*)::int FROM kernel.payout po WHERE po.cause = 'promoter_commission'), 7, 'G11: SEVEN promoter_commission payouts — one per lined attribution');
SELECT ok((SELECT bool_and(po.payee_kind = 'identity' AND po.status = 'pending' AND po.hold_state = 'held' AND po.hold_reason_code = 'unfunded_settlement' AND po.held_by IS NULL AND po.amount_minor > 0 AND po.currency = 'USD'
                           AND po.idempotency_key = 'promoter_commission:' || po.cause_ref::text || ':' || po.payee_identity_id::text)
             FROM kernel.payout po WHERE po.cause = 'promoter_commission'),
  'G12: each payout: identity payee, pending, HELD unfunded_settlement (E-138 / X-12 — no funding leg exists in Phase 2), +amount, idempotency_key = ''promoter_commission:<attribution_id>:<payee_identity_id>'' BYTE FOR BYTE (§4.2(3))');
SELECT is(tap._outbox155('payout_on_hold', (tap._payout155((tap._attr155(tap._u155('o1'))).id)).payout_id), 1, 'G12b: the hold is BE-noticed (payout_on_hold, reason unfunded_settlement)');
SELECT throws_ok(format($$SELECT kernel.mark_payout_transfer_state(%L, 'paid', 'tr_x', NULL, 'ck90-g12c')$$, (tap._payout155((tap._attr155(tap._u155('o1'))).id)).payout_id), 'P0001', NULL, 'G12c: a HELD commission payout cannot be advanced to paid (payout_held) — no money leaves until the funding source is ruled');
SELECT tap.login(tap.risk155()); SELECT tap._aal2();
SELECT is((kernel.release_payout((tap._payout155((tap._attr155(tap._u155('o14'))).id)).payout_id, 'ck90-g12d') ->> 'status'), 'ok', 'G12d: the release path exists — platform_risk releases a funded commission payout (Control-5)');
SELECT tap.logout();
SELECT ok((SELECT po.hold_state = 'none' AND po.status = 'pending' FROM tap._payout155((tap._attr155(tap._u155('o14'))).id) po), 'G12e: …hold cleared, status untouched (MB-2: the hold overlay never touches status)');
SELECT ok((SELECT po.payee_identity_id = tap.other_user() AND po.amount_minor = 1000 FROM tap._payout155((tap._attr155(tap._u155('o1'))).id) po), 'G13: o1''s payout: 1000 to promoter P''s identity');
SELECT ok((SELECT po.payee_identity_id = tap.fan155() AND po.amount_minor = 600 FROM tap._payout155((tap._attr155(tap._u155('o14'))).id) po), 'G14: o14''s payout: 600 (flat 300 × 2) to promoter Q''s identity');
SELECT ok((SELECT bool_and(-l.amount_minor = po.amount_minor) FROM venue.settlement_line l JOIN kernel.payout po ON po.cause = 'promoter_commission' AND po.cause_ref = l.cause_ref
            WHERE l.settlement_id = tap._u155('s1') AND l.cause = 'promoter_commission'), 'G15: money conservation — every line''s debit equals its payout''s credit');
SELECT is(tap._outbox155('promoter_commission_accrued', (tap._attr155(tap._u155('o1'))).id), 1, 'G16: G-25 #32 PromoterCommissionAccrued BE-emitted per accrual (dedup commission:<attribution_id>)');
SELECT is((SELECT count(*)::int FROM notify.outbox o WHERE o.event_type = 'promoter_commission_accrued' AND o.event_key = 'commission:' || (tap._attr155(tap._u155('o12'))).id::text), 0, 'G16b: …and none for a held attribution');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit a WHERE a.action = 'settlement.commission' AND a.subject_id = tap._u155('s1')), 1, 'G17: one settlement.commission audit row names the held set');
SELECT ok((SELECT (a.after -> 'held') @> jsonb_build_array(jsonb_build_object('attribution_id', (tap._attr155(tap._u155('o12'))).id, 'reason', 'unreviewed_flag'))
              AND (a.after -> 'held') @> jsonb_build_array(jsonb_build_object('attribution_id', (tap._attr155(tap._u155('o13'))).id, 'reason', 'unreviewed_flag'))
              AND NOT ((a.after -> 'held') @> jsonb_build_array(jsonb_build_object('attribution_id', (tap._attr155(tap._u155('o2'))).id, 'reason', 'basis_zero')))
              AND (a.after ->> 'lines_written')::int = 7
             FROM kernel.admin_audit a WHERE a.action = 'settlement.commission' AND a.subject_id = tap._u155('s1')),
  'G18: …held[] explains the arithmetic: o12/o13 unreviewed_flag (revisable holds); the refunded o2 is a TERMINAL class the seam excludes before the primitive runs (E-146) — no line, not re-walked');
SELECT is(to_jsonb(tap._attr155(tap._u155('o1'))), tap._fetch155('a1_pre_close')::jsonb, 'G19: the attribution row is BYTE-IDENTICAL after the partial void and the close (§12.45) — credited stays the accrual, payable lives on the line');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.close_settlement(tap._u155('s1'), 'ck90-close1b') ->> 'status'), 'noop_replay', 'G20: a re-close is a noop_replay');
SELECT tap.logout();
SELECT is(tap._lines155(tap._u155('s1')) + (SELECT count(*)::int FROM kernel.payout po WHERE po.cause = 'promoter_commission'), 14, 'G20b: …no second line, no second payout');
-- structural uniqueness (§4.2): the three constraints, exercised
SELECT tap.login(tap.seller());
SELECT tap._store155('s2', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), NULL,
  jsonb_build_object('period_start', (now())::text, 'period_end', (now() + interval '30 days')::text), 'ck90-s2') ->> 'settlement_id'));
SELECT tap.logout();
SELECT throws_ok(format($$INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (%L, 'promoter_commission', %L, -1)$$, tap._u155('s2'), (tap._attr155(tap._u155('o1'))).id),
  '23505', NULL, 'G21: §12.33 — lining the SAME attribution into a SECOND settlement is rejected by attribution_one_commission_line_ever (the assertion that failed before §3.14.1)');
SELECT throws_ok(format($$INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (%L, 'promoter_commission', %L, -1)$$, tap._u155('s1'), (tap._attr155(tap._u155('o1'))).id),
  '23505', NULL, 'G22: §12.32 — …and into the same settlement');
SELECT throws_ok(format($$INSERT INTO kernel.payout (payee_kind, payee_identity_id, cause, cause_ref, amount_minor, status, idempotency_key) VALUES ('identity', %L, 'promoter_commission', %L, 1, 'pending', %L)$$,
  tap.other_user(), (tap._attr155(tap._u155('o1'))).id, 'promoter_commission:' || (tap._attr155(tap._u155('o1'))).id::text || ':' || tap.other_user()::text),
  '23505', NULL, 'G23: §12.34 — a second payout with the same (cause, cause_ref, payee) collides on idempotency_key');
SELECT throws_ok(format($$INSERT INTO venue.attribution (order_id, promoter_id, org_id, event_id, code_id, method, touch_corroborated, terms_version, commission_kind, commission_bps_applied, basis_minor, credited_amount_minor, resolution_reason, order_paid_at)
  VALUES (%L, %L, %L, %L, %L, 'code', false, 1, 'bps', 1000, 1, 0, 'code_only', now())$$, tap._u155('o1'), tap._u155('promP'), tap._u155('org1'), tap._u155('event1'), tap._u155('codeP')),
  '23505', NULL, 'G24: §12.35 — two attributions for one order_id raise');
-- s2 (period settlement) sees nothing new: o12/o13 still held, everything else lined
SELECT tap.login(tap.admin_user());
SELECT tap._store155('c2', kernel.close_settlement(tap._u155('s2'), 'ck90-close2')::text);
SELECT tap.logout();
SELECT is(tap._lines155(tap._u155('s2')), 0, 'G25: a second (period) settlement over the same venue lines NOTHING already lined — and the held rows roll forward, unlined');
-- adjudication (§7.7 / AUTHZ-H10)
SELECT tap.login(tap.pm155());
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g26')$$, (tap._attr155(tap._u155('o12'))).id), '42501', NULL, 'G26: AUTHZ-H10 — venue_promoter_manager is DENIED (fox at the henhouse)');
SELECT tap.logout();
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at) VALUES (tap._u155('org1'), tap.dp155(), 'org_promoter_manager', tap.seller(), now() - interval '40 days');
UPDATE kernel.identity_ext SET deletion_state = 'ACTIVE' WHERE identity_id = tap.dp155();
SELECT tap.login(tap.dp155());
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g27')$$, (tap._attr155(tap._u155('o12'))).id), '42501', NULL, 'G27: AUTHZ-H10 — org_promoter_manager is DENIED too');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g28')$$, (tap._attr155(tap._u155('o12'))).id), '42501', NULL, 'G28: a fan is denied');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g29')$$, (tap._attr155(tap._u155('o12'))).id), '42501', NULL, 'G29: the promoter cannot release their own flag');
SELECT tap.logout();
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES (tap._u155('venue1'), tap.other_user(), 'venue_manager', tap.seller());
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g29b')$$, (tap._attr155(tap._u155('o12'))).id), '42501', NULL, 'G29b: separation of duties — even as venue_manager, the attributed promoter cannot adjudicate their OWN flag');
SELECT tap.logout();
DELETE FROM venue.staff_role WHERE venue_id = tap._u155('venue1') AND identity_id = tap.other_user() AND role = 'venue_manager';
SELECT ok((SELECT p.prosrc LIKE '%attribution.review:%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='pay_promoter_commission'), 'G29c: pay_promoter_commission takes the SAME per-attribution advisory key as review_attribution_flag — release/deny cannot interleave with the decision read (the money and the decision freeze together)');
SELECT tap.login(tap.seller());   -- org_owner over the venue
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g30')$$, (tap._attr155(tap._u155('o4'))).id), 'P0001', NULL, 'G30: not_flagged — an unflagged attribution cannot be adjudicated');
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'approve', 'legitimate_guest_purchase', NULL, 'ck90-g31')$$, (tap._attr155(tap._u155('o12'))).id), '22023', NULL, 'G31: bad_decision');
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'release', 'looks_fine', NULL, 'ck90-g32')$$, (tap._attr155(tap._u155('o12'))).id), '22023', NULL, 'G32: invalid_reason_code');
SELECT tap._store155('r1', venue.review_attribution_flag((tap._attr155(tap._u155('o12'))).id, 'release', 'legitimate_guest_purchase', 'own table for own guests', 'ck90-g33')::text);
SELECT is((tap._fetch155('r1')::jsonb ->> 'seq')::int, 1, 'G33: org_owner releases o12 at seq 1');
SELECT is((venue.review_attribution_flag((tap._attr155(tap._u155('o12'))).id, 'release', 'legitimate_guest_purchase', NULL, 'ck90-g33') ->> 'status'), 'idempotency_replay', 'G33b: a replay is idempotency_replay (no seq 2)');
SELECT tap.logout();
SELECT tap.login(tap.risk155());
SELECT is((venue.review_attribution_flag((tap._attr155(tap._u155('o13'))).id, 'deny', 'duplicate_account_suspected', 'shared card', 'ck90-g34') ->> 'seq')::int, 1, 'G34: platform_risk denies o13 at seq 1');
SELECT tap.logout();
SELECT ok((SELECT a.self_deal_flag AND a.credited_amount_minor = 2000 FROM tap._attr155(tap._u155('o12')) a), 'G35: the attribution row is NOT touched by adjudication (flag and accrual unchanged)');
-- s3: the released flag pays at the NEXT close; the denied one never
SELECT tap.login(tap.seller());
SELECT tap._store155('s3', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), tap._u155('event1'), '{}'::jsonb, 'ck90-s3') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u155('s3'), 'ck90-close3');
SELECT tap.logout();
SELECT is(tap._lines155(tap._u155('s3')), 1, 'G36: T-RPC-MONEY-19 — the RELEASED attribution (o12) is lined at the next close; the DENIED one (o13) is not');
SELECT ok((SELECT l.amount_minor = -2000 FROM tap._line155((tap._attr155(tap._u155('o12'))).id) l) AND (SELECT po.amount_minor = 2000 FROM tap._payout155((tap._attr155(tap._u155('o12'))).id) po), 'G37: o12: −2000 line, +2000 payout');
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.review_attribution_flag(%L, 'deny', 'policy_violation', NULL, 'ck90-g38')$$, (tap._attr155(tap._u155('o12'))).id), 'P0001', NULL, 'G38: T-RPC-MONEY §12.63 — a review after the commission line exists → attribution_settled (the money and the decision froze together)');
-- supersession: o13 deny (seq 1) → release (seq 2); both rows survive; effective = max(seq)
SELECT is((venue.review_attribution_flag((tap._attr155(tap._u155('o13'))).id, 'release', 'shared_instrument_explained', 'spouse card', 'ck90-g39') ->> 'seq')::int, 2, 'G39: a wrong denial is corrected by APPENDING seq 2');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.attribution_review r WHERE r.attribution_id = (tap._attr155(tap._u155('o13'))).id), 2, 'G40: §12.64 — both rows survive');
SELECT throws_ok(format($$UPDATE venue.attribution_review SET decision = 'deny' WHERE attribution_id = %L$$, (tap._attr155(tap._u155('o13'))).id), 'P0001', NULL, 'G41: the review ledger is AO (UPDATE raises for the owner)');
SELECT throws_ok(format($$DELETE FROM venue.attribution_review WHERE attribution_id = %L$$, (tap._attr155(tap._u155('o13'))).id), 'P0001', NULL, 'G41b: …DELETE raises');
-- 2026-09-02 (package 093): NEW COVERAGE for RATIFIED ruling A4. 090:1535 excluded only
-- ('refunded','cancelled'); 093 adds 'partially_refunded' to that terminal class. The defect it
-- closes: a DIRECT partial refund voids NO atoms (085:571-573 makes the void scope conditional on
-- v_full), so the surviving-atom basis at 090:1461-1466 is completely unreduced and FULL commission
-- would be paid on partly refunded revenue — and 093 is what gives this seam revenue to deduct
-- from, so the defect would have gone live with it. o13 is the only attribution still unlined at
-- this point, which makes it the one place the new exclusion can be isolated from the seam's
-- never-lined-before dedupe. The status is restored immediately so G42 still proves the
-- release-at-seq-2 payout on an untouched fixture.
UPDATE venue."order" SET status = 'partially_refunded' WHERE order_id = tap._u155('o13');
SELECT tap.login(tap.seller());
SELECT tap._store155('s4pr', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), tap._u155('event1'), '{}'::jsonb, 'ck90-s4pr') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u155('s4pr'), 'ck90-close4pr');
SELECT tap.logout();
SELECT is(tap._lines155(tap._u155('s4pr')), 0,
  'G41c: ruling A4 — a PARTIALLY_REFUNDED order yields NO commission line, even with an effective release decision (093 adds partially_refunded to 090:1535''s terminal-class exclusion)');
SELECT is((SELECT count(*)::int FROM kernel.payout po WHERE po.cause = 'promoter_commission' AND po.cause_ref = (tap._attr155(tap._u155('o13'))).id), 0,
  'G41d: …and NO commission payout is minted for it — the exclusion happens before pay_promoter_commission runs, so nothing is accrued, held or released');
UPDATE venue."order" SET status = 'paid' WHERE order_id = tap._u155('o13');
SELECT tap.login(tap.seller());
SELECT tap._store155('s4', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), tap._u155('event1'), '{}'::jsonb, 'ck90-s4') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u155('s4'), 'ck90-close4');
SELECT tap.logout();
SELECT ok(tap._lines155(tap._u155('s4')) = 1 AND (SELECT po.amount_minor = 1000 FROM tap._payout155((tap._attr155(tap._u155('o13'))).id) po), 'G42: the effective decision (seq 2 = release) pays o13 (1000 — attributed under terms v2) at the next close');
SELECT is((SELECT count(*)::int FROM kernel.payout po WHERE po.cause = 'promoter_commission'), 9, 'G43: nine commission payouts in total; every attribution paid at most once');
SELECT is((SELECT count(*)::int FROM venue.settlement_line l WHERE l.cause = 'promoter_commission'), 9, 'G43b: nine lines — one per paid attribution, across four settlements');
-- E-128: an affiliate (no identity) accrues but is held payee_unresolvable; the org keeps the money
SELECT tap._neworder155('o18', tap.buyer(), tap._u155('session1'), tap._u155('org1'), tap._u155('tt1'), tap._u155('batch1'), 1, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o18'), 'AFFIL', NULL, 'ck90-b-o18'); SELECT tap.logout();
SELECT tap._store155('pay18', tap._newpayment155(tap.buyer(), tap.seller(), 5000, 'pi_90_18')::text);
SELECT venue.finalize_primary_order(tap._u155('o18'), tap._u155('pay18'), 'ck90-f-o18', NULL);
SELECT ok((SELECT a.promoter_id = tap._u155('promA') AND a.credited_amount_minor = 250 FROM tap._attr155(tap._u155('o18')) a), 'G44: the affiliate''s code attributes (250 on 5000 at 500 bps)');
SELECT tap.login(tap.seller());
SELECT tap._store155('s5', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), tap._u155('event1'), '{}'::jsonb, 'ck90-s5') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u155('s5'), 'ck90-close5');
SELECT tap.logout();
SELECT ok(tap._lines155(tap._u155('s5')) = 0 AND (SELECT count(*) = 0 FROM kernel.payout po WHERE po.cause = 'promoter_commission' AND po.cause_ref = (tap._attr155(tap._u155('o18'))).id)
       AND (SELECT count(*) = 0 FROM kernel.admin_audit a WHERE a.action = 'settlement.commission' AND a.subject_id = tap._u155('s5')),
  'G45: E-128 — no line, no payout for an identity-less payee: the seam excludes it as a terminal class before the primitive runs (the slot stays open; no silent money sink; nothing re-walked at every close)');
-- event cancellation (§5.4): every basis goes to 0 — no commission, no cancellation-specific logic
SELECT tap._neworder155('o17', tap.buyer(), tap._u155('session2'), tap._u155('org1'), tap._u155('tt2'), tap._u155('batch2'), 1, 4000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u155('o17'), 'jordy', NULL, 'ck90-b-o17'); SELECT tap.logout();
SELECT tap._store155('pay17', tap._newpayment155(tap.buyer(), tap.seller(), 4000, 'pi_90_17')::text);
SELECT venue.finalize_primary_order(tap._u155('o17'), tap._u155('pay17'), 'ck90-f-o17', NULL);
SELECT ok((SELECT a.credited_amount_minor = 800 AND a.event_id = tap._u155('event2') FROM tap._attr155(tap._u155('o17')) a), 'G46: o17 (event2) accrues 800 (bps 2000 on 4000) — E7: the unscoped code works org-wide');
SELECT tap._store155('a17', to_jsonb(tap._attr155(tap._u155('o17')))::text);
SELECT tap.login(tap.seller()); SELECT tap._aal2();
SELECT is((catalog.cancel_event(tap._u155('event2'), 'weather', 'ck90-ce2') ->> 'status'), 'ok', 'G47: the org owner cancels event2 (SSCAS #10 — every order refunded)');
SELECT tap._store155('s6', (venue.open_settlement(tap._u155('org1'), tap._u155('venue1'), tap._u155('event2'), '{}'::jsonb, 'ck90-s6') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u155('s6'), 'ck90-close6');
SELECT tap.logout();
SELECT is(tap._lines155(tap._u155('s6')), 0, 'G48: §12.46 — a cancelled event yields NO commission line for its attributed order (basis 0 — falls out of §5.2)');
SELECT is(to_jsonb(tap._attr155(tap._u155('o17'))), tap._fetch155('a17')::jsonb, 'G49: …and the attribution row is untouched (AO — the ledger records both the sale and its reversal)');
-- resale / transfer (§5.5/§5.6): structural — nothing outside the primary order can create an attribution or a commission candidate
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market' AND (p.prosrc ~ 'venue\.attribution' OR p.prosrc ~ 'promoter_commission')), 0,
  'G50: §12.48 — no market routine touches venue.attribution or the commission cause (a resale earns the original promoter nothing)');
SELECT ok((SELECT p.prosrc !~ 'market\.' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_commission_lines'),
  'G51: the commission seam reads no market relation — candidates come only from venue.attribution (order-grain)');

-- ============================================================================
-- SECTION H — READS, ISOLATION, THE PREDICATE (RPC §17.19 / §1.1c; PROMOTER §8; §12 H)
-- ============================================================================
SELECT tap.login(tap.other_user());   -- promoter P
SELECT tap._store155('sumP', venue.get_my_promoter_summary(tap._u155('org1'), NULL, '{}')::text);
SELECT ok((tap._fetch155('sumP')::jsonb ->> 'commission_accrued_minor')::int = 1500+500+500+500+500+500+1000+2000+1000+800   -- o2's accrual stays on the ledger after its refund (AO)
       AND (tap._fetch155('sumP')::jsonb ->> 'commission_held_minor')::int = 0 AND (tap._fetch155('sumP')::jsonb ->> 'commission_paid_minor')::int = 0
       AND (tap._fetch155('sumP')::jsonb ->> 'code_count')::int = 8 AND (tap._fetch155('sumP')::jsonb ->> 'link_count')::int = 1,
  'H1: get_my_promoter_summary(P): accrued 8800 across ten sales (o2 refunded — its accrual still shows; payable was 0); held 0 (both flags adjudicated); paid 0 (payouts pending); 8 codes; 1 link');
SELECT is((tap._fetch155('sumP')::jsonb ->> 'tickets_attributed')::int, 3+1+1+1+1+1+1+2+1+1, 'H1b: 13 tickets attributed');
SELECT is(jsonb_array_length(tap._fetch155('sumP')::jsonb -> 'per_event'), 2, 'H1c: two per-event rows (event1, event2)');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch155('sumP')::jsonb) k),
  ARRAY['code_count','commission_accrued_minor','commission_held_minor','commission_paid_minor','gross_attributed_minor','link_count','per_event','tickets_attributed'],
  'H2: the summary carries EXACTLY its contracted fields (no buyer, no org total, no fingerprint)');
SELECT throws_ok(format($$SELECT venue.get_my_promoter_summary(%L, NULL, '{}')$$, tap._u155('org2')), '42501', NULL, 'H3: §12.52 — the filter cannot be widened by passing another org''s id');
SELECT tap._store155('listP', venue.list_my_attributions(tap._u155('org1'), '{}', NULL)::text);
SELECT is(jsonb_array_length(tap._fetch155('listP')::jsonb -> 'rows'), 10, 'H4: list_my_attributions(P): ten rows');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch155('listP')::jsonb -> 'rows' -> 0) k),
  ARRAY['basis_minor','credited_amount_minor','cursor','event_title','method','occurred_at','payout_status','qty','review_decision','review_reason_code','self_deal_flag','self_deal_reasons','terms_version','ticket_type'],
  'H5: T-RPC-PROMO-11 — the promoter''s projection is EXACT: no buyer name/email/id, no order ref, no displaced_promoter_id, no note, NO touch_corroborated, no fingerprint (column-list comparison)');
SELECT ok((SELECT count(*) = 10 FROM jsonb_array_elements(tap._fetch155('listP')::jsonb -> 'rows') r WHERE r ->> 'method' IN ('code','link')), 'H6: method always shown');
SELECT ok((SELECT count(*) >= 1 FROM jsonb_array_elements(tap._fetch155('listP')::jsonb -> 'rows') r WHERE r ->> 'method' = 'code' AND r ->> 'occurred_at' IS NOT NULL), 'H7: T-RPC-PROMO-09 — code-sourced rows (link_id NULL) ARE visible to their own promoter');
SELECT ok((SELECT (r ->> 'review_decision') = 'release' AND (r ->> 'review_reason_code') = 'legitimate_guest_purchase' AND (r ->> 'payout_status') = 'pending'
             FROM jsonb_array_elements(tap._fetch155('listP')::jsonb -> 'rows') r WHERE (r ->> 'self_deal_reasons')::jsonb ? 'same_identity'), 'H8: the flagged row shows its decision + reason code and payout status');
SELECT tap._store155('page1', venue.list_my_attributions(tap._u155('org1'), '{"limit":4}', NULL)::text);
SELECT ok(jsonb_array_length(tap._fetch155('page1')::jsonb -> 'rows') = 4 AND (tap._fetch155('page1')::jsonb -> 'next_cursor') IS NOT NULL, 'H9: keyset page 1 (limit 4) carries a next_cursor');
SELECT tap._store155('page2', venue.list_my_attributions(tap._u155('org1'), '{"limit":4}', tap._fetch155('page1')::jsonb -> 'next_cursor')::text);
SELECT ok(jsonb_array_length(tap._fetch155('page2')::jsonb -> 'rows') = 4
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(tap._fetch155('page1')::jsonb -> 'rows') a JOIN jsonb_array_elements(tap._fetch155('page2')::jsonb -> 'rows') b ON a -> 'cursor' = b -> 'cursor'),
  'H10: page 2 is disjoint from page 1 (keyset on order_paid_at DESC, id DESC)');
SELECT throws_ok($$SELECT * FROM venue.attribution$$, '42501', NULL, 'H11: AUTHZ-M9 — the promoter has NO direct SELECT on venue.attribution');
SELECT throws_ok($$SELECT * FROM venue.attribution_review$$, '42501', NULL, 'H11b: …nor on attribution_review');
SELECT is((SELECT count(*)::int FROM venue.promoter), 1, 'H12: direct table: the promoter sees ONLY their own promoter row');
SELECT is((SELECT count(*)::int FROM venue.promoter_code), 8, 'H13: …only their own codes (8)');
SELECT is((SELECT count(*)::int FROM venue.promoter_link), 1, 'H14: …only their own link');
SELECT ok(kernel.is_promoter_for_event(tap._u155('event1')) AND kernel.is_promoter_for_event(tap._u155('event2')) AND NOT kernel.is_promoter_for_event(tap._u155('event3')),
  'H15: is_promoter_for_event(P): event1 (link + code), event2 (unscoped code — E7/E-127), not another org''s event');
SELECT throws_ok(format($$SELECT venue.list_promoter_attributions('event', %L, '{}', NULL)$$, tap._u155('event1')), '42501', NULL, 'H16: the promoter is denied the back-office view');
SELECT tap.logout();
SELECT tap.login(tap.fan155());   -- promoter Q
SELECT is(jsonb_array_length(venue.list_my_attributions(tap._u155('org1'), '{}', NULL) -> 'rows'), 1, 'H17: §12.49 — promoter Q sees ONLY their own attribution (never P''s)');
SELECT is((SELECT count(*)::int FROM venue.promoter_code), 1, 'H18: §12.50 — Q cannot SELECT P''s codes (own only)');
SELECT ok(kernel.is_promoter_for_event(tap._u155('event1')) AND NOT kernel.is_promoter_for_event(tap._u155('event2')), 'H19: is_promoter_for_event(Q): event1 only (scoped code + link; single-event promoter)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.get_my_promoter_summary(%L, NULL, '{}')$$, tap._u155('org1')), '42501', NULL, 'H20: a caller with no promoter row is refused (never an empty success)');
SELECT throws_ok(format($$SELECT venue.list_my_attributions(%L, '{}', NULL)$$, tap._u155('org1')), '42501', NULL, 'H20b: …on both promoter reads');
SELECT throws_ok(format($$SELECT venue.list_promoter_attributions('venue', %L, '{}', NULL)$$, tap._u155('venue1')), '42501', NULL, 'H21: a fan is denied the back-office view');
SELECT ok(NOT kernel.is_promoter_for_event(tap._u155('event1')), 'H22: a fan is not a promoter for anything');
SELECT is((SELECT count(*)::int FROM venue.promoter) + (SELECT count(*)::int FROM venue.promoter_code) + (SELECT count(*)::int FROM venue.promoter_link), 0, 'H23: a fan sees no promoter/code/link row');
SELECT tap.logout();
SELECT tap.login(tap.pm155());   -- venue_promoter_manager: the back-office read admits them (§11.5)
SELECT tap._store155('office', venue.list_promoter_attributions('event', tap._u155('event1'), '{}', NULL)::text);
SELECT is(jsonb_array_length(tap._fetch155('office')::jsonb -> 'rows'), 11, 'H24: list_promoter_attributions(event1) as venue_promoter_manager: eleven rows (P 8 + Q 1 + M 0 + the affiliate 1 + o13 — every event1 attribution)');
SELECT ok((SELECT bool_and(r ? 'touch_corroborated' AND r ? 'method' AND r ? 'self_deal_flag' AND r ? 'terms_version' AND r ? 'order_ref' AND r ? 'ticket_type' AND r ? 'qty' AND r ? 'gross_attributed_minor' AND r ? 'commission_minor')
             FROM jsonb_array_elements(tap._fetch155('office')::jsonb -> 'rows') r), 'H25: dash §10.6''s columns are all present (method / touch_corroborated / self_deal_flag / terms version …)');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(tap._fetch155('office')::jsonb -> 'rows') r, jsonb_object_keys(r) k WHERE k ~* 'buyer|email|fingerprint|name$'), 0,
  'H26: T-RPC-PROMO-10 — no buyer PII key in any back-office row (the promoter dimension is not a back door into the attendee list)');
SELECT ok((SELECT (r ->> 'displaced_promoter') = 'Jordy Q' AND (r ->> 'resolution_reason') = 'code_over_link' AND (r ->> 'settled')::boolean
             FROM jsonb_array_elements(tap._fetch155('office')::jsonb -> 'rows') r WHERE (r ->> 'order_ref') = left(replace(tap._fetch155('o1'),'-',''), 8)),
  'H27: o1''s row shows the displaced promoter resolved to a display name, its resolution reason, and settled=true');
SELECT tap.logout();
SELECT tap.login(tap.fan2155());   -- org2's owner
SELECT throws_ok(format($$SELECT venue.list_promoter_attributions('venue', %L, '{}', NULL)$$, tap._u155('venue1')), '42501', NULL, 'H28: another org''s owner cannot read venue1''s attribution view');
SELECT is(jsonb_array_length(venue.list_promoter_attributions('org', tap._u155('org2'), '{}', NULL) -> 'rows'), 0, 'H29: …their own org scope is readable and empty');
SELECT is((SELECT count(*)::int FROM venue.promoter), 1, 'H30: org2''s owner sees only org2''s promoter (R)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((SELECT count(*)::int FROM venue.promoter), 4, 'H31: org1''s owner sees org1''s four promoters (P, Q, A, M) — not R');
SELECT is(jsonb_array_length(venue.list_promoter_attributions('org', tap._u155('org1'), '{}', NULL) -> 'rows'), 12, 'H32: the org scope lists all twelve org1 attributions (event1 eleven + event2 one)');
SELECT is(jsonb_array_length(venue.list_promoter_attributions('venue', tap._u155('venue1'), jsonb_build_object('promoter_id', tap._u155('promQ')), NULL) -> 'rows'), 1, 'H33: the promoter_id filter narrows to Q''s one');
SELECT throws_ok($$SELECT venue.list_promoter_attributions('planet', gen_random_uuid(), '{}', NULL)$$, '22023', NULL, 'H34: an unknown scope_kind is invalid_input');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());   -- platform_support + platform_admin
SELECT is((SELECT count(*)::int FROM venue.promoter), 5, 'H35: platform reads every promoter row (A)');
SELECT throws_ok($$SELECT * FROM venue.attribution$$, '42501', NULL, 'H36: …but the attribution ledger stays an RPC projection even for the platform plane (V — no table grant)');
SELECT is(jsonb_array_length(venue.list_promoter_attributions('org', tap._u155('org1'), '{}', NULL) -> 'rows'), 12, 'H36b: …and that projection IS readable by the platform plane (platform_risk adjudicates what it can read; support V)');
SELECT tap.logout();
-- T-RPC-AUTHZ-11: a code-only promoter with NO live link is a promoter for the event
SELECT tap.login(tap.buyer2155());   -- promoter M (link inactive, no code yet)
SELECT ok(NOT kernel.is_promoter_for_event(tap._u155('event1')), 'H37: M with an inactive link and no code is NOT a promoter for event1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT venue.create_promoter_code(tap._u155('promM'), 'MCODE1', ARRAY[tap._u155('event1')], NULL, NULL, 'vanity', 'ck90-h38');
SELECT tap.logout();
SELECT tap.login(tap.buyer2155());
SELECT ok(kernel.is_promoter_for_event(tap._u155('event1')) AND NOT kernel.is_promoter_for_event(tap._u155('event2')), 'H38: T-RPC-AUTHZ-11 — a code scoped to event1 and NO link at all satisfies is_promoter_for_event (event1 only)');
SELECT tap.logout();

-- ============================================================================
-- SECTION I — ODR-16 (OR-13): the promoter hook + the tombstone posture
-- ============================================================================
SELECT ok((SELECT status_changed_by = tap.pm155() FROM venue.promoter_link WHERE link_id = tap._u155('linkM')), 'I1: before erasure linkM.status_changed_by names pm155');
SELECT kernel.on_identity_erased_promoter(tap.pm155());
SELECT ok((SELECT status_changed_by IS NULL AND status = 'inactive' FROM venue.promoter_link WHERE link_id = tap._u155('linkM')), 'I2: INV #36 — status_changed_by is CLEANED (SET NULL); the status itself survives');
SELECT ok((SELECT created_by = tap.pm155() FROM venue.promoter_code WHERE code_id = tap._u155('codePM')), 'I3: INV #37 — promoter_code.created_by SURVIVES (codes outlive their issuer)');
SELECT is((SELECT count(*)::int FROM venue.promoter), 5, 'I4: INV #35 — every promoter row survives an erasure pass');
SELECT ok((SELECT bool_and(r.decided_by IS NOT NULL) FROM venue.attribution_review r), 'I5: INV #38 — attribution_review.decided_by is TOMBSTONED (untouched)');
SELECT ok((SELECT p.prosrc !~ 'venue\.promoter\b' AND p.prosrc !~ 'promoter_code' AND p.prosrc !~ 'attribution' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_promoter'),
  'I6: the hook writes promoter_link and nothing else (writer registry parity)');
SELECT is((SELECT count(*)::int FROM venue.promoter p WHERE p.identity_id = tap.other_user()), 1, 'I7: the commission-entitlement key (the promoter row) is retained for the promoter identity');

SELECT * FROM finish();
ROLLBACK;
