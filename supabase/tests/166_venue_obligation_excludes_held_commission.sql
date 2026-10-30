-- ============================================================================
-- 166_venue_obligation_excludes_held_commission.sql — package 100 (the G4
--   economic-consistency fix), SEAMS-ONLY.
--
-- SUBJECT: kernel.settlement_royalty_lines' chargeback-arm held-commission
--   reduction and kernel.settlement_primary_lines' symmetric refund_void
--   reduction. Migration 100 does NOT re-create close_settlement and does NOT
--   add a converge_held_commission verb — the held-commission PAYOUT is never
--   touched by 100 (funded, unconverged, held forever; convergence is
--   specified/deferred to the future promoter-payout ruling, PFA-PT-5).
--
-- Frozen sources: docs/phase2/G4_PROMOTER_REVERSAL_RULING.md, docs/phase2/
--   _impl/KF_promoter_prorata.md (098's basis formula), KC_chargeback_
--   accounting.md §2.i, supabase/migrations/100_venue_obligation_excludes_
--   held_commission.sql's own header (read in full before writing this file).
--
-- FIXTURE SHAPE: one org O (seller), one venue A, ONE order + ONE bps-1000
--   (10%) promoter attribution per section — deliberately isolated (own
--   event, own order, own attribution) so no section's fixtures leak into
--   another's held-commission reads. Every session sits well in the past and
--   payout.settlement_maturity_interval is '0 hours' (163's own recipe), so a
--   positive-net payout mints UNHELD unless a scenario deliberately puts an
--   operand in its way.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixture helpers reuse
--   163's tap._ord163/_disp163/_rf163/_settle163 SHAPE (renamed to the 166
--   suffix) and 151's tap._pinattr151 shape for a direct attribution insert
--   (bound to a caller-chosen face/bps rather than the hardcoded 10000/1000
--   151 pins).
-- ============================================================================
BEGIN;
SELECT plan(39);

SELECT tap.seed_core();

CREATE TABLE tap.memo_166 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st166(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_166 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._g166(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_166 WHERE k = $1 $m$;

-- the exact triple venue.finalize_primary_order leaves behind (163's _ord163).
CREATE FUNCTION tap._ord166(p_session uuid, p_org uuid, p_face int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_ord uuid := gen_random_uuid(); v_pay uuid := gen_random_uuid();
begin
  insert into venue."order" (order_id, buyer_id, event_session_id, org_id, status, source,
                             total_minor, currency, command_idempotency_key)
  values (v_ord, tap.buyer(), p_session, p_org, 'paid', 'app', p_face, 'USD', 'ck166-' || p_tag);
  insert into public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total,
                               stripe_payment_intent_id, status, mode, paid_at)
  values (v_pay, tap.buyer(), p_face, 0, 0, p_face, 'pi_166_' || p_tag, 'succeeded', 'native_primary', now());
  insert into kernel.payment_native (payment_id, order_id, amount_minor, currency)
  values (v_pay, v_ord, p_face, 'USD');
  return v_ord;
end $f$;

CREATE FUNCTION tap._disp166(p_order uuid, p_amt int, p_status text, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.dispute_native (dispute_id, stripe_dispute_ref, stripe_charge_ref,
                                     payment_id, amount_minor, currency, reason, status)
  select v_id, 'dp_166_' || p_tag, 'ch_166_' || p_tag, pn.payment_id, p_amt, 'USD', 'fraudulent', p_status
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

CREATE FUNCTION tap._rf166(p_order uuid, p_amt int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency,
                             status, stripe_refund_ref, idempotency_key)
  select v_id, pn.payment_id, 'buyer_request', p_amt, 'USD', 'succeeded', 're_166_' || p_tag, 'ck166-' || p_tag
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

-- a promoter (bps p_bps, identity = other_user()), a link, and an
-- attribution pinned to the given order — 151's tap._pinattr151 shape,
-- parameterized on face/bps so each section can drive its own arithmetic.
CREATE FUNCTION tap._promattr166(p_org uuid, p_event uuid, p_order uuid, p_face int, p_bps int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_pr uuid; v_ln uuid; v_attr uuid := gen_random_uuid();
BEGIN
  INSERT INTO venue.promoter (org_id, event_id, identity_id, commission_kind, commission_bps)
  VALUES (p_org, p_event, tap.other_user(), 'bps', p_bps) RETURNING promoter_id INTO v_pr;
  INSERT INTO venue.promoter_link (promoter_id, event_id, slug)
  VALUES (v_pr, p_event, 'ck166-link-' || lower(p_tag)) RETURNING link_id INTO v_ln;
  INSERT INTO venue.attribution (id, link_id, order_id, promoter_id, org_id, event_id, method,
      touch_corroborated, terms_version, commission_kind, commission_bps_applied,
      basis_minor, credited_amount_minor, resolution_reason, order_paid_at)
  VALUES (v_attr, v_ln, p_order, v_pr, p_org, p_event, 'link', true, 1, 'bps', p_bps,
      p_face, floor(p_face * p_bps / 10000.0)::int, 'link_only', now() - interval '40 days');
  RETURN v_attr;
END $f$;

-- open + close in one step; returns the settlement_id (163's tap._settle163 shape).
CREATE FUNCTION tap._settle166(p_org uuid, p_venue uuid, p_event uuid, p_key text) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_s uuid;
begin
  perform tap.login(tap.seller());
  v_s := (venue.open_settlement(p_org, p_venue, p_event, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid;
  perform tap.logout();
  perform tap.login(tap.admin_user());
  perform kernel.close_settlement(v_s, p_key || '-c');
  perform tap.logout();
  return v_s;
end $f$;

CREATE FUNCTION tap._netminor166(p_settlement uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT net_minor FROM venue.settlement WHERE settlement_id = p_settlement $f$;
CREATE FUNCTION tap._linesum166(p_settlement uuid, p_cause text) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT coalesce(sum(amount_minor),0)::bigint FROM venue.settlement_line WHERE settlement_id=p_settlement AND cause=p_cause $f$;
CREATE FUNCTION tap._oblamt166(p_ref uuid) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT amount_minor::bigint FROM kernel.organization_obligation WHERE origin_ref = p_ref $f$;
CREATE FUNCTION tap._oblcount166(p_ref uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM kernel.organization_obligation WHERE origin_ref = p_ref $f$;
CREATE FUNCTION tap._aal2_166() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._popaid166(p_settlement uuid, p_tr text, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_po uuid; v_org uuid; v jsonb;
begin
  select payout_id, payee_org_id into v_po, v_org from kernel.payout where cause='settlement' and cause_ref=p_settlement;
  perform tap.login(tap.seller());
  perform tap._aal2_166();
  perform kernel.request_org_payout(v_org, p_settlement, p_key || '-req');
  perform tap.logout();
  v := kernel.mark_payout_transfer_state(v_po, 'paid', p_tr, null, p_key);
  return v;
end $f$;
-- the CURRENT most-recent kernel.payout row for a promoter_commission
-- attribution (any state — 100 has no convergence, so there is exactly ONE
-- row for the lifetime of the fixture; ORDER BY/LIMIT is defensive, not
-- load-bearing).
CREATE FUNCTION tap._commrow166(p_attr uuid) RETURNS kernel.payout
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT po FROM kernel.payout po WHERE po.cause='promoter_commission' AND po.cause_ref=p_attr
      ORDER BY po.created_at DESC LIMIT 1 $f$;
CREATE FUNCTION tap._commcount166(p_attr uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM kernel.payout WHERE cause='promoter_commission' AND cause_ref=p_attr $f$;

-- ============================================================================
-- BASELINE FIXTURE — org O (seller), venue A. Every event/session sits well
--   in the past. Persists across every savepoint below.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st166('orgO', (kernel.create_organization('166 Co','166 Co','ck166-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g166('orgO');
SELECT tap.login(tap.seller());
SELECT tap._st166('venueA', (catalog.create_venue(tap._g166('orgO'),'166 Hall A','wynwood',NULL,'ck166-va') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g166('venueA'),'approved','miami_gate','ck166-aa');
SELECT tap.logout();

INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.settlement_maturity_interval', coalesce(max(version),0)+1, '"0 hours"'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.settlement_maturity_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '100000000'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';
UPDATE kernel.organization SET stripe_connect_account_ref='acct_166O', connect_transfers_active=true
 WHERE org_id = tap._g166('orgO');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days'
 WHERE org_id = tap._g166('orgO') AND identity_id = tap.seller();

SAVEPOINT sp_base;

-- ============================================================================
-- SECTION A — THE CANONICAL FIXTURE. face=10000, commission bps=1000 (10%),
--   funded and HELD via the real 090/098 path (pay_promoter_commission
--   through a settlement close), venue PAID 9000, then a FULL post-payout
--   chargeback (record_dispute_native lost + a later close). MUST prove: the
--   chargeback line is −9000 (NOT −10000), net −9000, obligation 9000 (NOT
--   10000); the held commission payout is UNTOUCHED (still 1000/pending/
--   held/unfunded_settlement — never converged, never minted twice, never
--   released); buyer net 0; conservation from DB rows only.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st166('evA', (catalog.create_event(tap._g166('venueA'),'166 A',
  jsonb_build_object('starts_at',(now()-interval '50 days')::text,'ends_at',(now()-interval '50 days'+interval '4 hours')::text),'ck166-ea') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st166('sessA', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g166('evA')));

SELECT tap._st166('oA', tap._ord166(tap._g166('sessA'), tap._g166('orgO'), 10000, 'oA')::text);
SELECT tap._st166('attrA', tap._promattr166(tap._g166('orgO'), tap._g166('evA'), tap._g166('oA'), 10000, 1000, 'A')::text);

-- first close: funds the commission (basis = full face, nothing reversed
-- yet) via the real 090/098 path, mints the venue's payout at the net
-- (9000), and pays it — the venue ACTUALLY RECEIVES 9000, exactly the
-- canonical fixture's premise.
SELECT tap._st166('SA1', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evA'), 'ck166-sa1')::text);
SELECT is(tap._netminor166(tap._g166('SA1')), 9000, 'A1: first close nets 9000 (10000 primary − 1000 commission funded)');
SELECT is(tap._linesum166(tap._g166('SA1'), 'promoter_commission'), -1000::bigint, 'A2: the commission line is −1000, funded held, not paid');
SELECT is((tap._commrow166(tap._g166('attrA'))).status||'|'||(tap._commrow166(tap._g166('attrA'))).hold_state||'|'||(tap._commrow166(tap._g166('attrA'))).hold_reason_code,
  'pending|held|unfunded_settlement', 'A3: the commission payout is born pending|held|unfunded_settlement — a GENUINE held kernel.payout row exists');
SELECT tap._popaid166(tap._g166('SA1'), 'tr_166_sa1', 'ck166-pay-sa1');
SELECT is((SELECT status FROM kernel.payout WHERE cause='settlement' AND cause_ref=tap._g166('SA1')), 'paid',
  'A4: the venue''s own settlement payout is paid — 9000 actually left the platform for the venue');

-- the full reversal: a lost dispute for the ENTIRE face, AFTER the venue was paid.
SELECT tap._st166('dA', tap._disp166(tap._g166('oA'), 10000, 'lost', 'dA')::text);
SELECT is((SELECT amount_minor FROM kernel.dispute_native WHERE dispute_id = tap._g166('dA')),
  (SELECT total_minor FROM venue."order" WHERE order_id = tap._g166('oA')),
  'A5: buyer net 0 — the dispute covers exactly the order''s full face, the same amount the buyer paid');

SELECT tap._st166('SA2', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evA'), 'ck166-sa2')::text);
SELECT is(tap._linesum166(tap._g166('SA2'), 'chargeback'), -9000::bigint,
  'A6: THE FIX — chargeback lines at −9000, not −10000 (face 10000 − held commission 1000)');
SELECT is(tap._netminor166(tap._g166('SA2')), -9000, 'A7: SA2 nets −9000');
SELECT is(tap._oblcount166(tap._g166('SA2')), 1, 'A8: exactly one obligation booked against SA2');
SELECT is(tap._oblamt166(tap._g166('SA2')), 9000::bigint, 'A9: THE FIX — venue owes 9000, not 10000');
SELECT is((SELECT venue_id FROM kernel.organization_obligation WHERE origin_ref = tap._g166('SA2')), tap._g166('venueA'),
  'A10: the obligation''s venue_id is venue A (097''s ring-fence, untouched)');

-- the held commission PAYOUT is NEVER touched by 100: same row, same amount,
-- same status/hold_state/hold_reason_code, before AND after the reversal —
-- 100 has no converge verb to call.
SELECT is(tap._commcount166(tap._g166('attrA')), 1, 'A11: still exactly ONE promoter_commission payout row for attrA — never minted twice');
SELECT is((tap._commrow166(tap._g166('attrA'))).amount_minor, 1000, 'A12: THE FIX — the held commission payout amount is UNCHANGED at 1000, never reduced');
SELECT is((tap._commrow166(tap._g166('attrA'))).status||'|'||(tap._commrow166(tap._g166('attrA'))).hold_state||'|'||(tap._commrow166(tap._g166('attrA'))).hold_reason_code,
  'pending|held|unfunded_settlement', 'A13: THE FIX — the held commission payout is UNTOUCHED: still pending|held|unfunded_settlement, never released, never relabeled');

-- CONSERVATION, every term a DB row, zero hand-derived quantity.
-- Funding side: order face = venue's paid settlement payout + the commission
-- the platform is still holding (never left the platform, never paid to the
-- promoter).
SELECT is(
  (SELECT total_minor FROM venue."order" WHERE order_id = tap._g166('oA'))::bigint,
  (SELECT amount_minor FROM kernel.payout WHERE cause='settlement' AND cause_ref=tap._g166('SA1'))::bigint
    + (tap._commrow166(tap._g166('attrA'))).amount_minor::bigint,
  'A14: CONSERVATION (funding side) — order face = venue''s paid settlement payout (9000) + the held commission payout (1000), read straight from kernel.payout');
-- Reversal side: the disputed amount = the obligation the venue owes back +
-- the held commission that stays with the platform, unreleased — the venue
-- was never paid that slice, so charging it back would claw back money the
-- venue never received, and it is not turned into platform revenue either
-- (it stays a HELD LIABILITY in kernel.payout, not booked as income anywhere).
SELECT is(
  (SELECT amount_minor FROM kernel.dispute_native WHERE dispute_id = tap._g166('dA'))::bigint,
  tap._oblamt166(tap._g166('SA2'))::bigint + (tap._commrow166(tap._g166('attrA'))).amount_minor::bigint,
  'A15: CONSERVATION (reversal side) — the disputed amount (10000) = the venue''s obligation (9000) + the held commission the platform is still sitting on (1000)');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION B — REFUND_VOID SYMMETRY. Same shape as A, but a POST-PAYOUT
--   SUCCEEDED REFUND (not a dispute) of a commissioned, already-paid-out
--   order. settlement_primary_lines' refund_void debit gets the identical
--   held-commission reduction settlement_royalty_lines' chargeback debit
--   gets in Section A. The obligation reflects face − held_commission (9000),
--   and the held commission payout is untouched here too.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st166('evB', (catalog.create_event(tap._g166('venueA'),'166 B',
  jsonb_build_object('starts_at',(now()-interval '49 days')::text,'ends_at',(now()-interval '49 days'+interval '4 hours')::text),'ck166-eb') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st166('sessB', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g166('evB')));

SELECT tap._st166('oB', tap._ord166(tap._g166('sessB'), tap._g166('orgO'), 10000, 'oB')::text);
SELECT tap._st166('attrB', tap._promattr166(tap._g166('orgO'), tap._g166('evB'), tap._g166('oB'), 10000, 1000, 'B')::text);
SELECT tap._st166('SB1', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evB'), 'ck166-sb1')::text);
SELECT is(tap._netminor166(tap._g166('SB1')), 9000, 'B1: SB1 funds the commission (1000) and nets 9000, same as A1');
SELECT tap._popaid166(tap._g166('SB1'), 'tr_166_sb1', 'ck166-pay-sb1');
SELECT is((SELECT status FROM kernel.payout WHERE cause='settlement' AND cause_ref=tap._g166('SB1')), 'paid',
  'B2: the venue''s settlement payout is paid — 9000 actually left the platform');

SELECT tap._st166('rB', tap._rf166(tap._g166('oB'), 10000, 'rB')::text);
SELECT tap._st166('SB2', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evB'), 'ck166-sb2')::text);
SELECT is(tap._linesum166(tap._g166('SB2'), 'refund_void'), -9000::bigint,
  'B3: THE SYMMETRY FIX — a POST-PAYOUT refund_void lines at −9000 (face 10000 − held commission 1000), not −10000');
SELECT is(tap._oblamt166(tap._g166('SB2')), 9000::bigint, 'B4: obligation 9000, matching the chargeback arm''s canonical result exactly');
SELECT is(tap._commcount166(tap._g166('attrB')), 1, 'B5: still exactly ONE promoter_commission payout row — never minted twice by the refund path either');
SELECT is((tap._commrow166(tap._g166('attrB'))).amount_minor||'|'||(tap._commrow166(tap._g166('attrB'))).status||'|'||(tap._commrow166(tap._g166('attrB'))).hold_state||'|'||(tap._commrow166(tap._g166('attrB'))).hold_reason_code,
  '1000|pending|held|unfunded_settlement', 'B6: THE FIX — the held commission payout is UNTOUCHED by the refund_void seam too: still 1000/pending/held/unfunded_settlement');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION C — NO COMMISSION ON THE ORDER (regression guard). 100 is a pure
--   no-op when held_commission_minor reads 0: the chargeback stays at the
--   ordinary face cap, byte-identical to 097.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st166('evC', (catalog.create_event(tap._g166('venueA'),'166 C',
  jsonb_build_object('starts_at',(now()-interval '48 days')::text,'ends_at',(now()-interval '48 days'+interval '4 hours')::text),'ck166-ec') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st166('sessC', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g166('evC')));

SELECT tap._st166('oC', tap._ord166(tap._g166('sessC'), tap._g166('orgO'), 10000, 'oC')::text);
SELECT tap._st166('SC1', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evC'), 'ck166-sc1')::text);
SELECT tap._popaid166(tap._g166('SC1'), 'tr_166_sc1', 'ck166-pay-sc1');
SELECT tap._st166('dC', tap._disp166(tap._g166('oC'), 10000, 'lost', 'dC')::text);
SELECT tap._st166('SC2', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evC'), 'ck166-sc2')::text);
SELECT is(tap._linesum166(tap._g166('SC2'), 'chargeback'), -10000::bigint, 'C1: NO ATTRIBUTION — the chargeback stays at the full face cap, byte-identical to 097 (no regression)');
SELECT is(tap._oblamt166(tap._g166('SC2')), 10000::bigint, 'C2: obligation is 10000 — unchanged from 097''s behavior when no commission exists');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION D — PRE-CLOSE / SAME-CLOSE (no double-reduce). A PARTIAL refund
--   (3000, well under face) lands BEFORE the commission is EVER funded — the
--   FIRST close for this order both books the refund_void AND funds the
--   commission, in the SAME transaction. held_commission_minor reads 0 at
--   settlement_primary_lines' seam time (no kernel.payout row exists yet for
--   this attribution), so refund_void is UNREDUCED (096/097 behaviour); 098's
--   OWN basis calc — a completely separate mechanism — then funds the
--   commission fresh against the ALREADY-refunded face. Two independent
--   reductions of the SAME 3000, each exactly once: prove neither seam
--   double-counts the other's work.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st166('evD', (catalog.create_event(tap._g166('venueA'),'166 D',
  jsonb_build_object('starts_at',(now()-interval '47 days')::text,'ends_at',(now()-interval '47 days'+interval '4 hours')::text),'ck166-ed') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st166('sessD', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g166('evD')));

SELECT tap._st166('oD', tap._ord166(tap._g166('sessD'), tap._g166('orgO'), 10000, 'oD')::text);
SELECT tap._st166('attrD', tap._promattr166(tap._g166('orgO'), tap._g166('evD'), tap._g166('oD'), 10000, 1000, 'D')::text);
-- the refund lands BEFORE any close — no prior close, no prior payout row
-- exists for attrD at all yet, so held_commission_minor cannot be anything
-- but 0 when the primary seam reads it.
SELECT is(tap._commcount166(tap._g166('attrD')), 0, 'D0: sanity — no commission payout exists yet for attrD before the first close');
SELECT tap._st166('rD', tap._rf166(tap._g166('oD'), 3000, 'rD')::text);
SELECT tap._st166('SD1', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evD'), 'ck166-sd1')::text);

SELECT is(tap._linesum166(tap._g166('SD1'), 'refund_void'), -3000::bigint,
  'D1: NO DOUBLE-REDUCE — the SAME-close refund_void lines at its own amount, unreduced (held_commission=0 — nothing funded yet when the seam ran)');
SELECT is(tap._linesum166(tap._g166('SD1'), 'promoter_commission'), -700::bigint,
  'D2: the commission funds FRESH, already against the post-refund face — floor((10000−3000)×1000/10000)=700, 098''s own formula, applied exactly once');
SELECT is(tap._netminor166(tap._g166('SD1')), 6300, 'D3: net = 10000 − 3000 − 700 = 6300 (positive — no obligation branch, and the 3000 was reduced from face exactly once, not twice)');
SELECT is(tap._oblcount166(tap._g166('SD1')), 0, 'D4: no obligation is booked — the venue was never underpaid');
SELECT is((tap._commrow166(tap._g166('attrD'))).hold_reason_code, 'unfunded_settlement',
  'D5: the freshly-funded row carries the ordinary 090/098 hold reason — 100 never touched it (there was nothing to converge)');
SELECT is(tap._commcount166(tap._g166('attrD')), 1, 'D6: exactly one payout row — 100 added no second seam pass here');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION E — RE-CLOSE IS noop_replay. 094/097's own forward-only behavior,
--   untouched by 100 (no new top-of-function work was added). Fixture-bearing
--   — placed last among the fixture sections so its rollback is the LAST
--   ROLLBACK TO SAVEPOINT in the file; the static sections below run
--   unrolled-back, exactly the shape 163_settlement_scope_and_shortfall.sql's
--   own closing "SECTION G" uses (pgTAP's own result bookkeeping is ordinary
--   transactional state — a ROLLBACK TO SAVEPOINT taken before finish() ever
--   runs erases it even though the TAP text was already printed, so the LAST
--   statement before finish() must never be a rollback).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st166('evE', (catalog.create_event(tap._g166('venueA'),'166 E',
  jsonb_build_object('starts_at',(now()-interval '46 days')::text,'ends_at',(now()-interval '46 days'+interval '4 hours')::text),'ck166-ee') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st166('sessE', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g166('evE')));
SELECT tap._st166('oE', tap._ord166(tap._g166('sessE'), tap._g166('orgO'), 10000, 'oE')::text);
SELECT tap._st166('SE1', tap._settle166(tap._g166('orgO'), tap._g166('venueA'), tap._g166('evE'), 'ck166-se1')::text);
SELECT tap.login(tap.admin_user());
SELECT is((kernel.close_settlement(tap._g166('SE1'), 'ck166-se1-c-again') ->> 'status'), 'noop_replay',
  'E1: a re-close of an already-closed settlement is noop_replay');
SELECT tap.logout();

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION F — THE HELD COMMISSION PAYOUT IS NEVER MINTED TWICE, NEVER
--   REDUCED, NEVER RELEASED BY 100 (static proof, no fixture needed). Grep
--   the two seam bodies: neither CALLS a convergence verb (the word
--   "converge" appears only in explanatory comments and one inert defensive
--   filter, `hold_reason_code <> 'commission_converged'`, guarding against a
--   value nothing in the shipped kernel ever sets — see the migration's own
--   header), nor do they insert/update kernel.payout. The dynamic proof is
--   Sections A/B above (the SAME row, SAME amount, SAME state, before and
--   after the reversal); this is the static complement.
-- ============================================================================
SELECT ok((SELECT pg_get_functiondef(p.oid) !~* 'converge_held_commission'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_primary_lines'),
  'F1: kernel.settlement_primary_lines never CALLS converge_held_commission — no convergence verb exists to call');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~* 'converge_held_commission'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'F2: kernel.settlement_royalty_lines never calls it either');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~* 'insert\s+into\s+kernel\.payout' AND pg_get_functiondef(p.oid) !~* 'update\s+kernel\.payout'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_primary_lines'),
  'F3: kernel.settlement_primary_lines never inserts into or updates kernel.payout — it only READS the held commission, mutates nothing');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~* 'insert\s+into\s+kernel\.payout' AND pg_get_functiondef(p.oid) !~* 'update\s+kernel\.payout'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'F4: kernel.settlement_royalty_lines never inserts into or updates kernel.payout either');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                        WHERE n.nspname='kernel' AND p.proname='converge_held_commission'),
  'F5: kernel.converge_held_commission does not exist — 100 shipped seams-only, no convergence verb');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~* 'converge_held_commission'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='close_settlement'),
  'F6: kernel.close_settlement never names converge_held_commission — 100 did not re-create close_settlement');

-- ============================================================================
-- SECTION G — kernel.record_organization_obligation IS UNTOUCHED. amount =
--   -net still holds, because net is now correct BEFORE record_organization_
--   obligation ever sees it — 100 never edits this function.
-- ============================================================================
SELECT ok((SELECT pg_get_functiondef(p.oid) !~* 'held_commission'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='record_organization_obligation'),
  'G1: kernel.record_organization_obligation never names held_commission — 100 does not touch it, it books whatever net the (now-correct) lines produced');
SELECT ok((SELECT pg_get_functiondef(p.oid) ~ 'amount_minor <> -v_s\.net_minor'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='record_organization_obligation'),
  'G2: the amount = -net precondition text is present, unchanged — 097''s own text');

SELECT * FROM finish();
ROLLBACK;
