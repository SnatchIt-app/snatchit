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
SELECT plan(53);

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
      AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) c
                   WHERE c LIKE 'search_path=%')),
  2,
  'both kernel helper trigger functions exist, owned by postgres, search_path pinned');

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

SELECT results_eq(
  $q$ SELECT column_name::text FROM information_schema.columns
       WHERE table_schema='notify' AND table_name='outbox' ORDER BY column_name $q$,
  ARRAY['aggregate_id','aggregate_kind','attempt','causation_id','claimed_until',
        'correlation_id','created_at','event_key','event_type','last_error',
        'occurred_at','outbox_id','payload','sequence','state'],
  'C12 envelope: exactly the fifteen frozen columns, no more, no fewer');

SELECT throws_ok(
  $q$ INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload, state)
      VALUES ('tap_bad_state','tap_agg', gen_random_uuid(), 1, 'tap_bad_state:1', '{}'::jsonb, 'bogus') $q$,
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
  (SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='notify' AND c.relname='outbox')
  AND (SELECT count(*) FROM pg_policies WHERE schemaname='notify' AND tablename='outbox') = 0,
  'outbox: RLS enabled with ZERO policies — deny-all, RPC-only');

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

SELECT tap.login('11111111-1111-1111-1111-111111111111');
SELECT throws_ok(
  $q$ INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload)
      VALUES ('tap_evil','tap_agg', gen_random_uuid(), 1, 'tap_evil:1', '{}'::jsonb) $q$,
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
                   WHERE c LIKE 'search_path=%')),
  2,
  'emit pair: SECURITY DEFINER, owned by postgres, search_path pinned');

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

-- ---------------------------------------------------------------------------
-- I. The unlocked-concurrency backstop (§17.24: sequence is allocated under
--    the aggregate's existing row lock; an emitter violating that collides on
--    the per-aggregate UNIQUE — warning for BE, raise for REQUIRED).
-- ---------------------------------------------------------------------------
INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload)
VALUES ('tap_forged','tap_agg_d','dddddddd-dddd-dddd-dddd-dddddddddddd', 1, 'tap_forged:1', '{}'::jsonb);

SELECT throws_ok(
  $q$ DO $body$
      BEGIN
        -- simulate a second emitter that did NOT serialize on the aggregate
        -- lock: it computed the same next sequence (1) before the forged row
        -- above was visible to it — here reproduced by forcing sequence 1.
        INSERT INTO notify.outbox (event_type, aggregate_kind, aggregate_id, sequence, event_key, payload)
        VALUES ('tap_collide','tap_agg_d','dddddddd-dddd-dddd-dddd-dddddddddddd', 1, 'tap_collide:1', '{}'::jsonb);
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
