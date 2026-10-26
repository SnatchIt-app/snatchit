-- ============================================================================
-- 255_venue_hold_sale_window.sql — migration 20261026230000 (registry 185 / pgTAP 255, A).
--
-- A's ruling 2026-10-26 (planning CONTRACTS.md §2 C2 "Sale windows"): a tier's sale
-- window — D's 162 predicate venue.ticket_type_on_sale(p_ticket_type_id, p_at) — is
-- enforced when a hold is CREATED, in venue.reserve_primary_inventory (buyer) and
-- venue.create_inventory_hold (staff), after the idempotency replay and before any
-- inventory/hold write; refusal 'precondition_failed: tier_not_on_sale' (162 defines no
-- code). Checkout (venue.create_primary_checkout) and comps (allocate_comp/issue_comp)
-- are not changed.
--
-- Fixture style: 229 (synthetic rows as postgres, fixed ids tagged 25500000-…, read and
-- driven as each caller through tap.login; everything dies with the ROLLBACK). Windows
-- are set through 162's setter as the org_owner, every bound relative to now(): now()
-- is frozen for the whole transaction, so "at the exact start/end instant" IS now() —
-- the bound is set explicitly to now(), never recomputed (the branch is asserted, not
-- the value).
--
--   F   fixtures in place (one assertion: the 14 tiers carry the intended windows)
--   A   shape: SECURITY DEFINER + search_path='' + EXECUTE ACL (authenticated yes;
--       anon/PUBLIC no) on both functions; exactly one 185 block pair per body, calling
--       162's predicate at now(); the 185 md5 of each body; strip-equivalence (minus the
--       marked blocks = the predecessor md5); checkout and comps carry no window gate.
--   W   reserve_primary_inventory as an authenticated BUYER: before -> refused; exact
--       start -> allowed; inside -> allowed; exact end -> refused; after -> refused;
--       NULL/NULL, NULL start, NULL end exactly as 162 (open on that side; ends still
--       exclusive); hidden -> refused, door_only -> allowed (162 W26/W27); the dark flag
--       and the event gate still answer first (feature_disabled / not_on_sale).
--   H   create_inventory_hold as the org_owner (staff): the same set; the event-status
--       arm of 162's predicate (announced event) -> refused (new for this function: 081
--       had no event gate here); a fan is refused 42501 before the window is consulted.
--   N   no inventory_hold / held / inventory_movement written by any refusal.
--   R   idempotency replay after the window closed: buyer -> idempotency_replay with
--       the SAME hold_id and expiry; staff -> 081's own replay answer
--       ('precondition_failed: idempotency_replay', raised at the INSERT — 081 returns no
--       hold_id there), the original row the only one for its key; fresh keys refused;
--       no new hold, no counter move.
--
-- NOT in-suite (runner, evidence dir a185/): the file-level proofs — pre-flight refusal
-- of a foreign body with nothing changed, idempotent re-apply, rollback restoring both
-- predecessor md5s with every other function's md5 unchanged, rollback refusal and
-- re-run. CI's `supabase test db` mounts supabase/tests only, so a suite cannot read
-- the migration/rollback files (the 250/253 precedent).
--
-- Expected on the stacked tree WITHOUT 185 (RED, predicted before the first run): the
-- file runs to the end (throws_ok and tap._try255 never abort). Not ok (28): A6 A7 (no
-- block pair), A8 A9 (no predicate call), A10 A11 (md5 is the predecessor's); W1 W4 W5
-- W9 W10 W11 (reserve succeeds); H1 H4 H5 H9 H10 H11 H13 (create_inventory_hold
-- succeeds); N1 N2 N3 (holds/counter/ledger written on the refused batches) and N5 (25
-- holds, not 12); R5 R10 (fresh keys succeed) and R11 R12 R13 (b13 carries 4 holds).
-- Vacuous passes on RED: A12 A13 (strip of a block-less body is the body itself) — the
-- md5 pins A10/A11 are what distinguish. R6-R9, W13 W14 and H15 pass on RED too (081
-- already replays; the gates they order already exist); their negative controls are the
-- runner mutants. Predicted RED: 28 not ok of 63 — the actual RED run on both clones
-- (chain + production-equal, 2026-10-26) matched it exactly.
-- Negative controls (runner, a185/mutants/): M1 no window block -> the 28 RED pins;
-- M2 create_inventory_hold without the replay-key skip -> A11 R6; M3 reserve's block
-- before the replay branch -> A10 W13 W14 R7 R8 R9; M4 create_inventory_hold's block
-- before the staff authority check -> A11 H15.
-- ============================================================================
BEGIN;
SELECT plan(63);

CREATE TABLE tap.memo_255 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store255(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_255 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch255(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_255 WHERE k = $1 $m$;
CREATE FUNCTION tap._t255(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS
$m$ SELECT ('25500000-0000-4000-8000-0000000100' || lpad(n::text, 2, '0'))::uuid $m$;   -- tier n
CREATE FUNCTION tap._b255(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS
$m$ SELECT ('25500000-0000-4000-8000-0000000200' || lpad(n::text, 2, '0'))::uuid $m$;   -- its batch
-- the caller's own call, never aborting the file: the RPC result, or {error, message}
-- (a refused call's writes roll back to the block's savepoint — as throws_ok's do).
CREATE FUNCTION tap._try255(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN r;
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
-- definer reads of what a refusal must not write (E-29: no client role reads held)
CREATE FUNCTION tap._holds255(b uuid[]) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT count(*)::integer FROM venue.inventory_hold WHERE batch_id = ANY (b) $m$;
CREATE FUNCTION tap._held255(b uuid[]) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT coalesce(sum(held), 0)::integer FROM venue.inventory_batch WHERE batch_id = ANY (b) $m$;
CREATE FUNCTION tap._moves255(b uuid[]) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT count(*)::integer FROM venue.inventory_movement WHERE batch_id = ANY (b) $m$;
-- strip rule (185 header): every line from a '-- ── 185 BLOCK <X> …' marker through its
-- '-- ── 185 BLOCK <X> END' marker (both included) goes; everything else is kept byte for byte.
CREATE FUNCTION tap._strip255(p_sig text) RETURNS text LANGUAGE sql STABLE AS $m$
  WITH l AS (
    SELECT t.line, t.n,
           CASE WHEN t.line ~ '^ *-- ── 185 BLOCK [A-Z0-9]+ END *$' THEN -1
                WHEN t.line ~ '^ *-- ── 185 BLOCK [A-Z0-9]+( |$)'   THEN 1 ELSE 0 END AS d,
           t.line ~ '^ *-- ── 185 BLOCK ' AS marker
      FROM regexp_split_to_table(pg_get_functiondef(p_sig::regprocedure), E'\n') WITH ORDINALITY AS t(line, n))
  SELECT md5(string_agg(x.line, E'\n' ORDER BY x.n))
    FROM (SELECT l.line, l.n, l.marker, sum(l.d) OVER (ORDER BY l.n) AS depth FROM l) x
   WHERE x.depth = 0 AND NOT x.marker $m$;
CREATE FUNCTION tap._markers255(p_sig text, p_end boolean) RETURNS integer LANGUAGE sql STABLE AS $m$
  SELECT count(*)::integer
    FROM regexp_split_to_table(pg_get_functiondef(p_sig::regprocedure), E'\n') AS t(line)
   WHERE CASE WHEN p_end THEN t.line ~ '^ *-- ── 185 BLOCK [A-Z0-9]+ END *$'
              ELSE t.line ~ '^ *-- ── 185 BLOCK [A-Z0-9]+ ' AND t.line !~ ' END *$' END $m$;
GRANT EXECUTE ON FUNCTION tap._store255(text, text), tap._fetch255(text), tap._t255(int), tap._b255(int),
  tap._try255(text), tap._holds255(uuid[]), tap._held255(uuid[]), tap._moves255(uuid[]) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('25500000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.255@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('25500000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.255@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('25500000-0000-4000-8000-00000000000a', 'Org A 255', 'Org A 255', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('25500000-0000-4000-8000-00000000000a', '25500000-0000-4000-8000-000000000101', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('25500000-0000-4000-8000-0000000000a1', '25500000-0000-4000-8000-00000000000a', 'Room 255', 'wynwood', 'approved');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('25500000-0000-4000-8000-0000000000e1', '25500000-0000-4000-8000-0000000000a1', '25500000-0000-4000-8000-00000000000a', 'On sale 255',   'on_sale'),
  ('25500000-0000-4000-8000-0000000000e2', '25500000-0000-4000-8000-0000000000a1', '25500000-0000-4000-8000-00000000000a', 'Announced 255', 'announced');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, ends_at, doors_at, status) VALUES
  ('25500000-0000-4000-8000-0000000000f1', '25500000-0000-4000-8000-0000000000e1', now() + interval '20 days', NULL, NULL, 'scheduled'),
  ('25500000-0000-4000-8000-0000000000f2', '25500000-0000-4000-8000-0000000000e2', now() + interval '25 days', NULL, NULL, 'scheduled');
-- t01..t13 on the on_sale event e1 (t11 hidden, t12 door_only, the rest public); t21 on the announced event e2.
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
SELECT tap._t255(n), '25500000-0000-4000-8000-0000000000e1', 'admission', 'Tier ' || n || ' 255', 2000 + n,
       CASE n WHEN 11 THEN 'hidden' WHEN 12 THEN 'door_only' ELSE 'public' END
  FROM generate_series(1, 13) n;
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  (tap._t255(21), '25500000-0000-4000-8000-0000000000e2', 'admission', 'Tier 21 255', 2021, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold)
SELECT tap._b255(n), tap._t255(n),
       CASE WHEN n = 21 THEN '25500000-0000-4000-8000-0000000000f2' ELSE '25500000-0000-4000-8000-0000000000f1' END::uuid,
       'public_sale', 10, 0, 0
  FROM (SELECT generate_series(1, 13) AS n UNION ALL SELECT 21) s;
-- native issuance on, a TTL and a per-user cap (the E-28 keys a live sale needs) — the next version of each key
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT x.k, coalesce((SELECT max(c.version) FROM catalog.platform_config c WHERE c.key = x.k), 0) + 1, x.v, x.vis
  FROM (VALUES ('feature.native_issuance_enabled',    'true'::jsonb,          'public'),
               ('inventory.hold_ttl_interval',        '"15 minutes"'::jsonb,  'restricted'),
               ('inventory.per_user_active_hold_max', '100'::jsonb,           'restricted')) x(k, v, vis);

-- the windows, through 162's setter as the org_owner; every bound relative to the frozen now()
SELECT tap.login('25500000-0000-4000-8000-000000000101');
DO $w$
BEGIN
  PERFORM venue.set_ticket_type_sale_window(tap._t255(1),  now() + interval '1 hour', now() + interval '2 hours', 'pgtap_255', 'ck255-w-01');  -- before
  PERFORM venue.set_ticket_type_sale_window(tap._t255(2),  now(),                     now() + interval '1 hour',  'pgtap_255', 'ck255-w-02');  -- starts exactly now
  PERFORM venue.set_ticket_type_sale_window(tap._t255(3),  now() - interval '1 hour', now() + interval '1 hour',  'pgtap_255', 'ck255-w-03');  -- inside
  PERFORM venue.set_ticket_type_sale_window(tap._t255(4),  now() - interval '1 hour', now(),                      'pgtap_255', 'ck255-w-04');  -- ends exactly now
  PERFORM venue.set_ticket_type_sale_window(tap._t255(5),  now() - interval '2 hours', now() - interval '1 hour', 'pgtap_255', 'ck255-w-05');  -- after
  -- t06 NULL/NULL (never set)
  PERFORM venue.set_ticket_type_sale_window(tap._t255(7),  NULL,                      now() + interval '1 hour',  'pgtap_255', 'ck255-w-07');  -- open start, ends later
  PERFORM venue.set_ticket_type_sale_window(tap._t255(8),  now() - interval '1 hour', NULL,                       'pgtap_255', 'ck255-w-08');  -- started, open end
  PERFORM venue.set_ticket_type_sale_window(tap._t255(9),  NULL,                      now(),                      'pgtap_255', 'ck255-w-09');  -- open start, ends exactly now
  PERFORM venue.set_ticket_type_sale_window(tap._t255(10), now() + interval '1 hour', NULL,                       'pgtap_255', 'ck255-w-10');  -- starts later, open end
  -- t11 hidden, t12 door_only, t21 (announced event): NULL/NULL
  PERFORM venue.set_ticket_type_sale_window(tap._t255(13), now() - interval '1 hour', NULL,                       'pgtap_255', 'ck255-w-13');  -- replay tier, open for now
END $w$;
SELECT tap.logout();
SELECT is((SELECT count(*)::integer FROM venue.ticket_type tt
            JOIN (VALUES (1,  now() + interval '1 hour',  now() + interval '2 hours'),
                         (2,  now(),                      now() + interval '1 hour'),
                         (3,  now() - interval '1 hour',  now() + interval '1 hour'),
                         (4,  now() - interval '1 hour',  now()),
                         (5,  now() - interval '2 hours', now() - interval '1 hour'),
                         (6,  NULL::timestamptz,          NULL::timestamptz),
                         (7,  NULL,                       now() + interval '1 hour'),
                         (8,  now() - interval '1 hour',  NULL),
                         (9,  NULL,                       now()),
                         (10, now() + interval '1 hour',  NULL),
                         (11, NULL,                       NULL),
                         (12, NULL,                       NULL),
                         (13, now() - interval '1 hour',  NULL),
                         (21, NULL,                       NULL)) w(n, s, e)
              ON tt.ticket_type_id = tap._t255(w.n)
             AND tt.sale_starts_at IS NOT DISTINCT FROM w.s AND tt.sale_ends_at IS NOT DISTINCT FROM w.e), 14,
  'F1: fixtures — the 14 tiers carry the intended windows (set through 162''s setter, bounds relative to the frozen now())');

-- ── Section A — shape, ACL, body text ────────────────────────────────────────
SELECT is((SELECT prosecdef AND proconfig = ARRAY['search_path=""'] AND prorettype = 'jsonb'::regtype
             FROM pg_proc WHERE oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure), true,
  'A1: reserve_primary_inventory(uuid, integer, text) is still SECURITY DEFINER, search_path='''', returns jsonb');
SELECT is((SELECT prosecdef AND proconfig = ARRAY['search_path=""'] AND prorettype = 'jsonb'::regtype
             FROM pg_proc WHERE oid = 'venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure), true,
  'A2: create_inventory_hold(uuid, integer, text, text) is still SECURITY DEFINER, search_path='''', returns jsonb');
SELECT is(ARRAY[has_function_privilege('authenticated', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE'),
                has_function_privilege('anon',          'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE'),
                (SELECT coalesce(bool_or(a.grantee = 0), false) FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  WHERE p.oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure AND a.privilege_type = 'EXECUTE')],
          ARRAY[true, false, false],
  'A3: reserve_primary_inventory EXECUTE — authenticated yes, anon no, PUBLIC no (the 081 ACL; 185 restates no grant)');
SELECT is(ARRAY[has_function_privilege('authenticated', 'venue.create_inventory_hold(uuid, integer, text, text)', 'EXECUTE'),
                has_function_privilege('anon',          'venue.create_inventory_hold(uuid, integer, text, text)', 'EXECUTE'),
                (SELECT coalesce(bool_or(a.grantee = 0), false) FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  WHERE p.oid = 'venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure AND a.privilege_type = 'EXECUTE')],
          ARRAY[true, false, false],
  'A4: create_inventory_hold EXECUTE — authenticated yes, anon no, PUBLIC no (the 081 ACL; 185 restates no grant)');
SELECT is((SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname IN ('reserve_primary_inventory', 'create_inventory_hold')), 2,
  'A5: one overload each — 185 replaces at the exact signatures, adds none');
SELECT is(ARRAY[tap._markers255('venue.reserve_primary_inventory(uuid, integer, text)', false),
                tap._markers255('venue.reserve_primary_inventory(uuid, integer, text)', true)], ARRAY[1, 1],
  'A6: reserve_primary_inventory carries exactly one 185 block (one opening, one END marker)');
SELECT is(ARRAY[tap._markers255('venue.create_inventory_hold(uuid, integer, text, text)', false),
                tap._markers255('venue.create_inventory_hold(uuid, integer, text, text)', true)], ARRAY[1, 1],
  'A7: create_inventory_hold carries exactly one 185 block (one opening, one END marker)');
SELECT ok(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure)
            ~ 'venue\.ticket_type_on_sale\(\s*\(select b\.ticket_type_id from venue\.inventory_batch b where b\.batch_id = p_batch_id\), now\(\)\)'
          AND pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure) ~ '''precondition_failed: tier_not_on_sale''',
  'A8: reserve_primary_inventory asks 162''s predicate about the batch''s tier at now() and refuses tier_not_on_sale');
SELECT ok(pg_get_functiondef('venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure)
            ~ 'venue\.ticket_type_on_sale\(\s*\(select b\.ticket_type_id from venue\.inventory_batch b where b\.batch_id = p_batch_id\), now\(\)\)'
          AND pg_get_functiondef('venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure) ~ '''precondition_failed: tier_not_on_sale''',
  'A9: create_inventory_hold asks 162''s predicate about the batch''s tier at now() and refuses tier_not_on_sale');
SELECT is(md5(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure)),
  'd30669daef75abe15725aa0b04a107b0',
  'A10: reserve_primary_inventory body = 185''s (md5(pg_get_functiondef) d30669da)');
SELECT is(md5(pg_get_functiondef('venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure)),
  'ae2d7634878c368d531b96699ff9db99',
  'A11: create_inventory_hold body = 185''s (md5(pg_get_functiondef) ae2d7634)');
SELECT is(tap._strip255('venue.reserve_primary_inventory(uuid, integer, text)'), '3538344c0418c7b322accafdee76f0f6',
  'A12: reserve_primary_inventory minus the 185 block = the predecessor byte for byte (081 body; md5 3538344c)');
SELECT is(tap._strip255('venue.create_inventory_hold(uuid, integer, text, text)'), 'f177b73fadaa60234a6d416fed558d11',
  'A13: create_inventory_hold minus the 185 block = the predecessor byte for byte (081 body; md5 f177b73f)');
SELECT is((SELECT ARRAY[count(*), count(*) FILTER (WHERE pg_get_functiondef(p.oid) !~ 'ticket_type_on_sale|tier_not_on_sale')]::integer[]
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname = 'create_primary_checkout'), ARRAY[1, 1],
  'A14: venue.create_primary_checkout (one overload) carries no window gate (checkout is not changed: it requires covering holds)');
SELECT is((SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname IN ('allocate_comp', 'issue_comp')
              AND pg_get_functiondef(p.oid) !~ 'ticket_type_on_sale|tier_not_on_sale'), 2,
  'A15: comps (allocate_comp, issue_comp) carry no window gate (not changed)');

-- ── Section W — reserve_primary_inventory as an authenticated buyer ──────────
SELECT tap.login('25500000-0000-4000-8000-000000000199');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-01')$$, tap._b255(1)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'W1: before the window -> refused tier_not_on_sale');
SELECT is(tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-02')$$, tap._b255(2))) ->> 'status', 'ok',
  'W2: at the exact start instant (sale_starts_at = now()) -> allowed (starts inclusive)');
SELECT is(tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-03')$$, tap._b255(3))) ->> 'status', 'ok',
  'W3: inside the window -> allowed');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-04')$$, tap._b255(4)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'W4: at the exact end instant (sale_ends_at = now()) -> refused (ends exclusive)');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-05')$$, tap._b255(5)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'W5: after the window -> refused');
SELECT is(tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-06')$$, tap._b255(6))) ->> 'status', 'ok',
  'W6: NULL/NULL window (open both sides, 162) -> allowed');
SELECT is(tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-07')$$, tap._b255(7))) ->> 'status', 'ok',
  'W7: NULL start, end later -> allowed (open on the start side)');
SELECT is(tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-08')$$, tap._b255(8))) ->> 'status', 'ok',
  'W8: started, NULL end -> allowed (open on the end side)');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-09')$$, tap._b255(9)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'W9: NULL start, end exactly now -> refused (the end stays exclusive with an open start)');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-10')$$, tap._b255(10)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'W10: starts later, NULL end -> refused (the start still binds with an open end)');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-11')$$, tap._b255(11)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'W11: a HIDDEN tier of an on_sale event -> refused (162: hidden is never on sale)');
SELECT is(tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-12')$$, tap._b255(12))) ->> 'status', 'ok',
  'W12: a door_only tier with no window -> allowed (162: door_only is on sale)');
SELECT tap.logout();
-- the dark flag still answers first (a new, higher version of the flag = false, then back on)
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', max(version) + 1, 'false'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
SELECT tap.login('25500000-0000-4000-8000-000000000199');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-dark')$$, tap._b255(1)),
  'P0001', 'precondition_failed: feature_disabled', 'W13: native issuance dark + a before-window tier -> feature_disabled (the flag gate stays first)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', max(version) + 1, 'true'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
SELECT tap.login('25500000-0000-4000-8000-000000000199');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-r-21')$$, tap._b255(21)),
  'P0001', 'precondition_failed: not_on_sale', 'W14: a tier of an ANNOUNCED event -> not_on_sale (081''s event gate still answers before the tier gate)');
SELECT tap.logout();

-- ── Section H — create_inventory_hold as the org_owner (staff) ───────────────
SELECT tap.login('25500000-0000-4000-8000-000000000101');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-01')$$, tap._b255(1)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H1: staff hold before the window -> refused tier_not_on_sale');
SELECT is(tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-02')$$, tap._b255(2))) ->> 'status', 'ok',
  'H2: staff hold at the exact start instant -> allowed');
SELECT is(tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-03')$$, tap._b255(3))) ->> 'status', 'ok',
  'H3: staff hold inside the window -> allowed');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-04')$$, tap._b255(4)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H4: staff hold at the exact end instant -> refused');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-05')$$, tap._b255(5)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H5: staff hold after the window -> refused');
SELECT is(tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-06')$$, tap._b255(6))) ->> 'status', 'ok',
  'H6: staff hold, NULL/NULL window -> allowed');
SELECT is(tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-07')$$, tap._b255(7))) ->> 'status', 'ok',
  'H7: staff hold, NULL start, end later -> allowed');
SELECT is(tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-08')$$, tap._b255(8))) ->> 'status', 'ok',
  'H8: staff hold, started, NULL end -> allowed');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-09')$$, tap._b255(9)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H9: staff hold, NULL start, end exactly now -> refused');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-10')$$, tap._b255(10)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H10: staff hold, starts later, NULL end -> refused');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-11')$$, tap._b255(11)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H11: staff hold on a HIDDEN tier -> refused (162''s predicate, as for the buyer)');
SELECT is(tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-12')$$, tap._b255(12))) ->> 'status', 'ok',
  'H12: staff hold on a door_only tier -> allowed');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-21')$$, tap._b255(21)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'H13: staff hold on a tier of an ANNOUNCED event -> refused (the event arm of 162''s predicate; 081 had no event gate here)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', max(version) + 1, 'false'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
SELECT tap.login('25500000-0000-4000-8000-000000000101');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-dark')$$, tap._b255(1)),
  'P0001', 'precondition_failed: feature_disabled', 'H14: native issuance dark + a before-window tier -> feature_disabled (the flag gate stays first)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', max(version) + 1, 'true'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
SELECT tap.login('25500000-0000-4000-8000-000000000199');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-h-fan')$$, tap._b255(1)),
  '42501', NULL, 'H15: a fan on a before-window tier -> 42501 (staff authority is decided before the window)');
SELECT tap.logout();

-- ── Section N — a refusal writes nothing (postgres reads) ────────────────────
SELECT is(tap._holds255(ARRAY[tap._b255(1), tap._b255(4), tap._b255(5), tap._b255(9), tap._b255(10), tap._b255(11), tap._b255(21)]), 0,
  'N1: no inventory_hold row on any refused batch (b01 b04 b05 b09 b10 b11 b21; buyer and staff)');
SELECT is(tap._held255(ARRAY[tap._b255(1), tap._b255(4), tap._b255(5), tap._b255(9), tap._b255(10), tap._b255(11), tap._b255(21)]), 0,
  'N2: held = 0 on every refused batch (no counter draw)');
SELECT is(tap._moves255(ARRAY[tap._b255(1), tap._b255(4), tap._b255(5), tap._b255(9), tap._b255(10), tap._b255(11), tap._b255(21)]), 0,
  'N3: no inventory_movement row on any refused batch (no ledger row)');
SELECT is(ARRAY[tap._holds255(ARRAY[tap._b255(2), tap._b255(3), tap._b255(6), tap._b255(7), tap._b255(8), tap._b255(12)]),
                tap._held255(ARRAY[tap._b255(2), tap._b255(3), tap._b255(6), tap._b255(7), tap._b255(8), tap._b255(12)])], ARRAY[12, 12],
  'N4: the six allowed batches carry exactly 12 holds and held = 12 (one buyer + one staff hold each)');
SELECT is((SELECT count(*)::integer FROM venue.inventory_hold
            WHERE identity_id IN ('25500000-0000-4000-8000-000000000101', '25500000-0000-4000-8000-000000000199')), 12,
  'N5: the two callers hold exactly 12 holds in all — nothing landed anywhere else');

-- ── Section R — idempotency replay after the window closed (t13 / b13) ──────
SELECT tap.login('25500000-0000-4000-8000-000000000199');
SELECT tap._store255('r_hold', tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-replay-b')$$, tap._b255(13))) ->> 'hold_id');
SELECT tap._store255('r_exp',  (SELECT expires_at::text FROM venue.inventory_hold WHERE hold_id = tap._fetch255('r_hold')::uuid));
SELECT isnt(tap._fetch255('r_hold'), NULL, 'R1: the buyer holds b13 in-window (open-ended window started an hour ago)');
SELECT tap.logout();
SELECT tap.login('25500000-0000-4000-8000-000000000101');
SELECT tap._store255('s_hold', tap._try255(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-replay-s')$$, tap._b255(13))) ->> 'hold_id');
SELECT isnt(tap._fetch255('s_hold'), NULL, 'R2: staff holds b13 in-window');
SELECT is(venue.set_ticket_type_sale_window(tap._t255(13), now() - interval '1 hour', now(), 'pgtap_255', 'ck255-w-13-close') ->> 'status', 'ok',
  'R3: the org_owner closes t13''s window — it now ends exactly now (closed: ends exclusive)');
SELECT is(venue.ticket_type_on_sale(tap._t255(13)), false, 'R4: 162''s predicate: t13 is not on sale now');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-replay-s2')$$, tap._b255(13)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'R5: a FRESH staff key on b13 is refused — the window really is closed for new holds');
SELECT throws_ok(format($$SELECT venue.create_inventory_hold(%L, 1, 'staff', 'ck255-replay-s')$$, tap._b255(13)),
  'P0001', 'precondition_failed: idempotency_replay',
  'R6: the staff REPLAY after the window closed -> 081''s own replay answer (idempotency_replay, raised at the INSERT), not tier_not_on_sale');
SELECT tap.logout();
SELECT tap.login('25500000-0000-4000-8000-000000000199');
SELECT tap._store255('r_replay', tap._try255(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-replay-b')$$, tap._b255(13)))::text);
SELECT is(tap._fetch255('r_replay')::jsonb ->> 'status', 'idempotency_replay',
  'R7: the buyer REPLAY after the window closed -> status idempotency_replay (not tier_not_on_sale)');
SELECT is(tap._fetch255('r_replay')::jsonb ->> 'hold_id', tap._fetch255('r_hold'), 'R8: …with the SAME hold_id');
SELECT is((tap._fetch255('r_replay')::jsonb ->> 'expires_at')::timestamptz, tap._fetch255('r_exp')::timestamptz, 'R9: …and the original expiry');
SELECT throws_ok(format($$SELECT venue.reserve_primary_inventory(%L, 1, 'ck255-replay-b2')$$, tap._b255(13)),
  'P0001', 'precondition_failed: tier_not_on_sale', 'R10: a FRESH buyer key on b13 is refused tier_not_on_sale');
SELECT tap.logout();
SELECT is(ARRAY[tap._holds255(ARRAY[tap._b255(13)]), tap._held255(ARRAY[tap._b255(13)]), tap._moves255(ARRAY[tap._b255(13)])], ARRAY[2, 2, 2],
  'R11: b13 still carries exactly the two in-window holds, held = 2, two ledger rows — neither replay nor refusal wrote');
SELECT is((SELECT array_agg(hold_id::text ORDER BY command_idempotency_key) FROM venue.inventory_hold WHERE batch_id = tap._b255(13)),
          ARRAY[tap._fetch255('r_hold'), tap._fetch255('s_hold')],
  'R12: the only rows on b13 are the buyer''s and the staff hold, under their original keys');
SELECT is((SELECT array_agg(status || '/' || quantity ORDER BY command_idempotency_key) FROM venue.inventory_hold WHERE batch_id = tap._b255(13)),
          ARRAY['active/1', 'active/1'],
  'R13: both originals unchanged (active, quantity 1)');

SELECT * FROM finish();
ROLLBACK;
