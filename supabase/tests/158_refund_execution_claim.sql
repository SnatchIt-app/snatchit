-- ============================================================================
-- 158_refund_execution_claim.sql — package 093 slice 10i.
--
-- SUBJECT: kernel.claim_refunds_for_execution(integer, integer) — the refund
--   executor's WORK LIST, and the reason it is a LEASED CLAIM rather than the
--   `kernel.list_pending_refunds(integer)` E4 §3 sketched.
--
-- Frozen sources: ruling D3 (PRIMARY_TICKETING_OWNER_RATIFICATION.md:327) ·
--   PFA-21 (service_role: schema USAGE only, no table/DML grants) · PFA-23 ·
--   docs/phase2/_impl/E4_refund_executor.md §3/§5 ·
--   docs/phase2/_impl/H1_refund_architecture.md · 064_webhook_event_claim_lease
--   (the house claim idiom) · 085 PART 2 (kernel.refund) · 077:236-264
--   (kernel.admin_audit is append-only and UPDATE/DELETE-revoked).
--
-- THE PROPERTY THIS FILE EXISTS TO PIN: a refund worker holds service_role and
--   nothing else. It must be structurally incapable of choosing WHICH refund it
--   executes, WHOSE payment it touches, HOW MUCH it moves, or WHETHER a Stripe
--   idempotency key is still a valid dedup token. Every assertion below is a
--   different way of attacking one of those four.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixtures are written as
--   postgres; every role boundary is exercised through tap.login*/logout, never
--   by asserting a grant catalogue alone where behaviour can be observed.
-- ============================================================================
BEGIN;
SELECT plan(39);

SELECT tap.seed_core();

CREATE TABLE tap.memo_158 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._st158(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_158 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fe158(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_158 WHERE k = $1 $m$;

-- A refund row, born exactly as kernel.refund_primary_order (085:599),
-- kernel.admin_refund (085:706) and catalog.cancel_event (088:1664/1716/1774)
-- all bear one: `pending`, no ref. p_age backdates created_at so the
-- oldest-money-first ordering is observable.
CREATE FUNCTION tap._mkrefund158(p_payment uuid, p_amount int, p_status text,
                                 p_ref text, p_age interval)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor,
                             status, stripe_refund_ref, idempotency_key, created_at, updated_at)
  values (v_id, p_payment, 'buyer_request', p_amount, p_status, p_ref,
          'ck158-' || v_id::text, now() - p_age, now() - p_age);
  return v_id;
end $f$;

-- A PRIOR execution attempt, i.e. the durable fact that this refund's Stripe
-- idempotency key was first used at a given instant. admin_audit is append-only
-- (077:261-264), so a claim's age can only ever be established by INSERT —
-- which is exactly why the lease is trustworthy.
CREATE FUNCTION tap._mkclaim158(p_refund uuid, p_age interval, p_mode text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id,
                                  reason_code, before, after, occurred_at, created_at)
  values ('00000000-0000-0000-0000-0000000000f1', 'refund.execute_claim', 'refund',
          p_refund, p_mode, '{}'::jsonb, '{}'::jsonb, now() - p_age, now() - p_age);
$f$;

CREATE FUNCTION tap._claim158(p_limit int, p_lease int) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$
  select kernel.claim_refunds_for_execution(p_limit, p_lease) $f$;

-- Did this claim batch contain this refund, and under which mode?
CREATE FUNCTION tap._mode158(p_batch jsonb, p_refund uuid) RETURNS text
LANGUAGE sql IMMUTABLE AS $f$
  select e ->> 'execution_mode' from jsonb_array_elements(p_batch -> 'refunds') e
   where e ->> 'refund_id' = p_refund::text $f$;

-- ============================================================================
-- SECTION A — THE VERB'S SHAPE AND ITS WALL
--   A machine verb on the money execution path. If any of these five flip, the
--   worker has gained a capability nobody granted it.
-- ============================================================================
SELECT has_function('kernel'::name, 'claim_refunds_for_execution'::name,
  ARRAY['integer','integer']::name[],
  'A1: the executor''s work list EXISTS — E4 §3''s 501 (index.ts:496) is closed');

SELECT ok(has_function_privilege('service_role','kernel.claim_refunds_for_execution(integer,integer)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.claim_refunds_for_execution(integer,integer)','EXECUTE')
      AND NOT has_function_privilege('anon','kernel.claim_refunds_for_execution(integer,integer)','EXECUTE'),
  'A2: EXEC DEF — service_role only; no client principal can enumerate refunds in flight');

SELECT ok((SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='claim_refunds_for_execution')
      AND (SELECT 'search_path=""' = ANY(coalesce(p.proconfig,'{}'::text[]))
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='claim_refunds_for_execution'),
  'A3: security definer with search_path pinned empty (076 discipline)');

-- The worker cannot name a subject because there is no parameter for one.
SELECT is((SELECT p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='claim_refunds_for_execution'),
  ARRAY['p_limit','p_lease_seconds'],
  'A4: TWO parameters, both throughput — no refund, payment, order, venue, org, identity or amount is nameable');

SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                       WHERE n.nspname='kernel' AND p.proname='list_pending_refunds'),
  'A5: the BARE LIST E4 §3 sketched was deliberately NOT built — a list hands N workers the same N refunds and leans on Stripe''s key as the FIRST defence');

SELECT ok(has_function_privilege('service_role','kernel.get_refund_execution_context(uuid)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.get_refund_execution_context(uuid)','EXECUTE'),
  'A6: the claim does NOT duplicate the binding read — 10g stays the single refund→PaymentIntent path, service_role only');

-- ============================================================================
-- FIXTURE — five refunds across two payments, covering every reachable state.
-- ============================================================================
SELECT tap._st158('r_old',  tap._mkrefund158(tap.payment_a(), 1000, 'pending',   NULL,        interval '3 hours')::text);
SELECT tap._st158('r_new',  tap._mkrefund158(tap.payment_a(), 1000, 'pending',   NULL,        interval '1 hour')::text);
SELECT tap._st158('r_sub',  tap._mkrefund158(tap.payment_b(), 1000, 'submitted', 're_sub158', interval '2 hours')::text);
SELECT tap._st158('r_suc',  tap._mkrefund158(tap.payment_b(), 1000, 'succeeded', 're_suc158', interval '2 hours')::text);
SELECT tap._st158('r_fail', tap._mkrefund158(tap.payment_b(), 1000, 'failed',    're_fai158', interval '2 hours')::text);

-- ============================================================================
-- SECTION B — THE DATABASE DECIDES WHAT IS ELIGIBLE
--   Attack: a worker that wants to "re-run" a refund that already settled, or
--   to resurrect one Stripe refused.
-- ============================================================================
SELECT tap._st158('b1', tap._claim158(50, 900)::text);

SELECT is(tap._mode158(tap._fe158('b1')::jsonb, tap._fe158('r_new')::uuid), 'create',
  'B1: a `pending` refund whose key has NEVER been used is claimed for create');

SELECT is(tap._mode158(tap._fe158('b1')::jsonb, tap._fe158('r_sub')::uuid), 'reconcile',
  'B2: a `submitted` refund IS claimable and is ALWAYS reconcile — E4 §5 case 4''s stranded row (which kept BP-12 blocking the buyer''s deletion forever) is now reachable, and it carries a ref (085:93) so it can never mint a second refund');

SELECT ok(tap._mode158(tap._fe158('b1')::jsonb, tap._fe158('r_suc')::uuid) IS NULL
      AND tap._mode158(tap._fe158('b1')::jsonb, tap._fe158('r_fail')::uuid) IS NULL,
  'B3: TERMINAL refunds (succeeded / failed) are never claimed — a worker cannot re-execute settled money or resurrect a Stripe-rejected refund');

SELECT is((SELECT (tap._fe158('b1')::jsonb -> 'refunds' -> 0 ->> 'refund_id')), tap._fe158('r_old'),
  'B4: oldest money first — the batch is ordered by kernel.refund.created_at, not by anything the worker supplies');

SELECT is((SELECT count(*)::int FROM jsonb_array_elements((tap._claim158(0, 900) -> 'refunds'))), 0,
  'B5: p_limit=0 clamps to 1 and the whole eligible set is already leased — a second tick gets nothing, not everything');

SELECT is((SELECT jsonb_array_length(tap._fe158('b1')::jsonb -> 'refunds')), 3,
  'B6: exactly the three UNFINISHED rows were claimed — the eligible set is a database predicate, not a worker filter');

-- ============================================================================
-- SECTION C — CLAIM EXCLUSIVITY, LEASE EXPIRY, AND RETRY
--   Attack: two workers on one refund; a worker that dies holding the lease;
--   a worker that lies about the lease length to reproduce the herd.
-- ============================================================================
SELECT is((SELECT count(*)::int FROM jsonb_array_elements((tap._claim158(50, 900) -> 'refunds'))), 0,
  'C1: a SECOND worker in the same lease window claims NOTHING — concurrent workers cannot both hold one refund');

SELECT is((SELECT count(*)::int FROM jsonb_array_elements((tap._claim158(50, 0) -> 'refunds'))), 0,
  'C2: p_lease_seconds=0 clamps to 60 — a worker cannot shorten the lease to vacuum up rows another worker is holding');

-- A stale claim: the worker died 2h ago holding a 900s lease.
SELECT tap._st158('r_stale', tap._mkrefund158(tap.payment_a(), 500, 'pending', NULL, interval '5 hours')::text);
SELECT tap._mkclaim158(tap._fe158('r_stale')::uuid, interval '2 hours', 'create');
SELECT tap._st158('c3', tap._claim158(50, 900)::text);

SELECT is(tap._mode158(tap._fe158('c3')::jsonb, tap._fe158('r_stale')::uuid), 'create',
  'C3: an ABANDONED lease recovers — the row is re-claimable once the lease elapses (064''s recovery property, expressed as an audit predicate)');

SELECT is((SELECT (e ->> 'attempt')::int FROM jsonb_array_elements(tap._fe158('c3')::jsonb -> 'refunds') e
            WHERE e ->> 'refund_id' = tap._fe158('r_stale')), 2,
  'C4: the attempt counter is the DURABLE claim history, not a mutable column — a crashed worker cannot reset it');

SELECT is((SELECT count(*)::int FROM kernel.admin_audit a
            WHERE a.action='refund.execute_claim' AND a.subject_id = tap._fe158('r_stale')::uuid), 2,
  'C5: every attempt on money leaves its own append-only row — the lease cannot be silently overwritten (077:259 revokes UPDATE/DELETE even from service_role)');

-- ============================================================================
-- SECTION D — THE STRIPE IDEMPOTENCY WINDOW
--   Attack: the double-refund E4 §5 cases 2/3/13 enable once Stripe forgets the
--   key. Stripe retains an idempotency key's result for 24h; after that the
--   identical POST /v1/refunds creates a SECOND, REAL refund. The database, not
--   the worker, decides whether the key is still a dedup token.
-- ============================================================================
SELECT tap._st158('r_expired', tap._mkrefund158(tap.payment_a(), 700, 'pending', NULL, interval '30 hours')::text);
SELECT tap._mkclaim158(tap._fe158('r_expired')::uuid, interval '25 hours', 'create');
SELECT tap._st158('r_fresh', tap._mkrefund158(tap.payment_a(), 700, 'pending', NULL, interval '3 hours')::text);
SELECT tap._mkclaim158(tap._fe158('r_fresh')::uuid, interval '2 hours', 'create');
SELECT tap._st158('d', tap._claim158(50, 900)::text);

SELECT is(tap._mode158(tap._fe158('d')::jsonb, tap._fe158('r_expired')::uuid), 'reconcile',
  'D1: a `pending` refund whose key was FIRST USED 25h ago is downgraded to reconcile — a blind create here is a second real refund to the buyer''s card');

SELECT is(tap._mode158(tap._fe158('d')::jsonb, tap._fe158('r_fresh')::uuid), 'create',
  'D2: first use 2h ago is still inside the window — the replay is deduped by Stripe and returns the ORIGINAL object');

-- A `submitted` row whose key expired 40h ago: the age that would make a
-- `pending` row dangerous makes no difference here, because the ref is durable.
SELECT tap._st158('r_oldsub', tap._mkrefund158(tap.payment_b(), 300, 'submitted', 're_old158', interval '45 hours')::text);
SELECT tap._mkclaim158(tap._fe158('r_oldsub')::uuid, interval '40 hours', 'create');
SELECT is(tap._mode158(tap._claim158(50, 900)::jsonb, tap._fe158('r_oldsub')::uuid), 'reconcile',
  'D3: a `submitted` row is reconcile regardless of age — it already carries the ref (085:93), so reconciliation never needs the expired key');

-- ============================================================================
-- SECTION E — WHAT THE WORKER IS TOLD, AND WHAT IT IS NOT
--   Attack: amount tampering, wrong-buyer targeting, wrong-venue targeting, and
--   a forged worker command key.
-- ============================================================================
SELECT is((SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)
             FROM jsonb_array_elements(tap._fe158('d')::jsonb -> 'refunds') e LIMIT 1),
  ARRAY['attempt','command_key','created_at','execution_mode','refund_id','status'],
  'E1: the batch projects SIX keys — no payment, no PaymentIntent, no amount, no currency, no buyer, no order, no venue, no org. Amount tampering has no surface because the amount is never shown to the worker');

SELECT is((SELECT e ->> 'command_key' FROM jsonb_array_elements(tap._fe158('d')::jsonb -> 'refunds') e
            WHERE e ->> 'refund_id' = tap._fe158('r_fresh')),
  'refund.execute:' || tap._fe158('r_fresh'),
  'E2: the command key is DERIVED FROM THE DURABLE REFUND FACT, not minted by the caller (index.ts built `sweep:<uuid>` itself) — two workers on one refund cannot land under two audit identities');

SELECT ok((SELECT bool_and((e ->> 'refund_id')::uuid IN (SELECT refund_id FROM kernel.refund))
             FROM jsonb_array_elements(tap._fe158('d')::jsonb -> 'refunds') e),
  'E3: every id handed out is a real kernel.refund primary key — the worker is given a HANDLE, and 10g is still the only way to turn it into money');

-- ============================================================================
-- SECTION F — THE CLAIM MOVES NOTHING
--   A claim must be observationally inert on the money ledger: it is a lease,
--   not a state transition. kernel.mark_refund_state (085:1737) stays the sole
--   writer of kernel.refund.status.
-- ============================================================================
SELECT tap._st158('f_before', (SELECT status || '|' || coalesce(stripe_refund_ref,'-') || '|' || updated_at::text
                                 FROM kernel.refund WHERE refund_id = tap._fe158('r_sub')::uuid));
SELECT tap._claim158(50, 1);   -- clamps to 60s; r_sub is still leased, so this is a no-op tick
SELECT is((SELECT status || '|' || coalesce(stripe_refund_ref,'-') || '|' || updated_at::text
             FROM kernel.refund WHERE refund_id = tap._fe158('r_sub')::uuid),
  tap._fe158('f_before'),
  'F1: claiming mutates NO column of kernel.refund — not status, not the ref, not updated_at');

SELECT throws_ok(
  format($$UPDATE kernel.admin_audit SET reason_code = 'tampered' WHERE subject_id = %L AND action = 'refund.execute_claim'$$,
         tap._fe158('r_stale')),
  NULL, 'append_only: admin_audit is immutable — UPDATE is not permitted',
  'F2: a claim record cannot be rewritten — the lease and the first-use instant the window depends on are both tamper-evident');

SELECT is((SELECT count(DISTINCT a.actor_identity)::int FROM kernel.admin_audit a
            WHERE a.action = 'refund.execute_claim'), 1,
  'F3: every claim is attributed to the SYSTEM identity (078:1611) — a claim is a machine act and can never be mistaken for a human refund decision');

-- ============================================================================
-- SECTION G — THE BINDING READ IS STILL THE ONLY DOOR TO THE MONEY
--   Attack: wrong payment, wrong PaymentIntent, enumeration.
-- ============================================================================
SELECT is(kernel.get_refund_execution_context(gen_random_uuid()), NULL,
  'G1: an unknown refund id yields SQL NULL, never a partial object — the context read is NON-ENUMERABLE');

SELECT is((kernel.get_refund_execution_context(tap._fe158('r_new')::uuid) ->> 'payment_id'),
  tap.payment_a()::text,
  'G2: the PaymentIntent is resolved from kernel.refund.payment_id (085:76, ON DELETE RESTRICT) — the worker never names it, so "wrong PaymentIntent" has no surface');

SELECT ok(NOT (kernel.get_refund_execution_context(tap._fe158('r_new')::uuid) ?| ARRAY['buyer_id','seller_id','email','venue_id','org_id']),
  'G3: X-6 / ruling F — no identity, no demographic, no venue and no org field crosses into the executor');

SELECT is((kernel.get_refund_execution_context(tap._fe158('r_new')::uuid) ->> 'stripe_livemode'), NULL,
  'G4: an UNCLASSIFIED payment (migration 045 left stripe_livemode NULL) reaches the executor as NULL and fails closed there — a test-era intent can never be refunded with a live key');

-- ============================================================================
-- SECTION H — CROSS-SUBJECT ISOLATION
--   Attack: one claim leaking authority over another refund, another payment,
--   another venue or another organization.
-- ============================================================================
SELECT ok((SELECT bool_and(
             (kernel.get_refund_execution_context((e ->> 'refund_id')::uuid) ->> 'refund_id') = (e ->> 'refund_id'))
             FROM jsonb_array_elements(tap._fe158('d')::jsonb -> 'refunds') e),
  'H1: each claimed handle resolves to ITS OWN refund and no other — a batch confers no authority over its neighbours');

SELECT isnt((kernel.get_refund_execution_context(tap._fe158('r_sub')::uuid) ->> 'payment_id'),
  (kernel.get_refund_execution_context(tap._fe158('r_new')::uuid) ->> 'payment_id'),
  'H2: refunds on different payments stay bound to different payments — the claim never re-parents a refund');

-- ============================================================================
-- SECTION I — THE ROLE WALL, EXERCISED (not merely catalogued)
--   Attack: service-role misuse from a client; a client trying to become the
--   worker.
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT kernel.claim_refunds_for_execution(5, 900)$$, '42501', NULL,
  'I1: an authenticated principal is REFUSED — the work list is not a client surface');
SELECT throws_ok($$SELECT kernel.get_refund_execution_context(gen_random_uuid())$$, '42501', NULL,
  'I2: and neither is the binding read (10g)');
SELECT tap.logout();

SELECT tap.login_anon();
SELECT throws_ok($$SELECT kernel.claim_refunds_for_execution(5, 900)$$, '42501', NULL,
  'I3: anon is refused (PFA-14 intact — no ruling in this train widens anon anywhere)');
SELECT tap.logout();

SELECT ok(has_function_privilege('service_role','kernel.mark_refund_state(uuid,text,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','kernel.mark_refund_state(uuid,text,text,text,text)','EXECUTE'),
  'I4: NOTHING here weakens the state writer — mark_refund_state (085:1737) is still service_role-only and still the sole transition out of `pending`');

-- ============================================================================
-- SECTION J — PFA-23'S DIRECT ARM: WHERE THE PLATFORM'S AUTHORITY ACTUALLY LIVES
--   085:2144-2146's grant-block COMMENT names a caller shape that cannot exist
--   ("the refund-execute edge as service_role, forwarding the platform JWT"):
--   PostgREST derives ONE database role per request, so a request is either
--   service_role (auth.uid() NULL ⇒ kernel.is_platform fails) or authenticated
--   (EXECUTE denied). PFA-23's own normative ruling never says that. The
--   platform-direct authority is reachable — through the authenticated door
--   PFA-23 itself names — and these three pin exactly which door that is, so a
--   future reader cannot mistake the dead branch for a missing capability.
--   The executed behaviour is asserted in 149 D2. See H1_refund_architecture.md.
-- ============================================================================
SELECT ok(NOT has_function_privilege('authenticated','kernel.refund_primary_order(uuid,integer,text,text)','EXECUTE')
      AND has_function_privilege('service_role','kernel.refund_primary_order(uuid,integer,text,text)','EXECUTE'),
  'J1: PFA-23 unchanged — refund_primary_order is EXEC DEF. Its DIRECT branch is definer-internal, not an edge-callable arm');

SELECT ok(has_function_privilege('authenticated','kernel.request_order_refund(uuid,uuid[],integer,text,text)','EXECUTE')
      AND (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='request_order_refund'),
  'J2: request_order_refund IS the authenticated, security-definer door — it carries auth.uid(), so kernel.is_platform() resolves, and it reaches the executor definer→definer');

SELECT ok(has_function_privilege('authenticated','kernel.record_money_denial(text,text,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','kernel.record_money_denial(text,text,uuid,text)','EXECUTE'),
  'J3: R-28 intact — the denial witness stays authenticated-only, so a refused platform refund is still recorded by the principal who was refused, not by a machine');

SELECT * FROM finish();
ROLLBACK;
