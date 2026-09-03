-- ============================================================================
-- 154_phase2_market_bridge_view_and_late_fk.sql — Phase-2 package 089 suite.
-- Frozen sources: plan §8/089 · registry row 089 (J2 ADOPT) · schema §4.6 ·
-- RLS §10.6 / §12 / §14.1 · SPEC_FOUNDATION §7 · 085 §1.8 (deferred FK) · CDM
-- C10 (rail) · E-106 (countersigned: no anon market access) · E-113..E-116.
-- The rail stays DARK at seed; the resale flag is flipped in-suite under
-- ROLLBACK to prove the bridge's own predicate. BEGIN … plan(N) … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(64);
SELECT tap.seed_core();

CREATE TABLE tap.memo_154 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._s154(k text, v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_154 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._u154(k text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_154 WHERE k=$1 $m$;
CREATE FUNCTION tap._cfg154(p_key text, p_val jsonb, p_vis text DEFAULT 'public') RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.platform_config (key, version, value, visibility) SELECT p_key, coalesce(max(version),0)+1, p_val, p_vis FROM catalog.platform_config WHERE key = p_key $m$;
CREATE FUNCTION tap._newpayment154(p_buyer uuid, p_seller uuid, p_total int, p_pi text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ WITH l AS (INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
      VALUES (p_seller, 'Bridge Pay ' || gen_random_uuid()::text, 'Bridge Hall', 'wynwood', (now()+interval '15 days')::date, '20:00', 'GA', 1, 'mobile_transfer', 50, 50, 24, now()+interval '1 day', 'covers/fixture.jpg') RETURNING id)
    INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
    SELECT l.id, p_buyer, p_seller, (p_total * 9) / 10, p_total - (p_total * 9) / 10, p_total, 'succeeded', 'buy_now', p_pi FROM l RETURNING id $m$;
-- the projection expression, stated ONCE for the parity assertions (E-114 / E-115)
CREATE FUNCTION tap._ext154() RETURNS TABLE(id uuid, rail text, event_session_id uuid, event_name text, price_minor integer, currency text, seller_id uuid, status text, cover_image_path text, created_at timestamptz)
LANGUAGE sql STABLE AS $m$
  SELECT l.id, CASE WHEN l.proof_status = 'approved' THEN 'external_verified' ELSE 'external' END, NULL::uuid, l.event_name, (l.current_bid::bigint * 100)::integer, 'USD', l.seller_id, l.status, l.cover_image_path, l.created_at
    FROM public.listings l $m$;

-- ============================================================================
-- SECTION A — THE 089 CLOSED WORLD (parity: EXTRA = 0, MISSING = 0)
-- ============================================================================
SELECT has_view('market'::name, 'listing_unified'::name, 'A1: market.listing_unified exists');
SELECT ok((SELECT c.reloptions @> ARRAY['security_invoker=true'] FROM pg_class c WHERE c.oid = 'market.listing_unified'::regclass),
  'A2: RLS §14.1 — the bridge is security_invoker (evaluates under the CALLER; it cannot launder authority)');
SELECT is((SELECT string_agg(column_name||':'||data_type, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='market' AND table_name='listing_unified'),
  'id:uuid,rail:text,event_session_id:uuid,event_name:text,price_minor:bigint,currency:text,seller_id:uuid,status:text,cover_image_path:text,created_at:timestamp with time zone',
  'A3: exactly the common discovery column set (id · rail · event/session · price · seller · status · cover + currency, created_at) — no money/custody/PII column');
SELECT is((SELECT string_agg(DISTINCT n.nspname||'.'||c.relname, ',' ORDER BY n.nspname||'.'||c.relname)
             FROM pg_rewrite r JOIN pg_depend d ON d.objid = r.oid AND d.refclassid = 'pg_class'::regclass
             JOIN pg_class c ON c.oid = d.refobjid JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE r.ev_class = 'market.listing_unified'::regclass AND c.oid <> r.ev_class),
  'catalog.event,catalog.event_session,catalog.platform_config,market.listing_native,public.listings',
  'A4: the view reads EXACTLY public.listings ∪ market.listing_native (+ the flag row, the session→event title) — no kernel.* relation, no cross-rail join');
SELECT is((SELECT is_insertable_into FROM information_schema.views WHERE table_schema='market' AND table_name='listing_unified'), 'NO', 'A5: no write path through the view (not insertable)');
SELECT throws_ok($$INSERT INTO market.listing_unified (id, rail) VALUES (gen_random_uuid(), 'native')$$, '55000', NULL, 'A6: an INSERT through the bridge is refused by Postgres itself (UNION view — never auto-updatable)');
SELECT throws_ok($$DELETE FROM market.listing_unified$$, '55000', NULL, 'A7: …so is a DELETE');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='market' AND c.relkind='v'), 1, 'A8: market holds exactly ONE view');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='market' AND c.relkind='r'), 5, 'A9: …and still its five 088 tables (089 creates no table)');
SELECT is((SELECT (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='market')::text||'/'||(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel')::text||'/'||(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='catalog')::text), '22/136/16',
  -- 2026-09-03 (package 095, payout state machine): 125 -> 132. SEVEN added, zero removed
  -- (get_payout_execution_context was RE-CREATED body-only by 095 E-6, not added). The seven:
  -- guard_payout_org_payable and guard_settlement_forward_only (the two new trigger functions —
  -- no grant to any principal, 077 F1 sweep still zero), rearm_failed_payout and
  -- retry_held_payout (authenticated, +2 at F2), settlement_maturity_hold_codes
  -- (definer-internal constant, no grant), hold_payout_transfer_reversed and
  -- settlement_unbooked_refund_exposure (service_role, +2 at F3). Re-derived from the LIVE
  -- CATALOG, never by accepting a delta.
  -- 2026-09-02 (package 090): kernel 107 -> 109 (is_promoter_for_event + pay_promoter_commission); market/catalog unchanged.
  -- 2026-09-02 (package 093): kernel 109 -> 116. RATIFIED CONTRACT CHANGE — seven kernel routines:
  -- settlement_primary_lines (A3) · sync_org_connect_state + get_org_connect_state (A6) ·
  -- stage_org_connect_ref + get_org_connect_ref (A7/A9, RT-A-3) · get_refund_execution_context (D3)
  -- · is_order_buyer (F). MARKET AND CATALOG ARE THE ASSERTION THAT MATTERS HERE and both are
  -- unmoved (22 / 16): 093 dumps nothing into 089's schemas, which is what this guard proves.
  -- 2026-09-03: kernel 117 -> 119. 093 slice 30 §9/§10 (H6/F-3, F-4) adds kernel.authorize_org_payout_dashboard and kernel.guard_connect_id_not_org_bound.
  -- 2026-09-03 (package 093, payout-executor slice): 119 -> 125. SIX added, zero removed,
  -- re-derived from the LIVE CATALOG by diffing two rehearsal databases (one stopped at 092 via
  -- REHEARSAL_UPTO, one with 093) name-by-name, never by accepting a delta: kernel.settlement_payout_maturity
  -- and kernel.settlement_covered_payments (G2 — the maturity conjunction and its covered set, extracted
  -- from close_settlement's inline gate so the mint, the advance and the transfer share ONE definition;
  -- this is the D-1 closure) plus the payout executor's four (H8): claim_payouts_for_execution,
  -- get_payout_execution_context, hold_payout_destination_changed, record_payout_execution_note.
  -- All six are service_role-only definers. 141 A14a names all SIXTEEN of 093's kernel additions with
  -- their grant class, and 141 F3 moves 39 -> 45 by exactly these six.
  'A10: 089 creates NO function (market 22 / kernel 132 post-095 / catalog 16)');
-- 2026-09-02 (package 090): 57 -> 67 (+10 venue promoter-engine read policies).
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname IN ('kernel','venue','catalog','market','notify')), 72, 'A11 (092: register 72 after notify''s five owner policies): 089 creates NO policy (the view carries none — it inherits; register 67 post-090)');
-- 2026-09-02 (package 092): 18 -> 19 (+notify-drain-outbox).
SELECT is((SELECT count(*)::int FROM cron.job), 19, 'A12: 089 schedules nothing (cron rows unchanged; 19 post-092)');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='market' AND NOT t.tgisinternal), 5,
  'A13: no new trigger (the five 088 set_updated_at triggers only)');
-- the late-binding FK (plan §8/089; 085 §1.8)
SELECT ok((SELECT pg_get_constraintdef(c.oid) = 'FOREIGN KEY (sale_id) REFERENCES market.market_sale(sale_id) ON DELETE RESTRICT' AND c.convalidated AND NOT c.condeferrable
             FROM pg_constraint c WHERE c.conrelid='kernel.payment_native'::regclass AND c.conname='fk_payment_native_sale'),
  'A14: fk_payment_native_sale — (sale_id) → market.market_sale(sale_id) ON DELETE RESTRICT, VALIDATED, not deferrable');
SELECT is((SELECT count(*)::int FROM pg_constraint WHERE conrelid='kernel.payment_native'::regclass), 7, 'A15: payment_native now carries seven constraints (085''s six + the adopted FK)');
SELECT ok((SELECT pg_get_constraintdef(c.oid) LIKE '%order_id IS NOT NULL%' FROM pg_constraint c WHERE c.conrelid='kernel.payment_native'::regclass AND c.conname='payment_native_subject_xor_ck'),
  'A16: 085''s subject XOR CHECK is untouched (order XOR sale)');
-- SEAM accounting unchanged
-- 2026-09-02 (package 090): the 090 seams are now REAL; the 088 seam and the hook count (19) are unchanged.
SELECT ok((SELECT p.prosrc NOT LIKE '%where false%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_commission_lines')
       AND (SELECT btrim(p.prosrc) <> 'select' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='on_identity_erased_promoter')
       AND (SELECT p.prosrc LIKE '%chargeback%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='settlement_royalty_lines'),
  'A17: ODR-16 SEAM state after 090 — the two 090 seams are real, the 088 seam stays real (hook count 19)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('kernel','market') AND p.proname IN ('settlement_royalty_lines','settlement_commission_lines','on_atom_voided','on_door_freeze_engaged','door_freeze_drain_preview','deletion_blockers_market','on_identity_erased_market','on_identity_erased_promoter')), 8,
  'A18: overload count 1 on every seam name');
-- the projection is stated in bytes, never inferred at read time
SELECT ok((SELECT pg_get_viewdef('market.listing_unified'::regclass) LIKE '%proof_status = ''approved''%external_verified%'), 'A19: E-114 — rail = external_verified ⇔ proof_status = ''approved'' (the sole verified-positive label of 071''s CHECK set; C10)');
SELECT ok((SELECT pg_get_viewdef('market.listing_unified'::regclass) ~ 'current_bid\)::bigint \* 100' AND pg_get_viewdef('market.listing_unified'::regclass) !~ '\* 100\)+::integer'), 'A20: E-115 — the external dollar price is normalized to minor units (× 100) in bigint with NO narrowing cast (a poisoned current_bid cannot fail every price read)');
SELECT ok((SELECT pg_get_viewdef('market.listing_unified'::regclass) LIKE '%feature.native_resale_enabled%' AND pg_get_viewdef('market.listing_unified'::regclass) LIKE '%''active''%''reserved''%'),
  'A21: E-116 — the native arm carries the discovery predicate AND the flag explicitly');

-- ============================================================================
-- SECTION B — GRANTS (RLS §10.6 · E-106 / E-113 · PFA-1)
-- ============================================================================
SELECT ok(has_table_privilege('authenticated','market.listing_unified','SELECT') AND NOT has_table_privilege('service_role','market.listing_unified','SELECT') AND NOT has_schema_privilege('service_role','market','USAGE'),
  'B1: SELECT to authenticated only — E-118: service_role holds no USAGE on market/catalog, so RLS §10.6''s machine cell is undeliverable here and no dormant grant is written');
SELECT ok(NOT has_table_privilege('anon','market.listing_unified','SELECT') AND NOT has_schema_privilege('anon','market','USAGE'),
  'B2: E-106 (countersigned) / PFA-14 — NO anon grant on the bridge and no anon USAGE on market; the plan''s anon row is superseded (E-113)');
SELECT ok(NOT has_table_privilege('authenticated','market.listing_unified','INSERT') AND NOT has_table_privilege('authenticated','market.listing_unified','UPDATE') AND NOT has_table_privilege('authenticated','market.listing_unified','DELETE')
       AND NOT has_table_privilege('service_role','market.listing_unified','INSERT'),
  'B3: SELECT only — no DML privilege for any role');
SELECT is((SELECT count(*)::int FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
            WHERE c.oid='market.listing_unified'::regclass AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname='anon'))), 0,
  'B4: PFA-1 sweep — zero PUBLIC/anon privilege on the bridge');
SELECT is((SELECT rolname FROM pg_roles r JOIN pg_class c ON c.relowner=r.oid WHERE c.oid='market.listing_unified'::regclass), 'postgres', 'B5: owned by postgres (irrelevant to authority: security_invoker)');
SELECT tap.login_anon();
SELECT throws_ok($$SELECT count(*) FROM market.listing_unified$$, '42501', NULL, 'B6: anon cannot even reach the schema (the 076 wall) — the bridge is not an anon surface');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — EXTERNAL RAIL PARITY (plan §8/089 Tests: byte-identical to public.listings)
-- ============================================================================
UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_a();   -- one verified-external row (E-114 operand)
SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE rail IN ('external','external_verified')), (SELECT count(*)::int FROM public.listings),
  'C1: every public.listings row the caller can read is in the bridge, exactly once (no filter, no duplication)');
SELECT is((SELECT count(*)::int FROM ((SELECT * FROM market.listing_unified WHERE rail <> 'native') EXCEPT (SELECT * FROM tap._ext154())) x), 0, 'C2: the projected external tuples ⊆ the direct projection over public.listings…');
SELECT is((SELECT count(*)::int FROM ((SELECT * FROM tap._ext154()) EXCEPT (SELECT * FROM market.listing_unified WHERE rail <> 'native')) x), 0, 'C3: …and ⊇ — BYTE-IDENTICAL for the discovery set (marketplace parity)');
SELECT is((SELECT rail FROM market.listing_unified WHERE id = tap.listing_a()), 'external_verified', 'C4: E-114 — an approved proof surfaces as external_verified');
SELECT is((SELECT rail FROM market.listing_unified WHERE id = tap.listing_b()), 'external', 'C5: …an unapproved one as external');
SELECT ok((SELECT u.price_minor = l.current_bid * 100 AND u.event_session_id IS NULL AND u.currency = 'USD' AND u.seller_id = l.seller_id AND u.status = l.status AND u.cover_image_path = l.cover_image_path
             FROM market.listing_unified u JOIN public.listings l ON l.id = u.id WHERE u.id = tap.listing_b()),
  'C6: E-115 — an external row: price in minor units (dollars × 100), no session, USD, seller/status/cover passed through');
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE rail = 'native'), 0, 'C7: while the rail is DARK the bridge shows ZERO native rows to a fan');
SELECT tap.logout();

-- ============================================================================
-- FIXTURE — org1 → venue1 → event1 → session1 → tt → batch → order1 (buyer) →
--   atom a1 (finalized) → resale policy buy_now; the resale flag flips later.
-- ============================================================================
SELECT is((SELECT (value #>> '{}') FROM catalog.platform_config WHERE key='feature.native_resale_enabled' ORDER BY version DESC LIMIT 1), 'false', 'F0: native resale is DARK at seed');
SELECT tap.login(tap.seller());
SELECT tap._s154('org1', (kernel.create_organization('Bridge Co','Bridge Co','ck89-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u154('org1');
SELECT tap.login(tap.seller());
SELECT tap._s154('venue1', (catalog.create_venue(tap._u154('org1'),'Bridge Hall','wynwood',NULL,'ck89-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._u154('venue1'),'approved','miami_gate','ck89-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._s154('event1', (catalog.create_event(tap._u154('venue1'),'Bridge Night', jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck89-e1') ->> 'event_id'));
SELECT tap._s154('session1', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u154('event1')));
SELECT tap._s154('tt1', (venue.create_ticket_type(tap._u154('event1'),'admission','GA',5000,'public','ck89-tt1') ->> 'ticket_type_id'));
SELECT tap._s154('batch1', (venue.create_inventory_batch(tap._u154('tt1'), tap._u154('session1'), 'public_sale', 100, 0, 'ck89-b1') ->> 'batch_id'));
SELECT tap._s154('pol1', (catalog.set_resale_policy('event', tap._u154('event1'), '{"mode":"buy_now","price_cap_bps":10000}'::jsonb, 'ck89-pol1') ->> 'policy_id'));
SELECT tap.logout();
WITH k AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before) VALUES ('per_event', tap._u154('event1'), 'PUBKEY-89', 'kms-89', 'active', now()) RETURNING key_id)
SELECT tap._s154('key1', (SELECT key_id::text FROM k));
WITH o AS (INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  VALUES (tap.buyer(), tap._u154('session1'), tap._u154('org1'), 'pending', 'web', 5000, 'ck89-ord-1') RETURNING order_id)
SELECT tap._s154('order1', (SELECT order_id::text FROM o));
INSERT INTO venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) VALUES (tap._u154('order1'), tap._u154('tt1'), 1, 5000);
INSERT INTO venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES (tap._u154('batch1'), tap.buyer(), 1, 'active', now() + interval '1 hour', 'ck89-h-1');
UPDATE venue.inventory_batch SET held = 1 WHERE batch_id = tap._u154('batch1');
SELECT tap._s154('pay1', tap._newpayment154(tap.buyer(), tap.seller(), 5000, 'pi_89_1')::text);
SELECT tap._s154('pay2', tap._newpayment154(tap.other_user(), tap.buyer(), 5000, 'pi_89_2')::text);
SELECT tap._cfg154('feature.native_issuance_enabled', 'true'::jsonb);
SELECT is((venue.finalize_primary_order(tap._u154('order1'), tap._u154('pay1'), 'ck89-f1', NULL) ->> 'status'), 'ok', 'F1: order1 finalized → one atom minted to buyer');
SELECT tap._s154('a1', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id=tap._u154('session1') AND current_owner_id=tap.buyer()));
SELECT ok(tap._u154('a1') IS NOT NULL, 'F2: the atom resolved');

-- ============================================================================
-- SECTION D — THE NATIVE ARM: the bridge's OWN predicate (E-116) + the flag
-- ============================================================================
SELECT tap._cfg154('feature.native_resale_enabled', 'true'::jsonb, 'public');
SELECT tap.login(tap.buyer());
SELECT tap._s154('l1', (market.create_listing(tap._u154('a1'), 5000, 'buy_now', 'ck89-l1') ->> 'listing_id'));
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT ok((SELECT u.rail='native' AND u.event_session_id = tap._u154('session1') AND u.event_name IS NULL AND u.price_minor = 5000 AND u.currency = 'USD' AND u.seller_id = tap.buyer() AND u.status = 'active' AND u.cover_image_path IS NULL
             FROM market.listing_unified u WHERE u.id = tap._u154('l1')),
  'D1: flag ON — another fan discovers the native listing through the bridge; the event is still a DRAFT, so its title is NULL for them (the LEFT JOIN runs under the caller''s catalog policy — no row lost, no draft leaked)');
SELECT tap.logout();
UPDATE catalog.event SET status='announced' WHERE event_id = tap._u154('event1');
SELECT tap.login(tap.other_user());
SELECT is((SELECT u.event_name FROM market.listing_unified u WHERE u.id = tap._u154('l1')), 'Bridge Night', 'D1a: …once the event is announced its title resolves through the same caller-side policy');
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE rail = 'native'), 1, 'D2: exactly one native row');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE id = tap._u154('l1')), 1, 'D3: the seller sees their own active listing in the bridge too');
SELECT tap.logout();
-- non-discovery rows never surface, even to their owner
INSERT INTO market.listing_native (listing_id, ticket_atom_id, seller_id, event_session_id, listing_mode, price_minor, resale_policy_id, resale_policy_version, status, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000d001', tap._u154('a1'), tap.buyer(), tap._u154('session1'), 'buy_now', 5000, tap._u154('pol1'), 1, 'draft', 'ck89-draft'),
       ('00000000-0000-0000-0000-00000000d002', tap._u154('a1'), tap.buyer(), tap._u154('session1'), 'buy_now', 5000, tap._u154('pol1'), 1, 'cancelled', 'ck89-cxl');
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM market.listing_native WHERE seller_id = tap.buyer()), 3, 'D4: the base table shows the owner all three rows (owner arm)…');
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE rail = 'native'), 1, 'D5: …the bridge shows only the discoverable one (E-116: draft/cancelled never surface through the bridge)');
SELECT tap.logout();
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u154('l1');
SELECT tap.login(tap.other_user());
SELECT is((SELECT status FROM market.listing_unified WHERE id = tap._u154('l1')), 'reserved', 'D6: a RESERVED listing (checkout in flight) stays discoverable with its status (R-37 discovery set)');
SELECT tap.logout();
UPDATE market.listing_native SET status='active' WHERE listing_id = tap._u154('l1');
SELECT tap._cfg154('feature.native_resale_enabled', 'false'::jsonb, 'public');
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM market.listing_native WHERE listing_id = tap._u154('l1') AND status='active'), 1, 'D7: flag OFF — the owner still sees the active row on the base table…');
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE rail = 'native'), 0, 'D8: …but the bridge shows ZERO native rows (the native union is INERT while the rail is dark — plan §8/089)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE rail = 'native'), 0, 'D9: DARK-RAIL COMPOSITION — even a superuser read of the bridge yields no native row while OFF (the predicate is the view''s, not the caller''s RLS)');
SELECT tap._cfg154('feature.native_resale_enabled', 'true'::jsonb, 'public');
-- discovery through the bridge does NOT open a buying path: the parks hold
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT market.checkout_buy_now(%L, 'ck89-cb1')$$, (SELECT id FROM market.listing_unified WHERE rail='native' LIMIT 1)), '%resale_split_unavailable%',
  'D10: DARK-RAIL COMPOSITION — a listing discovered through the bridge still cannot be bought (PFA-30 park at ⑦)');
SELECT is((market.make_offer(tap._u154('l1'), 4000, now()+interval '1 hour', 'ck89-o1') ->> 'status'), 'ok', 'D11: …an offer on the discovered listing is a stated intent only (§20.8.5)…');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM market.market_sale), 0, 'D11a: …it moves no money and writes no sale (the accept path is the PFA-30 park)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT market.create_p2p_transfer(%L, 'friend', NULL, 'ck89-t1')$$, tap._u154('a1')), '%conflict_locked%', 'D12: the listed atom cannot be gifted (overlay); the p2p create park (TTL) stays behind it');
SELECT tap.logout();
SELECT ok((SELECT p.prosrc LIKE '%dual_control_unavailable%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='kernel' AND p.proname='resolve_dispute_native'),
  'D13: PFA-31 — dispute resolution remains parked (089 touches nothing there)');
SELECT is((SELECT (value #>> '{}') FROM catalog.platform_config WHERE key='feature.native_scanning_enabled' ORDER BY version DESC LIMIT 1), 'false', 'D14: native scanning stays DARK');

-- ============================================================================
-- SECTION E — THE FK BITES (RESTRICT; the 085 deferred link is now structural)
-- ============================================================================
SELECT throws_ok(format($$INSERT INTO kernel.payment_native (payment_id, sale_id, amount_minor, currency) VALUES (%L, gen_random_uuid(), 5000, 'USD')$$, tap._u154('pay2')), '23503', NULL,
  'E1: a payment link naming a sale that does not exist is refused (23503)');
UPDATE market.listing_native SET status='reserved' WHERE listing_id = tap._u154('l1');
INSERT INTO market.market_sale (sale_id, listing_id, ticket_atom_id, buyer_id, seller_id, price_minor, payment_id, sale_state, paid_pending_since, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000e001', tap._u154('l1'), tap._u154('a1'), tap.other_user(), tap.buyer(), 5000, tap._u154('pay2'), 'paid_pending_transfer', now(), 'ck89-s1');
SELECT is((market.finalize_market_sale('00000000-0000-0000-0000-00000000e001', 'ck89-fz1') ->> 'status'), 'ok', 'E2: the 088 engine completes the seeded sale and writes the payment link…');
SELECT ok((SELECT pn.sale_id = '00000000-0000-0000-0000-00000000e001' FROM kernel.payment_native pn WHERE pn.payment_id = tap._u154('pay2')), 'E3: …payment_native.sale_id points at the sale under the new FK');
SELECT throws_ok($$DELETE FROM market.market_sale WHERE sale_id = '00000000-0000-0000-0000-00000000e001'$$, '23503', NULL, 'E4: ON DELETE RESTRICT — the consummated sale cannot vanish from under its payment link');
SELECT throws_like(format($$UPDATE kernel.payment_native SET sale_id = gen_random_uuid() WHERE payment_id = %L$$, tap._u154('pay2')), '%append%', 'E5: re-pointing the link is refused by 085''s append-only guard BEFORE the FK is consulted (the link is write-once; the FK guards the referenced side — E4)');
SELECT ok((SELECT (l.current_bid::bigint * 100) = u.price_minor AND pg_typeof(u.price_minor)::text = 'bigint' FROM market.listing_unified u JOIN public.listings l ON l.id = u.id WHERE u.id = tap.listing_a()), 'E5a: the projected price is bigint end to end (E-115: no narrowing anywhere in the arm)');
SELECT is((SELECT count(*)::int FROM market.listing_unified WHERE id = tap._u154('l1')), 0, 'E6: a SOLD listing leaves discovery (status sold is not in the discovery set)');

-- ============================================================================
-- SECTION F — ODR-16 / writers / byte facts
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_constraint c WHERE c.conrelid='kernel.payment_native'::regclass AND c.contype='f' AND c.confrelid='auth.users'::regclass), 0,
  'F3: ODR-16 — 089 adds no identity FK (the adopted FK targets market_sale; the deletion composition is unchanged)');
SELECT ok((SELECT r.ev_type = '1' FROM pg_rewrite r WHERE r.ev_class = 'market.listing_unified'::regclass AND r.rulename = '_RETURN'),
  'F4: WRITER FENCE — the view''s only rule is its SELECT rule; it writes nothing (no new writer anywhere)');
SELECT ok((SELECT pg_get_viewdef('market.listing_unified'::regclass) !~* 'numeric|float|double|real|round\('), 'F5: integer arithmetic only in the price normalization');
SELECT ok((SELECT pg_get_viewdef('market.listing_unified'::regclass) !~* 'pgcrypto|hmac\(|digest\(|vault\.|net\.'), 'F6: PFA-28 / X-6 — 089''s only object touches no crypto, vault or network symbol');

SELECT * FROM finish();
ROLLBACK;
