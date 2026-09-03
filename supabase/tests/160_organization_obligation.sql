-- ============================================================================
-- 160_organization_obligation.sql — package 094 (org-side receivable RECORD).
--
-- SUBJECT: kernel.organization_obligation and its definer pair. The object that
--   exists because THE PLATFORM CANNOT OPEN A SETTLEMENT — venue.open_settlement's
--   gate is has_venue_role OR has_org_role (087:237-239) and kernel.has_org_role
--   carries no is_platform arm (077:453-466), so a debt that lives only in the
--   ledger is a debt whose booking depends on the debtor's cooperation.
--
-- Frozen sources: docs/phase2/_impl/J3_receivable_architecture.md (shape A′
--   §5.1/§5.2/§5.3) · kernel.identity_obligation 085:165-198 + its RPC pair
--   085:1790-1878 (the structural twin) · PHASE_2_MONEY_AUTHORITY_SPEC.md:1493-1496
--   (the "funds nothing, nets nothing, gates no payout" attestation) · 093:376
--   ("A negative net is NOT a receivable: this schema has no carry-forward
--   object") · 093:640-854 (kernel.close_settlement) · E-149/E-150/E-151.
--
-- THE FOUR PROPERTIES THIS FILE EXISTS TO PIN, each attacked from more than one
--   direction:
--     (i)   A POST-PAYOUT shortfall is RECORDED, and a PRE-payout refund is NOT.
--           The boundary is the whole point: 093's refund timing already reduces
--           the CURRENT settlement (succeeded-only debit at 093:526 + whole-order
--           deferral at 093:477-479), so an obligation there would double-count.
--     (ii)  The record is IDEMPOTENT under at-least-once delivery. The producer
--           is a retried webhook; UNIQUE(origin_kind, origin_ref) is the
--           mechanism, and a second delivery must return noop_replay with the
--           row count unmoved.
--     (iii) It is APPEND-ONLY and FORWARD-ONLY against every principal — no
--           DELETE, no rewrite of identity or magnitude, no second resolution,
--           no return to outstanding — enforced in the STORAGE layer so the
--           claim survives a future definer, not only this one.
--     (iv)  IT MOVES NO MONEY. It nets nothing into settlement_line, funds
--           nothing, gates no payout, and — asserted explicitly, in both the
--           source and the behaviour — NOTHING HERE PAYS A PROMOTER.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixtures are written as
--   postgres; role boundaries that cannot be observed behaviourally (the tap
--   personas set GUCs, not real roles) are asserted from the catalogue, the
--   house pattern used by 151/B8 and 158/A2.
-- ============================================================================
BEGIN;
SELECT plan(90);

SELECT tap.seed_core();

CREATE TABLE tap.memo_160 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st160(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_160 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._g160(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_160 WHERE k = $1 $m$;

-- The exact triple venue.finalize_primary_order leaves behind (085:2059-2061).
CREATE FUNCTION tap._ord160(p_session uuid, p_org uuid, p_face int, p_tag text,
                            p_status text DEFAULT 'paid')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_ord uuid := gen_random_uuid(); v_pay uuid := gen_random_uuid();
begin
  insert into venue."order" (order_id, buyer_id, event_session_id, org_id, status, source,
                             total_minor, currency, command_idempotency_key)
  values (v_ord, tap.buyer(), p_session, p_org, p_status, 'app', p_face, 'USD', 'ck160-' || p_tag);
  insert into public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total,
                               stripe_payment_intent_id, status, mode, paid_at)
  values (v_pay, tap.buyer(), p_face, 0, 0, p_face, 'pi_160_' || p_tag, 'succeeded', 'native_primary', now());
  insert into kernel.payment_native (payment_id, order_id, amount_minor, currency)
  values (v_pay, v_ord, p_face, 'USD');
  perform tap._st160('pay:' || p_tag, v_pay::text);
  return v_ord;
end $f$;

CREATE FUNCTION tap._rf160(p_order uuid, p_amt int, p_status text, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency,
                             status, stripe_refund_ref, idempotency_key)
  select v_id, pn.payment_id, 'buyer_request', p_amt, 'USD', p_status,
         case when p_status = 'pending' then null else 're_160_' || p_tag end, 'ck160-' || p_tag
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

-- A terminal-LOST dispute — the chargeback arm's operand (088:351-362 /
-- 093:1180-1196). Written directly because kernel.record_dispute_native has no
-- caller in any TypeScript today; that producer gap is real and is NOT this
-- file's to close.
CREATE FUNCTION tap._disp160(p_order uuid, p_amt int, p_tag text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.dispute_native (dispute_id, stripe_dispute_ref, stripe_charge_ref,
                                     payment_id, amount_minor, currency, reason, status)
  select v_id, 'dp_160_' || p_tag, 'ch_160_' || p_tag, pn.payment_id, p_amt, 'USD',
         'fraudulent', 'lost'
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

CREATE FUNCTION tap._open160(p_key text, p_org uuid, p_venue uuid, p_event uuid, p_owner uuid)
RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $f$
declare v uuid;
begin
  perform tap.login(p_owner);
  v := (venue.open_settlement(p_org, p_venue, p_event, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid;
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._close160(p_settlement uuid, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v jsonb;
begin
  perform tap.login(tap.admin_user());
  v := kernel.close_settlement(p_settlement, p_key);
  perform tap.logout();
  return v;
end $f$;

-- The RESOLVE verb as the edge reaches it: a PLATFORM principal's claims, with
-- the call itself made by the owner (the tap personas switch the real DB role,
-- and the verb is service_role-only by grant — B6 pins that from the
-- catalogue). This wrapper isolates the AUTHORITY check, kernel.is_platform,
-- from the grant, so E5 fails for the right reason.
CREATE FUNCTION tap._resolve160(p_oblig uuid, p_res text, p_reason text, p_key text, p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $f$
declare v jsonb;
begin
  perform tap.set_claims(p_uid);
  v := kernel.resolve_organization_obligation(p_oblig, p_res, p_reason, p_key);
  perform tap.logout();
  return v;
end $f$;

-- How many obligations does this org hold, and for this origin?
CREATE FUNCTION tap._obl160(p_org uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM kernel.organization_obligation WHERE org_id = p_org $f$;
CREATE FUNCTION tap._oblref160(p_ref uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM kernel.organization_obligation WHERE origin_ref = p_ref $f$;
CREATE FUNCTION tap._oblamt160(p_ref uuid) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT coalesce(sum(amount_minor),0)::bigint FROM kernel.organization_obligation WHERE origin_ref = p_ref $f$;
CREATE FUNCTION tap._oblid160(p_ref uuid) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT obligation_id FROM kernel.organization_obligation WHERE origin_ref = p_ref $f$;
-- a promoter payout's whole observable state, as one string
CREATE FUNCTION tap._payoutstate160(p_id uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT status || '|' || hold_state || '|' || coalesce(hold_reason_code,'-') || '|' || amount_minor::text
      FROM kernel.payout WHERE payout_id = p_id $f$;

-- ============================================================================
-- FIXTURE — org1 (seller) → venue1 → event1..event4 + org2 (other_user) →
--   venue2 → event5. Sessions are in the PAST so nothing here depends on the
--   maturity clock: this file is about the RECORD, and 151/C28 owns the gate.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st160('org1', (kernel.create_organization('Oblig Co','Oblig Co','ck160-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g160('org1');
SELECT tap.login(tap.seller());
SELECT tap._st160('venue1', (catalog.create_venue(tap._g160('org1'),'Oblig Hall','wynwood',NULL,'ck160-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g160('venue1'),'approved','miami_gate','ck160-a1');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._st160('org2', (kernel.create_organization('Other Oblig Co','Other Oblig Co','ck160-o2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g160('org2');
SELECT tap.login(tap.other_user());
SELECT tap._st160('venue2', (catalog.create_venue(tap._g160('org2'),'Other Oblig Hall','brickell',NULL,'ck160-v2') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g160('venue2'),'approved','miami_gate','ck160-a2');
SELECT tap.logout();

SELECT tap.login(tap.seller());
SELECT tap._st160('ev1', (catalog.create_event(tap._g160('venue1'),'Oblig One',
  jsonb_build_object('starts_at',(now()-interval '30 days')::text,'ends_at',(now()-interval '30 days'+interval '4 hours')::text),'ck160-e1') ->> 'event_id'));
SELECT tap._st160('ev2', (catalog.create_event(tap._g160('venue1'),'Oblig Two',
  jsonb_build_object('starts_at',(now()-interval '29 days')::text,'ends_at',(now()-interval '29 days'+interval '4 hours')::text),'ck160-e2') ->> 'event_id'));
SELECT tap._st160('ev3', (catalog.create_event(tap._g160('venue1'),'Oblig Three',
  jsonb_build_object('starts_at',(now()-interval '28 days')::text,'ends_at',(now()-interval '28 days'+interval '4 hours')::text),'ck160-e3') ->> 'event_id'));
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._st160('ev5', (catalog.create_event(tap._g160('venue2'),'Oblig Five',
  jsonb_build_object('starts_at',(now()-interval '27 days')::text,'ends_at',(now()-interval '27 days'+interval '4 hours')::text),'ck160-e5') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._st160('s1', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g160('ev1')));
SELECT tap._st160('s2', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g160('ev2')));
SELECT tap._st160('s3', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g160('ev3')));
SELECT tap._st160('s5', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g160('ev5')));

-- A HELD promoter_commission payout, born exactly as kernel.pay_promoter_commission
-- leaves one (090:1487-1491): held / 'unfunded_settlement'. It is the control for
-- the strongest constraint on this whole object — NOTHING MAY PAY A PROMOTER.
INSERT INTO kernel.payout (payout_id, payee_kind, payee_org_id, cause, cause_ref, amount_minor,
                           currency, status, hold_state, hold_reason_code, held_at, idempotency_key)
SELECT '99999999-0000-0000-0000-000000000160'::uuid, 'organization', tap._g160('org1'),
       'promoter_commission', gen_random_uuid(), 4200, 'USD', 'pending', 'held',
       'unfunded_settlement', now(), 'ck160-promoter';
SELECT tap._st160('promo_state_before', tap._payoutstate160('99999999-0000-0000-0000-000000000160'::uuid));

-- ============================================================================
-- SECTION A — THE RECORD'S SHAPE (J3 §5.1; the 085:165-198 transcription)
--   Every row here is a property the design named as load-bearing rather than
--   decorative. A failure is a design change, not a cosmetic drift.
-- ============================================================================
SELECT has_table('kernel'::name,'organization_obligation'::name,
  'A1: kernel.organization_obligation exists — the org-side twin of kernel.identity_obligation');
SELECT col_is_pk('kernel'::name,'organization_obligation'::name,'obligation_id'::name, 'A2: obligation_id is the PK');
SELECT col_type_is('kernel'::name,'organization_obligation'::name,'org_id'::name,'uuid', 'A3: org_id uuid — the debtor is an ORGANIZATION');
SELECT col_not_null('kernel'::name,'organization_obligation'::name,'org_id'::name, 'A4: org_id NOT NULL');
SELECT ok((SELECT c.confrelid = 'kernel.organization'::regclass AND c.confdeltype = 'r'
             FROM pg_constraint c
            WHERE c.conrelid = 'kernel.organization_obligation'::regclass AND c.contype='f'
              AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
                                     WHERE attrelid='kernel.organization_obligation'::regclass AND attname='org_id')]),
  'A5: org_id → kernel.organization ON DELETE RESTRICT — an outstanding debt makes its org undeletable, exactly as the identity twin''s FK does for BP-10');

-- THE POSITIVITY INVARIANT. Direction is the object''s identity, never a sign.
SELECT col_type_is('kernel'::name,'organization_obligation'::name,'amount_minor'::name,'integer',
  'A6: amount_minor integer — per-origin and bounded by the payment it derives from, matching the twin (085:171); int8 widening is an ACCUMULATOR precondition (E-149) and does not reach a per-origin row');
SELECT ok((SELECT count(*) = 1 FROM pg_constraint c
            WHERE c.conrelid='kernel.organization_obligation'::regclass AND c.contype='c'
              AND pg_get_constraintdef(c.oid) ~ 'amount_minor > 0'),
  'A7: amount_minor CHECK (> 0) — A POSITIVE MAGNITUDE ONLY. A signed amount would invite a negative-payout hack and would encode "we hold their money" and "they owe us money" as the sign of one integer');
SELECT throws_ok(format($$INSERT INTO kernel.organization_obligation (org_id, origin_kind, origin_ref, amount_minor)
                   VALUES (%L, 'settlement_shortfall', gen_random_uuid(), -1)$$, tap._g160('org1')),
  '23514', NULL, 'A8: a NEGATIVE magnitude is UNSTORABLE — the check is not advisory');

SELECT ok((SELECT pg_get_constraintdef(c.oid) ~ 'settlement_shortfall' AND pg_get_constraintdef(c.oid) ~ 'unlined_reversal'
             FROM pg_constraint c WHERE c.conrelid='kernel.organization_obligation'::regclass AND c.contype='c'
              AND pg_get_constraintdef(c.oid) LIKE '%origin_kind%'),
  'A9: origin_kind is the CLOSED two-member set — origins attach to the SHORTFALL, never to the dispute');
SELECT is((SELECT count(*)::int FROM pg_constraint c
            WHERE c.conrelid='kernel.organization_obligation'::regclass AND c.contype='c'
              AND pg_get_constraintdef(c.oid) LIKE '%origin_kind%'
              AND (pg_get_constraintdef(c.oid) LIKE '%chargeback%' OR pg_get_constraintdef(c.oid) LIKE '%refund_clawback%')), 0,
  'A10: it did NOT copy the identity twin''s enum — a chargeback origin would attach to the dispute the shipped netting already handles');
SELECT throws_ok(format($$INSERT INTO kernel.organization_obligation (org_id, origin_kind, origin_ref, amount_minor)
                   VALUES (%L, 'chargeback', gen_random_uuid(), 100)$$, tap._g160('org1')),
  '23514', NULL, 'A11: an unlisted origin_kind is unstorable — extending the enum is a ratification act, not an INSERT');

SELECT ok(EXISTS (SELECT 1 FROM pg_constraint c
                   WHERE c.conrelid='kernel.organization_obligation'::regclass AND c.contype='c'
                     AND pg_get_constraintdef(c.oid) ~ 'status'
                     AND pg_get_constraintdef(c.oid) ~ 'outstanding'
                     AND pg_get_constraintdef(c.oid) ~ 'recovered'
                     AND pg_get_constraintdef(c.oid) ~ 'written_off'),
  'A12: status is the three-label forward-only set — resolved by an audited platform act, never automatically');
SELECT col_default_is('kernel'::name,'organization_obligation'::name,'status'::name, 'outstanding',
  'A13: status defaults to outstanding — a booked debt starts unrecovered');
SELECT col_default_is('kernel'::name,'organization_obligation'::name,'currency'::name, 'USD',
  'A14: currency per row (J3 §8) — this is what dissolves E-149''s one-per-(org,currency) precondition instead of answering it');

-- THE IDEMPOTENCY MECHANISM.
SELECT ok((SELECT count(*) = 1 FROM pg_constraint c
            WHERE c.conrelid='kernel.organization_obligation'::regclass AND c.contype='u'
              AND pg_get_constraintdef(c.oid) = 'UNIQUE (origin_kind, origin_ref)'),
  'A15: UNIQUE(origin_kind, origin_ref) — THE idempotency mechanism. `balance = balance - X` has no database-enforceable equivalent, and the producer is an at-least-once webhook');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='kernel' AND tablename='organization_obligation'
                   AND indexname='organization_obligation_dispute_uq' AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%stripe_dispute_ref IS NOT NULL%'),
  'A16: the second idempotency key — partial UNIQUE on stripe_dispute_ref (085:185-186)');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='kernel' AND tablename='organization_obligation'
                   AND indexname='organization_obligation_outstanding_idx'
                   AND indexdef LIKE '%(org_id)%' AND indexdef LIKE '%status = ''outstanding''%'),
  'A17: the partial index (org_id) WHERE status=''outstanding'' — THIS INDEX IS the "does this organization have outstanding exposure" read; nothing materialises a balance');
SELECT ok((SELECT count(*) = 1 FROM pg_constraint c
            WHERE c.conrelid='kernel.organization_obligation'::regclass AND c.contype='c'
              AND pg_get_constraintdef(c.oid) LIKE '%resolution_reason_code IS NULL%'),
  'A18: the §1.9/§1.10 pairing CHECK — outstanding XOR a complete resolution triple');

-- ── DENY-ALL, APPEND-ONLY ───────────────────────────────────────────────────
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='kernel.organization_obligation'::regclass),
  'A19: RLS is ON');
SELECT is((SELECT count(*)::int FROM pg_policy WHERE polrelid='kernel.organization_obligation'::regclass), 0,
  'A20: ZERO policies — money-custody-RPC-only DENY-ALL (RLS §7.11), the kernel.reserve posture');
SELECT ok(NOT has_table_privilege('anon','kernel.organization_obligation','SELECT')
      AND NOT has_table_privilege('authenticated','kernel.organization_obligation','SELECT')
      AND NOT has_table_privilege('authenticated','kernel.organization_obligation','INSERT')
      AND NOT has_table_privilege('authenticated','kernel.organization_obligation','UPDATE'),
  'A21: no client principal holds ANY privilege on the table');
SELECT ok(NOT has_table_privilege('service_role','kernel.organization_obligation','SELECT')
      AND NOT has_table_privilege('service_role','kernel.organization_obligation','INSERT')
      AND NOT has_table_privilege('service_role','kernel.organization_obligation','UPDATE')
      AND NOT has_table_privilege('service_role','kernel.organization_obligation','DELETE'),
  'A22: NO DORMANT MACHINE GRANT on the table either (E-118/E-106 class) — E-150''s "a Gate-M writer will be a definer path" is satisfied BY CONSTRUCTION, not by policy');
SELECT is((SELECT count(*)::int FROM pg_trigger t WHERE t.tgrelid='kernel.organization_obligation'::regclass AND NOT t.tgisinternal), 2,
  'A23: exactly two triggers — set_updated_at and the append-only guard');

-- ============================================================================
-- SECTION B — THE VERB WALL (E-150; the 085 PART 14 discipline)
-- ============================================================================
SELECT has_function('kernel'::name,'record_organization_obligation'::name,
  ARRAY['uuid','text','uuid','text','integer','text','text','text']::name[],
  'B1: the WRITE verb exists — the platform''s way to book a debt WITHOUT the debtor opening a settlement');
SELECT has_function('kernel'::name,'resolve_organization_obligation'::name,
  ARRAY['uuid','text','text','text']::name[], 'B2: the RESOLVE verb exists (the 085:1838 pattern)');
SELECT has_function('kernel'::name,'org_outstanding_obligation_minor'::name, ARRAY['uuid']::name[],
  'B3: the PROJECTION exists — "does this org have outstanding exposure, and how much", served by A17''s index');

SELECT ok((SELECT bool_and(p.prosecdef AND 'search_path=""' = ANY(coalesce(p.proconfig,'{}'::text[])))
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('record_organization_obligation','resolve_organization_obligation',
                                                       'org_outstanding_obligation_minor','organization_obligation_guard')),
  'B4: all four are security definer with search_path pinned empty (the 076 discipline)');
SELECT ok(has_function_privilege('service_role','kernel.record_organization_obligation(uuid,text,uuid,text,integer,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.record_organization_obligation(uuid,text,uuid,text,integer,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('anon','kernel.record_organization_obligation(uuid,text,uuid,text,integer,text,text,text)','EXECUTE'),
  'B5: the WRITE verb is service_role ONLY — no client principal can book a debt against an organization');
SELECT ok(has_function_privilege('service_role','kernel.resolve_organization_obligation(uuid,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.resolve_organization_obligation(uuid,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('anon','kernel.resolve_organization_obligation(uuid,text,text,text)','EXECUTE'),
  'B6: the RESOLVE verb is service_role ONLY — strictly tighter than the identity twin, which is also granted to authenticated');
SELECT ok(has_function_privilege('service_role','kernel.org_outstanding_obligation_minor(uuid)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.org_outstanding_obligation_minor(uuid)','EXECUTE'),
  'B7: the projection is service_role only — an org''s debt is not a client-readable number');
SELECT ok(NOT has_function_privilege('service_role','kernel.organization_obligation_guard()','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.organization_obligation_guard()','EXECUTE'),
  'B8: the append-only guard is trigger-only — callable by NOBODY, service_role included');
SELECT ok((SELECT pg_get_functiondef(p.oid) ~ 'is_platform'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='resolve_organization_obligation'),
  'B9: resolution is gated on kernel.is_platform(platform_risk|platform_admin) — an audited PLATFORM act, unchanged from the twin');
-- close_settlement's own ACL must survive the CREATE OR REPLACE untouched.
SELECT ok(has_function_privilege('authenticated','kernel.close_settlement(uuid,text)','EXECUTE')
      AND NOT has_function_privilege('anon','kernel.close_settlement(uuid,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.close_settlement(uuid,text)','EXECUTE'),
  'B10: 094''s CREATE OR REPLACE did NOT alter kernel.close_settlement''s ACL — 087 PART 8''s caller-authorized classification survives (create or replace preserves ACLs)');

-- ============================================================================
-- SECTION C — THE BOUNDARY: PRE-PAYOUT REDUCES, POST-PAYOUT RECORDS
--   The single most important pair in this file. Getting it wrong in either
--   direction double-counts a loss or destroys one.
-- ============================================================================
-- C-a. NO OBLIGATION BEFORE PAYOUT. Event 3 carries two orders: one refunded
--   BEFORE the close, one not. 093's refund timing is already correct, so the
--   refund must reduce THIS settlement rather than produce a receivable.
SELECT tap._st160('oPre',  tap._ord160(tap._g160('s3'), tap._g160('org1'), 10000, 'oPre', 'refunded')::text);
SELECT tap._st160('oKeep', tap._ord160(tap._g160('s3'), tap._g160('org1'), 10000, 'oKeep')::text);
SELECT tap._st160('rPre',  tap._rf160(tap._g160('oPre'), 10000, 'succeeded', 'rPre')::text);
SELECT tap._st160('sPre',  tap._open160('ck160-sPre', tap._g160('org1'), tap._g160('venue1'), tap._g160('ev3'), tap.seller())::text);
SELECT tap._st160('closePre', (tap._close160(tap._g160('sPre'),'ck160-cPre') ->> 'net_minor'));

SELECT is((SELECT v FROM tap.memo_160 WHERE k='closePre'), '10000',
  'C1: a refund BEFORE payout REDUCES THE CURRENT SETTLEMENT — 20000 credited, 10000 debited, net 10000');
SELECT is(tap._oblref160(tap._g160('sPre')), 0,
  'C2: …and books NO OBLIGATION. This is the boundary: the object exists only for the POST-payout case, and an obligation here would double-count the debit the ledger already carries');
SELECT is((SELECT count(*)::int FROM kernel.payout WHERE cause='settlement' AND cause_ref=tap._g160('sPre')), 1,
  'C3: the reduced payout IS minted — the venue is paid the net, not the gross, and not nothing');

-- C-b. THE POST-PAYOUT REFUND. Event 1: close, pay, THEN refund, then close again.
SELECT tap._st160('oPost', tap._ord160(tap._g160('s1'), tap._g160('org1'), 10000, 'oPost')::text);
SELECT tap._st160('sA', tap._open160('ck160-sA', tap._g160('org1'), tap._g160('venue1'), tap._g160('ev1'), tap.seller())::text);
SELECT tap._st160('closeA', (tap._close160(tap._g160('sA'),'ck160-cA') ->> 'net_minor'));
SELECT is((SELECT v FROM tap.memo_160 WHERE k='closeA'), '10000', 'C4: settlement A closes +10000 and mints the payout — the money is now gone');
SELECT is(tap._obl160(tap._g160('org1')), 0, 'C5: a POSITIVE close books NOTHING — the record is reached only through a negative net');

-- the refund lands AFTER the payout was minted; the order is now refunded
UPDATE venue."order" SET status='refunded' WHERE order_id = tap._g160('oPost');
SELECT tap._st160('rPost', tap._rf160(tap._g160('oPost'), 10000, 'succeeded', 'rPost')::text);
SELECT tap._st160('sB', tap._open160('ck160-sB', tap._g160('org1'), tap._g160('venue1'), tap._g160('ev1'), tap.seller())::text);
SELECT tap._st160('closeB', (tap._close160(tap._g160('sB'),'ck160-cB') ->> 'net_minor'));

SELECT is((SELECT v FROM tap.memo_160 WHERE k='closeB'), '-10000',
  'C6: the next close nets −10000 — the credit was consumed by settlement A (platform-wide primary_sale uniqueness), so only the refund_void debit remains');
SELECT is((SELECT count(*)::int FROM kernel.payout WHERE cause='settlement' AND cause_ref=tap._g160('sB')), 0,
  'C7: a negative net mints NO payout — kernel.payout CHECK (amount_minor > 0) makes a negative instruction unstorable, and 094 does not touch that check');
SELECT is(tap._oblref160(tap._g160('sB')), 1,
  'C8: THE OBLIGATION IS BOOKED. 093:376''s "a negative net is NOT a receivable: this schema has no carry-forward object" is closed');
SELECT is(tap._oblamt160(tap._g160('sB')), 10000::bigint,
  'C9: …at the POSITIVE MAGNITUDE of the shortfall. Before 094 this residue was destroyed silently — seven such headers totalling −99,000 sat permanently closed in a full replay with nothing aggregating or ageing them');
SELECT is((SELECT origin_kind FROM kernel.organization_obligation WHERE origin_ref = tap._g160('sB')), 'settlement_shortfall',
  'C10: the origin attaches to the SHORTFALL, with origin_ref = settlement_id — not to the dispute, and not to a new settlement_line cause (J3 §5-bis.2, withdrawn)');
SELECT is((SELECT status FROM kernel.organization_obligation WHERE origin_ref = tap._g160('sB')), 'outstanding',
  'C11: it starts outstanding — nothing resolves it automatically');
SELECT is(kernel.org_outstanding_obligation_minor(tap._g160('org1')), 10000::bigint,
  'C12: the projection answers "does this organization have outstanding exposure" from these rows alone — cheap, unambiguous, and served by A17''s partial index');

-- C-c. THE CHARGEBACK. Event 2: close, pay, THEN lose a dispute.
SELECT tap._st160('oCB', tap._ord160(tap._g160('s2'), tap._g160('org1'), 7000, 'oCB')::text);
SELECT tap._st160('sC', tap._open160('ck160-sC', tap._g160('org1'), tap._g160('venue1'), tap._g160('ev2'), tap.seller())::text);
SELECT tap._st160('closeC', (tap._close160(tap._g160('sC'),'ck160-cC') ->> 'net_minor'));
SELECT is((SELECT v FROM tap.memo_160 WHERE k='closeC'), '7000', 'C13: settlement C closes +7000 and pays out');
SELECT tap._st160('dCB', tap._disp160(tap._g160('oCB'), 7000, 'dCB')::text);
SELECT tap._st160('sD', tap._open160('ck160-sD', tap._g160('org1'), tap._g160('venue1'), tap._g160('ev2'), tap.seller())::text);
SELECT tap._st160('closeD', (tap._close160(tap._g160('sD'),'ck160-cD') ->> 'net_minor'));
SELECT is((SELECT v FROM tap.memo_160 WHERE k='closeD'), '-7000',
  'C14: a LOST dispute after payout nets −7000 through the SHIPPED chargeback arm (088:351-362 / 093:1180-1196), whose semantics 094 leaves untouched');
SELECT is(tap._oblamt160(tap._g160('sD')), 7000::bigint,
  'C15: the chargeback shortfall is recorded too — the record catches what netting could not recover, and does not replace the netting');
SELECT is((SELECT count(*)::int FROM venue.settlement_line WHERE settlement_id=tap._g160('sD') AND cause='chargeback'), 1,
  'C16: the chargeback LINE is still written exactly once — 094 adds no second netting cause, so the double-count 093''s slice 10h fixed is not reintroduced one cause over');
SELECT is(kernel.org_outstanding_obligation_minor(tap._g160('org1')), 17000::bigint,
  'C17: exposure aggregates across origins in BIGINT (10000 + 7000)');

-- ============================================================================
-- SECTION D — IDEMPOTENCY AND ISOLATION
-- ============================================================================
-- D-a. The at-least-once webhook, delivered twice.
SELECT is((SELECT kernel.record_organization_obligation(
             tap._g160('org1'), 'settlement_shortfall', tap._g160('sB'), NULL,
             10000, 'USD', 'redelivery', 'ck160-dup') ->> 'status'), 'noop_replay',
  'D1: A SECOND DELIVERY OF THE SAME WEBHOOK IS A NO-OP — UNIQUE(origin_kind, origin_ref) is the mechanism a mutable balance cannot have');
SELECT is(tap._oblref160(tap._g160('sB')), 1,
  'D2: …and the row count is UNMOVED. `balance = balance - X` would have double-debited this org with no evidence in the row that it happened');
SELECT is((tap._close160(tap._g160('sB'),'ck160-cB2') ->> 'status'), 'noop_replay',
  'D3: re-closing the settlement is a replay that never reaches the branch');
SELECT is(tap._oblref160(tap._g160('sB')), 1, 'D4: …so a re-close cannot double-book either');

-- D-b. The magnitude is not a free parameter.
SELECT throws_ok(format($$SELECT kernel.record_organization_obligation(%L,'settlement_shortfall',%L,NULL,99999,'USD','attack','ck160-x1')$$,
  tap._g160('org1'), tap._g160('sD')), 'P0001', NULL,
  'D5: a caller cannot choose the amount — it is re-derived from the closed header, so the close cannot book a magnitude the ledger does not prove');
SELECT throws_ok(format($$SELECT kernel.record_organization_obligation(%L,'settlement_shortfall',%L,NULL,10000,'USD','attack','ck160-x2')$$,
  tap._g160('org1'), tap._g160('sPre')), 'P0001', NULL,
  'D6: nor can one be booked against a settlement that nets POSITIVE — there is no shortfall to record');
SELECT throws_ok(format($$SELECT kernel.record_organization_obligation(%L,'settlement_shortfall',%L,NULL,10000,'USD','attack','ck160-x3')$$,
  tap._g160('org2'), tap._g160('sB')), 'P0001', NULL,
  'D7: CROSS-ORG ISOLATION — org2 cannot be made the debtor of org1''s shortfall');
SELECT throws_ok($$SELECT kernel.record_organization_obligation('00000000-0000-0000-0000-0000000000aa','settlement_shortfall',
                     '00000000-0000-0000-0000-0000000000bb',NULL,100,'USD','attack','ck160-x4')$$,
  'P0002', NULL, 'D8: an unknown organization is not_found — the soft origin_ref has no FK, so the writer verifies the party itself');

-- D-c. unlined_reversal and its anti-double-count guard.
SELECT throws_ok(format($$SELECT kernel.record_organization_obligation(%L,'unlined_reversal',%L,NULL,7000,'USD','sweep','ck160-x5')$$,
  tap._g160('org1'), tap._g160('dCB')), 'P0001', NULL,
  'D9: an ALREADY-LINED dispute is refused for unlined_reversal — the shipped netting has it, and booking it here would double-count the same loss');
SELECT is((SELECT kernel.record_organization_obligation(
             tap._g160('org1'), 'unlined_reversal', '00000000-0000-0000-0000-0000000000cc', 'dp_dormant',
             2500, 'USD', 'dormant_org', 'ck160-u1') ->> 'status'), 'ok',
  'D10: an UNLINED reversal — the dormant-org case, where the debit is never even OFFERED because no settlement is ever opened — is bookable by the platform alone');
SELECT is(kernel.org_outstanding_obligation_minor(tap._g160('org2')), 0::bigint,
  'D11: org2 holds nothing — obligations do not leak across the org boundary');
SELECT is(kernel.org_outstanding_obligation_minor(tap._g160('org1')), 19500::bigint,
  'D12: org1''s exposure is its own three origins and no more');

-- ============================================================================
-- SECTION E — APPEND-ONLY, FORWARD-ONLY, AND THE AUDITED RESOLUTION
--   Asserted against the TABLE OWNER, which is the point: these are properties
--   of the object, not the discipline of one function.
-- ============================================================================
SELECT throws_ok(format($$DELETE FROM kernel.organization_obligation WHERE origin_ref = %L$$, tap._g160('sB')),
  'P0001', NULL, 'E1: DELETE IS REFUSED — a realized loss is never erased, and the guard holds even for the owner (REVOKE DELETE alone would not)');
SELECT throws_ok(format($$UPDATE kernel.organization_obligation SET amount_minor = 1 WHERE origin_ref = %L$$, tap._g160('sB')),
  'P0001', NULL, 'E2: the MAGNITUDE is write-once — a booked money fact cannot be silently restated');
SELECT throws_ok(format($$UPDATE kernel.organization_obligation SET org_id = %L WHERE origin_ref = %L$$,
  tap._g160('org2'), tap._g160('sB')), 'P0001', NULL, 'E3: the DEBTOR is write-once — a debt cannot be moved to another organization');
SELECT throws_ok(format($$UPDATE kernel.organization_obligation SET origin_ref = gen_random_uuid() WHERE origin_ref = %L$$, tap._g160('sB')),
  'P0001', NULL, 'E4: the ORIGIN is write-once — rewriting it would defeat the idempotency key itself');

-- the audited platform act
SELECT throws_ok(format($$SELECT tap._resolve160(%L,'written_off','give_up','ck160-r0',%L)$$,
  tap._oblid160(tap._g160('sB')), tap.buyer()),
  '42501', NULL, 'E5: a non-platform principal cannot resolve — recovery and write-off are platform acts, not org self-service (the AUTHORITY check, not the grant: B6 pins the grant)');
SELECT is((tap._resolve160(tap._oblid160(tap._g160('sB')),'recovered','off_platform_payment','ck160-r1', tap.admin_user()) ->> 'status'), 'ok',
  'E6: platform_admin resolves it — an AUDITED act, never a timer and never a netting');
SELECT is((tap._resolve160(tap._oblid160(tap._g160('sB')),'recovered','off_platform_payment','ck160-r1', tap.admin_user()) ->> 'status'), 'noop_replay',
  'E7: re-resolving to the SAME terminal is an idempotent replay');
SELECT throws_ok(format($$SELECT tap._resolve160(%L,'written_off','second','ck160-r2',%L)$$,
  tap._oblid160(tap._g160('sB')), tap.admin_user()),
  'P0001', NULL, 'E8: OVER-RESOLUTION IS IMPOSSIBLE — the two terminals are exclusive, so a debt cannot be both recovered and written off');
SELECT throws_ok(format($$UPDATE kernel.organization_obligation SET status='written_off' WHERE origin_ref = %L$$, tap._g160('sB')),
  'P0001', NULL, 'E9: …and the STORAGE LAYER says so too — a terminal is terminal even for the owner');
SELECT throws_ok(format($$UPDATE kernel.organization_obligation SET status='outstanding', resolution_reason_code=NULL, resolved_at=NULL WHERE origin_ref = %L$$, tap._g160('sB')),
  'P0001', NULL, 'E10: FORWARD-ONLY — an obligation never returns to outstanding');
SELECT is((SELECT status || '|' || resolution_reason_code FROM kernel.organization_obligation WHERE origin_ref = tap._g160('sB')),
  'recovered|off_platform_payment', 'E11: the resolution triple is intact and readable');
SELECT is(kernel.org_outstanding_obligation_minor(tap._g160('org1')), 9500::bigint,
  'E12: the projection drops the resolved row — "outstanding" is the durable meaning of "not recovered", which is exactly the operand a lines-written guard lacks');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action IN ('org_obligation.record','org_obligation.resolve')), 4,
  'E13: every write and every resolution left a kernel.admin_audit row (3 records + 1 resolution) — the record is auditable, not just durable');

-- ============================================================================
-- SECTION F — THE ATTESTATION, CHECKED RATHER THAN ASSERTED
--   "It funds nothing, it nets nothing, it gates no payout" — the identity
--   twin's ratified posture (MONEY:1493-1496), which must be LITERALLY TRUE of
--   this object for it to ship the way OR-21 and R-40 shipped.
-- ============================================================================
SELECT is((SELECT count(*)::int FROM venue.settlement_line l
            WHERE l.cause_ref IN (SELECT obligation_id FROM kernel.organization_obligation)), 0,
  'F1: NETS NOTHING — no settlement_line anywhere references an obligation; the object is not in the waterfall');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) !~ 'settlement_line')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('record_organization_obligation','resolve_organization_obligation',
                                                       'org_outstanding_obligation_minor')
              AND p.proname <> 'record_organization_obligation'),
  'F2: neither the resolve verb nor the projection can even name venue.settlement_line (the write verb reads it ONLY for the anti-double-count guard, and never writes it)');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) !~ 'insert into venue\.settlement_line'
                       AND pg_get_functiondef(p.oid) !~ 'update venue\.settlement_line')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('record_organization_obligation','resolve_organization_obligation',
                                                       'org_outstanding_obligation_minor','organization_obligation_guard')),
  'F3: …and no 094 verb writes a settlement line at all — J3''s own withdrawn first draft (a new netting cause) is NOT what was built');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) !~ 'kernel\.payout')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('record_organization_obligation','resolve_organization_obligation',
                                                       'org_outstanding_obligation_minor','organization_obligation_guard')),
  'F4: FUNDS NOTHING — not one 094 verb names kernel.payout, in any direction');
SELECT ok((SELECT bool_and(pg_get_functiondef(p.oid) !~ 'release_payout'
                       AND pg_get_functiondef(p.oid) !~ 'pay_promoter_commission'
                       AND pg_get_functiondef(p.oid) !~ 'promoter')
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('record_organization_obligation','resolve_organization_obligation',
                                                       'org_outstanding_obligation_minor','organization_obligation_guard')),
  'F5: NOTHING HERE PAYS A PROMOTER — no 094 verb names release_payout, pay_promoter_commission, or a promoter at all');
SELECT is(tap._payoutstate160('99999999-0000-0000-0000-000000000160'::uuid), (SELECT v FROM tap.memo_160 WHERE k='promo_state_before'),
  'F6: …and BEHAVIOURALLY the held promoter_commission payout is byte-identical after three closes, three bookings and a resolution — still pending|held|unfunded_settlement|4200');
SELECT is((SELECT count(*)::int FROM kernel.payout WHERE cause='promoter_commission' AND hold_state <> 'held'), 0,
  'F7: no promoter_commission payout anywhere left its hold — nothing was released, unheld or advanced');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~ 'organization_obligation'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_payout_maturity'),
  'F8: GATES NO PAYOUT — the maturity conjunction does not read the obligation table. Whether an outstanding debt should HOLD an org''s payouts is J3''s Q5, an owner decision deliberately not made here');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~ 'organization_obligation'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='get_payout_execution_context'),
  'F9: …nor does the transfer context. The projection in B3 is a READ that exists for such a guard to consume; consuming it is not this package''s act');
SELECT ok((SELECT pg_get_functiondef(p.oid) !~ 'organization_obligation'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'F10: the chargeback arm is UNTOUCHED — its deliberate absence of a scope predicate (088:310-316, "not 093''s to change") survives 094 exactly');

-- ── the sealed neighbours ───────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM kernel.reserve), 0,
  'F11: kernel.reserve is STILL EMPTY — 091''s always-empty checked property and its guarded, droppable rollback survive this package (E-149/E-151)');
SELECT ok((SELECT count(*) = 1 FROM pg_constraint c WHERE c.conrelid='kernel.payout'::regclass AND c.contype='c'
            AND pg_get_constraintdef(c.oid) ~ 'amount_minor > 0'),
  'F12: kernel.payout''s CHECK (amount_minor > 0) is INTACT — the positivity invariant that makes close_settlement mint nothing rather than mint a negative instruction');
SELECT is((SELECT count(*)::int FROM kernel.identity_obligation), 0,
  'F13: kernel.identity_obligation is untouched — 094 is a SEPARATE table with its own closed enum, so §1.10a:1186''s enum-extension ratification trigger is not fired');
SELECT ok((SELECT pg_get_constraintdef(c.oid) ~ 'chargeback' AND pg_get_constraintdef(c.oid) ~ 'refund_clawback'
             FROM pg_constraint c WHERE c.conrelid='kernel.identity_obligation'::regclass AND c.contype='c'
              AND pg_get_constraintdef(c.oid) LIKE '%origin_kind%'),
  'F14: …and its enum still reads exactly chargeback|refund_clawback — BP-10 and OR-21 are undisturbed');
SELECT is((SELECT count(*)::int FROM venue.settlement_line WHERE cause NOT IN
            ('issue','primary_sale','comp','door_sale','p2p_transfer','market_sale','auction_sale',
             'admin_action','refund_void','import','promoter_commission','settlement','chargeback')), 0,
  'F15: no new settlement_line cause exists in the data — the D3 closed set is unchanged');

SELECT * FROM finish();
ROLLBACK;
