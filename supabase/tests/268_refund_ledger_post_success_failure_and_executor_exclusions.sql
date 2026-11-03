-- ============================================================================
-- 268_refund_ledger_post_success_failure_and_executor_exclusions.sql — migration 20261102130000 (registry 199 /
-- pgTAP 268, D). Spec: planning/2026-10-26-launch/D/s15-199/DESIGN-199-FINAL.md §9.
--
--   A  shape: the four new kernel functions resolve; grant class by name; exact ACLs of all eight; SECURITY DEFINER,
--      search_path '', owner postgres, volatility; md5 of the eight and of the three pinned dependencies; argument
--      names; no body names a 189 function; exactly two functions UPDATE kernel.refund; no client or machine role
--      may INSERT into kernel.admin_audit.
--   F  fixtures: O1-O6 finalized through the real path (venue.finalize_primary_order); the ops settings on and every
--      ops action approved against its exact terms.
--   M  refunds-2: the real producers — ops.record_primary_refund (DIRECT arm, aal2 platform_admin), the delegated
--      req: row from kernel.request_order_refund, kernel.admin_refund, and a cancel_event-shaped row. The manual row
--      is never claimed and its context raises; every other row is claimed with its unchanged mode; claim and context
--      agree row by row; a terminal manual row is still held and its context still returns the object.
--   P  refunds-7: park (key, outcome, attempt fencing, status scope, terminal, replay), the claim excludes a parked row
--      and re-admits it once its status moves, the context raises, the re-arm wall (service_role, anon, a fan, a
--      platform_support operator, aal1, no aal, a manual row, unattributed Stripe money: succeeded, pending and
--      requires_action observations and an unobserved one-way record) and the re-armed row reconciling; a park at
--      SUBMITTED (hold, claim exclusion, context raise, re-arm by platform_risk with no money guard, reconcile).
--   W  claim mode (refunds-1 residual): created 21 h ago and never claimed -> reconcile; created 1 h ago -> create;
--      created 21 h ago with its first claim 1 h ago -> reconcile.
--   S  refunds-4: a delegated full refund that succeeded and then failed at Stripe converges to failed through the
--      verb (code from the recorded state, audit row, replay, settlement booking afterwards, replacement headroom,
--      atoms untouched); the submitted arm, canceled, binding mismatches, pending-with-ref, a booked refund_void line,
--      a clawback obligation, in_flight (pending; requires_action on a succeeded row), mark_refund_state's guard in both
--      directions (failed and canceled), and the org settlement seam lock held by the verb (S25 the order, S28 the lock
--      itself in pg_locks). S29-S34 (revision after review of 45708aec): a ref without the re_ prefix, stored by the
--      column's only writer kernel.mark_refund_state, converges through the verb on both arms — succeeded -> failed with
--      the audit row and the settlement-review residue (S29-S32), submitted -> failed on a canceled refund (S33) — and
--      a NULL, empty or blank ref is still refused (S34).
--   E  refunds-5: ops.executor_claim on refunded payments — unresolved, previously-sent admitted, Stripe-confirmed
--      acknowledgement, legacy unobserved, charged back (whole and split with a succeeded refund), the unchanged plain
--      claim, a failed payment, the empty-claims session, a previously-sent action whose payment later gained an
--      unobserved refund, and a refunded payment with no PaymentIntent.
--
-- Race R1 (design §6; I-E3 one lease holder, a parked row never claimed) is NOT proven here: this file runs in one
-- session, so a second session's committed claim or park can never sit between the claim's cursor snapshot and its row
-- lock, and the claim's in-loop lease/hold recheck decides nothing in this file (its removal leaves only A5 red). The
-- R1 proof is the three-session harness planning/2026-10-26-launch/D/s15-199/race_199.sh, run on 199 (one claim row
-- each for R11 and R12), on 199 without the recheck (R11 claimed twice, the parked R12 claimed) and on the base.
--
-- Conventions: BEGIN … plan … finish … ROLLBACK. Every call of a function 199 creates or replaces goes through a value
-- helper (tap._val268 / tap._err268 / tap._svc268), so a RED run or a mutant emits every assertion instead of
-- aborting. Every verb result is stored in one statement and read in a later one (statement snapshot). service_role
-- calls re-login on every call (tap.logout leaves the claims GUC '', which request_is_service_role refuses). Fixture
-- rows that the real path cannot produce are labelled where they are written (direct kernel.refund inserts, as 158
-- writes them; back-dated claim rows; the ops action/approval pair, as 184 E10 writes its direct action).
-- Section order matters: M's claim leases its rows before P's fixtures exist; P parks Rq/Ru/Rm/Rps/Rv1-Rv3 before P4's
-- claim; W's rows are written after P's last claim; S and E write no claim.
--
-- RED (main without 199), predicted before the run: the file runs to the end; 99 emitted = 25 ok + 74 not ok.
--   ok: A6 A7 A8 A10 · F1 F2 · M1 M4 M5 M8 M10 M11 · W2 · S1 S2 S4 S5 S12 S24 S29 · E2 E4 E7 E8 E9.
--   A8 is vacuous on RED (only the four replaced bodies resolve); W2 is the window's positive control (true before
--   and after); S29 is the Rp setup (the 085 mark_refund_state already stores any non-null ref); the rest are
--   behaviour 199 must preserve. Every other assertion is not ok (M12 P20-P26 S26-S28 S30-S34 E11 E12 included).
-- GREEN: 99/99. Mutant predictions: planning/2026-10-26-launch/D/s15-199/delta-regex/mut/PREDICTIONS.txt, run by
-- delta-regex/run_199d.sh (each mutant is a create-or-replace of one function, or one grant, after the GREEN apply;
-- MU38a restores the ref shape check of 45708aec and must turn S30-S34 red).
-- ============================================================================
BEGIN;
SELECT plan(99);

-- ── helpers ──────────────────────────────────────────────────────────────────
CREATE TABLE tap.memo_268 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st268(k text, v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_268 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._fe268(k text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_268 WHERE k = $1 $m$;
-- a stored value as jsonb; an error text or a NULL never raises here
CREATE FUNCTION tap._js268(t text) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS
$m$ BEGIN RETURN t::jsonb; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('unparsed', t); END $m$;
CREATE FUNCTION tap._fj268(k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT tap._js268((SELECT v FROM tap.memo_268 WHERE k = $1)) $m$;
-- value helper (232 idiom): the value, or 'ERROR <SQLSTATE>|<SQLERRM>'
CREATE FUNCTION tap._val268(q text) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v;
    EXCEPTION WHEN OTHERS THEN RETURN 'ERROR ' || SQLSTATE || '|' || SQLERRM; END $m$;
-- error helper: 'no error' or '<SQLSTATE>|<SQLERRM>'
CREATE FUNCTION tap._err268(q text) RETURNS text LANGUAGE plpgsql AS
$m$ BEGIN EXECUTE q; RETURN 'no error';
    EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || '|' || SQLERRM; END $m$;
-- the service path: re-login on every call
CREATE FUNCTION tap._svc268(q text) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN PERFORM tap.login_service(); v := tap._val268(q); PERFORM tap.logout(); RETURN v; END $m$;
-- an aal claim merged into the current claims (the 182 / 259 helper)
CREATE FUNCTION tap._aal268(p text) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM set_config('request.jwt.claims',
  (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb || jsonb_build_object('aal', p))::text, true); END $f$;
-- a caller's call: login, optional aal, the value, logout
CREATE FUNCTION tap._as268(p_uid uuid, p_aal text, q text) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN PERFORM tap.login(p_uid); IF p_aal IS NOT NULL THEN PERFORM tap._aal268(p_aal); END IF;
    v := tap._val268(q); PERFORM tap.logout(); RETURN v; END $m$;
-- the 199 verbs, each through the value helpers
CREATE FUNCTION tap._claim268() RETURNS text LANGUAGE sql AS
$m$ SELECT tap._svc268('SELECT kernel.claim_refunds_for_execution(50, 900)::text') $m$;
CREATE FUNCTION tap._park268(p_refund uuid, p_attempt int, p_reason text, p_key text) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._svc268(format('SELECT kernel.park_refund_execution(%L, %s, %L, %L, %L)::text',
                                p_refund, p_attempt, 'stripe_error', p_reason, p_key)) $m$;
CREATE FUNCTION tap._mark268(p_refund uuid, p_status text, p_ref text, p_code text) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._svc268(format('SELECT kernel.mark_refund_state(%L, %L, %L, %L, %L)::text',
                                p_refund, p_status, p_ref, p_code, 'ck268-mark-' || p_status || '-' || p_refund::text)) $m$;
CREATE FUNCTION tap._verb268(p_ref text, p_key text) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._svc268(format('SELECT kernel.record_refund_stripe_failure(%L, %L)::text', p_ref, p_key)) $m$;
CREATE FUNCTION tap._rrs268(p_pi text, p_re text, p_status text, p_amount int, p_reason text) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._svc268(format('SELECT public.record_refund_state(%L, %L, %L, %s, %L, %L, %L)::text',
                                p_pi, p_re, p_status, p_amount, p_reason, 'dashboard', 'webhook')) $m$;
CREATE FUNCTION tap._rearm268(p_uid uuid, p_aal text, p_refund uuid, p_key text) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._as268(p_uid, p_aal, format('SELECT kernel.rearm_refund_execution(%L, %L, %L)::text', p_refund, 'operator_review', p_key)) $m$;
CREATE FUNCTION tap._ctx268(p_refund uuid) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._err268(format('SELECT kernel.get_refund_execution_context(%L)', p_refund)) $m$;
CREATE FUNCTION tap._hold268(p_refund uuid) RETURNS text LANGUAGE sql AS
$m$ SELECT coalesce(tap._val268(format('SELECT kernel.refund_executor_hold(%L)', p_refund)), '<null>') $m$;
CREATE FUNCTION tap._xclaim268(p_action uuid) RETURNS text LANGUAGE sql AS
$m$ SELECT tap._svc268(format('SELECT ops.executor_claim(%L)::text', p_action)) $m$;
-- did a stored claim batch carry this refund, and in which mode? ('<absent>' when not, or when the batch is no batch)
CREATE FUNCTION tap._mode268(p_batch text, p_refund uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $m$
  SELECT coalesce((SELECT e ->> 'execution_mode' FROM jsonb_array_elements(
                     CASE WHEN jsonb_typeof(tap._fj268(p_batch) -> 'refunds') = 'array' THEN tap._fj268(p_batch) -> 'refunds' ELSE '[]'::jsonb END) e
                    WHERE e ->> 'refund_id' = p_refund::text), '<absent>') $m$;
CREATE FUNCTION tap._id268(k text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT CASE WHEN v ~ '^[0-9a-f]{8}-' THEN v::uuid END FROM tap.memo_268 WHERE k = $1 $m$;
-- a kernel.refund row written directly (the shape 158 writes; labelled at each use)
CREATE FUNCTION tap._mkrefund268(p_payment uuid, p_amount int, p_status text, p_ref text, p_age interval, p_key text,
                                 p_reason text DEFAULT 'buyer_request') RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, status, stripe_refund_ref,
                             idempotency_key, created_at, updated_at)
  values (v_id, p_payment, p_reason, p_amount, p_status, p_ref, p_key, now() - p_age, now() - p_age);
  return v_id::text;
end $f$;
-- a back-dated claim row, shaped exactly as the claim writes it (before {status, stripe_refund_ref}, after {...})
CREATE FUNCTION tap._mkclaim268(p_refund uuid, p_age interval, p_status text, p_attempt int) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after,
                                  occurred_at, created_at)
  values ((repeat('0', 30) || 'f1')::uuid, 'refund.execute_claim', 'refund', p_refund, 'create',
          jsonb_build_object('status', p_status, 'stripe_refund_ref', null),
          jsonb_build_object('execution_mode', 'create', 'attempt', p_attempt, 'lease_seconds', 900,
                             'first_attempt_at', now() - p_age),
          now() - p_age, now() - p_age);
$f$;
-- an ops refund_execute action at `processing` and its approval bound to the exact terms (184 E10 writes the action
-- directly; the approval is the row ops.approve_action leaves behind). p_result is the handoff object ops.action_run
-- stores for a refund_execute action, or NULL as a direct insert leaves it (E5 pins that NULL is not "previously sent")
CREATE FUNCTION tap._mkaction268(p_key text, p_payment uuid, p_attempt int, p_result jsonb) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
declare v_id uuid;
begin
  insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, params, requested_by, state, attempt, result)
  values (p_key, 'refund_execute', 'payment', p_payment, '{}'::jsonb, 'a2680000-0000-4000-a000-000000000a01', 'processing', p_attempt, p_result)
  returning id into v_id;
  insert into ops.approval (action_id, action_hash, requested_by, decided_by, state, expires_at, decided_at)
  values (v_id, ops.action_hash('refund_execute', 'payment', p_payment, null, '{}'::jsonb),
          'a2680000-0000-4000-a000-000000000a01', 'a2680000-0000-4000-a000-000000000a02', 'approved', now() + interval '1 day', now());
  return v_id::text;
end $f$;
-- an ACL as sorted grantee:privilege entries (NULL when the function does not resolve)
CREATE FUNCTION tap._acl268(sig text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT string_agg(CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type, ','
                    ORDER BY CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type)
    FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   WHERE p.oid = to_regprocedure(sig) $m$;
CREATE FUNCTION tap._md5268(sig text) RETURNS text LANGUAGE sql STABLE AS
$m$ SELECT coalesce(md5(pg_get_functiondef(to_regprocedure(sig))), '<absent>') $m$;
-- does THIS backend hold the org settlement seam lock, pg_advisory_xact_lock(hashtext('settlement.seam.org:'||org))?
-- (a bigint advisory key shows as classid = high 32 bits, objid = low 32 bits, objsubid = 1)
CREATE FUNCTION tap._seam268(p_org uuid) RETURNS boolean LANGUAGE sql VOLATILE AS $m$
  SELECT EXISTS (SELECT 1 FROM pg_locks l, (SELECT hashtext('settlement.seam.org:' || p_org::text)::bigint AS k) x
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 1
                    AND l.classid::bigint = ((x.k >> 32) & 4294967295) AND l.objid::bigint = (x.k & 4294967295)) $m$;
CREATE FUNCTION tap._pem268() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;
GRANT EXECUTE ON FUNCTION tap._st268(text, text), tap._fe268(text), tap._js268(text), tap._fj268(text), tap._val268(text),
  tap._err268(text), tap._svc268(text), tap._aal268(text), tap._as268(uuid, text, text), tap._claim268(),
  tap._park268(uuid, int, text, text), tap._mark268(uuid, text, text, text), tap._verb268(text, text),
  tap._rrs268(text, text, text, int, text), tap._rearm268(uuid, text, uuid, text), tap._ctx268(uuid), tap._hold268(uuid),
  tap._xclaim268(uuid), tap._mode268(text, uuid), tap._id268(text), tap._seam268(uuid) TO anon, authenticated, service_role;

-- ── fixture (synthetic; never a migration) ──────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT u.id::uuid, repeat('0', 32)::uuid, 'authenticated', 'authenticated', u.email, '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM (VALUES ('a2680000-0000-4000-a000-000000000101', 'buyer.268@test.local'),
               ('a2680000-0000-4000-a000-000000000199', 'fan.268@test.local'),
               ('a2680000-0000-4000-a000-000000000a01', 'admin.268@test.local'),
               ('a2680000-0000-4000-a000-000000000a02', 'support.268@test.local'),
               ('a2680000-0000-4000-a000-000000000a03', 'risk.268@test.local'),
               ('a2680000-0000-4000-a000-000000000a05', 'owner.268@test.local'),
               (repeat('0', 30) || 'f1', 'sn-system.268@test.local')) u(id, email)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES
  ('a2680000-0000-4000-a000-000000000a01', 'platform_admin'),
  ('a2680000-0000-4000-a000-000000000a02', 'platform_support'),
  ('a2680000-0000-4000-a000-000000000a03', 'platform_risk');
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('a2680000-0000-4000-a000-00000000000a', 'Org 268', 'Org 268', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at) VALUES
  ('a2680000-0000-4000-a000-00000000000a', 'a2680000-0000-4000-a000-000000000a05', 'org_owner', 'a2680000-0000-4000-a000-000000000a01', now());
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('a2680000-0000-4000-a000-0000000000a1', 'a2680000-0000-4000-a000-00000000000a', 'Room 268', 'wynwood', 'approved');
-- three events, one session / ticket type / batch / buyer hold each: E1 carries O1 O2 O5 O6, E3 carries O3, E4 carries O4
-- (one event per settlement, so E3's and E4's closes each see exactly one order)
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status)
SELECT ('a2680000-0000-4000-a000-0000000000e' || x)::uuid, 'a2680000-0000-4000-a000-0000000000a1', 'a2680000-0000-4000-a000-00000000000a', 'Refunds 268 E' || x, 'on_sale'
  FROM unnest(ARRAY['1', '3', '4']) x;
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status)
SELECT ('a2680000-0000-4000-a000-00000000005' || x)::uuid, ('a2680000-0000-4000-a000-0000000000e' || x)::uuid, now() + interval '30 days', 'scheduled'
  FROM unnest(ARRAY['1', '3', '4']) x;
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
SELECT ('a2680000-0000-4000-a000-00000000001' || x)::uuid, ('a2680000-0000-4000-a000-0000000000e' || x)::uuid, 'admission', 'GA 268 E' || x, 10000, 'public'
  FROM unnest(ARRAY['1', '3', '4']) x;
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold)
SELECT ('a2680000-0000-4000-a000-00000000002' || x)::uuid, ('a2680000-0000-4000-a000-00000000001' || x)::uuid, ('a2680000-0000-4000-a000-00000000005' || x)::uuid, 'public_sale', 100, 1, 0
  FROM unnest(ARRAY['1', '3', '4']) x;
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
SELECT ('a2680000-0000-4000-a000-00000000003' || x)::uuid, ('a2680000-0000-4000-a000-00000000002' || x)::uuid, 'a2680000-0000-4000-a000-000000000101', 1, 'active', now() + interval '1 hour', 'h-268-' || x
  FROM unnest(ARRAY['1', '3', '4']) x;
-- six one-ticket orders (face 10000; the payment charged 11000 = face + 1000 buyer fee)
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
SELECT ('a2680000-0000-4000-a000-00000000030' || o.n)::uuid, 'a2680000-0000-4000-a000-000000000101',
       ('a2680000-0000-4000-a000-00000000005' || o.e)::uuid, 'a2680000-0000-4000-a000-00000000000a', 'pending', 'app', 10000, 'USD', 'o-268-' || o.n
  FROM (VALUES ('1', '1'), ('2', '1'), ('3', '3'), ('4', '4'), ('5', '1'), ('6', '1')) o(n, e);
INSERT INTO venue.order_item (id, order_id, ticket_type_id, quantity, unit_price_minor)
SELECT ('a2680000-0000-4000-a000-0000000004' || right(o.order_id::text, 2))::uuid, o.order_id,
       (SELECT tt.ticket_type_id FROM catalog.event_session es JOIN venue.ticket_type tt ON tt.event_id = es.event_id WHERE es.session_id = o.event_session_id),
       1, 10000
  FROM venue."order" o WHERE o.order_id::text LIKE 'a2680000-%';
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
SELECT ('a2680000-0000-4000-a000-0000000006' || right(o.order_id::text, 2))::uuid, NULL, 'a2680000-0000-4000-a000-000000000101', NULL,
       10000, 1000, 0, 11000, 'pi_268_' || right(o.order_id::text, 2), 'succeeded', 'native_primary', now()
  FROM venue."order" o WHERE o.order_id::text LIKE 'a2680000-%';
-- payments with no native link: PP (the P / W rows), PU (Ru, Rps), PV1-PV3 (Rv1-Rv3), PS (the S direct rows), PY
-- (S17's foreign observation), PE5-PE14 (section E; PE12 is a failed payment; PE13 is a refunded payment with no
-- PaymentIntent — a direct insert: record_payment_refund finds a payment only by its PI, so the real path cannot make it)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
SELECT x.id::uuid, NULL, 'a2680000-0000-4000-a000-000000000101', NULL, x.total - 1000, 1000, 0, x.total, x.pi, x.st, 'native_primary', now()
  FROM (VALUES ('a2680000-0000-4000-a000-000000000701', 'pi_268_pp',  50000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000702', 'pi_268_u',   11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000703', 'pi_268_v1',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000704', 'pi_268_v2',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000705', 'pi_268_v3',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000711', 'pi_268_s',  100000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000712', 'pi_268_y',  100000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000805', 'pi_268_e5',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000806', 'pi_268_e6',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000807', 'pi_268_e7',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000808', 'pi_268_e8',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000809', 'pi_268_e9',  11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000810', 'pi_268_e10', 11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000811', 'pi_268_e11', 11000, 'succeeded'),
               ('a2680000-0000-4000-a000-000000000812', 'pi_268_e12', 11000, 'failed'),
               ('a2680000-0000-4000-a000-000000000813', NULL,         11000, 'refunded'),
               ('a2680000-0000-4000-a000-000000000814', 'pi_268_e14', 11000, 'succeeded')) x(id, pi, total, st);
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT x.k, coalesce((SELECT max(c.version) FROM catalog.platform_config c WHERE c.key = x.k), 0) + 1, x.v, x.vis
  FROM (VALUES ('feature.native_issuance_enabled', 'true'::jsonb, 'public')) x(k, v, vis);
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
SELECT (repeat('0', 30) || 'b0')::uuid, 'global', tap._pem268(),
       'arn:aws:kms:us-east-1:' || repeat('0', 12) || ':key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now()
 WHERE NOT EXISTS (SELECT 1 FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active');
-- THE REAL ISSUANCE PATH for O1-O6 (as the rehearsal superuser; auth.uid() NULL -> actor SN-SYSTEM)
SELECT tap._st268('fin_' || right(o::text, 2), tap._val268(format('SELECT venue.finalize_primary_order(%L, %L, %L, NULL)::text',
         o, ('a2680000-0000-4000-a000-0000000006' || right(o::text, 2))::uuid, 'ck268-fin-' || right(o::text, 2))))
  FROM unnest(ARRAY['a2680000-0000-4000-a000-000000000301', 'a2680000-0000-4000-a000-000000000302', 'a2680000-0000-4000-a000-000000000303',
                    'a2680000-0000-4000-a000-000000000304', 'a2680000-0000-4000-a000-000000000305', 'a2680000-0000-4000-a000-000000000306']::uuid[]) o;
-- section E's ops: the console on, refund execution on, eight approved refund_execute actions (a8 with a NULL result)
UPDATE ops.setting SET value = 'true'::jsonb WHERE key IN ('refund_execute_enabled', 'actions_enabled');
SELECT tap._st268('a' || x.n, tap._mkaction268('k268-e-' || x.n || '-action', x.pay::uuid, x.att,
         CASE WHEN x.n = '8' THEN NULL ELSE jsonb_build_object('status', 'processing', 'handoff', 'ops-refund-execute', 'amount_cents', 11000, 'currency', 'usd') END))
  FROM (VALUES ('5', 'a2680000-0000-4000-a000-000000000805', 0), ('6', 'a2680000-0000-4000-a000-000000000806', 0),
               ('7', 'a2680000-0000-4000-a000-000000000807', 0), ('8', 'a2680000-0000-4000-a000-000000000808', 0),
               ('9', 'a2680000-0000-4000-a000-000000000809', 0), ('10', 'a2680000-0000-4000-a000-000000000810', 0),
               ('11', 'a2680000-0000-4000-a000-000000000811', 0), ('12', 'a2680000-0000-4000-a000-000000000812', 1)) x(n, pay, att);

-- ── Section A — shape ────────────────────────────────────────────────────────
SELECT is(ARRAY[to_regprocedure('kernel.refund_executor_hold(uuid)') IS NOT NULL,
                to_regprocedure('kernel.record_refund_stripe_failure(text,text)') IS NOT NULL,
                to_regprocedure('kernel.park_refund_execution(uuid,integer,text,text,text)') IS NOT NULL,
                to_regprocedure('kernel.rearm_refund_execution(uuid,text,text)') IS NOT NULL],
          ARRAY[true, true, true, true],
  'A1: the four new kernel functions resolve (refund_executor_hold, record_refund_stripe_failure, park_refund_execution, rearm_refund_execution)');
SELECT is((SELECT string_agg(p.proname || ' secdef=' || p.prosecdef::text
                             || ' auth=' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
                             || ' svc='  || has_function_privilege('service_role',  p.oid, 'EXECUTE')::text, ';' ORDER BY p.proname COLLATE "C")
             FROM pg_proc p WHERE p.pronamespace = 'kernel'::regnamespace
              AND p.proname IN ('refund_executor_hold', 'record_refund_stripe_failure', 'park_refund_execution', 'rearm_refund_execution')),
  'park_refund_execution secdef=true auth=false svc=true;rearm_refund_execution secdef=true auth=true svc=false;'
  || 'record_refund_stripe_failure secdef=true auth=false svc=true;refund_executor_hold secdef=true auth=false svc=false',
  'A2: grant class by name — the hold is nobody''s, the converger and the park are service_role''s, the re-arm is authenticated''s and never service_role''s');
SELECT is(ARRAY[tap._acl268('kernel.refund_executor_hold(uuid)'),
                tap._acl268('kernel.mark_refund_state(uuid,text,text,text,text)'),
                tap._acl268('kernel.claim_refunds_for_execution(integer,integer)'),
                tap._acl268('kernel.get_refund_execution_context(uuid)'),
                tap._acl268('kernel.record_refund_stripe_failure(text,text)'),
                tap._acl268('kernel.park_refund_execution(uuid,integer,text,text,text)'),
                tap._acl268('kernel.rearm_refund_execution(uuid,text,text)'),
                tap._acl268('ops.executor_claim(uuid,integer)')],
          ARRAY['postgres:EXECUTE',
                'postgres:EXECUTE,service_role:EXECUTE', 'postgres:EXECUTE,service_role:EXECUTE', 'postgres:EXECUTE,service_role:EXECUTE',
                'postgres:EXECUTE,service_role:EXECUTE', 'postgres:EXECUTE,service_role:EXECUTE',
                'authenticated:EXECUTE,postgres:EXECUTE',
                'postgres:EXECUTE,service_role:EXECUTE'],
  'A3: exact ACLs of the eight (no PUBLIC entry anywhere)');
SELECT is((SELECT string_agg(p.proname || ':' || (p.prosecdef AND p.proconfig = ARRAY['search_path=""'] AND p.proowner = 'postgres'::regrole)::text
                             || ':' || p.provolatile::text, ',' ORDER BY p.proname COLLATE "C")
             FROM pg_proc p
            WHERE p.oid IN (to_regprocedure('kernel.refund_executor_hold(uuid)'), to_regprocedure('kernel.mark_refund_state(uuid,text,text,text,text)'),
                            to_regprocedure('kernel.claim_refunds_for_execution(integer,integer)'), to_regprocedure('kernel.get_refund_execution_context(uuid)'),
                            to_regprocedure('kernel.record_refund_stripe_failure(text,text)'), to_regprocedure('kernel.park_refund_execution(uuid,integer,text,text,text)'),
                            to_regprocedure('kernel.rearm_refund_execution(uuid,text,text)'), to_regprocedure('ops.executor_claim(uuid,integer)'))),
  'claim_refunds_for_execution:true:v,executor_claim:true:v,get_refund_execution_context:true:s,mark_refund_state:true:v,'
  || 'park_refund_execution:true:v,rearm_refund_execution:true:v,record_refund_stripe_failure:true:v,refund_executor_hold:true:s',
  'A4: posture of the eight — SECURITY DEFINER, search_path '''', owner postgres; the hold and the context STABLE, the rest VOLATILE');
SELECT is(ARRAY[tap._md5268('kernel.refund_executor_hold(uuid)'),
                tap._md5268('kernel.mark_refund_state(uuid,text,text,text,text)'),
                tap._md5268('kernel.claim_refunds_for_execution(integer,integer)'),
                tap._md5268('kernel.get_refund_execution_context(uuid)'),
                tap._md5268('kernel.record_refund_stripe_failure(text,text)'),
                tap._md5268('kernel.park_refund_execution(uuid,integer,text,text,text)'),
                tap._md5268('kernel.rearm_refund_execution(uuid,text,text)'),
                tap._md5268('ops.executor_claim(uuid,integer)')],
          ARRAY['31d6705d651d04ef82191faec528ad27', 'a14aafa2040db639a18f64aa30e5b6f1', '3664f28dc744d274ff8813309edf9fd0',
                '8aede0fc7dbdb0bc37a53d53c0eda51e', '8a443bd8ee3444ba11b6097eeda6fd9a', '822d2d2fd0cfd3e39f8fe6f1f0baec74',
                '977edd52c3d535a36f7431ea008a2bb9', '2d658f3406ea6e774fd8f6dcb163a27f'],
  'A5: md5(pg_get_functiondef) of the eight = the values 199 declares');
SELECT is(ARRAY[tap._md5268('kernel.refund_primary_order(uuid,integer,text,text)'),
                tap._md5268('public.record_refund_state(text,text,text,integer,text,text,text)'),
                tap._md5268('kernel.settlement_primary_lines(uuid)')],
          ARRAY['e0a37574a02131e4cedec43a2ef427f7', '5e9f66129a4bb82b6b3e7a1b41e04365', 'ebc5d6c16334e55e39ceea63d9eab7f6'],
  'A6: the three pinned dependencies are unchanged (085 refund_primary_order, 150 record_refund_state, 100 settlement_primary_lines)');
SELECT is(ARRAY[(SELECT proargnames::text FROM pg_proc WHERE oid = to_regprocedure('kernel.claim_refunds_for_execution(integer,integer)')),
                (SELECT proargnames::text FROM pg_proc WHERE oid = to_regprocedure('kernel.get_refund_execution_context(uuid)')),
                (SELECT proargnames::text FROM pg_proc WHERE oid = to_regprocedure('ops.executor_claim(uuid,integer)'))],
          ARRAY['{p_limit,p_lease_seconds}', '{p_refund_id}', '{p_action_id,p_lease_seconds}'],
  'A7: argument names of the claim, the context and ops.executor_claim are unchanged (158 A4)');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p
                       WHERE p.oid IN (to_regprocedure('kernel.refund_executor_hold(uuid)'), to_regprocedure('kernel.mark_refund_state(uuid,text,text,text,text)'),
                                       to_regprocedure('kernel.claim_refunds_for_execution(integer,integer)'), to_regprocedure('kernel.get_refund_execution_context(uuid)'),
                                       to_regprocedure('kernel.record_refund_stripe_failure(text,text)'), to_regprocedure('kernel.park_refund_execution(uuid,integer,text,text,text)'),
                                       to_regprocedure('kernel.rearm_refund_execution(uuid,text,text)'), to_regprocedure('ops.executor_claim(uuid,integer)'))
                         AND p.prosrc ~ '(record_primary_refund|primary_reconciliation)'),
  'A8: no body among the eight names a 189 function (189''s rollback guard stays satisfiable)');
SELECT is((SELECT string_agg(n.nspname || '.' || p.proname, ',' ORDER BY n.nspname || '.' || p.proname)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'tap') AND n.nspname !~ '^pg_'
              AND p.prosrc ~* 'update\s+kernel\.refund\s'),
  'kernel.mark_refund_state,kernel.record_refund_stripe_failure',
  'A9: exactly two functions UPDATE kernel.refund — mark_refund_state and record_refund_stripe_failure');
SELECT is(ARRAY[has_table_privilege('anon', 'kernel.admin_audit', 'INSERT'), has_table_privilege('authenticated', 'kernel.admin_audit', 'INSERT'),
                has_table_privilege('service_role', 'kernel.admin_audit', 'INSERT')],
          ARRAY[false, false, false],
  'A10: no INSERT on kernel.admin_audit for anon, authenticated or service_role — the hold markers are unforgeable');

-- ── Section F — fixtures ─────────────────────────────────────────────────────
SELECT is(ARRAY[(SELECT count(*) FROM tap.memo_268 WHERE k LIKE 'fin\_%' AND tap._js268(v) ->> 'status' = 'ok')::int,
                (SELECT count(*) FROM kernel.payment_native WHERE order_id::text LIKE 'a2680000-%')::int,
                (SELECT count(*) FROM kernel.ticket_ownership_log l JOIN venue.order_item oi ON oi.id = l.cause_ref
                  WHERE l.sequence = 1 AND oi.order_id::text LIKE 'a2680000-%')::int],
          ARRAY[6, 6, 6],
  'F1: O1-O6 finalized through the real path — six payment_native links, six atoms');
SELECT is(ARRAY[(SELECT value #>> '{}' FROM ops.setting WHERE key = 'refund_execute_enabled'),
                (SELECT value #>> '{}' FROM ops.setting WHERE key = 'actions_enabled'),
                (SELECT count(*) FROM ops.action a JOIN ops.approval ap ON ap.action_id = a.id AND ap.state = 'approved'
                  WHERE a.idempotency_key LIKE 'k268-e-%' AND a.state = 'processing'
                    AND ap.action_hash = ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params))::text],
          ARRAY['true', 'true', '8'],
  'F2: refund_execute_enabled and actions_enabled are on; eight refund_execute actions are processing with an approval bound to their exact terms');

-- ── Section M — manual-rail exclusion (refunds-2) ────────────────────────────
-- the manual row: the real producer, an aal2 platform_admin through ops.record_primary_refund (DIRECT arm, partial)
SELECT tap._st268('m1', tap._as268('a2680000-0000-4000-a000-000000000a01', 'aal2',
         $q$SELECT ops.record_primary_refund('a2680000-0000-4000-a000-000000000301', 1000, 'admin_action', 'ck268-m1-manual')::text$q$));
SELECT tap._st268('r_man', tap._fj268('m1') ->> 'refund_id');
SELECT is((SELECT ARRAY[tap._fj268('m1') ->> 'status', r.status, (r.stripe_refund_ref IS NULL)::text, a.after ->> 'delegated',
                        (a.after ->> 'refund_id' = r.refund_id::text)::text]
             FROM kernel.refund r
             LEFT JOIN kernel.admin_audit a ON a.action = 'refund.issue' AND a.subject_kind = 'order'
                                           AND a.subject_id = 'a2680000-0000-4000-a000-000000000301'
            WHERE r.refund_id = tap._id268('r_man')),
          ARRAY['ok', 'pending', 'true', 'false', 'true'],
  'M1: ops.record_primary_refund (aal2 platform_admin) writes a pending row with no ref and the refund.issue audit carrying delegated=false and the row''s refund_id (the marker shape)');
-- the delegated row (request_order_refund, auto-executed for a platform_admin -> req: key), the admin_refund row, and a
-- cancel_event-shaped row (direct insert as 088 writes one: event_cancelled, no audit) on O1's own payment
SELECT tap._st268('m_del', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.request_order_refund('a2680000-0000-4000-a000-000000000302', '{}'::uuid[], 2000, 'buyer_request', 'ck268-m-deleg')::text$q$));
SELECT tap._st268('r_del', tap._fj268('m_del') ->> 'refund_id');
SELECT tap._st268('m_adm', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.admin_refund('a2680000-0000-4000-a000-000000000606', '{}'::uuid[], 1000, 'admin_action', 'ck268-m-admin')::text$q$));
SELECT tap._st268('r_adm', tap._fj268('m_adm') ->> 'refund_id');
SELECT tap._st268('r_can', tap._mkrefund268('a2680000-0000-4000-a000-000000000601', 500, 'pending', NULL, interval '0',
         '268cmd:order:a2680000-0000-4000-a000-000000000301', 'event_cancelled'));
SELECT is(ARRAY[tap._hold268(tap._id268('r_man')), tap._hold268(tap._id268('r_del'))], ARRAY['manual_record', '<null>'],
  'M2: refund_executor_hold marks the manual row manual_record and leaves the delegated req: row unmarked');
SELECT tap._st268('m10_before', (SELECT status || '|' || coalesce(stripe_refund_ref, '-') || '|' || updated_at::text
                                   FROM kernel.refund WHERE refund_id = tap._id268('r_man')));
SELECT tap._st268('m3', tap._claim268());
SELECT ok(jsonb_typeof(tap._fj268('m3') -> 'refunds') = 'array' AND tap._mode268('m3', tap._id268('r_man')) = '<absent>',
  'M3: the claim batch does not carry the manual row');
SELECT is(tap._mode268('m3', tap._id268('r_del')), 'create',
  'M4: the delegated req: row is claimed, in create mode');
SELECT is(ARRAY[tap._mode268('m3', tap._id268('r_can')), tap._mode268('m3', tap._id268('r_adm'))], ARRAY['create', 'create'],
  'M5: the cancel_event-shaped row (on the manual row''s own payment) and the kernel.admin_refund row are both claimed');
SELECT is(ARRAY[(SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_claim' AND subject_id = tap._id268('r_man'))::int,
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_claim' AND subject_id = tap._id268('r_del'))::int],
          ARRAY[0, 1],
  'M6: claim rows — none for the manual row, one for the delegated row');
SELECT is(tap._ctx268(tap._id268('r_man')), 'P0001|precondition_failed: executor_hold manual_record (refund ' || tap._fe268('r_man') || ')',
  'M7: get_refund_execution_context raises executor_hold manual_record for the manual row (every Stripe POST path reads it first)');
SELECT is((SELECT array_agg(k ORDER BY k COLLATE "C")
             FROM jsonb_object_keys(tap._js268(tap._val268(format('SELECT kernel.get_refund_execution_context(%L)::text', tap._id268('r_del'))))) k),
          ARRAY['amount_minor', 'currency', 'disputed_minor', 'order_id', 'payment_id', 'payment_status', 'payment_total_minor',
                'prior_non_failed_minor', 'reason_code', 'refund_id', 'sale_id', 'status', 'stripe_livemode',
                'stripe_payment_intent_id', 'stripe_refund_ref'],
  'M8: the delegated row''s context carries exactly 093''s fifteen keys');
SELECT ok((SELECT bool_and((tap._mode268('m3', x.id) <> '<absent>') = (tap._ctx268(x.id) NOT LIKE '%executor_hold%'))
                  AND bool_or(tap._mode268('m3', x.id) = '<absent>') AND bool_or(tap._mode268('m3', x.id) <> '<absent>')
             FROM (SELECT tap._id268(k) AS id FROM unnest(ARRAY['r_man', 'r_del', 'r_can', 'r_adm']) k) x),
  'M9: claim and context agree on all four rows (claimed exactly when the context does not raise executor_hold), and the set holds both an excluded and a claimed row');
SELECT is((SELECT status || '|' || coalesce(stripe_refund_ref, '-') || '|' || updated_at::text FROM kernel.refund WHERE refund_id = tap._id268('r_man')),
          tap._fe268('m10_before'),
  'M10: the manual row''s status, ref and updated_at are unchanged across the claim');
SELECT ok(tap._val268(format('SELECT kernel.get_refund_execution_context(%L)::text', gen_random_uuid())) IS NULL,
  'M11: an unknown refund id still yields SQL NULL (158 G1)');
-- a second manual row on O1 through the same real producer, then moved to terminal through mark_refund_state (the only
-- writer of submitted / succeeded); written after M3's claim, and terminal before any later claim runs
SELECT tap._st268('m12', tap._as268('a2680000-0000-4000-a000-000000000a01', 'aal2',
         $q$SELECT ops.record_primary_refund('a2680000-0000-4000-a000-000000000301', 1000, 'admin_action', 'ck268-m12-manual')::text$q$));
SELECT tap._st268('r_m12', tap._fj268('m12') ->> 'refund_id');
SELECT tap._st268('m12s', tap._mark268(tap._id268('r_m12'), 'submitted', 're_268m12', NULL));
SELECT tap._st268('m12t', tap._mark268(tap._id268('r_m12'), 'succeeded', 're_268m12', NULL));
SELECT is(ARRAY[tap._fj268('m12') ->> 'status', tap._fj268('m12s') ->> 'status', tap._fj268('m12t') ->> 'status', tap._hold268(tap._id268('r_m12')),
                tap._js268(tap._val268(format('SELECT kernel.get_refund_execution_context(%L)::text', tap._id268('r_m12')))) ->> 'status'],
          ARRAY['ok', 'ok', 'ok', 'manual_record', 'succeeded'],
  'M12: a terminal (succeeded) manual row is still marked manual_record, yet its context returns the object (the raise covers only pending/submitted rows; planReconcile''s noop_replay stays reachable)');

-- ── Section P — park and re-arm (refunds-7) ──────────────────────────────────
-- direct pending rows (158's shape) created 26 h ago on PP/PU, each claimed once 25 h ago (attempt 1, at pending);
-- Rs2 also holds a live attempt 2 (1 minute ago), so no claim in this file can take it; Rterm is terminal
SELECT tap._st268('r' || x, tap._mkrefund268(CASE x WHEN 'u' THEN 'a2680000-0000-4000-a000-000000000702' ELSE 'a2680000-0000-4000-a000-000000000701' END::uuid,
                                             1000, 'pending', NULL, interval '26 hours', 'ck268-p-' || x))
  FROM unnest(ARRAY['p', 't', 'q', 'm', 's2', 'u']) x;
SELECT tap._st268('rterm', tap._mkrefund268('a2680000-0000-4000-a000-000000000701', 1000, 'succeeded', 're_268term', interval '26 hours', 'ck268-p-term'));
SELECT tap._mkclaim268(tap._id268('r' || x), interval '25 hours', 'pending', 1) FROM unnest(ARRAY['p', 't', 'q', 'm', 's2', 'u']) x;
SELECT tap._mkclaim268(tap._id268('rs2'), interval '1 minute', 'pending', 2);
-- Rps (PU): claimed at pending (attempt 1, 25 h ago), moved to submitted, claimed at submitted (attempt 2, 24 h ago);
-- both claims back-dated, so only the hold can keep a later claim off it -> the park at SUBMITTED (P20-P24).
-- Rv1-Rv3 (PV1-PV3): pending rows claimed once 25 h ago and parked; their payments later carry Stripe money bound to no
-- kernel refund (P25, P26)
SELECT tap._st268('r' || x.k, tap._mkrefund268(x.pay::uuid, 1000, 'pending', NULL, interval '26 hours', 'ck268-p-' || x.k))
  FROM (VALUES ('ps', 'a2680000-0000-4000-a000-000000000702'), ('v1', 'a2680000-0000-4000-a000-000000000703'),
               ('v2', 'a2680000-0000-4000-a000-000000000704'), ('v3', 'a2680000-0000-4000-a000-000000000705')) x(k, pay);
SELECT tap._mkclaim268(tap._id268('r' || x), interval '25 hours', 'pending', 1) FROM unnest(ARRAY['ps', 'v1', 'v2', 'v3']) x;
SELECT tap._st268('p20m', tap._mark268(tap._id268('rps'), 'submitted', 're_268ps', NULL));
SELECT tap._mkclaim268(tap._id268('rps'), interval '24 hours', 'submitted', 2);
SELECT tap._st268('p_before', (SELECT status || '|' || coalesce(stripe_refund_ref, '-') || '|' || updated_at::text FROM kernel.refund WHERE refund_id = tap._id268('rp')));
SELECT tap._st268('p1', tap._park268(tap._id268('rp'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rp')));
SELECT is(tap._fj268('p1') ->> 'status', 'ok',
  'P1: the sweep parks Rp (attempt 1, stripe_error, charge_disputed, its DB-issued key) -> ok');
SELECT is((SELECT ARRAY[count(*)::text, min(actor_identity::text), min(reason_code), min(before ->> 'status'), min(after ->> 'outcome'), min(after ->> 'attempt')]
             FROM kernel.admin_audit WHERE action = 'refund.execute_parked' AND subject_id = tap._id268('rp')),
          ARRAY['1', ((repeat('0', 30) || 'f1')::uuid)::text, 'charge_disputed', 'pending', 'stripe_error', '1'],
  'P2: exactly one refund.execute_parked row — SYSTEM actor, reason charge_disputed, before.status pending, outcome stripe_error, attempt 1');
SELECT tap._st268('p3', tap._park268(tap._id268('rp'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rp')));
SELECT is(ARRAY[tap._fj268('p3') ->> 'status',
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_parked' AND subject_id = tap._id268('rp'))::text],
          ARRAY['noop_replay', '1'],
  'P3: the replay is noop_replay and writes nothing (still one park row)');
SELECT tap._st268('park_q', tap._park268(tap._id268('rq'), 1, 'resource_missing', 'refund.execute:' || tap._fe268('rq')));
SELECT tap._st268('park_u', tap._park268(tap._id268('ru'), 1, 'reconcile_ambiguous', 'refund.execute:' || tap._fe268('ru')));
SELECT tap._st268('p20', tap._park268(tap._id268('rps'), 2, 'resource_missing', 'refund.execute:' || tap._fe268('rps')));
SELECT tap._st268('park_v' || x, tap._park268(tap._id268('rv' || x), 1, 'reconcile_ambiguous', 'refund.execute:' || tap._fe268('rv' || x)))
  FROM unnest(ARRAY['1', '2', '3']) x;
SELECT is(ARRAY[tap._fj268('p20m') ->> 'status', tap._fj268('p20') ->> 'status', tap._fj268('p20') ->> 'parked_status', tap._hold268(tap._id268('rps'))],
          ARRAY['ok', 'ok', 'submitted', 'parked'],
  'P20: Rps (moved to submitted, then claimed at submitted as attempt 2) -> park(Rps, 2, resource_missing) is ok with parked_status submitted, and the hold reads parked');
SELECT tap._st268('p8m', tap._mark268(tap._id268('rm'), 'submitted', 're_268m', NULL));
SELECT tap._st268('p8', tap._park268(tap._id268('rm'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rm')));
SELECT is(ARRAY[tap._fj268('p8m') ->> 'status', tap._fj268('p8') ->> 'status', tap._fj268('p8') ->> 'reason',
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_parked' AND subject_id = tap._id268('rm'))::text],
          ARRAY['ok', 'not_parked', 'status_moved', '0'],
  'P8: Rm moved to submitted after its pending claim -> park(Rm, 1) is not_parked/status_moved and writes nothing');
SELECT tap._st268('p4', tap._claim268());
SELECT is(ARRAY[tap._mode268('p4', tap._id268('rp')), tap._mode268('p4', tap._id268('rt'))], ARRAY['<absent>', 'reconcile'],
  'P4: the claim excludes parked Rp and takes its twin Rt in reconcile mode');
SELECT is(ARRAY[jsonb_typeof(tap._fj268('p4') -> 'refunds'), tap._mode268('p4', tap._id268('rps'))], ARRAY['array', '<absent>'],
  'P21: the same claim batch excludes Rps, parked at submitted (its last claim is 24 h old: only the hold keeps it out)');
SELECT is(tap._ctx268(tap._id268('rps')), 'P0001|precondition_failed: executor_hold parked (refund ' || tap._fe268('rps') || ')',
  'P22: get_refund_execution_context raises executor_hold parked for Rps (a submitted row)');
SELECT tap._st268('p5a', tap._park268(tap._id268('rp'), 1, 'charge_disputed', 'sweep:' || tap._fe268('rp')));
SELECT tap._st268('p5b', tap._park268(tap._id268('rp'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rt')));
SELECT is(ARRAY[tap._fe268('p5a'), tap._fe268('p5b'),
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_parked' AND subject_id = tap._id268('rp'))::text],
          ARRAY['ERROR P0001|invalid_input: command_key is not the DB-issued refund.execute:<refund_id>',
                'ERROR P0001|invalid_input: command_key is not the DB-issued refund.execute:<refund_id>', '1'],
  'P5: a sweep:<id> key and another refund''s refund.execute key are refused invalid_input; no row');
SELECT tap._st268('rn6', tap._mkrefund268('a2680000-0000-4000-a000-000000000701', 1000, 'pending', NULL, interval '26 hours', 'ck268-p-n6'));
SELECT tap._st268('p6', tap._park268(tap._id268('rn6'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rn6')));
SELECT is(tap._fe268('p6'), 'ERROR P0001|precondition_failed: never_claimed (refund ' || tap._fe268('rn6') || ' has no refund.execute_claim row)',
  'P6: a never-claimed row cannot be parked (never_claimed)');
SELECT tap._st268('p7a', tap._park268(tap._id268('rs2'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rs2')));
SELECT tap._st268('p7b', tap._park268(tap._id268('rs2'), 3, 'charge_disputed', 'refund.execute:' || tap._fe268('rs2')));
SELECT is(ARRAY[tap._fj268('p7a') ->> 'status', tap._fj268('p7a') ->> 'reason', tap._fe268('p7b'),
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_parked' AND subject_id = tap._id268('rs2'))::text],
          ARRAY['not_parked', 'stale_attempt', 'ERROR P0001|invalid_input: no_such_claim_attempt (3 > latest 2)', '0'],
  'P7: Rs2 (attempts 1 and 2) — park(attempt 1) is not_parked/stale_attempt, park(attempt 3) is no_such_claim_attempt; no row');
SELECT tap._st268('p9m', tap._mark268(tap._id268('rq'), 'submitted', 're_268q', NULL));
SELECT tap._st268('p9', tap._claim268());
SELECT is(ARRAY[tap._fj268('park_q') ->> 'status', tap._fj268('p9m') ->> 'status', tap._mode268('p9', tap._id268('rq'))],
          ARRAY['ok', 'ok', 'reconcile'],
  'P9: Rq parked at pending, then submitted -> the park no longer applies and the claim takes Rq in reconcile');
SELECT tap._st268('p10', tap._park268(tap._id268('rterm'), 1, 'charge_disputed', 'refund.execute:' || tap._fe268('rterm')));
SELECT is(ARRAY[tap._fj268('p10') ->> 'status', tap._fj268('p10') ->> 'reason'], ARRAY['not_parked', 'terminal'],
  'P10: a terminal row is never parked (not_parked/terminal)');
SELECT is(ARRAY[tap._fj268('p1') ->> 'status',
                (SELECT status || '|' || coalesce(stripe_refund_ref, '-') || '|' || updated_at::text FROM kernel.refund WHERE refund_id = tap._id268('rp'))],
          ARRAY['ok', tap._fe268('p_before')],
  'P11: the park returned ok and Rp''s status, ref and updated_at are unchanged (a park writes only audit)');
SELECT is(tap._ctx268(tap._id268('rp')), 'P0001|precondition_failed: executor_hold parked (refund ' || tap._fe268('rp') || ')',
  'P12: get_refund_execution_context raises executor_hold parked for Rp');
SELECT tap._st268('p13s', tap._svc268(format('SELECT kernel.rearm_refund_execution(%L, %L, %L)::text', tap._id268('rt'), 'operator_review', 'ck268-p13-svc')));
SELECT tap.login_anon();
SELECT tap._st268('p13a', tap._val268(format('SELECT kernel.rearm_refund_execution(%L, %L, %L)::text', tap._id268('rt'), 'operator_review', 'ck268-p13-anon')));
SELECT tap.logout();
SELECT tap._st268('p13f', tap._rearm268('a2680000-0000-4000-a000-000000000199', 'aal2', tap._id268('rt'), 'ck268-p13-fan'));
SELECT tap._st268('p13p', tap._rearm268('a2680000-0000-4000-a000-000000000a02', 'aal2', tap._id268('rt'), 'ck268-p13-support'));
SELECT is(ARRAY[tap._fe268('p13s'), tap._fe268('p13a'), tap._fe268('p13f'), tap._fe268('p13p')],
          ARRAY['ERROR 42501|permission denied for function rearm_refund_execution',
                'ERROR 42501|permission denied for schema kernel',
                'ERROR 42501|insufficient_privilege: platform_risk or platform_admin required',
                'ERROR 42501|insufficient_privilege: platform_risk or platform_admin required'],
  'P13: the re-arm wall — service_role holds no EXECUTE, anon no schema USAGE, an aal2 fan and an aal2 platform_support operator are not platform_risk/platform_admin (O-11)');
SELECT tap._st268('p14a', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal1', tap._id268('rt'), 'ck268-p14-aal1'));
SELECT tap._st268('p14b', tap._rearm268('a2680000-0000-4000-a000-000000000a01', NULL, tap._id268('rt'), 'ck268-p14-noaal'));
SELECT is(ARRAY[tap._fe268('p14a'), tap._fe268('p14b')],
          ARRAY['ERROR P0001|step_up_required: a step-up (aal2) session is required to re-arm a parked refund',
                'ERROR P0001|step_up_unavailable: the session carries no aal claim'],
  'P14: a platform_admin at aal1 -> step_up_required; with no aal claim -> step_up_unavailable');
SELECT tap._st268('p15', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('r_man'), 'ck268-p15-manual'));
SELECT is(tap._fe268('p15'), 'ERROR P0001|precondition_failed: manual_record_not_rearmable (refund ' || tap._fe268('r_man') || ')',
  'P15: a manual row is not re-armable, even by an aal2 platform_admin');
SELECT tap._st268('p16r', tap._rrs268('pi_268_u', 're_268dash', 'succeeded', 500, NULL));
SELECT tap._st268('p16', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('ru'), 'ck268-p16-rearm'));
SELECT is(ARRAY[tap._fj268('park_u') ->> 'status', tap._fj268('p16r') ->> 'recorded', tap._fe268('p16')],
          ARRAY['ok', 'true', 'ERROR P0001|precondition_failed: unattributed_stripe_refunds (500 minor units on payment a2680000-0000-4000-a000-000000000702 are bound to no kernel refund)'],
  'P16: parked pending Ru on a payment carrying a 500 Dashboard refund bound to no kernel refund -> re-arm refused unattributed_stripe_refunds');
SELECT tap._st268('p23', tap._rearm268('a2680000-0000-4000-a000-000000000a03', 'aal2', tap._id268('rps'), 'ck268-p23-rearm'));
SELECT is(ARRAY[tap._fj268('p23') ->> 'status', tap._fj268('p23') ->> 'rearmed_status',
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_rearmed' AND subject_id = tap._id268('rps')
                    AND actor_identity = 'a2680000-0000-4000-a000-000000000a03')::text,
                tap._hold268(tap._id268('rps'))],
          ARRAY['ok', 'submitted', '1', '<null>'],
  'P23: an aal2 platform_risk identity re-arms Rps -> ok at submitted although PU still carries the unbound 500 (the money guard applies only to a pending row, whose reconcile cannot find a Dashboard refund); one rearmed row by that identity; the hold is gone');
-- Stripe money bound to no kernel refund on PV1-PV3: a pending and a requires_action observation (each also enters the
-- one-way record) and a one-way record with no observation at all (a legacy Dashboard refund)
SELECT tap._st268('p25r1', tap._rrs268('pi_268_v1', 're_268v1dash', 'pending', 300, NULL));
SELECT tap._st268('p25r2', tap._rrs268('pi_268_v2', 're_268v2dash', 'requires_action', 400, NULL));
SELECT tap._st268('p26r', tap._svc268($q$SELECT public.record_payment_refund('pi_268_v3', 're_268v3legacy', NULL, 600, 'dashboard')::text$q$));
SELECT tap._st268('p25a', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('rv1'), 'ck268-p25-rearm-1'));
SELECT tap._st268('p25b', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('rv2'), 'ck268-p25-rearm-2'));
SELECT tap._st268('p26', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('rv3'), 'ck268-p26-rearm'));
SELECT is(ARRAY[tap._fj268('park_v1') ->> 'status', tap._fj268('park_v2') ->> 'status', tap._fj268('p25r1') ->> 'recorded', tap._fj268('p25r2') ->> 'recorded',
                tap._fe268('p25a'), tap._fe268('p25b')],
          ARRAY['ok', 'ok', 'true', 'true',
                'ERROR P0001|precondition_failed: unattributed_stripe_refunds (300 minor units on payment a2680000-0000-4000-a000-000000000703 are bound to no kernel refund)',
                'ERROR P0001|precondition_failed: unattributed_stripe_refunds (400 minor units on payment a2680000-0000-4000-a000-000000000704 are bound to no kernel refund)'],
  'P25: parked pending Rv1 / Rv2 whose payments carry an in-flight Dashboard refund (Stripe pending / requires_action) bound to no kernel refund -> re-arm refused unattributed_stripe_refunds');
SELECT is(ARRAY[tap._fj268('park_v3') ->> 'status', tap._fj268('p26r') ->> 'recorded', tap._fe268('p26')],
          ARRAY['ok', 'true',
                'ERROR P0001|precondition_failed: unattributed_stripe_refunds (600 minor units on payment a2680000-0000-4000-a000-000000000705 are bound to no kernel refund)'],
  'P26: parked pending Rv3 whose payment carries a refund in the one-way record only (no Stripe state observed) -> re-arm refused unattributed_stripe_refunds');
SELECT tap._st268('p17', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('rp'), 'ck268-p17-rearm'));
SELECT is(ARRAY[tap._fj268('p17') ->> 'status',
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.execute_rearmed' AND subject_id = tap._id268('rp')
                    AND actor_identity = 'a2680000-0000-4000-a000-000000000a01')::text,
                tap._hold268(tap._id268('rp'))],
          ARRAY['ok', '1', '<null>'],
  'P17: an aal2 platform_admin re-arms Rp -> ok, one refund.execute_rearmed row by that admin, and the hold is gone');
SELECT tap._st268('p18', tap._claim268());
SELECT is(tap._mode268('p18', tap._id268('rp')), 'reconcile',
  'P18: the re-armed Rp is claimed in reconcile mode — never a blind create after the window');
SELECT is(tap._mode268('p18', tap._id268('rps')), 'reconcile',
  'P24: the re-armed Rps (submitted) is claimed again, in reconcile mode');
SELECT tap._st268('p19', tap._rearm268('a2680000-0000-4000-a000-000000000a01', 'aal2', tap._id268('rp'), 'ck268-p19-rearm'));
SELECT is(tap._fj268('p19') ->> 'status', 'noop_replay',
  'P19: re-arming the now-unheld Rp again is noop_replay');

-- ── Section W — claim mode by creation time (refunds-1 residual) ─────────────
-- direct pending rows on PP: Rw1 created 21 h ago, never claimed; Rw2 created 1 h ago, never claimed; Rw3 created
-- 21 h ago whose first (and only) claim was 1 h ago (its 900 s lease long expired)
SELECT tap._st268('rw1', tap._mkrefund268('a2680000-0000-4000-a000-000000000701', 700, 'pending', NULL, interval '21 hours', 'ck268-w-1'));
SELECT tap._st268('rw2', tap._mkrefund268('a2680000-0000-4000-a000-000000000701', 700, 'pending', NULL, interval '1 hour', 'ck268-w-2'));
SELECT tap._st268('rw3', tap._mkrefund268('a2680000-0000-4000-a000-000000000701', 700, 'pending', NULL, interval '21 hours', 'ck268-w-3'));
SELECT tap._mkclaim268(tap._id268('rw3'), interval '1 hour', 'pending', 1);
SELECT tap._st268('w', tap._claim268());
SELECT is(tap._mode268('w', tap._id268('rw1')), 'reconcile',
  'W1: a pending row created 21 h ago and never claimed is claimed in reconcile (a POST may exist with no claim row)');
SELECT is(tap._mode268('w', tap._id268('rw2')), 'create',
  'W2: a pending row created 1 h ago and never claimed is still claimed in create (every POST with its key is inside Stripe''s dedupe)');
SELECT is(tap._mode268('w', tap._id268('rw3')), 'reconcile',
  'W3: a pending row created 21 h ago whose first claim was 1 h ago is claimed in reconcile (creation, not the first claim, bounds the key''s first use)');

-- ── Section S — post-success failure (refunds-4) ─────────────────────────────
-- Rs: a delegated FULL refund of O3 (amount = payments.total 11000; request_order_refund auto-executed for a
-- platform_admin, voiding O3's atom), then submitted, observed succeeded, marked succeeded
SELECT tap._st268('s_rs', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         format('SELECT kernel.request_order_refund(%L, %L::uuid[], 11000, %L, %L)::text', 'a2680000-0000-4000-a000-000000000303',
                (SELECT array_agg(l.ticket_atom_id)::text FROM kernel.ticket_ownership_log l
                  WHERE l.cause_ref = 'a2680000-0000-4000-a000-000000000403' AND l.sequence = 1),
                'buyer_request', 'ck268-s-rs')));
SELECT tap._st268('r_s', tap._fj268('s_rs') ->> 'refund_id');
SELECT tap._st268('s1a', tap._mark268(tap._id268('r_s'), 'submitted', 're_268s', NULL));
SELECT tap._st268('s1b', tap._rrs268('pi_268_03', 're_268s', 'succeeded', 11000, NULL));
SELECT tap._st268('s1c', tap._mark268(tap._id268('r_s'), 'succeeded', 're_268s', NULL));
SELECT is(ARRAY[tap._fj268('s_rs') ->> 'status', tap._fj268('s1a') ->> 'status', tap._fj268('s1c') ->> 'status',
                (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('r_s')),
                (SELECT refund_succeeded_cents || '/' || total FROM public.payments WHERE id = 'a2680000-0000-4000-a000-000000000603')],
          ARRAY['executed', 'ok', 'ok', 'succeeded', '11000/11000'],
  'S1: setup — Rs submitted then succeeded (re_268s), Stripe recorded succeeded; refund_succeeded_cents = total');
SELECT tap._st268('s2', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.admin_refund('a2680000-0000-4000-a000-000000000603', '{}'::uuid[], 1, 'admin_action', 'ck268-s2-replacement')::text$q$));
SELECT is(tap._fe268('s2'), 'ERROR P0001|precondition_failed: over_refund (11000 + 1 > 11000)',
  'S2: before the failure a money-only replacement (kernel.admin_refund) is over_refund — Rs holds the whole payment');
-- S28's probe: the first verb call in this file; no settlement close (the only other taker of the seam lock) has run yet
SELECT tap._st268('s28a', tap._seam268('a2680000-0000-4000-a000-00000000000a')::text);
SELECT tap._st268('s3', tap._verb268('re_268s', 'webhook:evt_268_s0'));
SELECT tap._st268('s28b', tap._seam268('a2680000-0000-4000-a000-00000000000a')::text);
SELECT is(ARRAY[tap._fj268('s3') ->> 'status', (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('r_s'))],
          ARRAY['not_failed', 'succeeded'],
  'S3: the verb before any failure observation -> not_failed (Stripe says succeeded); Rs stays succeeded');
SELECT is(tap._err268(format('SELECT kernel.mark_refund_state(%L, ''failed'', ''re_268s'', ''x'', ''ck268-s4'')', tap._id268('r_s'))),
          'P0001|precondition_failed: refund_state_backwards (succeeded → failed)',
  'S4: mark_refund_state still refuses succeeded -> failed (refund_state_backwards; its direction check is unchanged)');
SELECT tap._st268('s5', tap._rrs268('pi_268_03', 're_268s', 'failed', 11000, 'expired_or_canceled_card'));
SELECT is(ARRAY[tap._fj268('s5') ->> 'recorded', (SELECT refund_failed_cents::text FROM public.payments WHERE id = 'a2680000-0000-4000-a000-000000000603')],
          ARRAY['true', '11000'],
  'S5: the webhook records the Stripe failure (expired_or_canceled_card); refund_failed_cents = total');
SELECT tap._st268('s6', tap._verb268('re_268s', 'webhook:evt_268_s'));
SELECT is(ARRAY[tap._fj268('s6') ->> 'status', tap._fj268('s6') ->> 'transition'], ARRAY['ok', 'succeeded_to_failed'],
  'S6: the verb converges Rs -> ok, succeeded_to_failed');
SELECT is((SELECT ARRAY[status, stripe_refund_ref] FROM kernel.refund WHERE refund_id = tap._id268('r_s')), ARRAY['failed', 're_268s'],
  'S7: Rs is failed and keeps its ref');
SELECT is((SELECT ARRAY[count(*)::text, min(reason_code), min(actor_identity::text), min(before ->> 'status'), min(after ->> 'command_key')]
             FROM kernel.admin_audit WHERE action = 'refund.failed_after_success' AND subject_id = tap._id268('r_s')),
          ARRAY['1', 'expired_or_canceled_card', ((repeat('0', 30) || 'f1')::uuid)::text, 'succeeded', 'webhook:evt_268_s'],
  'S8: one refund.failed_after_success row — reason from the RECORDED Stripe state, SYSTEM actor, before succeeded, the command key');
SELECT tap._st268('s9', tap._verb268('re_268s', 'webhook:evt_268_s'));
SELECT is(ARRAY[tap._fj268('s9') ->> 'status',
                (SELECT count(*) FROM kernel.admin_audit WHERE action = 'refund.failed_after_success' AND subject_id = tap._id268('r_s'))::text],
          ARRAY['noop_replay', '1'],
  'S9: the replay is noop_replay; still one audit row');
SELECT tap._st268('s10o', tap._as268('a2680000-0000-4000-a000-000000000a05', NULL,
         $q$SELECT venue.open_settlement('a2680000-0000-4000-a000-00000000000a', 'a2680000-0000-4000-a000-0000000000a1', 'a2680000-0000-4000-a000-0000000000e3', '{}'::jsonb, 'ck268-open-e3')::text$q$));
SELECT tap._st268('s10c', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         format('SELECT kernel.close_settlement(%L, %L)::text', tap._fj268('s10o') ->> 'settlement_id', 'ck268-close-e3')));
SELECT is(ARRAY[tap._fj268('s10c') ->> 'status',
                (SELECT coalesce(sum(amount_minor), 0)::text FROM venue.settlement_line WHERE cause = 'primary_sale' AND cause_ref = 'a2680000-0000-4000-a000-000000000303'),
                (SELECT count(*)::text FROM venue.settlement_line WHERE cause = 'refund_void' AND cause_ref = tap._id268('r_s'))],
          ARRAY['ok', '10000', '0'],
  'S10: the real close of E3 books O3''s primary_sale +10000 and no refund_void for the failed Rs (the 093:358 rule)');
SELECT tap._st268('s11', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.admin_refund('a2680000-0000-4000-a000-000000000603', '{}'::uuid[], 1, 'admin_action', 'ck268-s11-replacement')::text$q$));
SELECT is(ARRAY[tap._fj268('s11') ->> 'status',
                tap._js268(tap._val268(format('SELECT kernel.get_refund_execution_context(%L)::text', tap._fj268('s11') ->> 'refund_id'))) ->> 'prior_non_failed_minor'],
          ARRAY['ok', '0'],
  'S11: after the failure the same money-only replacement is ok, and its context sees prior_non_failed_minor 0 (the failed row frees its headroom)');
SELECT is(ARRAY[(SELECT status FROM venue."order" WHERE order_id = 'a2680000-0000-4000-a000-000000000303'),
                (SELECT string_agg(t.state, ',') FROM kernel.ticket_ownership_log l JOIN kernel.tickets t ON t.ticket_atom_id = l.ticket_atom_id
                  WHERE l.cause_ref = 'a2680000-0000-4000-a000-000000000403' AND l.sequence = 1)],
          ARRAY['refunded', 'voided'],
  'S12: O3 is still refunded and its atom still voided (the verb records exposure; it repairs nothing)');
SELECT is(ARRAY[(tap._fj268('s6') -> 'atoms_voided' = (SELECT jsonb_agg(l.ticket_atom_id ORDER BY l.ticket_atom_id) FROM kernel.ticket_ownership_log l
                                                         WHERE l.cause = 'refund_void' AND l.cause_ref = tap._id268('r_s')))::text,
                (jsonb_array_length(coalesce(tap._fj268('s6') -> 'atoms_voided', '[]'::jsonb)) >= 1)::text,
                tap._fj268('s6') ->> 'settlement_review_required'],
          ARRAY['true', 'true', 'false'],
  'S13: S6''s atoms_voided is exactly O3''s refund_void atoms (non-empty); with no line, obligation, resale or commission, settlement_review_required is false');
SELECT tap._st268('s14n', (SELECT count(*)::text FROM kernel.admin_audit));
SELECT tap._st268('s14', tap._verb268('re_268nobody', 'webhook:evt_268_nb'));
SELECT is(ARRAY[tap._fj268('s14') ->> 'status', ((SELECT count(*) FROM kernel.admin_audit) - tap._fe268('s14n')::bigint)::text],
          ARRAY['not_bound', '0'],
  'S14: a ref bound to no kernel refund -> not_bound, and nothing is written');
-- the S direct rows (158's shape) on PS, each moved to submitted through mark_refund_state
SELECT tap._st268('r' || x, tap._mkrefund268('a2680000-0000-4000-a000-000000000711', 1000, 'pending', NULL, interval '2 hours', 'ck268-s-' || x))
  FROM unnest(ARRAY['b', 'k', 'x', 'a', 'f', 'g', 'h', 'i', 'j']) x;
SELECT tap._st268('sub_' || x, tap._mark268(tap._id268('r' || x), 'submitted', 're_268' || x, NULL)) FROM unnest(ARRAY['b', 'k', 'x', 'a', 'f', 'g', 'h', 'i', 'j']) x;
SELECT tap._st268('s15r', tap._rrs268('pi_268_s', 're_268b', 'failed', 1000, NULL));
SELECT tap._st268('s15', tap._verb268('re_268b', 'webhook:evt_268_b'));
SELECT is(ARRAY[tap._fj268('sub_b') ->> 'status', tap._fj268('s15') ->> 'status', tap._fj268('s15') ->> 'transition', tap._fj268('s15') ->> 'failure_code',
                (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('rb')),
                (SELECT count(*)::text FROM kernel.admin_audit WHERE action = 'refund.state_sync' AND subject_id = tap._id268('rb') AND reason_code = 'stripe_refund_failed')],
          ARRAY['ok', 'ok', 'submitted_to_failed', 'stripe_refund_failed', 'failed', '1'],
  'S15: submitted arm — a failed observation with no failure_reason -> submitted_to_failed with stripe_refund_failed, through mark_refund_state (its refund.state_sync row)');
SELECT tap._st268('s16r', tap._rrs268('pi_268_s', 're_268k', 'canceled', 1000, 'merchant_request'));
SELECT tap._st268('s16', tap._verb268('re_268k', 'webhook:evt_268_k'));
SELECT is(ARRAY[tap._fj268('s16') ->> 'status', tap._fj268('s16') ->> 'failure_code'], ARRAY['ok', 'refund_canceled'],
  'S16: a canceled observation maps to refund_canceled unconditionally (its failure_reason merchant_request is not the code)');
SELECT tap._st268('s17r', tap._rrs268('pi_268_y', 're_268x', 'failed', 1000, NULL));
SELECT tap._st268('s17', tap._verb268('re_268x', 'webhook:evt_268_x'));
SELECT is(tap._fe268('s17'), 'ERROR P0001|conflict_locked: refund_payment_mismatch (re_268x is observed on payment a2680000-0000-4000-a000-000000000712; refund '
                             || tap._fe268('rx') || ' is on payment a2680000-0000-4000-a000-000000000711)',
  'S17: the observation sits on another payment -> conflict_locked refund_payment_mismatch, never a convergence');
SELECT tap._st268('s18r', tap._rrs268('pi_268_s', 're_268a', 'failed', 900, NULL));
SELECT tap._st268('s18', tap._verb268('re_268a', 'webhook:evt_268_a'));
SELECT is(tap._fe268('s18'), 'ERROR P0001|conflict_locked: refund_amount_mismatch (900 observed, 1000 recorded)',
  'S18: the observed amount differs from the row''s -> conflict_locked refund_amount_mismatch');
-- Rn: a pending row carrying a ref — not producible through mark_refund_state (it writes the ref only with submitted)
SELECT tap._st268('rn', tap._mkrefund268('a2680000-0000-4000-a000-000000000711', 1000, 'pending', 're_268n', interval '2 hours', 'ck268-s-n'));
SELECT tap._st268('s19', tap._verb268('re_268n', 'webhook:evt_268_n'));
SELECT is(tap._fe268('s19'), 'ERROR P0001|precondition_failed: refund_not_submitted (refund ' || tap._fe268('rn') || ' is pending)',
  'S19: a pending row that carries a ref -> precondition_failed refund_not_submitted');
-- Rl: a delegated partial refund of O4 (3000, money only), succeeded, then BOOKED by the real close of E4, then failed
SELECT tap._st268('s_rl', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.request_order_refund('a2680000-0000-4000-a000-000000000304', '{}'::uuid[], 3000, 'buyer_request', 'ck268-s-rl')::text$q$));
SELECT tap._st268('r_l', tap._fj268('s_rl') ->> 'refund_id');
SELECT tap._st268('s20a', tap._mark268(tap._id268('r_l'), 'submitted', 're_268l', NULL));
SELECT tap._st268('s20b', tap._mark268(tap._id268('r_l'), 'succeeded', 're_268l', NULL));
SELECT tap._st268('s20o', tap._as268('a2680000-0000-4000-a000-000000000a05', NULL,
         $q$SELECT venue.open_settlement('a2680000-0000-4000-a000-00000000000a', 'a2680000-0000-4000-a000-0000000000a1', 'a2680000-0000-4000-a000-0000000000e4', '{}'::jsonb, 'ck268-open-e4')::text$q$));
SELECT tap._st268('s20c', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         format('SELECT kernel.close_settlement(%L, %L)::text', tap._fj268('s20o') ->> 'settlement_id', 'ck268-close-e4')));
SELECT tap._st268('s20r', tap._rrs268('pi_268_04', 're_268l', 'failed', 3000, 'lost_or_stolen_card'));
SELECT tap._st268('s20', tap._verb268('re_268l', 'webhook:evt_268_l'));
SELECT is(ARRAY[tap._fj268('s20c') ->> 'status', tap._fj268('s20') ->> 'transition',
                (tap._fj268('s20') #>> '{refund_void_line,settlement_id}' = tap._fj268('s20o') ->> 'settlement_id')::text,
                tap._fj268('s20') #>> '{refund_void_line,amount_minor}', tap._fj268('s20') #>> '{refund_void_line,settlement_status}',
                tap._fj268('s20') ->> 'settlement_review_required',
                (SELECT count(*) || '/' || coalesce(sum(amount_minor), 0) FROM venue.settlement_line WHERE cause = 'refund_void' AND cause_ref = tap._id268('r_l'))],
          ARRAY['ok', 'succeeded_to_failed', 'true', '-3000', 'closed', 'true', '1/-3000'],
  'S20: a booked refund_void line — the verb reports its settlement, amount -3000 and closed status, settlement_review_required true; the line stays (one, unchanged)');
-- Rc: kernel.admin_refund on O5 (admin_action, money only), succeeded, a refund_clawback obligation recorded, then failed
SELECT tap._st268('s_rc', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.admin_refund('a2680000-0000-4000-a000-000000000605', '{}'::uuid[], 2000, 'admin_action', 'ck268-s-rc')::text$q$));
SELECT tap._st268('r_c', tap._fj268('s_rc') ->> 'refund_id');
SELECT tap._st268('s21a', tap._mark268(tap._id268('r_c'), 'submitted', 're_268c', NULL));
SELECT tap._st268('s21b', tap._mark268(tap._id268('r_c'), 'succeeded', 're_268c', NULL));
SELECT tap._st268('s21o', tap._val268(format('SELECT kernel.record_identity_obligation(%L, %L, %L, NULL, 2000, %L, %L)::text',
         'a2680000-0000-4000-a000-000000000101', 'refund_clawback', tap._id268('r_c'), 'refund_clawback', 'ck268-s21-clawback')));
SELECT tap._st268('s21r', tap._rrs268('pi_268_05', 're_268c', 'failed', 2000, NULL));
SELECT tap._st268('s21', tap._verb268('re_268c', 'webhook:evt_268_c'));
SELECT is(ARRAY[tap._fj268('s21o') ->> 'status', tap._fj268('s21') #>> '{refund_clawback_obligation,status}',
                (SELECT status FROM kernel.identity_obligation WHERE origin_kind = 'refund_clawback' AND origin_ref = tap._id268('r_c')),
                tap._fj268('s21') ->> 'settlement_review_required'],
          ARRAY['ok', 'outstanding', 'outstanding', 'true'],
  'S21: a refund_clawback obligation is reported (outstanding) and left outstanding; settlement_review_required true');
SELECT tap._st268('s22r', tap._rrs268('pi_268_s', 're_268f', 'pending', 1000, NULL));
SELECT tap._st268('s22n', (SELECT count(*)::text FROM kernel.admin_audit WHERE subject_id = tap._id268('rf')));
SELECT tap._st268('s22', tap._verb268('re_268f', 'webhook:evt_268_f'));
SELECT is(ARRAY[tap._fj268('s22') ->> 'status', (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('rf')),
                ((SELECT count(*) FROM kernel.admin_audit WHERE subject_id = tap._id268('rf')) - tap._fe268('s22n')::bigint)::text],
          ARRAY['in_flight', 'submitted', '0'],
  'S22: Stripe still pending -> in_flight with no write');
SELECT tap._st268('s23r', tap._rrs268('pi_268_s', 're_268g', 'failed', 1000, NULL));
SELECT tap._st268('s23', tap._mark268(tap._id268('rg'), 'succeeded', 're_268g', NULL));
SELECT is(ARRAY[tap._fe268('s23'), (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('rg'))],
          ARRAY['ERROR P0001|precondition_failed: refund_failed_at_stripe (re_268g is failed)', 'submitted'],
  'S23: mark_refund_state refuses succeeded for a ref Stripe recorded failed (refund_failed_at_stripe); the row stays submitted');
SELECT tap._st268('s24r', tap._rrs268('pi_268_s', 're_268h', 'succeeded', 1000, NULL));
SELECT tap._st268('s24', tap._mark268(tap._id268('rh'), 'succeeded', 're_268h', NULL));
SELECT is(ARRAY[tap._fj268('s24') ->> 'status', (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('rh'))], ARRAY['ok', 'succeeded'],
  'S24: the guard stays quiet for a ref Stripe recorded succeeded — marking it succeeded is ok');
SELECT ok(coalesce((SELECT strpos(p.prosrc, 'settlement.seam.org:') > 0 AND strpos(p.prosrc, 'for update') > strpos(p.prosrc, 'settlement.seam.org:')
                      FROM pg_proc p WHERE p.oid = to_regprocedure('kernel.record_refund_stripe_failure(text,text)')), false),
  'S25: the verb takes the org settlement seam lock before the kernel.refund row lock (the close''s lock order)');
-- Ri: submitted, Stripe recorded succeeded, marked succeeded, then Stripe recorded requires_action (a bank refund after
-- success; 150 orders no transition out of succeeded) -> the verb must not converge it (§6 refunds-4 #5, O-6)
SELECT tap._st268('s26r1', tap._rrs268('pi_268_s', 're_268i', 'succeeded', 1000, NULL));
SELECT tap._st268('s26m', tap._mark268(tap._id268('ri'), 'succeeded', 're_268i', NULL));
SELECT tap._st268('s26r2', tap._rrs268('pi_268_s', 're_268i', 'requires_action', 1000, NULL));
SELECT tap._st268('s26n', (SELECT count(*)::text FROM kernel.admin_audit WHERE subject_id = tap._id268('ri')));
SELECT tap._st268('s26', tap._verb268('re_268i', 'webhook:evt_268_i'));
SELECT is(ARRAY[tap._fj268('s26m') ->> 'status', tap._fj268('s26r2') ->> 'recorded', tap._fj268('s26') ->> 'status', tap._fj268('s26') ->> 'stripe_status',
                (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('ri')),
                ((SELECT count(*) FROM kernel.admin_audit WHERE subject_id = tap._id268('ri')) - tap._fe268('s26n')::bigint)::text],
          ARRAY['ok', 'true', 'in_flight', 'requires_action', 'succeeded', '0'],
  'S26: a succeeded row whose ref Stripe then records requires_action -> in_flight with no write; the row stays succeeded and keeps its headroom (O-6)');
SELECT tap._st268('s27r', tap._rrs268('pi_268_s', 're_268j', 'canceled', 1000, 'merchant_request'));
SELECT tap._st268('s27', tap._mark268(tap._id268('rj'), 'succeeded', 're_268j', NULL));
SELECT is(ARRAY[tap._fj268('s27r') ->> 'recorded', tap._fe268('s27'), (SELECT status FROM kernel.refund WHERE refund_id = tap._id268('rj'))],
          ARRAY['true', 'ERROR P0001|precondition_failed: refund_failed_at_stripe (re_268j is canceled)', 'submitted'],
  'S27: mark_refund_state refuses succeeded for a ref Stripe recorded canceled (refund_failed_at_stripe); the row stays submitted (I-R1)');
SELECT is(ARRAY[tap._fe268('s28a'), tap._fe268('s28b')], ARRAY['false', 'true'],
  'S28: this backend does not hold Org 268''s settlement seam lock (advisory hashtext(''settlement.seam.org:''||org)) before S3''s verb call and holds it after (the verb takes the lock the close takes; I-S1)');
-- Rp: a ref with no re_ prefix, stored by the column's only writer. kernel.admin_refund on O6 (admin_action, money only),
-- moved to submitted and then succeeded through kernel.mark_refund_state with ref pyr_268_shape (it stores any non-null
-- ref), Stripe recorded succeeded, a refund_clawback obligation recorded, then Stripe records the refund failed
SELECT tap._st268('s_rp', tap._as268('a2680000-0000-4000-a000-000000000a01', NULL,
         $q$SELECT kernel.admin_refund('a2680000-0000-4000-a000-000000000606', '{}'::uuid[], 2000, 'admin_action', 'ck268-s-rp')::text$q$));
SELECT tap._st268('r_p', tap._fj268('s_rp') ->> 'refund_id');
SELECT tap._st268('s29a', tap._mark268(tap._id268('r_p'), 'submitted', 'pyr_268_shape', NULL));
SELECT tap._st268('s29b', tap._rrs268('pi_268_06', 'pyr_268_shape', 'succeeded', 2000, NULL));
SELECT tap._st268('s29c', tap._mark268(tap._id268('r_p'), 'succeeded', 'pyr_268_shape', NULL));
SELECT tap._st268('s29o', tap._val268(format('SELECT kernel.record_identity_obligation(%L, %L, %L, NULL, 2000, %L, %L)::text',
         'a2680000-0000-4000-a000-000000000101', 'refund_clawback', tap._id268('r_p'), 'refund_clawback', 'ck268-s29-clawback')));
SELECT tap._st268('s29r', tap._rrs268('pi_268_06', 'pyr_268_shape', 'failed', 2000, 'declined'));
SELECT is(ARRAY[tap._fj268('s_rp') ->> 'status', tap._fj268('s29a') ->> 'status', tap._fj268('s29b') ->> 'recorded', tap._fj268('s29c') ->> 'status',
                tap._fj268('s29o') ->> 'status', tap._fj268('s29r') ->> 'recorded',
                (SELECT status || '|' || stripe_refund_ref FROM kernel.refund WHERE refund_id = tap._id268('r_p'))],
          ARRAY['ok', 'ok', 'true', 'ok', 'ok', 'true', 'succeeded|pyr_268_shape'],
  'S29: setup — Rp (admin_refund on O6) carries pyr_268_shape, written by mark_refund_state (submitted, then succeeded); clawback recorded; Stripe recorded succeeded, then failed (declined)');
SELECT tap._st268('s30', tap._verb268('pyr_268_shape', 'webhook:evt_268_p'));
SELECT is(ARRAY[tap._fj268('s30') ->> 'status', tap._fj268('s30') ->> 'transition', tap._fj268('s30') ->> 'failure_code',
                (tap._fj268('s30') ->> 'refund_id' = tap._fe268('r_p'))::text,
                (SELECT status || '|' || stripe_refund_ref FROM kernel.refund WHERE refund_id = tap._id268('r_p'))],
          ARRAY['ok', 'succeeded_to_failed', 'declined', 'true', 'failed|pyr_268_shape'],
  'S30: a stored ref without the re_ prefix converges like S6 — ok, succeeded_to_failed, code from the recorded state; Rp is failed and keeps its ref');
SELECT is((SELECT ARRAY[count(*)::text, min(reason_code), min(actor_identity::text), min(before ->> 'status'), min(before ->> 'stripe_refund_ref'),
                        min(after ->> 'status'), min(after ->> 'command_key')]
             FROM kernel.admin_audit WHERE action = 'refund.failed_after_success' AND subject_id = tap._id268('r_p')),
          ARRAY['1', 'declined', ((repeat('0', 30) || 'f1')::uuid)::text, 'succeeded', 'pyr_268_shape', 'failed', 'webhook:evt_268_p'],
  'S31: one refund.failed_after_success row for Rp — reason from the recorded state, SYSTEM actor, before succeeded with the stored ref, after failed, the command key');
SELECT is(ARRAY[tap._fj268('s30') #>> '{refund_clawback_obligation,status}',
                (SELECT status FROM kernel.identity_obligation WHERE origin_kind = 'refund_clawback' AND origin_ref = tap._id268('r_p')),
                tap._fj268('s30') ->> 'settlement_review_required',
                (SELECT after ->> 'settlement_review_required' FROM kernel.admin_audit
                  WHERE action = 'refund.failed_after_success' AND subject_id = tap._id268('r_p')),
                tap._fj268('s30') ->> 'order_id', tap._fj268('s30') ->> 'payment_id', tap._fj268('s30') ->> 'atoms_voided'],
          ARRAY['outstanding', 'outstanding', 'true', 'true', 'a2680000-0000-4000-a000-000000000306', 'a2680000-0000-4000-a000-000000000606', '[]'],
  'S32: the settlement-review residue is computed for Rp as in S21 — clawback reported and left outstanding, settlement_review_required true in the verdict and the audit row, O6''s order and payment, no atoms');
-- Rpc: a direct pending row (158's shape) on PS, moved to submitted by mark_refund_state with pyr_268_shape_c; Stripe cancels it
SELECT tap._st268('rpc', tap._mkrefund268('a2680000-0000-4000-a000-000000000711', 1000, 'pending', NULL, interval '2 hours', 'ck268-s-pc'));
SELECT tap._st268('s33a', tap._mark268(tap._id268('rpc'), 'submitted', 'pyr_268_shape_c', NULL));
SELECT tap._st268('s33r', tap._rrs268('pi_268_s', 'pyr_268_shape_c', 'canceled', 1000, 'merchant_request'));
SELECT tap._st268('s33', tap._verb268('pyr_268_shape_c', 'webhook:evt_268_pc'));
SELECT is(ARRAY[tap._fj268('s33a') ->> 'status', tap._fj268('s33') ->> 'status', tap._fj268('s33') ->> 'transition', tap._fj268('s33') ->> 'failure_code',
                (SELECT status || '|' || stripe_refund_ref FROM kernel.refund WHERE refund_id = tap._id268('rpc')),
                (SELECT count(*)::text FROM kernel.admin_audit WHERE action = 'refund.state_sync' AND subject_id = tap._id268('rpc') AND reason_code = 'refund_canceled')],
          ARRAY['ok', 'ok', 'submitted_to_failed', 'refund_canceled', 'failed|pyr_268_shape_c', '1'],
  'S33: the submitted arm with a stored ref without the re_ prefix — canceled -> submitted_to_failed, refund_canceled, through mark_refund_state');
SELECT tap._st268('s34n', (SELECT count(*)::text FROM kernel.admin_audit));
SELECT tap._st268('s34a', tap._verb268(NULL, 'webhook:evt_268_null'));
SELECT tap._st268('s34b', tap._verb268('', 'webhook:evt_268_empty'));
SELECT tap._st268('s34c', tap._verb268('   ', 'webhook:evt_268_blank'));
SELECT is(ARRAY[tap._fe268('s34a'), tap._fe268('s34b'), tap._fe268('s34c'), ((SELECT count(*) FROM kernel.admin_audit) - tap._fe268('s34n')::bigint)::text],
          ARRAY['ERROR P0001|invalid_input: stripe_refund_ref is mandatory', 'ERROR P0001|invalid_input: stripe_refund_ref is mandatory',
                'ERROR P0001|invalid_input: stripe_refund_ref is mandatory', '0'],
  'S34: a NULL, empty or blank ref is still refused (invalid_input) and nothing is written');

-- ── Section E — ops.executor_claim on refunded payments (refunds-5) ──────────
SELECT tap._st268('e1p', tap._rrs268('pi_268_e5', 're_268e5', 'pending', 11000, NULL));
SELECT tap._st268('e1f', tap._rrs268('pi_268_e5', 're_268e5', 'failed', 11000, 'insufficient_funds'));
SELECT tap._st268('e1', tap._xclaim268(tap._id268('a5')));
SELECT is(ARRAY[tap._fj268('e1') ->> 'status', tap._fj268('e1') ->> 'reason', tap._fj268('e1') #>> '{detail,succeeded_cents}',
                tap._fj268('e1') #>> '{detail,failed_cents}', tap._fj268('e1') #>> '{detail,payment_status}'],
          ARRAY['refused', 'refund_state_unresolved', '0', '11000', 'refunded'],
  'E1: PE5 refunded by a refund Stripe then failed; a fresh action -> refund_state_unresolved, detail succeeded 0 / failed 11000');
SELECT is((SELECT ARRAY[a.state, a.attempt::text,
                        (SELECT count(*) FROM ops.audit au WHERE au.action = 'action.claim.refund_execute' AND au.action_id = a.id)::text]
             FROM ops.action a WHERE a.id = tap._id268('a5')),
          ARRAY['processing', '0', '0'],
  'E2: the refused claim wrote nothing — still processing, attempt 0, no claim audit row');
SELECT tap._st268('e3a', tap._xclaim268(tap._id268('a6')));
SELECT tap._st268('e3o', tap._svc268(format('SELECT ops.record_action_outcome(%L, %L, %L::jsonb, NULL, NULL)::text', tap._id268('a6'), 'processing', '{"stripe_request_started_at":"t"}')));
SELECT tap._st268('e3p', tap._rrs268('pi_268_e6', 're_268e6', 'pending', 11000, NULL));
SELECT tap._st268('e3f', tap._rrs268('pi_268_e6', 're_268e6', 'failed', 11000, 'insufficient_funds'));
UPDATE ops.action SET claimed_until = now() - interval '1 minute' WHERE id = tap._id268('a6');
SELECT tap._st268('e3', tap._xclaim268(tap._id268('a6')));
SELECT is(ARRAY[tap._fj268('e3a') ->> 'status', tap._fj268('e3o') ->> 'status', tap._fj268('e3') ->> 'status',
                tap._fj268('e3') ->> 'previously_sent', tap._fj268('e3') ->> 'amount_cents'],
          ARRAY['claimed', 'ok', 'claimed', 'true', '11000'],
  'E3: a previously-sent action (claimed while succeeded, request started) on a payment since refunded-then-failed is re-claimed — the handler lists before it POSTs');
SELECT tap._st268('e4r', tap._rrs268('pi_268_e7', 're_268e7', 'succeeded', 11000, NULL));
SELECT tap._st268('e4', tap._xclaim268(tap._id268('a7')));
SELECT is(ARRAY[tap._fj268('e4') ->> 'status', tap._fj268('e4') ->> 'reason', tap._fj268('e4') ->> 'stripe_refund_id'],
          ARRAY['refused', 'already_refunded_locally', 're_268e7'],
  'E4: Stripe-confirmed succeeded refunds cover the total -> already_refunded_locally with the stripe_refund_id');
SELECT tap._st268('e5r', tap._svc268($q$SELECT public.record_payment_refund('pi_268_e8', 're_268legacy', NULL, NULL, 'dashboard')::text$q$));
SELECT tap._st268('e5', tap._xclaim268(tap._id268('a8')));
SELECT is(ARRAY[tap._fj268('e5r') ->> 'status', tap._fj268('e5') ->> 'reason', tap._fj268('e5') #>> '{detail,unobserved_cents}'],
          ARRAY['refunded', 'refund_state_unobserved', '11000'],
  'E5: a legacy full refund recorded with no Stripe state -> a fresh action (its result NULL, as a direct insert leaves it) is refund_state_unobserved, unobserved_cents 11000 (O-3)');
SELECT tap._st268('e6r', tap._svc268($q$SELECT public.record_payment_refund('pi_268_e9', NULL, 'dp_268', NULL, 'dispute_lost')::text$q$));
SELECT tap._st268('e6', tap._xclaim268(tap._id268('a9')));
SELECT is(ARRAY[tap._fj268('e6r') ->> 'status', tap._fj268('e6') ->> 'reason', tap._fj268('e6') #>> '{detail,chargeback_cents}'],
          ARRAY['refunded', 'charged_back', '11000'],
  'E6: a lost chargeback covers the payment -> charged_back, chargeback_cents 11000');
SELECT tap._st268('e7', tap._xclaim268(tap._id268('a11')));
SELECT is(ARRAY[tap._fj268('e7') ->> 'status',
                (SELECT string_agg(k, ',' ORDER BY k COLLATE "C") FROM jsonb_object_keys(tap._fj268('e7')) k)],
          ARRAY['claimed', 'action_id,amount_cents,attempt,currency,payment_id,payment_total_cents,previously_sent,provider_ref,reason_code,status,stripe_livemode,stripe_payment_intent_id'],
  'E7: a plain succeeded payment is claimed exactly as before — the twelve keys of 118''s payload');
SELECT tap._st268('e8', tap._xclaim268(tap._id268('a12')));
SELECT is(ARRAY[tap._fj268('e8') ->> 'status', tap._fj268('e8') ->> 'reason'], ARRAY['refused', 'payment_not_refundable'],
  'E8: a failed payment with a previously-sent action -> payment_not_refundable (previously-sent admits only a refunded payment)');
SELECT tap.logout();
SELECT is(tap._err268(format('SELECT ops.executor_claim(%L)', tap._id268('a11'))), '42501|insufficient_privilege: service_role only',
  'E9: after tap.logout (claims '''') ops.executor_claim is refused 42501');
SELECT tap._st268('e10a', tap._xclaim268(tap._id268('a10')));
SELECT tap._st268('e10o', tap._svc268(format('SELECT ops.record_action_outcome(%L, %L, %L::jsonb, NULL, NULL)::text', tap._id268('a10'), 'processing', '{"stripe_request_started_at":"t"}')));
SELECT tap._st268('e10r', tap._svc268($q$SELECT public.record_payment_refund('pi_268_e10', 're_268e10', NULL, NULL, 'dashboard')::text$q$));
UPDATE ops.action SET claimed_until = now() - interval '1 minute' WHERE id = tap._id268('a10');
SELECT tap._st268('e10', tap._xclaim268(tap._id268('a10')));
SELECT is(ARRAY[tap._fj268('e10a') ->> 'status', tap._fj268('e10r') ->> 'status', tap._fj268('e10') ->> 'status', tap._fj268('e10') ->> 'previously_sent'],
          ARRAY['claimed', 'refunded', 'claimed', 'true'],
  'E10: a previously-sent action whose payment later gained an unobserved full refund is still re-claimed (the unobserved refusal sits below the previously-sent admit)');
SELECT tap._st268('a13', tap._mkaction268('k268-e-13-action', 'a2680000-0000-4000-a000-000000000813', 1,
         jsonb_build_object('status', 'processing', 'handoff', 'ops-refund-execute', 'amount_cents', 11000, 'currency', 'usd')));
SELECT tap._st268('e11', tap._xclaim268(tap._id268('a13')));
SELECT is(ARRAY[tap._fj268('e11') ->> 'status', tap._fj268('e11') ->> 'reason', tap._fj268('e11') ->> 'payment_status'],
          ARRAY['refused', 'payment_not_refundable', 'refunded'],
  'E11: a previously-sent action (attempt 1) on a refunded payment that has no PaymentIntent -> payment_not_refundable (the previously-sent admit still needs a PI)');
-- PE14: a Stripe-confirmed partial refund (5000 succeeded) and a lost chargeback (6000) together cover the total
SELECT tap._st268('e12r', tap._rrs268('pi_268_e14', 're_268e14', 'succeeded', 5000, NULL));
SELECT tap._st268('e12d', tap._svc268($q$SELECT public.record_payment_refund('pi_268_e14', NULL, 'dp_268e14', 6000, 'dispute_lost')::text$q$));
SELECT tap._st268('a14', tap._mkaction268('k268-e-14-action', 'a2680000-0000-4000-a000-000000000814', 0,
         jsonb_build_object('status', 'processing', 'handoff', 'ops-refund-execute', 'amount_cents', 11000, 'currency', 'usd')));
SELECT tap._st268('e12', tap._xclaim268(tap._id268('a14')));
SELECT is(ARRAY[tap._fj268('e12r') ->> 'recorded', tap._fj268('e12d') ->> 'status', tap._fj268('e12') ->> 'status', tap._fj268('e12') ->> 'reason',
                tap._fj268('e12') #>> '{detail,succeeded_cents}', tap._fj268('e12') #>> '{detail,chargeback_cents}'],
          ARRAY['true', 'refunded', 'refused', 'charged_back', '5000', '6000'],
  'E12: a succeeded partial refund plus a lost chargeback that together cover the total -> charged_back (succeeded 5000 + chargeback 6000)');

SELECT * FROM finish();
ROLLBACK;
