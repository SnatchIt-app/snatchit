-- ============================================================================
-- 159_refund_accounting_timing.sql — package 093 slice 10b.
--
-- SUBJECT: WHEN kernel.settlement_primary_lines reduces a venue's obligation.
--   Not WHETHER a refund is debited (151/C20e-C20h already pin the cross-
--   settlement uniqueness of the line) but at WHICH kernel.refund.status the
--   debit — and the CREDIT it nets against — become ledger facts at all.
--
-- Frozen sources: 085:82-88 (kernel.refund pending → submitted →
--   succeeded|failed; 'failed' = Stripe ACCEPTED and could not settle, so THE
--   BUYER GOT NOTHING BACK) · 087:110-112 (venue.settlement_line is append-only)
--   · 093 slice 10b (the succeeded-only debit arm + the whole-order deferral in
--   scoped_order) · 093 slice 10c (settlement_one_refund_void_line_ever) ·
--   ruling A5 (face-value entitlement; the buyer-side service fee is platform
--   money) · docs/phase2/_impl/J6_refund_accounting.md.
--
-- THE PROPERTY THIS FILE EXISTS TO PIN. venue.settlement_line has no UPDATE and
--   no DELETE, and 10c makes a second 'refund_void' line for a refund_id
--   unstorable platform-wide. A line is therefore a claim that can never be
--   withdrawn, so the seam may only ever write a fact that can no longer
--   change. That splits into two halves, and BOTH are load-bearing — one
--   without the other just moves the loss to the other party:
--     (i)  the debit arm takes 'succeeded' ONLY  — booking 'pending' or
--          'submitted' would debit a venue for money that may never leave;
--     (ii) an order carrying a NON-TERMINAL refund is deferred WHOLE — neither
--          credit nor debit — because (i) alone would pay the venue face value
--          for an order that is about to be refunded.
--   Nothing in 151 asserts either half. This file does, in both directions:
--   the refund that succeeds after being deferred, and the one that FAILS.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixtures are written as
--   postgres; kernel.settlement_primary_lines is definer-internal (093 revokes
--   EXECUTE from every role), so it is probed as the owner, exactly as
--   kernel.close_settlement reaches it.
-- ============================================================================
BEGIN;
SELECT plan(22);

SELECT tap.seed_core();

CREATE TABLE tap.memo_159 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st159(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_159 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._g159(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_159 WHERE k = $1 $m$;

-- The exact triple venue.finalize_primary_order leaves behind (085:2059-2061):
-- venue."order" + public.payments + kernel.payment_native. p_fee is the
-- BUYER-SIDE service fee, which rides in payments.total (000:978-985) but is
-- NOT part of the venue's face-value entitlement under ruling A5 — the operand
-- the cap in A8 turns on.
CREATE FUNCTION tap._ord159(p_session uuid, p_org uuid, p_face int, p_fee int,
                            p_tag text, p_status text DEFAULT 'paid')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_ord uuid := gen_random_uuid(); v_pay uuid := gen_random_uuid();
begin
  insert into venue."order" (order_id, buyer_id, event_session_id, org_id, status, source,
                             total_minor, currency, command_idempotency_key)
  values (v_ord, tap.buyer(), p_session, p_org, p_status, 'app', p_face, 'USD', 'ck159-' || p_tag);
  insert into public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total,
                               stripe_payment_intent_id, status, mode, paid_at)
  values (v_pay, tap.buyer(), p_face, p_fee, 0, p_face + p_fee,
          'pi_159_' || p_tag, 'succeeded', 'native_primary', now());
  insert into kernel.payment_native (payment_id, order_id, amount_minor, currency)
  values (v_pay, v_ord, p_face + p_fee, 'USD');
  perform tap._st159('pay:' || p_tag, v_pay::text);
  return v_ord;
end $f$;

-- A refund against that order's payment, at an arbitrary point of the 085:82-85
-- machine. refund_ref_pairing_ck (085:93) forbids a ref on 'pending' and
-- requires one on every later state, so the fixture honours it rather than
-- working around it.
CREATE FUNCTION tap._rf159(p_order uuid, p_amt int, p_status text, p_tag text,
                           p_reason text DEFAULT 'buyer_request')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency,
                             status, stripe_refund_ref, idempotency_key)
  select v_id, pn.payment_id, p_reason, p_amt, 'USD', p_status,
         case when p_status = 'pending' then null else 're_159_' || p_tag end,
         'ck159-' || p_tag
    from kernel.payment_native pn where pn.order_id = p_order;
  return v_id;
end $f$;

-- Candidate probes. The seam is a pure generator: called on a settlement whose
-- lines have not been written, it can be asked the same question repeatedly.
CREATE FUNCTION tap._cand159(p_settlement uuid, p_ref uuid) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT count(*)::int FROM kernel.settlement_primary_lines(p_settlement) c WHERE c.cause_ref = p_ref $f$;
CREATE FUNCTION tap._amt159(p_settlement uuid, p_cause text, p_ref uuid) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT coalesce(sum(c.amount_minor), 0)::bigint FROM kernel.settlement_primary_lines(p_settlement) c
     WHERE c.cause = p_cause AND c.cause_ref = p_ref $f$;
-- what the LEDGER holds for a reference, across every settlement, ever
CREATE FUNCTION tap._lined159(p_ref uuid) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$f$ SELECT coalesce(sum(l.amount_minor), 0)::bigint FROM venue.settlement_line l WHERE l.cause_ref = p_ref $f$;

CREATE FUNCTION tap._open159(p_key text, p_event uuid) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $f$
declare v uuid;
begin
  perform tap.login(tap.seller());
  v := (venue.open_settlement(tap._g159('org1'), tap._g159('venue1'), p_event, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid;
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._close159(p_settlement uuid, p_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $f$
declare v jsonb;
begin
  perform tap.login(tap.admin_user());
  v := kernel.close_settlement(p_settlement, p_key);
  perform tap.logout();
  return v;
end $f$;

-- ============================================================================
-- FIXTURE — org1 (seller owner) → venue1 → event1 → session1. The session is in
--   the PAST so nothing here depends on the maturity clock; this file is about
--   the LINES, and 151/C28 owns the payout gate.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st159('org1', (kernel.create_organization('Refund Timing Co','Refund Timing Co','ck159-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._g159('org1');
SELECT tap.login(tap.seller());
SELECT tap._st159('venue1', (catalog.create_venue(tap._g159('org1'),'Refund Timing Hall','wynwood',NULL,'ck159-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._g159('venue1'),'approved','miami_gate','ck159-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._st159('event1', (catalog.create_event(tap._g159('venue1'),'Refund Timing Night',
  jsonb_build_object('starts_at',(now() - interval '30 days')::text,
                     'ends_at',  (now() - interval '30 days' + interval '4 hours')::text),'ck159-e1') ->> 'event_id'));
SELECT tap._st159('sess1', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g159('event1')));
SELECT tap.logout();
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._g159('org1'), tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id = tap._g159('org1');

-- SEVEN orders on one session, one per state of the question.
SELECT tap._st159('oN',    tap._ord159(tap._g159('sess1'), tap._g159('org1'),  5000,  500, 'oN')::text);
SELECT tap._st159('oP',    tap._ord159(tap._g159('sess1'), tap._g159('org1'), 10000, 1000, 'oP')::text);
SELECT tap._st159('oS',    tap._ord159(tap._g159('sess1'), tap._g159('org1'), 10000, 1000, 'oS')::text);
SELECT tap._st159('oF',    tap._ord159(tap._g159('sess1'), tap._g159('org1'), 10000, 1000, 'oF')::text);
SELECT tap._st159('oK',    tap._ord159(tap._g159('sess1'), tap._g159('org1'), 10000, 1000, 'oK', 'refunded')::text);
SELECT tap._st159('oPart', tap._ord159(tap._g159('sess1'), tap._g159('org1'), 10000, 1000, 'oPart', 'partially_refunded')::text);
SELECT tap._st159('oCap',  tap._ord159(tap._g159('sess1'), tap._g159('org1'), 10000, 1000, 'oCap', 'refunded')::text);

SELECT tap._st159('rP',    tap._rf159(tap._g159('oP'),    10000, 'pending',   'rP')::text);
SELECT tap._st159('rS',    tap._rf159(tap._g159('oS'),    10000, 'submitted', 'rS')::text);
SELECT tap._st159('rF',    tap._rf159(tap._g159('oF'),    10000, 'failed',    'rF')::text);
SELECT tap._st159('rK',    tap._rf159(tap._g159('oK'),    10000, 'succeeded', 'rK')::text);
SELECT tap._st159('rPart', tap._rf159(tap._g159('oPart'),  3000, 'succeeded', 'rPart')::text);
-- 11000 = face 10000 + the buyer-side service fee 1000. Legal against the
-- PAYMENT (000:978-985) and the operand ruling A5's face cap exists to refuse.
SELECT tap._st159('rCap',  tap._rf159(tap._g159('oCap'),  11000, 'succeeded', 'rCap')::text);

SELECT tap._st159('sA', tap._open159('ck159-sA', tap._g159('event1'))::text);

-- ============================================================================
-- SECTION A — THE CANDIDATE CONTRACT. No lines are written in this section, so
--   every probe asks the seam the same question about a different refund state.
-- ============================================================================
SELECT is(tap._amt159(tap._g159('sA'), 'primary_sale', tap._g159('oN')), 5000::bigint,
  'A1: CONTROL — an order with no refund at all emits its +face credit');

SELECT is(tap._cand159(tap._g159('sA'), tap._g159('oP')), 0,
  'A2: a PENDING refund defers the ORDER WHOLE — the credit arm emits nothing for it (booking the credit alone would pay the venue face value for an order about to be refunded; nothing in 087:289-355 or 087:423-465 reads refund state)');
SELECT is(tap._cand159(tap._g159('sA'), tap._g159('rP')), 0,
  'A2a: … and the debit arm emits nothing for that pending refund either — money still in motion is not yet an economic fact about the venue');

SELECT is(tap._cand159(tap._g159('sA'), tap._g159('oS')), 0,
  'A3: a SUBMITTED refund defers the order identically — Stripe has ACCEPTED it but not settled it, so it is still not terminal (085:82-85)');
SELECT is(tap._cand159(tap._g159('sA'), tap._g159('rS')), 0,
  'A3a: … and no refund_void line is minted for a submitted refund');

SELECT is(tap._amt159(tap._g159('sA'), 'primary_sale', tap._g159('oF')), 10000::bigint,
  'A4: a FAILED refund does NOT defer — failed is terminal, and it means the buyer got nothing back (085:86-88), so the venue''s credit is real');
SELECT is(tap._cand159(tap._g159('sA'), tap._g159('rF')), 0,
  'A5: … and it books NO debit. Booking one would debit the venue for money that never left, permanently, in a ledger with no UPDATE and no DELETE (see C1-C3)');

SELECT ok(tap._amt159(tap._g159('sA'), 'primary_sale', tap._g159('oK')) = 10000
      AND tap._amt159(tap._g159('sA'), 'refund_void',  tap._g159('rK')) = -10000,
  'A6: a SUCCEEDED refund books BOTH — the +face credit and the offsetting debit, in the same close, netting to zero. Succeeded is the ONLY state in which the buyer actually has the money back');

SELECT ok(tap._amt159(tap._g159('sA'), 'primary_sale', tap._g159('oPart')) = 10000
      AND tap._amt159(tap._g159('sA'), 'refund_void',  tap._g159('rPart')) = -3000,
  'A7: a PARTIAL refund emits the full credit and a partial debit — never a naked negative (the adversarial X-5 shape: a debit with no matching revenue line drives the venue''s net below zero)');

SELECT is(tap._amt159(tap._g159('sA'), 'refund_void', tap._g159('rCap')), -10000::bigint,
  'A8: the debit is capped at the order''s FACE value, not the refund amount — a refund measured against payments.total carries the buyer-side service fee, which is platform money under ruling A5 and must not be subtracted from the venue''s entitlement');

SELECT cmp_ok((SELECT count(*)::int FROM kernel.settlement_primary_lines(tap._g159('sA'))), '>=', 5,
  'A9: deferral is per-ORDER, never per-settlement — the deferred orders do not freeze the venue''s unrelated revenue in the same close');

-- ============================================================================
-- SECTION B — RECONCILIATION IN BOTH DIRECTIONS. Deferral withholds an order's
--   face value; this section proves the withholding is TEMPORARY and that the
--   later close is arithmetically exact whichever way the refund resolves.
--   Deferral is only safe because it is recoverable: venue.open_settlement
--   (087:227) carries no uniqueness on scope, so a second settlement over the
--   same event is openable, and 10c's global indexes make double-crediting
--   unstorable.
-- ============================================================================
SELECT lives_ok($$ SELECT tap._close159(tap._g159('sA'), 'ck159-cA') $$,
  'B1: close #1 succeeds with two orders deferred');
SELECT ok(tap._lined159(tap._g159('oP')) = 0 AND tap._lined159(tap._g159('rP')) = 0,
  'B1a: … and the deferred order appears NOWHERE in the ledger — not as a credit, not as a debit, in any settlement');

-- the refund resolves. The executor's claim verb (10i) keeps claiming BOTH
-- non-terminal states forever, so this transition is the expected end state.
UPDATE kernel.refund SET status = 'submitted', stripe_refund_ref = 're_159_rP' WHERE refund_id = tap._g159('rP');
UPDATE kernel.refund SET status = 'succeeded' WHERE refund_id = tap._g159('rP');
UPDATE venue."order" SET status = 'refunded' WHERE order_id = tap._g159('oP');
SELECT tap._st159('sB', tap._open159('ck159-sB', tap._g159('event1'))::text);
SELECT lives_ok($$ SELECT tap._close159(tap._g159('sB'), 'ck159-cB') $$,
  'B2: a SECOND settlement over the same scope is openable and closable');
SELECT is(tap._lined159(tap._g159('oP')) + tap._lined159(tap._g159('rP')), 0::bigint,
  'B3: the once-deferred order now carries BOTH lines and contributes exactly ZERO — the credit and the debit land in the same close, so the deferral cost the venue nothing but time');

-- the mirror: oS's refund FAILS instead.
UPDATE kernel.refund SET status = 'failed' WHERE refund_id = tap._g159('rS');
SELECT tap._st159('sC', tap._open159('ck159-sC', tap._g159('event1'))::text);
SELECT tap._close159(tap._g159('sC'), 'ck159-cC');
SELECT ok(tap._lined159(tap._g159('oS')) = 10000 AND tap._lined159(tap._g159('rS')) = 0,
  'B4: THE MIRROR — a refund that FAILS after its order was deferred releases the credit ALONE. The buyer was not paid, so the venue''s face value is genuinely earned and no debit is owed');

-- ============================================================================
-- SECTION C — WHY (i) AND (ii) MUST BE PREVENTIVE. If a debit were ever booked
--   for a refund that later failed, this is the whole set of corrections the
--   schema can represent. Every arm below is closed, which is why the seam must
--   refuse to write the line in the first place rather than plan to reverse it.
-- ============================================================================
SELECT throws_ok(
  format($$UPDATE venue.settlement_line SET amount_minor = 0 WHERE cause = 'refund_void' AND cause_ref = %L$$, tap._g159('rK')),
  'P0001', NULL,
  'C1: a booked refund_void line cannot be AMENDED — venue.settlement_line is append-only (087:110-112)');
SELECT throws_ok(
  format($$DELETE FROM venue.settlement_line WHERE cause = 'refund_void' AND cause_ref = %L$$, tap._g159('rK')),
  'P0001', NULL,
  'C2: … and it cannot be WITHDRAWN either');
SELECT throws_ok(
  format($$INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor)
           VALUES (%L, 'refund_void', %L, 10000)$$, tap._g159('sC'), tap._g159('rK')),
  '23505', NULL,
  'C3: … and a COMPENSATING positive line under the same cause is unstorable platform-wide (settlement_one_refund_void_line_ever, 10c). The only representable reversal is a different cause, which would fabricate an act that never happened — so the seam must never write the line it cannot take back');

-- ============================================================================
-- SECTION D — THE COHORT. catalog.cancel_event (088:1612) inserts a refund for
--   EVERY order on the event in one statement, all born 'pending' (085:83), so
--   the deferral fires for the whole event at once rather than for one order.
--   That arm's refund cascade is ATOM-driven (088:1740-1780) and the atom
--   issuance path is 143/148's fixture surface, so this section reproduces
--   exactly what it leaves behind — one kernel.refund per order,
--   reason_code='event_cancelled', DEFAULT status — and asserts what the
--   settlement seam then does with it.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._st159('eventX', (catalog.create_event(tap._g159('venue1'),'Cancelled Night',
  jsonb_build_object('starts_at',(now() - interval '20 days')::text,
                     'ends_at',  (now() - interval '20 days' + interval '4 hours')::text),'ck159-eX') ->> 'event_id'));
SELECT tap._st159('sessX', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._g159('eventX')));
SELECT tap.logout();
SELECT tap._st159('xA', tap._ord159(tap._g159('sessX'), tap._g159('org1'), 10000, 1000, 'xA')::text);
SELECT tap._st159('xB', tap._ord159(tap._g159('sessX'), tap._g159('org1'),  6000,  600, 'xB')::text);
SELECT tap._st159('xC', tap._ord159(tap._g159('sessX'), tap._g159('org1'),  4000,  400, 'xC')::text);
SELECT tap._st159('rxA', tap._rf159(tap._g159('xA'), 10000, 'pending', 'rxA', 'event_cancelled')::text);
SELECT tap._st159('rxB', tap._rf159(tap._g159('xB'),  6000, 'pending', 'rxB', 'event_cancelled')::text);
SELECT tap._st159('rxC', tap._rf159(tap._g159('xC'),  4000, 'pending', 'rxC', 'event_cancelled')::text);
UPDATE catalog.event_session SET status = 'cancelled' WHERE session_id = tap._g159('sessX');
UPDATE catalog.event         SET status = 'cancelled' WHERE event_id   = tap._g159('eventX');

SELECT tap._st159('sX', tap._open159('ck159-sX', tap._g159('eventX'))::text);
SELECT is((SELECT count(*)::int FROM kernel.settlement_primary_lines(tap._g159('sX'))), 0,
  'D1: a cancelled event''s ENTIRE cohort is deferred at once — every order carries a pending event_cancelled refund, so the seam emits nothing at all rather than crediting revenue that is on its way back to the buyers');
SELECT is((tap._close159(tap._g159('sX'), 'ck159-cX') ->> 'net_minor')::bigint, 0::bigint,
  'D1a: … so the close nets ZERO and mints no payout, which is exactly what a fully-refunded event owes');

-- the ordinary outcome: most refunds settle, one does not.
UPDATE kernel.refund SET status = 'succeeded', stripe_refund_ref = 're_159_' || left(refund_id::text, 8)
 WHERE refund_id IN (tap._g159('rxA'), tap._g159('rxB'));
UPDATE kernel.refund SET status = 'failed',    stripe_refund_ref = 're_159_' || left(refund_id::text, 8)
 WHERE refund_id = tap._g159('rxC');
SELECT tap._st159('sX2', tap._open159('ck159-sX2', tap._g159('eventX'))::text);
SELECT tap._close159(tap._g159('sX2'), 'ck159-cX2');
SELECT is((SELECT net_minor::bigint FROM venue.settlement WHERE settlement_id = tap._g159('sX2')), 4000::bigint,
  'D2: once the cohort resolves, the venue is owed EXACTLY the face value of the order whose refund failed — three credits, two debits, and the buyer who was never paid is the only revenue the venue keeps');

SELECT * FROM finish();
ROLLBACK;
