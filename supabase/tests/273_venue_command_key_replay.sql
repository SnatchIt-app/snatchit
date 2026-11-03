-- ============================================================================
-- 273_venue_command_key_replay.sql — migration venue_command_key_replay (registry 204 / DB-6, pgTAP 273, D).
--
-- Guarantee under test: command-key replay for catalog.create_event, catalog.create_event_session,
-- catalog.publish_event, venue.set_ticket_type_sale_window and venue.allocate_comp. For the same actor, verb and
-- key: the same request answers {status 'noop_replay', the original ids / values} and writes nothing; a different
-- request is refused with 093's literal 'precondition_failed: idempotency_conflict — command key reused with
-- different parameters' and writes nothing; with no receipt the call behaves as before. The receipt is the verb's
-- own kernel.admin_audit row (after carries command_key_sha256 and request_sha256), so a refused call leaves none.
-- The lookup runs after authority, under a per-scope advisory lock taken after the parent-row lock.
--
--   A  posture: 204's md5s (prosrc / functiondef), ACL, SECURITY DEFINER / plpgsql / search_path / VOLATILE / jsonb /
--      owner / one overload, the COMMENTs, kernel.admin_audit's columns and indexes (all unchanged but the bodies).
--   B  static order (comments stripped): one advisory lock and one key-digest lookup per body; the lock after the
--      authority raise and before the audit lookup; publish: before the transition check; publish keeps 202's gate 4
--      and the E-76 conjunct; allocate_comp keeps one live operator assert and checks the key after it.
--   Z1 no auth.uid() (the NULL-claims arm, before any tap.login): 42501 on all five.
--   K  create_event   S  create_event_session   P  publish_event   W  set_ticket_type_sale_window   C  allocate_comp
--      Every field of each request digest is varied alone under the same key (conflict): W4 sale_ends_at, W10
--      sale_starts_at, W9 ticket_type_id, W5 reason; C5 quantity, C6 batch, C10 session, C9 reason. W3b pins the
--      values a sale-window replay returns (the original request's, not the current window).
--   X  scope: another actor with the same key is independent, for all five verbs (X1/X5 create_event and its
--      implicit session, X4 publish_event, X6 the sale window, X7 allocate_comp); one key on two verbs is
--      independent (X3).
--   Z2-Z4  a fan guessing a key, a manager whose role was deleted after a first call, an unknown event: the existing
--      refusals answer first (no receipt or conflict signal before authority / existence).
-- NOT in-suite (evidence dir D/s18-204/): the pre-flight / post-flight / rollback refusals, idempotent re-apply, the
-- apply / rollback cycle, the mutants and the concurrent-session race harness (lock waits need two sessions).
--
-- Fixture: synthetic rows as postgres with letter-bearing ids (a2730000-…); everything dies with the ROLLBACK.
-- Org A (active) owners UA and UB; venue_managers UM and UM2 bound to room VA; fan UF; rooms VA and VB (Org A,
-- approved).
-- Every call goes through tap._run273, which keeps the call's jsonb text, or 'ERROR <SQLSTATE>|<SQLERRM>', under a
-- key; the assertions read the kept values in later statements, so a refusal or a mutant never aborts the file.
--
-- Design ids are kept; C7 (issue_comp on the allocation) is not here: a scoped signing key cannot be inserted on this
-- chain (signing_key_insert_refused: scoped_key_parked), issue_comp is not changed by 204, and pgTAP 257 P10 already
-- issues an allocate_comp allocation.
--
-- Expected on main + 202 WITHOUT 204 (RED, predicted before the run; all 80 emitted): not ok (51) — A1-A5; B1 B2 B3
-- B4 B6; K2 K3 K4 K5 K6 K7 K9 K11; S2 S3 S5 S6 S8 S10; P1b P2 P3 P5 P6 P8; W1b W1c W3 W3b W4 W5 W8 W9 W10; C1 C3 C4
-- C5 C6 C9 C10 C8; X2 X5 X6 X7. Passing on RED by design (29): A6-A9 B5 Z1 K1 K8 K10 S1 S3a S4 S9 S7 P1 P4 P7 W1 W2
-- W6 W7 C2 X1 X3 X4 Z2 Z3a Z3 Z4 (first calls, refusals and residual R6, which 204 must leave as they were).
-- ============================================================================
BEGIN;
SELECT plan(80);

CREATE TABLE tap.memo_273 (k text PRIMARY KEY, v text);
-- RETURNS void: a kept value never reaches the TAP stream (pg_prove reads an output line starting "ok" as a test).
CREATE FUNCTION tap._put273(k text, v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_273 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._get273(k text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_273 WHERE k = $1 $m$;
-- the value helper: the text a call returns AS THE CALLER, or 'ERROR <SQLSTATE>|<SQLERRM>'; it never aborts the file
CREATE FUNCTION tap._try273(q text) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN 'ERROR ' || SQLSTATE || '|' || SQLERRM; END $m$;
-- run one call as the current caller and keep its result (the write); assertions read it later (the read)
CREATE FUNCTION tap._run273(k text, q text) RETURNS void LANGUAGE plpgsql AS
$m$ BEGIN PERFORM tap._put273(k, tap._try273(q)); END $m$;
-- one field of a kept result, or the kept error text
CREATE FUNCTION tap._f273(k text, f text) RETURNS text LANGUAGE sql STABLE AS
$m$ SELECT CASE WHEN v IS NULL THEN '<no result>' WHEN v LIKE 'ERROR %' THEN v ELSE coalesce(v::jsonb ->> f, '<null>') END
      FROM (SELECT tap._get273(k) AS v) x $m$;
CREATE FUNCTION tap._st273(k text) RETURNS text LANGUAGE sql STABLE AS $m$ SELECT tap._f273(k, 'status') $m$;
-- the SQLSTATE of a kept refusal ('ERROR <code>'), or the status of a kept result
CREATE FUNCTION tap._c273(k text) RETURNS text LANGUAGE sql STABLE AS
$m$ SELECT CASE WHEN v LIKE 'ERROR %' THEN split_part(v, '|', 1) ELSE tap._st273(k) END FROM (SELECT tap._get273(k) AS v) x $m$;
-- the receipt digest of a text
CREATE FUNCTION tap._sha273(t text) RETURNS text LANGUAGE sql IMMUTABLE AS
$m$ SELECT encode(sha256(convert_to(t, 'UTF8')), 'hex') $m$;
-- a body with its comments stripped
CREATE FUNCTION tap._src273(sig text) RETURNS text LANGUAGE sql STABLE AS
$m$ SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') FROM pg_proc p WHERE p.oid = to_regprocedure(sig) $m$;
-- receipts: audit rows of one actor and action whose after carries the digest of the key
CREATE FUNCTION tap._rc273(p_actor uuid, p_action text, p_key text) RETURNS integer LANGUAGE sql STABLE AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a
     WHERE a.actor_identity = p_actor AND a.action = p_action AND a.after ->> 'command_key_sha256' = tap._sha273(p_key) $m$;
CREATE FUNCTION tap._sigs273() RETURNS TABLE (n text, sig text) LANGUAGE sql IMMUTABLE AS $m$ VALUES
  ('allocate_comp', 'venue.allocate_comp(uuid,uuid,integer,text,text)'),
  ('create_event', 'catalog.create_event(uuid,text,jsonb,text)'),
  ('create_event_session', 'catalog.create_event_session(uuid,jsonb,text)'),
  ('publish_event', 'catalog.publish_event(uuid,text,text)'),
  ('set_ticket_type_sale_window', 'venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)') $m$;
GRANT EXECUTE ON FUNCTION tap._put273(text, text), tap._get273(text), tap._try273(text), tap._run273(text, text),
  tap._f273(text, text), tap._st273(text), tap._c273(text), tap._sha273(text) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('a2730000-0000-4000-a000-0000000000a1', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'owner.a.273@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('a2730000-0000-4000-a000-0000000000a2', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'owner.b.273@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('a2730000-0000-4000-a000-0000000000a3', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'mgr.273@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('a2730000-0000-4000-a000-0000000000a4', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'fan.273@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('a2730000-0000-4000-a000-0000000000a5', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'mgr2.273@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('a2730000-0000-4000-a000-0000000000c1', 'Org A 273', 'Org A 273', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('a2730000-0000-4000-a000-0000000000c1', 'a2730000-0000-4000-a000-0000000000a1', 'org_owner'),
  ('a2730000-0000-4000-a000-0000000000c1', 'a2730000-0000-4000-a000-0000000000a2', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'Room VA 273', 'wynwood',  'approved'),
  ('a2730000-0000-4000-a000-0000000000d2', 'a2730000-0000-4000-a000-0000000000c1', 'Room VB 273', 'brickell', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000a3', 'venue_manager'),
  ('a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000a5', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('a2730000-0000-4000-a000-00000000e101', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'P 273',       'draft'),
  ('a2730000-0000-4000-a000-00000000e102', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'P twin 273',  'draft'),
  ('a2730000-0000-4000-a000-00000000e103', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'W 273',       'on_sale'),
  ('a2730000-0000-4000-a000-00000000e104', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'C 273',       'on_sale'),
  ('a2730000-0000-4000-a000-00000000e105', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'S 273',       'draft'),
  ('a2730000-0000-4000-a000-00000000e106', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'S other 273', 'draft'),
  ('a2730000-0000-4000-a000-00000000e107', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'X 273',       'draft'),
  ('a2730000-0000-4000-a000-00000000e108', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'Z 273',       'draft'),
  ('a2730000-0000-4000-a000-00000000e109', 'a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000c1', 'P7 273',      'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, status) VALUES
  ('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000e104', NULL, '2027-07-04 01:00:00+00', 'scheduled'),
  ('a2730000-0000-4000-a000-00000000f109', 'a2730000-0000-4000-a000-00000000e109', NULL, '2027-07-09 01:00:00+00', 'scheduled'),
  ('a2730000-0000-4000-a000-00000000f1c4', 'a2730000-0000-4000-a000-00000000e104', 'Late C 273', '2027-07-05 01:00:00+00', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('a2730000-0000-4000-a000-00000000aa03', 'a2730000-0000-4000-a000-00000000e103', 'admission', 'GA W 273', 2500, 'public'),
  ('a2730000-0000-4000-a000-00000000aa05', 'a2730000-0000-4000-a000-00000000e103', 'admission', 'VIP W 273', 5000, 'public'),
  ('a2730000-0000-4000-a000-00000000aa04', 'a2730000-0000-4000-a000-00000000e104', 'admission', 'GA C 273', 2500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity) VALUES
  ('a2730000-0000-4000-a000-00000000bb01', 'a2730000-0000-4000-a000-00000000aa04', 'a2730000-0000-4000-a000-00000000f104', 'comp', 100),
  ('a2730000-0000-4000-a000-00000000bb02', 'a2730000-0000-4000-a000-00000000aa04', 'a2730000-0000-4000-a000-00000000f104', 'comp', 100);

-- ── Section A — posture ─────────────────────────────────────────────────────
SELECT is((SELECT md5(prosrc) || '/' || md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid = to_regprocedure('catalog.create_event(uuid,text,jsonb,text)')),
  'd0cc74b90d40fa57f092ef59a8791d49/d4412bd702a938a18d4de28da68fbb70',
  'A1: catalog.create_event carries 204''s body (md5 prosrc / functiondef; 078''s was e48b7093 / 02314a38)');
SELECT is((SELECT md5(prosrc) || '/' || md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid = to_regprocedure('catalog.create_event_session(uuid,jsonb,text)')),
  '33b0d32e2a3b4269ad2fc9ae173066e1/8ce6b96c396f577adbf6be707b1433b3',
  'A2: catalog.create_event_session carries 204''s body (e76''s was ee243b12 / 560bd7d3)');
SELECT is((SELECT md5(prosrc) || '/' || md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid = to_regprocedure('catalog.publish_event(uuid,text,text)')),
  'fe9bc5f0f91611a064b1cdef5143efec/3243d8a053e81181d6c54fe1f05d5288',
  'A3: catalog.publish_event carries 204''s body = 202''s plus the receipt (202''s was 0f7d65e7 / f30eaca2)');
SELECT is((SELECT md5(prosrc) || '/' || md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid = to_regprocedure('venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)')),
  'a417a4acb7523b8a1d35c8fc3a025432/a9e9d11d0619b03d22bb1f920901d2a8',
  'A4: venue.set_ticket_type_sale_window carries 204''s body (162''s was 9fd9b5f5 / dc5cf9c9)');
SELECT is((SELECT md5(prosrc) || '/' || md5(pg_get_functiondef(oid)) FROM pg_proc WHERE oid = to_regprocedure('venue.allocate_comp(uuid,uuid,integer,text,text)')),
  'd35f9a24869a91b70755dcd75613f410/fd475aaf290c34405b0037f35547d358',
  'A5: venue.allocate_comp carries 204''s body (187''s was 26920648 / 73ad103d)');
SELECT is((SELECT string_agg(s.n || '=' || coalesce(p.proacl::text, '<null>'), ' ' ORDER BY s.n)
             FROM tap._sigs273() s LEFT JOIN pg_proc p ON p.oid = to_regprocedure(s.sig)),
  'allocate_comp={postgres=X/postgres,authenticated=X/postgres} create_event={postgres=X/postgres,authenticated=X/postgres} '
  'create_event_session={postgres=X/postgres,authenticated=X/postgres} publish_event={postgres=X/postgres,authenticated=X/postgres} '
  'set_ticket_type_sale_window={postgres=X/postgres,authenticated=X/postgres}',
  'A6: the five ACLs are unchanged — owner + authenticated EXECUTE; no anon, service_role or PUBLIC entry');
SELECT is((SELECT count(*)::int FROM tap._sigs273() s JOIN pg_proc p ON p.oid = to_regprocedure(s.sig) JOIN pg_language l ON l.oid = p.prolang
            WHERE p.prosecdef AND l.lanname = 'plpgsql' AND p.proconfig = ARRAY['search_path=""'] AND p.provolatile = 'v'
              AND p.prorettype = 'jsonb'::regtype AND p.proowner = 'postgres'::regrole
              AND (SELECT count(*) FROM pg_proc x WHERE x.pronamespace = p.pronamespace AND x.proname = p.proname) = 1), 5,
  'A7: each is still one postgres-owned SECURITY DEFINER VOLATILE plpgsql body, search_path = '''', returning jsonb');
SELECT is((SELECT string_agg(s.n || '=' || coalesce(md5(obj_description(p.oid, 'pg_proc')), '<none>'), ' ' ORDER BY s.n)
             FROM tap._sigs273() s LEFT JOIN pg_proc p ON p.oid = to_regprocedure(s.sig)),
  'allocate_comp=<none> create_event=<none> create_event_session=<none> publish_event=<none> set_ticket_type_sale_window=0bea27a400548d0ead5d9a5c1ce07d79',
  'A8: the COMMENTs are unchanged (four none; 162''s text on the sale-window setter, which stays true: the noop arm is unchanged)');
SELECT is((SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
             FROM pg_attribute a WHERE a.attrelid = to_regclass('kernel.admin_audit') AND a.attnum > 0 AND NOT a.attisdropped)
          || ' | ' || (SELECT string_agg(c.relname, ',' ORDER BY c.relname) FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
                        WHERE i.indrelid = to_regclass('kernel.admin_audit')),
  'id:uuid,actor_identity:uuid,action:text,subject_kind:text,subject_id:uuid,reason_code:text,before:jsonb,after:jsonb,occurred_at:timestamp with time zone,created_at:timestamp with time zone'
  ' | admin_audit_actor_idx,admin_audit_occurred_idx,admin_audit_pkey,admin_audit_subject_idx',
  'A9: kernel.admin_audit (the receipt store) keeps its columns and four indexes — 204 adds no schema');

-- ── Section B — static order (comments stripped) ────────────────────────────
SELECT is((SELECT string_agg(s.n || '=' || (SELECT count(*) FROM regexp_matches(b.src, 'pg_advisory_xact_lock\(hashtextextended\(''db6:', 'g'))
                               || '/' || (SELECT count(*) FROM regexp_matches(b.src, '->> ''command_key_sha256'' = v_kd', 'g')), ' ' ORDER BY s.n)
             FROM tap._sigs273() s CROSS JOIN LATERAL (SELECT tap._src273(s.sig) AS src) b),
  'allocate_comp=1/1 create_event=1/1 create_event_session=1/1 publish_event=1/1 set_ticket_type_sale_window=1/1',
  'B1: each body takes exactly one db6 advisory lock and runs exactly one key-digest receipt lookup');
SELECT is((SELECT string_agg(s.n || '=' || (strpos(b.src, 'insufficient_privilege: venue_manager') > 0
                                            AND strpos(b.src, 'pg_advisory_xact_lock(hashtextextended(''db6:') > strpos(b.src, 'insufficient_privilege: venue_manager'))::text, ' ' ORDER BY s.n)
             FROM tap._sigs273() s CROSS JOIN LATERAL (SELECT tap._src273(s.sig) AS src) b),
  'allocate_comp=true create_event=true create_event_session=true publish_event=true set_ticket_type_sale_window=true',
  'B2: in each body the receipt lock comes after the authority refusal — no receipt or conflict signal before authority');
SELECT is((SELECT string_agg(s.n || '=' || (strpos(b.src, 'pg_advisory_xact_lock(hashtextextended(''db6:') > 0
                                            AND strpos(b.src, 'pg_advisory_xact_lock(hashtextextended(''db6:') < strpos(b.src, 'from kernel.admin_audit a'))::text, ' ' ORDER BY s.n)
             FROM tap._sigs273() s CROSS JOIN LATERAL (SELECT tap._src273(s.sig) AS src) b),
  'allocate_comp=true create_event=true create_event_session=true publish_event=true set_ticket_type_sale_window=true',
  'B3: in each body the lock is taken before the receipt lookup reads kernel.admin_audit (serialization)');
SELECT ok(coalesce((SELECT strpos(b.src, 'pg_advisory_xact_lock(hashtextextended(''db6:') > 0
                       AND strpos(b.src, 'pg_advisory_xact_lock(hashtextextended(''db6:') < strpos(b.src, 'illegal_transition')
                      FROM (SELECT tap._src273('catalog.publish_event(uuid,text,text)') AS src) b), false),
  'B4: publish_event answers a replay before its transition check (a resend after the move is not illegal_transition)');
SELECT ok(coalesce((SELECT strpos(p.prosrc, E'    select l.value into v_fee_raw\n      from (select c.value\n              from catalog.platform_config c\n             where c.key = ''fee.buyer_service_bps''\n             order by c.version desc\n             limit 1) l;\n') > 0
                       AND strpos(p.prosrc, 'fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000') > 0
                       AND p.prosrc ~ 'and exists \(select 1 from catalog\.venue v\s+where v\.venue_id = v_venue and v\.org_id = v_org_id\)'
                      FROM pg_proc p WHERE p.oid = to_regprocedure('catalog.publish_event(uuid,text,text)')), false),
  'B5: publish_event keeps 202''s gate-4 read and range refusal and the E-76 conjunct (pgTAP 232 A10''s shape)');
SELECT ok(coalesce((SELECT (SELECT count(*) FROM regexp_matches(b.src, 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\(', 'g')) = 1
                       AND strpos(p.prosrc, '-- ── 187 BLOCK END') > 0
                       AND strpos(p.prosrc, 'precondition_failed: command key required') > strpos(p.prosrc, '-- ── 187 BLOCK END')
                       AND strpos(p.prosrc, 'precondition_failed: command key required') > strpos(p.prosrc, 'precondition_failed: bad_quantity')
                       AND strpos(p.prosrc, 'precondition_failed: command key required') < strpos(p.prosrc, 'pg_advisory_xact_lock(')
                      FROM pg_proc p, LATERAL (SELECT tap._src273('venue.allocate_comp(uuid,uuid,integer,text,text)') AS src) b
                     WHERE p.oid = to_regprocedure('venue.allocate_comp(uuid,uuid,integer,text,text)')), false),
  'B6: allocate_comp keeps one live venue.assert_session_operator and checks the key after the 187 block and bad_quantity, before the receipt');

-- ── Z1 — no auth.uid() (claims never set in this session: the NULL arm, before any tap.login) ───────────────
SELECT tap._run273('z1a', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('z1b', $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-01T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap._run273('z1c', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p1')$$);
SELECT tap._run273('z1d', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap._run273('z1e', $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', 'ck273-c1')$$);
SELECT is(coalesce(current_setting('request.jwt.claims', true), '<unset>') || ' | ' || tap._c273('z1a') || ' / ' || tap._c273('z1b') || ' / '
          || tap._c273('z1c') || ' / ' || tap._c273('z1d') || ' / ' || tap._c273('z1e'),
  '<unset> | ERROR 42501 / ERROR 42501 / ERROR 42501 / ERROR 42501 / ERROR 42501',
  'Z1: with no claims at all (NULL, not '''') each of the five refuses 42501');

-- ── Section K — catalog.create_event (UA) ───────────────────────────────────
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('k1',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('k3',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('k11', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', '  Night K 273  ', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('k5',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273 renamed', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('k6',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-02T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('k7',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d2', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap.logout();
SELECT is(tap._st273('k1'), 'ok', 'K1: first create_event is ok (unchanged first call)');
SELECT is((SELECT (a.after ->> 'command_key_sha256' = tap._sha273('ck273-k1'))::text || '|' || ((a.after ->> 'request_sha256') ~ '^[0-9a-f]{64}$')::text
                  || '|' || (a.after - 'command_key_sha256' - 'request_sha256')::text
             FROM kernel.admin_audit a WHERE a.action = 'event.create' AND a.subject_id::text = tap._f273('k1', 'event_id')),
  'true|true|{"status": "draft", "venue_id": "a2730000-0000-4000-a000-0000000000d1"}',
  'K2: its event.create audit row carries sha256(key) and a request digest beside the unchanged after keys (no raw key)');
SELECT is(tap._st273('k3') || '|' || (tap._f273('k3', 'event_id') = tap._f273('k1', 'event_id'))::text || '|' || (tap._f273('k3', 'session_id') = tap._f273('k1', 'session_id'))::text,
  'noop_replay|true|true', 'K3: the same key and request replays the original event_id and implicit session_id');
SELECT is(tap._st273('k11') || '|' || (tap._f273('k11', 'event_id') = tap._f273('k1', 'event_id'))::text,
  'noop_replay|true', 'K11: a title differing only by surrounding spaces is the same request (the stored title is trimmed)');
SELECT is(tap._get273('k5'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'K5: the same key with another title is refused with the house conflict literal');
SELECT is(tap._get273('k6'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'K6: …with another first session');
SELECT is(tap._get273('k7'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'K7: …at another room of the same org');
SELECT is((SELECT count(*) FROM catalog.event e WHERE e.venue_id IN ('a2730000-0000-4000-a000-0000000000d1', 'a2730000-0000-4000-a000-0000000000d2') AND e.title LIKE 'Night K 273%')::text
          || '|' || (SELECT count(*) FROM catalog.event_session s WHERE s.event_id::text = tap._f273('k1', 'event_id'))::text
          || '|' || tap._rc273('a2730000-0000-4000-a000-0000000000a1', 'event.create', 'ck273-k1')
          || '|' || tap._rc273('a2730000-0000-4000-a000-0000000000a1', 'session.create', 'ck273-k1:implicit-session'),
  '1|1|1|1', 'K4: replays and conflicts wrote nothing — one event, one session, one event.create and one implicit session.create receipt');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('k8',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k8')$$);
SELECT tap.logout();
SELECT is(tap._st273('k8') || '|' || (tap._f273('k8', 'event_id') <> tap._f273('k1', 'event_id'))::text, 'ok|true',
  'K8: a NEW key with the same request is a new command — a second event (unchanged)');
UPDATE catalog.event SET title = 'Night K 273 retitled', status = 'announced' WHERE event_id::text = tap._f273('k1', 'event_id');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('k9',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('k10a', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K10 273', '{}', 'ck273-k10')$$);
SELECT tap._run273('k10b', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K10 273', '{"starts_at": "2027-03-10T01:00:00+00:00"}', 'ck273-k10')$$);
SELECT tap.logout();
SELECT is(tap._st273('k9') || '|' || (tap._f273('k9', 'event_id') = tap._f273('k1', 'event_id'))::text || '|' || (tap._f273('k9', 'session_id') = tap._f273('k1', 'session_id'))::text,
  'noop_replay|true|true', 'K9: after the event was retitled and announced, the resend still replays the original ids');
SELECT is(tap._get273('k10a') || ' / ' || tap._st273('k10b'), 'ERROR P0001|invalid_input: starts_at required / ok',
  'K10: a refused first call records nothing, so the same key with a valid request is a first call');

-- ── Section S — catalog.create_event_session (UA on S 273) ──────────────────
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('s1',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-01T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap._run273('s2',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-01T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap._run273('s3a', $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"session_label": "Late 273", "starts_at": "2027-04-02T01:00:00+00:00"}', 'ck273-s3')$$);
SELECT tap._run273('s3',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"session_label": "Late 273", "starts_at": "2027-04-02T01:00:00+00:00"}', 'ck273-s3')$$);
SELECT tap._run273('s4',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"session_label": "Late 273", "starts_at": "2027-04-02T01:00:00+00:00"}', 'ck273-s4')$$);
SELECT tap._run273('s5',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-05T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap._run273('s6',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e106', '{"starts_at": "2027-04-01T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap._run273('s8',  format($$SELECT catalog.create_event_session(%L, '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1:implicit-session')$$, tap._f273('k1', 'event_id')));
SELECT tap._run273('s9a', $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-09T03:00:00+00:00", "ends_at": "2027-04-09T01:00:00+00:00"}', 'ck273-s9')$$);
SELECT tap._run273('s9b', $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-09T01:00:00+00:00", "ends_at": "2027-04-09T03:00:00+00:00"}', 'ck273-s9')$$);
SELECT tap.logout();
SELECT is(tap._st273('s1'), 'ok', 'S1: first create_event_session is ok (unchanged first call)');
SELECT is(tap._st273('s2') || '|' || (tap._f273('s2', 'session_id') = tap._f273('s1', 'session_id'))::text, 'noop_replay|true',
  'S2: the same key and request replays the original session_id');
SELECT is(tap._st273('s3a'), 'ok', 'S3a: a labelled first call is ok');
SELECT is(tap._st273('s3') || '|' || (tap._f273('s3', 'session_id') = tap._f273('s3a', 'session_id'))::text, 'noop_replay|true',
  'S3: a same-key labelled resend replays (before 204: a raw 23505 on event_session_label_uq)');
SELECT is(tap._c273('s4'), 'ERROR 23505', 'S4: a NEW key with the same label still hits the unique label (unchanged)');
SELECT is(tap._get273('s5'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'S5: the same key with another session payload is refused (conflict)');
SELECT is(tap._get273('s6'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'S6: the same key on another event is refused (conflict)');
SELECT is(tap._st273('s8') || '|' || (tap._f273('s8', 'session_id') = tap._f273('k1', 'session_id'))::text, 'noop_replay|true',
  'S8: a direct call with create_event''s derived key, same event and payload, replays the implicit session');
SELECT is(tap._get273('s9a') || ' / ' || tap._st273('s9b'), 'ERROR P0001|precondition_failed: ends_at must be after starts_at / ok',
  'S9: a refused first call records nothing, so the same key with a valid payload is a first call');
SELECT is((SELECT count(*) FROM catalog.event_session s WHERE s.event_id = 'a2730000-0000-4000-a000-00000000e105')::text || '|'
          || (SELECT count(*) FROM kernel.admin_audit a WHERE a.action = 'session.create' AND a.after ->> 'event_id' = 'a2730000-0000-4000-a000-00000000e105')::text || '|'
          || (SELECT count(*) FROM catalog.event_session s WHERE s.event_id = 'a2730000-0000-4000-a000-00000000e106')::text,
  '3|3|0', 'S10: replays and conflicts wrote nothing — S 273 has the three first-call sessions (S1, S3a, S9) and three receipts; the other event none');
UPDATE catalog.event SET status = 'cancelled' WHERE event_id = 'a2730000-0000-4000-a000-00000000e105';
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('s7',  $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e105', '{"starts_at": "2027-04-01T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap.logout();
SELECT is(tap._get273('s7'), 'ERROR P0001|precondition_failed: event_terminal',
  'S7: a resend after the event was cancelled answers the existing pre-authority gate (event_terminal), not a replay');

-- ── Section P — catalog.publish_event (UA) ──────────────────────────────────
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('p1',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p1')$$);
SELECT tap._run273('p2',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p1')$$);
SELECT tap._run273('p3',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'on_sale', 'ck273-p1')$$);
SELECT tap._run273('p4',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p4')$$);
SELECT tap._run273('p6',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e102', 'announced', 'ck273-p1')$$);
SELECT tap._run273('p7a', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e109', 'announced', 'ck273-p7a')$$);
SELECT tap._run273('p7b', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e109', 'on_sale', 'ck273-p7')$$);
SELECT tap.logout();
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('a2730000-0000-4000-a000-00000000aa09', 'a2730000-0000-4000-a000-00000000e109', 'admission', 'GA P7 273', 2500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity) VALUES
  ('a2730000-0000-4000-a000-00000000bb09', 'a2730000-0000-4000-a000-00000000aa09', 'a2730000-0000-4000-a000-00000000f109', 'public_sale', 10);
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('p7c', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e109', 'on_sale', 'ck273-p7')$$);
SELECT tap.logout();
UPDATE catalog.event SET status = 'on_sale' WHERE event_id = 'a2730000-0000-4000-a000-00000000e101';
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('p5',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p1')$$);
SELECT tap.logout();
SELECT is(tap._st273('p1') || '|' || tap._f273('p1', 'event_status'), 'ok|announced', 'P1: first publish draft -> announced is ok (unchanged)');
SELECT is((SELECT (a.after ->> 'command_key_sha256' = tap._sha273('ck273-p1'))::text || '|' || ((a.after ->> 'request_sha256') ~ '^[0-9a-f]{64}$')::text
                  || '|' || a.reason_code || '|' || (a.after - 'command_key_sha256' - 'request_sha256')::text
             FROM kernel.admin_audit a WHERE a.action = 'event.status' AND a.subject_id = 'a2730000-0000-4000-a000-00000000e101'),
  'true|true|publish|{"status": "announced"}', 'P1b: its event.status audit row keeps reason publish and carries the two digests');
SELECT is(tap._st273('p2') || '|' || tap._f273('p2', 'event_status') || '|rows='
          || (SELECT count(*) FROM kernel.admin_audit a WHERE a.action = 'event.status' AND a.subject_id = 'a2730000-0000-4000-a000-00000000e101'),
  'noop_replay|announced|rows=1', 'P2: the same key replays {noop_replay, announced}; replays and refusals left exactly one event.status row');
SELECT is(tap._get273('p3'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'P3: the same key with another target is refused (conflict), not run through the gates');
SELECT is(tap._get273('p4'), 'ERROR P0001|precondition_failed: illegal_transition (announced -> announced)',
  'P4: a NEW key re-announcing is still illegal_transition (unchanged)');
SELECT is(tap._st273('p5') || '|' || tap._f273('p5', 'event_status') || '|' || (SELECT status FROM catalog.event WHERE event_id = 'a2730000-0000-4000-a000-00000000e101'),
  'noop_replay|announced|on_sale', 'P5: after the event moved on, the resend replays the ORIGINAL target and changes nothing');
SELECT is(tap._get273('p6') || ' / ' || (SELECT status FROM catalog.event WHERE event_id = 'a2730000-0000-4000-a000-00000000e102'),
  'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters / draft',
  'P6: the same key on the twin draft is refused (conflict) and the twin stays draft');
SELECT is(tap._st273('p7a') || ' / ' || tap._get273('p7b') || ' / ' || tap._get273('p7c'),
  'ok / ERROR P0001|precondition_failed: empty_inventory / ERROR P0001|precondition_failed: connect_not_ready',
  'P7: an on_sale refused empty_inventory records nothing; after inventory is added the same key runs on to the next gate');
UPDATE catalog.event SET status = 'cancelled' WHERE event_id = 'a2730000-0000-4000-a000-00000000e101';
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('p8',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p1')$$);
SELECT tap.logout();
SELECT is(tap._st273('p8') || '|' || tap._f273('p8', 'event_status') || '|' || (SELECT status FROM catalog.event WHERE event_id = 'a2730000-0000-4000-a000-00000000e101'),
  'noop_replay|announced|cancelled', 'P8: after cancellation the resend still replays the original target (before 204: illegal_transition)');

-- ── Section W — venue.set_ticket_type_sale_window (UA, UB on GA W 273) ──────
SET LOCAL timezone = 'UTC';
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w1',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap.logout();
SELECT is(tap._st273('w1'), 'ok', 'W1: UA''s first window change is ok (unchanged first call)');
SELECT is((SELECT (a.after ->> 'command_key_sha256' = tap._sha273('ck273-w1'))::text || '|' || ((a.after ->> 'request_sha256') ~ '^[0-9a-f]{64}$')::text || '|' || a.reason_code
             FROM kernel.admin_audit a WHERE a.action = 'ticket_type.sale_window_change' AND a.subject_id = 'a2730000-0000-4000-a000-00000000aa03'
              AND a.actor_identity = 'a2730000-0000-4000-a000-0000000000a1'),
  'true|true|presale', 'W1b: its audit row carries the two digests and the reason');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w1c', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap.logout();
SELECT is(tap._st273('w1c'), 'noop_replay', 'W1c: an immediate resend is answered by the receipt, before the value-equal noop arm');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a2');
SELECT tap._run273('w2',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-12-01 00:00+00', '2036-12-02 00:00+00', 'moved', 'ck273-w2')$$);
SELECT tap.logout();
SELECT is(tap._st273('w2'), 'ok', 'W2: UB moves the window (ok)');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w6',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-12-01 00:00+00', '2036-12-02 00:00+00', 'again', 'ck273-w6')$$);
SELECT tap._run273('w7a', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-12-01 00:00+00', '2036-12-02 00:00+00', 'hold', 'ck273-w7')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a2');
SELECT tap._run273('w7b', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2037-01-01 00:00+00', '2037-01-02 00:00+00', 'shift', 'ck273-w7b')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w7c', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-12-01 00:00+00', '2036-12-02 00:00+00', 'hold', 'ck273-w7')$$);
SELECT tap.logout();
SELECT is(tap._st273('w6'), 'noop', 'W6: a NEW key with the current values is the value-equal noop (unchanged, pgTAP 229 W18)');
SELECT is(tap._st273('w7a') || ' / ' || tap._st273('w7b') || ' / ' || tap._st273('w7c') || ' / '
          || (SELECT (sale_starts_at = '2036-12-01 00:00+00' AND sale_ends_at = '2036-12-02 00:00+00')::text FROM venue.ticket_type WHERE ticket_type_id = 'a2730000-0000-4000-a000-00000000aa03'),
  'noop / ok / ok / true', 'W7: residual R6 pinned — a value-equal noop leaves no receipt, so after UB''s change UA''s same-key resend re-applies');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w3',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap.logout();
SELECT is(tap._st273('w3') || '|' || (SELECT (sale_starts_at = '2036-12-01 00:00+00' AND sale_ends_at = '2036-12-02 00:00+00')::text FROM venue.ticket_type WHERE ticket_type_id = 'a2730000-0000-4000-a000-00000000aa03')
          || '|rows=' || (SELECT count(*) FROM kernel.admin_audit a WHERE a.action = 'ticket_type.sale_window_change' AND a.subject_id = 'a2730000-0000-4000-a000-00000000aa03'),
  'noop_replay|true|rows=4', 'W3: UA''s original key replays and does NOT re-apply its old window over the current one (W1, W2, W7b, W7c rows only)');
SELECT is(tap._st273('w3') || '|' || tap._f273('w3', 'sale_starts_at') || '|' || tap._f273('w3', 'sale_ends_at'),
  'noop_replay|2036-11-01T00:00:00+00:00|2036-11-02T00:00:00+00:00',
  'W3b: that replay returns the ORIGINAL request''s window (W1''s), not the current window UB set (session TimeZone UTC)');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w4',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-03 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap._run273('w5',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale-2', 'ck273-w1')$$);
SELECT tap._run273('w9',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa05', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap._run273('w10', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-10-25 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap.logout();
SELECT is(tap._get273('w4'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'W4: the same key with another window is refused (conflict)');
SELECT is(tap._get273('w5'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'W5: the same key with another reason is refused (conflict)');
SELECT is(tap._get273('w9') || ' / ' || (SELECT (sale_starts_at IS NULL AND sale_ends_at IS NULL)::text FROM venue.ticket_type WHERE ticket_type_id = 'a2730000-0000-4000-a000-00000000aa05'),
  'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters / true',
  'W9: the same key and window on ANOTHER ticket type of the event is refused (conflict) and that tier''s window stays unset');
SELECT is(tap._get273('w10') || ' / ' || (SELECT (sale_starts_at = '2036-12-01 00:00+00' AND sale_ends_at = '2036-12-02 00:00+00')::text FROM venue.ticket_type WHERE ticket_type_id = 'a2730000-0000-4000-a000-00000000aa03'),
  'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters / true',
  'W10: the same key with only sale_starts_at changed is refused (conflict) and the current window is untouched');
SET LOCAL timezone = 'America/New_York';
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('w8',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-10-31 20:00:00-04', '2036-11-01 20:00:00-04', 'presale', 'ck273-w1')$$);
SELECT tap.logout();
SET LOCAL timezone = 'UTC';
SELECT is(tap._st273('w8'), 'noop_replay', 'W8: the same instants in another session TimeZone and offset are the same request (the digest uses epochs)');

-- ── Section C — venue.allocate_comp (UM, the bound manager) ─────────────────
SELECT tap.login('a2730000-0000-4000-a000-0000000000a3');
SELECT tap._run273('c1a', $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', NULL)$$);
SELECT tap._run273('c1b', $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', '  ')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a4');
SELECT tap._run273('c2',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', '')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a3');
SELECT tap._run273('c3',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', 'ck273-c1')$$);
SELECT tap._run273('c4',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', 'ck273-c1')$$);
SELECT tap._run273('c5',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 3, 'press', 'ck273-c1')$$);
SELECT tap._run273('c6',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb02', 2, 'press', 'ck273-c1')$$);
SELECT tap._run273('c8',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 1, NULL, 'ck273-c8')$$);
SELECT tap._run273('c9',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'staff', 'ck273-c1')$$);
SELECT tap._run273('c10', $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f1c4', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', 'ck273-c1')$$);
SELECT tap.logout();
SELECT is(tap._get273('c1a') || ' / ' || tap._get273('c1b'),
  'ERROR P0001|precondition_failed: command key required / ERROR P0001|precondition_failed: command key required',
  'C1: the bound manager''s NULL or blank key is refused (new: the key anchors the receipt)');
SELECT is(tap._c273('c2'), 'ERROR 42501', 'C2: an unauthorized caller with a blank key gets 42501 — the key check comes after authority');
SELECT is(tap._st273('c3') || '|' || (SELECT count(*) || '|' || string_agg(a.reason_code || '|' || (a.actor_identity = 'a2730000-0000-4000-a000-0000000000a3')::text
                                            || '|' || (a.after ->> 'command_key_sha256' = tap._sha273('ck273-c1'))::text
                                            || '|' || ((a.after - 'command_key_sha256' - 'request_sha256') = jsonb_build_object('session_id', 'a2730000-0000-4000-a000-00000000f104'::uuid,
                                                         'batch_id', 'a2730000-0000-4000-a000-00000000bb01'::uuid, 'quantity', 2))::text, ';')
                                         FROM kernel.admin_audit a WHERE a.action = 'comp.allocate' AND a.subject_id::text = tap._f273('c3', 'comp_allocation_id')),
  'ok|1|press|true|true|true', 'C3: the first allocation is ok and writes one comp.allocate audit row (reason, actor, digests)');
SELECT is(tap._st273('c4') || '|' || (tap._f273('c4', 'comp_allocation_id') = tap._f273('c3', 'comp_allocation_id'))::text || '|rows='
          || (SELECT count(*) FROM venue.comp_allocation c WHERE c.event_session_id = 'a2730000-0000-4000-a000-00000000f104' AND c.batch_id = 'a2730000-0000-4000-a000-00000000bb01' AND c.quantity = 2),
  'noop_replay|true|rows=1', 'C4: the resend replays the same allocation id; the refused C1 / C9 calls and the replay wrote no row');
SELECT is(tap._get273('c5'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'C5: the same key with another quantity is refused (conflict)');
SELECT is(tap._get273('c6'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'C6: the same key with another batch is refused (conflict)');
SELECT is(tap._get273('c9'), 'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters',
  'C9: the same key with only another reason_code is refused (conflict)');
SELECT is(tap._get273('c10') || ' / ' || (SELECT count(*) FROM venue.comp_allocation c WHERE c.event_session_id = 'a2730000-0000-4000-a000-00000000f1c4')::text,
  'ERROR P0001|precondition_failed: idempotency_conflict — command key reused with different parameters / 0',
  'C10: the same key with only another session_id is refused (conflict) and writes no allocation on that session');
SELECT is(tap._st273('c8') || '|' || (SELECT a.reason_code FROM kernel.admin_audit a WHERE a.action = 'comp.allocate' AND a.subject_id::text = tap._f273('c8', 'comp_allocation_id')),
  'ok|unspecified', 'C8: a NULL reason is recorded as unspecified (the audit reason_code is NOT NULL)');

-- ── Section X — scope: actor and verb ───────────────────────────────────────
SELECT tap.login('a2730000-0000-4000-a000-0000000000a2');
SELECT tap._run273('x1',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('x2',  $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('x3a', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e107', 'announced', 'ck273-x3')$$);
SELECT tap._run273('x3b', $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e107', '{"starts_at": "2027-05-01T01:00:00+00:00"}', 'ck273-x3')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a2');
SELECT tap._run273('x4',  $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e107', 'announced', 'ck273-x3')$$);
SELECT tap._run273('x6',  $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap.logout();
SELECT tap.login('a2730000-0000-4000-a000-0000000000a5');
SELECT tap._run273('x7',  $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', 'ck273-c1')$$);
SELECT tap.logout();
SELECT is(tap._st273('x1') || '|' || (tap._f273('x1', 'event_id') <> tap._f273('k1', 'event_id'))::text, 'ok|true',
  'X1: another actor with UA''s key and request makes an independent first call (a new event)');
SELECT is(tap._st273('x2') || '|' || (tap._f273('x2', 'event_id') = tap._f273('k1', 'event_id'))::text || '|' || (tap._f273('x2', 'session_id') = tap._f273('k1', 'session_id'))::text,
  'noop_replay|true|true', 'X2: UA''s resend still replays UA''s own ids');
SELECT is(tap._st273('x3a') || ' / ' || tap._st273('x3b'), 'ok / ok', 'X3: one key on publish_event then create_event_session — two verbs, two independent first calls');
SELECT is(tap._get273('x4'), 'ERROR P0001|precondition_failed: illegal_transition (announced -> announced)',
  'X4: another actor with UA''s publish key gets no replay — illegal_transition, as before 204');
SELECT is('UA=' || tap._rc273('a2730000-0000-4000-a000-0000000000a1', 'event.create', 'ck273-k1') || ' UB=' || tap._rc273('a2730000-0000-4000-a000-0000000000a2', 'event.create', 'ck273-k1'),
  'UA=1 UB=1', 'X5: one event.create receipt per actor for the shared key digest');
SELECT is(tap._st273('x6') || '|' || (SELECT (sale_starts_at = '2036-11-01 00:00+00' AND sale_ends_at = '2036-11-02 00:00+00')::text FROM venue.ticket_type WHERE ticket_type_id = 'a2730000-0000-4000-a000-00000000aa03')
          || '|UA=' || tap._rc273('a2730000-0000-4000-a000-0000000000a1', 'ticket_type.sale_window_change', 'ck273-w1')
          || ' UB=' || tap._rc273('a2730000-0000-4000-a000-0000000000a2', 'ticket_type.sale_window_change', 'ck273-w1'),
  'ok|true|UA=1 UB=1', 'X6: UB sending UA''s sale-window key and request is an independent first call — applied, with its own receipt');
SELECT is(tap._st273('x7') || '|' || (tap._f273('x7', 'comp_allocation_id') <> tap._f273('c3', 'comp_allocation_id'))::text || '|rows='
          || (SELECT count(*) FROM venue.comp_allocation c WHERE c.event_session_id = 'a2730000-0000-4000-a000-00000000f104' AND c.batch_id = 'a2730000-0000-4000-a000-00000000bb01' AND c.quantity = 2)
          || '|UM=' || tap._rc273('a2730000-0000-4000-a000-0000000000a3', 'comp.allocate', 'ck273-c1')
          || ' UM2=' || tap._rc273('a2730000-0000-4000-a000-0000000000a5', 'comp.allocate', 'ck273-c1'),
  'ok|true|rows=2|UM=1 UM2=1', 'X7: a second bound manager sending UM''s comp key and request gets a NEW allocation and its own receipt');

-- ── Z2-Z4 — refusals answer before any receipt ──────────────────────────────
SELECT tap.login('a2730000-0000-4000-a000-0000000000a4');
SELECT tap._run273('z2a', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'Night K 273', '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1')$$);
SELECT tap._run273('z2b', format($$SELECT catalog.create_event_session(%L, '{"starts_at": "2027-03-01T01:00:00+00:00"}', 'ck273-k1:implicit-session')$$, tap._f273('k1', 'event_id')));
SELECT tap._run273('z2c', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e101', 'announced', 'ck273-p1')$$);
SELECT tap._run273('z2d', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale', 'ck273-w1')$$);
SELECT tap._run273('z2e', $$SELECT venue.allocate_comp('a2730000-0000-4000-a000-00000000f104', 'a2730000-0000-4000-a000-00000000bb01', 2, 'press', 'ck273-c1')$$);
SELECT tap.logout();
SELECT is(tap._c273('z2a') || ' / ' || tap._c273('z2b') || ' / ' || tap._c273('z2c') || ' / ' || tap._c273('z2d') || ' / ' || tap._c273('z2e'),
  'ERROR 42501 / ERROR 42501 / ERROR 42501 / ERROR 42501 / ERROR 42501',
  'Z2: a fan replaying another actor''s keys and requests is refused 42501 by all five');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a3');
SELECT tap._run273('z3a', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'UM night 273', '{"starts_at": "2027-06-01T01:00:00+00:00"}', 'ck273-z3e')$$);
SELECT tap._run273('z3b', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e108', 'announced', 'ck273-z3p')$$);
SELECT tap._run273('z3c', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2037-02-01 00:00+00', '2037-02-02 00:00+00', 'um', 'ck273-z3w')$$);
SELECT tap.logout();
DELETE FROM venue.staff_role WHERE identity_id = 'a2730000-0000-4000-a000-0000000000a3';
SELECT tap.login('a2730000-0000-4000-a000-0000000000a3');
SELECT tap._run273('z3d', $$SELECT catalog.create_event('a2730000-0000-4000-a000-0000000000d1', 'UM night 273', '{"starts_at": "2027-06-01T01:00:00+00:00"}', 'ck273-z3e')$$);
SELECT tap._run273('z3e', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e108', 'announced', 'ck273-z3p')$$);
SELECT tap._run273('z3f', $$SELECT venue.set_ticket_type_sale_window('a2730000-0000-4000-a000-00000000aa03', '2037-02-01 00:00+00', '2037-02-02 00:00+00', 'um', 'ck273-z3w')$$);
SELECT tap.logout();
SELECT is(tap._st273('z3a') || ' / ' || tap._st273('z3b') || ' / ' || tap._st273('z3c'), 'ok / ok / ok',
  'Z3a: the bound manager''s first create_event, publish_event and window change are ok');
SELECT is(tap._c273('z3d') || ' / ' || tap._c273('z3e') || ' / ' || tap._c273('z3f'), 'ERROR 42501 / ERROR 42501 / ERROR 42501',
  'Z3: after the manager''s role is deleted, the same-key resends are refused 42501 — a receipt never outlives authority');
SELECT tap.login('a2730000-0000-4000-a000-0000000000a1');
SELECT tap._run273('z4a', $$SELECT catalog.publish_event('a2730000-0000-4000-a000-00000000e1ff', 'announced', 'ck273-p1')$$);
SELECT tap._run273('z4b', $$SELECT catalog.create_event_session('a2730000-0000-4000-a000-00000000e1ff', '{"starts_at": "2027-04-01T01:00:00+00:00"}', 'ck273-s1')$$);
SELECT tap.logout();
SELECT is(tap._c273('z4a') || ' / ' || tap._c273('z4b'), 'ERROR P0002 / ERROR P0002',
  'Z4: an unknown event answers not_found (P0002) before any receipt, even for a key that has one (pgTAP 232 Section U order)');

SELECT * FROM finish();
ROLLBACK;
