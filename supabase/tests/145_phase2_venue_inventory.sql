-- ============================================================================
-- 145_phase2_venue_inventory.sql — Phase-2 package 081 test suite.
--
-- Frozen sources: plan §8/081 · schema §3.1-§3.5 (+§3.3.1 the oversell proof,
-- §3.5.1 the G-24 sweep) · RPC §4.2 (publish_event), §5.1-§5.5,
-- §20.3.1/§20.3.2/§20.3.3 (T-RPC-INV-01..-06) · RLS §9.1-§9.5, §16.10 · CRON
-- register row 081 · OR-17 F-1 · E-28 (the two unseeded PFA-9 CLASS A keys) ·
-- E-29 (the counter-column impossibility). NATIVE ISSUANCE + BUY NOW stay dark.
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK (no committed state).
-- ============================================================================
BEGIN;
SELECT plan(96);

SELECT tap.seed_core();

CREATE TABLE tap.memo_145 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store145(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_145 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch145(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_145 WHERE k = $1 $m$;
-- definer reads of the withheld counter columns (E-29: raw counters are not
-- client-selectable; these stand in for the batch/capacity RPC result JSON).
CREATE FUNCTION tap._cap(b uuid)  RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT capacity FROM venue.inventory_batch WHERE batch_id = b $m$;
CREATE FUNCTION tap._held(b uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT held FROM venue.inventory_batch WHERE batch_id = b $m$;
CREATE FUNCTION tap._rem(b uuid)  RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT remaining FROM venue.inventory_batch WHERE batch_id = b $m$;
CREATE FUNCTION tap._shardcnt(b uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM venue.inventory_batch_shard WHERE batch_id = b $m$;
CREATE FUNCTION tap._shardsum(b uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT coalesce(sum(capacity),0)::int FROM venue.inventory_batch_shard WHERE batch_id = b $m$;
GRANT EXECUTE ON FUNCTION tap._cap(uuid), tap._held(uuid), tap._rem(uuid),
  tap._shardcnt(uuid), tap._shardsum(uuid) TO authenticated;

-- ============================================================================
-- SECTION A — THE 081 CLOSED WORLD
-- ============================================================================

SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relkind='r'), 8,
  'A1: venue holds EIGHT tables — staff_role (080) + five 081 inventory + two 082 order');
SELECT is((SELECT string_agg(c.relname,',' ORDER BY c.relname) FROM pg_class c
            JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='venue' AND c.relkind='r'),
  'inventory_batch,inventory_batch_shard,inventory_hold,inventory_movement,order,order_item,staff_role,ticket_type',
  'A2: exactly the frozen names — order/order_item present (082), inventory_unit ABSENT (EXT/C42)');
SELECT hasnt_table('venue'::name,'inventory_unit'::name, 'A3: venue.inventory_unit is NOT created (EXT/C42)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue'), 15,
  'A4: venue holds FIFTEEN functions — 082''s fourteen + 083''s append_door_manifest_delta');
SELECT has_function('catalog'::name,'publish_event'::name, ARRAY['uuid','text','text']::name[],
  'A5: catalog.publish_event authored HERE (SEAM-1: reads ticket_type + inventory_batch)');
SELECT has_function('kernel'::name,'issue_ticket_atoms'::name, ARRAY['jsonb','text']::name[],
  'A6: the mint engine landed in 083 (C114) — kernel.issue_ticket_atoms(jsonb, text) exists');
SELECT hasnt_function('venue'::name,'finalize_primary_order'::name, 'A7: no order engine (082/085)');
SELECT hasnt_function('venue'::name,'allocate_comp'::name, 'A8: no comp engine (086)');
SELECT hasnt_function('venue'::name,'record_scan'::name, 'A9: no door/scan surface (086)');

-- the C27 oversell CHECK, structurally
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='venue.inventory_batch'::regclass
                   AND contype='c' AND conname='inventory_batch_oversell_check'),
  'A10: the batch oversell CHECK exists (held>=0 AND sold>=0 AND held+sold<=capacity)');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='venue.inventory_batch_shard'::regclass
                   AND contype='c' AND conname='inventory_batch_shard_oversell_check'),
  'A11: the per-shard oversell CHECK exists');
SELECT is((SELECT a.attgenerated FROM pg_attribute a
            WHERE a.attrelid='venue.inventory_batch'::regclass AND a.attname='remaining'), 's',
  'A12: remaining is a GENERATED column (capacity-held-sold), never stored-writable (C27)');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='venue.inventory_movement'::regclass
                   AND contype='u' AND conname='inventory_movement_cause_uq'),
  'A13: the movement ledger carries the C26-shape UNIQUE(cause,cause_ref,batch_id,movement_kind)');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='venue.inventory_hold'::regclass
                   AND contype='u' AND conname='inventory_hold_command_uq'),
  'A14: the hold carries UNIQUE(identity_id, command_idempotency_key) (C16)');
SELECT has_index('venue','inventory_hold','inventory_hold_expiry_idx',
  'A15: the G-24 partial index expires_at WHERE status=active exists — for the sweep 081 also builds');
-- FK cascade: shard ON DELETE CASCADE, everything else RESTRICT
SELECT is((SELECT confdeltype FROM pg_constraint WHERE conrelid='venue.inventory_batch_shard'::regclass
            AND contype='f' AND conname LIKE '%batch%'), 'c',
  'A16: shard.batch_id is ON DELETE CASCADE (shards are a decomposition, not independent facts)');

-- SEAM-2: 081 replaces NO blocker hook
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel'
             AND ((p.proname LIKE 'deletion_blockers%' AND btrim(p.prosrc)<>'select null::text')
               OR (p.proname LIKE 'on_identity_erased%' AND btrim(p.prosrc)<>'select')
               OR (p.proname='on_deletion_q5_release' AND btrim(p.prosrc)<>'select')
               OR (p.proname='has_outstanding_obligations' AND btrim(p.prosrc)<>'select false'))), 4,
  'A17: SEAM-2 has EXACTLY four real bodies (079 custody + 080 staff + 082 orders + 083 wallet)');
SELECT ok(btrim((SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel' AND p.proname='deletion_blockers_orders'))<>'select null::text',
  'A18: deletion_blockers_orders now carries its real BP-12 pending-order body (082 filled it)');

-- cron + policies
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname='sweep-expired-inventory-holds'), 1,
  'A19: the per-package hold-sweep cron entry exists (register row 081)');
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname) FROM pg_policy p
            JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='venue' AND c.relname IN ('ticket_type','inventory_batch','inventory_hold')),
  'venue_inventory_batch_sel_public,venue_inventory_batch_sel_venue,'
  || 'venue_inventory_hold_sel_owner,venue_inventory_hold_sel_venue,'
  || 'venue_ticket_type_sel_public,venue_ticket_type_sel_venue',
  'A20: exactly the six §16.10 policy names');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
           WHERE c.relname IN ('inventory_batch_shard','inventory_movement')), 0,
  'A21: shard + movement carry ZERO policies — money-custody-RPC-only, deny-all (§9.3/§9.4)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='venue' AND p.polcmd::text<>'r'), 0,
  'A22: no venue INSERT/UPDATE/DELETE policy — writes are RPC-only');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname IN ('kernel','catalog','venue')
             AND coalesce(btrim(pg_get_expr(p.polqual, p.polrelid)),'')='true'), 0,
  'A23: still no USING(true) anywhere');

-- E-29: the counter columns are withheld from EVERY client role; remaining granted
SELECT ok(NOT has_column_privilege('authenticated','venue.inventory_batch','held','SELECT')
       AND NOT has_column_privilege('authenticated','venue.inventory_batch','capacity','SELECT')
       AND NOT has_column_privilege('authenticated','venue.inventory_batch','sold','SELECT'),
  'A24: E-29 — raw counters capacity/held/sold are NOT client-selectable (the E-24 column impossibility, fail-closed)');
SELECT ok(has_column_privilege('authenticated','venue.inventory_batch','remaining','SELECT'),
  'A25: …while remaining IS world-readable (footnote 23)');
SELECT ok(NOT has_table_privilege('authenticated','venue.inventory_batch_shard','SELECT'),
  'A26: shard rows are deny-all to clients (§9.3 fn25)');
SELECT ok(NOT has_table_privilege('authenticated','venue.inventory_movement','SELECT')
       AND NOT has_table_privilege('authenticated','venue.inventory_movement','INSERT'),
  'A27: the movement ledger is deny-all to clients (AO, §9.4)');

-- EXEC classes
SELECT ok(has_function_privilege('authenticated','venue.create_ticket_type(uuid, text, text, integer, text, text)','EXECUTE')
       AND has_function_privilege('authenticated','venue.reserve_primary_inventory(uuid, integer, text)','EXECUTE')
       AND has_function_privilege('authenticated','catalog.publish_event(uuid, text, text)','EXECUTE'),
  'A28: the caller-authorized RPCs are authenticated');
SELECT ok(has_function_privilege('service_role','venue.sweep_expired_inventory_holds(int)','EXECUTE')
       AND NOT has_function_privilege('authenticated','venue.sweep_expired_inventory_holds(int)','EXECUTE')
       AND NOT has_function_privilege('anon','venue.sweep_expired_inventory_holds(int)','EXECUTE'),
  'A29: the hold sweep is DEF — service_role only (§20.3.3)');

-- native issuance / buy now stay dark; FK still 084's
SELECT is((SELECT value::text FROM catalog.platform_config WHERE key='feature.native_issuance_enabled' ORDER BY version DESC LIMIT 1),
  'false', 'A30: NATIVE ISSUANCE stays dark — 081 built the substrate, not the switch');
SELECT is((SELECT value::text FROM catalog.platform_config WHERE key='feature.native_resale_enabled' ORDER BY version DESC LIMIT 1),
  'false', 'A31: BUY NOW stays dark');
SELECT is((SELECT count(*)::int FROM pg_constraint WHERE conrelid='kernel.tickets'::regclass
            AND contype='f' AND conname LIKE '%ticket_type%'), 1,
  'A32: kernel.tickets.ticket_type_id FK is adopted by 084 (fk_tickets_ticket_type) — 081 built the target only');

-- HARDENING-1 / BP-1 / MB-4 survive
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='sweep_deletion_pending')) LIKE '%transaction_isolation%',
  'A33: HARDENING-1 survives 081');
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='deletion_blockers_custody')) LIKE '%kernel.tickets%',
  'A34: the 079 BP-1 body survives 081');

-- ============================================================================
-- SECTION B — fixtures + ticket type / batch creation (§5.1/§5.2)
-- ============================================================================

SELECT tap.login(tap.seller());
SELECT tap._store145('org',
  (kernel.create_organization('Inv Co','Inv Co','ck-o-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch145('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store145('venue',
  (catalog.create_venue(tap._fetch145('org')::uuid,'Hall','wynwood',NULL,'ck-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch145('venue')::uuid,'approved','miami_gate','ck-a-1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store145('event',
  (catalog.create_event(tap._fetch145('venue')::uuid,'Inv Night',
     jsonb_build_object('starts_at',(now()+interval '20 days')::text,
                        'ends_at',(now()+interval '20 days 5 hours')::text),'ck-e-1') ->> 'event_id'));
SELECT tap._store145('session',
  (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch145('event')::uuid));

-- a fan cannot create a ticket type
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.create_ticket_type(%L,'admission','GA',5000,'public','ck-tt-x')$$,
  tap._fetch145('event')), '42501', NULL, 'B1: a fan cannot create a ticket type');
SELECT tap.logout();

SELECT tap.login(tap.seller());
SELECT tap._store145('tt',
  (venue.create_ticket_type(tap._fetch145('event')::uuid,'admission','GA',5000,'public','ck-tt-1') ->> 'ticket_type_id'));
SELECT is((SELECT price_minor FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tt')::uuid), 5000,
  'B2: org_owner creates a ticket type — price snapshot stored');
SELECT throws_ok(format($$SELECT venue.create_ticket_type(%L,'admission','GA',6000,'public','ck-tt-2')$$,
  tap._fetch145('event')), NULL, NULL, 'B3: UNIQUE(event_id,name) — a duplicate name raises');
SELECT throws_ok(format($$SELECT venue.create_ticket_type(%L,'admission','VIP',0,'public','ck-tt-3')$$,
  tap._fetch145('event')), NULL, NULL, 'B4: price_minor must be > 0');
SELECT throws_ok(format($$SELECT venue.create_ticket_type(%L,'balcony','VIP',9000,'public','ck-tt-4')$$,
  tap._fetch145('event')), NULL, NULL, 'B5: kind outside {admission,table} raises');

-- price change (§20.3.1)
SELECT is((venue.set_ticket_type_price(tap._fetch145('tt')::uuid, 5500, 'demand', 'ck-p-1') ->> 'price_minor'), '5500',
  'B6: set_ticket_type_price with a reason updates');
SELECT is((venue.set_ticket_type_price(tap._fetch145('tt')::uuid, 5500, 'demand', 'ck-p-2') ->> 'status'), 'noop_replay',
  'B7: an identical price is noop_replay');
SELECT throws_ok(format($$SELECT venue.set_ticket_type_price(%L, 6000, NULL, 'ck-p-3')$$, tap._fetch145('tt')),
  NULL, NULL, 'B8: a price change requires a reason code');

-- batch creation (§5.2)
SELECT tap._store145('batch',
  (venue.create_inventory_batch(tap._fetch145('tt')::uuid, tap._fetch145('session')::uuid,
     'public_sale', 100, 0, 'ck-b-1') ->> 'batch_id'));
SELECT is(tap._cap(tap._fetch145('batch')::uuid), 100,
  'B9: create_inventory_batch — capacity set, held/sold default 0 (counter via definer, E-29)');
SELECT is(tap._rem(tap._fetch145('batch')::uuid), 100,
  'B10: remaining computes to capacity for a fresh batch');
SELECT throws_ok(format($$SELECT venue.create_inventory_batch(%L, %L, 'public_sale', 30, 4, 'ck-b-2')$$,
  tap._fetch145('tt'), tap._fetch145('session')), NULL, NULL,
  'B11: E-32 — create_inventory_batch REFUSES shard_count>0 (sharding deferred, schema §3.3 MVP-optional)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.inventory_batch_shard), 0,
  'B12: …so NO shard row is ever created — the aggregate counter is the single oversell guard');
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.create_inventory_batch(%L, %L, 'public_sale', 0, 0, 'ck-b-3')$$,
  tap._fetch145('tt'), tap._fetch145('session')), NULL, NULL, 'B13: capacity must be > 0');

-- ============================================================================
-- SECTION C — set_batch_capacity (§20.3.2; T-RPC-INV-02/-03; the C27 floor)
-- ============================================================================

SELECT is((venue.set_batch_capacity(tap._fetch145('batch')::uuid, 150, 'expansion', 'ck-c-1') ->> 'capacity'), '150',
  'C1: a grow is permitted');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.inventory_movement
            WHERE batch_id = tap._fetch145('batch')::uuid AND movement_kind='capacity_change'), 1,
  'C2: …and writes a capacity_change ledger row (C27: every delta has a ledger row)');
-- stage held+sold > 0 as postgres, then prove the floor
UPDATE venue.inventory_batch SET held = 40 WHERE batch_id = tap._fetch145('batch')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.set_batch_capacity(%L, 30, 'shrink', 'ck-c-2')$$, tap._fetch145('batch')),
  NULL, NULL, 'C3: T-RPC-INV-02 — a shrink BELOW held+sold raises below_committed (the absolute C27 floor)');
SELECT is((venue.set_batch_capacity(tap._fetch145('batch')::uuid, 50, 'shrink', 'ck-c-3') ->> 'capacity'), '50',
  'C4: a shrink to exactly >= held+sold is permitted');
SELECT throws_ok(format($$SELECT venue.set_batch_capacity(%L, 50, NULL, 'ck-c-4')$$, tap._fetch145('batch')),
  NULL, NULL, 'C5: capacity change requires a reason code');
SELECT tap.logout();
UPDATE venue.inventory_batch SET held = 0 WHERE batch_id = tap._fetch145('batch')::uuid;
-- platform_admin is DENIED set_batch_capacity entirely (§20.3.2: no platform arm)
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT venue.set_batch_capacity(%L, 200, 'support', 'ck-c-5')$$, tap._fetch145('batch')),
  '42501', NULL, 'C6: T-RPC-INV-02 — even platform_admin is refused a capacity edit (a room edit is not a support action)');
SELECT tap.logout();

-- (T-RPC-INV-03 sharded grow deferred with sharding, E-32.)
SELECT tap.login(tap.seller());
SELECT is((SELECT is_sharded FROM venue.inventory_batch WHERE batch_id = tap._fetch145('batch')::uuid), false,
  'C7: E-32 — every batch is unsharded (is_sharded=false); no shard machinery is live');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.inventory_batch_shard), 0,
  'C8: …and no shard row exists anywhere in the schema');

-- ============================================================================
-- SECTION D — the OVERSELL PROOF + the native-issuance dark gate
-- ============================================================================

-- reserve refuses while native issuance is DARK (feature_disabled), so the
-- substrate provably cannot draw. This is the §7 requirement.
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck-r-1')$$, tap._fetch145('batch')),
  NULL, NULL, 'D1: reserve refuses feature_disabled while native issuance is dark — no counter draw is reachable');
SELECT tap.logout();

-- The oversell CHECK itself, exercised directly as postgres (the constraint, not
-- the RPC — proving remaining can never go negative by construction, §3.3.1 pt 1).
SELECT throws_ok(format($$UPDATE venue.inventory_batch SET held = 60, sold = 60 WHERE batch_id = %L$$,
  tap._fetch145('batch')), '23514', NULL,
  'D2: §3.3.1 — the oversell CHECK aborts any write leaving held+sold>capacity (remaining<0 is impossible)');
SELECT throws_ok(format($$UPDATE venue.inventory_batch SET held = -1 WHERE batch_id = %L$$,
  tap._fetch145('batch')), '23514', NULL, 'D3: negative held is impossible');
-- no client can write the counter directly at all (single-writer, §3.3.1 point 3)
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$UPDATE venue.inventory_batch SET sold = 1 WHERE batch_id = %L$$, tap._fetch145('batch')),
  '42501', NULL, 'D4: even an org_owner cannot write held/sold directly — single-writer, RPC-only');
SELECT throws_ok(format($$INSERT INTO venue.inventory_movement (batch_id, movement_kind, cause, cause_ref)
  VALUES (%L, 'hold', 'primary_sale', gen_random_uuid())$$, tap._fetch145('batch')),
  '42501', NULL, 'D5: no client can append to the movement ledger directly (AO, RPC-only)');
SELECT tap.logout();

-- ============================================================================
-- SECTION E — the HOLD SWEEP (§20.3.3; G-24; T-RPC-INV-04/-05/-06)
-- Native issuance is dark, so holds are staged directly (as the issue path would).
-- ============================================================================

-- stage two active holds, one already expired
SELECT tap.logout();
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000a0001', tap._fetch145('batch')::uuid, tap.buyer(), 3, 'active', now() - interval '1 minute', 'ck-h-1'),
       ('00000000-0000-0000-0000-0000000a0002', tap._fetch145('batch')::uuid, tap.buyer(), 2, 'active', now() + interval '1 hour', 'ck-h-2');
UPDATE venue.inventory_batch SET held = 5 WHERE batch_id = tap._fetch145('batch')::uuid;   -- 3+2 held

SELECT is(tap._rem(tap._fetch145('batch')::uuid), 45,
  'E1: T-RPC-INV-04 — with the expired hold UNSWEPT, remaining is provably reduced (50-5)');
SELECT is((venue.sweep_expired_inventory_holds() ->> 'swept')::int, 1,
  'E2: the sweep releases exactly the ONE expired hold');
SELECT is((SELECT status FROM venue.inventory_hold WHERE hold_id = '00000000-0000-0000-0000-0000000a0001'), 'expired',
  'E3: the expired hold flips active -> expired');
SELECT is(tap._rem(tap._fetch145('batch')::uuid), 48,
  'E4: T-RPC-INV-04 — held is RETURNED (50-2=48): the sweep is LOAD-BEARING, not cosmetic');
SELECT is((SELECT status FROM venue.inventory_hold WHERE hold_id = '00000000-0000-0000-0000-0000000a0002'), 'active',
  'E5: the unexpired hold is untouched');
SELECT is((venue.sweep_expired_inventory_holds() ->> 'swept')::int, 0,
  'E6: T-RPC-INV-06 — a re-run over the same window releases nothing further');
-- a hold that CONVERTED is not re-released (§20.3.3 skip-converted; -05 shape)
UPDATE venue.inventory_hold SET status='converted', expires_at = now() - interval '1 minute'
 WHERE hold_id = '00000000-0000-0000-0000-0000000a0002';
SELECT is((venue.sweep_expired_inventory_holds() ->> 'swept')::int, 0,
  'E7: T-RPC-INV-05 — a converted hold is SKIPPED, not released (releasing it would return sold capacity)');
SELECT is(tap._held(tap._fetch145('batch')::uuid), 2,
  'E8: …the counter is unchanged by that pass');

-- the movement ledger reconciles: a release row was appended for the swept hold
SELECT is((SELECT count(*)::int FROM venue.inventory_movement
            WHERE cause_ref = '00000000-0000-0000-0000-0000000a0001' AND movement_kind='release'), 1,
  'E9: the sweep wrote a release movement (the ledger reconciles to the counter)');

-- ============================================================================
-- SECTION F — publish_event (§4.2; SEAM-1; the empty-inventory guard)
-- ============================================================================

-- a fresh event with NO inventory cannot go on_sale
SELECT tap.login(tap.seller());
SELECT tap._store145('event2',
  (catalog.create_event(tap._fetch145('venue')::uuid,'Empty Night',
     jsonb_build_object('starts_at',(now()+interval '25 days')::text),'ck-e2') ->> 'event_id'));
SELECT is((catalog.publish_event(tap._fetch145('event2')::uuid, 'announced', 'ck-pub-1') ->> 'event_status'),
  'announced', 'F1: draft -> announced is a legal forward transition');
SELECT throws_ok(format($$SELECT catalog.publish_event(%L, 'on_sale', 'ck-pub-2')$$, tap._fetch145('event2')),
  NULL, NULL, 'F2: on_sale with NO ticket type + batch raises empty_inventory');
SELECT throws_ok(format($$SELECT catalog.publish_event(%L, 'live', 'ck-pub-3')$$, tap._fetch145('event2')),
  NULL, NULL, 'F3: announced -> live is an illegal (skipping) transition');
SELECT throws_ok(format($$SELECT catalog.publish_event(%L, 'cancelled', 'ck-pub-4')$$, tap._fetch145('event2')),
  NULL, NULL, 'F4: cancellation is NOT a publish target (it is catalog.cancel_event)');

-- the event WITH inventory can reach on_sale
SELECT is((catalog.publish_event(tap._fetch145('event')::uuid, 'announced', 'ck-pub-5') ->> 'event_status'),
  'announced', 'F5: the inventoried event announces');
SELECT is((catalog.publish_event(tap._fetch145('event')::uuid, 'on_sale', 'ck-pub-6') ->> 'event_status'),
  'on_sale', 'F6: …and reaches on_sale (>=1 ticket type WITH a batch, the SEAM-1 read)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT catalog.publish_event(%L, 'live', 'ck-pub-7')$$, tap._fetch145('event')),
  '42501', NULL, 'F7: a fan cannot publish');
SELECT tap.logout();

-- now native issuance is on_sale — but the FLAG is still false, so reserve
-- STILL refuses feature_disabled (the flag, not the lifecycle, is the dark gate)
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck-r-2')$$, tap._fetch145('batch')),
  NULL, NULL, 'F8: even on an on_sale event, reserve refuses feature_disabled — the flag is the gate, not the status');
SELECT tap.logout();

-- ============================================================================
-- SECTION G — E-28: the flag-flip proves the unseeded PFA-9 keys fail-safe
-- (a controlled probe: flip the flag in this rolled-back txn to reach the
--  TTL/cap reads and prove they REFUSE rather than invent policy)
-- ============================================================================

SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key='inventory.hold_ttl_interval'), 0,
  'G1: E-28 — inventory.hold_ttl_interval is UNSEEDED (a PFA-9 CLASS A key, no frozen spelling)');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key='inventory.per_user_active_hold_max'), 0,
  'G2: E-28 — inventory.per_user_active_hold_max is UNSEEDED');
-- event must be on_sale for the per-user/TTL path; it is (F6). The per-user cap
-- is read BEFORE the TTL; unseeded cap => 0 => refuse (fail-to-zero, loud).
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck-r-3')$$, tap._fetch145('batch')),
  NULL, NULL, 'G3: E-28 — with the flag flipped but the cap unseeded, reserve REFUSES (fail-to-zero, never unbounded)');
SELECT tap.logout();
-- seed the cap, leave TTL unseeded => refuse hold_ttl_unset (never invents a TTL)
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('inventory.per_user_active_hold_max', 1, '4'::jsonb, 'restricted');
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck-r-4')$$, tap._fetch145('batch')),
  NULL, NULL, 'G4: E-28 — cap seeded, TTL still unseeded: reserve REFUSES hold_ttl_unset (a TTL is policy, never invented)');
SELECT tap.logout();
-- seed the TTL => reserve now DRAWS (the oversell choke-point works end-to-end)
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('inventory.hold_ttl_interval', 1, '"15 minutes"'::jsonb, 'restricted');
SELECT tap.login(tap.buyer());
SELECT is((venue.reserve_primary_inventory(tap._fetch145('batch')::uuid, 1, 'ck-r-5') ->> 'status'), 'ok',
  'G5: with both keys seeded AND the flag on, reserve draws — the choke-point works end to end');
SELECT ok((venue.reserve_primary_inventory(tap._fetch145('batch')::uuid, 1, 'ck-r-6') ->> 'expires_at') IS NOT NULL,
  'G6: …and returns a server-set expiry');
-- F-1: a DELETION_PENDING caller cannot acquire
SELECT tap.logout();
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.buyer(),'ACTIVE')
  ON CONFLICT (identity_id) DO UPDATE SET deletion_state='DELETION_PENDING';
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck-r-7')$$, tap._fetch145('batch')),
  NULL, NULL, 'G7: OR-17 F-1 — a DELETION_PENDING caller is refused deletion_pending (may not acquire new inventory)');
SELECT tap.logout();
UPDATE kernel.identity_ext SET deletion_state='ACTIVE' WHERE identity_id = tap.buyer();

-- ============================================================================
-- SECTION H — RLS reads (ticket_type visibility; hold owner scope; counter hide)
-- ============================================================================

SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tt')::uuid), 1,
  'H1: a fan reads a PUBLIC-visibility ticket type');
SELECT is((SELECT remaining FROM venue.inventory_batch WHERE batch_id = tap._fetch145('batch')::uuid),
          tap._rem(tap._fetch145('batch')::uuid),
  'H2: a fan reads remaining, matching the authoritative value (the availability projection)');
SELECT throws_ok(format($$SELECT held FROM venue.inventory_batch WHERE batch_id = %L$$, tap._fetch145('batch')),
  '42501', NULL, 'H3: E-29 — a fan cannot select the raw counter column');
SELECT is((SELECT count(*)::int FROM venue.inventory_hold
            WHERE identity_id = tap.buyer() AND status='active'), 2,
  'H4: the holder reads their own ACTIVE holds (the two ck-r-5/6 draws)');
SELECT tap.logout();
-- a hidden ticket type is invisible to a fan
SELECT tap.login(tap.seller());
SELECT tap._store145('tth',
  (venue.create_ticket_type(tap._fetch145('event')::uuid,'table','Backstage',20000,'hidden','ck-tt-h') ->> 'ticket_type_id'));
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tth')::uuid), 0,
  'H5: a fan cannot see a HIDDEN ticket type');
SELECT is((SELECT count(*)::int FROM venue.inventory_hold WHERE identity_id <> tap.buyer()), 0,
  'H6: a fan sees no other holder''s holds');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tth')::uuid), 1,
  'H7: the venue org_owner reads the hidden type (venue-scoped, the top tier)');
SELECT tap.logout();
INSERT INTO auth.users (id,email,role,instance_id,aud,created_at,updated_at)
VALUES ('00000000-0000-0000-0000-00000000f501','lp@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now())
ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT venue.grant_staff_role(tap._fetch145('venue')::uuid,'00000000-0000-0000-0000-00000000f501','venue_marketing','ck-sr-1');
SELECT venue.grant_staff_role(tap._fetch145('venue')::uuid,'00000000-0000-0000-0000-00000000f501','venue_scanner','ck-sr-2');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000f501');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tth')::uuid), 0,
  'H7a: B-P1 — a venue_marketing/scanner reads ZERO hidden ticket types (the §9.1 two-tier split; no name/price leak)');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tt')::uuid), 1,
  'H7b: …but DOES read the public type (the lower tier gets public + door_only, never hidden)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok('SELECT count(*) FROM venue.inventory_movement', '42501', NULL,
  'H8: anon cannot read the movement ledger');
SELECT throws_ok('SELECT count(*) FROM venue.ticket_type', '42501', NULL,
  'H9: E-30 — anon is walled from the ENTIRE venue schema (076 grants venue USAGE to authenticated only), so §9.1''s anon-public arm is undeliverable here; fail-closed');
SELECT tap.logout();
-- the public-availability read IS delivered to any authenticated fan:
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = tap._fetch145('tt')::uuid), 1,
  'H10: an authenticated fan reads the public ticket type (the deliverable half of §9.1)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
