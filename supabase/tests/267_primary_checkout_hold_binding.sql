-- ============================================================================
-- 267_primary_checkout_hold_binding.sql — migration 20261102120000 (registry 198 / pgTAP 267, D).
--
-- What 198 guarantees, and where each guarantee is pinned:
--   (1) a hold backs at most one live order: venue.inventory_hold.order_id is written only by
--       venue.create_primary_checkout, for the caller's own named, active, unexpired holds in the order's
--       session that are unbound or bound to a cancelled order; each item binds to the smallest single
--       batch that covers it, every bindable named hold on that batch whole (A1-A4b, B1-B11). Each binding
--       condition has its own behavioural assertion: the caller's own (B9), active (B13), unexpired (B14), in
--       the order's session (X1, X2), unbound or bound to a cancelled order (B2, B5); every item of a
--       multi-item order binds (T1);
--   (2) checkout refuses 'precondition_failed: feature_disabled' unless the NEWEST
--       feature.native_issuance_enabled version is true, after the C16 replay (F0-F5, F6, A9);
--   (3) replay returns carry order_status and holds_live: the keys and true (H2), null with no bound hold
--       (B5r), false when the one bound hold is past expires_at but unswept (L5r), released (R1r), or when
--       one of two bound holds lapsed (T3);
--   (4) finalize converts exactly the order's own still-active bound holds, whatever their expires_at, draws
--       the unbacked part from free capacity, and otherwise raises refund_required and rolls back; the 085
--       heuristic serves only unbound orders and only unbound holds (S1-S8, E1-E3, L2-L4, R2, G1-G4, H3, X2);
--       for a two-item order it converts both items' holds (T2), and a lapse on the second item rolls back the
--       first item's conversion and mint (T4, T5);
--   (5) the sweep takes batch then hold with SKIP LOCKED, reports skipped_busy, and p_limit = 0 is a
--       write-free lapse report of PENDING orders only, with lapsed_at from the hold (L1, L1b, L5, L6, L7, R1,
--       R3, H5, H6, A10).
--
-- Fixture (synthetic, ids 26700000-…, as postgres; everything dies with the ROLLBACK): one org made
-- Connect-ready by UPDATE, one venue, one on_sale event, sessions S1 and S2 (S2 only for BXB, the second
-- session of tier TX), one public 2500 tier per batch group, the global ES256 key through the live 110 guard
-- when none resolves, and NEW config versions: flag true, cap 6, TTL "10 minutes", fee 1000 bps. Holds come
-- from venue.reserve_primary_inventory as the buyer (HL is a direct insert with held raised to match).
-- Payments are native_primary rows (amount = face, buyer_fee, total = charge, distinct pi_267_* ids,
-- succeeded). finalize runs as postgres; sweeps run under tap.login_service(); E3's direct release runs as
-- postgres with only service_role claims (the service_role role cannot execute release). "Expired, unswept" =
-- expires_at set to now() - 1 second. Buyers: U1 flag, U5 exclusivity, U6 multi-batch, U7 identity, U9 the
-- status / expiry / session conditions and the cancelled lapse, U2 settlement-2, U3 settlement-1 / lapse /
-- release, U4 legacy and happy path, U8 two-item orders, V competitor. No buyer ever holds more than 6
-- active holds. Every positive call goes through tap._call267 ({"ok": result} or {state, message, detail})
-- and every read that names order_id through tap._q267 (text or 'ERR:<sqlstate>'), so the file runs to the
-- end on the tree without 198 and under every mutant. Writes and reads are separate statements. T3-T5 lapse
-- the item finalize reaches second (order_item ids are random), so the first item's rollback is observable.
--
-- RED (the CI chain at main 7496fee3 without 198), predicted before the run and reconciled after it:
--   pass (17): A7 A8 F0 F4 B4 S2 L0 L3 L5 L4 R2 G1 H1 H3 H4 T2 F6b — non-regression of postures, pinned
--              dependencies, the happy path and behaviour 085/081 already had (L3: the 085 raise also rolls
--              back, L2 tells the two apart; L5: LIMIT 0 already swept nothing, mutant M18 tells them apart;
--              T2: 085's per-tier heuristic already finalized a two-item order, mutants R2b, R2e and M-strict
--              tell them apart; F6b: the fixture witness).
--   fail (59): every other assertion. A6 and F6 also carry a 198-only conjunct (the block-marker census;
--              a newest `false` refusing on the seq-scan plan), so neither passes on a tree without 198.
--
-- Mutants (each ONE create or replace, or grant, after 198 applies; must-fail sets per DESIGN §8.4 as amended
-- in review round 1; every listed assertion failed in every mutant, none was missing). Kills are counted with
-- A5 and A6 excluded, because those two pin bytes and block markers and so fail under every body mutant:
-- every mutant then still fails a behavioural assertion except M10, M11 and M-finlock (lock order or gate
-- placement that one session cannot observe; killed by the text pins A9 / A10, behaviour covered by the race
-- rehearsal), R2i (killed by the ACL pin A7; the ACL is the defect) and M-unmarked (the provenance control).
-- Observed extras, each explained:
--   * A5 in every mutant that replaces one of the three bodies — A5 pins all three bodies byte for byte.
--   * A6 when a mutant removes 198 markers: M1 (checkout = 188), M2 (finalize = 085), M5 (no L blocks),
--     M14 (no P blocks), M-nogate (no F block) — A6 also counts the markers.
--   * F6 under M1 and M-nogate — with no switch read, the newest `false` no longer refuses on the seq-scan plan.
--   * F3 and F5 under M-nogate — ck267-f1 is no longer refused, so it binds HF1, and ck267-f5 then finds HF1
--     bound to that pending order.
--   * L1b under M18 — the report-mode call sweeps HK first, so OK reads lapse 'expired', not 'expired_unswept'.
--   * L6 and R3 under M-strict — OE and OR stay pending with a lapsed bound hold, so they are still reported.
--   * A8 under the release control — A8 pins release's md5.
--   * T3 under R2b, only when the item that lapses is TW1 — R2b binds only the last item's holds (HW2), so the
--     replay then sees one live bound hold and answers true; when TW2 lapses it answers false and T3 passes.
--   M1 checkout = 188 · M2 finalize = 085 · M3 bound branch keeps expires_at > now() · M4 bound raise uses the
--   oversell_rejected prefix · M5 legacy branch without L1-L3 · M6 sweep = 081 · M7a refuse when bindable holds
--   span batches · M7b sum across batches · M7c first covering batch by id · M8 no rebind from a cancelled
--   order · M9 switch before the replay · M10 hold lock unordered · M11 switch after the bind (A9 only) · M12
--   cast-before-LIMIT switch read · M13 no DETAIL · M14 no replay state · M15 lapse without expired_unswept ·
--   M16 lapse without o.status = 'pending' · M16b live bound holds counted · M17 report whatever p_limit · M18
--   pass 1 without LIMIT · M-nogate no switch · M-grant order_id column granted · M-identity bind any holder's
--   hold · M-min bind only what covers · M-strict any non-active bound hold refuses · M-finlock no up-front
--   hold lock · M-unmarked one character outside the blocks · control: release without its status re-check.
--   Review round 1: R1-status / R1-expiry / R1-session drop that condition from BLOCK B's lock and bindable
--   select (B13 / B14 / X1 X2) · R2d drops the session from the bindable select only (X1 X2) · R1-cancelled
--   lapse report also lists cancelled orders (L7) · R2a1 holds_live ignores expiry (L5r) · R2a2 holds_live
--   constant (L5r R1r T3) · R2a3 holds_live as bool_or (T3) · R2b binds only the last item (T1 T2 T4 T5) · R2e
--   finalize picks an item's batch without its tier (T2) · R2g lapsed_at = now() (L1) · R2f bound conversion
--   without the status re-check (L2 L3 L4 L6 R2 R3 T4 T5) · R2h refund_required returned, not raised (L2 T4
--   T5) · R2i finalize EXECUTE granted to authenticated (A7). New must-fails for earlier mutants: M1 also B12
--   X1 L5r L7 R1r T1 T3 T4 T5 (nothing binds; no replay state; 085's oversell_rejected) · M2 and M4 also T4 ·
--   M6 and M16 also L7 · M14 also L5r R1r T3 · M-strict also T2 (the first item's conversion makes the second
--   item refuse).
--
-- Registry 201 (primary_checkout_sale_eligibility) moved these pins, nothing else, and kept every assertion:
-- EXECUTE on venue.reserve_primary_inventory is revoked from authenticated, so tap._rsv267 calls the engine in
-- owner context through tap._eng267 (a SECURITY DEFINER helper; the buyer's request.jwt.claims stay set, so
-- auth.uid() still resolves the buyer); A5 expects 201's checkout and finalize md5s (0222d6d9 / 3c359ec1); A6's
-- strips also remove the 201 blocks (byte-for-byte additions, so the 188 / 093 / 085 md5s stand; the 198 marker
-- counts do not move); A8 expects 201's reserve md5 (1d759c5d); B2 and B6 expect the coverage DETAIL with 201's
-- appended non_buyer_kind_units=0. (Before the venue_not_approved token, a line inside 201's BLOCK V of reserve
-- and checkout, A5 / A8 pinned 50ed88e0 / 079aa9b5.)
-- ============================================================================
BEGIN;
SELECT plan(76);

-- ── harness ──────────────────────────────────────────────────────────────────
CREATE TABLE tap.memo_267 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store267(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_267 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch267(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_267 WHERE k = $1 $m$;
-- every positive call: {"ok": <result>} or {"state","message","detail"} — never aborts the file
CREATE FUNCTION tap._call267(q text) RETURNS jsonb LANGUAGE plpgsql AS $m$
DECLARE r jsonb; s text; m text; d text;
BEGIN EXECUTE q INTO r; RETURN jsonb_build_object('ok', r);
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE, m = MESSAGE_TEXT, d = PG_EXCEPTION_DETAIL;
  RETURN jsonb_build_object('state', s, 'message', m, 'detail', nullif(d, '')); END $m$;
-- every read that names order_id (absent on the tree without 198): text, or 'ERR:<sqlstate>'
CREATE FUNCTION tap._q267(q text) RETURNS text LANGUAGE plpgsql AS $m$
DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLSTATE; END $m$;
-- fixed ids
CREATE FUNCTION tap._id267(k text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $m$
  SELECT ('26700000-0000-4000-8000-' || lpad(t.v, 12, '0'))::uuid FROM (VALUES
    ('ORG','a'), ('VEN','a1'), ('EVT','e1'), ('S1','f1'), ('S2','f2'),
    ('U1','101'), ('U2','102'), ('U3','103'), ('U4','104'), ('U5','105'), ('U6','106'), ('U7','107'), ('V','109'),
    ('U8','108'), ('U9','10a'),
    ('TF','11'), ('TB','12'), ('TB2','13'), ('TM','14'), ('TN','15'), ('TI','16'), ('TS','17'), ('TE','18'),
    ('TL','19'), ('TK','1a'), ('TL4','1b'), ('TR','1c'), ('TG','1d'), ('TH','1e'),
    ('TQ','1f'), ('TX','20'), ('TZ','21'), ('TT1','22'), ('TT2','23'), ('TW1','24'), ('TW2','25'),
    ('BF','201'), ('BB','202'), ('BB2','203'), ('BM1','204'), ('BM2','205'), ('BN2','206'), ('BN1','207'),
    ('BI1','208'), ('BI2','209'), ('BS','210'), ('BE','211'), ('BL','212'), ('BK','213'), ('BL4','214'),
    ('BR','215'), ('BG','216'), ('BH','217'),
    ('BQ','218'), ('BXA','219'), ('BXB','21a'), ('BZ','21b'), ('BT1','21c'), ('BT2','21d'), ('BW1','21e'), ('BW2','21f'),
    ('HL','301'), ('LG','401'), ('LGI','411'), ('LX','402'),
    ('PA','601'), ('PB','602'), ('PC','603'), ('PD','604'), ('PE','605'), ('PR','606'), ('PLG','607'),
    ('PB4','608'), ('PH','609'), ('PX','60a'), ('PT','60b'), ('PW','60c')) AS t(n, v) WHERE t.n = k $m$;
-- reserve / checkout as the logged-in buyer (holds named by memo key, in the given order); registry 201: the engine
-- runs in owner context (tap._eng267) with the buyer's claims still set
CREATE FUNCTION tap._eng267(p_batch uuid, p_qty integer, p_key text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT venue.reserve_primary_inventory(p_batch, p_qty, p_key) $m$;
CREATE FUNCTION tap._rsv267(p_key text, p_batch text, p_qty integer) RETURNS jsonb LANGUAGE sql AS $m$
  SELECT tap._call267(format('SELECT tap._eng267(%L::uuid, %s, %L)', tap._id267(p_batch), p_qty, p_key)) $m$;
CREATE FUNCTION tap._ck267(p_key text, p_tt text, p_qty integer, p_holds text[]) RETURNS jsonb LANGUAGE sql AS $m$
  SELECT tap._call267(format('SELECT venue.create_primary_checkout(%L::uuid, %L::jsonb, %L::uuid[], %L)',
           tap._id267('S1'),
           jsonb_build_array(jsonb_build_object('ticket_type_id', tap._id267(p_tt), 'quantity', p_qty))::text,
           (SELECT array_agg(tap._fetch267(u.k) ORDER BY u.o) FROM unnest(p_holds) WITH ORDINALITY AS u(k, o))::text,
           p_key)) $m$;
-- a multi-item checkout on S1: items (tier memo, quantity) in the given order, holds named by memo key
CREATE FUNCTION tap._ckm267(p_key text, p_tts text[], p_qtys integer[], p_holds text[]) RETURNS jsonb LANGUAGE sql AS $m$
  SELECT tap._call267(format('SELECT venue.create_primary_checkout(%L::uuid, %L::jsonb, %L::uuid[], %L)',
           tap._id267('S1'),
           (SELECT jsonb_agg(jsonb_build_object('ticket_type_id', tap._id267(i.tt), 'quantity', i.q) ORDER BY i.o)
              FROM unnest(p_tts, p_qtys) WITH ORDINALITY AS i(tt, q, o))::text,
           (SELECT array_agg(tap._fetch267(u.k) ORDER BY u.o) FROM unnest(p_holds) WITH ORDINALITY AS u(k, o))::text,
           p_key)) $m$;
-- readers (as postgres)
CREATE FUNCTION tap._o267(k text) RETURNS text LANGUAGE sql AS $m$ SELECT coalesce(tap._fetch267(k)::jsonb #>> '{ok,order_id}', '<no order>') $m$;
CREATE FUNCTION tap._hs267(k text) RETURNS text LANGUAGE sql AS $m$
  SELECT coalesce(tap._q267(format('SELECT h.status || ''|'' || coalesce(h.order_id::text, ''-'') FROM venue.inventory_hold h WHERE h.hold_id = %L::uuid',
                                   coalesce(tap._fetch267(k), tap._id267(k)::text))), '<no hold>') $m$;
CREATE FUNCTION tap._st267(k text) RETURNS text LANGUAGE sql AS $m$
  SELECT coalesce((SELECT h.status FROM venue.inventory_hold h WHERE h.hold_id = coalesce(tap._fetch267(k)::uuid, tap._id267(k))), '<no hold>') $m$;
CREATE FUNCTION tap._bs267(b text) RETURNS text LANGUAGE sql AS $m$
  SELECT coalesce((SELECT x.held || '|' || x.sold FROM venue.inventory_batch x WHERE x.batch_id = tap._id267(b)), '<no batch>') $m$;
CREATE FUNCTION tap._os267(p_order text) RETURNS text LANGUAGE sql AS $m$
  SELECT coalesce((SELECT o.status FROM venue."order" o WHERE o.order_id::text = p_order), '<no order>') $m$;
CREATE FUNCTION tap._n267(p_key text) RETURNS integer LANGUAGE sql AS $m$
  SELECT count(*)::integer FROM venue."order" o WHERE o.command_idempotency_key = p_key $m$;
CREATE FUNCTION tap._atoms267(p_orders text[]) RETURNS text LANGUAGE sql AS $m$
  SELECT count(*)::integer || '|' || coalesce(bool_and(t.current_owner_id = tap._id267('U2'))::text, '-')
    FROM kernel.tickets t
    JOIN kernel.ticket_ownership_log l ON l.ticket_atom_id = t.ticket_atom_id AND l.sequence = 1
   WHERE l.cause_ref IN (SELECT oi.id FROM venue.order_item oi WHERE oi.order_id::text = ANY (p_orders)) $m$;
CREATE FUNCTION tap._lapsed267(k text) RETURNS jsonb LANGUAGE sql AS $m$ SELECT tap._fetch267(k)::jsonb #> '{ok,lapsed_orders}' $m$;
-- fixture writers (as postgres)
CREATE FUNCTION tap._cfg267(p_key text, p_val jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO catalog.platform_config (key, version, value, visibility)
  SELECT p_key, coalesce(max(c.version), 0) + 1, p_val,
         coalesce((SELECT c2.visibility FROM catalog.platform_config c2 WHERE c2.key = p_key ORDER BY c2.version DESC LIMIT 1), 'restricted')
    FROM catalog.platform_config c WHERE c.key = p_key $m$;
CREATE FUNCTION tap._pay267(p_pay text, p_buyer text, p_face integer, p_fee integer) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
  VALUES (tap._id267(p_pay), NULL, tap._id267(p_buyer), NULL, p_face, p_fee, 0, p_face + p_fee, 'pi_267_' || lower(p_pay), 'succeeded', 'native_primary', now()) $m$;
CREATE FUNCTION tap._backdate267(k text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  UPDATE venue.inventory_hold SET expires_at = now() - interval '1 second' WHERE hold_id = tap._fetch267(k)::uuid $m$;
CREATE FUNCTION tap._fin267(p_ck text, p_pay text, p_key text) RETURNS jsonb LANGUAGE sql AS $m$
  SELECT tap._call267(format('SELECT venue.finalize_primary_order(%L::uuid, %L::uuid, %L, NULL)',
           coalesce(tap._fetch267(p_ck)::jsonb #>> '{ok,order_id}', tap._id267(p_ck)::text), tap._id267(p_pay), p_key)) $m$;
-- strip rule (registry 198 header): every line from a '-- ── <tag> BLOCK <X> …' marker through its END marker goes
CREATE FUNCTION tap._strip267(p_sig text, p_tags text) RETURNS text LANGUAGE sql STABLE AS $m$
  WITH l AS (
    SELECT t.line, t.n,
           CASE WHEN t.line ~ ('^ *-- ── (' || p_tags || ') BLOCK [A-Z0-9]+ END *$') THEN -1
                WHEN t.line ~ ('^ *-- ── (' || p_tags || ') BLOCK [A-Z0-9]+( |$)')   THEN 1 ELSE 0 END AS d,
           t.line ~ ('^ *-- ── (' || p_tags || ') BLOCK ') AS marker
      FROM regexp_split_to_table(pg_get_functiondef(to_regprocedure(p_sig)), E'\n') WITH ORDINALITY AS t(line, n))
  SELECT md5(string_agg(x.line, E'\n' ORDER BY x.n))
    FROM (SELECT l.line, l.n, l.marker, sum(l.d) OVER (ORDER BY l.n) AS depth FROM l) x
   WHERE x.depth = 0 AND NOT x.marker $m$;
CREATE FUNCTION tap._markers267(p_sig text, p_tag text, p_end boolean) RETURNS integer LANGUAGE sql STABLE AS $m$
  SELECT count(*)::integer
    FROM regexp_split_to_table(pg_get_functiondef(to_regprocedure(p_sig)), E'\n') AS t(line)
   WHERE CASE WHEN p_end THEN t.line ~ ('^ *-- ── ' || p_tag || ' BLOCK [A-Z0-9]+ END *$')
              ELSE t.line ~ ('^ *-- ── ' || p_tag || ' BLOCK [A-Z0-9]+( |$)') AND t.line !~ ' END *$' END $m$;
CREATE FUNCTION tap._def267(p_sig text) RETURNS text LANGUAGE sql STABLE AS $m$ SELECT pg_get_functiondef(to_regprocedure(p_sig)) $m$;
-- forced plans (SET LOCAL) for F6
CREATE FUNCTION tap._seqplan267() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'on', true);  PERFORM set_config('enable_indexscan', 'off', true);
  PERFORM set_config('enable_bitmapscan', 'off', true); PERFORM set_config('enable_indexonlyscan', 'off', true);
END $m$;
CREATE FUNCTION tap._anyplan267() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'on', true);  PERFORM set_config('enable_indexscan', 'on', true);
  PERFORM set_config('enable_bitmapscan', 'on', true); PERFORM set_config('enable_indexonlyscan', 'on', true);
END $m$;
GRANT EXECUTE ON FUNCTION tap._store267(text, text), tap._fetch267(text), tap._call267(text), tap._q267(text),
  tap._id267(text), tap._eng267(uuid, integer, text), tap._rsv267(text, text, integer), tap._ck267(text, text, integer, text[]),
  tap._ckm267(text, text[], integer[], text[]), tap._seqplan267(), tap._anyplan267() TO authenticated, service_role;
-- throwaway P-256 SPKI PEM (suite 176's; no private half anywhere)
CREATE FUNCTION tap._pem267() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;

-- ── fixture (synthetic; never a migration) ──────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT tap._id267(u), repeat('0', 32)::uuid, 'authenticated', 'authenticated', lower(u) || '.267@test.local',
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM unnest(ARRAY['U1','U2','U3','U4','U5','U6','U7','V','U8','U9']) AS u
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES (tap._id267('ORG'), 'Org 267', 'Org 267', 'active');
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_267BINDTEST', connect_transfers_active = true WHERE org_id = tap._id267('ORG');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  (tap._id267('VEN'), tap._id267('ORG'), 'Room 267', 'wynwood', 'approved');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  (tap._id267('EVT'), tap._id267('VEN'), tap._id267('ORG'), 'Binding 267', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  (tap._id267('S1'), tap._id267('EVT'), now() + interval '40 days', 'scheduled'),
  (tap._id267('S2'), tap._id267('EVT'), now() + interval '41 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
SELECT tap._id267(t), tap._id267('EVT'), 'admission', 'GA ' || t || ' 267', 2500, 'public'
  FROM unnest(ARRAY['TF','TB','TB2','TM','TN','TI','TS','TE','TL','TK','TL4','TR','TG','TH','TQ','TX','TZ','TT1','TT2','TW1','TW2']) AS t;
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold)
SELECT tap._id267(b.b), tap._id267(b.t), tap._id267('S1'), 'public_sale', b.cap, 0, 0
  FROM (VALUES ('BF','TF',50), ('BB','TB',50), ('BB2','TB2',50), ('BM1','TM',50), ('BM2','TM',50), ('BN1','TN',50), ('BN2','TN',50),
               ('BI1','TI',50), ('BI2','TI',50), ('BS','TS',4), ('BE','TE',2), ('BL','TL',2), ('BK','TK',10), ('BL4','TL4',10),
               ('BR','TR',10), ('BG','TG',2), ('BH','TH',50), ('BQ','TQ',50), ('BXA','TX',50), ('BZ','TZ',10),
               ('BT1','TT1',50), ('BT2','TT2',50), ('BW1','TW1',1), ('BW2','TW2',1)) AS b(b, t, cap);
-- tier TX also sells on the second session S2 (BXB): the only batch outside S1
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold)
VALUES (tap._id267('BXB'), tap._id267('TX'), tap._id267('S2'), 'public_sale', 50, 0, 0);
-- the global ES256 bootstrap key THROUGH THE LIVE 110 GUARD (B's recipe), only when no active global key resolves
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
SELECT (repeat('0', 30) || 'b0')::uuid, 'global', tap._pem267(),
       'arn:aws:kms:us-east-1:' || repeat('0', 12) || ':key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now()
 WHERE NOT EXISTS (SELECT 1 FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active');
SELECT tap._cfg267('feature.native_issuance_enabled', 'true'::jsonb);
SELECT tap._cfg267('inventory.per_user_active_hold_max', '6'::jsonb);
SELECT tap._cfg267('inventory.hold_ttl_interval', '"10 minutes"'::jsonb);
SELECT tap._cfg267('fee.buyer_service_bps', '1000'::jsonb);

-- ── Section A — structure and provenance ─────────────────────────────────────
SELECT is(coalesce((SELECT format_type(a.atttypid, a.atttypmod) || '|' || a.attnotnull || '|' || a.atthasdef
                      FROM pg_attribute a WHERE a.attrelid = 'venue.inventory_hold'::regclass AND a.attname = 'order_id' AND NOT a.attisdropped), '<absent>'),
  'uuid|false|false',
  'A1: venue.inventory_hold.order_id is uuid, nullable, with no default');
SELECT is(coalesce((SELECT pg_get_constraintdef(c.oid) || '|' || c.convalidated FROM pg_constraint c
                     WHERE c.conrelid = 'venue.inventory_hold'::regclass AND c.conname = 'inventory_hold_order_fk' AND c.contype = 'f'), '<absent>'),
  'FOREIGN KEY (order_id) REFERENCES venue."order"(order_id) ON DELETE RESTRICT|true',
  'A2: inventory_hold_order_fk references venue."order"(order_id) ON DELETE RESTRICT and is validated');
SELECT is(coalesce((SELECT pg_get_indexdef(i.indexrelid) FROM pg_index i WHERE i.indexrelid = to_regclass('venue.inventory_hold_order_idx')), '<absent>'),
  'CREATE INDEX inventory_hold_order_idx ON venue.inventory_hold USING btree (order_id) WHERE (order_id IS NOT NULL)',
  'A3: the partial index inventory_hold_order_idx on (order_id) WHERE order_id IS NOT NULL');
SELECT is(tap._q267($q$SELECT has_column_privilege('authenticated', 'venue.inventory_hold', 'order_id', 'SELECT') || '|'
                          || has_column_privilege('anon', 'venue.inventory_hold', 'order_id', 'SELECT') || '|'
                          || has_column_privilege('service_role', 'venue.inventory_hold', 'order_id', 'SELECT') || '|'
                          || (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM pg_attribute a
                               WHERE a.attrelid = 'venue.inventory_hold'::regclass AND a.attnum > 0 AND NOT a.attisdropped
                                 AND has_column_privilege('authenticated', a.attrelid, a.attnum, 'SELECT'))::text$q$),
  'false|false|false|{batch_id,command_idempotency_key,created_at,expires_at,hold_id,quantity,shard_no,status,updated_at}',
  'A4a: no client role can read order_id; authenticated still reads exactly its 9 hold columns');
SELECT tap.login(tap._id267('U1'));
SELECT throws_ok('SELECT order_id FROM venue.inventory_hold', '42501', 'permission denied for table inventory_hold',
  'A4b: a signed-in buyer selecting order_id is refused 42501');
SELECT tap.logout();
SELECT is(ARRAY[md5(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')),
                md5(tap._def267('venue.finalize_primary_order(uuid, uuid, text, text)')),
                md5(tap._def267('venue.sweep_expired_inventory_holds(integer)'))],
          ARRAY['0222d6d9f064a3f5d32e87a483872c4b', '3c359ec14a788be8398d67210828b773', 'd2ed033325aa3972e9c1be48bb8f4e91'],
  'A5: checkout and finalize bodies are 201''s (198''s daf8bffd / 7b8007e5 plus the 201 blocks: 0222d6d9 / 3c359ec1), the sweep 198''s (d2ed0333)');
SELECT is(ARRAY[tap._markers267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '198', false)::text,
                tap._markers267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '198', true)::text,
                tap._markers267('venue.finalize_primary_order(uuid, uuid, text, text)', '198', false)::text,
                tap._markers267('venue.finalize_primary_order(uuid, uuid, text, text)', '198', true)::text,
                tap._markers267('venue.sweep_expired_inventory_holds(integer)', '198', false)::text,
                tap._strip267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '198|201'),
                tap._strip267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', '188|198|201'),
                tap._strip267('venue.finalize_primary_order(uuid, uuid, text, text)', '198|201')],
          ARRAY['7', '7', '8', '8', '0', '77004331198b9dad2e51e1ed2ceaef35', 'a629b41216397da48f71a7c6cc4fd298', '99a391ea1e5f80e4523da3a05b1c7d3a'],
  'A6: 198 blocks — checkout 7 (D P1 P2 F P3 P4 B), finalize 8 (D K1 L1 K2 K3 L2 L3 K4), sweep none; checkout minus them (and 201''s) = 188 (77004331), minus 198, 201 and 188 = 093 (a629b412), finalize minus them (and 201''s) = 085 (99a391ea)');
SELECT is(ARRAY(SELECT p.oid::regprocedure::text || ' ' || p.prosecdef || ' ' || p.proconfig::text || ' ' || p.proowner::regrole::text || ' ' || coalesce(p.proacl::text, '<default>')
                  FROM pg_proc p
                 WHERE p.oid IN (to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'),
                                 to_regprocedure('venue.finalize_primary_order(uuid, uuid, text, text)'),
                                 to_regprocedure('venue.sweep_expired_inventory_holds(integer)'))
                 ORDER BY 1),
          ARRAY['venue.create_primary_checkout(uuid,jsonb,uuid[],text) true {"search_path=\"\""} postgres {postgres=X/postgres,authenticated=X/postgres}',
                'venue.finalize_primary_order(uuid,uuid,text,text) true {"search_path=\"\""} postgres {postgres=X/postgres,service_role=X/postgres}',
                'venue.sweep_expired_inventory_holds(integer) true {"search_path=\"\""} postgres {postgres=X/postgres,service_role=X/postgres}'],
  'A7: all three stay SECURITY DEFINER, search_path='''', owner postgres, with the exact EXECUTE ACLs (checkout: authenticated; finalize and sweep: service_role)');
SELECT is(ARRAY[(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE (n.nspname, p.proname) IN (('venue','create_primary_checkout'),('venue','finalize_primary_order'),('venue','sweep_expired_inventory_holds')))::text,
                (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue')::text,
                md5(tap._def267('venue.release_inventory_hold(uuid, text)')),
                md5(tap._def267('venue.reserve_primary_inventory(uuid, integer, text)')),
                md5(tap._def267('kernel.issue_ticket_atoms(jsonb, text)')),
                md5(tap._def267('venue.cancel_pending_order(uuid, text, text)')),
                coalesce((SELECT j.schedule || ' | ' || j.command FROM cron.job j WHERE j.jobname = 'sweep-expired-inventory-holds'), '<missing>')],
          ARRAY['3', '110', 'b981bef80b10455a0c45a6e908c91aec', '1d759c5dd7aaa19b9366f0195ab5f528', '9f559af1202fa0e7d8bae0c44df93ff8',
                '3d7fef64c44483586f46b568cb92c610', '*/2 * * * * | select venue.sweep_expired_inventory_holds();'],
  'A8: one overload each, venue functions 110, release / mint / cancel unchanged (b981 / 9f55 / 3d7f), reserve = 201''s (1d75), the sweep cron job unchanged');
SELECT ok(strpos(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), 'select order_id, total_minor, currency into v_ex_id') > 0
          AND strpos(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), 'select order_id, total_minor, currency into v_ex_id')
            < strpos(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), '''feature.native_issuance_enabled''')
          AND (SELECT count(*) FROM regexp_matches(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), 'feature\.native_issuance_enabled', 'g')) = 1
          AND strpos(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), '''feature.native_issuance_enabled''')
            < strpos(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), '''precondition_failed: no items'''),
  'A9: checkout reads the sales switch once, after the C16 replay lookup and before the first other gate (no items)');
SELECT is(ARRAY[(SELECT count(*) FROM regexp_matches(tap._def267('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), 'order by h\.hold_id\s+for update of h;', 'g'))::int,
                (SELECT count(*) FROM regexp_matches(tap._def267('venue.finalize_primary_order(uuid, uuid, text, text)'), 'where h\.order_id = p_order_id\s+order by h\.hold_id\s+for update;', 'g'))::int,
                (SELECT count(*) FROM regexp_matches(tap._def267('venue.sweep_expired_inventory_holds(integer)'), 'for update skip locked', 'g'))::int,
                (SELECT count(*) FROM regexp_matches(tap._def267('venue.sweep_expired_inventory_holds(integer)'), 'for update of h skip locked', 'g'))::int],
          ARRAY[1, 1, 2, 0],
  'A10: lock clauses — checkout locks the named holds ordered by hold_id (once); finalize locks the bound holds ordered by hold_id (once); the sweep takes two SKIP LOCKED row locks and no cursor lock');

-- ── Section F — the sales switch (U1, BF) ────────────────────────────────────
SELECT tap.login(tap._id267('U1'));
SELECT tap._store267('HF0', tap._rsv267('r267-hf0', 'BF', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HF1', tap._rsv267('r267-hf1', 'BF', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_f0', tap._ck267('ck267-f0', 'TF', 1, ARRAY['HF0'])::text);
SELECT tap.logout();
SELECT is(tap._fetch267('ck_f0')::jsonb #>> '{ok,status}', 'ok', 'F0: with the switch on, checkout naming HF0 for 1 returns ok');
SELECT tap._cfg267('feature.native_issuance_enabled', 'false'::jsonb);
SELECT tap.login(tap._id267('U1'));
SELECT tap._store267('ck_f1', tap._ck267('ck267-f1', 'TF', 1, ARRAY['HF1'])::text);
SELECT tap._store267('ck_f4', tap._ck267('ck267-f0', 'TF', 1, ARRAY['HF0'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_f1')::jsonb ->> 'state') || '|' || (tap._fetch267('ck_f1')::jsonb ->> 'message'), '<no refusal>'),
  'P0001|precondition_failed: feature_disabled',
  'F1: a newest `false` version refuses a new checkout with P0001 precondition_failed: feature_disabled');
SELECT is(tap._n267('ck267-f1'), 0, 'F2: …and no order exists for that key');
SELECT is(tap._hs267('HF1'), 'active|-', 'F3: …and HF1 is still active and unbound (nothing written)');
SELECT is(coalesce((tap._fetch267('ck_f4')::jsonb #>> '{ok,status}') || '|' || ((tap._fetch267('ck_f4')::jsonb #>> '{ok,order_id}') = tap._o267('ck_f0')), '<no replay>'),
  'idempotency_replay|true',
  'F4: replaying ck267-f0 under the same `false` still answers idempotency_replay with the original order (replay runs ahead of the switch)');
SELECT tap._cfg267('feature.native_issuance_enabled', 'true'::jsonb);
SELECT tap.login(tap._id267('U1'));
SELECT tap._store267('ck_f5', tap._ck267('ck267-f5', 'TF', 1, ARRAY['HF1'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_f5')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HF1'),
  'ok|active|' || tap._o267('ck_f5'),
  'F5: with a newer `true` on top, checkout naming HF1 returns ok and binds HF1 to that order');

-- ── Section B — exclusivity and the choice of batch ──────────────────────────
SELECT tap.login(tap._id267('U5'));
SELECT tap._store267('HB1', tap._rsv267('r267-hb1', 'BB', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_b1', tap._ck267('ck267-b1', 'TB', 2, ARRAY['HB1'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_b1')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HB1'),
  'ok|active|' || tap._o267('ck_b1'),
  'B1: U5''s checkout naming HB1 (2) for 2 returns ok and binds HB1 to O_b1');
SELECT tap.login(tap._id267('U5'));
SELECT tap._store267('ck_b2', tap._ck267('ck267-b2', 'TB', 2, ARRAY['HB1'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_b2')::jsonb ->> 'state') || ' / ' || (tap._fetch267('ck_b2')::jsonb ->> 'message') || ' / '
                   || coalesce(tap._fetch267('ck_b2')::jsonb ->> 'detail', '<no detail>'), '<no refusal>'),
  'P0001 / precondition_failed: holds do not cover item (type ' || tap._id267('TB') || ', need 2, held 0) / bound_to_pending_order_units=2 other_batch_units=0 non_buyer_kind_units=0',
  'B2: a second key naming the same HB1 is refused hold-coverage (held 0), DETAIL bound_to_pending_order_units=2 other_batch_units=0 (registry 201 appends non_buyer_kind_units=0)');
SELECT is(tap._n267('ck267-b2') || '|' || tap._hs267('HB1'), '0|active|' || tap._o267('ck_b1'),
  'B3: …no order exists for ck267-b2 and HB1 is still bound to O_b1');
SELECT tap.login(tap._id267('U5'));
SELECT tap._store267('ck_b4', tap._ck267('ck267-b1', 'TB', 2, ARRAY['HB1'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_b4')::jsonb #>> '{ok,status}') || '|' || ((tap._fetch267('ck_b4')::jsonb #>> '{ok,order_id}') = tap._o267('ck_b1')), '<no replay>'),
  'idempotency_replay|true',
  'B4: replaying ck267-b1 returns idempotency_replay with O_b1');
SELECT tap._store267('cxl_b1', tap._call267(format('SELECT venue.cancel_pending_order(%L::uuid, %L, %L)', tap._o267('ck_b1'), 'payment_failed', 'ck267-b5c'))::text);
SELECT tap.login(tap._id267('U5'));
SELECT tap._store267('ck_b5', tap._ck267('ck267-b5', 'TB', 2, ARRAY['HB1'])::text);
SELECT tap._store267('ck_b5r', tap._ck267('ck267-b1', 'TB', 2, ARRAY['HB1'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('cxl_b1')::jsonb #>> '{ok,status}', '<cancel failed>') || '|' || coalesce(tap._fetch267('ck_b5')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HB1'),
  'cancelled|ok|active|' || tap._o267('ck_b5'),
  'B5: once O_b1 is cancelled, a new key naming HB1 returns ok and rebinds HB1 to O_b5');
SELECT is(coalesce(tap._fetch267('ck_b5r')::jsonb #>> '{ok,status}', '<refused>') || '|' || coalesce(tap._fetch267('ck_b5r')::jsonb #>> '{ok,order_status}', '<absent>')
          || '|' || coalesce(jsonb_typeof(tap._fetch267('ck_b5r')::jsonb #> '{ok,holds_live}'), '<absent>'),
  'idempotency_replay|cancelled|null',
  'B5r: replaying ck267-b1 now answers order_status cancelled and holds_live JSON null (no hold is bound to O_b1)');
SELECT tap.login(tap._id267('U6'));
SELECT tap._store267('HM1', tap._rsv267('r267-hm1', 'BM1', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HM2', tap._rsv267('r267-hm2', 'BM2', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_b6', tap._ck267('ck267-b6', 'TM', 2, ARRAY['HM1', 'HM2'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_b6')::jsonb ->> 'state') || ' / ' || (tap._fetch267('ck_b6')::jsonb ->> 'message') || ' / '
                   || coalesce(tap._fetch267('ck_b6')::jsonb ->> 'detail', '<no detail>'), '<no refusal>'),
  'P0001 / precondition_failed: holds do not cover item (type ' || tap._id267('TM') || ', need 2, held 1) / bound_to_pending_order_units=0 other_batch_units=1 non_buyer_kind_units=0',
  'B6: holds of 1 on BM1 and 1 on BM2 for an item of 2 — no single batch covers: refused (held 1), DETAIL other_batch_units=1 (registry 201 appends non_buyer_kind_units=0)');
SELECT is(tap._hs267('HM1') || '|' || tap._hs267('HM2') || '|' || tap._n267('ck267-b6'), 'active|-|active|-|0',
  'B7: …HM1 and HM2 stay unbound and no order exists for ck267-b6');
SELECT tap.login(tap._id267('U6'));
SELECT tap._store267('HN1', tap._rsv267('r267-hn1', 'BN1', 2) #>> '{ok,hold_id}');
SELECT tap._store267('HN2', tap._rsv267('r267-hn2', 'BN2', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HN3', tap._rsv267('r267-hn3', 'BN2', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_b8', tap._ck267('ck267-b8', 'TN', 2, ARRAY['HN3', 'HN2', 'HN1'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_b8')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HN1') || '|' || tap._hs267('HN2') || '|' || tap._hs267('HN3'),
  'ok|active|' || tap._o267('ck_b8') || '|active|-|active|-',
  'B8: BN1 (2) and BN2 (1+2) both cover 2 — the SMALLEST covering batch BN1 is bound (HN1); BN2''s HN2 and HN3 stay unbound');
SELECT tap.login(tap._id267('U7'));
SELECT tap._store267('HU1', tap._rsv267('r267-hu1', 'BI1', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HU2', tap._rsv267('r267-hu2', 'BI2', 1) #>> '{ok,hold_id}');
SELECT tap.logout();
SELECT tap.login(tap._id267('V'));
SELECT tap._store267('HV', tap._rsv267('r267-hv', 'BI1', 1) #>> '{ok,hold_id}');
SELECT tap.logout();
SELECT tap.login(tap._id267('U7'));
SELECT tap._store267('ck_b9', tap._ck267('ck267-b9', 'TI', 2, ARRAY['HU1', 'HU2', 'HV'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_b9')::jsonb ->> 'state') || ' / ' || (tap._fetch267('ck_b9')::jsonb ->> 'message'), '<no refusal>')
          || '|' || tap._hs267('HU1') || '|' || tap._hs267('HU2') || '|' || tap._hs267('HV'),
  'P0001 / precondition_failed: holds do not cover item (type ' || tap._id267('TI') || ', need 2, held 1)|active|-|active|-|active|-',
  'B9: U7 naming V''s hold HV beside HU1 (BI1) and HU2 (BI2) for 2 is refused — another buyer''s hold never counts — and all three stay unbound');
SELECT tap.login(tap._id267('U5'));
SELECT tap._store267('HB9a', tap._rsv267('r267-hb9a', 'BB2', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HB9b', tap._rsv267('r267-hb9b', 'BB2', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HB9c', tap._rsv267('r267-hb9c', 'BB', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_b10', tap._ck267('ck267-b10', 'TB2', 1, ARRAY['HB9a', 'HB9b', 'HB9c'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_b10')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HB9a') || '|' || tap._hs267('HB9b'),
  'ok|active|' || tap._o267('ck_b10') || '|active|' || tap._o267('ck_b10'),
  'B10: an item of 1 on BB2 named with HB9a (1) and HB9b (1) binds BOTH (the whole batch''s bindable holds)');
SELECT is(tap._hs267('HB9c'), 'active|-', 'B11: HB9c (tier TB, not among the items) named in the same call stays unbound');
-- I1's status and expiry conditions (U9, BQ): a released and a backdated hold of the same tier and batch, named
-- beside a covering live hold. Each would make BQ's bindable group 2 if its condition were dropped.
SELECT tap.login(tap._id267('U9'));
SELECT tap._store267('HQr', tap._rsv267('r267-hqr', 'BQ', 1) #>> '{ok,hold_id}');
SELECT tap._store267('rel_q', tap._call267(format('SELECT public.release_primary_hold(%L::uuid, %L)', tap._fetch267('HQr'), 'ck267-relq'))::text);
SELECT tap._store267('HQe', tap._rsv267('r267-hqe', 'BQ', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HQl', tap._rsv267('r267-hql', 'BQ', 1) #>> '{ok,hold_id}');
SELECT tap.logout();
SELECT tap._backdate267('HQe');
SELECT tap.login(tap._id267('U9'));
SELECT tap._store267('ck_q', tap._ck267('ck267-q', 'TQ', 1, ARRAY['HQr', 'HQe', 'HQl'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_q')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HQl'),
  'ok|active|' || tap._o267('ck_q'),
  'B12: U9 names a released HQr, a backdated HQe and a live HQl (1 each, all on BQ) for 1 — ok, and the live HQl is bound');
SELECT is(tap._hs267('HQr'), 'released|-', 'B13: …the released HQr stays unbound (only an active hold binds)');
SELECT is(tap._hs267('HQe'), 'active|-', 'B14: …the backdated HQe stays unbound (only a hold with expires_at > now() binds)');
-- I1's session condition (U9, tier TX: BXA in S1, BXB in S2). BXB's 1 is the smaller covering batch, so it is
-- the one chosen if the session condition is dropped from the bind.
SELECT tap.login(tap._id267('U9'));
SELECT tap._store267('HXa', tap._rsv267('r267-hxa', 'BXA', 2) #>> '{ok,hold_id}');
SELECT tap._store267('HXb', tap._rsv267('r267-hxb', 'BXB', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_x', tap._ck267('ck267-x', 'TX', 1, ARRAY['HXa', 'HXb'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_x')::jsonb #>> '{ok,status}', '<refused>') || '|' || tap._hs267('HXa') || '|' || tap._hs267('HXb'),
  'ok|active|' || tap._o267('ck_x') || '|active|-',
  'X1: an S1 checkout of 1 naming HXa (2, S1) and HXb (1, S2) binds HXa; HXb stays unbound (only a hold in the order''s session binds)');
SELECT tap._pay267('PX', 'U9', 2500, 250);
SELECT tap._store267('fin_x', tap._fin267('ck_x', 'PX', 'fin267-x')::text);
SELECT is(coalesce((tap._fetch267('fin_x')::jsonb #>> '{ok,status}') || '|' || jsonb_array_length(tap._fetch267('fin_x')::jsonb #> '{ok,atom_ids}'),
                   tap._fetch267('fin_x')::jsonb ->> 'message', '<raised>')
          || '|' || tap._st267('HXa') || '|' || tap._bs267('BXA') || '|' || tap._hs267('HXb') || '|' || tap._bs267('BXB'),
  'ok|1|converted|0|1|active|-|1|0',
  'X2: finalize of that order returns ok with 1 atom: HXa converted (BXA held 0, sold 1); HXb untouched (active, unbound; BXB held 1)');

-- ── Section S — settlement-2 (U2, BS capacity 4) ─────────────────────────────
SELECT tap.login(tap._id267('U2'));
SELECT tap._store267('HA', tap._rsv267('r267-ha', 'BS', 2) #>> '{ok,hold_id}');
SELECT tap._store267('HB', tap._rsv267('r267-hb', 'BS', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_sa', tap._ck267('ck267-sa', 'TS', 2, ARRAY['HA'])::text);
SELECT tap._store267('ck_sb', tap._ck267('ck267-sb', 'TS', 2, ARRAY['HB'])::text);
SELECT tap.logout();
SELECT tap._pay267('PA', 'U2', 5000, 500);
SELECT tap._pay267('PB', 'U2', 5000, 500);
SELECT is(tap._bs267('BS') || '|' || (tap._hs267('HA') = 'active|' || tap._o267('ck_sa')) || '|' || (tap._hs267('HB') = 'active|' || tap._o267('ck_sb')),
  '4|0|true|true',
  'S1: BS held 4, sold 0; HA is bound to OA and HB to OB');
SELECT tap._store267('fin_sa', tap._fin267('ck_sa', 'PA', 'fin267-sa')::text);
SELECT is(coalesce((tap._fetch267('fin_sa')::jsonb #>> '{ok,status}') || '|' || jsonb_array_length(tap._fetch267('fin_sa')::jsonb #> '{ok,atom_ids}'), '<raised>'),
  'ok|2', 'S2: finalize(OA) returns ok with 2 atoms');
SELECT is(tap._hs267('HA') || '|' || tap._hs267('HB'), 'converted|' || tap._o267('ck_sa') || '|active|' || tap._o267('ck_sb'),
  'S3: finalize(OA) converted only HA; HB is still active and bound to OB');
SELECT is(tap._bs267('BS'), '2|2', 'S4: BS held 2, sold 2');
SELECT tap.login(tap._id267('V'));
SELECT tap._store267('rsv_s5', tap._rsv267('r267-vs', 'BS', 2)::text);
SELECT tap.logout();
SELECT ok(coalesce(tap._fetch267('rsv_s5')::jsonb ->> 'message', '') LIKE '%oversell_rejected%',
  'S5: V''s reserve of 2 on BS is refused oversell_rejected (OB''s reservation is still counted)');
SELECT tap._store267('fin_sb', tap._fin267('ck_sb', 'PB', 'fin267-sb')::text);
SELECT is(coalesce((tap._fetch267('fin_sb')::jsonb #>> '{ok,status}') || '|' || jsonb_array_length(tap._fetch267('fin_sb')::jsonb #> '{ok,atom_ids}'), '<raised>'),
  'ok|2', 'S6: finalize(OB) returns ok with 2 atoms');
SELECT is(tap._bs267('BS') || '|' || tap._st267('HB') || '|' || tap._os267(tap._o267('ck_sa')) || '|' || tap._os267(tap._o267('ck_sb')),
  '0|4|converted|paid|paid', 'S7: BS held 0, sold 4; HB converted; OA and OB paid');
SELECT is(tap._atoms267(ARRAY[tap._o267('ck_sa'), tap._o267('ck_sb')]), '4|true',
  'S8: 4 atoms exist across OA''s and OB''s items (sequence-1 ledger, cause_ref = their order items), all owned by U2');

-- ── Section E — settlement-1 / case A (U3, BE capacity 2) ────────────────────
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('HC', tap._rsv267('r267-hc', 'BE', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_e', tap._ck267('ck267-e', 'TE', 2, ARRAY['HC'])::text);
SELECT tap.logout();
SELECT tap._pay267('PC', 'U3', 5000, 500);
SELECT tap._backdate267('HC');
SELECT tap._store267('fin_e', tap._fin267('ck_e', 'PC', 'fin267-e')::text);
SELECT is(coalesce(tap._fetch267('fin_e')::jsonb #>> '{ok,status}', (tap._fetch267('fin_e')::jsonb ->> 'message')), 'ok',
  'E1: finalize(OC) after HC expired but before any sweep returns ok');
SELECT is(tap._st267('HC') || '|' || tap._bs267('BE'), 'converted|0|2', 'E2: HC converted; BE held 0, sold 2');
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT tap._store267('rel_e3', tap._call267(format('SELECT venue.release_inventory_hold(%L::uuid, %L)', tap._fetch267('HC'), 'sweep:' || tap._fetch267('HC')))::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('rel_e3')::jsonb #>> '{ok,status}') || '|' || (tap._fetch267('rel_e3')::jsonb #>> '{ok,hold_status}'), tap._fetch267('rel_e3')::jsonb ->> 'state')
          || '|' || tap._bs267('BE'),
  'noop_replay|converted|0|2', 'E3: the sweep''s release of the converted HC is a noop_replay and held stays 0 (no double decrement)');

-- ── Section L — lapse ────────────────────────────────────────────────────────
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('HD', tap._rsv267('r267-hd', 'BL', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_l', tap._ck267('ck267-l', 'TL', 2, ARRAY['HD'])::text);
SELECT tap.logout();
SELECT tap._pay267('PD', 'U3', 5000, 500);
SELECT tap._backdate267('HD');
SELECT tap.login_service();
SELECT tap._store267('sw_l0', tap._call267('SELECT venue.sweep_expired_inventory_holds(500)')::text);
SELECT tap.logout();
SELECT tap.login(tap._id267('V'));
SELECT tap._store267('rsv_vl', tap._rsv267('r267-vl', 'BL', 2)::text);
SELECT tap.logout();
SELECT is(tap._st267('HD') || '|' || tap._bs267('BL'), 'expired|2|0', 'L0: HD swept to expired; V reserved the 2 units (BL held 2, sold 0)');
SELECT tap.login_service();
SELECT tap._store267('sw_l1', tap._call267('SELECT venue.sweep_expired_inventory_holds(0)')::text);
SELECT tap.logout();
SELECT ok(coalesce(tap._lapsed267('sw_l1') @> jsonb_build_array(jsonb_build_object('order_id', tap._o267('ck_l'), 'buyer_id', tap._id267('U3'),
            'event_session_id', tap._id267('S1'), 'total_minor', 5000, 'currency', 'USD', 'lapse', 'expired')), false)
          AND coalesce((SELECT (e ->> 'lapsed_at')::timestamptz FROM jsonb_array_elements(tap._lapsed267('sw_l1')) e WHERE e ->> 'order_id' = tap._o267('ck_l'))
                       = (SELECT h.expires_at FROM venue.inventory_hold h WHERE h.hold_id = tap._fetch267('HD')::uuid), false),
  'L1: report mode lists OD (buyer U3, session S1, 5000 USD) with lapse expired and lapsed_at = HD''s expires_at');
SELECT tap._store267('fin_l', tap._fin267('ck_l', 'PD', 'fin267-l')::text);
SELECT ok(coalesce(tap._fetch267('fin_l')::jsonb ->> 'state' = 'P0001'
                   AND tap._fetch267('fin_l')::jsonb ->> 'message' ~ '^refund_required: hold_lapsed'
                   AND lower(tap._fetch267('fin_l')::jsonb ->> 'message')
                       !~ '(oversell_rejected|not_found|invalid_input|payment_unverified|only a pending order|no reservation names|identity is erased|no_active_signing_key|insufficient_privilege|permission denied)', false),
  'L2: finalize(OD) with its hold lapsed and the units taken raises P0001 refund_required: hold_lapsed, matching no finalize classifier substring');
SELECT is(tap._os267(tap._o267('ck_l')) || '|' || tap._bs267('BL') || '|' || split_part(tap._atoms267(ARRAY[tap._o267('ck_l')]), '|', 1)
          || '|' || (SELECT count(*) FROM kernel.payment_native pn WHERE pn.payment_id = tap._id267('PD')),
  'pending|2|0|0|0', 'L3: …and the whole call rolled back: OD pending, BL held 2 sold 0, no atom, no payment_native row');
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('HK', tap._rsv267('r267-hk', 'BK', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_k', tap._ck267('ck267-k', 'TK', 1, ARRAY['HK'])::text);
SELECT tap.logout();
SELECT tap._backdate267('HK');
SELECT tap.login_service();
SELECT tap._store267('sw_l1b', tap._call267('SELECT venue.sweep_expired_inventory_holds(0)')::text);
SELECT tap.logout();
SELECT ok(coalesce(tap._lapsed267('sw_l1b') @> jsonb_build_array(jsonb_build_object('order_id', tap._o267('ck_k'), 'lapse', 'expired_unswept')), false),
  'L1b: an expired but not yet swept bound hold makes its order lapsed (OK, lapse expired_unswept)');
SELECT is(tap._st267('HK') || '|' || coalesce(tap._fetch267('sw_l1b')::jsonb #>> '{ok,swept}', '<raised>'), 'active|0',
  'L5: report mode wrote nothing — HK is still active and swept is 0');
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('ck_k2', tap._ck267('ck267-k', 'TK', 1, ARRAY['HK'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_k2')::jsonb #>> '{ok,status}') || '|' || (tap._fetch267('ck_k2')::jsonb #>> '{ok,order_status}') || '|'
                   || (tap._fetch267('ck_k2')::jsonb #>> '{ok,holds_live}'), '<incomplete>'),
  'idempotency_replay|pending|false',
  'L5r: replaying ck267-k while OK''s one bound hold HK is still active but past expires_at (unswept) answers order_status pending, holds_live false');
-- a cancelled order whose hold stays bound and is then swept to expired (U9, BZ): checked by L7 after sw_l6
SELECT tap.login(tap._id267('U9'));
SELECT tap._store267('HZ', tap._rsv267('r267-hz', 'BZ', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_z', tap._ck267('ck267-z', 'TZ', 1, ARRAY['HZ'])::text);
SELECT tap.logout();
SELECT tap._store267('cxl_z', tap._call267(format('SELECT venue.cancel_pending_order(%L::uuid, %L, %L)', tap._o267('ck_z'), 'payment_failed', 'ck267-zc'))::text);
SELECT tap._backdate267('HZ');
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('HE', tap._rsv267('r267-he', 'BL4', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_l4', tap._ck267('ck267-l4', 'TL4', 2, ARRAY['HE'])::text);
SELECT tap.logout();
SELECT tap._pay267('PE', 'U3', 5000, 500);
SELECT tap._backdate267('HE');
SELECT tap.login_service();
SELECT tap._store267('sw_l4', tap._call267('SELECT venue.sweep_expired_inventory_holds(500)')::text);
SELECT tap.logout();
SELECT tap._store267('fin_l4', tap._fin267('ck_l4', 'PE', 'fin267-l4')::text);
SELECT is(coalesce(tap._fetch267('fin_l4')::jsonb #>> '{ok,status}', '<raised>') || '|' || tap._bs267('BL4'), 'ok|0|2',
  'L4: a lapsed order whose units are still free mints from free capacity (ok; BL4 held 0, sold 2)');
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
VALUES (tap._id267('LX'), tap._id267('U3'), tap._id267('S1'), tap._id267('ORG'), 'pending', 'web', 2500, 'USD', 'lx-267');
SELECT tap.login_service();
SELECT tap._store267('sw_l6', tap._call267('SELECT venue.sweep_expired_inventory_holds(0)')::text);
SELECT tap.logout();
SELECT ok(coalesce(jsonb_typeof(tap._lapsed267('sw_l6')) = 'array'
                   AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(tap._lapsed267('sw_l6')) e
                                    WHERE e ->> 'order_id' IN (tap._o267('ck_b5'), tap._o267('ck_b1'), tap._o267('ck_sa'), tap._o267('ck_sb'),
                                                               tap._o267('ck_l4'), tap._id267('LX')::text)), false),
  'L6: the report omits a live bound order (O_b5), a cancelled one (O_b1, no bound hold since B5), paid ones (OA, OB, OE) and an unbound pending order (LX)');
SELECT ok(coalesce(tap._fetch267('cxl_z')::jsonb #>> '{ok,status}' = 'cancelled'
                   AND tap._hs267('HZ') = 'expired|' || tap._o267('ck_z')
                   AND jsonb_typeof(tap._lapsed267('sw_l6')) = 'array'
                   AND NOT (tap._lapsed267('sw_l6') @> jsonb_build_array(jsonb_build_object('order_id', tap._o267('ck_z')))), false),
  'L7: a cancelled order whose hold is still bound and was swept to expired (OZ, HZ) is not reported — only pending orders lapse');

-- ── Section R — release before payment (U3, BR) ──────────────────────────────
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('HR', tap._rsv267('r267-hr', 'BR', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_r', tap._ck267('ck267-r', 'TR', 2, ARRAY['HR'])::text);
SELECT tap._store267('rel_r', tap._call267(format('SELECT public.release_primary_hold(%L::uuid, %L)', tap._fetch267('HR'), 'ck267-rel'))::text);
SELECT tap.logout();
SELECT tap._pay267('PR', 'U3', 5000, 500);
SELECT tap.login_service();
SELECT tap._store267('sw_r1', tap._call267('SELECT venue.sweep_expired_inventory_holds(0)')::text);
SELECT tap.logout();
SELECT ok(tap._st267('HR') = 'released' AND tap._bs267('BR') = '0|0'
          AND coalesce(tap._lapsed267('sw_r1') @> jsonb_build_array(jsonb_build_object('order_id', tap._o267('ck_r'), 'lapse', 'released')), false),
  'R1: the buyer released the bound HR before payment — held 0, and the report lists OR with lapse released');
SELECT tap.login(tap._id267('U3'));
SELECT tap._store267('ck_r2', tap._ck267('ck267-r', 'TR', 2, ARRAY['HR'])::text);
SELECT tap.logout();
SELECT is(coalesce((tap._fetch267('ck_r2')::jsonb #>> '{ok,status}') || '|' || (tap._fetch267('ck_r2')::jsonb #>> '{ok,order_status}') || '|'
                   || (tap._fetch267('ck_r2')::jsonb #>> '{ok,holds_live}'), '<incomplete>'),
  'idempotency_replay|pending|false',
  'R1r: replaying ck267-r after the buyer released OR''s bound hold answers order_status pending, holds_live false');
SELECT tap._store267('fin_r', tap._fin267('ck_r', 'PR', 'fin267-r')::text);
SELECT is(coalesce(tap._fetch267('fin_r')::jsonb #>> '{ok,status}', '<raised>') || '|' || split_part(tap._bs267('BR'), '|', 2), 'ok|2',
  'R2: finalize(OR) mints from the capacity the release freed (ok, sold 2)');
SELECT tap.login_service();
SELECT tap._store267('sw_r3', tap._call267('SELECT venue.sweep_expired_inventory_holds(0)')::text);
SELECT tap.logout();
SELECT ok(coalesce(jsonb_typeof(tap._lapsed267('sw_r3')) = 'array'
                   AND NOT (tap._lapsed267('sw_r3') @> jsonb_build_array(jsonb_build_object('order_id', tap._o267('ck_r')))), false),
  'R3: once paid, OR is no longer reported');

-- ── Section G — legacy isolation (U4, BG capacity 2) ─────────────────────────
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
VALUES (tap._id267('HL'), tap._id267('BG'), tap._id267('U4'), 1, 'active', now() + interval '10 minutes', 'hl-267');
UPDATE venue.inventory_batch SET held = held + 1 WHERE batch_id = tap._id267('BG');
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
VALUES (tap._id267('LG'), tap._id267('U4'), tap._id267('S1'), tap._id267('ORG'), 'pending', 'web', 2500, 'USD', 'lg-267');
INSERT INTO venue.order_item (id, order_id, ticket_type_id, quantity, unit_price_minor)
VALUES (tap._id267('LGI'), tap._id267('LG'), tap._id267('TG'), 1, 2500);
SELECT tap.login(tap._id267('U4'));
SELECT tap._store267('HB4', tap._rsv267('r267-hb4', 'BG', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_g', tap._ck267('ck267-g', 'TG', 1, ARRAY['HB4'])::text);
SELECT tap.logout();
SELECT tap._pay267('PLG', 'U4', 2500, 250);
SELECT tap._pay267('PB4', 'U4', 2500, 250);
SELECT tap._store267('fin_lg', tap._fin267('LG', 'PLG', 'fin267-lg')::text);
SELECT is(coalesce(tap._fetch267('fin_lg')::jsonb #>> '{ok,status}', '<raised>'), 'ok', 'G1: finalize of the unbound legacy order LG returns ok');
SELECT is(tap._hs267('HL') || '|' || tap._hs267('HB4') || '|' || tap._bs267('BG'), 'converted|-|active|' || tap._o267('ck_g') || '|1|1',
  'G2: the legacy branch converted only the unbound HL; HB4 stays active and bound to OB4 (BG held 1, sold 1)');
SELECT tap.login(tap._id267('V'));
SELECT tap._store267('rsv_g3', tap._rsv267('r267-vg', 'BG', 1)::text);
SELECT tap.logout();
SELECT ok(coalesce(tap._fetch267('rsv_g3')::jsonb ->> 'message', '') LIKE '%oversell_rejected%',
  'G3: V''s reserve of 1 on BG is refused oversell_rejected (OB4''s reservation is still counted)');
SELECT tap._store267('fin_b4', tap._fin267('ck_g', 'PB4', 'fin267-b4')::text);
SELECT is(coalesce(tap._fetch267('fin_b4')::jsonb #>> '{ok,status}', '<raised>') || '|' || tap._bs267('BG'), 'ok|0|2',
  'G4: finalize(OB4) converts HB4 (ok; BG held 0, sold 2)');

-- ── Section H — happy-path shapes (U4, BH) ───────────────────────────────────
SELECT tap.login(tap._id267('U4'));
SELECT tap._store267('HH', tap._rsv267('r267-hh', 'BH', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_h', tap._ck267('ck267-h', 'TH', 2, ARRAY['HH'])::text);
SELECT tap._store267('ck_h2', tap._ck267('ck267-h', 'TH', 2, ARRAY['HH'])::text);
SELECT tap.logout();
SELECT tap._pay267('PH', 'U4', 5000, 500);
SELECT is(coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch267('ck_h')::jsonb -> 'ok') AS k)::text, '<none>')
          || '|' || coalesce((tap._fetch267('ck_h')::jsonb #>> '{ok,status}') || '|' || (tap._fetch267('ck_h')::jsonb #>> '{ok,total_minor}') || '|'
          || (tap._fetch267('ck_h')::jsonb #>> '{ok,buyer_fee_minor}') || '|' || (tap._fetch267('ck_h')::jsonb #>> '{ok,charge_total_minor}'), '<refused>'),
  '{buyer_fee_minor,charge_total_minor,currency,order_id,org_id,status,total_minor}|ok|5000|500|5500',
  'H1: the ok result keeps exactly its seven keys and values (ok, 5000 face, 500 fee, 5500 charge)');
SELECT is(coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch267('ck_h2')::jsonb -> 'ok') AS k)::text, '<none>')
          || '|' || coalesce((tap._fetch267('ck_h2')::jsonb #>> '{ok,status}') || '|' || ((tap._fetch267('ck_h2')::jsonb #>> '{ok,order_id}') = tap._o267('ck_h')) || '|'
          || (tap._fetch267('ck_h2')::jsonb #>> '{ok,total_minor}') || '|' || (tap._fetch267('ck_h2')::jsonb #>> '{ok,currency}') || '|'
          || (tap._fetch267('ck_h2')::jsonb #>> '{ok,order_status}') || '|' || (tap._fetch267('ck_h2')::jsonb #>> '{ok,holds_live}'), '<incomplete>'),
  '{currency,holds_live,order_id,order_status,status,total_minor}|idempotency_replay|true|5000|USD|pending|true',
  'H2: the replay keys are exactly {status, order_id, total_minor, currency, order_status, holds_live} (pending, holds live)');
SELECT tap._store267('fin_h', tap._fin267('ck_h', 'PH', 'fin267-h')::text);
SELECT tap._store267('fin_h2', tap._fin267('ck_h', 'PH', 'fin267-h')::text);
SELECT is(coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch267('fin_h')::jsonb -> 'ok') AS k)::text, '<none>')
          || '|' || coalesce((tap._fetch267('fin_h')::jsonb #>> '{ok,status}') || '|' || jsonb_array_length(tap._fetch267('fin_h')::jsonb #> '{ok,atom_ids}') || '|'
          || (tap._fetch267('fin_h')::jsonb #>> '{ok,order_status}'), '<raised>')
          || '|' || tap._os267(tap._o267('ck_h')) || '|' || coalesce((SELECT pn.amount_minor::text FROM kernel.payment_native pn WHERE pn.payment_id = tap._id267('PH')), '<none>')
          || '|' || tap._st267('HH') || '|' || tap._bs267('BH'),
  '{atom_ids,order_status,status}|ok|2|paid|paid|5000|converted|0|2',
  'H3: finalize keeps its shape (ok, 2 atoms, paid); order paid, payment_native 5000, HH converted, BH held 0 sold 2');
SELECT is(coalesce((tap._fetch267('fin_h2')::jsonb #>> '{ok,status}') || '|'
          || ((SELECT array_agg(x ORDER BY x) FROM jsonb_array_elements_text(tap._fetch267('fin_h2')::jsonb #> '{ok,atom_ids}') x)
              = (SELECT array_agg(x ORDER BY x) FROM jsonb_array_elements_text(tap._fetch267('fin_h')::jsonb #> '{ok,atom_ids}') x)), '<raised>'),
  'idempotency_replay|true', 'H4: a redelivery returns idempotency_replay with the identical atom set');
SELECT tap.login_service();
SELECT tap._store267('sw_h5', tap._call267('SELECT venue.sweep_expired_inventory_holds(500)')::text);
SELECT tap._store267('sw_h6', tap._call267('SELECT venue.sweep_expired_inventory_holds(0)')::text);
SELECT tap.logout();
SELECT is(coalesce((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch267('sw_h5')::jsonb -> 'ok') AS k)::text, '<none>')
          || '|' || coalesce(jsonb_typeof(tap._fetch267('sw_h5')::jsonb #> '{ok,lapsed_orders}'), '<absent>')
          || '|' || coalesce(tap._fetch267('sw_h5')::jsonb #>> '{ok,skipped_busy}', '<absent>') || '|' || coalesce(tap._fetch267('sw_h5')::jsonb #>> '{ok,errors}', '<absent>'),
  '{batches_touched,errors,lapsed_orders,released_qty,skipped_busy,swept}|null|0|0',
  'H5: a cron-mode sweep returns exactly six keys; lapsed_orders is JSON null, skipped_busy 0, errors 0');
SELECT is(coalesce(jsonb_typeof(tap._fetch267('sw_h6')::jsonb #> '{ok,lapsed_orders}'), '<absent>') || '|' || coalesce(tap._fetch267('sw_h6')::jsonb #>> '{ok,swept}', '<absent>'),
  'array|0', 'H6: report mode returns lapsed_orders as an array and swept 0');

-- ── Section T — two-item orders (U8) ─────────────────────────────────────────
SELECT tap.login(tap._id267('U8'));
SELECT tap._store267('HT1', tap._rsv267('r267-ht1', 'BT1', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HT2', tap._rsv267('r267-ht2', 'BT2', 2) #>> '{ok,hold_id}');
SELECT tap._store267('ck_t', tap._ckm267('ck267-t', ARRAY['TT1', 'TT2'], ARRAY[1, 2], ARRAY['HT1', 'HT2'])::text);
SELECT tap.logout();
SELECT tap._pay267('PT', 'U8', 7500, 750);
SELECT is(coalesce((tap._fetch267('ck_t')::jsonb #>> '{ok,status}') || '|' || (tap._fetch267('ck_t')::jsonb #>> '{ok,total_minor}') || '|'
                   || (tap._fetch267('ck_t')::jsonb #>> '{ok,charge_total_minor}'), '<refused>')
          || '|' || tap._hs267('HT1') || '|' || tap._hs267('HT2'),
  'ok|7500|8250|active|' || tap._o267('ck_t') || '|active|' || tap._o267('ck_t'),
  'T1: a two-item checkout (1 x TT1 naming HT1 on BT1, 2 x TT2 naming HT2 on BT2) returns ok (7500 face, 8250 charge) and binds BOTH holds to the order');
SELECT tap._store267('fin_t', tap._fin267('ck_t', 'PT', 'fin267-t')::text);
SELECT is(coalesce((tap._fetch267('fin_t')::jsonb #>> '{ok,status}') || '|' || jsonb_array_length(tap._fetch267('fin_t')::jsonb #> '{ok,atom_ids}'),
                   tap._fetch267('fin_t')::jsonb ->> 'message', '<raised>')
          || '|' || tap._st267('HT1') || '|' || tap._st267('HT2') || '|' || tap._bs267('BT1') || '|' || tap._bs267('BT2') || '|' || tap._os267(tap._o267('ck_t')),
  'ok|3|converted|converted|0|1|0|2|paid',
  'T2: finalize returns ok with 3 atoms; both holds converted; BT1 held 0 sold 1, BT2 held 0 sold 2; the order paid');
-- BW1 and BW2 hold 1 each. finalize walks order items by order_item id (random): the item it reaches SECOND
-- lapses, so the first item is converted and minted before the refusal and the whole-call rollback is visible.
SELECT tap.login(tap._id267('U8'));
SELECT tap._store267('HW1', tap._rsv267('r267-hw1', 'BW1', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HW2', tap._rsv267('r267-hw2', 'BW2', 1) #>> '{ok,hold_id}');
SELECT tap._store267('ck_w', tap._ckm267('ck267-w', ARRAY['TW1', 'TW2'], ARRAY[1, 1], ARRAY['HW1', 'HW2'])::text);
SELECT tap.logout();
SELECT tap._store267('w_late', (SELECT CASE WHEN oi.ticket_type_id = tap._id267('TW1') THEN '1' ELSE '2' END
                                  FROM venue.order_item oi WHERE oi.order_id::text = tap._o267('ck_w') ORDER BY oi.id DESC LIMIT 1));
SELECT tap._store267('w_early', CASE tap._fetch267('w_late') WHEN '1' THEN '2' ELSE '1' END);
SELECT tap._backdate267('HW' || tap._fetch267('w_late'));
SELECT tap.login_service();
SELECT tap._store267('sw_w', tap._call267('SELECT venue.sweep_expired_inventory_holds(500)')::text);
SELECT tap.logout();
SELECT tap.login(tap._id267('V'));
SELECT tap._store267('rsv_vw', tap._rsv267('r267-vw', 'BW' || tap._fetch267('w_late'), 1)::text);
SELECT tap.logout();
SELECT tap.login(tap._id267('U8'));
SELECT tap._store267('ck_w2', tap._ckm267('ck267-w', ARRAY['TW1', 'TW2'], ARRAY[1, 1], ARRAY['HW1', 'HW2'])::text);
SELECT tap.logout();
SELECT tap._pay267('PW', 'U8', 5000, 500);
SELECT is(coalesce((tap._fetch267('ck_w2')::jsonb #>> '{ok,status}') || '|' || (tap._fetch267('ck_w2')::jsonb #>> '{ok,order_status}') || '|'
                   || (tap._fetch267('ck_w2')::jsonb #>> '{ok,holds_live}'), '<incomplete>'),
  'idempotency_replay|pending|false',
  'T3: replaying ck267-w with one bound hold swept to expired and the other still live answers holds_live false (every bound hold must be live)');
SELECT tap._store267('fin_w', tap._fin267('ck_w', 'PW', 'fin267-w')::text);
SELECT ok(coalesce(tap._fetch267('fin_w')::jsonb ->> 'state' = 'P0001'
                   AND tap._fetch267('fin_w')::jsonb ->> 'message' ~ '^refund_required: hold_lapsed', false),
  'T4: finalize of the two-item order whose second item''s bound hold lapsed (and V then took that batch''s unit) raises P0001 refund_required: hold_lapsed');
SELECT is(tap._hs267('HW' || tap._fetch267('w_early')) || '|' || tap._bs267('BW' || tap._fetch267('w_early')) || '|'
          || tap._hs267('HW' || tap._fetch267('w_late')) || '|' || tap._bs267('BW' || tap._fetch267('w_late')) || '|'
          || tap._os267(tap._o267('ck_w')) || '|' || split_part(tap._atoms267(ARRAY[tap._o267('ck_w')]), '|', 1) || '|'
          || (SELECT count(*) FROM kernel.payment_native pn WHERE pn.payment_id = tap._id267('PW')),
  'active|' || tap._o267('ck_w') || '|1|0|expired|' || tap._o267('ck_w') || '|1|0|pending|0|0',
  'T5: …and the whole call rolled back: the first item''s hold is still active and bound (its batch held 1, sold 0), the lapsed hold expired, the order pending, no atom, no payment_native row');

-- ── Section F6 — plan independence of the switch read (LAST: a bad version stays in the history) ──
SELECT tap.login(tap._id267('U1'));
SELECT tap._store267('HF6', tap._rsv267('r267-hf6', 'BF', 1) #>> '{ok,hold_id}');
SELECT tap._store267('HF7', tap._rsv267('r267-hf7', 'BF', 1) #>> '{ok,hold_id}');
SELECT tap.logout();
SELECT tap._cfg267('feature.native_issuance_enabled', '"yes please"'::jsonb);
SELECT tap._cfg267('feature.native_issuance_enabled', 'true'::jsonb);
SELECT tap._seqplan267();
DISCARD PLANS;
SELECT tap.login(tap._id267('U1'));
SELECT tap._store267('ck_f6', tap._ck267('ck267-f6', 'TF', 1, ARRAY['HF6'])::text);
SELECT tap.logout();
SELECT tap._cfg267('feature.native_issuance_enabled', 'false'::jsonb);
DISCARD PLANS;
SELECT tap.login(tap._id267('U1'));
SELECT tap._store267('ck_f6x', tap._ck267('ck267-f6x', 'TF', 1, ARRAY['HF7'])::text);
SELECT tap.logout();
SELECT is(coalesce(tap._fetch267('ck_f6')::jsonb #>> '{ok,status}', tap._fetch267('ck_f6')::jsonb ->> 'state') || '|'
          || coalesce((tap._fetch267('ck_f6x')::jsonb ->> 'state') || '|' || (tap._fetch267('ck_f6x')::jsonb ->> 'message'), '<no refusal>'),
  'ok|P0001|precondition_failed: feature_disabled',
  'F6: on the seq-scan plan, with a non-boolean version in the history, checkout reads only the newest version: true -> ok, then false -> feature_disabled');
SELECT is(tap._call267($q$SELECT to_jsonb((c.value #>> '{}')::boolean) FROM catalog.platform_config c WHERE c.key = 'feature.native_issuance_enabled' ORDER BY c.version DESC LIMIT 1$q$) ->> 'state',
  '22P02',
  'F6b: fixture witness — the cast-before-LIMIT idiom (reserve and the mint) run directly on the same plan raises 22P02, so the planted version is live');
SELECT tap._anyplan267();
DISCARD PLANS;

SELECT * FROM finish();
ROLLBACK;
