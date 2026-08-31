-- ============================================================================
-- 140_phase2_outbox_foundation.sql — Phase-2 package 076.
--
-- FROZEN SOURCE (baseline 06fd5ec / phase2-architecture-v2):
--   plan §8/076 Tests row · registry 076 · contracts §17.24/§17.24a/§20.16 ·
--   schema §13.3 (C12 envelope) · OR-1/OR-12 choice 9 (inverted D-1) ·
--   R2 (OR-14: BEST-EFFORT vs REQUIRED emission; N-A30 no-swallow-in-REQUIRED).
--
-- Every assertion below cites the frozen requirement it witnesses. The
-- transactional proofs (REQ-1/BE-1) are REAL PostgreSQL subtransaction
-- proofs: the producer mutation and the envelope write live in one atomic
-- statement, and the assertion observes whether the producer mutation
-- survived — not a unit-test simulation.
-- ============================================================================

BEGIN;
SELECT plan(59);

-- ---------------------------------------------------------------------------
-- A. The five schemas + the GRANT boundary (frozen §8/076 Tests: "\dn shows
--    five schemas"; USAGE booleans; deny-by-default wall).
-- ---------------------------------------------------------------------------
SELECT has_schema('kernel',  'schema kernel exists (076)');
SELECT has_schema('catalog', 'schema catalog exists (076)');
SELECT has_schema('venue',   'schema venue exists (076)');
SELECT has_schema('market',  'schema market exists (076)');
SELECT has_schema('notify',  'schema notify exists (076, OR-12 fifth schema)');

SELECT is(has_schema_privilege('anon','kernel','USAGE'),  false, 'anon has NO USAGE on kernel (frozen Tests row)');
SELECT is(has_schema_privilege('anon','notify','USAGE'),  false, 'anon has NO USAGE on notify (OR-12/F-P1-7 wall)');
SELECT is(has_schema_privilege('authenticated','notify','USAGE'), false, 'authenticated has NO USAGE on notify');
SELECT is(has_schema_privilege('anon','catalog','USAGE'), true,  'anon HAS USAGE on catalog (frozen Tests row)');
SELECT is(has_schema_privilege('authenticated','catalog','USAGE'), true, 'authenticated HAS USAGE on catalog');
SELECT is(has_schema_privilege('authenticated','kernel','USAGE'), true, 'authenticated USAGE on kernel (function-EXECUTE-only)');
SELECT is(has_schema_privilege('authenticated','venue','USAGE'),  true, 'authenticated USAGE on venue (function-EXECUTE-only)');
SELECT is(has_schema_privilege('authenticated','market','USAGE'), true, 'authenticated USAGE on market (function-EXECUTE-only)');
SELECT is(has_schema_privilege('service_role','notify','USAGE'),  true, 'service_role USAGE on notify (emit pair is service_role-only, NOTIF §4.3)');

-- ---------------------------------------------------------------------------
-- B. OR-1 / OR-12 choice 9 — the inverted D-1 structural assertion:
--    pg_roles contains NO crm_export_builder after 076 (re-asserted
--    chain-final after 092 by that package's suite).
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM pg_roles WHERE rolname = 'crm_export_builder'),
  0,
  'OR-1/choice 9: crm_export_builder exists NOWHERE in pg_roles (inverted D-1)');

-- ---------------------------------------------------------------------------
-- C. Shared helpers (contracts §20.16; frozen Tests: "Helpers owned by
--    postgres with pinned search_path").
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'
      AND p.proname IN ('set_updated_at','raise_append_only')
      AND pg_get_userbyid(p.proowner) = 'postgres'
      AND p.prosecdef
      AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) c
                   WHERE c = 'search_path=""')),
  2,
  'both kernel helpers: SECURITY DEFINER (frozen plan :531), owned by postgres, search_path pinned to EMPTY');

-- ---------------------------------------------------------------------------
-- D. The ALTER DEFAULT PRIVILEGES belt: no default table grant for
--    anon/authenticated (or PUBLIC) in the four walled schemas.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int
     FROM pg_default_acl d
     JOIN pg_namespace n ON n.oid = d.defaclnamespace
    CROSS JOIN LATERAL aclexplode(d.defaclacl) a
    WHERE n.nspname IN ('kernel','venue','market','notify')
      AND d.defaclobjtype = 'r'
      AND (a.grantee = 0  -- PUBLIC
           OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated')))),
  0,
  'default-privileges belt: zero default table rights for PUBLIC/anon/authenticated in kernel/venue/market/notify');

-- ---------------------------------------------------------------------------
-- E. notify.outbox — the C12 envelope, column-for-column (schema §13.3).
-- ---------------------------------------------------------------------------
SELECT has_table('notify','outbox','notify.outbox exists (OR-12/OR-4 — COND-A RULED)');

SELECT is(
  (SELECT string_agg(column_name::text, ',' ORDER BY column_name::text COLLATE "C")
     FROM information_schema.columns
    WHERE table_schema='notify' AND table_name='outbox'),
  'aggregate_id,aggregate_kind,attempt,causation_id,claimed_until,correlation_id,created_at,event_key,event_type,last_error,occurred_at,outbox_id,payload,sequence,state',
  'C12 envelope: exactly the fifteen frozen columns, no more, no fewer');

SELECT throws_ok(
  $q$ INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload, occurred_at, state)
      VALUES ('tap_bad_state','tap_agg', gen_random_uuid(), 1, 'tap_bad_state:1', '{}'::jsonb, now(), 'bogus') $q$,
  '23514', NULL,
  'state CHECK admits only pending/claimed/done/dead');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='notify' AND tablename='outbox'
           AND indexdef LIKE '%UNIQUE%(event_type, event_key)%'),
  'UNIQUE(event_type, event_key) — the idempotency key (C12)');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='notify' AND tablename='outbox'
           AND indexdef LIKE '%UNIQUE%(aggregate_kind, aggregate_id, sequence)%'),
  'UNIQUE(aggregate_kind, aggregate_id, sequence) — the per-aggregate ordering key (C12)');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='notify' AND tablename='outbox'
           AND indexdef LIKE '%(state, occurred_at)%'
           AND indexdef ILIKE '%WHERE%state%pending%claimed%'),
  'partial drain index (state, occurred_at) WHERE state IN (pending, claimed)');

SELECT ok(
  (SELECT relrowsecurity AND NOT relforcerowsecurity
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='notify' AND c.relname='outbox')
  AND (SELECT count(*) FROM pg_policies WHERE schemaname='notify' AND tablename='outbox') = 0,
  'outbox: RLS enabled, NOT forced (the sanctioned owner-definer path), ZERO policies — deny-all, RPC-only');

-- ---------------------------------------------------------------------------
-- F. Hostile-role catalog + direct-mutation attacks (mission §7/§8: prove
--    from catalog state AND by hostile execution, never "RLS protects it").
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM information_schema.role_table_grants
    WHERE table_schema='notify' AND table_name='outbox'
      AND grantee IN ('anon','authenticated','PUBLIC')),
  0,
  'catalog: zero outbox table grants for anon/authenticated/PUBLIC');

SELECT is(
  (SELECT count(*)::int FROM information_schema.role_table_grants
    WHERE table_schema='notify' AND table_name='outbox' AND grantee <> 'postgres'),
  0,
  'outbox: postgres is the SOLE grantee — service_role (BYPASSRLS) holds zero table grants; the grant wall is its only wall and it is watched (review C-F8/E-F3)');

-- Re-scoped at package 077 (PFA-1's own standing obligation: "every later
-- package's suite keeps this sweep green over its own functions"): the
-- INVARIANT arms — zero PUBLIC and zero anon EXECUTE on ANY walled-schema
-- function, forever — stay here unchanged. The authenticated arm is no longer
-- a global zero once RLS §11's caller-authorized class exists (077's client
-- RPCs carry GRANT EXECUTE TO authenticated BY FROZEN CONTRACT), so from 077
-- each package's suite asserts its own schema's authenticated EXECUTE closure
-- by EXACT NAME EQUALITY (kernel: 141 test F2), and this sweep pins
-- authenticated at zero for the schemas that still have no caller-authorized
-- function (venue, market, notify).
SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE a.privilege_type = 'EXECUTE'
      AND (   (n.nspname IN ('kernel','venue','market','notify')
               AND (a.grantee = 0
                    OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname = 'anon')))
           OR (n.nspname IN ('venue','market','notify')
               AND a.grantee IN (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
               -- 2026-08-31 (package 080): venue gains its FIRST two
               -- caller-authorized functions (RLS §11.1 rows: grant_staff_role /
               -- revoke_staff_role, G-13). Named, not counted, so the sweep
               -- still pins every OTHER venue/market/notify function at zero.
               -- 2026-08-31 (package 081): venue's inventory RPCs are
               -- caller-authorized (RLS §9.1/§9.2/§20.3). The DEF hold sweep is
               -- service_role (not authenticated) so it is not excepted here.
               -- 2026-08-31 (package 082): venue.create_primary_checkout is
               -- caller-authorized (RLS §9.7). cancel_pending_order is service_role
               -- and the two order guard trigger fns hold no EXECUTE — not excepted.
               AND p.proname NOT IN ('grant_staff_role','revoke_staff_role',
                     'create_ticket_type','set_ticket_type_price','create_inventory_batch',
                     'set_batch_capacity','reserve_primary_inventory','create_inventory_hold',
                     'release_inventory_hold','create_primary_checkout')))),
  0,
  'PFA-1 witness: zero PUBLIC/anon EXECUTE on ANY walled-schema function, and zero authenticated EXECUTE outside kernel''s name-equality-asserted caller-authorized set (141 F2) — the per-object sweep replacing the impossible per-schema functions belt');

SELECT tap.login('11111111-1111-1111-1111-111111111111');
SELECT throws_ok(
  $q$ INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload, occurred_at, state)
      VALUES ('tap_evil','tap_agg', gen_random_uuid(), 1, 'tap_evil:1', '{}'::jsonb, now(), 'pending') $q$,
  '42501', NULL, 'authenticated direct outbox INSERT is refused (42501)');
SELECT throws_ok(
  $q$ UPDATE notify.outbox SET state='done' $q$,
  '42501', NULL, 'authenticated direct outbox UPDATE is refused (42501)');
SELECT throws_ok(
  $q$ DELETE FROM notify.outbox $q$,
  '42501', NULL, 'authenticated direct outbox DELETE is refused (42501)');
SELECT throws_ok(
  $q$ SELECT notify.emit_event('tap_evil','tap_agg', gen_random_uuid(), 'tap_evil:2') $q$,
  '42501', NULL, 'authenticated CANNOT call notify.emit_event (service_role-only)');
SELECT tap.logout();

SELECT tap.login_anon();
SELECT throws_ok(
  $q$ SELECT count(*) FROM notify.outbox $q$,
  '42501', NULL, 'anon direct outbox SELECT is refused (42501)');
SELECT tap.logout();

SELECT is(has_function_privilege('authenticated','notify.emit_event(text,text,uuid,text,jsonb,uuid,uuid)','execute'),
  false, 'authenticated holds no EXECUTE on emit_event');
SELECT is(has_function_privilege('anon','notify.emit_event_required(text,text,uuid,text,jsonb,uuid,uuid)','execute'),
  false, 'anon holds no EXECUTE on emit_event_required');
SELECT is(
  has_function_privilege('service_role','notify.emit_event(text,text,uuid,text,jsonb,uuid,uuid)','execute')
  AND has_function_privilege('service_role','notify.emit_event_required(text,text,uuid,text,jsonb,uuid,uuid)','execute'),
  true, 'service_role holds EXECUTE on BOTH emit functions (NOTIF §4.3)');

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='notify' AND p.proname IN ('emit_event','emit_event_required')
      AND p.prosecdef
      AND pg_get_userbyid(p.proowner)='postgres'
      AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) c
                   WHERE c = 'search_path=""')),
  2,
  'emit pair: SECURITY DEFINER, owned by postgres, search_path pinned to EMPTY');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='notify' AND p.proname='emit_event'
             AND 'lock_timeout=2s' = ANY (coalesce(p.proconfig,'{}'::text[]))),
  'PFA-2: emit_event carries lock_timeout=2s — a blocked envelope becomes 55P03 (caught) instead of consuming the producer statement-timeout budget (57014 pierces WHEN OTHERS)');

-- ---------------------------------------------------------------------------
-- G. Envelope behavior (as the trusted definer/service path — tap.logout()
--    state; §17.24 shared semantics).
-- ---------------------------------------------------------------------------
SELECT lives_ok(
  $q$ SELECT notify.emit_event('tap_happy','tap_agg_a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','tap_happy:1','{"id":1}'::jsonb) $q$,
  'BE emit: happy path succeeds');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox WHERE event_type='tap_happy'),
  1, 'BE emit wrote exactly one pending envelope');
SELECT ok(
  (SELECT state='pending' AND sequence=1 AND payload->>'id'='1'
     FROM notify.outbox WHERE event_type='tap_happy'),
  'envelope born pending, sequence 1, payload preserved');

SELECT lives_ok(
  $q$ SELECT notify.emit_event('tap_happy','tap_agg_a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','tap_happy:1','{"id":1}'::jsonb) $q$,
  'BE replay of the same (event_type, event_key) is a successful no-op');
SELECT lives_ok(
  $q$ SELECT notify.emit_event_required('tap_happy','tap_agg_a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','tap_happy:1','{"id":1}'::jsonb) $q$,
  'REQUIRED replay of the same (event_type, event_key) is a successful no-op — replay must never raise');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox WHERE event_type='tap_happy'),
  1, 'idempotency: still exactly one envelope after both replays');

SELECT lives_ok(
  $q$ SELECT notify.emit_event_required('tap_second','tap_agg_a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','tap_second:1') $q$,
  'second event on the same aggregate succeeds (REQUIRED)');
SELECT is(
  (SELECT sequence::int FROM notify.outbox WHERE event_type='tap_second'),
  2, 'sequence advances per (aggregate_kind, aggregate_id): 1 → 2');
SELECT lives_ok(
  $q$ SELECT notify.emit_event('tap_other','tap_agg_b','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','tap_other:1') $q$,
  'a different aggregate starts its own sequence');
SELECT is(
  (SELECT sequence::int FROM notify.outbox WHERE event_type='tap_other'),
  1, 'per-aggregate sequence isolation: the other aggregate starts at 1');

-- ---------------------------------------------------------------------------
-- H. THE TRANSACTIONAL PROOFS (mission §6/§5) — real subtransaction
--    atomicity: one DO block = producer mutation + envelope attempt; the
--    surviving state proves the contract.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE tap_producer_work (id int, note text);

-- REQ-1: producer mutation + REQUIRED envelope failure = producer ROLLBACK.
SELECT throws_ok(
  $q$ DO $body$
      BEGIN
        INSERT INTO tap_producer_work VALUES (1, 'money row that must NOT survive');
        PERFORM notify.emit_event_required(
          'tap_req_fail','tap_agg_c','cccccccc-cccc-cccc-cccc-cccccccccccc',
          NULL);  -- event_key NULL -> NOT NULL violation on the envelope
      END $body$ $q$,
  '23502', NULL,
  'REQUIRED: a failed envelope write RAISES out of the producer body (§17.24a)');
SELECT is(
  (SELECT count(*)::int FROM tap_producer_work WHERE id = 1),
  0,
  'REQ-1 PROOF: the producer mutation ROLLED BACK with the failed REQUIRED envelope — atomic, not simulated');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox WHERE event_type='tap_req_fail'),
  0, 'REQ-1: no partial envelope survived either');

-- BE-1: producer mutation + BEST-EFFORT envelope failure = producer SURVIVES.
SELECT lives_ok(
  $q$ DO $body$
      BEGIN
        INSERT INTO tap_producer_work VALUES (2, 'money row that MUST survive');
        PERFORM notify.emit_event(
          'tap_be_fail','tap_agg_c','cccccccc-cccc-cccc-cccc-cccccccccccc',
          NULL);  -- same failure, BE class: warning + continue
      END $body$ $q$,
  'BEST-EFFORT: a failed envelope write does NOT raise (§17.24 — warning + commit)');
SELECT is(
  (SELECT count(*)::int FROM tap_producer_work WHERE id = 2),
  1,
  'BE-1 PROOF: the producer mutation SURVIVED the failed BEST-EFFORT envelope');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox WHERE event_type='tap_be_fail'),
  0, 'BE-1: the envelope was lost (logged), never half-written');

-- C-F5: a rolled-back producer consumed NO sequence — tap_agg_c saw two
-- failed emits (REQ-1 rolled back, BE-1 lost); the next successful emit on it
-- must allocate sequence 1, witnessing the gaplessness max()+1 was chosen for.
SELECT lives_ok(
  $q$ SELECT notify.emit_event('tap_gapless','tap_agg_c','cccccccc-cccc-cccc-cccc-cccccccccccc','tap_gapless:1') $q$,
  'post-rollback emit on the aggregate succeeds');
SELECT is(
  (SELECT sequence::int FROM notify.outbox WHERE event_type='tap_gapless'),
  1, 'C-F5 PROOF: rolled-back producers consume no sequence — the aggregate starts at 1');

-- PFA-2 (E-F1): same (event_type, event_key) reused for a DIFFERENT aggregate
-- violates NOTIF §4.2 (the key IS the business event); REQUIRED must raise
-- rather than silently lose the envelope.
SELECT throws_ok(
  $q$ SELECT notify.emit_event_required('tap_happy','tap_agg_OTHER','99999999-9999-9999-9999-999999999999','tap_happy:1') $q$,
  'P0001', NULL,
  'PFA-2 PROOF: a key collision with a DIFFERENT aggregate RAISES in the REQUIRED class — never a silent loss');

-- ---------------------------------------------------------------------------
-- I. The unlocked-concurrency backstop (§17.24: sequence is allocated under
--    the aggregate's existing row lock; an emitter violating that collides on
--    the per-aggregate UNIQUE — warning for BE, raise for REQUIRED).
-- ---------------------------------------------------------------------------
INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload, occurred_at, state)
VALUES ('tap_forged','tap_agg_d','dddddddd-dddd-dddd-dddd-dddddddddddd', 1, 'tap_forged:1', '{}'::jsonb, now(), 'pending');

SELECT throws_ok(
  $q$ DO $body$
      BEGIN
        -- simulate a second emitter that did NOT serialize on the aggregate
        -- lock: it computed the same next sequence (1) before the forged row
        -- above was visible to it — here reproduced by forcing sequence 1.
        INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload, occurred_at, state)
        VALUES ('tap_collide','tap_agg_d','dddddddd-dddd-dddd-dddd-dddddddddddd', 1, 'tap_collide:1', '{}'::jsonb, now(), 'pending');
      END $body$ $q$,
  '23505', NULL,
  'per-aggregate UNIQUE is the contracted backstop against unserialized emitters');
SELECT lives_ok(
  $q$ SELECT notify.emit_event('tap_after','tap_agg_d','dddddddd-dddd-dddd-dddd-dddddddddddd','tap_after:1') $q$,
  'a properly serialized emit after the collision succeeds (sequence 2)');
SELECT is(
  (SELECT sequence::int FROM notify.outbox WHERE event_type='tap_after'),
  2, 'the serialized emitter allocated the next free sequence');

SELECT * FROM finish();
ROLLBACK;
