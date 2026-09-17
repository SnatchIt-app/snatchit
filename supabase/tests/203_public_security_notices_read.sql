-- 203_public_security_notices_read.sql — migration 136: the mobile client's
-- owner-scoped read and acknowledgement of mandatory security notices are
-- reachable through `public`, render the server template, return only the
-- caller's own security-type rows, and are callable by authenticated only.
-- Runs as postgres inside BEGIN … ROLLBACK like every suite here.
BEGIN;
SELECT plan(36);

-- ── A. shape and grants ──────────────────────────────────────────────────────
SELECT has_function('public', 'get_my_security_notices', ARRAY[]::text[],
  'A1: public.get_my_security_notices() exists');
SELECT is_definer('public', 'get_my_security_notices', ARRAY[]::text[],
  'A2: ...SECURITY DEFINER (it must reach notify on the caller''s behalf)');
SELECT ok((SELECT p.proconfig @> ARRAY['search_path=""'] FROM pg_proc p WHERE p.oid = 'public.get_my_security_notices()'::regprocedure),
  'A3: search_path is pinned to EMPTY (exact proconfig entry)');
SELECT ok(has_function_privilege('authenticated', 'public.get_my_security_notices()', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.get_my_security_notices()', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'public.get_my_security_notices()', 'EXECUTE'),
  'A4: EXECUTE authenticated only — anon and service_role refused');
SELECT has_function('public', 'mark_security_notices_read', ARRAY['uuid[]'],
  'A5: public.mark_security_notices_read(uuid[]) exists');
SELECT is_definer('public', 'mark_security_notices_read', ARRAY['uuid[]'],
  'A6: ...SECURITY DEFINER');
SELECT ok((SELECT p.proconfig @> ARRAY['search_path=""'] FROM pg_proc p WHERE p.oid = 'public.mark_security_notices_read(uuid[])'::regprocedure),
  'A7: search_path is pinned to EMPTY');
SELECT ok(has_function_privilege('authenticated', 'public.mark_security_notices_read(uuid[])', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.mark_security_notices_read(uuid[])', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'public.mark_security_notices_read(uuid[])', 'EXECUTE'),
  'A8: EXECUTE authenticated only — anon and service_role refused');

-- ── B. fixtures (as postgres): one security notice and one non-security notice for the buyer ─
SELECT tap.seed_core();
CREATE TEMP TABLE _n203 AS
SELECT notify.enqueue(tap.buyer(), 'security_device_rebound', 'account_security', gen_random_uuid(),
                      '{"device_name":"iPhone 203"}'::jsonb, 'test-203-rebound') AS sec_id,
       notify.enqueue(tap.buyer(), 'purchase_failed', 'payment', gen_random_uuid(),
                      '{}'::jsonb, 'test-203-other') AS other_id;
-- memo helpers: after tap.login the caller is `authenticated`, which cannot read a postgres-owned temp table (the 198/202
-- lesson), so the fixture ids travel through SECURITY DEFINER readers owned by postgres.
CREATE FUNCTION public._sec203() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT sec_id FROM pg_temp._n203 $$;
CREATE FUNCTION public._oth203() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT other_id FROM pg_temp._n203 $$;
SELECT isnt(public._sec203(), NULL, 'B0: the security notice was enqueued (type registered and active)');
SELECT isnt(public._oth203(), NULL, 'B0b: the non-security notice was enqueued');

-- ── C. the buyer reads only the security notice, rendered from the server template ─
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*) FROM public.get_my_security_notices()), 1::bigint,
  'C1: exactly one row — the non-security notice is not returned');
SELECT is((SELECT type_key FROM public.get_my_security_notices()), 'security_device_rebound',
  'C2: ...and it is the device-rebound notice');
SELECT is((SELECT title FROM public.get_my_security_notices()), 'A device stopped receiving your notifications',
  'C3: title is the server template''s subject — 136''s v2 (D-verified copy), rendered server-side; the client never hard-codes it');
SELECT is((SELECT body FROM public.get_my_security_notices()),
  'A device that was getting notifications for this account is now registered to a different account. If that was you signing in to another account, there''s nothing to do. If not, sign out of all devices.',
  'C4: body is v2 verbatim — the owner-corrected meaning (THIS account''s device went to ANOTHER account), the one non-collateral action, and NO {{device_name}} (claimer-supplied text never enters the victim''s alert), no "sign in on that phone", no password clause');
SELECT ok((SELECT body NOT LIKE '%iPhone 203%' AND body NOT LIKE '%sign in on that phone%' AND body NOT LIKE '%password%' FROM public.get_my_security_notices()),
  'C4b: negative pins — the v1 hazards (device name, sign-in-on-that-phone, password) are absent from what the client receives');
SELECT is((SELECT read_at FROM public.get_my_security_notices()), NULL,
  'C5: unread on first read');
SELECT is((SELECT id FROM public.get_my_security_notices()), public._sec203(),
  'C6: the id is the enqueued notification id (the client acknowledges by it)');
SELECT tap.logout();

-- ── D. IDOR and anon ────────────────────────────────────────────────────────
SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*) FROM public.get_my_security_notices()), 0::bigint,
  'D1: another account sees none of the buyer''s notices');
SELECT is(public.mark_security_notices_read(ARRAY[public._sec203()]), 0,
  'D2: another account acknowledging the buyer''s notice touches 0 rows and learns nothing');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.get_my_security_notices() $$, '42501', NULL, 'D3: anon cannot read');
SELECT throws_ok($$ SELECT public.mark_security_notices_read('{}'::uuid[]) $$, '42501', NULL, 'D4: anon cannot acknowledge');
SELECT tap.logout();

-- ── E. acknowledgement: own security ids only, idempotent, never raises for foreign ids ─
SELECT tap.login(tap.buyer());
SELECT is(public.mark_security_notices_read(ARRAY[public._sec203(), public._oth203(), gen_random_uuid()]), 1,
  'E1: acknowledging [security id, own non-security id, unknown id] updates exactly the security notice');
SELECT is((SELECT count(*) FROM public.get_my_security_notices()), 0::bigint,
  'E2: the acknowledged notice LEAVES the surface — unread only (a read row is neither returned nor paged for, so the cost falls to zero on acknowledgement)');
SELECT ok((SELECT n.read_at IS NOT NULL FROM notify.notification n WHERE n.notification_id = public._sec203()),
  'E2b: ...while the row itself carries read_at (marked, not deleted or dismissed)');
SELECT is((SELECT n.read_at FROM notify.notification n WHERE n.notification_id = public._oth203()), NULL,
  'E3: the non-security notice was NOT marked — the wrapper is scoped to security types, not just to the caller');
SELECT is(public.mark_security_notices_read(ARRAY[public._sec203()]), 0,
  'E4: acknowledging again updates 0 (idempotent)');
SELECT is(public.mark_security_notices_read(NULL), 0,
  'E5: NULL ids → 0, no error');
SELECT tap.logout();

-- ── G. pagination (E-160), unread-only termination, and the input bound ──────
-- A second, UNREAD security notice (a different token's dedupe key), then 60 newer non-security rows push it onto
-- get_inbox's SECOND page; it must still come back (no cap, no silent truncation), and the cursor must not skip it
-- (created_at defaults to clock_timestamp(): no keyset ties). The first notice is already read (E) and must not be paged for.
SELECT tap.login(tap.buyer());
SELECT is(public.mark_security_notices_read(ARRAY[public._sec203()]), 0, 'G0: (setup) re-acknowledging the read notice returns 0, not an error');
SELECT tap.logout();
CREATE TEMP TABLE _n203b AS
SELECT notify.enqueue(tap.buyer(), 'security_device_rebound', 'account_security', gen_random_uuid(),
                      '{"device_name":"iPad 203"}'::jsonb, 'test-203-rebound-2') AS sec2_id;
CREATE FUNCTION public._sec203b() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT sec2_id FROM pg_temp._n203b $$;
SELECT count(*) FROM (SELECT notify.enqueue(tap.buyer(), 'purchase_failed', 'payment', gen_random_uuid(), '{}'::jsonb, NULL) FROM generate_series(1, 60)) g;
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*) FROM notify.get_inbox(NULL, 50) i WHERE i.type_key = 'security_device_rebound'), 0::bigint,
  'G1a: neither security notice is on the first inbox page any more (60 newer rows above them)');
SELECT is((SELECT count(*) FROM public.get_my_security_notices()), 1::bigint,
  'G1: the wrapper returns exactly the UNREAD one — it pages until every counted unread row is found; a 50-row or 200-row cap would have hidden a mandatory notice, and the read one is not paged for');
SELECT is((SELECT id FROM public.get_my_security_notices()), public._sec203b(),
  'G1b: ...and it is the unread notice, by id');
SELECT is(public.mark_security_notices_read((SELECT array_agg(gen_random_uuid()) FROM generate_series(1, 100)) || ARRAY[public._sec203b()]), 0,
  'G2: p_ids is bounded to its first 100 elements — the unread security id at position 101 is NOT considered (0)');
SELECT is(public.mark_security_notices_read(ARRAY[public._sec203b()]), 1,
  'G3: ...and the same id within the bound is marked (1) — the bound, not the scope, produced the 0 above');
SELECT is((SELECT count(*) FROM public.get_my_security_notices()), 0::bigint,
  'H1: after acknowledgement the surface is empty although both rows exist unread-free — the termination target is the unread count, so nothing is paged and nothing is rendered');
SELECT tap.logout();

-- ── F. the copy pin (owner-corrected meaning lives in the server template, one source for web and mobile) ─
SELECT is((SELECT version FROM notify.template WHERE template_key = 'security_device_rebound' AND locale = 'en-US' AND channel = 'in_app' ORDER BY version DESC LIMIT 1), 2,
  'F1: the rendered template is v2 (136) — a copy change is a new template version, reviewed, never a client string; v1 (135) is left in place');
SELECT is((SELECT count(*) FROM notify.template WHERE template_key = 'security_device_rebound' AND locale = 'en-US' AND channel = 'in_app'), 2::bigint,
  'F2: exactly two versions exist — 136 was additive, 135''s row untouched');

SELECT * FROM finish();
ROLLBACK;
