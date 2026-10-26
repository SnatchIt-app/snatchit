-- ============================================================================
-- 20261027015500_primary_buyer_holds_and_orders.sql — registry 167 (pgTAP 234):
-- the buyer's reserve / release / order-list verbs in `public` for the primary-
-- ticketing launch — three thin SECURITY DEFINER wrappers over the existing
-- venue.* engines and over 182's order read, so the app needs no venue schema.
--
-- Registry 167 / pgTAP 234 — assigned by Claude A 2026-10-26 (registry 167/234,
-- registry @ 5f29cbcc). D writes, A reviews before this leaves draft, C consumes.
-- DARK: applied nowhere but local rehearsal clones. It exposes no schema, flips
-- no flag, seeds no config key and touches no table, policy or trigger. It DOES
-- create three functions in `public`, which PostgREST serves at /rest/v1/rpc/
-- the moment it is applied — so the FOUR-FILE RULE is real here (below).
--
-- ORDER: after 182 (20261026200000 — public.get_my_primary_orders is called by
-- name here), which sits after 159 / 176 / 160 / 161 / 162. Merge order (A):
-- 164 -> 166 -> 167 -> 165. The pre-flight refuses to run without 182 and the
-- 081 engines. Nothing here depends on 164 / 166 objects; if either replaces
-- venue.reserve_primary_inventory or venue.release_inventory_hold, the wrappers
-- follow the new body automatically (they call the engines by name), exactly as
-- A's 185 sale-window refusal will.
--
-- WHAT THIS MIGRATION IS (A's shapes; CONTRACTS-D §3a / brief 167):
--  1. public.reserve_primary_tier(p_session_id uuid, p_ticket_type_id uuid,
--       p_quantity integer, p_command_key text) → jsonb
--       {status, hold_id, expires_at, quantity}
--     The SERVER picks the batch: a venue.inventory_batch row with
--       ticket_type_id = p_ticket_type_id, event_session_id = p_session_id,
--       release_kind = 'public_sale', whose tier has visibility = 'public' and
--       belongs to the session's event
--     then calls venue.reserve_primary_inventory(batch, p_quantity,
--     p_command_key) (081:527) and returns its outcome reshaped. EVERYTHING the
--     engine decides comes from its body unchanged: idempotency per (identity,
--     command key) — a replay returns the ORIGINAL hold whatever tier / qty the
--     replay names (081:563-576; quantity is read back from that hold row);
--     feature_disabled (081:578-587); not_on_sale / session_terminal
--     (081:589-606); the per-user active-hold cap hold_cap_exceeded (081:608-
--     626); hold_ttl_unset (081:628-639); oversell_rejected under the batch row
--     lock (081:642-647); bad_quantity; deletion_pending; command key required;
--     and any future refusal a later body adds (A's 185 sale window). Those
--     refusals are RAISED exceptions there and stay raised here: this wrapper
--     has NO exception handler, so the SQLSTATE and message reach the client
--     verbatim. The engine derives the actor from auth.uid() ITSELF (081:548-551:
--     `v_uid := auth.uid()`, refusing NULL with 42501) and has no identity
--     parameter; this wrapper passes none.
--     ZERO matching batches → 'not_found: no public_sale inventory for ticket
--     type <id> on session <id>' (SQLSTATE P0002, the engine's not_found class)
--     — one message for an unknown session, an unknown tier, a tier of another
--     event, a hidden or door_only tier, and a tier with only comp / door /
--     promoter_hold / presale batches on that session (no oracle among them).
--     hidden and door_only tiers are refused here although the engine itself
--     does not look at visibility: 182's get_primary_session never shows them
--     to a buyer, and a public verb must not sell what the public read hides —
--     FLAGGED for A if 'hidden' is meant to be sellable by direct link.
--     SEVERAL matching batches — POSSIBLE: 081 has no uniqueness on
--     (ticket_type_id, event_session_id, release_kind) (081:58-80; only the
--     non-unique inventory_batch_avail_idx), and 252's fixture itself carries
--     two public_sale batches for one tier/session. The pick is deterministic:
--     the OLDEST batch (created_at, then batch_id) that still has room for
--     p_quantity (capacity - held - sold >= p_quantity); if none has room, the
--     oldest one — so the engine's own oversell_rejected answers, under its
--     lock. The room test is an unlocked hint only; the engine re-checks under
--     FOR UPDATE, so a race can only turn into oversell_rejected, never an
--     oversell. 234 R11/R13 pin both branches. D's decision — FLAGGED for A.
--     NULL uid → 42501 'insufficient_privilege: authentication required' (the
--     engine's own text) is raised by the wrapper BEFORE the batch lookup, so
--     an unauthenticated caller cannot use not_found as a catalogue oracle.
--     KNOWN EDGE: a replay whose tier has since stopped resolving (made hidden,
--     its last public_sale batch gone) reads not_found instead of the replay.
--  2. public.release_primary_hold(p_hold_id uuid, p_command_key text) → jsonb
--       {status, hold_id, hold_status}
--     over venue.release_inventory_hold(p_hold_id, p_command_key) (081:764).
--     The engine's authority is the holder OR venue staff OR a NULL uid (the
--     definer sweep) (081:812-820) and it answers 42501 'not the holder or
--     venue staff' for someone else's hold — an existence oracle. The wrapper
--     narrows it to OWN holds: the hold must have identity_id = auth.uid(),
--     else 'not_found: hold <id>' (P0002) — byte-for-byte the engine's message
--     for an unknown id (081:794), so a foreign hold id and a made-up one are
--     indistinguishable. A NULL uid is refused 42501 first (otherwise the
--     engine's sweep branch would let it release anything). A command key
--     beginning 'sweep:' is refused ('precondition_failed: reserved_command_key')
--     because the engine turns such a key into the sweep's 'expired' transition
--     (081:823) — a buyer's own release must record 'released'. Status, the
--     terminal-state noop_replay and every other refusal pass through. The
--     engine's per-batch `remaining` is NOT returned (a batch-level counter;
--     182 exposes only the tier-level public_sale sum).
--  3. public.list_my_primary_orders() → rows (order_id uuid, status text,
--       total_minor integer, currency text, created_at timestamptz,
--       atoms_issued integer, payment_state text, charge_total_minor integer,
--       event_session_id uuid, title text)
--     = EXACTLY get_my_primary_orders' eight columns, in its order, then the
--     session id and the event title (A's addition, 2026-10-26: the Tickets
--     tab links a pending order to its ticket page). The caller's orders
--     across ALL sessions, newest first (created_at desc, order_id asc).
--     NOT A FORK: the body enumerates the caller's own sessions from
--     venue."order" (buyer_id = auth.uid()) and calls 182's
--     public.get_my_primary_orders(session) for each — so status, atoms_issued,
--     the payment_state mapping and charge_total_minor (the linked
--     payments.total; NULL while no payment is linked; never recomputed) are
--     182's expressions by construction, and get_my_primary_orders binds to
--     auth.uid() a second time on every row. No helper is created. A plpgsql
--     body records no pg_depend row for that call, which is why 182's
--     rollback carries G2b (it refuses to drop get_my_primary_orders while
--     this body names it). NULL uid → 28000 'orders_unauthenticated' (182's
--     code), raised before anything is read. title = catalog.event.title of
--     the order's session (the buyer's own order: no visibility filter).
--
-- EVERY FUNCTION: SECURITY DEFINER, SET search_path = '' (every reference
-- schema-qualified, auth.uid() included), LANGUAGE plpgsql. reserve and release
-- are VOLATILE (they write through the engines); the list is STABLE. None takes
-- a user, owner, buyer or org id.
--
-- GRANT DECISIONS (I-7: strip, then grant exactly): all three
--   REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO authenticated;
--   GRANT EXECUTE TO service_role — EXPLICIT, as 182 does (A's house posture:
--   never inherited from a default ACL, which CI's fresh stack does not carry).
--   service_role gains nothing by it: auth.uid() is NULL for it, so reserve and
--   release raise 42501 and the list raises 28000. anon: denied at the ACL.
--   Manifest class 'authenticated-execute' for all three.
--
-- FOUR-FILE RULE (CLAUDE.md) — REAL for this package:
--   1. supabase/ci/assert_public_table_grant_decisions.sql — three Part-B rows,
--      'authenticated-execute'.
--   2. supabase/ci/expected_grants.txt — public TABLE grants only: UNCHANGED
--      (no table grant moves; diffed in verification, not edited).
--   3. .github/workflows/ci.yml Gate-2 census — EXPECT_FUNCS 130 -> 133 (+3;
--      tables / policies / triggers unchanged). The same total is pinned by
--      pgTAP tests/162 P2 and 252 A17 (both 130 -> 133 in this package).
--   4. supabase/rollbacks/20261027015500_primary_buyer_holds_and_orders_
--      rollback.sql — md5-asserts the three live bodies before dropping them.
--
-- NEGATIVE CONTROLS (pgTAP 234 on mutant clones; EVIDENCE-167): release
-- without the owner predicate → X1/X4 fail; a list body that reads
-- venue."order" without auth.uid() → O1/O6 fail; 182's get_my_primary_orders
-- without its buyer_id predicate → O1 fails (the list's binding IS 182's);
-- batch pick without release_kind = 'public_sale' → R2/R3 fail; without the
-- visibility filter → R8 fails; oldest-batch pick ignoring room → R11 fails.
--
-- VERIFICATION (after apply):
--   select proname, prosecdef, provolatile, proconfig, proacl from pg_proc
--    where pronamespace = 'public'::regnamespace
--      and proname in ('reserve_primary_tier','release_primary_hold','list_my_primary_orders');
--   -- 3 rows; prosecdef t; provolatile v / v / s; proconfig {search_path=""};
--   -- proacl {postgres, authenticated, service_role}=X (entry order may differ).
--   select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');  -- 133 (was 130)
--   -- md5(prosrc) as applied (the rollback's G1 targets):
--   --   reserve_primary_tier    f397c9a49b04f37793165e996490e2f0
--   --   release_primary_hold    d043cada2d528d5ec5ab4a5164224261
--   --   list_my_primary_orders  febebba44a44fb925dd56de58a47effa
-- LOCKS / RUNTIME: three CREATE FUNCTION + grants — catalog rows only,
-- milliseconds. lock_timeout 3s so it fails cleanly rather than queue.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ============================================================================
-- PRE-FLIGHT — 182 and the 081 engines present; census captured
-- ============================================================================
CREATE TEMP TABLE _pre167 ON COMMIT DROP AS
  SELECT count(*)::integer AS n_public_fns
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');

DO $pre$
BEGIN
  IF to_regprocedure('public.get_my_primary_orders(uuid)') IS NULL THEN
    RAISE EXCEPTION '167_REFUSED: public.get_my_primary_orders(uuid) (182) is absent; apply 182 first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p
                  WHERE p.oid = to_regprocedure('public.get_my_primary_orders(uuid)')
                    AND p.proargnames = ARRAY['p_event_session_id','order_id','status','total_minor','currency','created_at',
                                              'atoms_issued','payment_state','charge_total_minor']) THEN
    RAISE EXCEPTION '167_REFUSED: public.get_my_primary_orders is not the 182 fold-in shape (eight columns ending charge_total_minor); apply the current 182 first.';
  END IF;
  IF to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)') IS NULL
  OR to_regprocedure('venue.release_inventory_hold(uuid, text)') IS NULL THEN
    RAISE EXCEPTION '167_REFUSED: an 081 engine (venue.reserve_primary_inventory / venue.release_inventory_hold) is absent.';
  END IF;
  IF to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)') IS NOT NULL
  OR to_regprocedure('public.release_primary_hold(uuid, text)') IS NOT NULL
  OR to_regprocedure('public.list_my_primary_orders()') IS NOT NULL THEN
    RAISE EXCEPTION '167_REFUSED: a 167 function already exists in public; this migration creates, it does not replace. Nothing changed.';
  END IF;
END $pre$;

-- ============================================================================
-- PART 1 — public.reserve_primary_tier  (authenticated; over 081 reserve)
-- ============================================================================
create function public.reserve_primary_tier(
  p_session_id uuid, p_ticket_type_id uuid, p_quantity integer, p_command_key text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_batch   uuid;
  v_res     jsonb;
  v_hold_id uuid;
  v_qty     integer;
  v_expires timestamptz;
begin
  -- the engine refuses a NULL uid itself (081:548-551); refusing it here FIRST
  -- keeps the not_found below from answering an unauthenticated caller.
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  -- the server picks the batch: a public_sale batch of a PUBLIC tier of this
  -- session's event; the oldest with room for the quantity, else the oldest
  -- (the engine's oversell_rejected then answers under its row lock).
  select b.batch_id into v_batch
    from venue.inventory_batch b
    join venue.ticket_type tt     on tt.ticket_type_id = b.ticket_type_id
    join catalog.event_session s  on s.session_id = b.event_session_id
   where b.event_session_id = p_session_id
     and b.ticket_type_id   = p_ticket_type_id
     and b.release_kind     = 'public_sale'
     and tt.visibility      = 'public'
     and tt.event_id        = s.event_id
   order by (b.capacity - b.held - b.sold >= coalesce(p_quantity, 0)) desc,
            b.created_at asc, b.batch_id asc
   limit 1;
  if v_batch is null then
    raise exception 'not_found: no public_sale inventory for ticket type % on session %', p_ticket_type_id, p_session_id
      using errcode = 'P0002';
  end if;

  -- every decision (idempotency, flag, sale state, cap, TTL, oversell) is the
  -- engine's; no exception handler here, so its refusals reach the client as-is.
  v_res := venue.reserve_primary_inventory(v_batch, p_quantity, p_command_key);

  v_hold_id := (v_res ->> 'hold_id')::uuid;
  select h.quantity, h.expires_at into v_qty, v_expires
    from venue.inventory_hold h
   where h.hold_id = v_hold_id
     and h.identity_id = auth.uid();

  return jsonb_build_object('status',     v_res ->> 'status',
                            'hold_id',    v_hold_id,
                            'expires_at', v_expires,
                            'quantity',   v_qty);
end;
$$;

comment on function public.reserve_primary_tier(uuid, uuid, integer, text) is
  '167: the buyer reserves a quantity of a PUBLIC tier for a session. The server picks the tier''s public_sale batch on that session (oldest with room, else oldest) and calls venue.reserve_primary_inventory, '
  'whose refusals (feature_disabled, not_on_sale, session_terminal, hold_cap_exceeded, hold_ttl_unset, oversell_rejected, bad_quantity, …) and idempotency per (auth.uid(), command key) pass through unchanged. '
  'Returns {status ok|idempotency_replay, hold_id, expires_at, quantity}. No public_sale batch of a public tier on that session -> P0002 not_found. EXECUTE authenticated (+ service_role, which auth.uid() NULL refuses).';

-- ============================================================================
-- PART 2 — public.release_primary_hold  (authenticated; OWN holds only)
-- ============================================================================
create function public.release_primary_hold(p_hold_id uuid, p_command_key text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_res    jsonb;
  v_status text;
begin
  -- a NULL uid is the engine's sweep branch (081:812-820) — never through here.
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  -- the engine maps a 'sweep:' key to the sweep's 'expired' transition (081:823).
  if p_command_key like 'sweep:%' then
    raise exception 'precondition_failed: reserved_command_key — the sweep: prefix belongs to venue.sweep_expired_inventory_holds';
  end if;
  -- OWN holds only; a foreign hold id gets the engine's unknown-id answer
  -- byte for byte (081:794), so existence never leaks.
  perform 1 from venue.inventory_hold h
   where h.hold_id = p_hold_id
     and h.identity_id = v_uid;
  if not found then
    raise exception 'not_found: hold %', p_hold_id using errcode = 'P0002';
  end if;

  v_res := venue.release_inventory_hold(p_hold_id, p_command_key);

  select h.status into v_status from venue.inventory_hold h where h.hold_id = p_hold_id;
  return jsonb_build_object('status',      v_res ->> 'status',
                            'hold_id',     p_hold_id,
                            'hold_status', v_status);
end;
$$;

comment on function public.release_primary_hold(uuid, text) is
  '167: the buyer releases one of HER OWN holds through venue.release_inventory_hold. Another buyer''s hold id answers exactly like an unknown id (P0002 not_found: hold <id>) — no existence oracle; a NULL uid is refused 42501; a sweep: command key is refused. '
  'Returns {status ok|noop_replay, hold_id, hold_status}. EXECUTE authenticated (+ service_role, which auth.uid() NULL refuses).';

-- ============================================================================
-- PART 3 — public.list_my_primary_orders  (authenticated; 182's read per session)
-- ============================================================================
create function public.list_my_primary_orders()
returns table (
  order_id           uuid,
  status             text,
  total_minor        integer,
  currency           text,
  created_at         timestamptz,
  atoms_issued       integer,
  payment_state      text,
  charge_total_minor integer,
  event_session_id   uuid,
  title              text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'orders_unauthenticated' using errcode = '28000';
  end if;

  -- 182's per-session read, called for each of the caller's own sessions: the
  -- projection, the payment_state mapping and charge_total_minor are its
  -- expressions (not a copy), and it re-binds every row to auth.uid().
  return query
  select g.order_id, g.status, g.total_minor, g.currency, g.created_at,
         g.atoms_issued, g.payment_state, g.charge_total_minor,
         ms.event_session_id, ms.title
    from (select distinct o.event_session_id, e.title
            from venue."order" o
            join catalog.event_session es on es.session_id = o.event_session_id
            join catalog.event e          on e.event_id   = es.event_id
           where o.buyer_id = v_uid) ms
    cross join lateral public.get_my_primary_orders(ms.event_session_id) g
   order by g.created_at desc, g.order_id asc;
end;
$$;

comment on function public.list_my_primary_orders() is
  '167: the caller''s own primary orders across ALL sessions, newest first — 182''s get_my_primary_orders columns verbatim (status, total_minor face, atoms_issued, payment_state, charge_total_minor = linked payments.total or NULL) '
  'plus event_session_id and the event title. Built by calling public.get_my_primary_orders per own session (no forked mapping). NULL uid raises 28000 orders_unauthenticated. EXECUTE authenticated (+ service_role, refused by the NULL uid).';

-- ============================================================================
-- PART 4 — function ACLs (strip, then grant exactly; service_role explicit)
-- ============================================================================
revoke all on function public.reserve_primary_tier(uuid, uuid, integer, text) from public, anon, authenticated;
grant execute on function public.reserve_primary_tier(uuid, uuid, integer, text) to authenticated;
grant execute on function public.reserve_primary_tier(uuid, uuid, integer, text) to service_role;

revoke all on function public.release_primary_hold(uuid, text) from public, anon, authenticated;
grant execute on function public.release_primary_hold(uuid, text) to authenticated;
grant execute on function public.release_primary_hold(uuid, text) to service_role;

revoke all on function public.list_my_primary_orders() from public, anon, authenticated;
grant execute on function public.list_my_primary_orders() to authenticated;
grant execute on function public.list_my_primary_orders() to service_role;

-- ============================================================================
-- POST-FLIGHT — refuse to COMMIT unless the three carry the decided posture and
-- the public census moved by exactly +3
-- ============================================================================
DO $post$
DECLARE
  v_pre  integer := (SELECT n_public_fns FROM _pre167);
  v_post integer;
  r      record;
  v_anon boolean; v_auth boolean; v_pub boolean; v_svc boolean;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public.reserve_primary_tier(uuid, uuid, integer, text)', 'v'),
      ('public.release_primary_hold(uuid, text)',                'v'),
      ('public.list_my_primary_orders()',                        's')) AS x(sig, vol)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE EXCEPTION '167_POSTFLIGHT: % was not created', r.sig;
    END IF;
    IF NOT (SELECT p.prosecdef AND p.provolatile::text = r.vol AND p.proconfig = ARRAY['search_path=""']
              FROM pg_proc p WHERE p.oid = to_regprocedure(r.sig)) THEN
      RAISE EXCEPTION '167_POSTFLIGHT: % is not SECURITY DEFINER / volatility % / search_path=''''', r.sig, r.vol;
    END IF;
    SELECT has_function_privilege('anon',          to_regprocedure(r.sig), 'EXECUTE'),
           has_function_privilege('authenticated', to_regprocedure(r.sig), 'EXECUTE'),
           has_function_privilege('service_role',  to_regprocedure(r.sig), 'EXECUTE'),
           EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
                    WHERE p.oid = to_regprocedure(r.sig) AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      INTO v_anon, v_auth, v_svc, v_pub;
    IF v_pub OR v_anon OR NOT v_auth OR NOT v_svc THEN
      RAISE EXCEPTION '167_POSTFLIGHT: ACL of % is not the decided posture (anon=% expected f, authenticated=%, service_role=% expected t, PUBLIC=%)',
        r.sig, v_anon, v_auth, v_svc, v_pub;
    END IF;
    IF (SELECT proacl FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS NULL THEN
      RAISE EXCEPTION '167_POSTFLIGHT: proacl of % is DEFAULTED (PUBLIC EXECUTE)', r.sig;
    END IF;
  END LOOP;

  SELECT count(*)::integer INTO v_post
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');
  IF v_post <> v_pre + 3 THEN
    RAISE EXCEPTION '167_POSTFLIGHT: public function census moved % -> % (expected +3)', v_pre, v_post;
  END IF;
  RAISE NOTICE '167 applied: public functions % -> % (Gate-2 EXPECT_FUNCS 130 -> 133 on the 182 chain).', v_pre, v_post;
END $post$;

COMMIT;
