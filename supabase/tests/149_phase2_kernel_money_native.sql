-- ============================================================================
-- 149_phase2_kernel_money_native.sql — Phase-2 package 085 suite.
--
-- Frozen sources: plan §8/085 · schema §1.8-§1.10a/§1.12.1 · RPC §6.3/§7.3/
-- §11.1-11.4/§17.1-17.9/§17.14/§20.7.x/§20.11.3/.5 · RLS §7.8-§7.10a + §11 ·
-- MONEY spec · OR-17/OR-21 · PFA-15/PFA-21/PFA-22 (owner-signed). D-3 keys are
-- ALL NULL-seeded: the suite proves the tier ladder FAILS CLOSED over NULL and
-- then sets values (as the owner will) to walk the dual-control loop.
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(108);

SELECT tap.seed_core();

CREATE TABLE tap.memo_149 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store149(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_149 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch149(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_149 WHERE k = $1 $m$;

-- ============================================================================
-- SECTION A — THE 085 CLOSED WORLD
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relkind='r'), 26,
  'A1: kernel holds 26 tables — 22 post-084 + the four money ledgers');
SELECT has_table('kernel'::name,'payment_native'::name, 'A2: kernel.payment_native (the R-34 link ledger)');
SELECT has_table('kernel'::name,'refund'::name, 'A3: kernel.refund');
SELECT has_table('kernel'::name,'payout'::name, 'A4: kernel.payout');
SELECT has_table('kernel'::name,'identity_obligation'::name, 'A5: kernel.identity_obligation (OR-21)');
SELECT has_function('venue'::name,'finalize_primary_order'::name, ARRAY['uuid','uuid','text','text']::name[],
  'A6: venue.finalize_primary_order is authored HERE (R2B/C111 — not 082)');
SELECT has_function('venue'::name,'resolve_order_attribution'::name, ARRAY['uuid']::name[],
  'A7: the resolve_order_attribution SEAM-2 stub (body 090)');
SELECT has_function('venue'::name,'on_payout_settled'::name, ARRAY['uuid']::name[],
  'A8: the on_payout_settled SEAM-2 stub (body 087)');
-- market's FIRST routine — three p_-prefixed params (C117/S2-B canonical)
SELECT is((SELECT p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='market' AND p.proname='on_atom_voided'),
  ARRAY['p_atom_id','p_refund_id','p_cause'],
  'A9: market.on_atom_voided — THREE params, p_-prefixed (SEAM-2a frozen; the 2-param summaries are stale)');
SELECT has_function('kernel'::name,'void_ticket_atom'::name, ARRAY['uuid','uuid','text']::name[],
  'A10: the void engine (SSCAS #3; FR-4 — born here with kernel.refund)');
SELECT hasnt_function('kernel'::name,'request_org_payout'::name, 'A11: request_org_payout is NOT here (087)');
SELECT hasnt_function('kernel'::name,'transfer_ticket_ownership'::name, 'A12: the transfer engine is NOT here (088)');
SELECT hasnt_table('market'::name,'market_sale'::name, 'A13: market.market_sale is NOT here (088)');
SELECT is((SELECT count(*)::int FROM pg_constraint WHERE conrelid='kernel.payment_native'::regclass
            AND contype='f' AND conname LIKE '%sale%'), 0,
  'A14: payment_native.sale_id carries NO FK — that is 089''s adopt step');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname='sweep-expired-refund-requests'), 1,
  'A15: the refund-TTL tick is scheduled (P0-1 — not optional)');
SELECT is((SELECT value FROM catalog.platform_config
            WHERE key='deletion.refund_possible_window_hours' AND version=1), 'null'::jsonb,
  'A16: PFA-22 — the dedicated BP-12 operand is seeded NULL / owner-unset');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 39,
  'A17: ZERO new policies — all four money tables are deny-all (GP-3a)');

-- ============================================================================
-- SECTION B — GRANTS & CUSTODY WALLS (PFA-15/PFA-21; RLS §7.8-§7.10a)
-- ============================================================================
SELECT ok(has_schema_privilege('service_role','venue','USAGE'),
  'B1: PFA-15 — service_role holds venue USAGE (the webhook path to finalize/cancel)');
SELECT ok(has_schema_privilege('service_role','kernel','USAGE'),
  'B2: PFA-21 — service_role holds kernel USAGE (the state-sync path)');
SELECT ok(NOT has_schema_privilege('anon','venue','USAGE') AND NOT has_schema_privilege('anon','kernel','USAGE'),
  'B3: anon is NOT widened by either ruling (PFA-14 intact)');
SELECT ok(NOT has_function_privilege('authenticated','venue.finalize_primary_order(uuid,uuid,text,text)','EXECUTE')
       AND NOT has_function_privilege('anon','venue.finalize_primary_order(uuid,uuid,text,text)','EXECUTE')
       AND has_function_privilege('service_role','venue.finalize_primary_order(uuid,uuid,text,text)','EXECUTE'),
  'B4: finalize is service_role-ONLY — "an authenticated grant here is the single highest-severity migration defect available in this schema"');
SELECT ok(NOT has_function_privilege('service_role','kernel.record_money_denial(text,text,uuid,text)','EXECUTE')
       AND has_function_privilege('authenticated','kernel.record_money_denial(text,text,uuid,text)','EXECUTE'),
  'B5: R-28 — the denial witness is authenticated-ONLY, never service_role');
SELECT ok(NOT has_table_privilege('authenticated','kernel.payment_native','SELECT')
       AND NOT has_column_privilege('authenticated','kernel.payment_native','instrument_fingerprint','SELECT'),
  'B6: the fingerprint column is unreachable by any client (C112/PROMO §1.8)');
SELECT ok(NOT has_table_privilege('authenticated','kernel.payout','SELECT'),
  'B7: kernel.payout has NO direct client read — list_org_payouts is the only path (¹⁵ᵇ)');
SELECT ok(NOT has_table_privilege('service_role','kernel.identity_obligation','DELETE'),
  'B8: identity_obligation: no DELETE ever (GP-2)');
SELECT ok((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
           WHERE n.nspname='kernel' AND c.relname='payment_native'
             AND p.proname='raise_append_only' AND NOT t.tgisinternal) = 1,
  'B9: payment_native carries the append-only guard (schema §1.8 "effectively AO" — E-50)');
SELECT ok(NOT has_function_privilege('authenticated','kernel.void_ticket_atom(uuid,uuid,text)','EXECUTE')
       AND NOT has_function_privilege('service_role','kernel.void_ticket_atom(uuid,uuid,text)','EXECUTE'),
  'B10: the void engine is definer-only — NO grant to any client or machine role');

-- ============================================================================
-- FIXTURE — org → venue → event → session → tt → batch → key → order+payment
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store149('org', (kernel.create_organization('Money Co','Money Co','ck85-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch149('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store149('venue', (catalog.create_venue(tap._fetch149('org')::uuid,'Money Hall','wynwood',NULL,'ck85-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch149('venue')::uuid,'approved','miami_gate','ck85-a');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store149('event', (catalog.create_event(tap._fetch149('venue')::uuid,'Money Night',
  jsonb_build_object('starts_at',(now()+interval '15 days')::text,'ends_at',(now()+interval '15 days 5 hours')::text),'ck85-e') ->> 'event_id'));
SELECT tap._store149('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch149('event')::uuid));
SELECT tap._store149('tt', (venue.create_ticket_type(tap._fetch149('event')::uuid,'admission','GA',5000,'public','ck85-tt') ->> 'ticket_type_id'));
SELECT tap._store149('batch', (venue.create_inventory_batch(tap._fetch149('tt')::uuid, tap._fetch149('session')::uuid, 'public_sale', 100, 0, 'ck85-b') ->> 'batch_id'));
SELECT tap.logout();
WITH insk AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch149('event')::uuid, 'PUBKEY-85', 'kms-85', 'active', now())
  RETURNING key_id
)
SELECT tap._store149('key', (SELECT key_id::text FROM insk));
-- the pending order + its item (direct facts; 082's checkout is not under test)
WITH inso AS (
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'pending', 'web', 10000, 'ck85-ord-1')
  RETURNING order_id
)
SELECT tap._store149('order', (SELECT order_id::text FROM inso));
WITH insi AS (
  INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor)
  VALUES (tap._fetch149('order')::uuid, tap._fetch149('tt')::uuid, 2, 5000)
  RETURNING id
)
SELECT tap._store149('item', (SELECT id::text FROM insi));
-- the buyer's live hold (E-40/E-47(b) substrate) + the batch counter
WITH insh AS (
  INSERT INTO venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  VALUES (tap._fetch149('batch')::uuid, tap.buyer(), 2, 'active', now() + interval '1 hour', 'ck85-h-1')
  RETURNING hold_id
)
SELECT tap._store149('hold', (SELECT hold_id::text FROM insh));
UPDATE venue.inventory_batch SET held = 2 WHERE batch_id = tap._fetch149('batch')::uuid;
-- the frozen public rail: a listing + a SUCCEEDED payment for the buyer
WITH insl AS (
  INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time,
                               ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
  VALUES (tap.seller(), 'Money Night', 'Money Hall', 'wynwood', (now()+interval '15 days')::date, '20:00',
          'GA', 2, 'mobile_transfer', 5000, 5000, 24, now()+interval '1 day', 'covers/fixture.jpg')
  RETURNING id
)
SELECT tap._store149('listing', (SELECT id::text FROM insl));
WITH insp AS (
  INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
  VALUES (tap._fetch149('listing')::uuid, tap.buyer(), tap.seller(), 9000, 1000, 10000, 'succeeded', 'buy_now')
  RETURNING id
)
SELECT tap._store149('payment', (SELECT id::text FROM insp));

-- ============================================================================
-- SECTION C — FINALIZE (SSCAS #1): darkness, refusals, the E-40/E-47(b) draw
-- ============================================================================
SELECT throws_ok(format($$SELECT venue.finalize_primary_order(%L, %L, 'ck85-f-1', 'fp-1')$$,
    tap._fetch149('order'), tap._fetch149('payment')),
  NULL, 'precondition_failed: feature_disabled',
  'C1: while native issuance is DARK the money path cannot mint (the 083 gate holds through finalize)');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
-- E-23 (085 arm): an ERASED buyer acquires NOTHING — the defensive twin
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.other_user(), 'ERASED')
ON CONFLICT (identity_id) DO UPDATE SET deletion_state = 'ERASED';
WITH inso2 AS (
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.other_user(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'pending', 'web', 5000, 'ck85-ord-erased')
  RETURNING order_id
)
SELECT tap._store149('order_erased', (SELECT order_id::text FROM inso2));
SELECT throws_ok(format($$SELECT venue.finalize_primary_order(%L, %L, 'ck85-f-e', NULL)$$,
    tap._fetch149('order_erased'), tap._fetch149('payment')),
  NULL, 'precondition_failed: buyer identity is erased — no acquisition',
  'C2: E-23 — an ERASED buyer is refused BEFORE any payment logic (the F-6 defensive twin)');
-- an unverified payment is refused
WITH insp2 AS (
  INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
  VALUES (tap._fetch149('listing')::uuid, tap.buyer(), tap.seller(), 9000, 1000, 10000, 'pending', 'buy_now')
  RETURNING id
)
SELECT tap._store149('payment_pending', (SELECT id::text FROM insp2));
SELECT throws_ok(format($$SELECT venue.finalize_primary_order(%L, %L, 'ck85-f-2', NULL)$$,
    tap._fetch149('order'), tap._fetch149('payment_pending')),
  NULL, NULL, 'C3: a non-succeeded payment is payment_unverified — money is the authority, and it must be real');
-- the happy path: money → tickets
SELECT is((venue.finalize_primary_order(tap._fetch149('order')::uuid, tap._fetch149('payment')::uuid,
           'ck85-f-3', 'fp-1') ->> 'status'), 'ok',
  'C4: finalize DRAWS — the only function that turns money into tickets');
SELECT is((SELECT count(*)::int FROM kernel.tickets t
            WHERE t.event_session_id = tap._fetch149('session')::uuid), 2,
  'C5: two atoms minted');
SELECT is((SELECT sold::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid), 2,
  'C6: sold += 2 (the mint leg)');
SELECT is((SELECT held::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid), 0,
  'C7: held -= 2 BEFORE the mint (E-47(b) — C27 never saw held+sold exceed capacity)');
SELECT is((SELECT status FROM venue.inventory_hold WHERE hold_id = tap._fetch149('hold')::uuid), 'converted',
  'C8: the live hold converted WHOLE (E-40 — no blind decrement, no split row)');
SELECT ok((SELECT pn.instrument_fingerprint = 'fp-1' AND pn.amount_minor = 10000 AND pn.order_id = tap._fetch149('order')::uuid
             FROM kernel.payment_native pn WHERE pn.payment_id = tap._fetch149('payment')::uuid),
  'C9: the payment link carries the fingerprint (C112 — written by its contracted writer)');
SELECT is((SELECT status FROM venue."order" WHERE order_id = tap._fetch149('order')::uuid), 'paid',
  'C10: order → paid');
SELECT is((venue.finalize_primary_order(tap._fetch149('order')::uuid, tap._fetch149('payment')::uuid,
           'ck85-f-3', 'fp-1') ->> 'status'), 'idempotency_replay',
  'C11: webhook redelivery returns the ORIGINAL atom set — no second mint');
SELECT ok((SELECT count(*)::int FROM kernel.tickets t WHERE t.event_session_id = tap._fetch149('session')::uuid) = 2
       AND (SELECT sold::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid) = 2,
  'C12: …and the replay moved NOTHING (atoms 2, sold 2)');
SELECT ok(to_regclass('venue.attribution') IS NULL,
  'C13: T-SCHEMA-ISSUE-02/-03 — the purchase COMMITTED with NO attribution substrate: the stub never raised and could not have written (table+body are 090''s)');

-- ============================================================================
-- SECTION D — THE REFUND EXECUTOR (§11.4): platform authority, voids, Σ-guard
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.refund_primary_order(gen_random_uuid(), 100, 'buyer_request', 'ck85-r-x')$$,
  '42501', NULL, 'D1: the executor refuses a plain buyer — platform or an APPROVED request only');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT is((kernel.refund_primary_order(tap._fetch149('order')::uuid, 10000, 'admin_action', 'ck85-r-1') ->> 'status'),
  'ok', 'D2: platform_admin executes a full refund');
SELECT tap._store149('refund', (SELECT r.refund_id::text FROM kernel.refund r WHERE r.idempotency_key='ck85-r-1'));
SELECT tap.logout();
SELECT ok((SELECT bool_and(t.state = 'voided' AND t.current_owner_id = '00000000-0000-0000-0000-0000000000f0'
                           AND t.credential_version = 1)
             FROM kernel.tickets t WHERE t.event_session_id = tap._fetch149('session')::uuid),
  'D3: both atoms voided — SN-VOID holds them, credential bumped (S-18/C107)');
SELECT is((SELECT sold::int FROM venue.inventory_batch WHERE batch_id = tap._fetch149('batch')::uuid), 0,
  'D4: the inventory came back (sold -= 2 via the void engine)');
SELECT is((SELECT count(*)::int FROM venue.inventory_movement m
            WHERE m.batch_id = tap._fetch149('batch')::uuid AND m.movement_kind='void_return'), 2,
  'D5: two void_return movements (one per atom — the AO ledger balances)');
SELECT is((SELECT status FROM venue."order" WHERE order_id = tap._fetch149('order')::uuid), 'refunded',
  'D6: order → refunded (full coverage)');
SELECT is((SELECT r.status FROM kernel.refund r WHERE r.refund_id = tap._fetch149('refund')::uuid), 'pending',
  'D7: the refund ledger row is born pending (the Stripe leg is the edge''s — never the DB''s)');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.refund_primary_order(tap._fetch149('order')::uuid, 10000, 'admin_action', 'ck85-r-1') ->> 'status'),
  'idempotency_replay', 'D8: the executor replays by idempotency_key — no double refund');
SELECT throws_ok(format($$SELECT kernel.refund_primary_order(%L, 1, 'admin_action', 'ck85-r-2')$$, tap._fetch149('order')),
  NULL, NULL, 'D9: one more cent exceeds the payment — over_refund (the Σ-guard under the payment lock)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit
            WHERE action='refund.issue' AND subject_id = tap._fetch149('order')::uuid), 1,
  'D10: the refund is admin-audited in-txn');
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.force_void_ticket(gen_random_uuid(), 'r', 'ck85-fv-x')$$,
  '42501', NULL, 'D11: force_void refuses a non-platform caller');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT kernel.force_void_ticket(%L, 'test', 'ck85-fv-1')$$,
    (SELECT t.ticket_atom_id::text FROM kernel.tickets t WHERE t.event_session_id = tap._fetch149('session')::uuid LIMIT 1)),
  NULL, NULL, 'D12: force-voiding an ALREADY-voided atom is a state_conflict — terminals are exclusive');
SELECT tap.logout();

-- ============================================================================
-- SECTION E — THE DUAL-CONTROL LOOP (§17.1-§17.4): NULL keys fail closed, then
--   the owner sets values and the ladder walks.
-- ============================================================================
-- a second paid order + minted atoms for the request path
WITH inso3 AS (
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'pending', 'web', 10000, 'ck85-ord-2')
  RETURNING order_id
)
SELECT tap._store149('order2', (SELECT order_id::text FROM inso3));
WITH insi2 AS (
  INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor)
  VALUES (tap._fetch149('order2')::uuid, tap._fetch149('tt')::uuid, 2, 5000)
  RETURNING id
)
SELECT tap._store149('item2', (SELECT id::text FROM insi2));
WITH insp3 AS (
  INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
  VALUES (tap._fetch149('listing')::uuid, tap.buyer(), tap.seller(), 9000, 1000, 10000, 'succeeded', 'buy_now')
  RETURNING id
)
SELECT tap._store149('payment2', (SELECT id::text FROM insp3));
SELECT venue.finalize_primary_order(tap._fetch149('order2')::uuid, tap._fetch149('payment2')::uuid, 'ck85-f-4', NULL);

-- E1: C61 — a parked request with an UNSET TTL cannot mint an immortal hold
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.request_order_refund(%L, ARRAY(SELECT t.ticket_atom_id FROM kernel.tickets t
      JOIN kernel.ticket_ownership_log l1 ON l1.ticket_atom_id=t.ticket_atom_id AND l1.sequence=1
      WHERE l1.cause_ref = %L::uuid), 10000, 'buyer_request', 'ck85-q-0')$$,
    tap._fetch149('order2'), tap._fetch149('item2')),
  NULL, NULL, 'E1: ALL D-3 keys NULL → the parked branch refuses config_unset (nothing auto-executes, nothing parks unbounded)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('refund.request_ttl_hours', 2, '24'::jsonb, 'restricted');
-- E2: with a TTL, the buyer parks to the STRICTEST class (amount keys still NULL)
SELECT tap.login(tap.buyer());
SELECT tap._store149('req1_res', (kernel.request_order_refund(tap._fetch149('order2')::uuid,
    ARRAY(SELECT t.ticket_atom_id FROM kernel.tickets t
          JOIN kernel.ticket_ownership_log l1 ON l1.ticket_atom_id=t.ticket_atom_id AND l1.sequence=1
          WHERE l1.cause_ref = tap._fetch149('item2')::uuid),
    10000, 'buyer_request', 'ck85-q-1'))::text);
SELECT tap.logout();
SELECT is((tap._fetch149('req1_res')::jsonb ->> 'status'), 'parked',
  'E2: NULL amount keys → the buyer request PARKS (no self-service tier exists yet)');
SELECT is((tap._fetch149('req1_res')::jsonb ->> 'required_approver_class'), 'platform',
  'E3: …to the STRICTEST class — platform (NULL org_dual authorizes nothing)');
SELECT tap._store149('req1', (tap._fetch149('req1_res')::jsonb ->> 'request_id'));
SELECT ok((SELECT bool_and(t.resale_state = 'refund_hold')
             FROM kernel.tickets t
             JOIN kernel.ticket_ownership_log l1 ON l1.ticket_atom_id=t.ticket_atom_id AND l1.sequence=1
            WHERE l1.cause_ref = tap._fetch149('item2')::uuid),
  'E4: the refund_hold overlay landed on the targeted atoms');
-- E5: SoD-2 — the requester can never decide their own token
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L, 'approve', 'r', 'ck85-ap-x')$$, tap._fetch149('req1')),
  NULL, NULL, 'E5: self_approval — the requester cannot decide their own request');
SELECT tap.logout();
-- E6: a platform-class request refuses an org approver outright
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by)
VALUES (tap._fetch149('org')::uuid, tap.other_user(), 'org_finance', tap.seller())
ON CONFLICT DO NOTHING;
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.other_user();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L, 'approve', 'r', 'ck85-ap-y')$$, tap._fetch149('req1')),
  '42501', NULL, 'E6: a platform-class request is NOT approvable by org money roles (AUTHZ-C1A branch table)');
SELECT tap.logout();
-- E7: deny (platform) — reason mandatory, holds release
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L, 'deny', '', 'ck85-ap-0')$$, tap._fetch149('req1')),
  NULL, NULL, 'E7: a denial without a reason is refused (the denial carries its reason)');
SELECT is((kernel.approve_refund_request(tap._fetch149('req1')::uuid, 'deny', 'not_warranted', 'ck85-ap-1') ->> 'status'),
  'denied', 'E8: platform denies the parked request');
SELECT tap.logout();
SELECT ok((SELECT bool_and(t.resale_state = 'none')
             FROM kernel.tickets t
             JOIN kernel.ticket_ownership_log l1 ON l1.ticket_atom_id=t.ticket_atom_id AND l1.sequence=1
            WHERE l1.cause_ref = tap._fetch149('item2')::uuid),
  'E9: …and the refund_hold overlays released on denial');
-- E10-E13: the ORG dual-control arm — owner sets org_dual, maturity gates, then executes
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('refund.org_dual_control_max_minor', 2, '50000'::jsonb, 'restricted');
SELECT tap.login(tap.buyer());
SELECT tap._store149('req2_res', (kernel.request_order_refund(tap._fetch149('order2')::uuid,
    ARRAY(SELECT t.ticket_atom_id FROM kernel.tickets t
          JOIN kernel.ticket_ownership_log l1 ON l1.ticket_atom_id=t.ticket_atom_id AND l1.sequence=1
          WHERE l1.cause_ref = tap._fetch149('item2')::uuid),
    10000, 'buyer_request', 'ck85-q-2'))::text);
SELECT tap.logout();
SELECT is((tap._fetch149('req2_res')::jsonb ->> 'required_approver_class'), 'org',
  'E10: with org_dual set (50000), a 10000 request parks to the ORG class');
SELECT tap._store149('req2', (tap._fetch149('req2_res')::jsonb ->> 'request_id'));
-- immature org grant → sod_violation (C58; authn.money_role_maturity_hours = 72 seeded)
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT kernel.approve_refund_request(%L, 'approve', 'ok', 'ck85-ap-2')$$, tap._fetch149('req2')),
  NULL, NULL, 'E11: an IMMATURE org money grant fails as sod_violation (C58 — maturity gates authority, 72h seed)');
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now() - interval '100 hours'
 WHERE org_id = tap._fetch149('org')::uuid AND identity_id = tap.other_user();
SELECT tap.login(tap.other_user());
SELECT tap._store149('ap2_res', (kernel.approve_refund_request(tap._fetch149('req2')::uuid, 'approve', 'ok', 'ck85-ap-3'))::text);
SELECT tap.logout();
SELECT is((tap._fetch149('ap2_res')::jsonb ->> 'status'), 'approved',
  'E12: the MATURED org approver completes dual control — the refund EXECUTES');
SELECT is((SELECT status FROM venue."order" WHERE order_id = tap._fetch149('order2')::uuid), 'refunded',
  'E13: …order2 is refunded through the approved request (delegated authority, not role bypass)');
-- E14: the expiry sweep releases what the TTL bounds
WITH inso4 AS (
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), tap._fetch149('session')::uuid, tap._fetch149('org')::uuid, 'paid', 'web', 4000, 'ck85-ord-3')
  RETURNING order_id
)
SELECT tap._store149('order3', (SELECT order_id::text FROM inso4));
WITH insp4 AS (
  INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode)
  VALUES (tap._fetch149('listing')::uuid, tap.buyer(), tap.seller(), 3600, 400, 4000, 'succeeded', 'buy_now')
  RETURNING id
)
SELECT tap._store149('payment3', (SELECT id::text FROM insp4));
INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor)
VALUES (tap._fetch149('payment3')::uuid, tap._fetch149('order3')::uuid, 4000);
SELECT tap.login(tap.buyer());
SELECT tap._store149('req3', ((kernel.request_order_refund(tap._fetch149('order3')::uuid, '{}'::uuid[],
    4000, 'buyer_request', 'ck85-q-3'))::jsonb ->> 'request_id'));
SELECT tap.logout();
UPDATE kernel.approval_request SET expires_at = now() - interval '1 minute'
 WHERE request_id = tap._fetch149('req3')::uuid;
SELECT ok(((kernel.sweep_expired_refund_requests()) ->> 'swept_count')::int >= 1,
  'E14: the TTL sweep expires the stale request (P0-1 — no immortal holds)');
SELECT is((SELECT state FROM kernel.approval_request WHERE request_id = tap._fetch149('req3')::uuid), 'expired',
  'E15: …state = expired, audited, notice emitted');
-- E16: cancel path
SELECT tap.login(tap.buyer());
SELECT tap._store149('req4', ((kernel.request_order_refund(tap._fetch149('order3')::uuid, '{}'::uuid[],
    4000, 'buyer_request', 'ck85-q-4'))::jsonb ->> 'request_id'));
SELECT is((kernel.cancel_refund_request(tap._fetch149('req4')::uuid, 'changed_mind', 'ck85-c-1') ->> 'status'),
  'cancelled', 'E16: the requester cancels their own pending request (no maturity conjunct — S-3)');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — PAYOUT HOLDS + STATE SYNC (MB-2; §20.7.6)
-- ============================================================================
WITH inspo AS (
  INSERT INTO kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('organization', tap._fetch149('org')::uuid, 'settlement', gen_random_uuid(), 20000, 'submitted', 'ck85-po-1')
  RETURNING payout_id
)
SELECT tap._store149('payout', (SELECT payout_id::text FROM inspo));
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.hold_payout(%L, 'risk', 'ck85-h-x')$$, tap._fetch149('payout')),
  '42501', NULL, 'F1: hold_payout refuses non-platform callers');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT is((kernel.hold_payout(tap._fetch149('payout')::uuid, 'risk_review', 'ck85-h-1') ->> 'status'), 'ok',
  'F2: platform holds the payout');
SELECT tap.logout();
SELECT ok((SELECT p.hold_state = 'held' AND p.status = 'submitted' AND p.held_by IS NOT NULL
             FROM kernel.payout p WHERE p.payout_id = tap._fetch149('payout')::uuid),
  'F3: the hold is the FOUR-COLUMN overlay — status untouched (S-15/C105)');
SELECT throws_ok(format($$SELECT kernel.mark_payout_transfer_state(%L, 'paid', 'tr_1', NULL, 'ck85-m-1')$$, tap._fetch149('payout')),
  NULL, 'precondition_failed: payout_held',
  'F4: a HELD payout refuses the webhook sync (Control-4 cannot be undone by Stripe)');
SELECT ok((SELECT p.status = 'submitted' AND p.stripe_transfer_ref IS NULL
             FROM kernel.payout p WHERE p.payout_id = tap._fetch149('payout')::uuid),
  'F5: …and BOTH columns are untouched (T-SCHEMA-PAYOUT-06 — zero mutation on refusal)');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.release_payout(tap._fetch149('payout')::uuid, 'ck85-rel-1') ->> 'status'), 'ok',
  'F6: platform releases the hold');
SELECT tap.logout();
SELECT ok((SELECT p.hold_state = 'none' AND p.hold_reason_code IS NULL AND p.held_by IS NULL AND p.held_at IS NULL
             FROM kernel.payout p WHERE p.payout_id = tap._fetch149('payout')::uuid),
  'F7: …all four hold columns cleared together (the pairing CHECK holds)');
SELECT is((kernel.mark_payout_transfer_state(tap._fetch149('payout')::uuid, 'paid', 'tr_1', NULL, 'ck85-m-2') ->> 'status'),
  'ok', 'F8: the executor syncs paid (form (a), O16) — the settlement hook fires as a no-op stub');
SELECT is((kernel.mark_payout_transfer_state(tap._fetch149('payout')::uuid, 'paid', 'tr_1', NULL, 'ck85-m-3') ->> 'status'),
  'noop_replay', 'F9: the same sync replays as a noop — never a raise');
SELECT throws_ok(format($$SELECT kernel.mark_payout_transfer_state(%L, 'failed', 'tr_1', 'x', 'ck85-m-4')$$, tap._fetch149('payout')),
  NULL, NULL, 'F10: paid → failed is BACKWARDS (payout_state_backwards)');
SELECT is((kernel.mark_payout_transfer_state(tap._fetch149('payout')::uuid, 'reversed', 'tr_1', NULL, 'ck85-m-5') ->> 'status'),
  'ok', 'F11: paid → reversed is the ONE legal terminal-to-terminal edge');

-- ============================================================================
-- SECTION G — REFUND STATE SYNC (§20.7.7; S-24)
-- ============================================================================
SELECT is((kernel.mark_refund_state(tap._fetch149('refund')::uuid, 'submitted', 're_1', NULL, 'ck85-rs-1') ->> 'status'),
  'ok', 'G1: pending → submitted (the ref is mandatory — non-pending rows carry it)');
SELECT throws_ok(format($$SELECT kernel.mark_refund_state(%L, 'succeeded', 're_DIFFERENT', NULL, 'ck85-rs-2')$$, tap._fetch149('refund')),
  NULL, NULL, 'G2: the stripe ref is WRITE-ONCE — a different ref is conflict_locked');
SELECT is((kernel.mark_refund_state(tap._fetch149('refund')::uuid, 'succeeded', 're_1', NULL, 'ck85-rs-3') ->> 'status'),
  'ok', 'G3: submitted → succeeded');
SELECT throws_ok(format($$SELECT kernel.mark_refund_state(%L, 'submitted', 're_1', NULL, 'ck85-rs-4')$$, tap._fetch149('refund')),
  NULL, NULL, 'G4: succeeded → submitted is BACKWARDS (refund_state_backwards)');
SELECT throws_ok(format($$UPDATE kernel.refund SET stripe_refund_ref = NULL WHERE refund_id = %L$$, tap._fetch149('refund')),
  '23514', NULL, 'G5: the S-24 pairing CHECK makes a ref-less non-pending row UNSTORABLE');

-- ============================================================================
-- SECTION H — OBLIGATIONS (OR-21) + BP-10
-- ============================================================================
SELECT tap._store149('oref', gen_random_uuid()::text);
SELECT is((kernel.record_identity_obligation(tap.other_user(), 'chargeback', tap._fetch149('oref')::uuid,
    'dp_1', 500, 'cb', 'ck85-ob-1') ->> 'status'), 'ok',
  'H1: the machine records an obligation (no debtor-state precondition — Q2 works on ERASED too)');
SELECT is((kernel.record_identity_obligation(tap.other_user(), 'chargeback', tap._fetch149('oref')::uuid,
    'dp_1', 500, 'cb', 'ck85-ob-1') ->> 'status'), 'noop_replay',
  'H2: (origin_kind, origin_ref) replays as a noop — one obligation per origin fact');
SELECT is(kernel.has_outstanding_obligations(tap.other_user()), true,
  'H3: BP-10 — the REAL body sees the outstanding debt (the 077 stub said false)');
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.resolve_identity_obligation(gen_random_uuid(), 'recovered', 'r', 'ck85-ob-x')$$,
  '42501', NULL, 'H4: resolve refuses non-platform callers');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT tap._store149('oblig', (SELECT o.obligation_id::text FROM kernel.identity_obligation o
                                WHERE o.origin_ref = tap._fetch149('oref')::uuid));
SELECT is((kernel.resolve_identity_obligation(tap._fetch149('oblig')::uuid, 'recovered', 'paid_back', 'ck85-ob-2') ->> 'status'),
  'ok', 'H5: platform resolves the obligation');
SELECT is((kernel.resolve_identity_obligation(tap._fetch149('oblig')::uuid, 'recovered', 'paid_back', 'ck85-ob-3') ->> 'status'),
  'noop_replay', 'H6: the same terminal replays as a noop');
SELECT throws_ok(format($$SELECT kernel.resolve_identity_obligation(%L, 'written_off', 'w', 'ck85-ob-4')$$, tap._fetch149('oblig')),
  NULL, NULL, 'H7: a DIFFERENT terminal is state_conflict — terminals are exclusive');
SELECT tap.logout();
SELECT is(kernel.has_outstanding_obligations(tap.other_user()), false,
  'H8: …and BP-10 clears');

-- ============================================================================
-- SECTION I — DELETION BLOCKERS (BP-5/BP-6/BP-12 + PFA-22)
-- ============================================================================
WITH inspi AS (
  INSERT INTO kernel.payout (payee_kind, payee_identity_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('identity', tap.buyer(), 'refund_void', gen_random_uuid(), 700, 'submitted', 'ck85-po-2')
  RETURNING payout_id
)
SELECT tap._store149('payout_id2', (SELECT payout_id::text FROM inspi));
SELECT ok(kernel.deletion_blockers_money(tap.buyer()) LIKE 'BP-5%',
  'I1: an unsettled identity payout blocks the tombstone (BP-5)');
SELECT kernel.mark_payout_transfer_state(tap._fetch149('payout_id2')::uuid, 'paid', 'tr_2', NULL, 'ck85-m-6');
-- order3 is still 'paid' (its requests expired/cancelled, never refunded) → a
-- BP-12 candidate exists → the PFA-22 NULL window BLOCKS
SELECT ok(kernel.deletion_blockers_money(tap.buyer()) LIKE 'BP-12%window unset%',
  'I2: PFA-22 — candidate orders + NULL window ⇒ BLOCKED (fail-closed exactly when it must be)');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('deletion.refund_possible_window_hours', 2, '0'::jsonb, 'restricted');
SELECT is(kernel.deletion_blockers_money(tap.buyer()), NULL,
  'I3: …the owner sets the window (0h) and the candidate falls OUTSIDE it — deletion unblocked (NULL never blocked without candidates)');
SELECT is(kernel.deletion_blockers_money(tap.other_user()), NULL,
  'I4: an identity with NO candidates and NO money facts is never blocked by the NULL key (the owner''s scoping verbatim)');

-- ============================================================================
-- SECTION J — Q5 RELEASE (OR-17): the deleting identity's parked requests
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT tap._store149('req5', ((kernel.request_order_refund(tap._fetch149('order3')::uuid, '{}'::uuid[],
    4000, 'buyer_request', 'ck85-q-5'))::jsonb ->> 'request_id'));
SELECT tap.logout();
SELECT lives_ok(format($$SELECT kernel.on_deletion_q5_release(%L)$$, tap.buyer()),
  'J1: the Q5 release runs (§17.4 semantics on the identity''s set)');
SELECT is((SELECT state FROM kernel.approval_request WHERE request_id = tap._fetch149('req5')::uuid), 'expired',
  'J2: …the deleting identity''s pending request is expired');
SELECT is((SELECT count(*)::int FROM kernel.tickets t
            WHERE t.current_owner_id = tap.buyer() AND t.resale_state = 'refund_hold'), 0,
  'J3: …and no refund_hold overlay survives on their atoms');

-- ============================================================================
-- SECTION K — THE DENIAL WITNESS (§17.9; R-28; T-SCHEMA-AUDIT-01/-02)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT is((kernel.record_money_denial('refund.request', 'order', tap._fetch149('order')::uuid, 'insufficient_privilege') ->> 'status'),
  'ok', 'K1: an authenticated human records their denial');
SELECT throws_ok($$SELECT kernel.record_money_denial('rm -rf', 'order', gen_random_uuid(), 'x')$$,
  NULL, NULL, 'K2: the action vocabulary is CLOSED — arbitrary strings are refused');
SELECT tap.logout();
SELECT throws_ok(format($$SELECT kernel.record_money_denial('refund.request', 'order', %L, 'x')$$, tap._fetch149('order')),
  '42501', NULL, 'K3: T-SCHEMA-AUDIT-01 — with NO human principal (auth.uid() NULL) the witness RAISES; no parameter can set the actor');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit
            WHERE action = 'refund.request.denied' AND actor_identity = tap.buyer()), 1,
  'K4: the denial row is attributed to auth.uid() and nothing else');

-- ============================================================================
-- SECTION L — PAYOUT DESTINATION (§17.7; SoD-1; AUTHZ-M4)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.set_org_payout_destination(%L, 'acct_X1', 'r', 'ck85-d-x')$$, tap._fetch149('org')),
  '42501', NULL, 'L1: only org_owner may touch the destination (SoD-1 — finance excluded)');
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now() - interval '100 hours'
 WHERE org_id = tap._fetch149('org')::uuid AND identity_id = tap.seller();
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT kernel.set_org_payout_destination(%L, 'acct_X1', 'r', 'ck85-d-0')$$, tap._fetch149('org')),
  NULL, NULL, 'L2: a session with NO aal claim is step_up_unavailable — never evaluated as satisfied (AUTHZ-M4)');
SELECT set_config('request.jwt.claims',
  (current_setting('request.jwt.claims', true)::jsonb || '{"aal":"aal1"}'::jsonb)::text, true);
SELECT throws_ok(format($$SELECT kernel.set_org_payout_destination(%L, 'acct_X1', 'r', 'ck85-d-1')$$, tap._fetch149('org')),
  NULL, NULL, 'L3: aal1 is step_up_required — money-destination changes demand the step-up');
SELECT set_config('request.jwt.claims',
  (current_setting('request.jwt.claims', true)::jsonb || '{"aal":"aal2"}'::jsonb)::text, true);
SELECT is((kernel.set_org_payout_destination(tap._fetch149('org')::uuid, 'acct_NEW1', 'rotation', 'ck85-d-2') ->> 'status'),
  'ok', 'L4: matured org_owner + aal2 changes the destination');
SELECT tap.logout();
SELECT ok((SELECT o.stripe_connect_account_ref = 'acct_NEW1' AND o.payout_destination_set_by = tap.seller()
             FROM kernel.organization o WHERE o.org_id = tap._fetch149('org')::uuid),
  'L5: …the setter is recorded — the §8.2 SoD exclusion now binds them at approval time');

SELECT finish();
ROLLBACK;
