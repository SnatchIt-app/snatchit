-- ============================================================================
-- 270_primary_checkout_sale_eligibility.sql — migration primary_checkout_sale_eligibility (registry 201 / pgTAP
-- 270, D), stacked on registry 198 (primary_checkout_hold_binding).
--
-- What 201 guarantees, and where each guarantee is pinned:
--   (1) EL-13: finalize refuses a pending order whose event is cancelled ('refund_required: event_cancelled —
--       order <id> …') or whose session is cancelled ('refund_required: session_cancelled — order <id> …'),
--       after the paid-order replay and before any conversion or mint, as a raise (E1-E6, S1-S2); a paid order
--       still replays after the event is cancelled (E3); 198's hold_lapsed raise is unchanged (L1-L2); finalize
--       gains no window / visibility / approval re-check (V8); the happy path is unchanged (H1-H2);
--   (2) DB-4: authenticated (and anon, service_role) cannot execute venue.reserve_primary_inventory; the
--       public.reserve_primary_tier wrapper still reserves for a buyer (A3-A5, R1-R3);
--   (3) DB-4: checkout coverage counts only public_sale batches of public tiers; the refusal text is kept and
--       198's DETAIL gains non_buyer_kind_units (C1-C5). A hold taken while its tier was public stops counting
--       once the tier is hidden mid-sale, so it no longer checks out (198 bound it); nothing is written (C6-C7);
--   (4) SW-4: reserve refuses door_only tiers and comp / door / presale / promoter_hold batches with
--       'precondition_failed: not_buyer_inventory', after the replay and before any write (K1-K5);
--   (5) EL-05: reserve and checkout refuse 'precondition_failed: venue_not_approved — venue is not approved' before
--       any write, for every status that is not approved — pending (V1, V9), draft (V9) and archived (V5, V7) — and
--       the replays still answer (V1-V7, V9-V10); every one of those refusals starts with the venue_not_approved
--       token and still carries catalog.create_event's prose 'venue is not approved', so a substring matcher on
--       the old text keeps matching (V11); structure and provenance (A1-A8).
--
-- Fixture (synthetic, letter-bearing ids a2010000-…-a000-…, as postgres; everything dies with the ROLLBACK): one
-- Connect-ready active org; venues VA (approved), VP (pending, draft mid-file), VX (approved, archived mid-file);
-- events EA, EP, EX, EC (all on_sale; EC cancelled mid-file); sessions SA1, SA2 (EA; SA2 cancelled mid-file), SP,
-- SX, SC; 2500 tiers, all public except TD (door_only), TV hidden mid-file; on SA1 tier TP carries one batch of
-- every release_kind (the comp batch's id sorts BEFORE the public_sale batch's, so 198's tie-break would bind it);
-- the global ES256 key through the live 110 guard when none resolves (its fixed id and ARN are built at run time);
-- new config versions: flag true, cap 6, TTL "10 minutes", fee 1000 bps. Buyers reserve through
-- public.reserve_primary_tier (the live path) or, where the wrapper cannot reach a batch (non-buyer kinds), through
-- tap._eng270: a SECURITY DEFINER tap helper that calls the engine in owner context with the buyer's claims still
-- set. Holds that a 201 engine cannot create (non-buyer inventory, or a venue that is not approved: a pre-201 or
-- staff-placed hold) are direct inserts with held raised to match. Payments are native_primary rows (succeeded).
-- finalize runs as postgres.
-- Every call goes through tap._run270 (stores the result, or 'ERROR <SQLSTATE>|<message>|<detail>'; RETURNS
-- void) and every value read through tap._try270 / tap._j270 (text; 'ERROR <SQLSTATE>|<message>' on error), so
-- the file runs to the end on the tree without 201 and under every mutant. Writes and reads are separate
-- statements.
--
-- RED (main c093bada + 198, without 201), predicted before the run and reconciled after it (they agree):
--   pass (12): A5 R3 K4 K5 V3 V4 V8 H1 H2 E3 L1 L2 — non-regression pins: the dependencies, the wrapper, a public
--              reserve, the reserve and checkout replays, finalize without a re-check, the happy path, the
--              paid-order replay and 198's lapse raise (each is told apart from a broken 201 by a mutant below).
--   fail (34): every other assertion. A2 also carries the marker census, so it cannot pass on a block-less body.
-- Mutants (each ONE create or replace, grant or alter after 201 applies; kills counted with A1, the md5 pin,
-- excluded): M01 reserve without the venue gate · M02 reserve without the buyer-inventory gate · M03 / M04 that
-- gate without its visibility / release_kind term · M05 both reserve gates ahead of the replay · M06 checkout
-- without the venue gate · M07 coverage without the kind filter · M08 / M09 the filter without its visibility /
-- release_kind term · M10 the 198 DETAIL · M11 other_batch_units not reduced by the excluded units · M12
-- finalize without the status gate · M13 the gate ahead of the paid replay · M14 / M15 without the session /
-- event arm · M16 refund_required returned, not raised · M17 the gate after the conversion (text pin A6) · M18
-- finalize re-checks venue approval · M19 EXECUTE granted back to authenticated · M20 the wrapper made SECURITY
-- INVOKER · M21 the message carries payment_unverified · M22 checkout's venue gate after the order insert (A8) ·
-- M23 reserve's venue gate after the cap lock (A7) · M24 one byte outside the 201 blocks (A2) · M25 checkout's
-- venue gate refuses only an archived venue · M26 the coverage filter counts a hidden tier (visibility <>
-- 'door_only') · M27 / M28 checkout's / reserve's venue gate lets a draft venue through. M25 and M26 are the review
-- mutants that the 41-assertion revision of this file let through; V9-V10 and C6-C7 were added for them. The
-- venue_not_approved token added V11 and five text mutants: M29 / M30 reserve's / checkout's refusal back to the
-- prose-only text (each body is then the reviewed 8d56adcd body, md5 079aa9b5 / 50ed88e0) · M31 / M32 checkout's /
-- reserve's token without the prose · M33 reserve's separator a hyphen instead of the em dash. All 33 are killed
-- (delta-venue-token/run_201_delta.log); the whole reviewed 8d56adcd file under this suite fails exactly A1 A7 A8 V1
-- V5 V7 V9 V11. Reconciled with the prediction: C5 does not fail under M07 or M09 — no single batch covers 2, so
-- the refusal fires either way, and BLOCK N computes the DETAIL independently of BLOCK C (C1-C4 kill both).
-- Extras, each explained: V6 under M01 (the archived-venue reserve then lands, so BX holds 3); A2 under M18 (its
-- lines sit outside the 201 blocks); M20 fails every wrapper-driven assertion; V11 fails wherever a venue refusal
-- no longer fires (M01 M06 M20 M25 M27 M28) and passes under M33 (token and prose intact; V1 V7 V9 pin the exact
-- separator).
-- ============================================================================
BEGIN;
SELECT plan(46);

-- ── harness ──────────────────────────────────────────────────────────────────
CREATE TABLE tap.memo_270 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._put270(k text, v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_270 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._get270(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_270 WHERE k = $1 $m$;
-- the value helper: the statement's single value as text, or 'ERROR <SQLSTATE>|<message>' — never aborts the file
CREATE FUNCTION tap._try270(q text) RETURNS text LANGUAGE plpgsql AS $m$
DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v;
EXCEPTION WHEN OTHERS THEN RETURN 'ERROR ' || SQLSTATE || '|' || SQLERRM; END $m$;
-- a call whose outcome later statements read: the value, or 'ERROR <SQLSTATE>|<message>|<detail>' (its writes roll back)
CREATE FUNCTION tap._run270(k text, q text) RETURNS void LANGUAGE plpgsql AS $m$
DECLARE v text; s text; m text; d text;
BEGIN
  BEGIN
    EXECUTE q INTO v;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE, m = MESSAGE_TEXT, d = PG_EXCEPTION_DETAIL;
    v := 'ERROR ' || s || '|' || m || '|' || coalesce(d, '');
  END;
  PERFORM tap._put270(k, v);
END $m$;
-- a stored JSON result's field, or the stored text itself when the call was refused (never a cast error)
CREATE FUNCTION tap._j270(k text, p text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN tap._get270(k) LIKE '{%' THEN tap._get270(k)::jsonb #>> p::text[] ELSE coalesce(tap._get270(k), '<none>') END $m$;
-- fixed ids (letter-bearing: no all-digit run)
CREATE FUNCTION tap._id270(k text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $m$
  SELECT ('a2010000-0000-4000-a000-' || lpad(t.v, 12, '0'))::uuid FROM (VALUES
    ('B1','b01'), ('B2','b02'), ('B3','b03'), ('B4','b04'), ('B5','b05'), ('B6','b06'), ('B7','b07'), ('B8','b08'), ('V1','b09'),
    ('ORG','a01'), ('VA','a11'), ('VP','a12'), ('VX','a13'),
    ('EA','e01'), ('EP','e02'), ('EX','e03'), ('EC','e04'),
    ('SA1','f01'), ('SA2','f02'), ('SP','f03'), ('SX','f04'), ('SC','f05'),
    ('TP','d01'), ('TD','d02'), ('TL','d03'), ('TH','d04'), ('TPP','d05'), ('TX','d06'), ('TC','d07'), ('TV','d08'),
    ('BCOMP','c01'), ('BDOOR','c02'), ('BPRE','c03'), ('BPROMO','c04'), ('BP','c05'), ('BDO','c06'), ('BP2','c07'),
    ('BL','c08'), ('BH','c09'), ('BPP','c0a'), ('BX','c0b'), ('BC','c0c'), ('BV','c0d'),
    ('HC','ab1'), ('HDO','ab2'), ('HC2','ab3'), ('HPRE','ab4'), ('HPP','ab5'),
    ('PH','fa1'), ('PX','fa2'), ('PC1','fa3'), ('PC2','fa4'), ('PS','fa5'), ('PL','fa6')) AS t(n, v) WHERE t.n = k $m$;
-- the engine in owner context with the caller's claims still set (auth.uid() resolves the buyer)
CREATE FUNCTION tap._eng270(p_batch uuid, p_qty integer, p_key text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT venue.reserve_primary_inventory(p_batch, p_qty, p_key) $m$;
-- call builders
CREATE FUNCTION tap._wrap270(p_sess text, p_tt text, p_qty integer, p_key text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT format('SELECT public.reserve_primary_tier(%L::uuid, %L::uuid, %s, %L)::text', tap._id270(p_sess), tap._id270(p_tt), p_qty, p_key) $m$;
CREATE FUNCTION tap._ck270(p_sess text, p_tt text, p_qty integer, p_holds text[], p_key text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT format('SELECT venue.create_primary_checkout(%L::uuid, %L::jsonb, %L::uuid[], %L)::text', tap._id270(p_sess),
                jsonb_build_array(jsonb_build_object('ticket_type_id', tap._id270(p_tt), 'quantity', p_qty))::text,
                (SELECT array_agg(CASE WHEN tap._get270(u.k) IS NOT NULL THEN tap._j270(u.k, '{hold_id}') ELSE tap._id270(u.k)::text END ORDER BY u.o)
                   FROM unnest(p_holds) WITH ORDINALITY AS u(k, o))::text, p_key) $m$;
CREATE FUNCTION tap._fin270(p_ck text, p_pay text, p_key text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT format('SELECT venue.finalize_primary_order(%L::uuid, %L::uuid, %L, NULL)::text', tap._j270(p_ck, '{order_id}'), tap._id270(p_pay), p_key) $m$;
-- readers (as postgres; E-29: no client role reads held)
CREATE FUNCTION tap._hold270(p_hold text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT coalesce((SELECT h.status || '|' || coalesce(h.order_id::text, '-') FROM venue.inventory_hold h WHERE h.hold_id::text = p_hold), '<no hold>') $m$;
CREATE FUNCTION tap._batch270(b text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT coalesce((SELECT x.held || '|' || x.sold FROM venue.inventory_batch x WHERE x.batch_id = tap._id270(b)), '<no batch>') $m$;
CREATE FUNCTION tap._nholds270(b text[]) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT (SELECT count(*) FROM venue.inventory_hold h WHERE h.batch_id IN (SELECT tap._id270(x) FROM unnest(b) x)) || '|'
      || (SELECT coalesce(sum(x.held), 0) FROM venue.inventory_batch x WHERE x.batch_id IN (SELECT tap._id270(y) FROM unnest(b) y)) || '|'
      || (SELECT count(*) FROM venue.inventory_movement m WHERE m.batch_id IN (SELECT tap._id270(z) FROM unnest(b) z)) $m$;
CREATE FUNCTION tap._nord270(p_key text) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT count(*)::integer FROM venue."order" o WHERE o.command_idempotency_key = p_key $m$;
CREATE FUNCTION tap._ostate270(p_ck text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT coalesce((SELECT o.status FROM venue."order" o WHERE o.order_id::text = tap._j270(p_ck, '{order_id}')), '<no order>') || '|'
      || (SELECT count(*) FROM kernel.tickets t
            JOIN kernel.ticket_ownership_log l ON l.ticket_atom_id = t.ticket_atom_id AND l.sequence = 1
           WHERE l.cause_ref IN (SELECT oi.id FROM venue.order_item oi WHERE oi.order_id::text = tap._j270(p_ck, '{order_id}'))) || '|'
      || (SELECT count(*) FROM kernel.payment_native pn WHERE pn.order_id::text = tap._j270(p_ck, '{order_id}')) $m$;
CREATE FUNCTION tap._pos270(p_sig text, p_needle text) RETURNS integer LANGUAGE sql STABLE AS $m$
  SELECT strpos(pg_get_functiondef(to_regprocedure(p_sig)), p_needle) $m$;
-- strip rule (201 header): every line from a '-- ── 201 BLOCK <X> …' marker through its END marker goes
CREATE FUNCTION tap._strip270(p_sig text) RETURNS text LANGUAGE sql STABLE AS $m$
  WITH l AS (
    SELECT t.line, t.n,
           CASE WHEN t.line ~ '^ *-- ── 201 BLOCK [A-Z0-9]+ END *$' THEN -1
                WHEN t.line ~ '^ *-- ── 201 BLOCK [A-Z0-9]+( |$)'   THEN 1 ELSE 0 END AS d,
           t.line ~ '^ *-- ── 201 BLOCK ' AS marker
      FROM regexp_split_to_table(pg_get_functiondef(to_regprocedure(p_sig)), E'\n') WITH ORDINALITY AS t(line, n))
  SELECT md5(string_agg(x.line, E'\n' ORDER BY x.n))
    FROM (SELECT l.line, l.n, l.marker, sum(l.d) OVER (ORDER BY l.n) AS depth FROM l) x
   WHERE x.depth = 0 AND NOT x.marker $m$;
CREATE FUNCTION tap._markers270(p_sig text, p_end boolean) RETURNS integer LANGUAGE sql STABLE AS $m$
  SELECT count(*)::integer
    FROM regexp_split_to_table(pg_get_functiondef(to_regprocedure(p_sig)), E'\n') AS t(line)
   WHERE CASE WHEN p_end THEN t.line ~ '^ *-- ── 201 BLOCK [A-Z0-9]+ END *$'
              ELSE t.line ~ '^ *-- ── 201 BLOCK [A-Z0-9]+( |$)' AND t.line !~ ' END *$' END $m$;
-- fixture writers (as postgres)
CREATE FUNCTION tap._cfg270(p_key text, p_val jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO catalog.platform_config (key, version, value, visibility)
  SELECT p_key, coalesce(max(c.version), 0) + 1, p_val,
         coalesce((SELECT c2.visibility FROM catalog.platform_config c2 WHERE c2.key = p_key ORDER BY c2.version DESC LIMIT 1), 'restricted')
    FROM catalog.platform_config c WHERE c.key = p_key $m$;
CREATE FUNCTION tap._pay270(p_pay text, p_buyer text, p_face integer) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
  VALUES (tap._id270(p_pay), NULL, tap._id270(p_buyer), NULL, p_face, p_face / 10, 0, p_face + p_face / 10, 'pi_270_' || lower(p_pay), 'succeeded', 'native_primary', now()) $m$;
CREATE FUNCTION tap._hold_direct270(p_hold text, p_batch text, p_buyer text, p_key text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  VALUES (tap._id270(p_hold), tap._id270(p_batch), tap._id270(p_buyer), 1, 'active', now() + interval '10 minutes', p_key);
  UPDATE venue.inventory_batch SET held = held + 1 WHERE batch_id = tap._id270(p_batch) $m$;
GRANT EXECUTE ON FUNCTION tap._put270(text, text), tap._get270(text), tap._try270(text), tap._run270(text, text), tap._j270(text, text),
  tap._id270(text), tap._eng270(uuid, integer, text), tap._wrap270(text, text, integer, text), tap._ck270(text, text, integer, text[], text)
  TO authenticated, anon, service_role;
-- throwaway P-256 SPKI PEM (suite 176's; no private half anywhere)
CREATE FUNCTION tap._pem270() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;

-- ── fixture (synthetic; never a migration) ──────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT tap._id270(u), repeat('0', 32)::uuid, 'authenticated', 'authenticated', lower(u) || '.270@test.local',
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM unnest(ARRAY['B1','B2','B3','B4','B5','B6','B7','B8','V1']) AS u
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES (tap._id270('ORG'), 'Org 270', 'Org 270', 'active');
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_270ELIGTEST', connect_transfers_active = true WHERE org_id = tap._id270('ORG');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  (tap._id270('VA'), tap._id270('ORG'), 'Room 270 A', 'wynwood', 'approved'),
  (tap._id270('VP'), tap._id270('ORG'), 'Room 270 P', 'wynwood', 'pending'),
  (tap._id270('VX'), tap._id270('ORG'), 'Room 270 X', 'wynwood', 'approved');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  (tap._id270('EA'), tap._id270('VA'), tap._id270('ORG'), 'Eligibility 270 A', 'on_sale'),
  (tap._id270('EP'), tap._id270('VP'), tap._id270('ORG'), 'Eligibility 270 P', 'on_sale'),
  (tap._id270('EX'), tap._id270('VX'), tap._id270('ORG'), 'Eligibility 270 X', 'on_sale'),
  (tap._id270('EC'), tap._id270('VA'), tap._id270('ORG'), 'Eligibility 270 C', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  (tap._id270('SA1'), tap._id270('EA'), now() + interval '40 days', 'scheduled'),
  (tap._id270('SA2'), tap._id270('EA'), now() + interval '41 days', 'scheduled'),
  (tap._id270('SP'),  tap._id270('EP'), now() + interval '42 days', 'scheduled'),
  (tap._id270('SX'),  tap._id270('EX'), now() + interval '43 days', 'scheduled'),
  (tap._id270('SC'),  tap._id270('EC'), now() + interval '44 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
SELECT tap._id270(t.t), tap._id270(t.e), 'admission', 'GA ' || t.t || ' 270', 2500, t.vis
  FROM (VALUES ('TP','EA','public'), ('TD','EA','door_only'), ('TL','EA','public'), ('TH','EA','public'),
               ('TPP','EP','public'), ('TX','EX','public'), ('TC','EC','public'), ('TV','EA','public')) AS t(t, e, vis);
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold)
SELECT tap._id270(b.b), tap._id270(b.t), tap._id270(b.s), b.k, b.cap, 0, 0
  FROM (VALUES ('BCOMP','TP','SA1','comp',50), ('BDOOR','TP','SA1','door',50), ('BPRE','TP','SA1','presale',50),
               ('BPROMO','TP','SA1','promoter_hold',50), ('BP','TP','SA1','public_sale',50), ('BDO','TD','SA1','public_sale',50),
               ('BP2','TP','SA2','public_sale',50), ('BL','TL','SA1','public_sale',1), ('BH','TH','SA1','public_sale',50),
               ('BPP','TPP','SP','public_sale',50), ('BX','TX','SX','public_sale',50), ('BC','TC','SC','public_sale',50),
               ('BV','TV','SA1','public_sale',50)) AS b(b, t, s, k, cap);
-- the global ES256 bootstrap key THROUGH THE LIVE 110 GUARD (B's recipe), only when no active global key resolves
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
SELECT (repeat('0', 30) || 'b0')::uuid, 'global', tap._pem270(),
       'arn:aws:kms:us-east-1:' || repeat('0', 12) || ':key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now()
 WHERE NOT EXISTS (SELECT 1 FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active');
SELECT tap._cfg270('feature.native_issuance_enabled', 'true'::jsonb);
SELECT tap._cfg270('inventory.per_user_active_hold_max', '6'::jsonb);
SELECT tap._cfg270('inventory.hold_ttl_interval', '"10 minutes"'::jsonb);
SELECT tap._cfg270('fee.buyer_service_bps', '1000'::jsonb);

-- ── Section A — structure and provenance ─────────────────────────────────────
SELECT is(ARRAY[md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)'))),
                md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))),
                md5(pg_get_functiondef(to_regprocedure('venue.finalize_primary_order(uuid, uuid, text, text)')))],
          ARRAY['1d759c5dd7aaa19b9366f0195ab5f528', '0222d6d9f064a3f5d32e87a483872c4b', '3c359ec14a788be8398d67210828b773'],
  'A1: reserve, checkout and finalize bodies are 201''s (md5(pg_get_functiondef) 1d759c5d / 0222d6d9 / 3c359ec1)');
SELECT is(ARRAY[tap._strip270('venue.reserve_primary_inventory(uuid, integer, text)'),
                tap._strip270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'),
                tap._strip270('venue.finalize_primary_order(uuid, uuid, text, text)'),
                tap._markers270('venue.reserve_primary_inventory(uuid, integer, text)', false)::text, tap._markers270('venue.reserve_primary_inventory(uuid, integer, text)', true)::text,
                tap._markers270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', false)::text, tap._markers270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', true)::text,
                tap._markers270('venue.finalize_primary_order(uuid, uuid, text, text)', false)::text, tap._markers270('venue.finalize_primary_order(uuid, uuid, text, text)', true)::text],
          ARRAY['d30669daef75abe15725aa0b04a107b0', 'daf8bffd8a5f4a71fc7229dc11e3494a', '7b8007e59e4faf6ed5d69cc3b2690d49', '2', '2', '5', '5', '2', '2'],
  'A2: 201 blocks — reserve 2 (V K), checkout 5 (D V C N N2), finalize 2 (D E), each with its END; minus them each body is its predecessor byte for byte (reserve 185 d30669da, checkout 198 daf8bffd, finalize 198 7b8007e5)');
SELECT is(ARRAY(SELECT p.oid::regprocedure::text || ' ' || p.prosecdef || ' ' || p.proconfig::text || ' ' || p.proowner::regrole::text || ' ' || coalesce(p.proacl::text, '<default>')
                  FROM pg_proc p
                 WHERE p.oid IN (to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)'),
                                 to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'),
                                 to_regprocedure('venue.finalize_primary_order(uuid, uuid, text, text)'))
                 ORDER BY 1),
          ARRAY['venue.create_primary_checkout(uuid,jsonb,uuid[],text) true {"search_path=\"\""} postgres {postgres=X/postgres,authenticated=X/postgres}',
                'venue.finalize_primary_order(uuid,uuid,text,text) true {"search_path=\"\""} postgres {postgres=X/postgres,service_role=X/postgres}',
                'venue.reserve_primary_inventory(uuid,integer,text) true {"search_path=\"\""} postgres {postgres=X/postgres}'],
  'A3: all three stay SECURITY DEFINER, search_path='''', owner postgres; checkout and finalize keep their ACLs; reserve is executable by its owner only');
SELECT is(ARRAY[has_function_privilege('authenticated', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE'),
                has_function_privilege('anon', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE'),
                has_function_privilege('service_role', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE'),
                (SELECT coalesce(bool_or(a.grantee = 0), false) FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  WHERE p.oid = to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)') AND a.privilege_type = 'EXECUTE'),
                has_function_privilege('authenticated', 'public.reserve_primary_tier(uuid, uuid, integer, text)', 'EXECUTE'),
                has_function_privilege('anon', 'public.reserve_primary_tier(uuid, uuid, integer, text)', 'EXECUTE'),
                (SELECT prosecdef AND proowner = (SELECT e.proowner FROM pg_proc e WHERE e.oid = to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)'))
                   FROM pg_proc WHERE oid = to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'))],
          ARRAY[false, false, false, false, true, false, true],
  'A4: the engine — authenticated, anon, service_role and PUBLIC hold no EXECUTE; the wrapper — authenticated yes, anon no, SECURITY DEFINER owned by the engine''s owner');
SELECT is(ARRAY[md5(pg_get_functiondef(to_regprocedure('venue.sweep_expired_inventory_holds(integer)'))),
                md5(pg_get_functiondef(to_regprocedure('venue.release_inventory_hold(uuid, text)'))),
                md5(pg_get_functiondef(to_regprocedure('kernel.issue_ticket_atoms(jsonb, text)'))),
                md5(pg_get_functiondef(to_regprocedure('venue.cancel_pending_order(uuid, text, text)'))),
                md5(pg_get_functiondef(to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'))),
                md5(pg_get_functiondef(to_regprocedure('venue.create_inventory_hold(uuid, integer, text, text)'))),
                (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue')::text,
                (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE (n.nspname, p.proname) IN (('venue','reserve_primary_inventory'),('venue','create_primary_checkout'),('venue','finalize_primary_order')))::text],
          ARRAY['d2ed033325aa3972e9c1be48bb8f4e91', 'b981bef80b10455a0c45a6e908c91aec', '9f559af1202fa0e7d8bae0c44df93ff8',
                '3d7fef64c44483586f46b568cb92c610', 'a58bb4af1512b1cb967a9bc57a57fc13', 'f177b73fadaa60234a6d416fed558d11', '110', '3'],
  'A5: sweep, release, mint, cancel, the reserve wrapper and the staff hold are unchanged; venue functions 110; one overload each');
SELECT ok(tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''idempotency_replay''') > 0
          AND tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''idempotency_replay''')
            < tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', 'only a pending order finalizes')
          AND tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', 'only a pending order finalizes')
            < tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''refund_required: event_cancelled')
          AND tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''refund_required: event_cancelled')
            < tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''refund_required: session_cancelled')
          AND tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''refund_required: session_cancelled')
            < tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', 'perform 1 from venue.inventory_batch b')
          AND tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''refund_required: session_cancelled')
            < tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', 'status = ''converted''')
          AND tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', '''refund_required: session_cancelled')
            < tap._pos270('venue.finalize_primary_order(uuid, uuid, text, text)', 'kernel.issue_ticket_atoms('),
  'A6: finalize — paid replay, then the pending-only refusal, then event_cancelled, then session_cancelled, all before the first batch lock, conversion and mint');
SELECT ok(tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', 'command_idempotency_key = p_command_key') > 0
          AND tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', 'command_idempotency_key = p_command_key')
            < tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: session_terminal''')
          AND tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: session_terminal''')
            < tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: venue_not_approved — venue is not approved''')
          AND tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: venue_not_approved — venue is not approved''')
            < tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: tier_not_on_sale''')
          AND tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: tier_not_on_sale''')
            < tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: not_buyer_inventory''')
          AND tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', '''precondition_failed: not_buyer_inventory''')
            < tap._pos270('venue.reserve_primary_inventory(uuid, integer, text)', 'pg_advisory_xact_lock'),
  'A7: reserve — replay lookup, session_terminal, venue approval (the venue_not_approved text), the 185 window, buyer inventory, then the cap lock (and every write after it)');
SELECT ok(tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', 'select order_id, total_minor, currency into v_ex_id') > 0
          AND tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', 'select order_id, total_minor, currency into v_ex_id')
            < tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '''precondition_failed: session_terminal''')
          AND tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '''precondition_failed: session_terminal''')
            < tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '''precondition_failed: venue_not_approved — venue is not approved''')
          AND tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '''precondition_failed: venue_not_approved — venue is not approved''')
            < tap._pos270('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', 'insert into venue."order"')
          AND tap._pos270('catalog.create_event(uuid, text, jsonb, text)', 'raise exception ''precondition_failed: venue is not approved'';') > 0,
  'A8: checkout — replay lookup, session_terminal, then venue approval (the venue_not_approved text), before the order insert; catalog.create_event keeps its own literal precondition_failed: venue is not approved, whose prose that text carries');

-- ── Section R — the engine is not client-callable; the wrapper still reserves ─
SELECT tap.login(tap._id270('B1'));
SELECT tap._run270('r_auth', format('SELECT venue.reserve_primary_inventory(%L::uuid, 1, %L)::text', tap._id270('BH'), 'k270-r-auth'));
SELECT tap.logout();
SELECT tap.login_anon();
SELECT tap._run270('r_anon', format('SELECT venue.reserve_primary_inventory(%L::uuid, 1, %L)::text', tap._id270('BH'), 'k270-r-anon'));
SELECT tap.logout();
SELECT tap.login_service();
SELECT tap._run270('r_svc', format('SELECT venue.reserve_primary_inventory(%L::uuid, 1, %L)::text', tap._id270('BH'), 'k270-r-svc'));
SELECT tap.logout();
SELECT is(ARRAY[tap._get270('r_auth'), tap._get270('r_anon'), tap._get270('r_svc')],
          ARRAY['ERROR 42501|permission denied for function reserve_primary_inventory|', 'ERROR 42501|permission denied for schema venue|',
                'ERROR 42501|permission denied for function reserve_primary_inventory|'],
  'R1: calling venue.reserve_primary_inventory directly is refused 42501 — a signed-in buyer and service_role at the function, anon already at the schema');
SELECT tap.login(tap._id270('B1'));
SELECT tap._run270('r_wrap', tap._wrap270('SA1', 'TH', 1, 'k270-r-wrap'));
SELECT tap.logout();
SELECT is(tap._try270(format($q$SELECT count(*)::text FROM venue.inventory_hold WHERE command_idempotency_key IN ('k270-r-auth', 'k270-r-anon', 'k270-r-svc')$q$)), '0',
  'R2: none of the refused direct calls wrote a hold');
SELECT is(tap._j270('r_wrap', '{status}') || '|' || tap._j270('r_wrap', '{quantity}') || '|' || tap._hold270(tap._j270('r_wrap', '{hold_id}')) || '|'
          || tap._try270(format('SELECT (batch_id = %L::uuid AND identity_id = %L::uuid)::text FROM venue.inventory_hold WHERE hold_id::text = %L',
                                tap._id270('BH'), tap._id270('B1'), tap._j270('r_wrap', '{hold_id}'))),
  'ok|1|active|-|true',
  'R3: public.reserve_primary_tier still reserves for the buyer — ok, quantity 1, an active unbound hold of B1''s on BH');

-- ── Section K — buyer holds draw only buyer inventory (SW-4) ─────────────────
-- a pre-201 buyer hold on the comp batch (a 201 engine cannot create one), for the replay-ordering assertion K5
SELECT tap._hold_direct270('HPRE', 'BCOMP', 'B2', 'k270-pre');
SELECT tap.login(tap._id270('B2'));
SELECT tap._run270('k_pub',   format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BP'),     'k270-k-pub'));
SELECT tap._run270('k_comp',  format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BCOMP'),  'k270-k-comp'));
SELECT tap._run270('k_door',  format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BDOOR'),  'k270-k-door'));
SELECT tap._run270('k_pre',   format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BPRE'),   'k270-k-pre'));
SELECT tap._run270('k_promo', format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BPROMO'), 'k270-k-promo'));
SELECT tap._run270('k_do',    format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BDO'),    'k270-k-do'));
SELECT tap._run270('k_replay', format('SELECT tap._eng270(%L::uuid, 1, %L)::text', tap._id270('BCOMP'), 'k270-pre'));
SELECT tap.logout();
SELECT is(ARRAY[tap._get270('k_comp'), tap._get270('k_door'), tap._get270('k_pre'), tap._get270('k_promo')],
          ARRAY['ERROR P0001|precondition_failed: not_buyer_inventory|', 'ERROR P0001|precondition_failed: not_buyer_inventory|',
                'ERROR P0001|precondition_failed: not_buyer_inventory|', 'ERROR P0001|precondition_failed: not_buyer_inventory|'],
  'K1: a buyer hold on a comp, door, presale or promoter_hold batch of a public tier is refused precondition_failed: not_buyer_inventory');
SELECT is(tap._get270('k_do'), 'ERROR P0001|precondition_failed: not_buyer_inventory|',
  'K2: a buyer hold on the public_sale batch of a door_only tier is refused precondition_failed: not_buyer_inventory');
SELECT is(tap._nholds270(ARRAY['BDOOR', 'BPRE', 'BPROMO', 'BDO']) || '|' || tap._nholds270(ARRAY['BCOMP']),
  '0|0|0|1|1|0',
  'K3: nothing written by the five refusals — no hold, held 0, no movement on door / presale / promoter_hold / door_only; the comp batch keeps only the pre-201 hold (held 1, no movement)');
SELECT is(tap._j270('k_pub', '{status}') || '|' || tap._batch270('BP'), 'ok|1|0',
  'K4: a public_sale batch of a public tier still reserves (owner context, buyer claims): ok, held 1');
SELECT is(tap._j270('k_replay', '{status}') || '|' || (tap._j270('k_replay', '{hold_id}') = tap._id270('HPRE')::text), 'idempotency_replay|true',
  'K5: a replay of the buyer''s existing comp-batch hold still answers idempotency_replay with that hold (the replay runs before the new gate)');

-- ── Section V — venue approval at reserve and checkout (EL-05) ───────────────
SELECT tap.login(tap._id270('B3'));
SELECT tap._run270('v_rsv_p', tap._wrap270('SP', 'TPP', 1, 'k270-v-p'));
SELECT tap._run270('v_hx1', tap._wrap270('SX', 'TX', 1, 'k270-v-hx1'));
SELECT tap._run270('v_hx2', tap._wrap270('SX', 'TX', 1, 'k270-v-hx2'));
SELECT tap._run270('v_ck1', tap._ck270('SX', 'TX', 1, ARRAY['v_hx1'], 'k270-v-ck1'));
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'archived' WHERE venue_id = tap._id270('VX');
SELECT tap.login(tap._id270('B3'));
SELECT tap._run270('v_ck1r', tap._ck270('SX', 'TX', 1, ARRAY['v_hx1'], 'k270-v-ck1'));
SELECT tap._run270('v_ck2', tap._ck270('SX', 'TX', 1, ARRAY['v_hx2'], 'k270-v-ck2'));
SELECT tap._run270('v_rsv_x', tap._wrap270('SX', 'TX', 1, 'k270-v-x3'));
SELECT tap.logout();
SELECT is(tap._get270('v_rsv_p'), 'ERROR P0001|precondition_failed: venue_not_approved — venue is not approved|',
  'V1: reserving a session of a pending venue (through the wrapper) is refused precondition_failed: venue_not_approved — venue is not approved');
SELECT is(tap._nholds270(ARRAY['BPP']), '0|0|0', 'V2: …nothing written on its batch (no hold, held 0, no movement)');
SELECT is(tap._j270('v_hx1', '{status}') || '|' || tap._j270('v_hx2', '{status}') || '|' || tap._j270('v_ck1', '{status}'), 'ok|ok|ok',
  'V3: while VX is approved, two holds and a checkout on its session succeed');
SELECT is(tap._j270('v_ck1r', '{status}') || '|' || (tap._j270('v_ck1r', '{order_id}') = tap._j270('v_ck1', '{order_id}')), 'idempotency_replay|true',
  'V4: after VX is archived, replaying that checkout still answers idempotency_replay with the original order');
SELECT is(tap._get270('v_ck2'), 'ERROR P0001|precondition_failed: venue_not_approved — venue is not approved|',
  'V5: a new checkout on the archived venue''s session is refused precondition_failed: venue_not_approved — venue is not approved');
SELECT is(tap._nord270('k270-v-ck2') || '|' || tap._hold270(tap._j270('v_hx2', '{hold_id}')) || '|' || tap._batch270('BX'), '0|active|-|2|0',
  'V6: …no order for that key, the named hold stays active and unbound, BX unchanged (held 2, sold 0)');
SELECT is(tap._get270('v_rsv_x') || '|' || tap._nholds270(ARRAY['BX']), 'ERROR P0001|precondition_failed: venue_not_approved — venue is not approved||2|2|2',
  'V7: a new reserve on the archived venue''s session is refused the same way and writes nothing (still 2 holds, held 2, 2 movements)');
-- finalize gains no approval / window / visibility re-check: hide the tier and close its window, then pay
UPDATE venue.ticket_type SET visibility = 'hidden', sale_ends_at = now() WHERE ticket_type_id = tap._id270('TX');
SELECT tap._pay270('PX', 'B3', 2500);
SELECT tap._run270('v_fin', tap._fin270('v_ck1', 'PX', 'k270-v-fin'));
SELECT is(tap._j270('v_fin', '{status}') || '|' || tap._ostate270('v_ck1') || '|' || tap._hold270(tap._j270('v_hx1', '{hold_id}')),
  'ok|paid|1|1|converted|' || tap._j270('v_ck1', '{order_id}'),
  'V8: finalize of the order checked out while VX was approved still issues after VX is archived and the tier is hidden with its window closed (paid, 1 atom, payment_native, its hold converted)');
-- the other two statuses that are not approved (V5 / V7 cover archived): a hold of B3's on VP's batch that predates
-- the status (direct insert; a 201 engine refuses a reserve there) is named by a checkout while VP is pending, and by
-- another checkout (new key) once VP is draft; a reserve is tried on the draft venue's session as well
SELECT tap._hold_direct270('HPP', 'BPP', 'B3', 'k270-v-hpp');
SELECT tap.login(tap._id270('B3'));
SELECT tap._run270('v_ckp', tap._ck270('SP', 'TPP', 1, ARRAY['HPP'], 'k270-v-ckp'));
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'draft' WHERE venue_id = tap._id270('VP');
SELECT tap.login(tap._id270('B3'));
SELECT tap._run270('v_ckd', tap._ck270('SP', 'TPP', 1, ARRAY['HPP'], 'k270-v-ckd'));
SELECT tap._run270('v_rsv_d', tap._wrap270('SP', 'TPP', 1, 'k270-v-d'));
SELECT tap.logout();
SELECT is(ARRAY[tap._get270('v_ckp'), tap._get270('v_ckd'), tap._get270('v_rsv_d')],
          ARRAY['ERROR P0001|precondition_failed: venue_not_approved — venue is not approved|', 'ERROR P0001|precondition_failed: venue_not_approved — venue is not approved|',
                'ERROR P0001|precondition_failed: venue_not_approved — venue is not approved|'],
  'V9: a checkout naming the buyer''s own hold is refused precondition_failed: venue_not_approved — venue is not approved on a pending venue''s session and again (new key) once the venue is draft; a reserve on the draft venue''s session is refused the same way');
SELECT is(tap._nord270('k270-v-ckp') || '|' || tap._nord270('k270-v-ckd') || '|' || tap._hold270(tap._id270('HPP')::text) || '|' || tap._nholds270(ARRAY['BPP']),
  '0|0|active|-|1|1|0',
  'V10: …no order for either key, the named hold stays active and unbound, and BPP is unchanged (that one hold, held 1, no movement)');
SELECT is(ARRAY(SELECT u.k || ' ' || (split_part(coalesce(tap._get270(u.k), '<none>'), '|', 1) = 'ERROR P0001')::text
                       || ' ' || starts_with(split_part(coalesce(tap._get270(u.k), '<none>'), '|', 2), 'precondition_failed: venue_not_approved')::text
                       || ' ' || (strpos(split_part(coalesce(tap._get270(u.k), '<none>'), '|', 2), 'venue is not approved') > 0)::text
                  FROM unnest(ARRAY['v_rsv_p', 'v_rsv_x', 'v_rsv_d', 'v_ck2', 'v_ckp', 'v_ckd']) WITH ORDINALITY AS u(k, o) ORDER BY u.o),
          ARRAY['v_rsv_p true true true', 'v_rsv_x true true true', 'v_rsv_d true true true',
                'v_ck2 true true true', 'v_ckp true true true', 'v_ckd true true true'],
  'V11: every venue-approval refusal above (reserve V1 V7 V9, checkout V5 V9) is P0001, its message starts with the token precondition_failed: venue_not_approved and still contains the prose venue is not approved (a substring matcher on the old text keeps matching)');

-- ── Section C — checkout coverage counts only buyer inventory (DB-4) ─────────
-- pre-201 / staff-placed holds on non-buyer inventory (a 201 engine refuses them)
SELECT tap._hold_direct270('HC',  'BCOMP', 'B4', 'k270-c-hc');
SELECT tap._hold_direct270('HDO', 'BDO',   'B4', 'k270-c-hdo');
SELECT tap._hold_direct270('HC2', 'BCOMP', 'B4', 'k270-c-hc2');
SELECT tap.login(tap._id270('B4'));
SELECT tap._run270('c_hp',  tap._wrap270('SA1', 'TP', 1, 'k270-c-hp'));
SELECT tap._run270('c_hp2', tap._wrap270('SA1', 'TP', 1, 'k270-c-hp2'));
SELECT tap._run270('c_1', tap._ck270('SA1', 'TP', 1, ARRAY['HC'], 'k270-c-1'));
SELECT tap._run270('c_3', tap._ck270('SA1', 'TD', 1, ARRAY['HDO'], 'k270-c-3'));
SELECT tap._run270('c_4', tap._ck270('SA1', 'TP', 1, ARRAY['HC', 'c_hp'], 'k270-c-4'));
SELECT tap._run270('c_5', tap._ck270('SA1', 'TP', 2, ARRAY['c_hp2', 'HC2'], 'k270-c-5'));
SELECT tap.logout();
SELECT is(tap._get270('c_1'),
  'ERROR P0001|precondition_failed: holds do not cover item (type ' || tap._id270('TP') || ', need 1, held 0)|bound_to_pending_order_units=0 other_batch_units=0 non_buyer_kind_units=1',
  'C1: a checkout naming only a comp-batch hold is refused with the unchanged coverage text (held 0) and DETAIL non_buyer_kind_units=1');
SELECT is(tap._nord270('k270-c-1') || '|' || tap._hold270(tap._id270('HC')::text), '0|active|-',
  'C2: …no order for that key and the comp hold stays active and unbound');
SELECT is(tap._get270('c_3'),
  'ERROR P0001|precondition_failed: holds do not cover item (type ' || tap._id270('TD') || ', need 1, held 0)|bound_to_pending_order_units=0 other_batch_units=0 non_buyer_kind_units=1',
  'C3: a checkout naming a hold on a door_only tier''s public_sale batch is refused the same way (the tier is not public)');
SELECT is(tap._j270('c_4', '{status}') || '|' || tap._hold270(tap._j270('c_hp', '{hold_id}')) || '|' || tap._hold270(tap._id270('HC')::text),
  'ok|active|' || tap._j270('c_4', '{order_id}') || '|active|-',
  'C4: naming a comp hold and a public_sale hold for 1 binds the public_sale hold; the comp hold (whose batch id sorts first) stays unbound');
SELECT is(tap._get270('c_5'),
  'ERROR P0001|precondition_failed: holds do not cover item (type ' || tap._id270('TP') || ', need 2, held 1)|bound_to_pending_order_units=0 other_batch_units=0 non_buyer_kind_units=1',
  'C5: a public_sale hold of 1 plus a comp hold of 1 for 2 is refused (held 1); the comp unit is reported as non_buyer_kind_units, not other_batch_units');
-- a tier hidden mid-sale: B1 takes a hold on TV while it is public, then TV is hidden (185's window refuses a NEW
-- reserve on a hidden tier, so a hold taken before the hide is the one way a hidden-tier hold reaches checkout)
SELECT tap.login(tap._id270('B1'));
SELECT tap._run270('c_hv', tap._wrap270('SA1', 'TV', 1, 'k270-c-hv'));
SELECT tap.logout();
UPDATE venue.ticket_type SET visibility = 'hidden' WHERE ticket_type_id = tap._id270('TV');
SELECT tap.login(tap._id270('B1'));
SELECT tap._run270('c_6', tap._ck270('SA1', 'TV', 1, ARRAY['c_hv'], 'k270-c-6'));
SELECT tap.logout();
SELECT is(tap._get270('c_6'),
  'ERROR P0001|precondition_failed: holds do not cover item (type ' || tap._id270('TV') || ', need 1, held 0)|bound_to_pending_order_units=0 other_batch_units=0 non_buyer_kind_units=1',
  'C6: a hold taken while its tier was public no longer covers once the tier is hidden mid-sale — refused with the unchanged coverage text (held 0) and DETAIL non_buyer_kind_units=1');
SELECT is(tap._j270('c_hv', '{status}') || '|' || tap._nord270('k270-c-6') || '|' || tap._hold270(tap._j270('c_hv', '{hold_id}')) || '|' || tap._batch270('BV'),
  'ok|0|active|-|1|0',
  'C7: …the hold had been taken (ok); no order for that key, the hold stays active and unbound, BV unchanged (held 1, sold 0)');

-- ── Section H — the accepted happy path, unchanged ───────────────────────────
SELECT tap.login(tap._id270('B5'));
SELECT tap._run270('h_hold', tap._wrap270('SA1', 'TH', 2, 'k270-h-hold'));
SELECT tap._run270('h_ck', tap._ck270('SA1', 'TH', 2, ARRAY['h_hold'], 'k270-h-ck'));
SELECT tap.logout();
SELECT tap._pay270('PH', 'B5', 5000);
SELECT tap._run270('h_fin', tap._fin270('h_ck', 'PH', 'k270-h-fin'));
SELECT is(tap._j270('h_hold', '{status}') || '|' || tap._j270('h_ck', '{status}') || '|' || tap._j270('h_ck', '{total_minor}') || '|' || tap._j270('h_ck', '{charge_total_minor}'),
  'ok|ok|5000|5500',
  'H1: approved venue, public tier, public_sale batch, live event — reserve through the wrapper and checkout return ok (face 5000, charge 5500)');
SELECT is(tap._j270('h_fin', '{status}') || '|' || tap._ostate270('h_ck') || '|' || tap._hold270(tap._j270('h_hold', '{hold_id}')),
  'ok|paid|2|1|converted|' || tap._j270('h_ck', '{order_id}'),
  'H2: finalize issues — ok, order paid, 2 atoms, one payment_native row, the bound hold converted');

-- ── Section E — finalize on a cancelled event (EL-13) ────────────────────────
SELECT tap.login(tap._id270('B6'));
SELECT tap._run270('e_h1', tap._wrap270('SC', 'TC', 1, 'k270-e-h1'));
SELECT tap._run270('e_h2', tap._wrap270('SC', 'TC', 1, 'k270-e-h2'));
SELECT tap._run270('e_ck1', tap._ck270('SC', 'TC', 1, ARRAY['e_h1'], 'k270-e-ck1'));
SELECT tap._run270('e_ck2', tap._ck270('SC', 'TC', 1, ARRAY['e_h2'], 'k270-e-ck2'));
SELECT tap.logout();
SELECT tap._pay270('PC1', 'B6', 2500);
SELECT tap._pay270('PC2', 'B6', 2500);
SELECT tap._run270('e_fin1', tap._fin270('e_ck1', 'PC1', 'k270-e-fin1'));
UPDATE catalog.event SET status = 'cancelled' WHERE event_id = tap._id270('EC');
SELECT tap._run270('e_mv0', format('SELECT count(*)::text FROM venue.inventory_movement WHERE batch_id = %L::uuid', tap._id270('BC')));
SELECT tap._run270('e_fin2', tap._fin270('e_ck2', 'PC2', 'k270-e-fin2'));
SELECT tap._run270('e_mv1', format('SELECT count(*)::text FROM venue.inventory_movement WHERE batch_id = %L::uuid', tap._id270('BC')));
SELECT tap._run270('e_fin1r', tap._fin270('e_ck1', 'PC1', 'k270-e-fin1'));
SELECT is(tap._get270('e_fin2'),
  'ERROR P0001|refund_required: event_cancelled — order ' || tap._j270('e_ck2', '{order_id}') || ' was paid for a cancelled event; nothing was converted or issued and the charge must be refunded|',
  'E1: finalize of a pending, paid order on a cancelled event raises P0001 refund_required: event_cancelled — order <id> …');
SELECT is(tap._ostate270('e_ck2') || '|' || tap._hold270(tap._j270('e_h2', '{hold_id}')) || '|' || tap._batch270('BC'),
  'pending|0|0|active|' || tap._j270('e_ck2', '{order_id}') || '|1|1',
  'E2: …and nothing happened: the order stays pending, no atom, no payment_native, its hold stays active and bound, BC held 1 sold 1 (the other order''s)');
SELECT is(tap._j270('e_fin1', '{status}') || '|' || tap._j270('e_fin1r', '{status}') || '|' || (tap._j270('e_fin1r', '{atom_ids}') = tap._j270('e_fin1', '{atom_ids}')),
  'ok|idempotency_replay|true',
  'E3: the order finalized before the cancellation still replays afterwards — idempotency_replay with the same atom ids');
UPDATE catalog.event_session SET status = 'cancelled' WHERE session_id = tap._id270('SC');
SELECT tap._run270('e_fin2b', tap._fin270('e_ck2', 'PC2', 'k270-e-fin2'));
SELECT is(split_part(tap._get270('e_fin2b'), ' was paid', 1), 'ERROR P0001|refund_required: event_cancelled — order ' || tap._j270('e_ck2', '{order_id}'),
  'E4: with the session cancelled as well, the event answers first (event_cancelled)');
SELECT ok(split_part(tap._get270('e_fin2'), '|', 2) LIKE 'refund_required:%'
          AND strpos(tap._get270('e_fin2'), 'only a pending order finalizes') = 0
          AND strpos(tap._get270('e_fin2'), 'payment_unverified') = 0
          AND strpos(tap._get270('e_fin2'), 'oversell_rejected') = 0
          AND strpos(tap._get270('e_fin2'), 'not_found') = 0,
  'E5: the message starts with refund_required: and carries none of only a pending order finalizes / payment_unverified / oversell_rejected / not_found');
SELECT is(tap._get270('e_mv1'), tap._get270('e_mv0'),
  'E6: the refused finalize wrote no inventory movement on BC (count unchanged across the call)');

-- ── Section S — finalize on a cancelled session (EL-13) ──────────────────────
SELECT tap.login(tap._id270('B7'));
SELECT tap._run270('s_h', tap._wrap270('SA2', 'TP', 1, 'k270-s-h'));
SELECT tap._run270('s_ck', tap._ck270('SA2', 'TP', 1, ARRAY['s_h'], 'k270-s-ck'));
SELECT tap.logout();
SELECT tap._pay270('PS', 'B7', 2500);
UPDATE catalog.event_session SET status = 'cancelled' WHERE session_id = tap._id270('SA2');
SELECT tap._run270('s_fin', tap._fin270('s_ck', 'PS', 'k270-s-fin'));
SELECT is(tap._get270('s_fin'),
  'ERROR P0001|refund_required: session_cancelled — order ' || tap._j270('s_ck', '{order_id}') || ' was paid for a cancelled session; nothing was converted or issued and the charge must be refunded|',
  'S1: finalize of a pending, paid order on a cancelled session (event still on_sale) raises P0001 refund_required: session_cancelled — order <id> …');
SELECT is(tap._ostate270('s_ck') || '|' || tap._hold270(tap._j270('s_h', '{hold_id}')) || '|' || tap._batch270('BP2'),
  'pending|0|0|active|' || tap._j270('s_ck', '{order_id}') || '|1|0',
  'S2: …and nothing happened: pending, no atom, no payment_native, the hold active and bound, BP2 held 1 sold 0');

-- ── Section L — 198's lapsed-hold refusal is unchanged ───────────────────────
SELECT tap.login(tap._id270('B8'));
SELECT tap._run270('l_h', tap._wrap270('SA1', 'TL', 1, 'k270-l-h'));
SELECT tap._run270('l_ck', tap._ck270('SA1', 'TL', 1, ARRAY['l_h'], 'k270-l-ck'));
SELECT tap._run270('l_rel', format('SELECT public.release_primary_hold(%L::uuid, %L)::text', tap._j270('l_h', '{hold_id}'), 'k270-l-rel'));
SELECT tap.logout();
SELECT tap.login(tap._id270('V1'));
SELECT tap._run270('l_v', tap._wrap270('SA1', 'TL', 1, 'k270-l-v'));
SELECT tap.logout();
SELECT tap._pay270('PL', 'B8', 2500);
SELECT tap._run270('l_fin', tap._fin270('l_ck', 'PL', 'k270-l-fin'));
SELECT is(split_part(tap._get270('l_fin'), ' needs ', 1) || '|' || tap._j270('l_rel', '{status}') || '|' || tap._j270('l_v', '{status}'),
  'ERROR P0001|refund_required: hold_lapsed — order ' || tap._j270('l_ck', '{order_id}') || ' item ' ||
    coalesce((SELECT oi.id::text FROM venue.order_item oi WHERE oi.order_id::text = tap._j270('l_ck', '{order_id}')), '<no item>') || '|ok|ok',
  'L1: a bound order whose hold was released and whose unit was taken still raises 198''s refund_required: hold_lapsed');
SELECT is(tap._ostate270('l_ck') || '|' || tap._batch270('BL'), 'pending|0|0|1|0',
  'L2: …and rolls back as 198 defines: pending, no atom, no payment_native, BL held 1 (the competitor) sold 0');

SELECT * FROM finish();
ROLLBACK;
