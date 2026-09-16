-- ============================================================================
-- 163_settlement_scope_and_shortfall.sql — package 097.
--
-- SUBJECT: the venue ring-fence on kernel.settlement_royalty_lines' chargeback
--   arm, the refund/dispute deferral mirror on both debit arms, the fenced
--   and derived kernel.organization_obligation('unlined_reversal') origin,
--   the same-venue 'shortfall_pending' payout hold in kernel.close_settlement,
--   the ninth kernel.settlement_payout_maturity predicate ('dispute_
--   unabsorbed'), and the dispute-writer hygiene fixes.
--
-- Frozen sources: docs/phase2/_impl/KC_chargeback_accounting.md (§2.a-§2.U,
--   §4), KG_cross_venue_isolation.md (§2, V1-V10, §4), KB_dispute_db_mapping.md
--   (§2.3-§2.7, §4), KD_obligation_recovery.md §4.4, orchestrator DESIGN_
--   097_099.md §M2.
--
-- FIXTURE SHAPE (KG's, per the orchestrator memo): org O (seller) with TWO
--   venues, A and B; org P (other_user) with venue C. Every session sits well
--   in the past and payout.settlement_maturity_interval is '0 hours', so a
--   payout mints UNHELD by the maturity clock unless a scenario deliberately
--   puts an operand in its way — the maturity clock itself is not this file's
--   subject (151/C28 owns it).
--
-- ISOLATION: each major section runs inside its OWN SAVEPOINT (KG's own
--   methodology, §2.0) and rolls back to a shared baseline before the next
--   section starts. The chargeback arm now offers ANY unlined, ring-fenced
--   dispute to the NEXT settlement of that venue regardless of which order
--   introduced it — so an unlined dispute left over from one section would
--   otherwise be silently swept into an unrelated later section's close.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixtures reuse the
--   tap._ord160-style order/payment/payment_native triple (160) and the
--   tap._sess160-style session/config idiom (161) — renamed to the 163
--   suffix so nothing here collides with a sibling file's memo table.
-- ============================================================================
BEGIN;
SELECT plan(74);

SELECT tap.seed_core();

CREATE TABLE tap.memo_163 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st163(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_163 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._g163(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_163 WHERE k = $1 $m$;

CREATE FUNCTION tap._aal2_163() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- The exact triple venue.finalize_primary_order leaves behind (085:2059-2061).
-- p_fee sits ON TOP of p_face (payments.total = face+fee, order.total_minor =
-- face only) — KC's own harness shape, needed so the deferral arithmetic has
-- a real fee slice to prove it caps at the PAYMENT's total, not the order's face.
CREATE FUNCTION tap._ord163(p_session uuid, p_org uuid, p_face int, p_fee int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_ord uuid := gen_random_uuid(); v_pay uuid := gen_random_uuid();
begin
  insert into venue."order" (order_id, buyer_id, event_session_id, org_id, status, source,
                             total_minor, currency, command_idempotency_key)
  values (v_ord, tap.buyer(), p_session, p_org, 'paid', 'app', p_face, 'USD', 'ck163-' || p_tag);
  insert into public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total,
                               stripe_payment_intent_id, status, mode, paid_at)
  values (v_pay, tap.buyer(), p_face, p_fee, 0, p_face + p_fee, 'pi_163_' || p_tag, 'succeeded', 'native_primary', now());
  insert into kernel.payment_native (payment_id, order_id, amount_minor, currency)
  values (v_pay, v_ord, p_face + p_fee, 'USD');
  return v_ord;
end $f$;

-- A dispute, written directly (no TS caller exists — KA/KB gap, not this
-- file's to close), with a real stripe_dispute_ref so mark_dispute_state can
-- be exercised on it.
CREATE FUNCTION tap._disp163(p_order uuid, p_amt int, p_status text, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.dispute_native (dispute_id, stripe_dispute_ref, stripe_charge_ref,
                                     payment_id, amount_minor, currency, reason, status)
  select v_id, 'dp_163_' || p_tag, 'ch_163_' || p_tag, pn.payment_id, p_amt, 'USD',
         'fraudulent', p_status
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

CREATE FUNCTION tap._rf163(p_order uuid, p_amt int, p_status text, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency,
                             status, stripe_refund_ref, idempotency_key)
  select v_id, pn.payment_id, 'buyer_request', p_amt, 'USD', p_status,
         case when p_status = 'pending' then null else 're_163_' || p_tag end, 'ck163-' || p_tag
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

-- open + close in one step; returns the settlement_id. event-scoped when
-- p_event is not null, else period-scoped with NO window (open-ended —
-- 097 carries no period window on debits, so this is the honest default).
-- 2026-09-03 (this reconciliation): p_owner added, defaulting to tap.seller() (every existing
-- call site is unaffected) — the ORIGINAL body hardcoded tap.seller() as the opener regardless
-- of which org was passed, which fails for org P (owned by tap.other_user(), never seller())
-- with insufficient_privilege. A pre-existing fixture bug, never actually run before this
-- reconciliation (163's KM2 report is AUTHOR ONLY).
CREATE FUNCTION tap._settle163(p_org uuid, p_venue uuid, p_event uuid, p_key text, p_owner uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_s uuid;
begin
  perform tap.login(coalesce(p_owner, tap.seller()));
  v_s := (venue.open_settlement(p_org, p_venue, p_event, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid;
  perform tap.logout();
  perform tap.login(tap.admin_user());
  perform kernel.close_settlement(v_s, p_key || '-c');
  perform tap.logout();
  return v_s;
end $f$;

CREATE FUNCTION tap._payoutstate163(p_id uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT status || '|' || hold_state || '|' || coalesce(hold_reason_code,'-') || '|' || amount_minor::text
      FROM kernel.payout WHERE payout_id = p_id $f$;
CREATE FUNCTION tap._settlepo163(p_settlement uuid) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT payout_id FROM kernel.payout WHERE cause='settlement' AND cause_ref=p_settlement ORDER BY created_at LIMIT 1 $f$;
CREATE FUNCTION tap._netminor163(p_settlement uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT net_minor FROM venue.settlement WHERE settlement_id = p_settlement $f$;
CREATE FUNCTION tap._linesum163(p_settlement uuid, p_cause text) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT coalesce(sum(amount_minor),0)::bigint FROM venue.settlement_line WHERE settlement_id=p_settlement AND cause=p_cause $f$;
CREATE FUNCTION tap._linecount163(p_settlement uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM venue.settlement_line WHERE settlement_id = p_settlement $f$;
CREATE FUNCTION tap._haslined163(p_settlement uuid, p_cause text, p_ref uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT exists(SELECT 1 FROM venue.settlement_line WHERE settlement_id=p_settlement AND cause=p_cause AND cause_ref=p_ref) $f$;
-- 2026-09-03 (this reconciliation): the ORIGINAL body called mark_payout_transfer_state(paid)
-- directly on a still-'pending' payout, which 085's own forward-only state machine has ALWAYS
-- refused (precondition_failed: payout_state_backwards) — pending must first advance through
-- request_org_payout to 'submitted'. This was a pre-existing fixture bug (never actually run
-- before this reconciliation — 163's own KM2 report is AUTHOR ONLY, no DB access), not a 097
-- behavior change. Fixed here by deriving the payout's org/settlement and requesting it first,
-- as tap.seller() (orgO's org_owner, membership backdated 40 days past the 24h maturity floor)
-- with aal2 — the same authorization request_org_payout requires everywhere else in the corpus
-- (161/162's own _request16x helpers). Every existing call site is unaffected (same signature).
CREATE FUNCTION tap._pay163(p_payout uuid, p_tr text, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v_settlement uuid; v_org uuid; v_status text; v jsonb;
begin
  select cause_ref, payee_org_id, status into v_settlement, v_org, v_status from kernel.payout where payout_id = p_payout;
  if v_status = 'pending' then
    perform tap.login(tap.seller());
    perform tap._aal2_163();
    perform kernel.request_org_payout(v_org, v_settlement, p_key || '-req');
    perform tap.logout();
  end if;
  v := kernel.mark_payout_transfer_state(p_payout, 'paid', p_tr, null, p_key);
  return v;
end $f$;
CREATE FUNCTION tap._oblcount163(p_ref uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM kernel.organization_obligation WHERE origin_ref = p_ref $f$;
CREATE FUNCTION tap._oblrow163(p_ref uuid) RETURNS kernel.organization_obligation
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT o FROM kernel.organization_obligation o WHERE origin_ref = p_ref ORDER BY created_at DESC LIMIT 1 $f$;
CREATE FUNCTION tap._cbline163(p_dispute uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM venue.settlement_line WHERE cause='chargeback' AND cause_ref = p_dispute $f$;
CREATE FUNCTION tap._coveredhas163(p_settlement uuid, p_session uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT exists(SELECT 1 FROM kernel.settlement_covered_payments(p_settlement) c WHERE c.session_id = p_session) $f$;
CREATE FUNCTION tap._retry163(p_org uuid, p_settlement uuid, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v jsonb;
begin
  perform tap.login(tap.seller());
  perform tap._aal2_163();
  v := kernel.retry_held_payout(p_org, p_settlement, p_key);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._release163(p_payout uuid, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v jsonb;
begin
  perform tap.login(tap.admin_user());
  v := kernel.release_payout(p_payout, p_key);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._mark163(p_ref text, p_status text, p_key text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT kernel.mark_dispute_state(p_ref, p_status, p_key) $f$;

-- ============================================================================
-- BASELINE FIXTURE — org O (seller) → venue A, venue B. org P (other_user) →
--   venue C. Persists across every savepoint below (never rolled back).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st163('orgO', (kernel.create_organization('163 Co','163 Co','ck163-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g163('orgO');
SELECT tap.login(tap.seller());
SELECT tap._st163('venueA', (catalog.create_venue(tap._g163('orgO'),'163 Hall A','wynwood',NULL,'ck163-va') ->> 'venue_id'));
SELECT tap._st163('venueB', (catalog.create_venue(tap._g163('orgO'),'163 Hall B','brickell',NULL,'ck163-vb') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g163('venueA'),'approved','miami_gate','ck163-aa');
SELECT catalog.approve_venue(tap._g163('venueB'),'approved','miami_gate','ck163-ab');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._st163('orgP', (kernel.create_organization('163 Other Co','163 Other Co','ck163-op') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g163('orgP');
SELECT tap.login(tap.other_user());
SELECT tap._st163('venueC', (catalog.create_venue(tap._g163('orgP'),'163 Hall C','downtown miami',NULL,'ck163-vc') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g163('venueC'),'approved','miami_gate','ck163-ac');
SELECT tap.logout();

SELECT tap.login(tap.seller());
SELECT tap._st163('evA', (catalog.create_event(tap._g163('venueA'),'163 A',
  jsonb_build_object('starts_at',(now()-interval '50 days')::text,'ends_at',(now()-interval '50 days'+interval '4 hours')::text),'ck163-ea') ->> 'event_id'));
SELECT tap._st163('evA2', (catalog.create_event(tap._g163('venueA'),'163 A2',
  jsonb_build_object('starts_at',(now()-interval '49 days')::text,'ends_at',(now()-interval '49 days'+interval '4 hours')::text),'ck163-ea2') ->> 'event_id'));
SELECT tap._st163('evB', (catalog.create_event(tap._g163('venueB'),'163 B',
  jsonb_build_object('starts_at',(now()-interval '48 days')::text,'ends_at',(now()-interval '48 days'+interval '4 hours')::text),'ck163-eb') ->> 'event_id'));
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._st163('evC', (catalog.create_event(tap._g163('venueC'),'163 C',
  jsonb_build_object('starts_at',(now()-interval '47 days')::text,'ends_at',(now()-interval '47 days'+interval '4 hours')::text),'ck163-ec') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st163('sessA',  (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g163('evA')));
SELECT tap._st163('sessB',  (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g163('evB')));
SELECT tap._st163('sessC',  (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g163('evC')));

INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.settlement_maturity_interval', coalesce(max(version),0)+1, '"0 hours"'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.settlement_maturity_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '100000000'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';
-- Connect capability for org O (161's recipe) — needed only so retry_held_
-- payout's CLEAR path can delegate all the way to a real 'submitted' below.
UPDATE kernel.organization SET stripe_connect_account_ref='acct_163O', connect_transfers_active=true
 WHERE org_id = tap._g163('orgO');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days'
 WHERE org_id = tap._g163('orgO') AND identity_id = tap.seller();

SAVEPOINT sp_base;

-- ============================================================================
-- SECTION A — THE VENUE RING-FENCE (KG P0-1/P0-2; V1/V2/V3/V4/V8/V10).
-- ============================================================================
SELECT tap._st163('oA1', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 50000, 0, 'oA1')::text);
SELECT tap._st163('SA1', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), tap._g163('evA'), 'sa1')::text);
SELECT is(tap._netminor163(tap._g163('SA1')), 50000, 'A1: SA1 (venue A, event evA) nets 50000 on oA1 alone');
SELECT tap._pay163(tap._settlepo163(tap._g163('SA1')), 'tr_163_sa1', 'ck163-pay-sa1');
SELECT is(tap._payoutstate163(tap._settlepo163(tap._g163('SA1'))), 'paid|none|-|50000', 'A2: SA1''s payout is paid');

SELECT tap._st163('dA1', tap._disp163(tap._g163('oA1'), 50000, 'lost', 'dA1')::text);

-- V2: venue B, EVENT-scoped — offered nothing of A's debt.
SELECT tap._st163('oB1', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 100000, 0, 'oB1')::text);
SELECT tap._st163('SBe', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), tap._g163('evB'), 'sbe')::text);
SELECT is(tap._netminor163(tap._g163('SBe')), 100000, 'A3: V2 — SBe (venue B, event-scoped) nets its own 100000, not 50000');
SELECT is(tap._linecount163(tap._g163('SBe')), 1, 'A4: …exactly one line — no foreign chargeback offered');
SELECT is(tap._cbline163(tap._g163('dA1')), 0, 'A5: dA1 carries no chargeback line anywhere yet');
SELECT is(tap._coveredhas163(tap._g163('SBe'), tap._g163('sessA')), false,
  'A6: V6/V7/V7b proxy — SBe''s covered set excludes venue A''s session entirely (nothing of A''s lifecycle can leak onto B''s hold/staleness operands)');

-- V1: venue B, PERIOD-scoped (a fresh order, oB1 is already lined) — same result.
SELECT tap._st163('oB1b', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 20000, 0, 'oB1b')::text);
SELECT tap._st163('SBp', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp')::text);
SELECT is(tap._netminor163(tap._g163('SBp')), 20000, 'A7: V1 — SBp (venue B, period-scoped) nets its own 20000, not 70000');

-- V3: venue A's own NEXT settlement absorbs its own dispute.
SELECT tap._st163('SA2', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa2')::text);
SELECT is(tap._netminor163(tap._g163('SA2')), -50000, 'A8: SA2 (venue A, period-scoped, no new orders) nets -50000 on dA1 alone');
SELECT ok(tap._haslined163(tap._g163('SA2'), 'chargeback', tap._g163('dA1')),
  'A9: …as an append-only negative line, cause_ref = the dispute (153/H47 shape, re-proved at one venue)');
SELECT is(tap._settlepo163(tap._g163('SA2')), null,
  'A10: NEGATIVE_SETTLEMENT_CARRY — no payout is minted for SA2 (153/H48 shape, re-proved at one venue)');
SELECT is(tap._oblcount163(tap._g163('SA2')), 1, 'A11: the shortfall is booked — one obligation row, origin_ref = SA2');
SELECT is((tap._oblrow163(tap._g163('SA2'))).amount_minor, 50000, 'A12: …amount 50000');
SELECT is((tap._oblrow163(tap._g163('SA2'))).venue_id, tap._g163('venueA'),
  'A13: …venue_id = venue A — the ORIGINATING venue, not any absorbing one (KD P1-5 closed)');

-- V10: a DIFFERENT event at the SAME venue still absorbs (grain-agnostic).
SELECT tap._st163('oA3', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 30000, 0, 'oA3')::text);
SELECT tap._st163('dA2', tap._disp163(tap._g163('oA3'), 30000, 'lost', 'dA2')::text);
SELECT tap._st163('SA3', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), tap._g163('evA2'), 'sa3')::text);
SELECT is(tap._netminor163(tap._g163('SA3')), -30000,
  'A14: V10 — SA3 (venue A, event evA2 — a DIFFERENT event than dA2''s order) still absorbs dA2''s -30000');
SELECT is((tap._oblrow163(tap._g163('SA3'))).venue_id, tap._g163('venueA'), 'A15: …venue_id = venue A again');

-- V4: venue B nets its own clean revenue even while venue A carries a
-- SEPARATE, still-unlined debt bigger than it.
SELECT tap._st163('oA4', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 80000, 0, 'oA4')::text);
SELECT tap._st163('dA3', tap._disp163(tap._g163('oA4'), 80000, 'lost', 'dA3')::text);
SELECT tap._st163('oB2', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 30000, 0, 'oB2')::text);
SELECT tap._st163('SBp2', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp2')::text);
SELECT is(tap._netminor163(tap._g163('SBp2')), 30000,
  'A16: V4 — SBp2 nets exactly its own 30000; venue A''s 80000 debt does not touch it');
SELECT is(tap._cbline163(tap._g163('dA3')), 0, 'A17: …dA3 stays unlined, waiting for a venue A close, not silently consumed');

-- V8: cross-org isolation is unaffected by the ring-fence.
-- 2026-09-03 (this reconciliation): dC1 moved to AFTER SCp's close. cb_candidate (097
-- Section 5, unchanged in this respect from 093) has NO "already paid out" precondition —
-- it lines any lost/charge_refunded dispute that exists BEFORE a close, whether or not the
-- order was ever paid before. The ORIGINAL ordering created dC1 before SCp's first-ever
-- close, so oC1's own dispute would have been netted INTO SCp itself (30000 credit − 30000
-- debit = net 0), contradicting both A18 (want 30000) and A19 (want dC1 unlined) — a
-- pre-existing fixture-ordering bug (never actually run before this reconciliation), not a
-- 097 behavior change. Re-ordering to close-then-dispute (the same pattern org O''s own A1-A3
-- fixture above uses: pay first, dispute after) makes both assertions honestly true.
SELECT tap._st163('oC1', tap._ord163(tap._g163('sessC'), tap._g163('orgP'), 30000, 0, 'oC1')::text);
SELECT tap._st163('SCp', tap._settle163(tap._g163('orgP'), tap._g163('venueC'), null, 'scp', tap.other_user())::text);
SELECT is(tap._netminor163(tap._g163('SCp')), 30000, 'A18: V8 — org P''s own settlement nets its own revenue');
SELECT tap._st163('dC1', tap._disp163(tap._g163('oC1'), 30000, 'lost', 'dC1')::text);
SELECT is(tap._cbline163(tap._g163('dC1')), 0, 'A19: …dC1 is not lined anywhere (org P has not yet closed a second settlement)');

-- CONSERVATION BLOCK (KC's identity), scoped to the oA1/dA1/SA2 triple:
--   collected − chargeback − venue_paid = −obligation_receivable, exactly.
-- 2026-09-03 (this reconciliation): pgTAP's is() couldn't resolve an overload for
-- bigint vs integer (the LHS promotes to bigint via _linesum163's bigint return; the RHS
-- was a bare integer negation) — "function is(bigint, integer, unknown) does not exist".
-- A pre-existing type-mismatch bug (never actually run before this reconciliation), fixed
-- by an explicit ::bigint cast on the RHS; the arithmetic itself is unchanged.
SELECT is(
  (SELECT p.total FROM public.payments p WHERE p.stripe_payment_intent_id = 'pi_163_oA1')
  - (- tap._linesum163(tap._g163('SA2'), 'chargeback'))
  - (SELECT po.amount_minor FROM kernel.payout po WHERE po.cause='settlement' AND po.cause_ref = tap._g163('SA1') AND po.status='paid'),
  (- (tap._oblrow163(tap._g163('SA2'))).amount_minor)::bigint,
  'A20: CONSERVATION — collected(50000) − chargeback(50000) − venue_paid(50000) = −obligation(50000)');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION B — REFUND/DISPUTE DEFERRAL MIRROR (KC P0-2, 2.d-i / 2.d-ii).
-- ============================================================================
-- 2.d-i: refund pending 23000 + dispute lost 23000 on a NEVER-CLOSED order —
--   both arms move together in ONE close: credit +19000, debit −19000, net 0.
SELECT tap._st163('oB3', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 19000, 4000, 'oB3')::text);
SELECT tap._st163('r0',  tap._rf163(tap._g163('oB3'), 23000, 'pending', 'r0')::text);
SELECT tap._st163('d0',  tap._disp163(tap._g163('oB3'), 23000, 'lost', 'd0')::text);
SELECT tap._st163('SBp3', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp3')::text);
SELECT ok(tap._haslined163(tap._g163('SBp3'), 'primary_sale', tap._g163('oB3')),
  'B1: 2.d-i — the credit lands (the refund could never succeed within the payment total, so it does not defer)');
SELECT ok(tap._haslined163(tap._g163('SBp3'), 'chargeback', tap._g163('d0')),
  'B2: …the SAME close lines the chargeback, capped at face (−19000, not −23000)');
SELECT is(tap._netminor163(tap._g163('SBp3')), 0, 'B3: …net 0 — no shortfall, no phantom debt');
SELECT is(tap._oblcount163(tap._g163('SBp3')), 0, 'B4: …no obligation booked');

ROLLBACK TO SAVEPOINT sp_base;

-- 2.d-ii: venue already paid; refund+dispute arrive AFTER — the credit is
--   already lined, so only the debit is at stake, and it lines correctly.
SELECT tap._st163('oB4', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 19000, 4000, 'oB4')::text);
SELECT tap._st163('SBp4a', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp4a')::text);
SELECT is(tap._netminor163(tap._g163('SBp4a')), 19000, 'B5: SBp4a nets 19000 cleanly, before any dispute exists');
SELECT tap._pay163(tap._settlepo163(tap._g163('SBp4a')), 'tr_163_sbp4a', 'ck163-pay-sbp4a');
SELECT tap._st163('r1', tap._rf163(tap._g163('oB4'), 23000, 'pending', 'r1')::text);
SELECT tap._st163('d1', tap._disp163(tap._g163('oB4'), 23000, 'lost', 'd1')::text);
SELECT tap._st163('SBp4b', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp4b')::text);
SELECT is(tap._linecount163(tap._g163('SBp4b')), 1, 'B6: SBp4b carries exactly one NEW line (the primary_sale is already lined)');
SELECT ok(tap._haslined163(tap._g163('SBp4b'), 'chargeback', tap._g163('d1')), 'B7: …the chargeback, capped at face −19000');
SELECT is(tap._netminor163(tap._g163('SBp4b')), -19000, 'B8: …net −19000');
SELECT is((tap._oblrow163(tap._g163('SBp4b'))).amount_minor, 19000, 'B9: …shortfall 19000 booked, venue B');
SELECT is((tap._oblrow163(tap._g163('SBp4b'))).venue_id, tap._g163('venueB'), 'B10: …venue_id = venue B');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION C — THE unlined_reversal FENCE (KC P1-2/2.e/2.g/2.U, KD §4.4).
-- ============================================================================
-- 2.e analog: a loss already absorbed by refund_void seniority has no headroom.
SELECT tap._st163('oB5', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 19000, 0, 'oB5')::text);
SELECT tap._st163('SBp5a', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp5a')::text);
SELECT tap._pay163(tap._settlepo163(tap._g163('SBp5a')), 'tr_163_sbp5a', 'ck163-pay-sbp5a');
SELECT tap._st163('r2', tap._rf163(tap._g163('oB5'), 19000, 'succeeded', 'r2')::text);
SELECT tap._st163('SBp5b', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sbp5b')::text);
SELECT is(tap._netminor163(tap._g163('SBp5b')), -19000, 'C1: fixture control — refund_void −19000 booked as a shortfall first');
SELECT tap._st163('d2', tap._disp163(tap._g163('oB5'), 19000, 'lost', 'd2')::text);
SELECT throws_like(
  format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,null,19000,'USD','test','ck163-noheadroom1')$$,
         tap._g163('orgO'), tap._g163('d2')),
  '%no_headroom%', 'C2: 2.e — no headroom left (refund_void already consumed the whole face)');

ROLLBACK TO SAVEPOINT sp_base;

-- 2.g analog: a loss already capped away by a PRIOR chargeback has no headroom.
SELECT tap._st163('oA1', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 50000, 0, 'oA1')::text);
SELECT tap._st163('SA1', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa1g')::text);
SELECT tap._pay163(tap._settlepo163(tap._g163('SA1')), 'tr_163_sa1g', 'ck163-pay-sa1g');
SELECT tap._st163('dA1', tap._disp163(tap._g163('oA1'), 50000, 'lost', 'dA1g')::text);
SELECT tap._st163('SA2', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa2g')::text);
SELECT is(tap._netminor163(tap._g163('SA2')), -50000, 'C3: fixture control — the whole face is capped by the first dispute''s chargeback');
SELECT tap._st163('dA1b', tap._disp163(tap._g163('oA1'), 10000, 'lost', 'dA1bg')::text);
SELECT throws_like(
  format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,null,10000,'USD','test','ck163-noheadroom2')$$,
         tap._g163('orgO'), tap._g163('dA1b')),
  '%no_headroom%', 'C4: 2.g — a third dispute on the SAME order, after the face is exhausted, has no headroom');

ROLLBACK TO SAVEPOINT sp_base;

-- 2.U analog: booked once, a LATER close does NOT line it a second time.
SELECT tap._st163('oA5', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 40000, 0, 'oA5')::text);
SELECT tap._st163('SA5a', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa5a')::text);
SELECT tap._pay163(tap._settlepo163(tap._g163('SA5a')), 'tr_163_sa5a', 'ck163-pay-sa5a');
SELECT tap._st163('d3', tap._disp163(tap._g163('oA5'), 40000, 'lost', 'd3')::text);
SELECT is(
  (kernel.record_organization_obligation(tap._g163('orgO'),'unlined_reversal',tap._g163('d3'),null,40000,'USD','test','ck163-u1') ->> 'status'),
  'ok', 'C5: 2.U — the operator books the loss directly, amount ledger-derived (40000)');
SELECT tap._st163('SA5b', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa5b')::text);
SELECT is(tap._cbline163(tap._g163('d3')), 0, 'C6: …the LATER venue-A close does NOT also line it as a chargeback (bidirectional fence)');
SELECT is(tap._oblcount163(tap._g163('d3')), 1, 'C7: …org_outstanding stays at the SINGLE loss — booked once, not twice');
SELECT is(tap._netminor163(tap._g163('SA5b')), 0, 'C8: …SA5b itself nets 0 (nothing else to line)');

ROLLBACK TO SAVEPOINT sp_base;

-- POST-PAYOUT PROOF: an order that was never even lined into a settlement
-- carries no debt — "a loss on money the organization never received".
SELECT tap._st163('oA6', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 15000, 0, 'oA6')::text);
SELECT tap._st163('d4', tap._disp163(tap._g163('oA6'), 15000, 'lost', 'd4')::text);
SELECT throws_like(
  format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,null,15000,'USD','test','ck163-notpaid')$$,
         tap._g163('orgO'), tap._g163('d4')),
  '%order_not_paid_out%', 'C9: the order was never lined into ANY settlement — refused as order_not_paid_out');

ROLLBACK TO SAVEPOINT sp_base;

-- AMOUNT IS LEDGER-DERIVED, never caller-priced; replay is idempotent.
SELECT tap._st163('oA7', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 20000, 0, 'oA7')::text);
SELECT tap._st163('SA7a', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa7a')::text);
SELECT tap._pay163(tap._settlepo163(tap._g163('SA7a')), 'tr_163_sa7a', 'ck163-pay-sa7a');
SELECT tap._st163('d5', tap._disp163(tap._g163('oA7'), 20000, 'lost', 'd5')::text);
SELECT throws_like(
  format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,null,99,'USD','test','ck163-wrongamt')$$,
         tap._g163('orgO'), tap._g163('d5')),
  '%ledger-derived loss%', 'C10: the caller''s wrong amount (99) is refused, not silently accepted');
SELECT is(
  (kernel.record_organization_obligation(tap._g163('orgO'),'unlined_reversal',tap._g163('d5'),null,20000,'USD','test','ck163-rightamt') ->> 'status'),
  'ok', 'C11: the derived amount (20000) is accepted');
SELECT is(
  (kernel.record_organization_obligation(tap._g163('orgO'),'unlined_reversal',tap._g163('d5'),null,20000,'USD','test','ck163-rightamt') ->> 'status'),
  'noop_replay', 'C12: a replay of the same command is idempotent');

-- RANDOM UUID refused.
SELECT throws_like(
  format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,null,1,'USD','test','ck163-random')$$,
         tap._g163('orgO'), gen_random_uuid()),
  '%not_found%', 'C13: a random uuid resolves to neither a dispute nor a refund — not_found');

-- SALE-ARM (resale-rail) origin refused.
-- payments_rail_pairing_ck (093 PFA-PT-3) requires a buy_now/auction row to carry a real
-- listing_id + seller_id (native_primary is the only mode allowed to leave them null) — the
-- ORIGINAL insert omitted both, which 097/093's own CHECK has always refused. A pre-existing
-- fixture bug (never actually run before this reconciliation), fixed by giving it a real
-- public.listings row, matching the shape 153's tap._newlisting153/_newpayment153 use.
SELECT tap.login_service();
INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time,
      ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
VALUES (tap.seller(), '163 Sale-Arm Fixture', '163 Hall A', 'wynwood',
      (now()+interval '15 days')::date, '20:00', 'GA', 1, 'mobile_transfer', 50, 50, 24,
      now()+interval '1 day', 'covers/fixture.jpg');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode)
SELECT gen_random_uuid(), l.id, tap.buyer(), tap.seller(), 5000, 0, 0, 5000, 'pi_163_salearm', 'succeeded', 'buy_now'
  FROM public.listings l WHERE l.event_name = '163 Sale-Arm Fixture';
SELECT tap.logout();
SELECT tap._st163('pFake', (SELECT id::text FROM public.payments WHERE stripe_payment_intent_id = 'pi_163_salearm'));
-- fk_payment_native_sale (089's late-binding FK, 154/A14) requires a REAL market.market_sale
-- row — the ORIGINAL insert cited a bare gen_random_uuid(), which that FK has always refused.
-- A pre-existing fixture bug (never actually run before this reconciliation). The minimal real
-- chain: one venue.ticket_type + one kernel.signing_key + one kernel.tickets atom + one
-- market.market_sale, none of which this file otherwise needs, built directly (raw INSERT,
-- matching this file's own house style for every other fixture row).
-- market.market_sale.listing_id FKs to market.listing_native (the NATIVE resale listing),
-- a DIFFERENT table from public.listings above (which only payments_rail_pairing_ck cares
-- about) — listing_native itself needs a resale_policy row (catalog.resale_policy) and a
-- real kernel.tickets atom (which needs a venue.ticket_type + kernel.signing_key). All built
-- directly, matching this file's house style.
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, currency, visibility)
VALUES ('00000000-0000-0000-0000-000000163001', tap._g163('evC'), 'admission', '163 Sale-Arm GA', 5000, 'USD', 'hidden');
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, status, not_before)
VALUES ('00000000-0000-0000-0000-000000163002', 'global', 'MTYzLXNhbGUtYXJtLWZpeHR1cmU=', 'kms://163-fixture', 'active', now() - interval '1 day');
INSERT INTO kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, signing_key_id)
VALUES ('00000000-0000-0000-0000-000000163003', tap._g163('sessC'), tap._g163('orgP'), '00000000-0000-0000-0000-000000163001', 1, tap.buyer(), '00000000-0000-0000-0000-000000163002');
INSERT INTO catalog.resale_policy (policy_id, scope_kind, venue_id, mode, version)
VALUES ('00000000-0000-0000-0000-000000163005', 'venue', tap._g163('venueC'), 'buy_now', 1);
INSERT INTO market.listing_native (listing_id, ticket_atom_id, seller_id, event_session_id, listing_mode,
      price_minor, resale_policy_id, resale_policy_version, status, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-000000163006', '00000000-0000-0000-0000-000000163003', tap.seller(),
      tap._g163('sessC'), 'buy_now', 5000, '00000000-0000-0000-0000-000000163005', 1, 'reserved', 'ck163-salearm-ln');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, sale_state, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-000000163004', '00000000-0000-0000-0000-000000163006', '00000000-0000-0000-0000-000000163003', tap.buyer(), tap.seller(), 5000, 'initiated', 'ck163-salearm-ms');
INSERT INTO kernel.payment_native (payment_id, sale_id, amount_minor, currency)
VALUES (tap._g163('pFake'), '00000000-0000-0000-0000-000000163004', 5000, 'USD');
INSERT INTO kernel.dispute_native (dispute_id, stripe_dispute_ref, stripe_charge_ref, payment_id, amount_minor, currency, reason, status)
VALUES (gen_random_uuid(), 'dp_163_salearm', 'ch_163_salearm', tap._g163('pFake'), 5000, 'USD', 'fraudulent', 'lost');
SELECT tap._st163('d6', (SELECT dispute_id::text FROM kernel.dispute_native WHERE stripe_dispute_ref = 'dp_163_salearm'));
SELECT throws_like(
  format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,null,1,'USD','test','ck163-salearm')$$,
         tap._g163('orgO'), tap._g163('d6')),
  '%unlined_reversal_sale_arm_unsupported%', 'C14: a resale-rail (sale_id) origin is refused — no headroom model for it here');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION D — THE SHORTFALL HOLD (KC P1-1 O7 / KD P1-3). NOT an offset.
-- ============================================================================
SELECT tap._st163('oA8', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 25000, 0, 'oA8')::text);
SELECT tap._st163('SA8', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), tap._g163('evA'), 'sa8')::text);
SELECT tap._st163('poA8', tap._settlepo163(tap._g163('SA8'))::text);
SELECT is(tap._payoutstate163(tap._g163('poA8')), 'pending|none|-|25000', 'D1: poA8 mints pending, unheld');

-- 2026-09-03 (this reconciliation): SA9 opened against evA (not evA2) — oA9 is on sessA,
-- which belongs to evA; the ORIGINAL fixture scoped SA9 to evA2, an event with no session
-- of oA9's, so open_settlement's event-scoped credit set was empty and no payout ever
-- minted (poA9 = NULL, hence D4's "have: NULL"). A pre-existing fixture bug (never actually
-- run before this reconciliation). SA8 already consumed oA8 at its own close, so a second
-- evA settlement (SA9) legitimately captures only the NEW order oA9 (12000) — the D-section's
-- actual subject is "same VENUE, different settlement", not "different event".
SELECT tap._st163('oA9', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 12000, 0, 'oA9')::text);
SELECT tap._st163('SA9', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), tap._g163('evA'), 'sa9')::text);
SELECT tap._st163('poA9', tap._settlepo163(tap._g163('SA9'))::text);
UPDATE kernel.payout SET status = 'submitted' WHERE payout_id = tap._g163('poA9');

SELECT tap._st163('oA10', tap._ord163(tap._g163('sessA'), tap._g163('orgO'), 8000, 0, 'oA10')::text);
SELECT tap._st163('SA10a', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa10a')::text);
SELECT tap._pay163(tap._settlepo163(tap._g163('SA10a')), 'tr_163_sa10a', 'ck163-pay-sa10a');
SELECT tap._st163('d7', tap._disp163(tap._g163('oA10'), 8000, 'lost', 'd7')::text);
SELECT tap._st163('SA10b', tap._settle163(tap._g163('orgO'), tap._g163('venueA'), null, 'sa10b')::text);
SELECT is(tap._netminor163(tap._g163('SA10b')), -8000, 'D2: SA10b nets -8000 on d7 alone — the shortfall trigger');

SELECT is(tap._payoutstate163(tap._g163('poA8')), 'pending|held|shortfall_pending|25000',
  'D3: poA8 (PENDING, same venue) is HELD under the new reason — never netted, never paid');
SELECT is(tap._payoutstate163(tap._g163('poA9')), 'submitted|none|-|12000',
  'D4: poA9 (SUBMITTED) is left completely untouched — an executor may be mid-transfer');
SELECT ok(EXISTS (SELECT 1 FROM kernel.admin_audit a WHERE a.action='payout.shortfall_hold' AND a.subject_id = tap._g163('SA10b')
                    AND (a.after ->> 'submitted_unheld')::int = 1
                    AND a.after -> 'held_payout_ids' @> to_jsonb(tap._g163('poA8')::text)),
  'D5: the audit row names the settlement, the held payout, and counts the untouched submitted one');

-- 2026-09-03 (this reconciliation): routed through tap._retry163 (login+aal2 as tap.seller(),
-- the org_owner) — the ORIGINAL call hit kernel.retry_held_payout directly with no session
-- claims at all, so it failed at the AUTHORITY check (insufficient_privilege: authenticated
-- actor required) before ever reaching the maturity-code predicate this assertion is actually
-- about. A pre-existing fixture bug (never actually run before this reconciliation) — every
-- other retry_held_payout call in this file (line ~177, ~581) already goes through the wrapper.
SELECT throws_like(format($$SELECT tap._retry163(%L,%L,'ck163-retry-shortfall')$$, tap._g163('orgO'), tap._g163('SA8')),
  '%not_a_maturity_hold%', 'D6: retry_held_payout REFUSES — ''shortfall_pending'' is not a maturity code, only kernel.release_payout exits it');

SELECT is((tap._release163(tap._g163('poA8'), 'ck163-release') ->> 'status'), 'ok', 'D7: kernel.release_payout clears it');
SELECT is(tap._payoutstate163(tap._g163('poA8')), 'pending|none|-|25000', 'D8: …poA8 is back to pending|none, nothing paid, nothing netted');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION E — THE NINTH MATURITY PREDICATE, 'dispute_unabsorbed' (KB P0-1 O1).
-- ============================================================================
SELECT tap._st163('oB9', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 7000, 0, 'oB9')::text);
SELECT tap._st163('d10', tap._disp163(tap._g163('oB9'), 7000, 'needs_response', 'd10')::text);
SELECT tap._st163('SB9', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), tap._g163('evB'), 'sb9')::text);
SELECT tap._st163('poB9', tap._settlepo163(tap._g163('SB9'))::text);
SELECT is(tap._payoutstate163(tap._g163('poB9')), 'pending|held|dispute_open|7000',
  'E1: fixture control — an OPEN dispute holds the payout under the existing dispute_open code');

SELECT tap._mark163('dp_163_d10', 'lost', 'ck163-mark1');
SELECT is(
  (tap._retry163(tap._g163('orgO'), tap._g163('SB9'), 'ck163-retry1') ->> 'hold_reason_code'),
  'dispute_unabsorbed',
  'E2: once the dispute is LOST, retry_held_payout re-evaluates and the hold reason is REFRESHED to dispute_unabsorbed — still held, not cleared');
SELECT is(tap._payoutstate163(tap._g163('poB9')), 'pending|held|dispute_unabsorbed|7000', 'E3: …the row itself carries the new reason');

SELECT tap._st163('oB10', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 7000, 0, 'oB10')::text);
SELECT tap._st163('SB10', tap._settle163(tap._g163('orgO'), tap._g163('venueB'), null, 'sb10')::text);
SELECT is(tap._netminor163(tap._g163('SB10')), 0, 'E4: SB10 nets 0 — d10''s chargeback finally lands, offset by oB10''s own face');
SELECT ok(tap._haslined163(tap._g163('SB10'), 'chargeback', tap._g163('d10')), 'E5: …the chargeback line for d10 now exists');

SELECT is(
  (tap._retry163(tap._g163('orgO'), tap._g163('SB9'), 'ck163-retry2') ->> 'status'),
  'submitted',
  'E6: NOW retry_held_payout clears the hold and the delegated advance succeeds — SB9''s payout reaches submitted');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION F — DISPUTE-WRITER HYGIENE (KB P1-1/P2-2).
-- ============================================================================
SELECT throws_like(
  $$SELECT kernel.record_dispute_native('dp_163_buynow','ch_163_buynow','pi_fixture_a',100,'USD','fraudulent','needs_response',null,'ck163-buynow')$$,
  '%not_native_rail%', 'F1: record_dispute_native refuses a legacy buy_now payment with no native link (KB A2 closed)');

SELECT tap._st163('oB11', tap._ord163(tap._g163('sessB'), tap._g163('orgO'), 5000, 0, 'oB11')::text);
SELECT is(
  (kernel.record_dispute_native('dp_163_hygiene','ch_163_hygiene',
     (SELECT stripe_payment_intent_id FROM public.payments WHERE id = (SELECT payment_id FROM kernel.payment_native WHERE order_id = tap._g163('oB11'))),
     5000,'USD','fraudulent','needs_response',null,'ck163-hygiene-ok') ->> 'status'),
  'ok', 'F2: …but a real native-primary payment is still recordable');
SELECT throws_like(
  $$SELECT kernel.mark_dispute_state('dp_163_hygiene','lost',null)$$,
  '%command_key%', 'F3: mark_dispute_state refuses a NULL command_key — bound by record''s own regex (KB P2-2)');
SELECT throws_like(
  format($$SELECT kernel.mark_dispute_state('dp_163_hygiene','lost',%L)$$, repeat('x', 65)),
  '%command_key%', 'F4: …and refuses a 65-char key');
SELECT is((tap._mark163('dp_163_hygiene', 'lost', 'ck163-hygiene-mark') ->> 'status'), 'ok', 'F5: …a well-shaped key is accepted');

ROLLBACK TO SAVEPOINT sp_base;

-- ============================================================================
-- SECTION G — CENSUS / LABEL FACTS (no fixture needed).
-- ============================================================================
SELECT is(array_length(kernel.settlement_maturity_hold_codes(), 1), 9,
  'G1: the maturity vocabulary is now NINE codes (161/A9 was eight — orchestrator delta, see report)');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) LIKE '%''' || c || '''%')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
                  unnest(kernel.settlement_maturity_hold_codes()) c
            WHERE n.nspname='kernel' AND p.proname='settlement_payout_maturity'),
  'G2: every one of the nine codes is a literal kernel.settlement_payout_maturity can actually emit (161/A9a re-proved)');
SELECT ok(NOT ('shortfall_pending' = ANY (kernel.settlement_maturity_hold_codes())),
  'G3: ''shortfall_pending'' is deliberately NOT a maturity code — kernel.release_payout is its only exit');

-- 160/F10 was `settlement_royalty_lines'' body !~ ''organization_obligation''`.
-- That is now FALSE BY DESIGN (the unlined fence reads the table); replaced
-- here by the assertion that matters: it reads it ONLY for the
-- unlined_reversal origin, never to gate anything else.
SELECT ok((SELECT pg_get_functiondef(p.oid) ~ 'organization_obligation' AND pg_get_functiondef(p.oid) ~ 'unlined_reversal'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'G4: 160/F10 successor — the chargeback arm reads kernel.organization_obligation ONLY through the origin_kind=''unlined_reversal'' fence');
SELECT ok((SELECT pg_get_functiondef(p.oid) ~ 'e\.venue_id = s\.venue_id'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'G5: the ring-fence predicate is textually present in the chargeback arm');

-- Grants discipline: CREATE OR REPLACE preserved every ACL — none of these
-- nine functions changed who may call them.
SELECT ok(has_function_privilege('service_role','kernel.settlement_payout_maturity(uuid)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.settlement_payout_maturity(uuid)','EXECUTE'),
  'G6: settlement_payout_maturity — still service_role only (093 ACL untouched)');
SELECT ok(has_function_privilege('service_role','kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text)','EXECUTE'),
  'G7: record_dispute_native — still service_role only (088 ACL untouched)');
SELECT ok(NOT has_function_privilege('service_role','kernel.organization_obligation_guard()','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.organization_obligation_guard()','EXECUTE'),
  'G8: organization_obligation_guard — still trigger-only, nobody may call it directly (094 ACL untouched)');

-- The new column carries no privilege of its own — the table stays deny-all.
SELECT ok(NOT has_column_privilege('service_role','kernel.organization_obligation','venue_id','SELECT')
      AND NOT has_column_privilege('authenticated','kernel.organization_obligation','venue_id','SELECT'),
  'G9: kernel.organization_obligation.venue_id — no role holds a privilege on it (table-level REVOKE ALL covers it)');

-- The one column 097 DOES add, shaped correctly. (A whole-stack relation
-- census belongs to tests/141-157, which this file does not touch — see the
-- KM2 report for the exact delta those files need once 096's own two new
-- tables are accounted for.)
SELECT col_type_is('kernel'::name,'organization_obligation'::name,'venue_id'::name,'uuid',
  'G10: kernel.organization_obligation.venue_id is uuid');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint c
                    WHERE c.conrelid = 'kernel.organization_obligation'::regclass AND c.contype = 'f'
                      AND c.confrelid = 'catalog.venue'::regclass
                      AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
                                              WHERE attrelid = 'kernel.organization_obligation'::regclass AND attname = 'venue_id')]),
  'G11: …with a foreign key to catalog.venue(venue_id) — the write is always to a real venue or NULL, never a dangling id');

SELECT * FROM finish();
ROLLBACK;
