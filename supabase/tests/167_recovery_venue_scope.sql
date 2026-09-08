-- ============================================================================
-- 167_recovery_venue_scope.sql — package 101, verifier T2.
--
-- SUBJECT: proves migration 101's fix for ADV P0-1 (docs/phase2/_impl/
--   KADV_adversarial_reproof.md): kernel.organization_obligation_recovery_guard()
--   (096:518-582, body-only re-created by 101) now refuses a `transfer_reversal`
--   recovery whose reversed payout's ORIGINATING VENUE differs from the
--   obligation's own venue_id — closing the hole where Venue B's payout
--   reversal could recover Venue A's debt inside the same organization (the
--   default cross-venue netting ruling G5 forbids).
--
-- FIXTURE SHAPE: org1 (seller-owned) with TWO venues, A and B, each with its
--   own event/session/order — the 163 two-venue-one-org pattern. Venue A's
--   settlement is paid, then a lost dispute on that same order forces a LATER,
--   period-scoped close on venue A to net negative — 097's automatic
--   `settlement_shortfall` booking on kernel.close_settlement (097:891-893)
--   stamps venue_id := the closing settlement's own venue (097 §3, KD P1-5),
--   exactly as proved by 163's SA1/dA1/SA2 triple (venue A) — reused here.
--   Venue B's own settlement is paid then fully reversed via
--   kernel.record_payout_reversal (096), producing a `trr_B…` fact bound (via
--   payout → settlement → venue_id) to venue B. Venue A's OWN paid settlement
--   is also reversed, producing a `trr_A…` fact bound to venue A, so the SAME
--   obligation can be shown recovered by the matching venue's reversal after
--   the mismatched one is refused. A second organization (org2, one venue X)
--   supplies its own independent settlement_shortfall obligation to re-prove
--   the ORG-level guard (096's original check, undisturbed by 101) still
--   fires first, ahead of the new venue check, exactly as 101's guard body
--   orders its predicates (organization_obligation_recovery_guard():
--   reversal_org_mismatch at 101:96-99, THEN reversal_venue_mismatch at
--   101:105-113).
--
-- Sources read: supabase/migrations/101_recovery_venue_scope.sql (in full);
--   supabase/migrations/097_settlement_scope_and_shortfall.sql:220-431,760-936
--   (record_organization_obligation venue_id derivation, close_settlement's
--   automatic settlement_shortfall booking); supabase/migrations/096_payout_
--   reversal_and_obligation_recovery.sql (record_payout_reversal, record_
--   obligation_recovery); supabase/tests/162_payout_reversal_and_obligation_
--   recovery.sql (fixture idiom: _cov/_settle/_request/_po/_ob helpers, the
--   K/L section's manual+transfer_reversal receipt shape, the M-section
--   auth wrapper); supabase/tests/163_settlement_scope_and_shortfall.sql
--   (the two-venue-one-org SA1/dA1/SA2 shortfall shape, A8-A13; the _ord163/
--   _disp163/_settle163/_pay163 fixture idiom, reused verbatim under a 167
--   suffix); docs/phase2/_impl/KADV_adversarial_reproof.md (ADV P0-1).
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK, the 162/163 idiom.
-- ============================================================================
BEGIN;
SELECT plan(24);

SELECT tap.seed_core();

CREATE TABLE tap.memo_167 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st167(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_167 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._g167(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_167 WHERE k = $1 $m$;

CREATE FUNCTION tap._aal2_167() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- 163's tap._ord163 body, verbatim (the venue.finalize_primary_order triple).
CREATE FUNCTION tap._ord167(p_session uuid, p_org uuid, p_face int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_ord uuid := gen_random_uuid(); v_pay uuid := gen_random_uuid();
begin
  insert into venue."order" (order_id, buyer_id, event_session_id, org_id, status, source,
                             total_minor, currency, command_idempotency_key)
  values (v_ord, tap.buyer(), p_session, p_org, 'paid', 'app', p_face, 'USD', 'ck167-' || p_tag);
  insert into public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total,
                               stripe_payment_intent_id, status, mode, paid_at)
  values (v_pay, tap.buyer(), p_face, 0, 0, p_face, 'pi_167_' || p_tag, 'succeeded', 'native_primary', now());
  insert into kernel.payment_native (payment_id, order_id, amount_minor, currency)
  values (v_pay, v_ord, p_face, 'USD');
  return v_ord;
end $f$;

-- 163's tap._disp163 body, verbatim.
CREATE FUNCTION tap._disp167(p_order uuid, p_amt int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.dispute_native (dispute_id, stripe_dispute_ref, stripe_charge_ref,
                                     payment_id, amount_minor, currency, reason, status)
  select v_id, 'dp_167_' || p_tag, 'ch_167_' || p_tag, pn.payment_id, p_amt, 'USD',
         'fraudulent', 'lost'
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

-- 163's tap._settle163 body, verbatim (open as owner, close as admin).
CREATE FUNCTION tap._settle167(p_org uuid, p_venue uuid, p_key text) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_s uuid;
begin
  perform tap.login(tap.seller());
  v_s := (venue.open_settlement(p_org, p_venue, NULL, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid;
  perform tap.logout();
  perform tap.login(tap.admin_user());
  perform kernel.close_settlement(v_s, p_key || '-c');
  perform tap.logout();
  return v_s;
end $f$;

CREATE FUNCTION tap._payoutid167(p_settlement uuid) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT payout_id FROM kernel.payout WHERE cause='settlement' AND cause_ref=p_settlement ORDER BY created_at LIMIT 1 $f$;

-- 163's tap._pay163 body (request as owner, then mark paid), verbatim.
CREATE FUNCTION tap._pay167(p_payout uuid, p_tr text, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_settlement uuid; v_org uuid; v_status text; v jsonb;
begin
  select cause_ref, payee_org_id, status into v_settlement, v_org, v_status from kernel.payout where payout_id = p_payout;
  if v_status = 'pending' then
    perform tap.login(tap.seller());
    perform tap._aal2_167();
    perform kernel.request_org_payout(v_org, v_settlement, p_key || '-req');
    perform tap.logout();
  end if;
  v := kernel.mark_payout_transfer_state(p_payout, 'paid', p_tr, null, p_key);
  return v;
end $f$;

CREATE FUNCTION tap._oblrow167(p_ref uuid) RETURNS kernel.organization_obligation
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT o FROM kernel.organization_obligation o WHERE origin_ref = p_ref ORDER BY created_at DESC LIMIT 1 $m$;

-- record_obligation_recovery requires authenticated + platform role + aal2
-- (096 A7/M1-M4); wrap every call the way 162's K/L/M sections do.
CREATE FUNCTION tap._recover167(p_obligation uuid, p_amt int, p_kind text, p_ref text, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v jsonb;
begin
  perform tap.login(tap.admin_user());
  perform tap._aal2_167();
  v := kernel.record_obligation_recovery(p_obligation, p_amt, p_kind, p_ref, 'K T2 167', p_key);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._recover_throws167(p_obligation uuid, p_amt int, p_kind text, p_ref text, p_key text) RETURNS text
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_msg text;
begin
  perform tap.login(tap.admin_user());
  perform tap._aal2_167();
  begin
    perform kernel.record_obligation_recovery(p_obligation, p_amt, p_kind, p_ref, 'K T2 167 (expected refusal)', p_key);
    v_msg := 'NO_EXCEPTION_RAISED';
  exception when others then
    v_msg := sqlerrm;
  end;
  perform tap.logout();
  return v_msg;
end $f$;

-- ============================================================================
-- BASELINE FIXTURE — org1 (seller) → venue A, venue B. org2 (seller, a SECOND
-- organization) → venue X. Every session sits well in the past; maturity
-- config mirrors 163's (0h settlement maturity, 24h role maturity).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st167('org1', (kernel.create_organization('167 Co','167 Co','ck167-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g167('org1');
SELECT tap.login(tap.seller());
SELECT tap._st167('venueA', (catalog.create_venue(tap._g167('org1'),'167 Hall A','wynwood',NULL,'ck167-va') ->> 'venue_id'));
SELECT tap._st167('venueB', (catalog.create_venue(tap._g167('org1'),'167 Hall B','brickell',NULL,'ck167-vb') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g167('venueA'),'approved','miami_gate','ck167-aa');
SELECT catalog.approve_venue(tap._g167('venueB'),'approved','miami_gate','ck167-ab');
SELECT tap.logout();

SELECT tap.login(tap.seller());
SELECT tap._st167('org2', (kernel.create_organization('167 Co2','167 Co2','ck167-o2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g167('org2');
SELECT tap.login(tap.seller());
SELECT tap._st167('venueX', (catalog.create_venue(tap._g167('org2'),'167 Hall X','downtown miami',NULL,'ck167-vx') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g167('venueX'),'approved','miami_gate','ck167-ax');
SELECT tap.logout();

SELECT tap.login(tap.seller());
SELECT tap._st167('evA', (catalog.create_event(tap._g167('venueA'),'167 A',
  jsonb_build_object('starts_at',(now()-interval '50 days')::text,'ends_at',(now()-interval '50 days'+interval '4 hours')::text),'ck167-ea') ->> 'event_id'));
SELECT tap._st167('evB', (catalog.create_event(tap._g167('venueB'),'167 B',
  jsonb_build_object('starts_at',(now()-interval '49 days')::text,'ends_at',(now()-interval '49 days'+interval '4 hours')::text),'ck167-eb') ->> 'event_id'));
SELECT tap._st167('evX', (catalog.create_event(tap._g167('venueX'),'167 X',
  jsonb_build_object('starts_at',(now()-interval '48 days')::text,'ends_at',(now()-interval '48 days'+interval '4 hours')::text),'ck167-ex') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st167('sessA', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g167('evA')));
SELECT tap._st167('sessB', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g167('evB')));
SELECT tap._st167('sessX', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g167('evX')));

INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.settlement_maturity_interval', coalesce(max(version),0)+1, '"0 hours"'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.settlement_maturity_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '100000000'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';

UPDATE kernel.organization SET stripe_connect_account_ref='acct_167O1', connect_transfers_active=true
 WHERE org_id = tap._g167('org1');
UPDATE kernel.organization SET stripe_connect_account_ref='acct_167O2', connect_transfers_active=true
 WHERE org_id = tap._g167('org2');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days'
 WHERE org_id IN (tap._g167('org1'), tap._g167('org2')) AND identity_id = tap.seller();

-- ============================================================================
-- SECTION A — VENUE A: paid settlement, then a post-payout lost dispute forces
-- a later negative-net close — the settlement_shortfall obligation obA, venue_
-- id = venue A (097's automatic booking, the 163 A8-A13 shape).
-- ============================================================================
SELECT tap._st167('oA1', tap._ord167(tap._g167('sessA'), tap._g167('org1'), 50000, 'oA1')::text);
SELECT tap._st167('SA1', tap._settle167(tap._g167('org1'), tap._g167('venueA'), 'sa1')::text);
SELECT is((SELECT net_minor FROM venue.settlement WHERE settlement_id = tap._g167('SA1')), 50000,
  '01: fixture control — SA1 (venue A) nets 50000 on oA1 alone');
SELECT tap._st167('pA', tap._payoutid167(tap._g167('SA1'))::text);
SELECT tap._pay167(tap._g167('pA'), 'tr_167a', 'ck167-pay-a');
SELECT is((SELECT status FROM kernel.payout WHERE payout_id = tap._g167('pA')), 'paid', '02: … venue A''s payout is paid');

SELECT tap._st167('dA1', tap._disp167(tap._g167('oA1'), 50000, 'dA1')::text);
SELECT tap._st167('SA2', tap._settle167(tap._g167('org1'), tap._g167('venueA'), 'sa2')::text);
SELECT is((SELECT net_minor FROM venue.settlement WHERE settlement_id = tap._g167('SA2')), -50000,
  '03: SA2 (venue A, period-scoped, no new orders) nets -50000 on dA1 alone');
SELECT is((tap._oblrow167(tap._g167('SA2'))).origin_kind, 'settlement_shortfall', '04: … booked as settlement_shortfall');
SELECT is((tap._oblrow167(tap._g167('SA2'))).amount_minor, 50000, '05: … amount 50000');
SELECT is((tap._oblrow167(tap._g167('SA2'))).venue_id, tap._g167('venueA'), '06: … venue_id = venue A (097 KD P1-5)');
SELECT is((tap._oblrow167(tap._g167('SA2'))).status, 'outstanding', '07: … status outstanding');
SELECT tap._st167('obA', (tap._oblrow167(tap._g167('SA2'))).obligation_id::text);

-- venue A's OWN paid settlement is fully reversed — trr_A167, bound (via
-- payout -> SA1 -> venue_id) to venue A.
SELECT is((kernel.record_payout_reversal(tap._g167('pA'), 'tr_167a', 'trr_167a', 50000, '{}'::jsonb, 'ck167-rva') ->> 'status'), 'ok',
  '08: record_payout_reversal on venue A''s own paid payout returns ok — trr_167a now exists, bound to venue A');

-- ============================================================================
-- SECTION B — VENUE B (SAME org1): a clean paid settlement, fully reversed —
-- trr_167b, bound to venue B. Nothing here ever touches venue A's debt.
-- ============================================================================
SELECT tap._st167('oB1', tap._ord167(tap._g167('sessB'), tap._g167('org1'), 30000, 'oB1')::text);
SELECT tap._st167('SB1', tap._settle167(tap._g167('org1'), tap._g167('venueB'), 'sb1')::text);
SELECT is((SELECT net_minor FROM venue.settlement WHERE settlement_id = tap._g167('SB1')), 30000,
  '09: fixture control — SB1 (venue B) nets 30000 on oB1 alone');
SELECT tap._st167('pB', tap._payoutid167(tap._g167('SB1'))::text);
SELECT tap._pay167(tap._g167('pB'), 'tr_167b', 'ck167-pay-b');
SELECT is((kernel.record_payout_reversal(tap._g167('pB'), 'tr_167b', 'trr_167b', 30000, '{}'::jsonb, 'ck167-rvb') ->> 'status'), 'ok',
  '10: record_payout_reversal on venue B''s own paid payout returns ok — trr_167b now exists, bound to venue B');

-- ============================================================================
-- SECTION C — THE PROOF (ADV P0-1 / 101). obA (venue A, 50000 outstanding).
-- ============================================================================
-- (a) MISMATCH REFUSED — trr_167b reversed venue B's payout; obA originates at
-- venue A. 096's guard alone (pre-101) checked only the ORG (org1 == org1,
-- would have passed); 101 adds the venue predicate that now refuses this.
SELECT is(tap._recover_throws167(tap._g167('obA'), 20000, 'transfer_reversal', 'trr_167b', 'ck167-rec-mismatch'),
  'precondition_failed: reversal_venue_mismatch — trr_167b reversed a payout of venue ' || tap._g167('venueB')::text
    || ', the obligation originates at venue ' || tap._g167('venueA')::text || ' (no cross-venue netting, ruling G5)',
  '11: (a) THE P0 IS CLOSED — Venue B''s trr_167b cannot recover Venue A''s obligation: reversal_venue_mismatch');
SELECT is((tap._oblrow167(tap._g167('SA2'))).status, 'outstanding', '12: … obA is untouched by the refused attempt, still outstanding');
SELECT is(kernel.obligation_outstanding_minor(tap._g167('obA')), 50000::bigint, '13: … outstanding still reads the full 50000');

-- (c) MANUAL RECEIPT — org-level, untouched by the venue scope (source_kind <>
-- 'transfer_reversal' never reaches the venue predicate at all).
SELECT is((tap._recover167(tap._g167('obA'), 20000, 'manual', 'receipt-167-1', 'ck167-rec-manual') ->> 'status'), 'ok',
  '14: (c) MANUAL RECOVERY STILL ALLOWED — an off-platform receipt against obA is unaffected by 101''s venue predicate');
SELECT is(kernel.obligation_outstanding_minor(tap._g167('obA')), 30000::bigint, '15: … 20000 of 50000 recovered, 30000 outstanding');
SELECT is((tap._oblrow167(tap._g167('SA2'))).status, 'outstanding', '16: … obA still outstanding (Σ < amount)');

-- (b) MATCHING VENUE ALLOWED — the SAME obligation, completed by trr_167a
-- (venue A's own reversal), Σ now = 50000 = amount.
SELECT is((tap._recover167(tap._g167('obA'), 30000, 'transfer_reversal', 'trr_167a', 'ck167-rec-match') ->> 'obligation_status'), 'recovered',
  '17: (b) MATCHING-VENUE RECOVERY ALLOWED — the SAME obligation, completed by venue A''s own trr_167a, flips to recovered');
SELECT is((tap._oblrow167(tap._g167('SA2'))).resolution_reason_code, 'recovered:transfer_reversal',
  '18: … the reason code names the completing source_kind');
SELECT is(kernel.obligation_outstanding_minor(tap._g167('obA')), 0::bigint, '19: … outstanding reads 0');

-- ============================================================================
-- SECTION D — CROSS-ORG (096's original guard, undisturbed by 101; the
-- reversal_org_mismatch check runs BEFORE the new venue check — 101:96-113).
-- org2/venue X gets its own independent settlement_shortfall obligation.
-- ============================================================================
SELECT tap._st167('oX1', tap._ord167(tap._g167('sessX'), tap._g167('org2'), 20000, 'oX1')::text);
SELECT tap._st167('SX1', tap._settle167(tap._g167('org2'), tap._g167('venueX'), 'sx1')::text);
SELECT tap._st167('pX', tap._payoutid167(tap._g167('SX1'))::text);
SELECT tap._pay167(tap._g167('pX'), 'tr_167x', 'ck167-pay-x');
SELECT tap._st167('dX1', tap._disp167(tap._g167('oX1'), 20000, 'dX1')::text);
SELECT tap._st167('SX2', tap._settle167(tap._g167('org2'), tap._g167('venueX'), 'sx2')::text);
SELECT is((SELECT net_minor FROM venue.settlement WHERE settlement_id = tap._g167('SX2')), -20000,
  '20: fixture control — SX2 (venue X, org2) nets -20000 on dX1 alone');
SELECT is((tap._oblrow167(tap._g167('SX2'))).venue_id, tap._g167('venueX'), '21: … booked venue_id = venue X, org2');
SELECT tap._st167('obX', (tap._oblrow167(tap._g167('SX2'))).obligation_id::text);

-- (d) org2's obligation cannot be recovered by org1's trr_167b — unclaimed
-- (the (a) attempt above THREW before any insert, so trr_167b was never
-- actually linked to an obligation; trr_167a is unusable here instead, since
-- (b) already consumed it against obA — kernel.record_obligation_recovery's
-- own source_ref uniqueness (096:755, recovery_source_already_linked) would
-- refuse it for that unrelated reason before the org check is even reached).
-- The org check (096, untouched by 101) refuses trr_167b before the venue
-- predicate is ever reached.
SELECT is(tap._recover_throws167(tap._g167('obX'), 5000, 'transfer_reversal', 'trr_167b', 'ck167-rec-orgmismatch'),
  'precondition_failed: reversal_org_mismatch — trr_167b reversed a payout of organization ' || tap._g167('org1')::text
    || ', the obligation belongs to ' || tap._g167('org2')::text,
  '22: (d) CROSS-ORG STILL REFUSED — org1''s trr_167b cannot recover org2''s obligation: reversal_org_mismatch (096, unmodified by 101)');
SELECT is((tap._oblrow167(tap._g167('SX2'))).status, 'outstanding', '23: … obX is untouched, still outstanding');
SELECT is(kernel.obligation_outstanding_minor(tap._g167('obX')), 20000::bigint, '24: … outstanding still reads the full 20000');

SELECT * FROM finish();
ROLLBACK;
