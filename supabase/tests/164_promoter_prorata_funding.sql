-- ============================================================================
-- 164_promoter_prorata_funding.sql — package 098 (promoter pro-rata funding,
--   PFA-PT-4). Executes the KF_promoter_prorata.md cases against the shipped
--   098 bodies of kernel.settlement_commission_lines, kernel.
--   pay_promoter_commission and kernel.mark_payout_transfer_state.
--
-- Frozen/investigator sources: docs/phase2/_impl/KF_promoter_prorata.md §2.1/
--   §4.2/§4.4/§4.5 (the rule and the executed numbers), 090:1401-1548 (the
--   commission leg, pre-098), 093:857-930 (10e, pre-098), 085:1668-1735 (the
--   state-sync pair), PHASE_2_PROMOTER_CODES_SPEC.md §5.2/§6.1-6.3, PFA-PT-4
--   (docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md). Fixture idiom
--   reused from supabase/tests/155_phase2_venue_promoter_engine.sql (persona/
--   org/venue/event/order helpers) and 159_refund_accounting_timing.sql
--   (refund forward-only state-sync calling convention).
--
-- SHAPE. Every case shares ONE order geometry — 2 tickets × 5000 = face 10000
--   — under org1/venue1, promoter P (other_user, bps 1000 = 10%, org-wide,
--   code PCODE98) or promoter F (a dedicated identity, flat_per_ticket 300,
--   org-wide, code FCODE98) — so every expected number is exactly the KF §4.2
--   formula applied to one face value, and a reader can check it by hand.
--   Each case (or case-pair, for E/Disp which need two attributions closing
--   TOGETHER) gets its OWN event/session/ticket_type/batch so settlements
--   never cross-contaminate. refund_primary_order (platform-authority DEF) is
--   called as the table owner under tap.set_claims(admin_user()) WITHOUT
--   tap.login — the session role stays the runner's (bypasses the service_role
--   EXEC grant), while auth.uid() resolves to admin_user() for the internal
--   is_platform() check (KF §9 repro note). mark_refund_state/
--   record_dispute_native/mark_dispute_state carry no internal authority
--   check (service_role EXEC grant only) and are called directly as the table
--   owner with no claims needed.
--
-- BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(29);

SELECT tap.seed_core();

CREATE TABLE tap.memo_164 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store164(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_164 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._u164(k text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_164 WHERE k=$1 $m$;
CREATE FUNCTION tap._cfg164(p_key text, p_val jsonb, p_vis text DEFAULT 'restricted') RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.platform_config (key, version, value, visibility)
    SELECT p_key, coalesce(max(version),0)+1, p_val, p_vis FROM catalog.platform_config WHERE key = p_key $m$;
CREATE FUNCTION tap.promf164() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '64646464-6464-6464-6464-646464646464'::uuid $$;

-- a pending order with one item + a live hold (the shape finalize_primary_order consumes) — 155's idiom
CREATE FUNCTION tap._neworder164(p_key text, p_buyer uuid, p_session uuid, p_org uuid, p_tt uuid, p_batch uuid, p_qty int, p_unit int) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
declare v_o uuid;
begin
  insert into venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  values (p_buyer, p_session, p_org, 'pending', 'web', p_qty * p_unit, 'ck98-ord-' || p_key) returning order_id into v_o;
  insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) values (v_o, p_tt, p_qty, p_unit);
  insert into venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch, p_buyer, p_qty, 'active', now() + interval '1 hour', 'ck98-h-' || p_key);
  update venue.inventory_batch set held = held + p_qty where batch_id = p_batch;
  perform tap._store164(p_key, v_o::text);
  return v_o;
end $m$;

CREATE FUNCTION tap._newpayment164(p_buyer uuid, p_seller uuid, p_total int, p_pi text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ WITH l AS (INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                 starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
               VALUES (p_seller, 'Promo98 Night ' || gen_random_uuid()::text, 'Promo98 Hall', 'wynwood', (now()+interval '15 days')::date, '20:00', 'GA', 2,
                 'mobile_transfer', 5000, 5000, 24, now()+interval '1 day', 'covers/fixture98.jpg') RETURNING id)
    INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
    SELECT id, p_buyer, p_seller, (p_total * 9) / 10, p_total - (p_total * 9) / 10, p_total, 'succeeded', 'buy_now', p_pi FROM l RETURNING id $m$;

-- one event/session/ticket_type/batch/signing_key per label, unit price fixed at 5000 (every
-- case's order is 2 × 5000 = face 10000, so every expected number is KF §4.2 applied to one value).
CREATE FUNCTION tap._mkevent164(p_label text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
declare v_event uuid; v_session uuid; v_tt uuid; v_batch uuid;
begin
  v_event := (catalog.create_event(tap._u164('venue1'), 'Promo98 ' || p_label,
    jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 4 hours')::text), 'ck98-e' || p_label) ->> 'event_id')::uuid;
  select session_id into v_session from catalog.event_session where event_id = v_event;
  v_tt := (venue.create_ticket_type(v_event, 'admission', 'GA', 5000, 'public', 'ck98-tt' || p_label) ->> 'ticket_type_id')::uuid;
  v_batch := (venue.create_inventory_batch(v_tt, v_session, 'public_sale', 20, 0, 'ck98-b' || p_label) ->> 'batch_id')::uuid;
  perform tap._store164('event' || p_label, v_event::text);
  perform tap._store164('session' || p_label, v_session::text);
  perform tap._store164('tt' || p_label, v_tt::text);
  perform tap._store164('batch' || p_label, v_batch::text);
  insert into kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  values ('per_event', v_event, 'PUBKEY-98-' || p_label, 'kms-98-' || p_label, 'active', now());
end $m$;

-- lookups
CREATE FUNCTION tap._attr164(p_order uuid) RETURNS venue.attribution LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT a FROM venue.attribution a WHERE a.order_id = p_order $m$;
CREATE FUNCTION tap._commlines164(p_attr uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM venue.settlement_line l WHERE l.cause = 'promoter_commission' AND l.cause_ref = p_attr $m$;
CREATE FUNCTION tap._line164(p_attr uuid) RETURNS venue.settlement_line LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT l FROM venue.settlement_line l WHERE l.cause = 'promoter_commission' AND l.cause_ref = p_attr $m$;
CREATE FUNCTION tap._commpayouts164(p_attr uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.payout po WHERE po.cause = 'promoter_commission' AND po.cause_ref = p_attr $m$;
CREATE FUNCTION tap._payout164(p_attr uuid) RETURNS kernel.payout LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT po FROM kernel.payout po WHERE po.cause = 'promoter_commission' AND po.cause_ref = p_attr $m$;
CREATE FUNCTION tap._auditrows164(p_settlement uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a WHERE a.action = 'settlement.commission' AND a.subject_id = p_settlement $m$;
CREATE FUNCTION tap._heldreason164(p_settlement uuid, p_attr uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT h ->> 'reason' FROM kernel.admin_audit a, jsonb_array_elements(a.after -> 'held') h
    WHERE a.action = 'settlement.commission' AND a.subject_id = p_settlement AND (h ->> 'attribution_id')::uuid = p_attr
    ORDER BY a.created_at DESC LIMIT 1 $m$;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (tap.promf164(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'promf164@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- FIXTURE — org1 → venue1 → eight events (A, B, C, D, E, H, Disp, Flat), each
--   2 × 5000 = 10000 face. Promoter P (other_user, bps 1000, org-wide, PCODE98)
--   funds every case except Flat, which uses promoter F (promf164,
--   flat_per_ticket 300, org-wide, FCODE98). admin_user carries a MATURED
--   org_finance grant (close_settlement authority) and platform_admin
--   (refund_primary_order authority, via kernel.is_platform()).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store164('org1', (kernel.create_organization('Promo98 Co','Promo98 Co','ck98-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u164('org1');
SELECT tap.login(tap.seller());
SELECT tap._store164('venue1', (catalog.create_venue(tap._u164('org1'),'Promo98 Hall','wynwood',NULL,'ck98-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._u164('venue1'),'approved','miami_gate98','ck98-a1');
SELECT tap.logout();

INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._u164('org1'), tap.admin_user(), 'org_finance', tap.seller(), now() - interval '40 days');
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.admin_user(), 'platform_admin', tap.admin_user());
SELECT tap._cfg164('authn.money_role_maturity_hours', '24'::jsonb);
SELECT tap._cfg164('feature.native_issuance_enabled', 'true'::jsonb);

SELECT tap.login(tap.seller());
SELECT tap._mkevent164('A');
SELECT tap._mkevent164('B');
SELECT tap._mkevent164('C');
SELECT tap._mkevent164('D');
SELECT tap._mkevent164('E');
SELECT tap._mkevent164('H');
SELECT tap._mkevent164('Disp');
SELECT tap._mkevent164('Flat');
SELECT tap._store164('promP', (venue.create_promoter(tap._u164('org1'), tap.other_user()::text, '{"commission_kind":"bps","commission_bps":1000}', 'ck98-pP') ->> 'promoter_id'));
SELECT tap._store164('promF', (venue.create_promoter(tap._u164('org1'), tap.promf164()::text, '{"commission_kind":"flat_per_ticket","commission_flat_minor":300}', 'ck98-pF') ->> 'promoter_id'));
SELECT tap._store164('codeP', (venue.create_promoter_code(tap._u164('promP'), 'PCODE98', NULL, NULL, NULL, 'vanity', 'ck98-cP') ->> 'code_id'));
SELECT tap._store164('codeF', (venue.create_promoter_code(tap._u164('promF'), 'FCODE98', NULL, NULL, NULL, 'vanity', 'ck98-cF') ->> 'code_id'));
SELECT tap.logout();

-- helper macro (as SQL, not plpgsql — one order bound to PCODE98/FCODE98, finalized) — inlined per case below.

-- ============================================================================
-- CASE A — clean order, no refund. Baseline: also the fixture for the
--   re-close-noop and post-close-refund (G4) checks below.
-- ============================================================================
SELECT tap._neworder164('oA', tap.buyer(), tap._u164('sessionA'), tap._u164('org1'), tap._u164('ttA'), tap._u164('batchA'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oA'), 'PCODE98', NULL, 'ck98-b-oA'); SELECT tap.logout();
SELECT tap._store164('payA', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_A')::text);
SELECT venue.finalize_primary_order(tap._u164('oA'), tap._u164('payA'), 'ck98-f-oA', NULL);

SELECT tap.login(tap.seller());
SELECT tap._store164('sA', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventA'), '{}'::jsonb, 'ck98-sA') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sA'), 'ck98-closeA');
SELECT tap.logout();
SELECT is((tap._line164((tap._attr164(tap._u164('oA'))).id)).amount_minor, -1000, 'A: clean order, face 10000, bps 1000 -> commission line -1000 (KF case A)');
SELECT ok((SELECT po.amount_minor = 1000 AND po.hold_state = 'held' AND po.hold_reason_code = 'unfunded_settlement' FROM tap._payout164((tap._attr164(tap._u164('oA'))).id) po),
  'A: commission payout +1000, held/unfunded_settlement (A4 — no release, no advance)');

-- re-close-noop: a second event-scoped settlement on the SAME event sees nothing new for A's attribution.
SELECT tap.login(tap.seller());
SELECT tap._store164('sA2', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventA'), '{}'::jsonb, 'ck98-sA2') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sA2'), 'ck98-closeA2');
SELECT tap.logout();
SELECT is(tap._commlines164((tap._attr164(tap._u164('oA'))).id), 1, 're-close-noop: A''s attribution still carries exactly ONE commission line after a second close (NOT EXISTS + the partial unique hold)');
SELECT is(tap._commpayouts164((tap._attr164(tap._u164('oA'))).id), 1, 're-close-noop: …and exactly ONE commission payout (idempotency_key on_conflict do nothing)');

-- post-close refund NOT re-funded (G4 stays held): a refund AFTER the line exists moves nothing.
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refA', (kernel.refund_primary_order(tap._u164('oA'), 3000, 'buyer_request', 'ck98-rA') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refA')::uuid, 'submitted', 're_98_A', NULL, 'ck98-rAs');
SELECT kernel.mark_refund_state(tap._u164('refA')::uuid, 'succeeded', 're_98_A', NULL, 'ck98-rAc');
SELECT tap.login(tap.seller());
SELECT tap._store164('sA3', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventA'), '{}'::jsonb, 'ck98-sA3') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sA3'), 'ck98-closeA3');
SELECT tap.logout();
SELECT is(tap._commlines164((tap._attr164(tap._u164('oA'))).id), 1, 'G4: a refund AFTER the commission line exists lines NOTHING new (the attribution is out of the eligible set forever once lined)');
SELECT is((tap._line164((tap._attr164(tap._u164('oA'))).id)).amount_minor, -1000, 'G4: …and the ORIGINAL line is untouched — still -1000 (append-only; the post-close reversal is not re-funded, not re-priced)');
SELECT ok((SELECT po.amount_minor = 1000 AND po.hold_state = 'held' AND po.hold_reason_code = 'unfunded_settlement' FROM tap._payout164((tap._attr164(tap._u164('oA'))).id) po),
  'G4: …and the payout stays held/unfunded_settlement — no release, no reduction (PROMO §5.3: the org absorbs, the promoter''s already-funded claim is not pursued)');

-- A4 negative: even forced to 'submitted', mark_payout_transfer_state refuses cause=promoter_commission.
UPDATE kernel.payout SET status = 'submitted'
 WHERE cause = 'promoter_commission' AND cause_ref = (tap._attr164(tap._u164('oA'))).id;
SELECT throws_like(
  format($$SELECT kernel.mark_payout_transfer_state(%L, 'paid', 'tr_98_a4neg', NULL, 'ck98-a4neg')$$,
    (SELECT po.payout_id FROM kernel.payout po WHERE po.cause='promoter_commission' AND po.cause_ref = (tap._attr164(tap._u164('oA'))).id)),
  '%promoter_payout_dark%',
  'A4 negative: mark_payout_transfer_state refuses cause=promoter_commission even forced to status=submitted (KF P2-1 — the fourth lock is now a REFUSAL, not an absence)');

-- ============================================================================
-- CASE B — partial refund 4000 succeeded before close.
-- ============================================================================
SELECT tap._neworder164('oB', tap.buyer(), tap._u164('sessionB'), tap._u164('org1'), tap._u164('ttB'), tap._u164('batchB'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oB'), 'PCODE98', NULL, 'ck98-b-oB'); SELECT tap.logout();
SELECT tap._store164('payB', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_B')::text);
SELECT venue.finalize_primary_order(tap._u164('oB'), tap._u164('payB'), 'ck98-f-oB', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refB', (kernel.refund_primary_order(tap._u164('oB'), 4000, 'buyer_request', 'ck98-rB') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refB')::uuid, 'submitted', 're_98_B', NULL, 'ck98-rBs');
SELECT kernel.mark_refund_state(tap._u164('refB')::uuid, 'succeeded', 're_98_B', NULL, 'ck98-rBc');

SELECT tap.login(tap.seller());
SELECT tap._store164('sB', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventB'), '{}'::jsonb, 'ck98-sB') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sB'), 'ck98-closeB');
SELECT tap.logout();
SELECT is((tap._line164((tap._attr164(tap._u164('oB'))).id)).amount_minor, -600,
  'B: surviving = 10000 - 4000 = 6000; payable = floor(6000*1000/10000) = 600 -> commission line -600 (KF case B)');
SELECT ok((SELECT po.amount_minor = 600 AND po.hold_state = 'held' FROM tap._payout164((tap._attr164(tap._u164('oB'))).id) po), 'B: commission payout +600, held (not the pre-098 total forfeiture)');

-- ============================================================================
-- CASE C — full refund 10000 succeeded before close: surviving = 0.
-- ============================================================================
SELECT tap._neworder164('oC', tap.buyer(), tap._u164('sessionC'), tap._u164('org1'), tap._u164('ttC'), tap._u164('batchC'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oC'), 'PCODE98', NULL, 'ck98-b-oC'); SELECT tap.logout();
SELECT tap._store164('payC', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_C')::text);
SELECT venue.finalize_primary_order(tap._u164('oC'), tap._u164('payC'), 'ck98-f-oC', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refC', (kernel.refund_primary_order(tap._u164('oC'), 10000, 'buyer_request', 'ck98-rC') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refC')::uuid, 'submitted', 're_98_C', NULL, 'ck98-rCs');
SELECT kernel.mark_refund_state(tap._u164('refC')::uuid, 'succeeded', 're_98_C', NULL, 'ck98-rCc');

SELECT tap.login(tap.seller());
SELECT tap._store164('sC', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventC'), '{}'::jsonb, 'ck98-sC') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sC'), 'ck98-closeC');
SELECT tap.logout();
SELECT is(tap._commlines164((tap._attr164(tap._u164('oC'))).id), 0, 'C: surviving = 10000 - 10000 = 0 -> NO commission line (basis_zero, still held not forfeited-silently)');
SELECT is(tap._commpayouts164((tap._attr164(tap._u164('oC'))).id), 0, 'C: …and NO commission payout is minted');
SELECT is(tap._heldreason164(tap._u164('sC'), (tap._attr164(tap._u164('oC'))).id), 'basis_zero',
  'C: the settlement.commission audit row NAMES the reason (basis_zero) — KF P1-1: because the attribution now REACHES pay_promoter_commission (it is no longer excluded a seam up), the hold is auditable, not silent');

-- ============================================================================
-- CASE D1/D2 — a refund PENDING at close defers the whole attribution; the
--   SAME refund later FAILED restores the full face (the buyer got nothing).
-- ============================================================================
SELECT tap._neworder164('oD', tap.buyer(), tap._u164('sessionD'), tap._u164('org1'), tap._u164('ttD'), tap._u164('batchD'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oD'), 'PCODE98', NULL, 'ck98-b-oD'); SELECT tap.logout();
SELECT tap._store164('payD', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_D')::text);
SELECT venue.finalize_primary_order(tap._u164('oD'), tap._u164('payD'), 'ck98-f-oD', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refD', (kernel.refund_primary_order(tap._u164('oD'), 4000, 'buyer_request', 'ck98-rD') ->> 'refund_id'));
SELECT tap.logout();
-- refD stays 'pending' — no mark_refund_state call yet.

SELECT tap.login(tap.seller());
SELECT tap._store164('sD1', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventD'), '{}'::jsonb, 'ck98-sD1') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sD1'), 'ck98-closeD1');
SELECT tap.logout();
SELECT is(tap._commlines164((tap._attr164(tap._u164('oD'))).id), 0, 'D1: a PENDING refund that could still succeed DEFERS the attribution whole -> 0 lines');
SELECT is(tap._auditrows164(tap._u164('sD1')), 0, 'D1: …the deferral happens in the eligible-set predicate, BEFORE pay_promoter_commission runs — no settlement.commission audit row at all (nothing was evaluated, not silently forfeited)');

SELECT kernel.mark_refund_state(tap._u164('refD')::uuid, 'submitted', 're_98_D', NULL, 'ck98-rDs');
SELECT kernel.mark_refund_state(tap._u164('refD')::uuid, 'failed', 're_98_D', 'card_declined', 'ck98-rDf');
SELECT tap.login(tap.seller());
SELECT tap._store164('sD2', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventD'), '{}'::jsonb, 'ck98-sD2') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sD2'), 'ck98-closeD2');
SELECT tap.logout();
SELECT is((tap._line164((tap._attr164(tap._u164('oD'))).id)).amount_minor, -1000,
  'D2: the refund FAILED (buyer got nothing back) — Σ succeeded refunds = 0, surviving = face 10000 -> FULL commission -1000 (KF case D2, not the pre-098 permanent forfeiture)');

-- ============================================================================
-- CASE E — two attributions in ONE close: E1 clean, E2 partially refunded.
-- ============================================================================
SELECT tap._neworder164('oE1', tap.buyer(), tap._u164('sessionE'), tap._u164('org1'), tap._u164('ttE'), tap._u164('batchE'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oE1'), 'PCODE98', NULL, 'ck98-b-oE1'); SELECT tap.logout();
SELECT tap._store164('payE1', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_E1')::text);
SELECT venue.finalize_primary_order(tap._u164('oE1'), tap._u164('payE1'), 'ck98-f-oE1', NULL);

SELECT tap._neworder164('oE2', tap.buyer(), tap._u164('sessionE'), tap._u164('org1'), tap._u164('ttE'), tap._u164('batchE'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oE2'), 'PCODE98', NULL, 'ck98-b-oE2'); SELECT tap.logout();
SELECT tap._store164('payE2', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_E2')::text);
SELECT venue.finalize_primary_order(tap._u164('oE2'), tap._u164('payE2'), 'ck98-f-oE2', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refE2', (kernel.refund_primary_order(tap._u164('oE2'), 4000, 'buyer_request', 'ck98-rE2') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refE2')::uuid, 'submitted', 're_98_E2', NULL, 'ck98-rE2s');
SELECT kernel.mark_refund_state(tap._u164('refE2')::uuid, 'succeeded', 're_98_E2', NULL, 'ck98-rE2c');

SELECT tap.login(tap.seller());
SELECT tap._store164('sE', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventE'), '{}'::jsonb, 'ck98-sE') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sE'), 'ck98-closeE');
SELECT tap.logout();
SELECT is((tap._line164((tap._attr164(tap._u164('oE1'))).id)).amount_minor, -1000, 'E: E1 (clean) -> -1000 in the SAME close as E2');
SELECT is((tap._line164((tap._attr164(tap._u164('oE2'))).id)).amount_minor, -600, 'E: E2 (4000 refunded) -> -600 — one seam evaluation prices two attributions independently and correctly (1000 + 600)');

-- ============================================================================
-- CASE H — 2 tickets, ONE direct partial refund of 5000 (a whole ticket's
--   worth of money; 085:563-568 voids NO atom for a direct partial refund).
-- ============================================================================
SELECT tap._neworder164('oH', tap.buyer(), tap._u164('sessionH'), tap._u164('org1'), tap._u164('ttH'), tap._u164('batchH'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oH'), 'PCODE98', NULL, 'ck98-b-oH'); SELECT tap.logout();
SELECT tap._store164('payH', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_H')::text);
SELECT venue.finalize_primary_order(tap._u164('oH'), tap._u164('payH'), 'ck98-f-oH', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refH', (kernel.refund_primary_order(tap._u164('oH'), 5000, 'buyer_request', 'ck98-rH') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refH')::uuid, 'submitted', 're_98_H', NULL, 'ck98-rHs');
SELECT kernel.mark_refund_state(tap._u164('refH')::uuid, 'succeeded', 're_98_H', NULL, 'ck98-rHc');

SELECT tap.login(tap.seller());
SELECT tap._store164('sH', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventH'), '{}'::jsonb, 'ck98-sH') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sH'), 'ck98-closeH');
SELECT tap.logout();
SELECT ok((SELECT bool_and(t.state <> 'voided') FROM kernel.tickets t JOIN kernel.ticket_ownership_log l ON l.ticket_atom_id = t.ticket_atom_id
             AND l.sequence = 1 AND l.cause = 'issue' JOIN venue.order_item oi ON oi.id = l.cause_ref WHERE oi.order_id = tap._u164('oH')),
  'H: the direct partial refund voided NO atom — BOTH tickets stay non-voided (085:563-568)');
SELECT is((tap._line164((tap._attr164(tap._u164('oH'))).id)).amount_minor, -500,
  'H: surviving = 10000 - 5000 = 5000; payable = floor(5000*1000/10000) = 500 (KF case H)');

-- ============================================================================
-- CASE Disp — a lost dispute counts as reversed at the funding close (KF
--   §4.4 default), capped so the combined refund+dispute reversal never
--   drives surviving below zero.
-- ============================================================================
SELECT tap._neworder164('oDisp1', tap.buyer(), tap._u164('sessionDisp'), tap._u164('org1'), tap._u164('ttDisp'), tap._u164('batchDisp'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oDisp1'), 'PCODE98', NULL, 'ck98-b-oDisp1'); SELECT tap.logout();
SELECT tap._store164('payDisp1', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_Disp1')::text);
SELECT venue.finalize_primary_order(tap._u164('oDisp1'), tap._u164('payDisp1'), 'ck98-f-oDisp1', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refDisp1', (kernel.refund_primary_order(tap._u164('oDisp1'), 3000, 'buyer_request', 'ck98-rDisp1') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refDisp1')::uuid, 'submitted', 're_98_Disp1', NULL, 'ck98-rDisp1s');
SELECT kernel.mark_refund_state(tap._u164('refDisp1')::uuid, 'succeeded', 're_98_Disp1', NULL, 'ck98-rDisp1c');
SELECT kernel.record_dispute_native('dp_98_1', 'ch_98_1', 'pi_98_Disp1', 4000, 'USD', 'fraudulent', 'needs_response', NULL, 'ck98-d1');
SELECT kernel.mark_dispute_state('dp_98_1', 'lost', 'ck98-d1lost');

SELECT tap._neworder164('oDisp2', tap.buyer(), tap._u164('sessionDisp'), tap._u164('org1'), tap._u164('ttDisp'), tap._u164('batchDisp'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oDisp2'), 'PCODE98', NULL, 'ck98-b-oDisp2'); SELECT tap.logout();
SELECT tap._store164('payDisp2', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_Disp2')::text);
SELECT venue.finalize_primary_order(tap._u164('oDisp2'), tap._u164('payDisp2'), 'ck98-f-oDisp2', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refDisp2', (kernel.refund_primary_order(tap._u164('oDisp2'), 9000, 'buyer_request', 'ck98-rDisp2') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refDisp2')::uuid, 'submitted', 're_98_Disp2', NULL, 'ck98-rDisp2s');
SELECT kernel.mark_refund_state(tap._u164('refDisp2')::uuid, 'succeeded', 're_98_Disp2', NULL, 'ck98-rDisp2c');
SELECT kernel.record_dispute_native('dp_98_2', 'ch_98_2', 'pi_98_Disp2', 5000, 'USD', 'fraudulent', 'needs_response', NULL, 'ck98-d2');
SELECT kernel.mark_dispute_state('dp_98_2', 'lost', 'ck98-d2lost');

SELECT tap.login(tap.seller());
SELECT tap._store164('sDisp', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventDisp'), '{}'::jsonb, 'ck98-sDisp') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sDisp'), 'ck98-closeDisp');
SELECT tap.logout();
SELECT is((tap._line164((tap._attr164(tap._u164('oDisp1'))).id)).amount_minor, -300,
  'Disp1: surviving = 10000 - 3000(refund) - 4000(lost dispute) = 3000; payable = floor(3000*1000/10000) = 300 — disputes count as reversed (KF §4.4 default)');
SELECT is(tap._commlines164((tap._attr164(tap._u164('oDisp2'))).id), 0,
  'Disp2: refund 9000 leaves headroom 1000; the 5000 dispute is CAPPED at that headroom (10h''s cap) so surviving floors at exactly 0 — no negative, no error, no line');
SELECT is(tap._heldreason164(tap._u164('sDisp'), (tap._attr164(tap._u164('oDisp2'))).id), 'basis_zero', 'Disp2: …held basis_zero, audited (not silently dropped)');

-- ============================================================================
-- CASE Flat — flat_per_ticket promoter F: surviving quantity is DERIVED from
--   surviving face (KF §4.5 option (a) — no atom is voided by a direct
--   partial refund, so there is no atom count to read).
-- ============================================================================
SELECT tap._neworder164('oFlat', tap.buyer(), tap._u164('sessionFlat'), tap._u164('org1'), tap._u164('ttFlat'), tap._u164('batchFlat'), 2, 5000);
SELECT tap.login(tap.buyer()); SELECT venue.bind_order_attribution(tap._u164('oFlat'), 'FCODE98', NULL, 'ck98-b-oFlat'); SELECT tap.logout();
SELECT tap._store164('payFlat', tap._newpayment164(tap.buyer(), tap.seller(), 10000, 'pi_98_Flat')::text);
SELECT venue.finalize_primary_order(tap._u164('oFlat'), tap._u164('payFlat'), 'ck98-f-oFlat', NULL);
SELECT tap.set_claims(tap.admin_user());
SELECT tap._store164('refFlat', (kernel.refund_primary_order(tap._u164('oFlat'), 5000, 'buyer_request', 'ck98-rFlat') ->> 'refund_id'));
SELECT tap.logout();
SELECT kernel.mark_refund_state(tap._u164('refFlat')::uuid, 'submitted', 're_98_Flat', NULL, 'ck98-rFlats');
SELECT kernel.mark_refund_state(tap._u164('refFlat')::uuid, 'succeeded', 're_98_Flat', NULL, 'ck98-rFlatc');

SELECT ok((SELECT a.commission_kind = 'flat_per_ticket' AND a.commission_flat_minor_applied = 300 FROM tap._attr164(tap._u164('oFlat')) a),
  'Flat: the attribution snapshot is flat_per_ticket, flat 300 (promoter F terms)');
SELECT tap.login(tap.seller());
SELECT tap._store164('sFlat', (venue.open_settlement(tap._u164('org1'), tap._u164('venue1'), tap._u164('eventFlat'), '{}'::jsonb, 'ck98-sFlat') ->> 'settlement_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT kernel.close_settlement(tap._u164('sFlat'), 'ck98-closeFlat');
SELECT tap.logout();
SELECT is((tap._line164((tap._attr164(tap._u164('oFlat'))).id)).amount_minor, -300,
  'Flat: surviving face 5000 on a 2x5000 order -> floor(5000/5000)=1 surviving ticket, capped at qty 2, x flat 300 = -300 (KF §4.5(a))');
SELECT ok((SELECT po.amount_minor = 300 AND po.hold_state = 'held' FROM tap._payout164((tap._attr164(tap._u164('oFlat'))).id) po), 'Flat: commission payout +300, held');

-- ============================================================================
-- CONSERVATION — case B's settlement: gross(10000) - refund(4000) =
--   distributable(5400) + commission funded(600). Both the line sum and the
--   header net_minor agree (KC's identity, applied to what 098 touches).
-- ============================================================================
SELECT is((SELECT sum(l.amount_minor)::bigint FROM venue.settlement_line l WHERE l.settlement_id = tap._u164('sB')), 5400::bigint,
  'conservation: sB''s lines (primary_sale +10000, refund_void -4000, promoter_commission -600) sum to 5400');
-- 2026-09-03 (this reconciliation): dropped the ::bigint literal cast — venue.settlement.net_minor
-- is integer, and pgTAP's is() couldn't resolve an is(integer, bigint, unknown) overload. A
-- pre-existing type-mismatch bug (never actually run before this reconciliation); the value
-- asserted is unchanged.
SELECT is((SELECT net_minor FROM venue.settlement WHERE settlement_id = tap._u164('sB')), 5400, 'conservation: …and the header net_minor reads back the same 5400 (10.2 R1-2)');
SELECT ok((10000 - 4000) = (600 + 5400), 'conservation: gross(10000) - refund(4000) = commission funded(600) + venue distributable(5400) — no money created, none destroyed');

SELECT * FROM finish();
ROLLBACK;
