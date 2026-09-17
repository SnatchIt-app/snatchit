-- ============================================================================
-- 162_payout_reversal_and_obligation_recovery.sql — package 096, implementer M1.
--
-- SUBJECT: every property DESIGN_096.md §1.8 requires re-executed as pgTAP
--   assertions against the ACTUAL objects 096 shipped (not the design prose):
--     kernel.payout_reversal (+ guard, + payout_reversed_minor)
--     payout_stripe_transfer_ref_uq (the missing uniqueness invariant, KE F-6)
--     kernel.record_payout_reversal        — the one writer of the reversal fact
--     kernel.organization_obligation_recovery (+ guard, + settle trigger)
--     kernel.obligation_outstanding_minor / kernel.org_outstanding_obligation_minor (re-created)
--     kernel.record_obligation_recovery    — the human declares a receipt
--     kernel.resolve_organization_obligation (re-created — GRANT to authenticated, honesty fix)
--     kernel.claim_failed_payouts_for_reconcile / kernel.reconcile_payout_transfer
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK, the 161 idiom. Fixtures
--   reuse the org1/venue1/event1/sessOld shape from 161 (its own tap.memo_160
--   and tap._aal2 etc. do not persist outside its own transaction — this file
--   is self-contained and defines its own 162-suffixed helpers).
--
-- Sources read: supabase/migrations/096_payout_reversal_and_obligation_
--   recovery.sql (in full — every predicate order and error string below is
--   quoted from the shipped bodies, not the design memo); docs/phase2/_impl/
--   KE_payout_reversal.md §4.4 (the conservation case table); KD_obligation_
--   recovery.md §3 P1-4 (the table of what a partial recovery must be able to
--   say); supabase/tests/161_payout_state_machine.sql (fixture idiom);
--   supabase/tests/160_organization_obligation.sql §F (the grep-the-bodies
--   idiom for "nothing here pays a promoter").
-- ============================================================================
BEGIN;
SELECT plan(86);

SELECT tap.seed_core();

CREATE TABLE tap.memo_162 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st162(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_162 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fe162(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_162 WHERE k=$1 $m$;

CREATE FUNCTION tap._aal2_162() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._aal1_162() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal1"}'::jsonb)::text, true); end $f$;

CREATE FUNCTION tap._po162(p_settlement uuid) RETURNS kernel.payout
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT p FROM kernel.payout p WHERE p.cause='settlement' AND p.cause_ref = p_settlement ORDER BY p.created_at LIMIT 1 $m$;
CREATE FUNCTION tap._ob162(p_id uuid) RETURNS kernel.organization_obligation
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT o FROM kernel.organization_obligation o WHERE o.obligation_id = p_id $m$;
CREATE FUNCTION tap._audit162(p_subject uuid, p_action text, p_reason text DEFAULT NULL) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = p_subject AND a.action = p_action
     AND (p_reason IS NULL OR a.reason_code = p_reason) $m$;

CREATE FUNCTION tap._sess162(p_event uuid, p_label text, p_end timestamptz) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.event_session (event_id, session_label, starts_at, ends_at, status)
    VALUES (p_event, p_label, p_end - interval '3 hours', p_end, 'completed') RETURNING session_id $m$;
CREATE FUNCTION tap._cov162(p_org uuid, p_session uuid, p_total int, p_tag text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
DECLARE v_pay uuid; v_order uuid;
BEGIN
  INSERT INTO public.payments (buyer_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
  VALUES (tap.buyer(), p_total, 0, p_total, 'succeeded', 'native_primary', p_tag) RETURNING id INTO v_pay;
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), p_session, p_org, 'pending', 'web', p_total, p_tag || '-ord') RETURNING order_id INTO v_order;
  INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor, currency)
  VALUES (v_pay, v_order, p_total, 'USD');
  PERFORM tap._st162(p_tag || '-pay', v_pay::text);
  RETURN v_order;
END $m$;
CREATE FUNCTION tap._settle162(p_org uuid, p_venue uuid, p_lines jsonb, p_key text) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $m$
DECLARE v_s uuid; v_l jsonb;
BEGIN
  PERFORM tap.login(tap.seller());
  v_s := (venue.open_settlement(p_org, p_venue, NULL, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid;
  PERFORM tap.logout();
  FOR v_l IN SELECT jsonb_array_elements(p_lines) LOOP
    INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor)
    VALUES (v_s, v_l ->> 'cause', (v_l ->> 'ref')::uuid, (v_l ->> 'amt')::integer);
  END LOOP;
  PERFORM tap.login(tap.admin_user());
  PERFORM kernel.close_settlement(v_s, p_key || '-c');
  PERFORM tap.logout();
  RETURN v_s;
END $m$;
CREATE FUNCTION tap._request162(p_org uuid, p_s uuid, p_key text) RETURNS text
LANGUAGE plpgsql AS $m$
DECLARE v text;
BEGIN
  PERFORM tap.login(tap.other_user());
  PERFORM tap._aal2_162();
  v := (kernel.request_org_payout(p_org, p_s, p_key) ->> 'status');
  PERFORM tap.logout();
  RETURN v;
END $m$;

-- ============================================================================
-- FIXTURE — org1/venue1/event1/sessOld exactly as 161, plus org2 (a SECOND
-- organization, needed only for the cross-org reversal_org_mismatch proof).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st162('org1', (kernel.create_organization('CK96 Co','CK96 Co','ck96-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fe162('org1')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._st162('venue1', (catalog.create_venue(tap._fe162('org1')::uuid,'CK96 Hall','wynwood',NULL,'ck96-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fe162('venue1')::uuid,'approved','miami_gate','ck96-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._st162('event1', (catalog.create_event(tap._fe162('venue1')::uuid,'CK96 Night',
  jsonb_build_object('starts_at',(now()-interval '40 days')::text,'ends_at',(now()-interval '40 days' + interval '4 hours')::text),'ck96-e1') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st162('sessOld', tap._sess162(tap._fe162('event1')::uuid, 'old', now() - interval '40 days')::text);

INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._fe162('org1')::uuid, tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days'
 WHERE org_id = tap._fe162('org1')::uuid AND identity_id = tap.seller();
UPDATE kernel.organization
   SET stripe_connect_account_ref = 'acct_CK96', connect_transfers_active = true
 WHERE org_id = tap._fe162('org1')::uuid;

INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.settlement_maturity_interval', coalesce(max(version),0)+1, '"7 days"'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.settlement_maturity_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '100000000'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';

-- a second organization, for the cross-org reversal test only.
SELECT tap.login(tap.seller());
SELECT tap._st162('org2', (kernel.create_organization('CK96 Co2','CK96 Co2','ck96-o2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fe162('org2')::uuid;
-- 2026-09-03 (package 097's fence): org2 needs its own venue/event/session now, so L8's
-- fixture (below) can back O2's origin with a real post-payout dispute — the fence requires
-- one for EVERY unlined_reversal origin, not only org1's.
SELECT tap.login(tap.seller());
SELECT tap._st162('venue2', (catalog.create_venue(tap._fe162('org2')::uuid,'CK96 Hall Two','brickell',NULL,'ck96-v2') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fe162('venue2')::uuid,'approved','miami_gate','ck96-a2');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._st162('event2', (catalog.create_event(tap._fe162('venue2')::uuid,'CK96 Night Two',
  jsonb_build_object('starts_at',(now()-interval '40 days')::text,'ends_at',(now()-interval '40 days' + interval '4 hours')::text),'ck96-e2') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st162('sessOld2', tap._sess162(tap._fe162('event2')::uuid, 'old2', now() - interval '40 days')::text);
-- org2 needs the same org_finance grant org1 gave tap.other_user() (line ~120 above) so
-- tap._request162 (which calls kernel.request_org_payout as tap.other_user()) can authorize
-- org2's payout too.
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._fe162('org2')::uuid, tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days'
 WHERE org_id = tap._fe162('org2')::uuid AND identity_id = tap.seller();
UPDATE kernel.organization
   SET stripe_connect_account_ref = 'acct_CK96TWO', connect_transfers_active = true
 WHERE org_id = tap._fe162('org2')::uuid;

-- ============================================================================
-- SECTION A — SHAPE: the 9 new functions, the 2 new tables, their grants and
-- RLS posture. If any of these flip, some principal gained an unreviewed door.
-- ============================================================================
SELECT has_table('kernel'::name, 'payout_reversal'::name, 'A1: kernel.payout_reversal exists');
SELECT has_table('kernel'::name, 'organization_obligation_recovery'::name, 'A2: kernel.organization_obligation_recovery exists');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'kernel.payout_reversal'::regclass)
      AND (SELECT count(*)::int FROM pg_policy WHERE polrelid = 'kernel.payout_reversal'::regclass) = 0
      AND NOT has_table_privilege('authenticated','kernel.payout_reversal','SELECT')
      AND NOT has_table_privilege('service_role','kernel.payout_reversal','SELECT'),
  'A3: kernel.payout_reversal is RLS-on, zero-policy, deny-all to every role — reachable only through a definer verb');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'kernel.organization_obligation_recovery'::regclass)
      AND (SELECT count(*)::int FROM pg_policy WHERE polrelid = 'kernel.organization_obligation_recovery'::regclass) = 0
      AND NOT has_table_privilege('authenticated','kernel.organization_obligation_recovery','SELECT')
      AND NOT has_table_privilege('service_role','kernel.organization_obligation_recovery','SELECT'),
  'A4: kernel.organization_obligation_recovery is RLS-on, zero-policy, deny-all — same posture');

SELECT ok(has_function_privilege('service_role','kernel.record_payout_reversal(uuid,text,text,integer,jsonb,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.record_payout_reversal(uuid,text,text,integer,jsonb,text)','EXECUTE'),
  'A5: kernel.record_payout_reversal is a MACHINE observation — service_role only, never a client');
SELECT ok(has_function_privilege('service_role','kernel.claim_failed_payouts_for_reconcile(integer,integer)','EXECUTE')
      AND has_function_privilege('service_role','kernel.reconcile_payout_transfer(uuid,text,jsonb,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.claim_failed_payouts_for_reconcile(integer,integer)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.reconcile_payout_transfer(uuid,text,jsonb,text)','EXECUTE'),
  'A6: the reconcile claim + writer pair is service_role only — no human path onto the failed→paid edge');
SELECT ok(has_function_privilege('authenticated','kernel.record_obligation_recovery(uuid,integer,text,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.record_obligation_recovery(uuid,integer,text,text,text,text)','EXECUTE'),
  'A7: kernel.record_obligation_recovery — authenticated ONLY, EXPLICITLY revoked from service_role (095 E-2 hard edge: a machine cannot declare a debt recovered)');
SELECT ok(has_function_privilege('authenticated','kernel.resolve_organization_obligation(uuid,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.resolve_organization_obligation(uuid,text,text,text)','EXECUTE'),
  'A8: kernel.resolve_organization_obligation — KD P1-1 fixed by grant: now authenticated, and the dead service_role grant is revoked');
SELECT ok(NOT has_function_privilege('authenticated','kernel.payout_reversal_guard()','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.payout_reversal_guard()','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.organization_obligation_recovery_guard()','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.organization_obligation_recovery_guard()','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.organization_obligation_recovery_settle()','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.organization_obligation_recovery_settle()','EXECUTE'),
  'A9: the three trigger functions are callable by NOBODY — trigger-only, exactly the 076 discipline');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid='kernel.payout_reversal'::regclass AND t.tgname='tg_payout_reversal_guard' AND NOT t.tgisinternal)
      AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid='kernel.organization_obligation_recovery'::regclass AND t.tgname='tg_organization_obligation_recovery_guard' AND NOT t.tgisinternal)
      AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid='kernel.organization_obligation_recovery'::regclass AND t.tgname='tg_organization_obligation_recovery_settle' AND NOT t.tgisinternal),
  'A10: all three guard/settle triggers are actually ATTACHED');
SELECT is((SELECT pg_get_indexdef(indexrelid) FROM pg_index WHERE indexrelid = 'kernel.payout_stripe_transfer_ref_uq'::regclass),
  'CREATE UNIQUE INDEX payout_stripe_transfer_ref_uq ON kernel.payout USING btree (stripe_transfer_ref) WHERE (stripe_transfer_ref IS NOT NULL)',
  'A11: KE F-6 closed — one Stripe transfer, one payout, as a partial unique index (safe on a dark rail, binds every writer)');

-- ============================================================================
-- FIXTURE P1 — paid 10000, then TWO PARTIAL reversals (4000, then 6000) that
-- together prove: partial stays paid + projection, full via Σ = amount moves
-- through the EXISTING edge, two-partials-summing, and trr_ replay.
-- ============================================================================
SELECT tap._st162('ordA', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 10000, 'pi_162_a')::text);
SELECT tap._st162('s1', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordA'),'amt',10000)), 'ck96-s1')::text);
SELECT tap._st162('p1', (tap._po162(tap._fe162('s1')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s1')::uuid, 'ck96-r1');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p1')::uuid, 'paid', 'tr_162a', NULL, 'ck96-m1');

SELECT is((kernel.record_payout_reversal(tap._fe162('p1')::uuid,'tr_162a','trr_162a1',4000,'{}'::jsonb,'ck96-rv1') ->> 'status'), 'ok',
  'B1: record_payout_reversal on a paid, under-amount reversal returns ok');
SELECT is((tap._po162(tap._fe162('s1')::uuid)).status, 'paid',
  'B2: PARTIAL (4000 of 10000) — the payout STAYS paid, no second door onto status');
SELECT is(kernel.payout_reversed_minor(tap._fe162('p1')::uuid), 4000::bigint,
  'B3: the projection kernel.payout_reversed_minor reads back exactly the Σ recorded — "how much came back" is derived, never a column');
SELECT ok((tap._po162(tap._fe162('s1')::uuid)).amount_minor = 10000
      AND (tap._po162(tap._fe162('s1')::uuid)).hold_state = 'none',
  'B4: the obligation column (amount_minor) is untouched and the row is not held — a paid row cannot be held (085:790)');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fe162('s1')::uuid), 'paid',
  'B5: the settlement header stays paid — 095 E-5 forward-only, the economic consequence lives on the obligation side, not the header');

SELECT is((kernel.record_payout_reversal(tap._fe162('p1')::uuid,'tr_162a','trr_162a2',6000,'{}'::jsonb,'ck96-rv2') ->> 'payout_status'), 'reversed',
  'C1: the SECOND partial (6000) brings Σ to 10000 = amount_minor — the row moves through kernel.mark_payout_transfer_state to reversed, THE EXISTING EDGE');
SELECT is((tap._po162(tap._fe162('s1')::uuid)).status, 'reversed',
  'C2: … the payout row itself now reads reversed');
SELECT is(kernel.payout_reversed_minor(tap._fe162('p1')::uuid), 10000::bigint,
  'C3: TWO PARTIALS SUMMING — 4000 + 6000 = the full 10000, exactly as the running-sum trigger requires');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fe162('s1')::uuid), 'paid',
  'C4: … and the settlement header is STILL paid — a full reversal never rewinds it (095 E-5)');

SELECT is((kernel.record_payout_reversal(tap._fe162('p1')::uuid,'tr_162a','trr_162a2',6000,'{}'::jsonb,'ck96-rv2-replay') ->> 'status'), 'noop_replay',
  'D1: TRR_ REPLAY — the same trr_ arriving again (a retried webhook) is a no-op, not a second fact');
SELECT is((SELECT count(*)::int FROM kernel.payout_reversal WHERE payout_id = tap._fe162('p1')::uuid), 2,
  'D2: … and exactly two rows exist — the replay wrote nothing');

-- over-sum refused: any further reversal, even 1, now exceeds the payout's own amount.
SELECT throws_like(format($$SELECT kernel.record_payout_reversal(%L,'tr_162a','trr_162a3',1,'{}'::jsonb,'ck96-rv3')$$, tap._fe162('p1')),
  '%reversal_exceeds_transfer%',
  'E1: OVER-SUM REFUSED — a reversal that would push Σ past amount_minor is refused by the trigger''s running-sum guard, even after the row is already reversed');

-- wrong-payout trr_ conflict: a DIFFERENT paid payout tries to claim trr_162a2.
SELECT tap._st162('ordCF', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 7000, 'pi_162_cf')::text);
SELECT tap._st162('sCF', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordCF'),'amt',7000)), 'ck96-scf')::text);
SELECT tap._st162('pCF', (tap._po162(tap._fe162('sCF')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('sCF')::uuid, 'ck96-rcf');
SELECT kernel.mark_payout_transfer_state(tap._fe162('pCF')::uuid, 'paid', 'tr_162cf', NULL, 'ck96-mcf');
SELECT throws_like(format($$SELECT kernel.record_payout_reversal(%L,'tr_162cf','trr_162a2',1000,'{}'::jsonb,'ck96-rvcf')$$, tap._fe162('pCF')),
  '%conflict_locked: reversal_ref_bound_elsewhere%',
  'F1: WRONG-PAYOUT trr_ — trr_162a2 is already bound to p1; a second payout citing the same trr_ is refused, never re-attached');

-- ============================================================================
-- SECTION G — THE SUBMITTED RACE (KE §4.3): the transfer exists, the ref is
-- not yet stored on the row. The fact is written, then the row is de-authorized
-- through kernel.hold_payout_transfer_reversed (095 E-4).
-- ============================================================================
SELECT tap._st162('ordB', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 9000, 'pi_162_b')::text);
SELECT tap._st162('s2', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordB'),'amt',9000)), 'ck96-s2')::text);
SELECT tap._st162('p2', (tap._po162(tap._fe162('s2')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s2')::uuid, 'ck96-r2');
SELECT is((tap._po162(tap._fe162('s2')::uuid)).status, 'submitted',
  'G0: FIXTURE CONTROL — p2 is submitted, ref not yet stored (the callback has not run)');
SELECT is((kernel.record_payout_reversal(tap._fe162('p2')::uuid,'tr_162b','trr_162b1',9000,'{}'::jsonb,'ck96-rvb1') ->> 'status'), 'held',
  'G1: SUBMITTED-RACE — the fact is written (the trigger permits ''submitted''), and the writer hands the row to hold_payout_transfer_reversed, returning ''held''');
SELECT ok((tap._po162(tap._fe162('s2')::uuid)).status = 'pending'
      AND (tap._po162(tap._fe162('s2')::uuid)).hold_state = 'held'
      AND (tap._po162(tap._fe162('s2')::uuid)).hold_reason_code = 'transfer_reversed'
      AND (tap._po162(tap._fe162('s2')::uuid)).stripe_transfer_ref IS NULL,
  'G2: … the row de-authorizes to pending+held/transfer_reversed and the stored ref STAYS NULL (085:133 — mark_payout_transfer_state alone writes it)');
SELECT is((SELECT count(*)::int FROM kernel.payout_reversal WHERE payout_id = tap._fe162('p2')::uuid AND stripe_reversal_ref = 'trr_162b1'), 1,
  'G3: … but the fact itself IS recorded — a keyed record now exists for the executor''s later adopt/hold decision, closing KE F-12');

-- ============================================================================
-- SECTION H — 'FAILED' REFUSES (the reconcile pass owns it, not this verb).
-- ============================================================================
SELECT tap._st162('ordC', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 4500, 'pi_162_c')::text);
SELECT tap._st162('s3', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordC'),'amt',4500)), 'ck96-s3')::text);
SELECT tap._st162('p3', (tap._po162(tap._fe162('s3')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s3')::uuid, 'ck96-r3');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p3')::uuid, 'failed', 'tr_162c', 'transfer_failed', 'ck96-f3');
SELECT throws_like(format($$SELECT kernel.record_payout_reversal(%L,'tr_162c','trr_162c1',4500,'{}'::jsonb,'ck96-rvc1')$$, tap._fe162('p3')),
  '%payout_failed_reconcile_required%',
  'H1: FAILED REFUSES — record_payout_reversal will not touch a failed row; the reconcile pass (R-7) owns it, and writing here would race the failed→paid edge');
SELECT is((tap._po162(tap._fe162('s3')::uuid)).status, 'failed',
  'H2: … and the refusal changed nothing — still failed, still carrying tr_162c');

-- ============================================================================
-- SECTION I — ONE TRANSFER, ONE PAYOUT (the new unique index, live).
-- ============================================================================
SELECT tap._st162('ordD', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 1200, 'pi_162_d')::text);
SELECT tap._st162('s4', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordD'),'amt',1200)), 'ck96-s4')::text);
SELECT tap._st162('p4', (tap._po162(tap._fe162('s4')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s4')::uuid, 'ck96-r4');
SELECT throws_like(format($$SELECT kernel.mark_payout_transfer_state(%L,'paid','tr_162a',NULL,'ck96-m4')$$, tap._fe162('p4')),
  '%payout_stripe_transfer_ref_uq%',
  'I1: UNIQUE tr_ INDEX — a second payout cannot be marked paid with a tr_ already bound to p1 (tr_162a); one Stripe transfer, one payout, enforced live');

-- ============================================================================
-- SECTION J — RECONCILE: the ref-bearing failed payout (KE §4.2).
-- ============================================================================
-- J-clean: a plain 404-free, un-reversed transfer. failed → paid, then
-- venue.on_payout_settled (the fifth seam) carries the header to paid too.
SELECT tap._st162('ordE', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 2200, 'pi_162_e')::text);
SELECT tap._st162('s5', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordE'),'amt',2200)), 'ck96-s5')::text);
SELECT tap._st162('p5', (tap._po162(tap._fe162('s5')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s5')::uuid, 'ck96-r5');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p5')::uuid, 'failed', 'tr_162e', 'transfer_failed', 'ck96-f5');

SELECT is((SELECT count(*)::int FROM jsonb_array_elements(kernel.claim_failed_payouts_for_reconcile(50,900) -> 'payouts') e
            WHERE e ->> 'payout_id' = tap._fe162('p5')), 1,
  'J1: the leased claim finds the ref-bearing failed payout — the population 095 E-2 refuses');

SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p5')::uuid, 'tr_162e',
    jsonb_build_object('found',true,'id','tr_162e','amount',2200,'currency','usd','destination','acct_CK96',
                        'transfer_group','payout_'||tap._fe162('p5'),'reversed',false,'amount_reversed',0,
                        'reversals','[]'::jsonb,'group_count',1),
    'ck96-rc1') ->> 'status'), 'ok',
  'J2: CLEAN — the single-writer edge failed → paid fires from Stripe-observed facts');
SELECT is((tap._po162(tap._fe162('s5')::uuid)).status, 'paid',
  'J3: … the payout row reads paid');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fe162('s5')::uuid), 'paid',
  'J4: … and venue.on_payout_settled (the fifth seam, fired inline) carried the HEADER to paid too — reconcile is not a partial fix');

-- J-full-reversed: failed → paid → reversed in one call, via reversals[].
SELECT tap._st162('ordF', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 8000, 'pi_162_f')::text);
SELECT tap._st162('s6', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordF'),'amt',8000)), 'ck96-s6')::text);
SELECT tap._st162('p6', (tap._po162(tap._fe162('s6')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s6')::uuid, 'ck96-r6');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p6')::uuid, 'failed', 'tr_162f', 'transfer_failed', 'ck96-f6');
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p6')::uuid, 'tr_162f',
    jsonb_build_object('found',true,'id','tr_162f','amount',8000,'currency','usd','destination','acct_CK96',
                        'transfer_group','payout_'||tap._fe162('p6'),'reversed',true,'amount_reversed',8000,
                        'reversals',jsonb_build_array(jsonb_build_object('id','trr_162f1','amount',8000)),'group_count',1),
    'ck96-rc2') ->> 'payout_status'), 'reversed',
  'J5: FULL-REVERSED — failed → paid → reversed in the one call: amount_reversed = amount drives the inner record_payout_reversal to Σ = amount_minor');
SELECT is((tap._po162(tap._fe162('s6')::uuid)).status, 'reversed',
  'J6: … the payout row confirms reversed');
SELECT is(kernel.payout_reversed_minor(tap._fe162('p6')::uuid), 8000::bigint,
  'J7: … and the reversal fact (trr_162f1) is recorded with source ''reconcile''');
SELECT is((SELECT source FROM kernel.payout_reversal WHERE stripe_reversal_ref='trr_162f1'), 'reconcile',
  'J7a: … tagged by its true observer, not stripe_webhook');

-- J-partial: 0 < amount_reversed < amount — failed → paid, stays paid, projection.
SELECT tap._st162('ordG', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 5000, 'pi_162_g')::text);
SELECT tap._st162('s7', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordG'),'amt',5000)), 'ck96-s7')::text);
SELECT tap._st162('p7', (tap._po162(tap._fe162('s7')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s7')::uuid, 'ck96-r7');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p7')::uuid, 'failed', 'tr_162g', 'transfer_failed', 'ck96-f7');
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p7')::uuid, 'tr_162g',
    jsonb_build_object('found',true,'id','tr_162g','amount',5000,'currency','usd','destination','acct_CK96',
                        'transfer_group','payout_'||tap._fe162('p7'),'reversed',false,'amount_reversed',2000,
                        'reversals',jsonb_build_array(jsonb_build_object('id','trr_162g1','amount',2000)),'group_count',1),
    'ck96-rc3') ->> 'payout_status'), 'paid',
  'J8: PARTIAL — failed → paid, and 2000 of 5000 reversed leaves it paid, not reversed');
SELECT is(kernel.payout_reversed_minor(tap._fe162('p7')::uuid), 2000::bigint,
  'J9: … the projection reads back the partial exactly');

-- J-404: found=false. Stays failed.
SELECT tap._st162('ordH', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 3300, 'pi_162_h')::text);
SELECT tap._st162('s8', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordH'),'amt',3300)), 'ck96-s8')::text);
SELECT tap._st162('p8', (tap._po162(tap._fe162('s8')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s8')::uuid, 'ck96-r8');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p8')::uuid, 'failed', 'tr_162h', 'transfer_failed', 'ck96-f8');
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p8')::uuid, 'tr_162h', jsonb_build_object('found',false), 'ck96-rc4') ->> 'refusal_code'),
  'transfer_unresolvable',
  'J10: 404 — Stripe has never heard of the ref. Stays failed, refused, audited; a terminal row cannot be held so the audit+page IS the operator hold');
SELECT is((tap._po162(tap._fe162('s8')::uuid)).status, 'failed',
  'J11: … status unchanged');

-- ref mismatch NEVER ADOPTS the caller's pair (still using p8's stored tr_162h).
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p8')::uuid, 'tr_wrongref',
    jsonb_build_object('found',true,'id','tr_wrongref','amount',3300), 'ck96-rc5') ->> 'refusal_code'), 'ref_mismatch',
  'J12: REF MISMATCH — the caller''s ref differs from the STORED one; refused before any observation is even trusted');
SELECT is((tap._po162(tap._fe162('s8')::uuid)).stripe_transfer_ref, 'tr_162h',
  'J13: … and the stored ref is UNCHANGED — the verb never adopts the caller''s pair, exactly the KE 4.2(a) rule');

-- amount / destination / ambiguous mismatches — each on its own fresh failed row
-- (the refusal precedence is causal; each case needs every EARLIER predicate clean).
SELECT tap._st162('ordI', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 6600, 'pi_162_i')::text);
SELECT tap._st162('s9', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordI'),'amt',6600)), 'ck96-s9')::text);
SELECT tap._st162('p9', (tap._po162(tap._fe162('s9')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s9')::uuid, 'ck96-r9');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p9')::uuid, 'failed', 'tr_162i', 'transfer_failed', 'ck96-f9');
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p9')::uuid, 'tr_162i',
    jsonb_build_object('found',true,'id','tr_162i','amount',6599,'currency','usd','destination','acct_CK96',
                        'transfer_group','payout_'||tap._fe162('p9'),'amount_reversed',0,'reversals','[]'::jsonb,'group_count',1),
    'ck96-rc6') ->> 'refusal_code'), 'amount_ledger_mismatch',
  'J14: AMOUNT MISMATCH — observed 6599 vs the ledger''s 6600, stays failed');
SELECT is((tap._po162(tap._fe162('s9')::uuid)).status, 'failed', 'J14a: … unchanged');

SELECT tap._st162('ordJ', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 4400, 'pi_162_j')::text);
SELECT tap._st162('s10', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordJ'),'amt',4400)), 'ck96-s10')::text);
SELECT tap._st162('p10', (tap._po162(tap._fe162('s10')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s10')::uuid, 'ck96-r10');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p10')::uuid, 'failed', 'tr_162j', 'transfer_failed', 'ck96-f10');
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p10')::uuid, 'tr_162j',
    jsonb_build_object('found',true,'id','tr_162j','amount',4400,'currency','usd','destination','acct_WRONG',
                        'transfer_group','payout_'||tap._fe162('p10'),'amount_reversed',0,'reversals','[]'::jsonb,'group_count',1),
    'ck96-rc7') ->> 'refusal_code'), 'destination_mismatch',
  'J15: DESTINATION MISMATCH — observed acct_WRONG vs the pinned acct_CK96, stays failed');

SELECT tap._st162('ordK', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 7700, 'pi_162_k')::text);
SELECT tap._st162('s11', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordK'),'amt',7700)), 'ck96-s11')::text);
SELECT tap._st162('p11', (tap._po162(tap._fe162('s11')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('s11')::uuid, 'ck96-r11');
SELECT kernel.mark_payout_transfer_state(tap._fe162('p11')::uuid, 'failed', 'tr_162k', 'transfer_failed', 'ck96-f11');
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p11')::uuid, 'tr_162k',
    jsonb_build_object('found',true,'id','tr_162k','amount',7700,'currency','usd','destination','acct_CK96',
                        'transfer_group','payout_'||tap._fe162('p11'),'amount_reversed',0,'reversals','[]'::jsonb,'group_count',2),
    'ck96-rc8') ->> 'refusal_code'), 'reconcile_ambiguous',
  'J16: AMBIGUOUS — two transfers share the group; refused rather than guessed, stays failed');
SELECT is((tap._po162(tap._fe162('s11')::uuid)).status, 'failed', 'J16a: … unchanged');

-- replay convergence: a clean reconcile of an already-paid ref is a no-op.
SELECT is((kernel.reconcile_payout_transfer(tap._fe162('p5')::uuid, 'tr_162e',
    jsonb_build_object('found',true,'id','tr_162e','amount',2200), 'ck96-rc1-replay') ->> 'status'), 'noop_replay',
  'J17: REPLAY CONVERGES — reconciling an already-paid ref with the same ref again is a no-op, not a second edge');

-- ============================================================================
-- SECTION K — OBLIGATION RECOVERY: kernel.organization_obligation_recovery.
-- O1: org1, unlined_reversal, 6000. Recovered in two receipts (2000 manual,
-- then 4000 via the p1 reversal facts trr_162a1) to prove partial → complete.
--
-- 2026-09-03 (package 097's fence, KM2 §2.3): record_organization_obligation's
-- unlined_reversal branch now resolves origin_ref to a REAL lost/charge_refunded
-- dispute or succeeded refund (not a bare UUID) AND requires POST-PAYOUT PROOF (a
-- settlement_line cause='primary_sale' whose settlement's payout is paid/reversed).
-- ordA/s1/p1 (Fixture P1 above) is exactly that: p1 is ALREADY 'paid' (line ~201)
-- and ordA has no chargeback/refund_void lined against it yet. A REAL lost dispute
-- on ordA's payment gives origin_amt=6000 with face=10000, so v_exposure=0 (no
-- succeeded refund on this payment) and v_derived = least(6000, greatest(0,10000-0))
-- = 6000 — the SAME literal the original fixture asserted, preserving every
-- downstream K-section number (K1-K-whatever) unchanged.
WITH ins AS (
  INSERT INTO kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, payment_id, amount_minor, currency, reason, status)
  VALUES ('dp_162_o1', 'ch_162_o1', tap._fe162('pi_162_a-pay')::uuid, 6000, 'USD', 'fraudulent', 'lost')
  RETURNING dispute_id
)
SELECT tap._st162('o1dispute', dispute_id::text) FROM ins;
SELECT tap._st162('o1', kernel.record_organization_obligation(
    tap._fe162('org1')::uuid, 'unlined_reversal', tap._fe162('o1dispute')::uuid, 'dp_162_o1', 6000, 'USD', 'unlined_reversal', 'ck96-ob1') ->> 'obligation_id');
SELECT is((tap._ob162(tap._fe162('o1')::uuid)).status, 'outstanding', 'K0: FIXTURE — O1 books outstanding at 6000 (a real post-payout lost dispute on ordA, per 097''s fence)');

SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT is((kernel.record_obligation_recovery(tap._fe162('o1')::uuid, 2000, 'manual', 'receipt-162-1', 'partial off-platform payment', 'ck96-rec1') ->> 'status'), 'ok',
  'K1: MANUAL RECEIPT — platform_risk/platform_admin on aal2 records 2000 of the 6000 debt');
SELECT tap.logout();
SELECT is(kernel.obligation_outstanding_minor(tap._fe162('o1')::uuid), 4000::bigint,
  'K2: 2000 OF 6000 — outstanding is now 4000, derived (amount − Σ receipts), never stored');
SELECT is((tap._ob162(tap._fe162('o1')::uuid)).status, 'outstanding', 'K3: … the obligation is still outstanding, Σ < amount');
SELECT is(kernel.org_outstanding_obligation_minor(tap._fe162('org1')::uuid), 4000::bigint,
  'K4: ORG_OUTSTANDING NETS RECOVERIES — the org-level projection reflects the partial recovery, not the original 6000');

-- >debt refused
SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,9000,'manual','receipt-162-2','too much','ck96-rec2')$$, tap._fe162('o1')),
  '%recovery_exceeds_debt%',
  'K5: >DEBT REFUSED — 2000 already recovered + 9000 would exceed the 6000 debt; the guard trigger refuses it, unstorable by design');
SELECT tap.logout();
SELECT is(kernel.obligation_outstanding_minor(tap._fe162('o1')::uuid), 4000::bigint,
  'K6: … and the refusal changed nothing — still 4000 outstanding');

-- the completing receipt: transfer_reversal citing trr_162a1 (4000, on p1, org1).
SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT is((kernel.record_obligation_recovery(tap._fe162('o1')::uuid, 4000, 'transfer_reversal', 'trr_162a1', 'recovered via payout reversal', 'ck96-rec3') ->> 'obligation_status'), 'recovered',
  'K7: 6000 COMPLETES — the transfer_reversal receipt (trr_162a1, the SAME fact p1''s partial reversal wrote) brings Σ to 6000 = amount; the AFTER trigger flips the obligation to recovered as a CONSEQUENCE, never an act');
SELECT tap.logout();
SELECT is((tap._ob162(tap._fe162('o1')::uuid)).resolution_reason_code, 'recovered:transfer_reversal',
  'K8: … the reason code names the completing source_kind');
SELECT is(kernel.obligation_outstanding_minor(tap._fe162('o1')::uuid), 0::bigint, 'K9: … outstanding reads 0');

-- ============================================================================
-- SECTION L — write-off, wrong-org, resolve-without-facts, org netting.
--
-- 2026-09-03 (package 097's fence): O3 and O4 need real post-payout origins too
-- (same reasoning as O1 above) — ordL/ordM are fresh paid-out orders, each carrying
-- one real lost dispute at the exact literal amount the section already asserts
-- (1000, 500), so every downstream L-number is unchanged.
-- ============================================================================
SELECT tap._st162('ordL', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 3000, 'pi_162_l')::text);
SELECT tap._st162('sL', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordL'),'amt',3000)), 'ck96-sL')::text);
SELECT tap._st162('pL', (tap._po162(tap._fe162('sL')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('sL')::uuid, 'ck96-rl');
SELECT kernel.mark_payout_transfer_state(tap._fe162('pL')::uuid, 'paid', 'tr_162l', NULL, 'ck96-ml');
WITH ins AS (
  INSERT INTO kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, payment_id, amount_minor, currency, reason, status)
  VALUES ('dp_162_o3', 'ch_162_o3', tap._fe162('pi_162_l-pay')::uuid, 1000, 'USD', 'fraudulent', 'lost')
  RETURNING dispute_id
)
SELECT tap._st162('o3dispute', dispute_id::text) FROM ins;
SELECT tap._st162('o3', kernel.record_organization_obligation(
    tap._fe162('org1')::uuid, 'unlined_reversal', tap._fe162('o3dispute')::uuid, 'dp_162_o3', 1000, 'USD', 'unlined_reversal', 'ck96-ob3') ->> 'obligation_id');
SELECT is(kernel.org_outstanding_obligation_minor(tap._fe162('org1')::uuid), 1000::bigint,
  'L1: O1 is recovered (nets 0) — O3''s fresh 1000 is the WHOLE of org1''s outstanding now');

SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT is((kernel.resolve_organization_obligation(tap._fe162('o3')::uuid, 'written_off', 'uncollectable', 'ck96-wo1') ->> 'status'), 'ok',
  'L2: kernel.resolve_organization_obligation still WRITES OFF — the one act 096 leaves on the verb, outstanding only, aal2');
SELECT tap.logout();
SELECT is((tap._ob162(tap._fe162('o3')::uuid)).status, 'written_off', 'L3: … O3 now written_off');
SELECT is(kernel.org_outstanding_obligation_minor(tap._fe162('org1')::uuid), 0::bigint, 'L4: … org1''s outstanding falls back to 0');

SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,100,'manual','receipt-162-late','late receipt after write-off','ck96-rec4')$$, tap._fe162('o3')),
  '%obligation_written_off%',
  'L5: AFTER WRITTEN_OFF REFUSED — a late receipt cannot be recorded against a written-off obligation; it is an owner item (KD §5 Q4), refused fail-closed, not invented as a reopen');
SELECT tap.logout();

-- resolve('recovered') refused without facts — a FRESH obligation, zero receipts.
-- 2026-09-03 (package 097's fence): O4 needs a real post-payout origin too (same
-- reasoning as O1/O3) — ordM is a fresh paid-out order carrying one real lost
-- dispute at the exact literal amount (500) this section already asserts.
SELECT tap._st162('ordM', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 2000, 'pi_162_m')::text);
SELECT tap._st162('sM', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordM'),'amt',2000)), 'ck96-sM')::text);
SELECT tap._st162('pM', (tap._po162(tap._fe162('sM')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('sM')::uuid, 'ck96-rm');
SELECT kernel.mark_payout_transfer_state(tap._fe162('pM')::uuid, 'paid', 'tr_162m', NULL, 'ck96-mm');
WITH ins AS (
  INSERT INTO kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, payment_id, amount_minor, currency, reason, status)
  VALUES ('dp_162_o4', 'ch_162_o4', tap._fe162('pi_162_m-pay')::uuid, 500, 'USD', 'fraudulent', 'lost')
  RETURNING dispute_id
)
SELECT tap._st162('o4dispute', dispute_id::text) FROM ins;
SELECT tap._st162('o4', kernel.record_organization_obligation(
    tap._fe162('org1')::uuid, 'unlined_reversal', tap._fe162('o4dispute')::uuid, 'dp_162_o4', 500, 'USD', 'unlined_reversal', 'ck96-ob4') ->> 'obligation_id');
SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT throws_like(format($$SELECT kernel.resolve_organization_obligation(%L,'recovered','off_platform','ck96-res1')$$, tap._fe162('o4')),
  '%recovery_facts_required%',
  'L6: RESOLVE(RECOVERED) REFUSED WITHOUT FACTS — the KD P1-4 honesty fix: ''recovered'' is a consequence of receipts summing to the debt, never an act, unless Σ already equals the amount');
SELECT tap.logout();
SELECT is((tap._ob162(tap._fe162('o4')::uuid)).status, 'outstanding', 'L7: … O4 is unchanged, still outstanding');

-- wrong-org trr_ refused: org2's obligation cannot be recovered with org1's reversal fact.
-- 2026-09-03 (package 097's fence): a real paid-out org2 order + a real lost dispute at the
-- full face (3000) — exposure=0, so v_derived = least(3000,3000) = 3000, the exact literal.
SELECT tap._st162('ordO2', tap._cov162(tap._fe162('org2')::uuid, tap._fe162('sessOld2')::uuid, 3000, 'pi_162_o2')::text);
SELECT tap._st162('sO2', tap._settle162(tap._fe162('org2')::uuid, tap._fe162('venue2')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordO2'),'amt',3000)), 'ck96-so2')::text);
SELECT tap._st162('pO2', (tap._po162(tap._fe162('sO2')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org2')::uuid, tap._fe162('sO2')::uuid, 'ck96-ro2');
SELECT kernel.mark_payout_transfer_state(tap._fe162('pO2')::uuid, 'paid', 'tr_162o2', NULL, 'ck96-mo2');
WITH ins AS (
  INSERT INTO kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, payment_id, amount_minor, currency, reason, status)
  VALUES ('dp_162_o2', 'ch_162_o2', tap._fe162('pi_162_o2-pay')::uuid, 3000, 'USD', 'fraudulent', 'lost')
  RETURNING dispute_id
)
SELECT tap._st162('o2dispute', dispute_id::text) FROM ins;
SELECT tap._st162('o2', kernel.record_organization_obligation(
    tap._fe162('org2')::uuid, 'unlined_reversal', tap._fe162('o2dispute')::uuid, 'dp_162_o2', 3000, 'USD', 'unlined_reversal', 'ck96-ob2') ->> 'obligation_id');
SELECT tap.login(tap.admin_user());
SELECT tap._aal2_162();
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,1000,'transfer_reversal','trr_162a2','cross-org attempt','ck96-rec5')$$, tap._fe162('o2')),
  '%reversal_org_mismatch%',
  'L8: WRONG-ORG trr_ REFUSED — trr_162a2 reversed a payout of org1; org2''s obligation cannot cite it. Venue A''s debt cannot be settled with Venue B''s org''s money (G5 direction)');
SELECT tap.logout();
SELECT is((tap._ob162(tap._fe162('o2')::uuid)).status, 'outstanding', 'L9: … org2''s obligation is untouched');

-- ============================================================================
-- SECTION M — AUTHORITY: record_obligation_recovery requires
-- authenticated + is_platform + aal2, and is REVOKED from service_role.
-- ============================================================================
SELECT tap.login(tap.buyer());   -- authenticated, no platform role
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,100,'manual','receipt-162-auth1','x','ck96-auth1')$$, tap._fe162('o4')),
  '%insufficient_privilege: platform_risk or platform_admin required%', 'M1: a bare authenticated principal with no platform role is refused (insufficient_privilege)');
SELECT tap.logout();

SELECT tap.login(tap.admin_user());   -- platform, but no aal claim at all
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,100,'manual','receipt-162-auth2','x','ck96-auth2')$$, tap._fe162('o4')),
  '%step_up_unavailable%', 'M2: an absent aal claim is unevaluable and refused — never read as satisfied (AUTHZ-M4, the 095 E-2 idiom)');
SELECT tap._aal1_162();
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,100,'manual','receipt-162-auth3','x','ck96-auth3')$$, tap._fe162('o4')),
  '%step_up_required%', 'M3: an aal1 session is refused too — a step-up is required to record a recovery');
SELECT tap.logout();

SELECT tap.login_service();   -- the REVOCATION itself: a real service_role call, grant-level refusal
SELECT throws_like(format($$SELECT kernel.record_obligation_recovery(%L,100,'manual','receipt-162-svc','x','ck96-svc1')$$, tap._fe162('o4')),
  '%permission denied%',
  'M4: SERVICE_ROLE REFUSED — a machine identity is refused at the GRANT itself (permission denied for function), never reaching the body; a machine cannot declare a debt recovered');
SELECT tap.logout();
SELECT tap.login_service();
SELECT throws_like(format($$SELECT kernel.resolve_organization_obligation(%L,'written_off','x','ck96-svc2')$$, tap._fe162('o4')),
  '%permission denied%',
  'M5: … and the SAME is true of resolve_organization_obligation — the dead 094 service_role grant (KD P1-1) is gone, a write-off is a human act only');
SELECT tap.logout();

-- ============================================================================
-- SECTION N — KE §4.4 CASE TABLE, WITH REAL NUMBERS: the conservation block.
--   A fresh payout+obligation pair proves the row 4.4 names "reversal of the
--   full amount for a NON-RECOVERY reason while the obligation is outstanding":
--   no double count, but the ledger honestly says BOTH — the org still owes,
--   AND the platform owes the venue — until a human links them (096 does not
--   invent that link; it is not designed here, per 096's own header).
-- ============================================================================
SELECT tap._st162('ordN', tap._cov162(tap._fe162('org1')::uuid, tap._fe162('sessOld')::uuid, 5500, 'pi_162_n')::text);
SELECT tap._st162('sN', tap._settle162(tap._fe162('org1')::uuid, tap._fe162('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe162('ordN'),'amt',5500)), 'ck96-sn')::text);
SELECT tap._st162('pN', (tap._po162(tap._fe162('sN')::uuid)).payout_id::text);
SELECT tap._request162(tap._fe162('org1')::uuid, tap._fe162('sN')::uuid, 'ck96-rn');
SELECT kernel.mark_payout_transfer_state(tap._fe162('pN')::uuid, 'paid', 'tr_162n', NULL, 'ck96-mn');
-- 2026-09-03 (package 097's fence): a real lost dispute on ordN's own payment, at the
-- full face (5500) — exposure=0 (no succeeded refund), so v_derived = least(5500,5500) = 5500,
-- the exact literal this section already asserts.
WITH ins AS (
  INSERT INTO kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, payment_id, amount_minor, currency, reason, status)
  VALUES ('dp_162_oN', 'ch_162_oN', tap._fe162('pi_162_n-pay')::uuid, 5500, 'USD', 'fraudulent', 'lost')
  RETURNING dispute_id
)
SELECT tap._st162('oNdispute', dispute_id::text) FROM ins;
SELECT tap._st162('oN', kernel.record_organization_obligation(
    tap._fe162('org1')::uuid, 'unlined_reversal', tap._fe162('oNdispute')::uuid, 'dp_162_oN', 5500, 'USD', 'unlined_reversal', 'ck96-obn') ->> 'obligation_id');

SELECT is((kernel.record_payout_reversal(tap._fe162('pN')::uuid,'tr_162n','trr_162n1',5500,'{}'::jsonb,'ck96-rvn1') ->> 'payout_status'), 'reversed',
  'N1: CONSERVATION — a FULL, UNLINKED reversal (no obligation cited) moves the payout to reversed exactly as a linked one would');
SELECT is((tap._ob162(tap._fe162('oN')::uuid)).status, 'outstanding',
  'N2: … but the obligation is COMPLETELY UNTOUCHED — nothing here auto-links a reversal to an obligation (that link is a human act via record_obligation_recovery, deliberately not invented)');
-- org1's outstanding at this point is O4 (500, section L) + oN (5500, this
-- section) = 6000: the unlinked reversal added a SECOND obligation-shaped
-- number without touching the first, exactly the "two truths" the row warns of.
SELECT is(kernel.org_outstanding_obligation_minor(tap._fe162('org1')::uuid), 6000::bigint,
  'N3: NO DOUBLE COUNT, BUT NOT SILENT EITHER — org1''s outstanding is O4''s 500 (section L) PLUS oN''s fresh 5500, unrelated to the 5500 the platform just pulled back off pN; the two numbers coexist honestly rather than one silently discharging the other');
SELECT is(kernel.payout_reversed_minor(tap._fe162('pN')::uuid), 5500::bigint,
  'N4: … the reversal fact says the platform pulled back the whole 5500 from the venue, independently of the org''s own 5500 debt — the KE 4.4 "double meaning" row, both sides visible, neither silently netted');

-- the RECOVERY-LINKED case (KE 4.4 row 1/2) for direct contrast: O1 above (K7)
-- already proved this — recovery reverses 6000 exactly, obligation recovered,
-- payout stays paid at Σ<amount along the way. Re-assert the header-stays-paid
-- half of the SAME case here for p1 (fully reversed via recovery-eligible facts):
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fe162('s1')::uuid), 'paid',
  'N5: … the RECOVERY case''s settlement header (s1, covering p1, whose reversal facts funded O1''s recovery) is STILL paid — 095 E-5: the header never reflects the reversal, recovered or not');

-- ============================================================================
-- SECTION O — THE ATTESTATION, CHECKED (160 F5 idiom): no 096 verb can even
-- NAME a promoter.
-- ============================================================================
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) !~ 'promoter')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN (
              'payout_reversal_guard','payout_reversed_minor','record_payout_reversal',
              'organization_obligation_recovery_guard','organization_obligation_recovery_settle',
              'obligation_outstanding_minor','record_obligation_recovery',
              'resolve_organization_obligation','org_outstanding_obligation_minor',
              'claim_failed_payouts_for_reconcile','reconcile_payout_transfer')),
  'O1: NOTHING HERE PAYS A PROMOTER — grepping every 096 verb body (new and re-created) for the word ''promoter'' finds nothing, the 160/F5 idiom applied to 096''s own surface');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) !~ 'release_payout')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN (
              'payout_reversal_guard','record_payout_reversal',
              'organization_obligation_recovery_guard','organization_obligation_recovery_settle',
              'record_obligation_recovery','resolve_organization_obligation',
              'claim_failed_payouts_for_reconcile','reconcile_payout_transfer')),
  'O2: … nor does any of them name kernel.release_payout — no verb here releases a hold on any other payout');

-- ============================================================================
-- SECTION P — GATE-2 (public schema census) IS UNTOUCHED: 096 adds nothing
-- to public. (The kernel-schema census bump itself is the orchestrator's job,
-- per DESIGN_096 — this file does not touch 141-157.)
-- ============================================================================
-- pg_proc is filtered to exclude pgtap's own extension-owned functions (this
-- test file's own transaction has pgtap installed into public, unlike the
-- rehearsal_reset.sh baseline read, which runs before pgtap exists); tables/
-- policies/triggers carry no such pollution and need no filter.
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND c.relkind='r'), 27,
  'P1: GATE-2 tables=27 — 096 adds no public table');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public'
              AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')), 70,
  'P2: GATE-2 functions=70 — 096 adds no public function (pgtap''s own extension-owned functions excluded)');
SELECT is((SELECT count(*)::int FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public'), 37,
  'P3: GATE-2 policies=37 — 096 adds no public policy');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND NOT t.tgisinternal), 26,
  'P4: GATE-2 triggers=26 — 096 adds no public trigger');

SELECT finish();
ROLLBACK;
