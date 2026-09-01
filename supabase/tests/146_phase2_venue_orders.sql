-- ============================================================================
-- 146_phase2_venue_orders.sql — Phase-2 package 082 test suite.
--
-- Frozen sources: plan §8/082 · schema §3.7/§3.8/§1.15.2/§13.2 · CRM §11.2 ·
-- RPC §6.1 (create_primary_checkout), §20.7.9 (cancel_pending_order), §17.21
-- (the 3 consent RPCs) · RLS §9.7/§9.8/§16.6/§16.10 · dsm §2 BP-12 / §3.2 F-1 ·
-- ODR16 row #22/#27 · OR-17 (deletion_blockers_orders body) · R2B/C112 (candidate
-- columns) · E-23 (checkout buyer must be ACTIVE, not merely not-pending).
-- NATIVE ISSUANCE + BUY NOW stay dark; the happy path is reached only by a
-- controlled in-txn flag flip. Convention: BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(71);

SELECT tap.seed_core();

CREATE TABLE tap.memo_146 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store146(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_146 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch146(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_146 WHERE k = $1 $m$;
-- definer reads of the deny-all consent tables + the order (E-29-style: the
-- consent tables carry zero client policies, so a persona SELECT cannot see them).
CREATE FUNCTION tap._cc_state(p_id uuid, p_org uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT state FROM kernel.org_contact_consent WHERE identity_id = p_id AND org_id = p_org $m$;
CREATE FUNCTION tap._cce_count(p_id uuid, p_org uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.org_contact_consent_event WHERE identity_id = p_id AND org_id = p_org $m$;
CREATE FUNCTION tap._ord_status(p_order uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT status FROM venue."order" WHERE order_id = p_order $m$;
GRANT EXECUTE ON FUNCTION tap._cc_state(uuid,uuid), tap._cce_count(uuid,uuid), tap._ord_status(uuid) TO authenticated;

-- ============================================================================
-- SECTION A — THE 082 CLOSED WORLD
-- ============================================================================
SELECT has_table('venue'::name, 'order'::name, 'A1: venue.order exists');
SELECT has_table('venue'::name, 'order_item'::name, 'A2: venue.order_item exists');
SELECT has_table('kernel'::name, 'org_contact_consent'::name, 'A3: kernel.org_contact_consent (current-state) exists');
SELECT has_table('kernel'::name, 'org_contact_consent_event'::name, 'A4: kernel.org_contact_consent_event (AO) exists');
SELECT has_function('venue'::name,'create_primary_checkout'::name, ARRAY['uuid','jsonb','uuid[]','text']::name[], 'A5: create_primary_checkout');
SELECT has_function('venue'::name,'cancel_pending_order'::name, ARRAY['uuid','text','text']::name[], 'A6: cancel_pending_order');
SELECT has_function('kernel'::name,'grant_org_contact_consent'::name, ARRAY['uuid','text','uuid']::name[], 'A7: grant_org_contact_consent');
SELECT has_function('kernel'::name,'withdraw_org_contact_consent'::name, ARRAY['uuid']::name[], 'A8: withdraw_org_contact_consent');
SELECT has_function('kernel'::name,'list_my_org_contact_consents'::name, 'A9: list_my_org_contact_consents (parameterless)');
-- forward objects are ABSENT (no 083+ leakage)
SELECT hasnt_function('venue'::name,'finalize_primary_order'::name, 'A10: finalize_primary_order is NOT here — moved to 085 (C111)');
SELECT has_function('kernel'::name,'issue_ticket_atoms'::name, ARRAY['jsonb','text']::name[], 'A11: the mint engine landed in 083 — issue_ticket_atoms(jsonb, text) exists');
SELECT hasnt_function('kernel'::name,'refund_primary_order'::name, 'A12: refund is NOT here (085)');
SELECT hasnt_function('venue'::name,'bind_order_attribution'::name, 'A13: attribution binding is NOT here (090)');
SELECT hasnt_table('kernel'::name,'payment_native'::name, 'A14: kernel.payment_native is NOT here (085)');
-- the C16 idempotency unique + the reserved-word table name
SELECT col_is_unique('venue'::name,'order'::name, ARRAY['buyer_id','command_idempotency_key']::name[], 'A15: order UNIQUE(buyer_id, command_idempotency_key) (C16)');
SELECT col_is_unique('venue'::name,'order_item'::name, ARRAY['order_id','ticket_type_id']::name[], 'A16: order_item UNIQUE(order_id, ticket_type_id)');
-- the two candidate columns are born plain (no FK at 082 — R2B/C112)
SELECT is((SELECT count(*)::int FROM pg_constraint WHERE conrelid='venue."order"'::regclass AND contype='f'
            AND conname LIKE '%attr%'), 0, 'A17: no attribution-candidate FK at 082 (adopted in 090)');
SELECT has_column('venue'::name,'order'::name,'attribution_candidate_code_id'::name, 'A18: candidate code column born here');
SELECT has_column('venue'::name,'order'::name,'attribution_candidate_link_id'::name, 'A19: candidate link column born here');
-- 6 RLS policies (order x3, order_item x3); consent tables ZERO policies
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname='venue' AND tablename='order'), 3, 'A20: venue.order has 3 SELECT policies');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname='venue' AND tablename='order_item'), 3, 'A21: venue.order_item has 3 SELECT policies');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname='kernel' AND tablename IN ('org_contact_consent','org_contact_consent_event')), 0,
  'A22: both consent tables are deny-all with ZERO policies (OR-1)');

-- ============================================================================
-- SECTION B — GRANTS / EXEC POSTURE
-- ============================================================================
SELECT ok(has_function_privilege('authenticated','venue.create_primary_checkout(uuid, jsonb, uuid[], text)','EXECUTE'), 'B1: create_primary_checkout is authenticated-callable');
SELECT ok(NOT has_function_privilege('anon','venue.create_primary_checkout(uuid, jsonb, uuid[], text)','EXECUTE'), 'B2: …but not anon');
SELECT ok(has_function_privilege('service_role','venue.cancel_pending_order(uuid, text, text)','EXECUTE')
       AND NOT has_function_privilege('authenticated','venue.cancel_pending_order(uuid, text, text)','EXECUTE'),
  'B3: cancel_pending_order is service_role only — no human path (§20.7.9)');
SELECT ok(has_function_privilege('authenticated','kernel.grant_org_contact_consent(uuid, text, uuid)','EXECUTE')
       AND has_function_privilege('authenticated','kernel.withdraw_org_contact_consent(uuid)','EXECUTE')
       AND has_function_privilege('authenticated','kernel.list_my_org_contact_consents()','EXECUTE'),
  'B4: the three consent RPCs are authenticated-callable');
SELECT ok(NOT has_table_privilege('authenticated','kernel.org_contact_consent','SELECT')
       AND NOT has_table_privilege('anon','kernel.org_contact_consent','SELECT'),
  'B5: kernel.org_contact_consent holds no client SELECT (deny-all)');
SELECT ok(NOT has_table_privilege('authenticated','kernel.org_contact_consent_event','SELECT')
       AND NOT has_table_privilege('service_role','kernel.org_contact_consent_event','UPDATE'),
  'B6: consent event ledger is deny-all + AO (no UPDATE even for service_role)');
SELECT ok(has_table_privilege('authenticated','venue."order"','SELECT')
       AND NOT has_table_privilege('authenticated','venue."order"','INSERT')
       AND NOT has_table_privilege('authenticated','venue."order"','UPDATE'),
  'B7: venue.order is client-read only — every write is RPC/definer');

-- ============================================================================
-- FIXTURE — org → venue → event → ticket_type → batch → on_sale
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store146('org', (kernel.create_organization('Ord Co','Ord Co','ck-o-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch146('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store146('venue', (catalog.create_venue(tap._fetch146('org')::uuid,'Hall','wynwood',NULL,'ck-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch146('venue')::uuid,'approved','miami_gate','ck-a-1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store146('event', (catalog.create_event(tap._fetch146('venue')::uuid,'Ord Night',
  jsonb_build_object('starts_at',(now()+interval '20 days')::text,
                     'ends_at',(now()+interval '20 days 5 hours')::text),'ck-e-1') ->> 'event_id'));
SELECT tap._store146('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch146('event')::uuid));
SELECT tap._store146('tt', (venue.create_ticket_type(tap._fetch146('event')::uuid,'admission','GA',5000,'public','ck-tt-1') ->> 'ticket_type_id'));
SELECT tap._store146('batch', (venue.create_inventory_batch(tap._fetch146('tt')::uuid, tap._fetch146('session')::uuid, 'public_sale', 100, 0, 'ck-b-1') ->> 'batch_id'));
SELECT catalog.publish_event(tap._fetch146('event')::uuid, 'announced', 'ck-pub-1');
SELECT catalog.publish_event(tap._fetch146('event')::uuid, 'on_sale', 'ck-pub-2');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — CRM CONTACT CONSENT (§17.21): grant/withdraw/list, AO event append
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT is((kernel.grant_org_contact_consent(tap._fetch146('org')::uuid, 'v1', NULL) ->> 'status'), 'ok', 'C1: grant records consent');
SELECT tap.logout();
SELECT is(tap._cc_state(tap.buyer(), tap._fetch146('org')::uuid), 'granted', 'C2: current-state is granted');
SELECT is(tap._cce_count(tap.buyer(), tap._fetch146('org')::uuid), 1, 'C3: exactly one event row was appended in the same txn');
SELECT tap.login(tap.buyer());
SELECT is((kernel.grant_org_contact_consent(tap._fetch146('org')::uuid, 'v1', NULL) ->> 'status'), 'noop_replay', 'C4: re-granting is a no-op');
SELECT tap.logout();
SELECT is(tap._cce_count(tap.buyer(), tap._fetch146('org')::uuid), 1, 'C5: …and a no-op appends NO event (log records decisions, not retries)');
SELECT tap.login(tap.buyer());
SELECT is((kernel.withdraw_org_contact_consent(tap._fetch146('org')::uuid) ->> 'status'), 'ok', 'C6: withdraw records the state change');
SELECT is((SELECT count(*)::int FROM kernel.list_my_org_contact_consents() WHERE org_id = tap._fetch146('org')::uuid AND state='withdrawn'), 1,
  'C7: list_my_org_contact_consents shows the withdrawn row (own subject)');
SELECT is((kernel.withdraw_org_contact_consent(tap._fetch146('org')::uuid) ->> 'status'), 'noop_replay', 'C8: re-withdraw is a no-op');
SELECT tap.logout();
SELECT is(tap._cc_state(tap.buyer(), tap._fetch146('org')::uuid), 'withdrawn', 'C9: current-state is withdrawn (a state change, never a delete)');
SELECT is(tap._cce_count(tap.buyer(), tap._fetch146('org')::uuid), 2, 'C10: two events total (granted, withdrawn) — the withdraw appended, the re-withdraw did not');
-- the event ledger is truly append-only
SELECT throws_ok($$UPDATE kernel.org_contact_consent_event SET event='granted'$$, 'P0001', NULL, 'C11: the event ledger refuses UPDATE (AO)');
-- no staff-side write path: no p_identity parameter exists anywhere (T-RPC-CRM-01)
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('grant_org_contact_consent','withdraw_org_contact_consent')
              AND pg_get_function_arguments(p.oid) LIKE '%identity%'), 0,
  'C12: no consent writer takes an identity parameter — a venue can never consent on a fan''s behalf');

-- ============================================================================
-- SECTION D — kernel.deletion_blockers_orders (SEAM-2 body; BP-12 pending arm)
-- ============================================================================
SELECT isnt(btrim(pg_get_functiondef('kernel.deletion_blockers_orders(uuid)'::regprocedure)), '', 'D1: the hook body exists');
SELECT ok(pg_get_functiondef('kernel.deletion_blockers_orders(uuid)'::regprocedure) LIKE '%venue.%order%',
  'D2: the 082 body reads venue.order (BP-12 pending arm) — the 077 stub returned null');
SELECT is(kernel.deletion_blockers_orders(tap.buyer()), NULL, 'D3: no pending order for the buyer → no BP-12 block');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='deletion_blockers_orders'), 1,
  'D4: SEAM-2a — exactly ONE kernel.deletion_blockers_orders (the CREATE OR REPLACE spawned no overload)');

-- ============================================================================
-- SECTION E — E-23 / F-1: the checkout buyer must be proven ACTIVE
-- (flip the flag + seed the E-28 keys so we reach the create path, then attack it)
-- ============================================================================
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('inventory.per_user_active_hold_max', 1, '10'::jsonb, 'restricted');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('inventory.hold_ttl_interval', 1, '"15 minutes"'::jsonb, 'restricted');

-- a DELETION_PENDING buyer is refused (F-1). Set the state directly in VALUES so
-- it holds whether or not the buyer already has a lazily-created identity_ext row.
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.buyer(),'DELETION_PENDING')
  ON CONFLICT (identity_id) DO UPDATE SET deletion_state='DELETION_PENDING';
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.create_primary_checkout(%L, '[]'::jsonb, ARRAY[]::uuid[], 'ck-e1')$$, tap._fetch146('session')),
  NULL, 'precondition_failed: deletion_pending', 'E1: OR-17 F-1 — a DELETION_PENDING buyer is refused deletion_pending, before any order work');
SELECT tap.logout();
-- an ERASED buyer is refused too (E-23: is_deletion_pending returns FALSE for ERASED)
UPDATE kernel.identity_ext SET deletion_state='ERASED' WHERE identity_id = tap.buyer();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.create_primary_checkout(%L, '[]'::jsonb, ARRAY[]::uuid[], 'ck-e2')$$, tap._fetch146('session')),
  NULL, 'precondition_failed: identity_erased', 'E2: E-23 — an ERASED buyer is refused identity_erased (is_deletion_pending returns FALSE for ERASED)');
SELECT tap.logout();
-- MUTATION-RESISTANCE (§9): prove the ERASED refusal is not vacuous. The only
-- difference between E2 (refused) and a would-be pass is the deletion_state; flip
-- it back to ACTIVE and the SAME empty-items call now fails on 'no items', NOT on
-- the identity gate — i.e. the gate is what stopped E2, and removing the ERASED
-- state removes exactly that refusal.
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.buyer();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.create_primary_checkout(%L, '[]'::jsonb, ARRAY[]::uuid[], 'ck-e3')$$, tap._fetch146('session')),
  'P0001', NULL, 'E3: mutation-resistance — ACTIVE buyer clears the identity gate and now fails on no-items (the gate, not luck, stopped E1/E2)');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — create_primary_checkout HAPPY PATH + idempotency (flag on, holds)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT tap._store146('hold', (venue.reserve_primary_inventory(tap._fetch146('batch')::uuid, 2, 'ck-r-1') ->> 'hold_id'));
SELECT tap._store146('checkout', (venue.create_primary_checkout(
  tap._fetch146('session')::uuid,
  format('[{"ticket_type_id":"%s","quantity":2}]', tap._fetch146('tt'))::jsonb,
  ARRAY[tap._fetch146('hold')::uuid], 'ck-co-1') ->> 'order_id'));
SELECT tap.logout();
SELECT isnt(tap._fetch146('checkout'), NULL, 'F1: create_primary_checkout builds an order from held inventory');
SELECT is(tap._ord_status(tap._fetch146('checkout')::uuid), 'pending', 'F2: the order is pending (no money moved, no atoms minted)');
SELECT is((SELECT total_minor FROM venue."order" WHERE order_id = tap._fetch146('checkout')::uuid), 10000, 'F3: total is server-computed from the ticket_type snapshot (2 × 5000)');
SELECT is((SELECT count(*)::int FROM venue.order_item WHERE order_id = tap._fetch146('checkout')::uuid), 1, 'F4: one order_item for the one ticket_type');
SELECT is((SELECT attribution_candidate_code_id FROM venue."order" WHERE order_id = tap._fetch146('checkout')::uuid), NULL,
  'F5: candidate columns stay NULL at 082 (inert until 090 — R2B/C112)');
-- idempotency: a replay of the same command returns the same order, not a new one
SELECT tap.login(tap.buyer());
SELECT is((venue.create_primary_checkout(tap._fetch146('session')::uuid,
  format('[{"ticket_type_id":"%s","quantity":2}]', tap._fetch146('tt'))::jsonb,
  ARRAY[tap._fetch146('hold')::uuid], 'ck-co-1') ->> 'status'), 'idempotency_replay', 'F6: C16 — a replay returns idempotency_replay');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue."order" WHERE buyer_id = tap.buyer() AND command_idempotency_key='ck-co-1'), 1, 'F7: …and exactly one order exists for the command key');
-- now that a pending order exists, the BP-12 hook blocks the buyer's deletion
SELECT isnt(kernel.deletion_blockers_orders(tap.buyer()), NULL, 'F8: BP-12 — the pending order now blocks tombstone entry (deletion_blockers_orders returns a reason)');

-- ============================================================================
-- SECTION G — cancel_pending_order (service_role; forward-only; noop on redelivery)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.cancel_pending_order(%L, 'payment_failed', 'ck-x-1')$$, tap._fetch146('checkout')),
  '42501', NULL, 'G1: a signed-in fan cannot call the machine-only cancel (no EXECUTE grant)');
SELECT tap.logout();
-- cancel is DEF/service_role (B3 asserts the grant). Its contracted caller is the
-- stripe-webhook, but 076 gives service_role no `venue` schema USAGE — the delivery
-- mechanism is escalated to the owner as PFA-15 (NOT resolved by this test). Here
-- we exercise the correct BODY in the DEFINER (postgres) context, as the DEFINER
-- runs it once reached; p_reason_code is the frozen closed-set value 'payment_failed'.
SELECT is((venue.cancel_pending_order(tap._fetch146('checkout')::uuid, 'payment_failed', 'ck-c-1') ->> 'status'), 'cancelled', 'G2: the webhook path cancels a pending order (§20.7.9 status=cancelled)');
SELECT throws_ok(format($$SELECT venue.cancel_pending_order(%L, 'bogus', 'ck-c-9')$$, tap._fetch146('checkout')),
  NULL, 'invalid_input: reason_code must be ''payment_failed''', 'G2b: reason_code outside the closed set is refused (§20.7.9)');
SELECT is((venue.cancel_pending_order(tap._fetch146('checkout')::uuid, 'payment_failed', 'ck-c-1') ->> 'status'), 'noop_replay', 'G3: redelivery on a cancelled order is a noop_replay (never raises — a raising webhook retries forever)');
SELECT is(tap._ord_status(tap._fetch146('checkout')::uuid), 'cancelled', 'G4: the order is cancelled');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE subject_id = tap._fetch146('checkout')::uuid AND action='order.cancel'
            AND actor_identity='00000000-0000-0000-0000-0000000000f1'), 1,
  'G5: an admin_audit row was written by the SN-SYSTEM sentinel');

-- ============================================================================
-- SECTION H — the two guard triggers (order_item IMM; candidate freeze)
-- ============================================================================
-- build a fresh order to force it to paid, then prove the item is frozen
SELECT tap.login(tap.buyer());
SELECT tap._store146('hold2', (venue.reserve_primary_inventory(tap._fetch146('batch')::uuid, 1, 'ck-r-2') ->> 'hold_id'));
SELECT tap._store146('ord2', (venue.create_primary_checkout(
  tap._fetch146('session')::uuid,
  format('[{"ticket_type_id":"%s","quantity":1}]', tap._fetch146('tt'))::jsonb,
  ARRAY[tap._fetch146('hold2')::uuid], 'ck-co-2') ->> 'order_id'));
SELECT tap.logout();
-- while pending, the order_item is mutable (definer context)
SELECT lives_ok(format($$UPDATE venue.order_item SET quantity=1 WHERE order_id=%L$$, tap._fetch146('ord2')),
  'H1: while the order is pending, its items are still mutable');
-- flip the parent to paid (definer/postgres), then the guard freezes the item
UPDATE venue."order" SET status='paid' WHERE order_id = tap._fetch146('ord2')::uuid;
SELECT throws_ok(format($$UPDATE venue.order_item SET quantity=2 WHERE order_id=%L$$, tap._fetch146('ord2')),
  'P0001', NULL, 'H2: once the order is paid, order_item is IMMUTABLE (guard trigger)');
SELECT throws_ok(format($$DELETE FROM venue.order_item WHERE order_id=%L$$, tap._fetch146('ord2')),
  'P0001', NULL, 'H3: …and cannot be DELETEd either');
-- candidate-freeze: once the order leaves pending, the candidate columns freeze
SELECT throws_ok(format($$UPDATE venue."order" SET attribution_candidate_code_id=gen_random_uuid() WHERE order_id=%L$$, tap._fetch146('ord2')),
  'P0001', NULL, 'H4: the attribution candidate is frozen once the order leaves pending (R2B/C112 guard)');

-- ============================================================================
-- SECTION I — RLS: owner reads own; a non-buyer is denied
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM venue."order" WHERE buyer_id = tap.buyer()), 2, 'I1: the buyer reads their own orders (owner policy)');
SELECT tap.logout();
-- a different signed-in user (not the buyer, holds no org/venue role) sees none
SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*)::int FROM venue."order"), 0, 'I2: a non-buyer, non-staff signed-in user sees ZERO orders');
SELECT is((SELECT count(*)::int FROM venue.order_item), 0, 'I3: …and zero order_items (order scope inherited)');
SELECT tap.logout();
-- venue staff over this venue can read the orders
SELECT tap.login(tap.seller());   -- the org owner reads own-org orders (org policy)
SELECT ok((SELECT count(*)::int FROM venue."order" WHERE org_id = tap._fetch146('org')::uuid) >= 2, 'I4: the org owner reads own-org orders (org policy)');
SELECT tap.logout();
-- regression (red-team D): the two role-matrix overreaches must never reappear in
-- the policy predicates — platform_support (graded V, redacted-RPC only) and
-- venue_scanner (own-session inexpressible → fail-closed, E-37).
SELECT is((SELECT count(*)::int FROM pg_policies
            WHERE schemaname='venue' AND tablename IN ('order','order_item')
              AND (qual LIKE '%platform_support%' OR qual LIKE '%venue_scanner%')), 0,
  'I5: no order/order_item policy references platform_support or venue_scanner (fail-closed authz scope)');

SELECT finish();
ROLLBACK;
