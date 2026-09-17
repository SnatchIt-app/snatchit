-- ============================================================================
-- 161_payout_state_machine.sql — package 095, Agent E (sections E-1 … E-6).
--
-- SUBJECT: the edges the settlement→payout lifecycle did not have.
--   E-1  kernel.guard_payout_org_payable      — a suspended org cannot be paid
--   E-2  kernel.rearm_failed_payout           — the only exit from 'failed'
--   E-3  kernel.retry_held_payout             — how a maturity hold clears
--   E-4  kernel.hold_payout_transfer_reversed — a reversed transfer is not a payment
--   E-5  kernel.guard_settlement_forward_only — header integrity
--   E-6  kernel.settlement_unbooked_refund_exposure — a line written is not a debt recovered
--
-- THE PROPERTIES THIS FILE EXISTS TO PIN, stated as claims and attacked as
-- claims rather than asserted as grants:
--   1. 'failed' is absorbing and STAYS absorbing — 095 adds a verb, it does not
--      widen a transition. Re-verified here by execution, not by reading.
--   2. Recovery cannot double-pay, cannot mutate the amount, cannot inherit an
--      authorization, and cannot be performed by a machine.
--   3. The pinned destination survives a recovery unchanged.
--   4. A payout cannot be AUTHORIZED against an organization the platform is
--      not willing to pay — checked for every member of the status CHECK.
--   5. A maturity hold clears only when the WHOLE conjunction is clean, only at
--      a human's request, and never for a risk hold wearing its clothes.
--   6. A transfer whose money came back is never recorded as a payment.
--   7. A closed settlement cannot be reopened, rewritten or deleted.
--   8. Booking a reversal into a settlement that pays nobody does not discharge
--      the exposure that reversal represents.
--
-- Frozen sources: 085 PART 3/9/11 · 087 PART 2/3 + 087:360 · 093 slices
--   10d/10j/10k/10m/10n/10o/10p · 077:111 (the organization status CHECK) ·
--   supabase/functions/payout-execute/executor.ts ·
--   docs/phase2/_impl/J5_payout_state_machine.md.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixtures are written as
--   postgres; every role boundary is exercised through tap.login*/logout.
-- ============================================================================
BEGIN;
SELECT plan(86);

SELECT tap.seed_core();

CREATE TABLE tap.memo_160 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st160(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_160 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fe160(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_160 WHERE k=$1 $m$;

-- step-up: every money verb here demands aal2 (AUTHZ-M4)
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._aal1() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal1"}'::jsonb)::text, true); end $f$;

CREATE FUNCTION tap._audit160(p_subject uuid, p_action text, p_reason text DEFAULT NULL) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = p_subject AND a.action = p_action
     AND (p_reason IS NULL OR a.reason_code = p_reason) $m$;

-- definer readers over deny-all money tables
CREATE FUNCTION tap._po160(p_settlement uuid) RETURNS kernel.payout
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT p FROM kernel.payout p WHERE p.cause='settlement' AND p.cause_ref = p_settlement ORDER BY p.created_at LIMIT 1 $m$;
CREATE FUNCTION tap._ctx160(p_payout uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $m$ SELECT kernel.get_payout_execution_context(p_payout) $m$;
CREATE FUNCTION tap._claim160() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $m$ SELECT kernel.claim_payouts_for_execution(50, 900) $m$;
CREATE FUNCTION tap._exposure160(p_settlement uuid) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $m$ SELECT kernel.settlement_unbooked_refund_exposure(p_settlement) $m$;

-- a session with an explicit end, and a covered (payment, order, payment_native)
-- triple. The order is left `pending` ON PURPOSE: the covered set resolves
-- through it while kernel.settlement_primary_lines (which requires
-- paid/partially_refunded/refunded) never sweeps it into some other settlement.
CREATE FUNCTION tap._sess160(p_event uuid, p_label text, p_end timestamptz) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.event_session (event_id, session_label, starts_at, ends_at, status)
    VALUES (p_event, p_label, p_end - interval '3 hours', p_end, 'completed') RETURNING session_id $m$;
CREATE FUNCTION tap._cov160(p_org uuid, p_session uuid, p_total int, p_tag text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
DECLARE v_pay uuid; v_order uuid;
BEGIN
  INSERT INTO public.payments (buyer_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
  VALUES (tap.buyer(), p_total, 0, p_total, 'succeeded', 'native_primary', p_tag) RETURNING id INTO v_pay;
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), p_session, p_org, 'pending', 'web', p_total, p_tag || '-ord') RETURNING order_id INTO v_order;
  INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor, currency)
  VALUES (v_pay, v_order, p_total, 'USD');
  PERFORM tap._st160(p_tag || '-pay', v_pay::text);
  RETURN v_order;
END $m$;
-- open + line + close, in one step. Returns the settlement id.
CREATE FUNCTION tap._settle160(p_org uuid, p_venue uuid, p_lines jsonb, p_key text) RETURNS uuid
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
-- the E-1 probe: cycle the org through a status and try the ONE guarded edge.
CREATE FUNCTION tap._advance160(p_payout uuid, p_org_status text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
  UPDATE kernel.organization SET status = p_org_status
   WHERE org_id = (SELECT payee_org_id FROM kernel.payout WHERE payout_id = p_payout);
  BEGIN
    UPDATE kernel.payout SET status = 'submitted' WHERE payout_id = p_payout;
    UPDATE kernel.payout SET status = 'pending'   WHERE payout_id = p_payout;   -- undo
    RETURN 'advanced';
  EXCEPTION WHEN others THEN
    RETURN CASE WHEN sqlerrm LIKE 'precondition_failed: org_not_active%' THEN 'refused:org_not_active'
                ELSE 'refused:' || sqlerrm END;
  END;
END $f$;

-- ============================================================================
-- SECTION A — THE SHAPE OF THE FIVE NEW VERBS, AND THEIR WALL.
--   If any of these flip, some principal has gained a capability nobody granted.
-- ============================================================================
SELECT has_function('kernel'::name, 'rearm_failed_payout'::name, ARRAY['uuid','text','text']::name[],
  'A1: the ONLY exit from the absorbing ''failed'' state exists');

SELECT ok(has_function_privilege('authenticated','kernel.rearm_failed_payout(uuid,text,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.rearm_failed_payout(uuid,text,text)','EXECUTE')
      AND NOT has_function_privilege('anon','kernel.rearm_failed_payout(uuid,text,text)','EXECUTE'),
  'A2: A SERVICE WORKER CANNOT SELF-AUTHORIZE MONEY — the machine that executes payouts is EXPLICITLY revoked from the verb that re-arms them');

SELECT ok((SELECT p.prosecdef AND 'search_path=""' = ANY(coalesce(p.proconfig,'{}'::text[]))
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='rearm_failed_payout'),
  'A3: security definer with search_path pinned empty (076 discipline)');

SELECT ok(has_function_privilege('authenticated','kernel.retry_held_payout(uuid,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.retry_held_payout(uuid,uuid,text)','EXECUTE'),
  'A4: the maturity self-clear is HUMAN-INITIATED — authenticated only, and no machine may clear a hold');

SELECT ok(has_function_privilege('service_role','kernel.hold_payout_transfer_reversed(uuid,text,integer,integer,jsonb,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.hold_payout_transfer_reversed(uuid,text,integer,integer,jsonb,text)','EXECUTE'),
  'A5: the reversal hold is a MACHINE observation — service_role only, never a client (the 10o posture)');

SELECT ok(has_function_privilege('service_role','kernel.settlement_unbooked_refund_exposure(uuid)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.settlement_unbooked_refund_exposure(uuid)','EXECUTE'),
  'A6: the staleness operand is a money gate, not a read model — service_role only');

SELECT ok(NOT has_function_privilege('authenticated','kernel.guard_payout_org_payable()','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.guard_payout_org_payable()','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.guard_settlement_forward_only()','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.guard_settlement_forward_only()','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.settlement_maturity_hold_codes()','EXECUTE'),
  'A7: the trigger functions and the hold-code constant are not callable verbs — no principal holds EXECUTE (077 F1 stays zero)');

SELECT ok(EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                   WHERE c.oid='kernel.payout'::regclass AND t.tgname='tg_payout_org_payable_guard' AND NOT t.tgisinternal)
      AND EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                   WHERE c.oid='venue.settlement'::regclass AND t.tgname='tg_settlement_forward_only' AND NOT t.tgisinternal),
  'A8: both guards are actually ATTACHED — a trigger function with no trigger protects nothing');

-- The drift detector. kernel.settlement_maturity_hold_codes() pins the eight
-- reasons 10m can emit; retry_held_payout will clear NOTHING outside that list.
-- If 10m gains a ninth code and this list does not, a payout would be
-- permanently unclearable by the retry path and nobody would notice — so the
-- coupling is asserted against 10m's OWN SOURCE, not against a copy.
-- 2026-09-03 (package 097): 8 -> 9. A ninth code, 'dispute_unabsorbed', joins after
-- 'dispute_open' (the shortfall-hold predicate). Re-derived from the live function.
SELECT is(array_length(kernel.settlement_maturity_hold_codes(), 1), 9,
  'A9: the maturity vocabulary is nine codes');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) LIKE '%''' || c || '''%')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
                  unnest(kernel.settlement_maturity_hold_codes()) c
            WHERE n.nspname='kernel' AND p.proname='settlement_payout_maturity'),
  'A9a: every code in the list is a literal kernel.settlement_payout_maturity can actually emit — the two cannot drift silently');

-- 095 adds a verb; it does NOT widen a transition.
SELECT is((SELECT pg_get_constraintdef(oid) FROM pg_constraint
            WHERE conrelid='kernel.payout'::regclass AND conname='payout_status_check'),
  'CHECK ((status = ANY (ARRAY[''pending''::text, ''submitted''::text, ''paid''::text, ''failed''::text, ''reversed''::text])))',
  'A10: the status CHECK is UNTOUCHED — five members, exactly as 085 wrote them. The recovery is a new verb, not a loosened machine');

-- ============================================================================
-- FIXTURE — org1 (seller = owner, other_user = matured org_finance) → venue1 →
--   event1 → sessions. Destination bound by direct write, so no destination
--   change audit exists and the §10.3 probation arm never fires (151's idiom).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st160('org1', (kernel.create_organization('PSM Co','PSM Co','ck94-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fe160('org1')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._st160('venue1', (catalog.create_venue(tap._fe160('org1')::uuid,'PSM Hall','wynwood',NULL,'ck94-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fe160('venue1')::uuid,'approved','miami_gate','ck94-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._st160('event1', (catalog.create_event(tap._fe160('venue1')::uuid,'PSM Night',
  jsonb_build_object('starts_at',(now()-interval '40 days')::text,'ends_at',(now()-interval '40 days' + interval '4 hours')::text),'ck94-e1') ->> 'event_id'));
SELECT tap.logout();
-- a MATURE session (ended 40 days ago) and an IMMATURE one (ends next month)
SELECT tap._st160('sessOld', tap._sess160(tap._fe160('event1')::uuid, 'old',  now() - interval '40 days')::text);
SELECT tap._st160('sessNew', tap._sess160(tap._fe160('event1')::uuid, 'new',  now() + interval '30 days')::text);
-- roles + destination + capability (direct fixture writes, as table owner)
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._fe160('org1')::uuid, tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days'
 WHERE org_id = tap._fe160('org1')::uuid AND identity_id = tap.seller();
UPDATE kernel.organization
   SET stripe_connect_account_ref = 'acct_PSM160', connect_transfers_active = true
 WHERE org_id = tap._fe160('org1')::uuid;
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.settlement_maturity_interval', coalesce(max(version),0)+1, '"7 days"'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.settlement_maturity_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '100000000'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';

-- S1: a mature, unheld, requested payout — the control every later section bends.
SELECT tap._st160('ordA', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 10000, 'pi_160_a')::text);
SELECT tap._st160('s1', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordA'),'amt',10000)), 'ck94-s1')::text);
SELECT tap._st160('p1', (tap._po160(tap._fe160('s1')::uuid)).payout_id::text);
SELECT ok((tap._po160(tap._fe160('s1')::uuid)).hold_state = 'none'
       AND (tap._po160(tap._fe160('s1')::uuid)).status = 'pending'
       AND (tap._po160(tap._fe160('s1')::uuid)).amount_minor = 10000,
  'A11: FIXTURE CONTROL — a mature settlement mints an UNHELD pending payout of the full net (if this fails, nothing below means what it says)');

-- ============================================================================
-- SECTION B — 'failed' IS ABSORBING, RE-VERIFIED BY EXECUTION.
--   095 must not have loosened it, and the recovery below must be a genuine
--   need rather than a decoration.
-- ============================================================================
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s1')::uuid, 'ck94-r1') ->> 'status'), 'submitted',
  'B1: below the dual-control threshold the payout advances pending → submitted and the destination is pinned');
SELECT tap.logout();
SELECT is((tap._po160(tap._fe160('s1')::uuid)).destination_ref, 'acct_PSM160',
  'B1a: … the PIN (10j) names the account the payout was authorized against');

SELECT is((kernel.mark_payout_transfer_state(tap._fe160('p1')::uuid, 'failed', NULL, 'transient_stripe_error', 'ck94-f1') ->> 'new_status'), 'failed',
  'B2: submitted → failed is permitted (which is exactly why the strand exists)');
SELECT throws_like(format($$SELECT kernel.mark_payout_transfer_state(%L,'paid','tr_160x',NULL,'ck94-f2')$$, tap._fe160('p1')),
  '%payout_state_backwards (failed → paid)%', 'B3: failed → paid RAISES — there is no forward edge out of failed');
SELECT throws_like(format($$SELECT kernel.mark_payout_transfer_state(%L,'reversed','tr_160x',NULL,'ck94-f3')$$, tap._fe160('p1')),
  '%payout_state_backwards (failed → reversed)%', 'B4: failed → reversed RAISES — the one terminal-to-terminal edge is paid → reversed and it is unreachable from here');
SELECT throws_like(format($$SELECT kernel.mark_payout_transfer_state(%L,'submitted',NULL,NULL,'ck94-f4')$$, tap._fe160('p1')),
  '%takes paid|failed|reversed%', 'B5: failed → submitted is not even a legal argument');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck94-r1b')$$, tap._fe160('org1'), tap._fe160('s1')),
  '%no pending payout for this settlement%',
  'B6: and the request path cannot see it either — it selects only pending|submitted, so WITHOUT 095 the venue''s 10000 is destroyed as a ledger fact');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — THE RE-ARM (E-2). Authority, then the six properties.
-- ============================================================================
SELECT tap.login(tap.other_user());   -- an org money role: owns the money, not the recovery
SELECT tap._aal2();
SELECT throws_ok(format($$SELECT kernel.rearm_failed_payout(%L,'stripe_outage','ck94-x1')$$, tap._fe160('p1')),
  '42501', NULL, 'C1: an org_finance cannot re-arm — the payee does not decide when its own failed payout comes back');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_like(format($$SELECT kernel.rearm_failed_payout(%L,'stripe_outage','ck94-x2a')$$, tap._fe160('p1')),
  '%step_up_unavailable%', 'C2: a session carrying NO aal claim is refused as unevaluable — an absent claim is never read as satisfied (AUTHZ-M4)');
SELECT tap._aal1();
SELECT throws_like(format($$SELECT kernel.rearm_failed_payout(%L,'stripe_outage','ck94-x2')$$, tap._fe160('p1')),
  '%step_up_required%', 'C2a: … and an aal1 session is refused too — a step-up is required to re-arm money');
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.rearm_failed_payout(%L,NULL,'ck94-x3')$$, tap._fe160('p1')),
  '%bad_reason_code%', 'C3: a reason code is mandatory — an unexplained re-arm is not a recovery, it is an untraceable one');
SELECT is((kernel.rearm_failed_payout(tap._fe160('p1')::uuid, 'stripe_outage', 'ck94-x4') ->> 'status'), 'rearmed',
  'C4: platform_risk/platform_admin on aal2 re-arms the payout');
SELECT tap.logout();

SELECT ok((tap._po160(tap._fe160('s1')::uuid)).status = 'pending'
       AND (tap._po160(tap._fe160('s1')::uuid)).hold_state = 'held'
       AND (tap._po160(tap._fe160('s1')::uuid)).hold_reason_code = 'failed_rearm'
       AND (tap._po160(tap._fe160('s1')::uuid)).held_by = tap.admin_user(),
  'C5: the row lands at pending + held/failed_rearm, stamped with the HUMAN who re-armed it — never at ''submitted'', so the re-arm is not an authorization');
SELECT is((tap._po160(tap._fe160('s1')::uuid)).destination_ref, 'acct_PSM160',
  'C6: THE ORIGINAL DESTINATION AUTHORIZATION IS PRESERVED — the 10j pin is neither cleared nor rewritten by the recovery');
SELECT ok((tap._po160(tap._fe160('s1')::uuid)).amount_minor = 10000
       AND (tap._po160(tap._fe160('s1')::uuid)).currency = 'USD'
       AND (tap._po160(tap._fe160('s1')::uuid)).cause = 'settlement'
       AND (tap._po160(tap._fe160('s1')::uuid)).cause_ref = tap._fe160('s1')::uuid
       AND (tap._po160(tap._fe160('s1')::uuid)).idempotency_key = 'settlement:' || tap._fe160('s1')
       AND (tap._po160(tap._fe160('s1')::uuid)).stripe_transfer_ref IS NULL,
  'C7: NO ARBITRARY AMOUNT MUTATION — amount, currency, cause, cause_ref, the idempotency key and the transfer ref are all exactly what close_settlement minted');
SELECT is(tap._audit160(tap._fe160('p1')::uuid, 'payout.rearm', 'stripe_outage'), 1,
  'C8: the re-arm is AUDITED with its operator reason, in an append-only table it cannot later erase');
SELECT is((kernel.rearm_failed_payout(tap._fe160('p1')::uuid, 'stripe_outage', 'ck94-x4') ->> 'status'), 'noop_replay',
  'C9: NO REPLAY AMBIGUITY — a second re-arm of an already-re-armed payout is a no-op, not a second recovery')
  FROM (SELECT tap.login(tap.admin_user()), tap._aal2()) _;
SELECT tap.logout();

SELECT is((SELECT count(*)::int FROM jsonb_array_elements(tap._claim160() -> 'payouts') e
            WHERE e ->> 'payout_id' = tap._fe160('p1')), 0,
  'C10: a re-armed payout is INVISIBLE to the executor''s claim — pending + held is not work, so no worker can see it, let alone execute it');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck94-r1c')$$, tap._fe160('org1'), tap._fe160('s1')),
  '%payout_held%', 'C11: nor can the org walk past the hold — a human must release before the payout can even be REQUESTED again');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT is((kernel.release_payout(tap._fe160('p1')::uuid, 'ck94-rel1') ->> 'status'), 'ok',
  'C12: kernel.release_payout (085, unchanged) is the release — 095 added no second release path');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s1')::uuid, 'ck94-r1d') ->> 'status'), 'submitted',
  'C13: … and only then does the ORG re-authorize it, behind SoD-1, aal2, maturity, probation and dual control — two authority domains, never one principal');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.payout WHERE cause='settlement' AND cause_ref = tap._fe160('s1')::uuid), 1,
  'C14: NO DOUBLE PAYOUT — the whole failure-and-recovery cycle left exactly ONE payout row; nothing re-minted, nothing forked');

-- the ref-bearing failure: the one case re-arm refuses, and why.
SELECT tap._st160('ordB', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 4000, 'pi_160_b')::text);
SELECT tap._st160('s2', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordB'),'amt',4000)), 'ck94-s2')::text);
SELECT tap._st160('p2', (tap._po160(tap._fe160('s2')::uuid)).payout_id::text);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s2')::uuid, 'ck94-r2');
SELECT tap.logout();
SELECT kernel.mark_payout_transfer_state(tap._fe160('p2')::uuid, 'failed', 'tr_160b', 'transfer_failed', 'ck94-f5');
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.rearm_failed_payout(%L,'retry','ck94-x5')$$, tap._fe160('p2')),
  '%transfer_already_recorded%',
  'C15: NO DOUBLE PAYOUT, the second lock — a failed payout that CARRIES a tr_… is refused: a Stripe Transfer exists, whether its money moved is not a fact this database can establish, and re-arming would offer a second one');
SELECT tap.logout();
SELECT is((tap._po160(tap._fe160('s2')::uuid)).status, 'failed',
  'C15a: … and the refusal changed nothing — the row is exactly as it was, which is the named residual (owner item J5 §7), not a silent recovery');

-- ============================================================================
-- SECTION D — A SUSPENDED ORGANIZATION (E-1).
--   Every member of the 077:111 CHECK, enumerated from the constraint rather
--   than guessed, exercised against the ONE guarded edge.
-- ============================================================================
SELECT is((SELECT count(*)::int FROM unnest(ARRAY['applied','approved','active','suspended','closed']) s
            WHERE pg_get_constraintdef((SELECT oid FROM pg_constraint
                    WHERE conrelid='kernel.organization'::regclass AND conname LIKE '%status%' AND contype='c'))
                  LIKE '%''' || s || '''%'), 5,
  'D0: the five status members under test ARE the CHECK''s members — the coverage claim is derived from the constraint, not asserted about it');

SELECT tap._st160('ordC', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 2500, 'pi_160_c')::text);
SELECT tap._st160('s3', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordC'),'amt',2500)), 'ck94-s3')::text);
SELECT tap._st160('p3', (tap._po160(tap._fe160('s3')::uuid)).payout_id::text);

SELECT is(tap._advance160(tap._fe160('p3')::uuid, 'applied'),   'refused:org_not_active', 'D1: applied — an unapproved org cannot have a payout authorized against it');
SELECT is(tap._advance160(tap._fe160('p3')::uuid, 'approved'),  'advanced',               'D2: approved — PAYABLE (the control; a guard that refuses everything proves nothing)');
SELECT is(tap._advance160(tap._fe160('p3')::uuid, 'active'),    'advanced',               'D3: active — PAYABLE, the ordinary case');
SELECT is(tap._advance160(tap._fe160('p3')::uuid, 'suspended'), 'refused:org_not_active', 'D4: suspended — REFUSED at the authorization edge itself, not later at the executor');
SELECT is(tap._advance160(tap._fe160('p3')::uuid, 'closed'),    'refused:org_not_active', 'D5: closed — REFUSED (077:920 makes closed terminal; a terminal org is never paid)');

-- the reported defect, end to end: request_org_payout used to advance a
-- suspended org's payout all the way to `submitted` with a pinned destination.
UPDATE kernel.organization SET status='suspended' WHERE org_id = tap._fe160('org1')::uuid;
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck94-r3')$$, tap._fe160('org1'), tap._fe160('s3')),
  '%org_not_active%',
  'D6: THE DEFECT — kernel.request_org_payout now FAILS for a suspended organization instead of advancing the authorization and leaving 10n/10o to unwind it');
SELECT tap.logout();
SELECT ok((tap._po160(tap._fe160('s3')::uuid)).status = 'pending'
       AND (tap._po160(tap._fe160('s3')::uuid)).destination_ref IS NULL,
  'D7: … and NOTHING advanced: the payout is still pending and no destination was pinned, so no authorization was spent');
SELECT is((SELECT count(*)::int FROM kernel.approval_request a
            WHERE a.action='payout.request' AND a.subject_id = tap._fe160('s3')::uuid), 0,
  'D8: … and no dual-control approval was PARKED for a suspended org — a request nobody may grant is never left sitting ready to be granted');
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fe160('org1')::uuid;

-- ============================================================================
-- SECTION E — HOW A MATURITY HOLD CLEARS (E-3).
-- ============================================================================
SELECT tap._st160('ordD', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessNew')::uuid, 6000, 'pi_160_d')::text);
SELECT tap._st160('s4', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordD'),'amt',6000)), 'ck94-s4')::text);
SELECT tap._st160('p4', (tap._po160(tap._fe160('s4')::uuid)).payout_id::text);
SELECT ok((tap._po160(tap._fe160('s4')::uuid)).hold_state = 'held'
       AND (tap._po160(tap._fe160('s4')::uuid)).hold_reason_code = 'maturity_not_elapsed'
       AND (tap._po160(tap._fe160('s4')::uuid)).held_by IS NULL,
  'E1: a session that has not happened yet mints a MACHINE maturity hold — held_by NULL is what makes it machine-set rather than a risk decision');

SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck94-r4')$$, tap._fe160('org1'), tap._fe160('s4')),
  '%payout_held%',
  'E2: THE DEFECT — request_org_payout refuses a held payout outright, so matures_at never clears itself and platform_risk attention is spent on a clock');
SELECT is((kernel.retry_held_payout(tap._fe160('org1')::uuid, tap._fe160('s4')::uuid, 'ck94-t1') ->> 'status'), 'maturity_held',
  'E3: the retry re-evaluates and, while the event is still in the future, HOLDS — nothing is released because time has not passed');
SELECT tap.logout();
SELECT ok((tap._po160(tap._fe160('s4')::uuid)).hold_state = 'held'
       AND (tap._po160(tap._fe160('s4')::uuid)).status = 'pending',
  'E4: … and the hold is intact afterwards — a refused retry is not a window');
SELECT is((SELECT count(*)::int FROM kernel.approval_request a
            WHERE a.action='payout.request' AND a.subject_id = tap._fe160('s4')::uuid), 0,
  'E5: … and no approval was parked against an immature settlement');

-- a refund goes non-terminal: the predicate that turns is NOT the clock, and
-- the retry must re-evaluate it too.
UPDATE catalog.event_session SET starts_at = now() - interval '30 days' - interval '3 hours',
                                 ends_at   = now() - interval '30 days'
 WHERE session_id = tap._fe160('sessNew')::uuid;
INSERT INTO kernel.refund (payment_id, reason_code, amount_minor, currency, status, idempotency_key)
VALUES (tap._fe160('pi_160_d-pay')::uuid, 'buyer_request', 500, 'USD', 'pending', 'ck94-rf1');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.retry_held_payout(tap._fe160('org1')::uuid, tap._fe160('s4')::uuid, 'ck94-t2') ->> 'hold_reason_code'), 'refund_in_flight',
  'E6: with the clock now satisfied but a refund in flight, the retry STILL holds — and names the predicate that is failing NOW, not the one from the close');
SELECT tap.logout();
UPDATE kernel.refund SET status='failed', stripe_refund_ref='re_160_x' WHERE idempotency_key='ck94-rf1';
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.retry_held_payout(tap._fe160('org1')::uuid, tap._fe160('s4')::uuid, 'ck94-t3') ->> 'status'), 'submitted',
  'E7: only when EVERY predicate is clean does the hold clear — and the advance is request_org_payout''s, behind its whole ladder, not this verb''s');
SELECT tap.logout();
SELECT is(tap._audit160(tap._fe160('p4')::uuid, 'payout.maturity_clear'), 1,
  'E8: the clear is audited under the name of the human who asked for it');

-- what the retry must REFUSE to clear.
SELECT tap._st160('ordE', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 3000, 'pi_160_e')::text);
SELECT tap._st160('s5', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordE'),'amt',3000)), 'ck94-s5')::text);
SELECT tap._st160('p5', (tap._po160(tap._fe160('s5')::uuid)).payout_id::text);
SELECT tap.login(tap.admin_user());
SELECT kernel.hold_payout(tap._fe160('p5')::uuid, 'fraud_review', 'ck94-h1');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.retry_held_payout(%L,%L,'ck94-t4')$$, tap._fe160('org1'), tap._fe160('s5')),
  '%human_hold%',
  'E9: A RISK HOLD CANNOT BE LAUNDERED — kernel.hold_payout stamps held_by, and a hold with a person''s name on it is released only by kernel.release_payout');
SELECT tap.logout();
UPDATE kernel.payout SET held_by = NULL, hold_reason_code = 'fraud_review' WHERE payout_id = tap._fe160('p5')::uuid;
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.retry_held_payout(%L,%L,'ck94-t5')$$, tap._fe160('org1'), tap._fe160('s5')),
  '%not_a_maturity_hold%',
  'E10: … and stripping held_by is not enough either — the reason code must be one of the eight the maturity gate can emit, so an operator-typed risk reason stays outside');
SELECT tap.logout();
UPDATE kernel.payout SET hold_state='probation_hold', hold_reason_code='destination_probation' WHERE payout_id = tap._fe160('p5')::uuid;
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.retry_held_payout(%L,%L,'ck94-t6')$$, tap._fe160('org1'), tap._fe160('s5')),
  '%payout_held%',
  'E11: … and a destination-probation hold keeps its own contracted exit (T-RPC-MONEY-32), untouched by the maturity retry');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — A REVERSED TRANSFER IS NOT A PAYMENT (E-4).
--   The defect: executor.ts read Transfer.reversed, which Stripe documents as
--   FULL reversal only, so a PARTIALLY reversed transfer synced to 'paid' at
--   full face value.
-- ============================================================================
SELECT tap._st160('ordF', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 8000, 'pi_160_f')::text);
SELECT tap._st160('s6', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordF'),'amt',8000)), 'ck94-s6')::text);
SELECT tap._st160('p6', (tap._po160(tap._fe160('s6')::uuid)).payout_id::text);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s6')::uuid, 'ck94-r6');
SELECT tap.logout();

SELECT throws_like(format($$SELECT kernel.hold_payout_transfer_reversed(%L,'tr_160f',8000,0,'{}'::jsonb,'ck94-v0')$$, tap._fe160('p6')),
  '%amount_reversed_minor must be positive%',
  'F1: the verb records a REVERSAL — a zero is not one, and passing it is an input error rather than a quiet no-op');
SELECT is((kernel.hold_payout_transfer_reversed(tap._fe160('p6')::uuid, 'tr_160f', 8000, 1200, '{}'::jsonb, 'ck94-v1') ->> 'fault'),
  'transfer_partially_reversed',
  'F2: 1200 of an 8000 obligation is a PARTIAL reversal — the case Transfer.reversed reports as false and the old executor recorded as a full payment');
SELECT ok((tap._po160(tap._fe160('s6')::uuid)).status = 'pending'
       AND (tap._po160(tap._fe160('s6')::uuid)).hold_state = 'held'
       AND (tap._po160(tap._fe160('s6')::uuid)).hold_reason_code = 'transfer_partially_reversed'
       AND (tap._po160(tap._fe160('s6')::uuid)).held_by IS NULL
       AND (tap._po160(tap._fe160('s6')::uuid)).stripe_transfer_ref IS NULL,
  'F3: NEITHER ''paid'' NOR ''reversed'' is written — the row de-authorizes to pending + held, and stripe_transfer_ref stays NULL because 085:133 makes it mark_payout_transfer_state''s column alone');
SELECT is((tap._po160(tap._fe160('s6')::uuid)).amount_minor, 8000,
  'F3a: … and the obligation is untouched: a partial reversal is UNREPRESENTABLE in one amount column, which is the named owner item, not something forced into the ledger');
SELECT is(tap._audit160(tap._fe160('p6')::uuid, 'payout.transfer_reversed_hold', 'transfer_partially_reversed'), 1,
  'F4: … and the exact amounts are audited, because a human now has to decide what the venue is still owed');
SELECT is((kernel.hold_payout_transfer_reversed(tap._fe160('p6')::uuid, 'tr_160f', 8000, 1200, '{}'::jsonb, 'ck94-v2') ->> 'status'), 'noop_replay',
  'F5: a replay is a no-op — the executor may observe the same reversal on every tick');
SELECT is((tap._ctx160(tap._fe160('p6')::uuid) ->> 'refusal_code'), 'payout_held',
  'F6: … and the held payout is refused by the executor''s own context read, so no worker re-attempts it');

-- the verdict is derived from the LEDGER, never from the caller's numbers.
SELECT tap._st160('ordG', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 5000, 'pi_160_g')::text);
SELECT tap._st160('s7', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordG'),'amt',5000)), 'ck94-s7')::text);
SELECT tap._st160('p7', (tap._po160(tap._fe160('s7')::uuid)).payout_id::text);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s7')::uuid, 'ck94-r7');
SELECT tap.logout();
-- a caller that UNDER-reports the transfer's own amount cannot turn a full
-- reversal into a partial one: the denominator is kernel.payout.amount_minor.
SELECT is((kernel.hold_payout_transfer_reversed(tap._fe160('p7')::uuid, 'tr_160g', 1, 5000, '{}'::jsonb, 'ck94-v3') ->> 'fault'),
  'transfer_reversed',
  'F7: full-versus-partial is decided against the OBLIGATION, not against the caller''s reported transfer amount — the caller''s numbers are evidence, never predicates');
SELECT throws_like(format($$SELECT kernel.hold_payout_transfer_reversed(%L,'not_a_transfer',5000,5000,'{}'::jsonb,'ck94-v4')$$, tap._fe160('p7')),
  '%Stripe transfer ref%', 'F8: a malformed transfer ref is refused — the audit''s evidence has to be a real Stripe handle');

-- ============================================================================
-- SECTION G — SETTLEMENT HEADER INTEGRITY (E-5).
--   venue.settlement_line has been append-only since 087; the header it rolls
--   up into had nothing.
-- ============================================================================
SELECT throws_like(format($$UPDATE venue.settlement SET status='open' WHERE settlement_id=%L$$, tap._fe160('s1')),
  '%settlement_status_backwards (closed → open)%',
  'G1: a CLOSED settlement cannot be reopened — the reopen-and-re-close that produced a REPORTED hold the payout mint never applied is now unreachable');
SELECT throws_like(format($$UPDATE venue.settlement SET net_minor = net_minor + 1 WHERE settlement_id=%L$$, tap._fe160('s1')),
  '%money columns and scope are written exactly once%',
  'G2: … nor can its money columns be rewritten, which is what let net_minor drift away from the amount an in-flight payout was authorized for');
SELECT throws_like(format($$UPDATE venue.settlement SET event_id=%L WHERE settlement_id=%L$$, tap._fe160('event1'), tap._fe160('s1')),
  '%money columns and scope are written exactly once%',
  'G2a: … nor its scope: WHAT this settlement settles (org, venue, event) was decided at the close, and re-scoping it would silently change what its immutable lines mean');
SELECT throws_like(format($$DELETE FROM venue.settlement WHERE settlement_id=%L$$, tap._fe160('s1')),
  '%is a money record and is not deletable%',
  'G3: … and it cannot be deleted, the append-only rule its lines have carried since 087');
SELECT lives_ok(format($$UPDATE venue.settlement SET updated_at = now() WHERE settlement_id=%L$$, tap._fe160('s1')),
  'G4: an UPDATE that changes neither status nor money still passes — the guard binds the transition, not the row');

-- the three legitimate writers all still work. If any of these fails the guard
-- has blocked a real workflow and must not ship.
SELECT tap.login(tap.seller());
SELECT tap._st160('s8', (venue.open_settlement(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid, NULL, '{}'::jsonb, 'ck94-s8') ->> 'settlement_id'));
SELECT tap.logout();
SELECT throws_like(format($$UPDATE venue.settlement SET status='paid' WHERE settlement_id=%L$$, tap._fe160('s8')),
  '%settlement_status_backwards (open → paid)%',
  'G5: open → paid skips the close and is refused — forward-only means through every state, not merely forwards');
SELECT lives_ok(format($$DELETE FROM venue.settlement WHERE settlement_id=%L$$, tap._fe160('s8')),
  'G6: an OPEN settlement with no lines is still deletable — the guard protects money records, it does not freeze the table');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fe160('s2')::uuid), 'closed',
  'G7: kernel.close_settlement (open → closed, four money columns in the same statement) passed the guard throughout this file');
SELECT kernel.mark_payout_transfer_state(tap._fe160('p3')::uuid, 'failed', NULL, 'unused', 'ck94-noop')
  FROM (SELECT 1) _ WHERE false;   -- (no-op: p3 is pending; kept out of the plan)
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s5')::uuid, 'ck94-r5x')
  FROM (SELECT 1) _ WHERE false;
SELECT tap.logout();
SELECT is((kernel.mark_payout_transfer_state(tap._fe160('p1')::uuid, 'paid', 'tr_160a', NULL, 'ck94-m1') ->> 'new_status'), 'paid',
  'G8: … and the closed → paid writer (venue.on_payout_settled, via the state sync) passes it too');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fe160('s1')::uuid), 'paid',
  'G8a: … the header actually reached ''paid'', so the guard let the real settlement hook through');
SELECT throws_like(format($$UPDATE venue.settlement SET status='closed' WHERE settlement_id=%L$$, tap._fe160('s1')),
  '%settlement_status_backwards (paid → closed)%',
  'G9: and ''paid'' is terminal — a discharged settlement cannot be walked back');

-- ============================================================================
-- SECTION H — A LINE WRITTEN IS NOT A DEBT RECOVERED (E-6).
--   The executed defeat: book the reversal into a settlement that pays nobody,
--   and the refund_exposure_stale guard stops firing.
-- ============================================================================
SELECT tap._st160('ordH', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 10000, 'pi_160_h')::text);
SELECT tap._st160('s9', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordH'),'amt',10000)), 'ck94-s9')::text);
SELECT tap._st160('p9', (tap._po160(tap._fe160('s9')::uuid)).payout_id::text);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.request_org_payout(tap._fe160('org1')::uuid, tap._fe160('s9')::uuid, 'ck94-r9') ->> 'status'), 'submitted',
  'H1: the control — a clean, mature settlement payout of 10000 is authorized and, at this instant, executable');
SELECT tap.logout();
SELECT is((tap._ctx160(tap._fe160('p9')::uuid) ->> 'refusal_code'), NULL,
  'H1a: … the executor''s own context agrees: nothing refuses it');

-- a refund SUCCEEDS after the close. Nothing has debited it anywhere.
INSERT INTO kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency, status, stripe_refund_ref, idempotency_key)
VALUES ('9e160000-0000-0000-0000-000000000009', tap._fe160('pi_160_h-pay')::uuid, 'buyer_request', 10000, 'USD', 'succeeded', 're_160_h', 'ck94-rf9');
SELECT is((tap._ctx160(tap._fe160('p9')::uuid) ->> 'refusal_code'), 'refund_exposure_stale',
  'H2: a settled post-close refund makes the payout stale — the ledger owes the buyer money it is about to hand the venue');

-- THE DEFEAT: book the reversal into a settlement that mints nothing.
SELECT tap._st160('s10', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','refund_void','ref','9e160000-0000-0000-0000-000000000009','amt',-10000)), 'ck94-s10')::text);
SELECT ok((SELECT net_minor < 0 FROM venue.settlement WHERE settlement_id = tap._fe160('s10')::uuid)
      AND NOT EXISTS (SELECT 1 FROM kernel.payout WHERE cause='settlement' AND cause_ref = tap._fe160('s10')::uuid),
  'H3: that second settlement nets NEGATIVE and mints NO payout — it writes a line and recovers nothing, because this schema has no carry-forward object');
SELECT is((tap._ctx160(tap._fe160('p9')::uuid) ->> 'refusal_code'), 'refund_exposure_stale',
  'H4: THE DEFECT — the payout is STILL refused. Under 093 the mere existence of that line discharged the exposure and the executor would have paid the venue in full for revenue that was entirely reversed');
SELECT is(((tap._ctx160(tap._fe160('p9')::uuid) -> 'maturity_detail') ->> 'unbooked_refund_exposure_minor')::bigint, 10000::bigint,
  'H4a: … and the reported exposure is still the whole 10000, so an operator sees the real number rather than a zero');
SELECT is(tap._exposure160(tap._fe160('s9')::uuid), 10000::bigint,
  'H5: the operand itself says so directly — a refund_void line in a negative-net settlement discharges nothing');

-- and the converse: a debit a settlement ACTUALLY absorbed does discharge.
SELECT tap._st160('ordJ', tap._cov160(tap._fe160('org1')::uuid, tap._fe160('sessOld')::uuid, 8000, 'pi_160_j')::text);
INSERT INTO kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency, status, stripe_refund_ref, idempotency_key)
VALUES ('9e160000-0000-0000-0000-00000000000a', tap._fe160('pi_160_j-pay')::uuid, 'buyer_request', 3000, 'USD', 'succeeded', 're_160_j', 'ck94-rfa');
SELECT tap._st160('s11', tap._settle160(tap._fe160('org1')::uuid, tap._fe160('venue1')::uuid,
  jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe160('ordJ'),'amt',8000),
                    jsonb_build_object('cause','refund_void','ref','9e160000-0000-0000-0000-00000000000a','amt',-3000)), 'ck94-s11')::text);
SELECT ok((SELECT net_minor = 5000 FROM venue.settlement WHERE settlement_id = tap._fe160('s11')::uuid),
  'H6: a settlement whose own revenue absorbed the refund closes at net 5000 and pays the venue the REDUCED amount');
SELECT is(tap._exposure160(tap._fe160('s11')::uuid), 0::bigint,
  'H7: … and THAT discharges the exposure — the fix distinguishes a debit the venue actually bore from one merely written down, which is the whole property');
SELECT is(tap._exposure160(tap._fe160('s2')::uuid), 0::bigint,
  'H8: a settlement with no refunds against its covered payments reports zero exposure — the guard does not fire on ordinary money');

SELECT finish();
ROLLBACK;
