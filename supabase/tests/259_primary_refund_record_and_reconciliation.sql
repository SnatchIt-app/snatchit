-- ============================================================================
-- 259_primary_refund_record_and_reconciliation.sql — migration 20261027033000 (registry 189 / pgTAP 259, A).
--
-- (a) ops.record_primary_refund(order, amount_minor, reason_code, command_key): ops.assert_role(platform_admin
--     | platform_support) — an operator role at aal2 — and the console pause switch, then
--     kernel.refund_primary_order as the CALLER (auth.uid() preserved inside the definer), result returned
--     as is, nothing else written. Refunds stay manual: the owner refunds in Stripe by hand.
-- (b) ops.primary_reconciliation(from, to): read-only, ops.assert_reader; one row per finalized native
--     payment; attention items (i) stripe_refunded_tickets_live CRITICAL, (ii) kernel_refund_without_stripe
--     (24 h), (iii) refund_amount_mismatch, (iv) issuance_missing (15 min) / issuance_over.
--
-- Fixture style: 252 (synthetic rows as postgres, fixed ids tagged 25900000-…; the orders go through the REAL
-- issuance path — venue.finalize_primary_order as the rehearsal superuser mints the atoms, links
-- kernel.payment_native and marks the order paid; the global ES256 key through the live 110 guard when no
-- active global key exists; every config value a NEW VERSION of the append-only row). Stripe refunds are
-- recorded through the webhook's own writer, public.record_refund_state, as service_role. Callers through
-- tap.login + an aal claim merged into request.jwt.claims (the 182 helper). Two states are NOT producible
-- through the real path and are written as rows, labelled where they are: R4/R5 (a payment_native link with
-- no mint — finalize links and mints in one transaction) and R6's second atom (the mint's replay check and
-- inventory_movement_cause_uq stop a second issuance; ownership_log_cause_uq alone would not). Time is
-- simulated only by back-dating a kernel.refund row the RPC wrote (R2) — now() is frozen per transaction,
-- so each window is asserted as a branch (inside / outside), never as a recomputed value.
--
--   A   shape: both functions exist, SECURITY DEFINER, search_path='', record VOLATILE / reader STABLE;
--       EXECUTE authenticated only (anon, service_role, PUBLIC none); md5 = 189's; one overload each; the
--       record body is the assert + pause + key checks + the kernel call; the reader starts with
--       ops.assert_reader(); kernel.refund_primary_order's ACL is untouched (still not authenticated).
--   U   record_primary_refund on O1: anon, a fan (aal2), an aal1 admin, an admin with no aal claim, a
--       platform_risk operator and platform_support over the cap are refused; nothing was written; the
--       door admits O1's atom; an aal2 platform_admin's FULL refund -> ok, voided 1; the kernel.refund row
--       (no Stripe ref), the order refunded, the atom voided, the kernel audit row attributed to the admin;
--       the door now refuses the atom; a replay with the same key -> idempotency_replay, same refund_id,
--       nothing new; a req: key and a malformed key refused; the console pause refuses; platform_support
--       WITHIN the cap succeeds (partial, money only — the kernel's cap rules apply unchanged); ops.action /
--       ops.audit untouched.
--   R   primary_reconciliation: anon / fan / aal1 refused, support aal2 reads; then per fixture, each item
--       appears and disappears when fixed: (i) R1 Stripe refunded with the atom live -> critical (+ (iii)),
--       fixed by recording the refund; (ii) R2 kernel refund inside 24 h -> none, back-dated past 24 h ->
--       kernel_refund_without_stripe, fixed by the Stripe refund -> refund_settled with the atom voided;
--       (iii) R3 kernel 2750 vs Stripe 2500 -> mismatch, a second Stripe refund of 250 -> none; (iv) R4
--       linked 20 min ago with no atom -> issuance_missing, minted -> none; R5 linked 5 min ago -> none;
--       R6 a second live atom on its item -> issuance_over, voided -> none; O2's deliberate kernel partial
--       with a matching Stripe partial -> no critical; the window filter; the reader writes nothing.
--
-- Expected on the stacked tree 159 .. 185 + 188 WITHOUT 189 (RED, predicted before the run): the file runs to
-- the end (every call of a 189 function goes through throws_ok or tap._try259, which catch its 42883).
-- Predicted: 54 emitted = 49 not ok + 5 ok. ok: F1 (fixtures), A10 (kernel ACL), U7 U8 (nothing refunded,
-- the door admits), U18 (no ops rows — nothing ran). not ok: A1-A9 (absent: every shape probe is NULL-safe
-- through to_regprocedure / coalesce), U1-U6 and U14-U16 (42883 instead of the expected refusal), U9-U13 and
-- U17 (no refund), R1-R3 and R22 (42883), R4-R21 and R23-R25 (no reconciliation; R6 because R2/R3 were not
-- refunded). OBSERVED: 47 not ok + 7 ok — U1 and R1 also pass on RED: anon holds no USAGE on schema ops, so
-- a missing function answers 42501 exactly like a revoked EXECUTE. U1/R1 are therefore vacuous as negative
-- evidence; the anon refusal is pinned structurally by A4 (has_function_privilege anon = false).
-- Negative controls (runner mutants on the GREEN tree, measured): M3 record_primary_refund without the
-- step-up (kernel.is_platform only) -> A5 A8 U2-U10 U13 not ok — U3 (the aal1 admin is NOT refused and
-- refunds O1) and U4 directly, U2/U5 by message, the rest downstream of the unexpected refund; M4 the reader
-- without item (i) -> A6 R7 R8 R9 not ok.
-- ============================================================================
BEGIN;
SELECT plan(54);

CREATE TABLE tap.memo_259 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store259(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_259 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch259(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_259 WHERE k = $1 $m$;
CREATE FUNCTION tap._try259(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN r;
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
-- an aal claim merged into the current claims (the 182 helper)
CREATE FUNCTION tap._aal259(p text) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM set_config('request.jwt.claims',
  (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb || jsonb_build_object('aal', p))::text, true); END $f$;
-- the stored reconciliation of a stage: the row of one payment, its attention codes, its state
CREATE FUNCTION tap._row259(stage text, pay uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT e FROM jsonb_array_elements((SELECT v::jsonb -> 'rows' FROM tap.memo_259 WHERE k = stage)) e
   WHERE e ->> 'payment_id' = pay::text $m$;
CREATE FUNCTION tap._codes259(stage text, pay uuid) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT coalesce((SELECT array_agg(c ORDER BY n) FROM jsonb_array_elements_text(tap._row259(stage, pay) -> 'attention') WITH ORDINALITY x(c, n)),
                  CASE WHEN tap._row259(stage, pay) IS NULL THEN NULL ELSE '{}'::text[] END) $m$;
-- definer reads of kernel / ops state (no client role reads them)
CREATE FUNCTION tap._refunds259(pay uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT count(*)::integer FROM kernel.refund WHERE payment_id = pay $m$;
CREATE FUNCTION tap._atom259(item uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT l.ticket_atom_id FROM kernel.ticket_ownership_log l WHERE l.cause_ref = item AND l.sequence = 1 ORDER BY l.ticket_atom_id LIMIT 1 $m$;
CREATE FUNCTION tap._state259(item uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT string_agg(t.state, ',' ORDER BY t.ticket_atom_id) FROM kernel.ticket_ownership_log l JOIN kernel.tickets t ON t.ticket_atom_id = l.ticket_atom_id
     WHERE l.cause_ref = item AND l.sequence = 1 $m$;
CREATE FUNCTION tap._ostatus259(o uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT status FROM venue."order" WHERE order_id = o $m$;
CREATE FUNCTION tap._opsrows259() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS
$m$ SELECT (SELECT count(*) FROM ops.action) + (SELECT count(*) FROM ops.audit) $m$;
CREATE FUNCTION tap._writes259() RETURNS bigint LANGUAGE sql STABLE AS
$m$ SELECT coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0)::bigint FROM pg_stat_xact_user_tables WHERE schemaname <> 'tap' $m$;
GRANT EXECUTE ON FUNCTION tap._store259(text, text), tap._fetch259(text), tap._try259(text), tap._aal259(text),
  tap._row259(text, uuid), tap._codes259(text, uuid), tap._refunds259(uuid), tap._atom259(uuid), tap._state259(uuid),
  tap._ostatus259(uuid), tap._opsrows259(), tap._writes259() TO anon, authenticated, service_role;
CREATE FUNCTION tap._pem259() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT u.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.email, '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM (VALUES ('25900000-0000-4000-8000-000000000101', 'buyer.259@test.local'),
               ('25900000-0000-4000-8000-000000000199', 'fan.259@test.local'),
               ('25900000-0000-4000-8000-000000000a01', 'admin.259@test.local'),
               ('25900000-0000-4000-8000-000000000a02', 'support.259@test.local'),
               ('25900000-0000-4000-8000-000000000a03', 'risk.259@test.local'),
               ('25900000-0000-4000-8000-000000000a04', 'scanner.259@test.local'),
               ('00000000-0000-0000-0000-0000000000f1', 'sn-system.259@test.local')) u(id, email)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES
  ('25900000-0000-4000-8000-000000000a01', 'platform_admin'),
  ('25900000-0000-4000-8000-000000000a02', 'platform_support'),
  ('25900000-0000-4000-8000-000000000a03', 'platform_risk');
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('25900000-0000-4000-8000-00000000000a', 'Org A 259', 'Org A 259', 'active');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('25900000-0000-4000-8000-0000000000a1', '25900000-0000-4000-8000-00000000000a', 'Room 259', 'wynwood', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES
  ('25900000-0000-4000-8000-0000000000a1', '25900000-0000-4000-8000-000000000a04', 'venue_scanner', '25900000-0000-4000-8000-000000000a01');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('25900000-0000-4000-8000-0000000000e1', '25900000-0000-4000-8000-0000000000a1', '25900000-0000-4000-8000-00000000000a', 'Refunds 259', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('25900000-0000-4000-8000-0000000000f1', '25900000-0000-4000-8000-0000000000e1', now() + interval '30 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('25900000-0000-4000-8000-000000000011', '25900000-0000-4000-8000-0000000000e1', 'admission', 'GA 259', 2500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('25900000-0000-4000-8000-000000000021', '25900000-0000-4000-8000-000000000011', '25900000-0000-4000-8000-0000000000f1', 'public_sale', 100, 1, 0);
-- the buyer's reservation: finalize names each item's batch through the buyer's hold (converted by the first finalize)
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('25900000-0000-4000-8000-000000000031', '25900000-0000-4000-8000-000000000021', '25900000-0000-4000-8000-000000000101', 1, 'active', now() + interval '1 hour', 'h-259');
-- eight one-ticket orders (2500 face; the payments row charged 2750 = face + 250 buyer fee, as the edge writes it)
--   O1 authority + full refund + door + replay · O2 support within the cap · R1 (i) · R2 (ii) / settled · R3 (iii)
--   R4 (iv) missing · R5 (iv) grace · R6 (iv) over
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
SELECT o.id::uuid, '25900000-0000-4000-8000-000000000101', '25900000-0000-4000-8000-0000000000f1', '25900000-0000-4000-8000-00000000000a',
       'pending', 'app', 2500, 'USD', 'o-259-' || o.tag
  FROM (VALUES ('25900000-0000-4000-8000-000000000301', 'o1'), ('25900000-0000-4000-8000-000000000302', 'o2'),
               ('25900000-0000-4000-8000-000000000311', 'r1'), ('25900000-0000-4000-8000-000000000312', 'r2'),
               ('25900000-0000-4000-8000-000000000313', 'r3'), ('25900000-0000-4000-8000-000000000314', 'r4'),
               ('25900000-0000-4000-8000-000000000315', 'r5'), ('25900000-0000-4000-8000-000000000316', 'r6')) o(id, tag);
INSERT INTO venue.order_item (id, order_id, ticket_type_id, quantity, unit_price_minor)
SELECT ('25900000-0000-4000-8000-0000000004' || right(o.order_id::text, 2))::uuid, o.order_id, '25900000-0000-4000-8000-000000000011', 1, 2500
  FROM venue."order" o WHERE o.order_id::text LIKE '25900000-%';
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
SELECT ('25900000-0000-4000-8000-0000000006' || right(o.order_id::text, 2))::uuid, NULL, '25900000-0000-4000-8000-000000000101', NULL,
       2500, 250, 0, 2750, 'pi_259_' || right(o.order_id::text, 2), 'succeeded', 'native_primary', now()
  FROM venue."order" o WHERE o.order_id::text LIKE '25900000-%';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT x.k, coalesce((SELECT max(c.version) FROM catalog.platform_config c WHERE c.key = x.k), 0) + 1, x.v, x.vis
  FROM (VALUES ('feature.native_issuance_enabled',     'true'::jsonb, 'public'),
               ('refund.platform_support_max_minor',   '1000'::jsonb, 'restricted')) x(k, v, vis);
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
SELECT '00000000-0000-0000-0000-0000000000b0', 'global', tap._pem259(),
       'arn:aws:kms:us-east-1:000000000000:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now()
 WHERE NOT EXISTS (SELECT 1 FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active');
-- THE REAL ISSUANCE PATH for O1 O2 R1 R2 R3 R6 (as the rehearsal superuser; auth.uid() NULL -> actor SN-SYSTEM)
SELECT tap._store259('fin_' || right(o::text, 2), venue.finalize_primary_order(o, ('25900000-0000-4000-8000-0000000006' || right(o::text, 2))::uuid, 'ck259-fin-' || right(o::text, 2), NULL)::text)
  FROM unnest(ARRAY['25900000-0000-4000-8000-000000000301', '25900000-0000-4000-8000-000000000302', '25900000-0000-4000-8000-000000000311',
                    '25900000-0000-4000-8000-000000000312', '25900000-0000-4000-8000-000000000313', '25900000-0000-4000-8000-000000000316']::uuid[]) o;
-- R4 / R5 — NOT producible through finalize (it links and mints in one transaction): paid orders linked with no
-- mint, R4 linked 20 minutes ago, R5 5 minutes ago (rows; the 252 payment_state-matrix precedent)
UPDATE venue."order" SET status = 'paid' WHERE order_id IN ('25900000-0000-4000-8000-000000000314', '25900000-0000-4000-8000-000000000315');
INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor, linked_at) VALUES
  ('25900000-0000-4000-8000-000000000614', '25900000-0000-4000-8000-000000000314', 2500, now() - interval '20 minutes'),
  ('25900000-0000-4000-8000-000000000615', '25900000-0000-4000-8000-000000000315', 2500, now() - interval '5 minutes');
SELECT is((SELECT ARRAY[count(*) FILTER (WHERE v::jsonb ->> 'status' = 'ok'),
                        (SELECT count(*) FROM kernel.payment_native WHERE order_id::text LIKE '25900000-%'),
                        (SELECT count(*) FROM venue."order" WHERE order_id::text LIKE '25900000-%' AND status = 'paid')]::integer[]
             FROM tap.memo_259 WHERE k LIKE 'fin\_%'),
          ARRAY[6, 8, 8],
  'F1: fixtures — six orders finalized through the real path, eight payment_native links, eight paid orders');

-- ── Section A — shape, ACL, body text ────────────────────────────────────────
SELECT is(ARRAY[to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)') IS NOT NULL,
                to_regprocedure('ops.primary_reconciliation(date, date)') IS NOT NULL], ARRAY[true, true],
  'A1: ops.record_primary_refund(uuid, integer, text, text) and ops.primary_reconciliation(date, date) exist');
SELECT ok(coalesce((SELECT bool_and(prosecdef AND proconfig = ARRAY['search_path=""'] AND prorettype = 'jsonb'::regtype) AND count(*) = 2
                      FROM pg_proc WHERE oid IN (to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'),
                                                 to_regprocedure('ops.primary_reconciliation(date, date)'))), false),
  'A2: both are SECURITY DEFINER, search_path='''', return jsonb');
SELECT is(ARRAY[(SELECT provolatile::text FROM pg_proc WHERE oid = to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')),
                (SELECT provolatile::text FROM pg_proc WHERE oid = to_regprocedure('ops.primary_reconciliation(date, date)'))],
          ARRAY['v', 's'],
  'A3: the record is VOLATILE, the reader STABLE (a write inside it raises)');
SELECT is(ARRAY[coalesce(has_function_privilege('authenticated', to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), 'EXECUTE'), false),
                coalesce(has_function_privilege('anon',          to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), 'EXECUTE'), true),
                coalesce(has_function_privilege('service_role',  to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), 'EXECUTE'), true),
                coalesce(has_function_privilege('authenticated', to_regprocedure('ops.primary_reconciliation(date, date)'), 'EXECUTE'), false),
                coalesce(has_function_privilege('anon',          to_regprocedure('ops.primary_reconciliation(date, date)'), 'EXECUTE'), true),
                coalesce(has_function_privilege('service_role',  to_regprocedure('ops.primary_reconciliation(date, date)'), 'EXECUTE'), true),
                coalesce((SELECT bool_or(a.grantee = 0) FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           WHERE p.oid IN (to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'),
                                           to_regprocedure('ops.primary_reconciliation(date, date)'))), true)],
          ARRAY[true, false, false, true, false, false, false],
  'A4: EXECUTE — authenticated only on both (anon no, service_role no, no PUBLIC entry)');
SELECT is(md5(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'))),
  '337a8f19d11a482e47437eb968dab40b', 'A5: ops.record_primary_refund body = 189''s (md5(pg_get_functiondef) 337a8f19)');
SELECT is(md5(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date, date)'))),
  '046dfce98f9e6714bb46a87e896e7763', 'A6: ops.primary_reconciliation body = 189''s (md5(pg_get_functiondef) 046dfce9)');
SELECT is((SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'ops' AND p.proname IN ('record_primary_refund', 'primary_reconciliation')), 2,
  'A7: one overload each');
SELECT ok(coalesce(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'))
            ~ E'begin\n(  --[^\n]*\n)*  perform ops\\.assert_role\\(array\\[''platform_admin'', ''platform_support''\\]\\);\n  perform ops\\.assert_actions_enabled\\(\\);\n', false)
          AND coalesce(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'))
            ~ E'  return kernel\\.refund_primary_order\\(p_order_id, p_amount_minor, p_reason_code, p_command_key\\);\nend;', false)
          AND coalesce((SELECT count(*) FROM regexp_matches(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')),
                         '(^|[^a-z_])(insert|update|delete)[[:space:]]', 'gi')) = 0, false),
  'A8: the record asserts role + aal2 and the pause switch FIRST, returns the kernel call, and has no insert/update/delete of its own');
SELECT ok(coalesce(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date, date)'))
            ~ E'\nbegin\n  -- the console''s reader gate: an operator role and an aal2 session \\(115\\)\n  perform ops\\.assert_reader\\(\\);\n', false),
  'A9: the reader''s first statement is ops.assert_reader()');
SELECT is(ARRAY[has_function_privilege('authenticated', 'kernel.refund_primary_order(uuid, integer, text, text)', 'EXECUTE'),
                has_function_privilege('service_role',  'kernel.refund_primary_order(uuid, integer, text, text)', 'EXECUTE')],
          ARRAY[false, true],
  'A10: kernel.refund_primary_order''s own ACL is untouched — still service_role, never authenticated (189 widens nothing)');

-- ── Section U — ops.record_primary_refund authority, effect, replay ──────────
SELECT tap.login_anon();
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-u1-anon')$q$,
  '42501', NULL, 'U1: anon is refused (no EXECUTE)');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000199'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-u2-fan')$q$,
  '42501', 'insufficient_privilege: operator role required', 'U2: a fan at aal2 is refused — operator role required');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal1');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-u3-aal1')$q$,
  'P0001', 'step_up_required: an aal2 (MFA) session is required for the operating console', 'U3: a platform_admin at aal1 is refused — step_up_required');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a01');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-u4-noaal')$q$,
  'P0001', 'step_up_unavailable: the session carries no aal claim', 'U4: a platform_admin whose session carries no aal claim is refused — step_up_unavailable');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a03'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-u5-risk')$q$,
  '42501', 'insufficient_privilege: requires one of {platform_admin,platform_support} (you are platform_risk)',
  'U5: a platform_risk operator at aal2 is refused (the kernel''s DIRECT arm is admin|support only)');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a02'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-u6-support')$q$,
  '42501', 'insufficient_privilege: platform_support cap exceeded (cumulative vs 1000)',
  'U6: platform_support at aal2 OVER the cap (2750 > refund.platform_support_max_minor 1000) is refused by the kernel''s own cap');
SELECT tap.logout();
SELECT is(ARRAY[tap._refunds259('25900000-0000-4000-8000-000000000601')::text, tap._ostatus259('25900000-0000-4000-8000-000000000301'),
                tap._state259('25900000-0000-4000-8000-000000000401')],
          ARRAY['0', 'paid', 'active'],
  'U7: after the six refusals O1 has no kernel.refund row, is still paid, and its atom is still active');
SELECT tap.login('25900000-0000-4000-8000-000000000a04');
SELECT is((SELECT (j ->> 'ticket_state', j ->> 'admissible')::text FROM (SELECT venue.validate_ticket_online(tap._atom259('25900000-0000-4000-8000-000000000401'), '25900000-0000-4000-8000-0000000000f1') j) x),
  ('active', 'true')::text, 'U8: the door (validate_ticket_online as the venue scanner) admits O1''s atom before the refund');
SELECT tap.logout();
SELECT tap._store259('ops0', tap._opsrows259()::text);
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('u9', tap._try259($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-o1-full')$q$)::text);
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', (j ->> 'voided')::int, j -> 'consumed')::text FROM (SELECT tap._fetch259('u9')::jsonb j) x),
  ('ok', 1, '[]'::jsonb)::text,
  'U9: a platform_admin at aal2 records the FULL refund of O1 (2750) — ok, one atom voided, none consumed');
SELECT is((SELECT (r.amount_minor, r.status, r.stripe_refund_ref IS NULL, r.idempotency_key, r.reason_code, r.refund_id::text = tap._fetch259('u9')::jsonb ->> 'refund_id')::text
             FROM kernel.refund r WHERE r.payment_id = '25900000-0000-4000-8000-000000000601'),
  (2750, 'pending', true, 'ck259-o1-full', 'buyer_request', true)::text,
  'U10: the kernel.refund row — 2750, pending, NO Stripe ref (the owner refunds by hand), keyed by the command key');
SELECT is(ARRAY[tap._ostatus259('25900000-0000-4000-8000-000000000301'), tap._state259('25900000-0000-4000-8000-000000000401'),
                (SELECT a.actor_identity::text FROM kernel.admin_audit a WHERE a.action = 'refund.issue' AND a.subject_id = '25900000-0000-4000-8000-000000000301')],
          ARRAY['refunded', 'voided', '25900000-0000-4000-8000-000000000a01'],
  'U11: O1 is refunded, its atom voided, and the kernel''s refund.issue audit row names the ADMIN — auth.uid() survived the definer');
SELECT tap.login('25900000-0000-4000-8000-000000000a04');
SELECT is((SELECT (j ->> 'ticket_state', j ->> 'admissible')::text FROM (SELECT venue.validate_ticket_online(tap._atom259('25900000-0000-4000-8000-000000000401'), '25900000-0000-4000-8000-0000000000f1') j) x),
  ('voided', 'false')::text, 'U12: the door now REFUSES the voided atom (admissible false)');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('u13', tap._try259($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000301', 2750, 'buyer_request', 'ck259-o1-full')$q$)::text);
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', j ->> 'refund_id' = tap._fetch259('u9')::jsonb ->> 'refund_id', tap._refunds259('25900000-0000-4000-8000-000000000601'),
                   (SELECT count(*) FROM kernel.admin_audit a WHERE a.action = 'refund.issue' AND a.subject_id = '25900000-0000-4000-8000-000000000301')::int)::text
             FROM (SELECT tap._fetch259('u13')::jsonb j) x),
  ('idempotency_replay', true, 1, 1)::text,
  'U13: the replay with the same key -> idempotency_replay with the SAME refund_id; still one refund row and one audit row');
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000302', 500, 'buyer_request', 'req:25900000-0000-4000-8000-000000000999')$q$,
  'P0001', 'invalid_input: a req: key is the dual-control delegated arm; this action records a direct refund only',
  'U14: a req: key (the kernel''s delegated dual-control arm) is refused — this action records DIRECT refunds only');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000302', 500, 'buyer_request', 'bad key')$q$,
  'P0001', 'invalid_input: command key must be 8-80 chars of [A-Za-z0-9._:-]', 'U15: a malformed command key is refused');
SELECT tap.logout();
UPDATE ops.setting SET value = 'false'::jsonb WHERE key = 'actions_enabled';
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000302', 500, 'buyer_request', 'ck259-u16-paused')$q$,
  'P0001', 'precondition_failed: console_actions_paused — a founder paused console actions (ops.setting actions_enabled = false); reads remain available',
  'U16: the console pause switch refuses it (ops.setting actions_enabled = false)');
SELECT tap.logout();
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'actions_enabled';
SELECT tap.login('25900000-0000-4000-8000-000000000a02'); SELECT tap._aal259('aal2');
SELECT tap._store259('u17', tap._try259($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000302', 500, 'buyer_request', 'ck259-o2-partial')$q$)::text);
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', (j ->> 'voided')::int, tap._ostatus259('25900000-0000-4000-8000-000000000302'), tap._state259('25900000-0000-4000-8000-000000000402'))::text
             FROM (SELECT tap._fetch259('u17')::jsonb j) x),
  ('ok', 0, 'partially_refunded', 'active')::text,
  'U17: platform_support at aal2 WITHIN the cap (500 <= 1000) records a partial refund — ok, money only (the kernel''s rules, unchanged)');
SELECT is(tap._opsrows259(), tap._fetch259('ops0')::bigint,
  'U18: ops.action + ops.audit row counts unchanged across U9-U17 — the record writes nothing of its own');

-- ── Section R — ops.primary_reconciliation ──────────────────────────────────
SELECT tap.login_anon();
SELECT throws_ok($q$SELECT ops.primary_reconciliation()$q$, '42501', NULL, 'R1: anon is refused (no EXECUTE)');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000199'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.primary_reconciliation()$q$, '42501', 'insufficient_privilege: operator role required', 'R2: a fan at aal2 is refused');
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal1');
SELECT throws_ok($q$SELECT ops.primary_reconciliation()$q$, 'P0001', 'step_up_required: an aal2 (MFA) session is required for the operating console', 'R3: an admin at aal1 is refused');
SELECT tap.logout();
-- stage s1: the fixtures as finalized (+ U's refunds on O1/O2), read by platform_support at aal2
SELECT tap.login('25900000-0000-4000-8000-000000000a02'); SELECT tap._aal259('aal2');
SELECT tap._store259('s1', tap._try259($q$SELECT ops.primary_reconciliation()$q$)::text);
SELECT tap.logout();
SELECT is(ARRAY[tap._codes259('s1', '25900000-0000-4000-8000-000000000611')::text, tap._codes259('s1', '25900000-0000-4000-8000-000000000612')::text,
                tap._codes259('s1', '25900000-0000-4000-8000-000000000613')::text, tap._codes259('s1', '25900000-0000-4000-8000-000000000614')::text,
                tap._codes259('s1', '25900000-0000-4000-8000-000000000615')::text, tap._codes259('s1', '25900000-0000-4000-8000-000000000616')::text,
                tap._codes259('s1', '25900000-0000-4000-8000-000000000601')::text, tap._codes259('s1', '25900000-0000-4000-8000-000000000602')::text],
          ARRAY['{}', '{}', '{}', '{issuance_missing}', '{}', '{}', '{}', '{}'],
  'R4: s1 (support at aal2 reads) — the finalized orders are clean, R4 (linked 20 min ago, no atom) is issuance_missing, R5 (5 min) is inside the grace, O1/O2 (kernel refunds < 24 h old) carry nothing');
SELECT is((SELECT (r ->> 'state', (r ->> 'tickets_issued')::int, (r ->> 'tickets_voided')::int, (r ->> 'tickets_live')::int, (r ->> 'kernel_refund_minor')::int,
                   (r ->> 'stripe_refund_succeeded_minor')::int, (r ->> 'payment_total_minor')::int, r ->> 'order_status')::text
             FROM (SELECT tap._row259('s1', '25900000-0000-4000-8000-000000000601') r) x),
  ('refund_awaiting_stripe', 1, 1, 0, 2750, 0, 2750, 'refunded')::text,
  'R5: O1''s row — refunded order, 1 issued / 1 voided / 0 live, kernel 2750, Stripe 0, payments.total 2750: refund_awaiting_stripe');
-- the (i)/(ii)/(iii)/(iv-over) fixtures
SELECT tap.login_service();
SELECT tap._store259('st_r1', public.record_refund_state('pi_259_11', 're_259_r1', 'succeeded', 2750, NULL, 'dashboard', 'webhook')::text);
SELECT tap._store259('st_r3a', public.record_refund_state('pi_259_13', 're_259_r3a', 'succeeded', 2500, NULL, 'dashboard', 'webhook')::text);
SELECT tap.logout();
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('rec_r2', tap._try259($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000312', 2750, 'buyer_request', 'ck259-r2-full')$q$)::text);
SELECT tap._store259('rec_r3', tap._try259($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000313', 2750, 'buyer_request', 'ck259-r3-full')$q$)::text);
SELECT tap.logout();
-- R6: a SECOND live atom on its item, written as rows exactly as the mint writes one (not producible through the
-- mint: its replay check and inventory_movement_cause_uq stop it; the custody trigger is deferred and satisfied)
INSERT INTO kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, state, credential_version, signing_key_id)
SELECT '25900000-0000-4000-8000-000000000716', t.event_session_id, t.org_id, t.ticket_type_id,
       (SELECT max(serial_no) + 1 FROM kernel.tickets WHERE event_session_id = t.event_session_id), t.current_owner_id, 'active', 0, t.signing_key_id
  FROM kernel.tickets t WHERE t.ticket_atom_id = tap._atom259('25900000-0000-4000-8000-000000000416');
INSERT INTO kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref, actor_identity, command_idempotency_key, credential_version_after, state_transition)
VALUES ('25900000-0000-4000-8000-000000000716', 1, NULL, '25900000-0000-4000-8000-000000000101', 'issue', '25900000-0000-4000-8000-000000000416',
        '00000000-0000-0000-0000-0000000000f1', 'ck259-dup:25900000-0000-4000-8000-000000000716', 0, jsonb_build_object('from', NULL, 'to', 'active', 'mint_cause', 'issue'));
SELECT is(ARRAY[(tap._fetch259('st_r1')::jsonb ->> 'recorded'), (tap._fetch259('st_r3a')::jsonb ->> 'recorded'),
                (tap._fetch259('rec_r2')::jsonb ->> 'status'), (tap._fetch259('rec_r3')::jsonb ->> 'status'), tap._state259('25900000-0000-4000-8000-000000000416')],
          ARRAY['true', 'true', 'ok', 'ok', 'active,active'],
  'R6: fixture — the webhook writer recorded R1''s 2750 and R3''s 2500 Stripe refunds; R2 and R3 refunded in full by the admin; R6''s item carries two live atoms');
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('s2', tap._try259($q$SELECT ops.primary_reconciliation()$q$)::text);
SELECT tap.logout();
SELECT is(tap._codes259('s2', '25900000-0000-4000-8000-000000000611'), ARRAY['stripe_refunded_tickets_live', 'refund_amount_mismatch'],
  'R7: (i) R1 — Stripe refunded 2750 (a Dashboard refund) while its atom is live: stripe_refunded_tickets_live, plus (iii) kernel 0 vs Stripe 2750');
SELECT is((SELECT (e ->> 'code', e ->> 'severity', e ->> 'payment_id')::text FROM jsonb_array_elements(tap._fetch259('s2')::jsonb -> 'attention') WITH ORDINALITY x(e, n) WHERE n = 1),
  ('stripe_refunded_tickets_live', 'critical', '25900000-0000-4000-8000-000000000611')::text,
  'R8: …listed FIRST in the attention list, severity critical');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(tap._fetch259('s2')::jsonb -> 'attention') e
            WHERE e ->> 'severity' = 'critical' AND e ->> 'payment_id' LIKE '25900000-%'), 1,
  'R9: exactly one critical item among the fixture payments (R1''s)');
SELECT is(ARRAY[tap._codes259('s2', '25900000-0000-4000-8000-000000000612')::text, tap._row259('s2', '25900000-0000-4000-8000-000000000612') ->> 'state'],
          ARRAY['{}', 'refund_awaiting_stripe'],
  'R10: (ii) R2 — a kernel refund less than 24 h old with nothing in Stripe is NOT flagged (refund_awaiting_stripe)');
SELECT is(tap._codes259('s2', '25900000-0000-4000-8000-000000000613'), ARRAY['refund_amount_mismatch'],
  'R11: (iii) R3 — kernel 2750 vs Stripe 2500: refund_amount_mismatch only (atom voided: no (i); < 24 h: no (ii))');
SELECT is(ARRAY[tap._codes259('s2', '25900000-0000-4000-8000-000000000614')::text, tap._codes259('s2', '25900000-0000-4000-8000-000000000615')::text,
                tap._codes259('s2', '25900000-0000-4000-8000-000000000616')::text],
          ARRAY['{issuance_missing}', '{}', '{issuance_over}'],
  'R12: (iv) R4 still issuance_missing, R5 still inside the 15-minute grace, R6 issuance_over (two live atoms for a quantity of one)');
-- (ii) after 24 h: the RPC's own row, back-dated (time is the only simulated thing)
UPDATE kernel.refund SET created_at = now() - interval '25 hours' WHERE payment_id = '25900000-0000-4000-8000-000000000612';
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('s3', tap._try259($q$SELECT ops.primary_reconciliation()$q$)::text);
SELECT tap.logout();
SELECT is(tap._codes259('s3', '25900000-0000-4000-8000-000000000612'), ARRAY['kernel_refund_without_stripe'],
  'R13: (ii) R2 — the same kernel refund once older than 24 h with no Stripe refund: kernel_refund_without_stripe');
SELECT is(tap._codes259('s3', '25900000-0000-4000-8000-000000000601'), '{}'::text[],
  'R14: …while O1''s kernel refund (still inside 24 h) is not flagged — the window is a branch, per row');
-- the fixes
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('fix_r1', tap._try259($q$SELECT ops.record_primary_refund('25900000-0000-4000-8000-000000000311', 2750, 'buyer_request', 'ck259-r1-full')$q$)::text);
SELECT tap.logout();
SELECT tap.login_service();
SELECT tap._store259('st_r2', public.record_refund_state('pi_259_12', 're_259_r2', 'succeeded', 2750, NULL, 'dashboard', 'webhook')::text);
SELECT tap._store259('st_r3b', public.record_refund_state('pi_259_13', 're_259_r3b', 'succeeded', 250, NULL, 'dashboard', 'webhook')::text);
SELECT tap._store259('st_o2', public.record_refund_state('pi_259_02', 're_259_o2', 'succeeded', 500, NULL, 'dashboard', 'webhook')::text);
SELECT tap.logout();
SELECT tap._store259('fix_r4', kernel.issue_ticket_atoms(jsonb_build_object(
         'session_id', '25900000-0000-4000-8000-0000000000f1', 'org_id', '25900000-0000-4000-8000-00000000000a',
         'ticket_type_id', '25900000-0000-4000-8000-000000000011', 'batch_id', '25900000-0000-4000-8000-000000000021',
         'owner_id', '25900000-0000-4000-8000-000000000101', 'quantity', 1, 'cause', 'issue',
         'cause_ref', '25900000-0000-4000-8000-000000000414'), 'ck259-fix-r4')::text);
SELECT tap._store259('fix_r6', kernel.void_ticket_atom('25900000-0000-4000-8000-000000000716', '25900000-0000-4000-8000-000000000916', 'ck259-fix-r6')::text);
SELECT is(ARRAY[tap._fetch259('fix_r1')::jsonb ->> 'status', tap._fetch259('st_r2')::jsonb ->> 'recorded', tap._fetch259('st_r3b')::jsonb ->> 'recorded',
                tap._fetch259('st_o2')::jsonb ->> 'recorded', tap._fetch259('fix_r4')::jsonb ->> 'status', tap._fetch259('fix_r6')::jsonb ->> 'status'],
          ARRAY['ok', 'true', 'true', 'true', 'ok', 'ok'],
  'R15: fixes — R1 refund recorded by the admin (voids its atom); Stripe refunds recorded for R2 (2750), R3 (+250) and O2 (500); R4 minted; R6''s second atom voided');
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('s4', tap._try259($q$SELECT ops.primary_reconciliation()$q$)::text);
SELECT tap.logout();
SELECT is(ARRAY[tap._codes259('s4', '25900000-0000-4000-8000-000000000611')::text, tap._row259('s4', '25900000-0000-4000-8000-000000000611') ->> 'state'],
          ARRAY['{}', 'refund_settled'],
  'R16: (i) disappears once the refund is recorded (R1''s atom voided, kernel 2750 = Stripe 2750): refund_settled');
SELECT is((SELECT (r ->> 'state', r -> 'attention', (r ->> 'tickets_voided')::int, (r ->> 'tickets_live')::int, (r ->> 'kernel_refund_minor')::int, (r ->> 'stripe_refund_succeeded_minor')::int)::text
             FROM (SELECT tap._row259('s4', '25900000-0000-4000-8000-000000000612') r) x),
  ('refund_settled', '[]'::jsonb, 1, 0, 2750, 2750)::text,
  'R17: (ii) disappears once Stripe records the refund — a Stripe-recorded refund with the atom VOIDED reads as SETTLED (no attention)');
SELECT is(tap._codes259('s4', '25900000-0000-4000-8000-000000000613'), '{}'::text[],
  'R18: (iii) disappears once Stripe''s succeeded sum (2500 + 250) equals the kernel''s 2750');
SELECT is(ARRAY[tap._codes259('s4', '25900000-0000-4000-8000-000000000614')::text, tap._codes259('s4', '25900000-0000-4000-8000-000000000616')::text],
          ARRAY['{}', '{}'],
  'R19: (iv) disappears — R4 minted (one atom), R6''s second atom voided (one live atom for a quantity of one)');
SELECT is((SELECT (r ->> 'state', r -> 'attention', r ->> 'order_status', (r ->> 'tickets_live')::int, (r ->> 'kernel_refund_minor')::int, (r ->> 'stripe_refund_succeeded_minor')::int)::text
             FROM (SELECT tap._row259('s4', '25900000-0000-4000-8000-000000000602') r) x),
  ('refund_settled', '[]'::jsonb, 'partially_refunded', 1, 500, 500)::text,
  'R20: O2 — a deliberate kernel PARTIAL (money only) with a matching Stripe partial keeps its live atom and is NOT critical');
SELECT is(ARRAY[(SELECT count(*)::int FROM jsonb_array_elements(tap._fetch259('s4')::jsonb -> 'attention') e WHERE e ->> 'payment_id' LIKE '25900000-%'),
                (SELECT count(*)::int FROM jsonb_array_elements(tap._fetch259('s4')::jsonb -> 'rows') e WHERE e ->> 'payment_id' LIKE '25900000-%')],
          ARRAY[0, 8],
  'R21: s4 — eight fixture rows (one per linked payment), no attention item left among them');
-- the window filter
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT throws_ok($q$SELECT ops.primary_reconciliation('2026-10-02', '2026-10-01')$q$, 'P0001', 'invalid_input: from must not be after to', 'R22: from after to is refused');
SELECT is((tap._try259($q$SELECT ops.primary_reconciliation('2000-01-01', '2000-01-02')$q$) ->> 'count')::int, 0, 'R23: a window with no linked payment reads zero rows');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(tap._try259($q$SELECT ops.primary_reconciliation(((now() - interval '1 day') AT TIME ZONE 'UTC')::date, (now() AT TIME ZONE 'UTC')::date)$q$) -> 'rows') e
            WHERE e ->> 'payment_id' LIKE '25900000-%'), 8,
  'R24: a closed window yesterday..today (UTC) holds the eight fixture payments');
SELECT tap.logout();
-- no writes from the reader
SELECT tap._store259('w0', tap._writes259()::text);
SELECT tap.login('25900000-0000-4000-8000-000000000a01'); SELECT tap._aal259('aal2');
SELECT tap._store259('w_call', tap._try259($q$SELECT ops.primary_reconciliation()$q$)::text);
SELECT tap.logout();
SELECT is((tap._writes259() - tap._fetch259('w0')::bigint, (tap._fetch259('w_call')::jsonb ->> 'count')::int >= 8)::text, (0, true)::text,
  'R25: the reader wrote nothing — inserted + updated + deleted tuples outside the tap schema are unchanged across a call that read the rows (pg_stat_xact_user_tables)');

SELECT * FROM finish();
ROLLBACK;
