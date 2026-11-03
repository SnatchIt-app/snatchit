-- ============================================================================
-- primary_checkout_sale_eligibility — registry 201 / pgTAP 270. D writes the SQL, pgTAP and four-file work;
-- A owns every edge and Stripe change. DRAFT: applied nowhere. ORDER: after registry 198
-- (primary_checkout_hold_binding), whose checkout and finalize bodies this file extends.
--
-- WHAT THIS MIGRATION GUARANTEES (A's decisions on the 2026-11-02 contract trace: EL-13, DB-4, SW-4, EL-05)
--   1. Finalize on a cancelled event or session (EL-13). venue.finalize_primary_order raises
--      'refund_required: event_cancelled — order <order_id> …' when the order's event is cancelled, otherwise
--      'refund_required: session_cancelled — order <order_id> …' when its session is cancelled. The check runs
--      after the order lock, after the paid-order idempotency_replay short-circuit (a replay of a paid order
--      answers exactly as before, whatever happened to the event since) and after the pending-only refusal;
--      it runs before any hold lock, hold conversion, counter move or mint. It is a raise, so the whole call
--      rolls back: no atom, no payment_native, no conversion, and the order stays pending. The text starts with
--      'refund_required:' (A's webhook arm) and carries none of the finalize classifier substrings
--      (oversell_rejected, not_found, invalid_input, payment_unverified, 'only a pending order finalizes',
--      'no reservation names a batch', no_active_signing_key, insufficient_privilege, 'permission denied').
--      Both statuses are read under the session row lock finalize already holds; catalog.cancel_event cancels
--      the sessions and the event in one transaction under those same session locks, so the read never sees
--      half a cancellation. Finalize gains no other refusal: no sale-window, visibility or venue-approval
--      re-check (a buyer whose PaymentIntent was created inside the window is still issued).
--   2. The buyer hold engine is not client-callable (DB-4). EXECUTE on
--      venue.reserve_primary_inventory(uuid, integer, text) is revoked from authenticated. Its one live caller,
--      public.reserve_primary_tier, is a SECURITY DEFINER wrapper owned by the engine's owner (the pre-flight
--      checks this), so it keeps working: the engine still reads the buyer from auth.uid() (the request's
--      claims), and the wrapper keeps its public_sale / public filter and its not_found answer.
--   3. Checkout coverage counts only buyer inventory (DB-4, defence in depth). In 198's BLOCK B a named hold
--      binds and counts toward an item only when its batch's release_kind = 'public_sale' and its tier's
--      visibility = 'public'. The refusal text is unchanged ('precondition_failed: holds do not cover item
--      (type %, need %, held %)'); 198's DETAIL gains non_buyer_kind_units=N: the caller's named, active,
--      unexpired, unbound (or cancelled-bound) units on this tier and session that the filter excluded.
--      other_batch_units no longer counts those units.
--   4. Buyer holds draw only buyer inventory (SW-4). reserve refuses 'precondition_failed: not_buyer_inventory'
--      unless the batch is public_sale and its tier is public: door_only tiers, and comp / door / presale /
--      promoter_hold batches. It sits after 185's sale-window block (a hidden tier keeps answering
--      tier_not_on_sale) and before the cap lock, the TTL read and every write. Staff holds
--      (venue.create_inventory_hold) are not touched.
--   5. Venue approval at reserve and checkout (EL-05). Both refuse 'precondition_failed: venue is not approved'
--      (the literal catalog.create_event raises and the venue dashboard maps) unless the venue of the
--      session's event has approval_status = 'approved'. The check sits with the event / session eligibility
--      checks (right after session_terminal), before every write; the idempotency replays above it still
--      answer.
--   Unchanged on purpose: every signature, SECURITY DEFINER, search_path and owner; the checkout and finalize
--   ACLs; 198's sweep, release, cancel_pending_order, the mint, public.reserve_primary_tier and the staff hold.
--   No table, column, function, trigger, view, policy or cron job is created. Nothing in `public` changes, so
--   the Gate-2 census (35|133|37|49), the grant-decision manifest and expected_grants do not move; the revoke
--   is on a `venue` function (dated note in ci.yml).
--
-- CONTRACT CHANGES (callers)
--   finalize  new raises 'refund_required: event_cancelled — order …' and 'refund_required: session_cancelled
--             — order …' (A's refund_required webhook arm).
--   reserve   new refusals 'precondition_failed: venue is not approved' and 'precondition_failed:
--             not_buyer_inventory'; a direct call as authenticated is refused 42501. Buyers use
--             public.reserve_primary_tier, whose not_found filter already hides non-buyer inventory.
--   checkout  new refusal 'precondition_failed: venue is not approved'; the coverage refusal's DETAIL gains
--             non_buyer_kind_units.
--
-- MD5 TABLE (md5(pg_get_functiondef(...)) under the default search_path; predecessors measured on a clone of the
-- CI chain at main c093bada plus registry 198)
--   venue.reserve_primary_inventory(uuid,integer,text)      d30669daef75abe15725aa0b04a107b0 (185) -> 079aa9b5c7185a7acdd969d4afe6d77a
--   venue.create_primary_checkout(uuid,jsonb,uuid[],text)   daf8bffd8a5f4a71fc7229dc11e3494a (198) -> 50ed88e09825c811a0aa155d06b00f32
--   venue.finalize_primary_order(uuid,uuid,text,text)       7b8007e59e4faf6ed5d69cc3b2690d49 (198) -> 3c359ec14a788be8398d67210828b773
--   pinned, unchanged: venue.sweep_expired_inventory_holds(integer)          d2ed033325aa3972e9c1be48bb8f4e91 (198)
--                      venue.release_inventory_hold(uuid,text)               b981bef80b10455a0c45a6e908c91aec
--                      kernel.issue_ticket_atoms(jsonb,text)                 9f559af1202fa0e7d8bae0c44df93ff8
--                      venue.cancel_pending_order(uuid,text,text)            3d7fef64c44483586f46b568cb92c610
--                      public.reserve_primary_tier(uuid,uuid,integer,text)   a58bb4af1512b1cb967a9bc57a57fc13
--                      venue.create_inventory_hold(uuid,integer,text,text)   f177b73fadaa60234a6d416fed558d11
--
-- STRIP RULE (pgTAP 270 A2). Deleting every line from a '-- ── 201 BLOCK <X> …' marker through its
-- '-- ── 201 BLOCK <X> END' marker reproduces each predecessor byte for byte: reserve d30669da, checkout daf8bffd,
-- finalize 7b8007e5. Checkout's BLOCK N ends in 'if false then' over 198's original raise and BLOCK N2 closes it (the
-- 188 / 198 technique), so 198's line survives byte for byte and never runs.
--
-- ROLLBACK: the file of this name plus _rollback under supabase/rollbacks/ restores the three predecessor bodies
-- verbatim under an inverse md5 guard, grants EXECUTE on the engine back to authenticated (no CASCADE) and
-- post-checks.
-- PINS MOVED in the same commit (registry 201; each file carries a note): pgTAP 145 (A28), 255 (A3, A10, A11, W12,
-- N1-N5), 258 (A7, A9) and 267 (A5, A6, A8, B2, B6). Suites 145, 146, 255 and 267 called the engine directly as a
-- buyer; they now call it in owner context — a SECURITY DEFINER tap helper with the buyer's request.jwt.claims
-- still set, so auth.uid() resolves the buyer — and keep every assertion.
-- LOCKS: CREATE OR REPLACE of three functions and one REVOKE (catalog rows only; no data read or written);
-- lock_timeout 3s. A checkout or reserve already running finishes on the body it started with.
-- VERIFY after apply:
--   select md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)')));      -- 079aa9b5c7185a7acdd969d4afe6d77a
--   select md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')));  -- 50ed88e09825c811a0aa155d06b00f32
--   select md5(pg_get_functiondef(to_regprocedure('venue.finalize_primary_order(uuid, uuid, text, text)')));      -- 3c359ec14a788be8398d67210828b773
--   select has_function_privilege('authenticated', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE');  -- false
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── step 1: PRE-FLIGHT ───────────────────────────────────────────────────────
do $pf$
declare
  v_r  text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)'))), '<missing>');
  v_c  text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))), '<missing>');
  v_f  text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.finalize_primary_order(uuid, uuid, text, text)'))), '<missing>');
  v_d0 text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.sweep_expired_inventory_holds(integer)'))), '<missing>');
  v_d1 text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.release_inventory_hold(uuid, text)'))), '<missing>');
  v_d2 text := coalesce(md5(pg_get_functiondef(to_regprocedure('kernel.issue_ticket_atoms(jsonb, text)'))), '<missing>');
  v_d3 text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.cancel_pending_order(uuid, text, text)'))), '<missing>');
  v_d4 text := coalesce(md5(pg_get_functiondef(to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'))), '<missing>');
  v_d5 text := coalesce(md5(pg_get_functiondef(to_regprocedure('venue.create_inventory_hold(uuid, integer, text, text)'))), '<missing>');
  v_new boolean;
  r record;
begin
  if v_r not in ('d30669daef75abe15725aa0b04a107b0', '079aa9b5c7185a7acdd969d4afe6d77a') then
    raise exception 'precondition_failed: 201 refuses an unexpected venue.reserve_primary_inventory body (md5 %); nothing changed', v_r; end if;
  if v_c not in ('daf8bffd8a5f4a71fc7229dc11e3494a', '50ed88e09825c811a0aa155d06b00f32') then
    raise exception 'precondition_failed: 201 refuses an unexpected venue.create_primary_checkout body (md5 %); nothing changed', v_c; end if;
  if v_f not in ('7b8007e59e4faf6ed5d69cc3b2690d49', '3c359ec14a788be8398d67210828b773') then
    raise exception 'precondition_failed: 201 refuses an unexpected venue.finalize_primary_order body (md5 %); nothing changed', v_f; end if;
  if v_d0 <> 'd2ed033325aa3972e9c1be48bb8f4e91'
     or v_d1 <> 'b981bef80b10455a0c45a6e908c91aec'
     or v_d2 <> '9f559af1202fa0e7d8bae0c44df93ff8'
     or v_d3 <> '3d7fef64c44483586f46b568cb92c610'
     or v_d4 <> 'a58bb4af1512b1cb967a9bc57a57fc13'
     or v_d5 <> 'f177b73fadaa60234a6d416fed558d11' then
    raise exception 'precondition_failed: 201 dependency moved (sweep %, release %, mint %, cancel %, reserve_primary_tier %, create_inventory_hold %); re-base 201; nothing changed', v_d0, v_d1, v_d2, v_d3, v_d4, v_d5; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where (n.nspname, p.proname) in (('venue','reserve_primary_inventory'),('venue','create_primary_checkout'),('venue','finalize_primary_order'))) <> 3 then
    raise exception 'precondition_failed: 201 expects exactly one overload of each replaced function; nothing changed'; end if;
  v_new := v_r = '079aa9b5c7185a7acdd969d4afe6d77a';
  if (v_c = '50ed88e09825c811a0aa155d06b00f32') is distinct from v_new or (v_f = '3c359ec14a788be8398d67210828b773') is distinct from v_new then
    raise exception 'precondition_failed: 201 found a partial state (reserve %, checkout %, finalize %); nothing changed', v_r, v_c, v_f; end if;
  -- after the revoke the wrapper is the buyer's only path: it must run as the engine's owner
  if not exists (select 1 from pg_proc w, pg_proc e
                  where w.oid = to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)')
                    and e.oid = to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)')
                    and w.prosecdef and w.proowner = e.proowner) then
    raise exception 'precondition_failed: 201 needs public.reserve_primary_tier to be SECURITY DEFINER and owned by the engine''s owner; nothing changed'; end if;
  -- capture each function's posture for the post-flight (never hard-coded: production may differ)
  for r in select * from (values ('r', 'venue.reserve_primary_inventory(uuid, integer, text)'),
                                 ('c', 'venue.create_primary_checkout(uuid, jsonb, uuid[], text)'),
                                 ('f', 'venue.finalize_primary_order(uuid, uuid, text, text)'),
                                 ('w', 'public.reserve_primary_tier(uuid, uuid, integer, text)')) as t(k, sig) loop
    perform set_config('a201.acl_' || r.k, (select coalesce(proacl::text, '<default>') from pg_proc where oid = to_regprocedure(r.sig)), true);
    perform set_config('a201.pos_' || r.k, (select prosecdef::text || '|' || coalesce(proconfig::text, '<none>') || '|' || proowner::regrole::text
                                              from pg_proc where oid = to_regprocedure(r.sig)), true);
  end loop;
  -- the engine's EXECUTE entries the post-flight must find: the captured ones minus authenticated's (computed)
  perform set_config('a201.acl_r_after', (select coalesce(string_agg(t.e, ',' order by t.e), '<none>')
     from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                  || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
                  || '/' || a.grantor::regrole::text as e
             from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)') and a.grantee <> 'authenticated'::regrole) t), true);
  perform set_config('a201.nfn', (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'venue'), true);
end $pf$;

-- ── step 2: the three bodies ─────────────────────────────────────────────────
-- venue.reserve_primary_inventory: the 185 body + 201 BLOCKS V, K
CREATE OR REPLACE FUNCTION venue.reserve_primary_inventory(p_batch_id uuid, p_quantity integer, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid;
  v_flag     boolean;
  v_held     integer;
  v_cap      integer;
  v_sold     integer;
  v_s_status   text;
  v_sess_status text;
  v_ttl      interval;
  v_cap_max  integer;
  v_active   integer;
  v_hold_id  uuid;
  v_expires  timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;

  -- OR-17 F-1: a pending-deletion caller may not ACQUIRE new inventory.
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;

  -- Idempotency short-circuit (§5.3): a replay of a SUCCEEDED reserve returns
  -- the original hold, not oversell_rejected (the caller's own committed hold
  -- fills the batch, so the oversell gate below would misreport it).
  declare v_ex_hold uuid; v_ex_exp timestamptz;
  begin
    select hold_id, expires_at into v_ex_hold, v_ex_exp
      from venue.inventory_hold
     where identity_id = v_uid and command_idempotency_key = p_command_key;
    if v_ex_hold is not null then
      return jsonb_build_object('status','idempotency_replay','hold_id',v_ex_hold,
                                'expires_at',v_ex_exp);
    end if;
  end;

  -- NATIVE ISSUANCE GATE (§4): real draws are gated behind the flag, false for
  -- the entire life of 081. The flag is checked BEFORE any counter mutation, so
  -- the substrate provably cannot draw while native issuance is dark.
  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c
   where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  -- the batch's EVENT must be on_sale/live AND its SESSION must not be terminal
  -- (§5.3: "batch's session/event on_sale/live"; a session carries its own
  -- cancelled/completed state, 078).
  select e.status, s.status into v_s_status, v_sess_status
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
    join catalog.event_session s on s.session_id = b.event_session_id
   where b.batch_id = p_batch_id;
  if v_s_status is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;
  if v_s_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;
  -- ── 201 BLOCK V — the session's venue must be approved
  if not exists (select 1
                   from venue.inventory_batch b
                   join catalog.event_session s on s.session_id = b.event_session_id
                   join catalog.event e on e.event_id = s.event_id
                   join catalog.venue v on v.venue_id = e.venue_id
                  where b.batch_id = p_batch_id
                    and v.approval_status = 'approved') then
    raise exception 'precondition_failed: venue is not approved';
  end if;
  -- ── 201 BLOCK V END
  -- ── 185 BLOCK W — tier sale window (A's ruling 2026-10-26, CONTRACTS C2): refuse when the batch's
  -- tier is not on sale at now() by D's 162 predicate venue.ticket_type_on_sale (starts inclusive,
  -- ends exclusive, NULL = open; hidden tiers and events not on_sale/live are never on sale).
  -- After the idempotency replay above (an in-window hold replays unchanged after the window
  -- closes) and the flag/event/session gates; before the cap lock, the TTL and every write below.
  if not venue.ticket_type_on_sale(
           (select b.ticket_type_id from venue.inventory_batch b where b.batch_id = p_batch_id), now()) then
    raise exception 'precondition_failed: tier_not_on_sale';
  end if;
  -- ── 185 BLOCK W END
  -- ── 201 BLOCK K — a buyer hold draws only a public_sale batch of a public tier
  if not exists (select 1
                   from venue.inventory_batch b
                   join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
                  where b.batch_id = p_batch_id
                    and b.release_kind = 'public_sale'
                    and tt.visibility = 'public') then
    raise exception 'precondition_failed: not_buyer_inventory';
  end if;
  -- ── 201 BLOCK K END

  -- Per-user active-hold cap (C5) via an advisory xact lock on the identity —
  -- NEVER a COUNT(*)<limit trigger (write-skew). The cap key is a PFA-9 CLASS A
  -- key with NO frozen spelling (erratum E-28): unseeded => fail-to-ZERO
  -- (AUTHZ-M8 precedent), so a missing seed refuses every reserve loudly rather
  -- than admitting unbounded holds silently. Unreachable while the flag is off.
  perform pg_advisory_xact_lock(hashtext('inv_hold_cap:'||v_uid::text));
  begin
    select (c.value #>> '{}')::integer into v_cap_max
      from catalog.platform_config c
     where c.key = 'inventory.per_user_active_hold_max'
     order by c.version desc limit 1;
  exception when others then v_cap_max := null;
  end;
  v_cap_max := coalesce(v_cap_max, 0);
  select count(*) into v_active from venue.inventory_hold h
   where h.identity_id = v_uid and h.status = 'active';
  if v_active + 1 > v_cap_max then
    raise exception 'precondition_failed: hold_cap_exceeded';
  end if;

  -- Hold TTL is a PFA-9 CLASS A key with NO frozen spelling (E-28): unseeded =>
  -- REFUSE rather than invent a business policy (a TTL is policy, not a default).
  begin
    select (c.value #>> '{}')::interval into v_ttl
      from catalog.platform_config c
     where c.key = 'inventory.hold_ttl_interval'
     order by c.version desc limit 1;
  exception when others then v_ttl := null;
  end;
  if v_ttl is null then
    raise exception 'precondition_failed: hold_ttl_unset';
  end if;
  v_expires := now() + v_ttl;

  -- THE OVERSELL CHOKE-POINT: FOR UPDATE on the counter row, then the CHECK.
  select b.held, b.capacity, b.sold into v_held, v_cap, v_sold
    from venue.inventory_batch b where b.batch_id = p_batch_id for update;
  if v_held + v_sold + p_quantity > v_cap then
    raise exception 'precondition_failed: oversell_rejected';
  end if;

  update venue.inventory_batch set held = held + p_quantity, updated_at = now()
   where batch_id = p_batch_id;

  insert into venue.inventory_hold
         (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch_id, v_uid, p_quantity, 'active', v_expires, p_command_key)
  returning hold_id into v_hold_id;

  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'hold', p_quantity, 0, 'primary_sale', v_hold_id, v_uid);

  return jsonb_build_object('status','ok','hold_id',v_hold_id,'expires_at',v_expires,
                            'remaining',v_cap - (v_held + p_quantity) - v_sold);
exception when unique_violation then
  raise exception 'precondition_failed: idempotency_replay';
end;
$function$

;

-- venue.create_primary_checkout: the 198 body + 201 BLOCKS D, V, C, N, N2
CREATE OR REPLACE FUNCTION venue.create_primary_checkout(p_session_id uuid, p_items jsonb, p_hold_ids uuid[], p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid       uuid;
  v_sess_status text;
  v_evt_status  text;
  v_org_id    uuid;
  v_order_id  uuid;
  v_total     integer := 0;
  v_ex_id     uuid;
  v_ex_total  integer;
  v_ex_curr   text;
  v_item      jsonb;
  v_tt_id     uuid;
  v_qty       integer;
  v_price     integer;
  v_held      integer;
  v_snapshot  jsonb := '[]'::jsonb;
  -- A8/G2: the readiness operands, read once from the selling organization.
  v_org_ref    text;
  v_org_ready  boolean;
  v_org_status text;
  -- A8/G2b: the deliverability operands — the event's scope keys for the
  -- signing-key resolution, and the key that resolution finds.
  v_event_id    uuid;
  v_venue_id    uuid;
  v_signing_key uuid;
  -- A5: the buyer-side service fee. v_fee_bps is NUMERIC on purpose — the cast
  -- happens once, and an owner typo is caught by an explicit range check with a
  -- greppable message instead of a raw 22P02 out of an ::integer cast.
  v_fee_bps      numeric;
  v_fee_minor    integer;
  v_charge_total integer;
  -- ── 188 BLOCK D — the newest fee.buyer_service_bps version, raw jsonb (read by BLOCK R1)
  v_fee_raw      jsonb;
  -- ── 188 BLOCK D END
  -- ── 198 BLOCK D — kill switch, replay state, hold binding
  v_flag_raw    jsonb;
  v_ex_status   text;
  v_ex_live     boolean;
  v_bind_bid    uuid;
  v_bind_qty    integer;
  v_bind_ids    uuid[];
  v_bound_units integer;
  v_other_units integer;
  -- ── 198 BLOCK D END
  -- ── 201 BLOCK D — units the buyer-inventory filter excludes
  v_kind_units  integer;
  -- ── 201 BLOCK D END
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- OR-17 F-1 + E-23 gate FIRST — an acquisition refusal fires before ANY work
  -- (as 081's reserve does), so a non-ACTIVE buyer is turned away regardless of
  -- what else is in the request. F-1 (dsm §3.2, tests the caller; buyer_id =
  -- auth.uid()): refuse DELETION_PENDING. E-23: is_deletion_pending returns FALSE
  -- for ERASED, so the checkout buyer must be proven ACTIVE, not merely
  -- not-pending — the 077 F-6 / E-8 defensive-twin idiom. (Defensive: an ERASED
  -- identity cannot authenticate, but E-23 mandates the refusal be present and
  -- NOT dischargeable by is_deletion_pending alone.)
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;
  if exists (select 1 from kernel.identity_ext e
              where e.identity_id = v_uid and e.deletion_state = 'ERASED') then
    raise exception 'precondition_failed: identity_erased';
  end if;

  -- Idempotency short-circuit (C16): a replay of a succeeded checkout returns the
  -- original order, not a second one. DELIBERATELY AHEAD OF THE A8/G2 GATE: an
  -- order that already exists is a settled fact, and re-refusing it would turn a
  -- harmless client retry into a phantom failure after the money decision was
  -- already taken.
  -- IT ALSO CARRIES NO FEE FIELDS, DELIBERATELY. A replay is not a fresh quote:
  -- the buyer-side charge for this order was quoted on the ORIGINAL call and
  -- the edge already minted a PaymentIntent from it. Re-deriving the fee here
  -- from the CURRENT rate would silently move the price under an already-minted
  -- PI if the owner had changed fee.buyer_service_bps in between. The fee is
  -- not stored on venue."order" (see the A5 block below — total_minor is face
  -- value and nothing else on the row may carry it), so this function cannot
  -- reproduce the original quote and must not guess at one. `idempotency_replay`
  -- means "you already have this order — reuse the quote you already made."
  -- Recorded as R30-4 in the footer.
  select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
    from venue."order"
   where buyer_id = v_uid and command_idempotency_key = p_command_key;
  if v_ex_id is not null then
    -- ── 198 BLOCK P1 — replay carries order status and hold liveness (no price fields)
    select o.status into v_ex_status from venue."order" o where o.order_id = v_ex_id;
    select bool_and(h.status = 'active' and h.expires_at > now()) into v_ex_live
      from venue.inventory_hold h where h.order_id = v_ex_id;
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr,
                              'order_status',v_ex_status,'holds_live',v_ex_live);
    if false then
    -- ── 198 BLOCK P1 END
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
    -- ── 198 BLOCK P2
    end if;
    -- ── 198 BLOCK P2 END
  end if;
  -- ── 198 BLOCK F — kill switch: the NEWEST version, cast after the LIMIT
  select l.value into v_flag_raw
    from (select c.value
            from catalog.platform_config c
           where c.key = 'feature.native_issuance_enabled'
           order by c.version desc
           limit 1) l;
  if not coalesce((v_flag_raw #>> '{}')::boolean, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;
  -- ── 198 BLOCK F END

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'precondition_failed: no items';
  end if;

  -- Session must be sellable (event on_sale/live) and not terminal (§6.1). org_id
  -- is server-derived from the session's event; never client-trusted.
  select e.status, s.status, e.org_id, e.event_id, e.venue_id
    into v_evt_status, v_sess_status, v_org_id, v_event_id, v_venue_id
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
   where s.session_id = p_session_id;
  if v_sess_status is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  if v_evt_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;
  -- ── 201 BLOCK V — the session's venue must be approved
  if not exists (select 1
                   from catalog.venue v
                  where v.venue_id = v_venue_id
                    and v.approval_status = 'approved') then
    raise exception 'precondition_failed: venue is not approved';
  end if;
  -- ── 201 BLOCK V END

  -- ---- A8 / F §3.5 gate G2 — PAYOUT READINESS, FAIL CLOSED -----------------
  -- The organization whose event this is must have a BOUND destination AND a
  -- live `transfers` capability. Under Ruling A1/A2 the platform is merchant of
  -- record and the organization is paid later by POST /v1/transfers, so
  -- `transfers` active is what makes that transfer legal — F §3.5 rules that
  -- payouts_enabled is explicitly NOT part of this predicate (an organization
  -- that can be transferred to but cannot yet reach its bank keeps selling; the
  -- money rests in their Stripe balance and no ticket is harmed).
  -- Both operands are required: a bound ref with a dead capability is not
  -- ready, and a live-looking flag with no ref has nowhere to send money. The
  -- org row is read WITHOUT a lock on purpose — checkout moves no money, and
  -- 085's finalize is the authoritative money moment; taking a row lock on the
  -- organization here would serialize every buyer in the venue behind one row.
  --
  -- THIS READ IS LEGAL AND NEEDS NO GRANT — DO NOT "FIX" IT BY WIDENING ONE.
  -- kernel.organization revokes everything from `authenticated` and grants back
  -- only (org_id, display_name, status) (077:133-138), so a BUYER cannot read
  -- stripe_connect_account_ref or the §1 columns. This function is SECURITY
  -- DEFINER: it executes as the function owner, not as the caller, so the
  -- client-side revoke does not apply to it and the select below succeeds for
  -- every buyer without any column ever becoming client-readable. That is the
  -- whole design — the gate reads privileged state, the caller cannot. Anyone
  -- who "fixes" a permission error here by granting `authenticated` SELECT on
  -- these columns has published the payout destination of every organization
  -- on the platform to every signed-in user. The read path for humans is
  -- kernel.get_org_connect_state (§6), which masks the account id.
  select o.stripe_connect_account_ref, o.connect_transfers_active, o.status
    into v_org_ref, v_org_ready, v_org_status
    from kernel.organization o
   where o.org_id = v_org_id;

  -- G2a — ORGANIZATION STATUS, AND IT IS CHECKED FIRST.
  -- A suspended organization could sell: this function read kernel.organization
  -- for two columns and never consulted `status`, so a suspended org with a
  -- bound acct_, transfers active and a live signing key refused only on the
  -- fee key. That is inconsistent with 093's own posture — this same migration
  -- added status ∈ ('approved','active') to BOTH Connect binders (§4, §5) and to
  -- the dashboard read verb (§6), on the reasoning that an organization the
  -- platform has suspended must not move money or name a payee. SELLING is the
  -- money-path entry that was left out, and it is the exact twin of the gap the
  -- rest of this slice closed.
  --
  -- ORDERED BEFORE THE CONNECT GATE, DELIBERATELY — this is the one place my
  -- ladder diverges from the one specified, and it is the divergence that was
  -- asked for: the more FUNDAMENTAL fact should win the error. "This
  -- organization is suspended" explains the refusal completely and is actionable
  -- by exactly one party (the platform, via kernel.set_org_status). Leading with
  -- `payout_not_ready` would send an operator to re-check Stripe — where they
  -- would find nothing wrong, because nothing is — for a condition Stripe has no
  -- part in. A suspended org that is ALSO not connect-ready should still report
  -- the suspension, because resolving the Connect side would not make it
  -- sellable.
  --
  -- FAILS CLOSED ON NULL. A null status covers the org row having vanished
  -- (SELECT INTO leaves every target null when no row matches), which is
  -- stricter than the previous behaviour: that case used to fall through to
  -- `payout_not_ready`, which was accidentally correct rather than deliberately.
  -- Any status outside the pair — 'applied', 'suspended', 'closed', or anything
  -- a later migration adds — refuses. X-12 restrictive: unknown authorizes
  -- NOTHING.
  --
  -- SCOPE, FOR THE RECORD, since this lands late in 093's life: 093 has never
  -- reached production; this is the same primary-ticketing atomic contract; it
  -- adds NO object and NO column, being a body-only CREATE OR REPLACE of a
  -- function 093 already replaces for G2/G2b/A5. THE OBJECT CENSUS DOES NOT
  -- MOVE: this change creates nothing, so whatever the slice's object count is
  -- at assembly time, this clause does not alter it.
  if v_org_status is null or v_org_status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_active — a % organization may not sell', coalesce(v_org_status,'missing');
  end if;

  if v_org_ref is null or coalesce(v_org_ready, false) is not true then
    -- X-12 restrictive reading: absent or unknown state authorizes NOTHING.
    raise exception 'precondition_failed: payout_not_ready';
  end if;
  -- ---- end A8 / G2 ---------------------------------------------------------

  -- ---- A8 / G2b — SIGNING-KEY DELIVERABILITY, FAIL CLOSED -----------------
  -- THE DEFECT THIS CLOSES: with ZERO signing keys in the database an order was
  -- created, the buyer paid, the webhook called venue.finalize_primary_order,
  -- and the mint raised `no_active_signing_key` (083:513-530) — AFTER the
  -- PaymentIntent was confirmed. The buyer is charged and holds no ticket, and
  -- with the refund executor undeployed and kernel.mark_refund_state without a
  -- caller, nothing gives the money back automatically. G2 asks whether the
  -- VENUE can be paid; this asks whether the BUYER can be delivered to. The
  -- owner's SALEABLE rule covers both: do not sell what Snatch It cannot
  -- honour, and a sale that provably cannot mint a ticket is the clearest case.
  --
  -- THE PREDICATE IS COPIED FROM THE MINT, NOT APPROXIMATED. A gate looser than
  -- the mint's would pass here and fail there, which is the bug being closed —
  -- so this is venue.finalize_primary_order's own resolution (085:1948-1960)
  -- character for character: active status, inside [not_before, not_after), and
  -- a scope that GOVERNS this event, ordered MOST SPECIFIC FIRST — per_event
  -- outranks per_venue outranks global. 083:517-527 then re-validates the
  -- pinned key with the identical conditions, so a key this finds is a key the
  -- mint accepts.
  --
  -- The `order by … limit 1` is retained even though a bare EXISTS would be
  -- logically equivalent for a yes/no gate: the ordering is what makes this
  -- visibly the SAME query as finalize's, so a future change to the precedence
  -- there is an obvious mismatch here rather than a silent divergence.
  --
  -- FAILS CLOSED ON EVERY AMBIGUITY: no key at all, a key that is inactive, one
  -- not yet in force, one already expired, or one whose scope does not govern
  -- this event all resolve to NULL and refuse. This gate is ON from the moment
  -- 093 applies and stays on until the ruling-B bootstrap key row exists — the
  -- owner ceremony (093 scope item 2) — which is the correct resting state:
  -- until that row exists, no ticket can be minted by anything.
  --
  -- NOTHING HERE PROVISIONS A KEY. Ruling B parks kernel.provision_signing_key
  -- and rotate_signing_key as unconditional raises, and this slice neither
  -- un-parks them nor inserts a signing_key row. A gate that could mint its own
  -- key would defeat the two-person KMS ceremony it exists to wait for.
  select k.key_id into v_signing_key
    from kernel.signing_key k
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and (   (k.scope = 'per_event' and k.event_id = v_event_id)
          or (k.scope = 'per_venue' and k.venue_id = v_venue_id)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_signing_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before a ticket can be sold';
  end if;
  -- The key is NOT pinned onto the order. Resolution happens again at finalize
  -- under the rank-1 session lock (085:1943-1960), which is the correct place
  -- for it: a key legitimately rotated between checkout and payment must not be
  -- frozen by a value captured here, and venue."order" has no column for one.
  -- This gate proves DELIVERABILITY AT QUOTE TIME; finalize decides WHICH key.
  -- ---- end A8 / G2b --------------------------------------------------------

  -- ---- A5 — BUYER SERVICE FEE RATE, FAIL CLOSED ---------------------------
  -- STRICTLY AFTER the gate above: an organization that cannot be paid is
  -- refused before the rate is read at all. STRICTLY BEFORE the item loop: an
  -- unset rate refuses without doing hold/inventory work.
  -- Same platform_config idiom as the money code (085:1646-1647) — highest
  -- version wins, and `#>> '{}'` turns the seeded jsonb `null` into a SQL NULL.
  -- ── 188 BLOCK R1 — the rate: the NEWEST version first, the cast after (A, 2026-10-27; registry 188)
  -- 093's read below casts in an ordered target list. On a seq-scan plan the cast runs on EVERY
  -- version of the key before ORDER BY / LIMIT, so one non-numeric version anywhere in the
  -- append-only history raised 22P02 under a valid newest value: pricing depended on the plan.
  -- The subquery picks the newest row (a subquery with LIMIT is never pulled up) and only that
  -- one value is inspected, then cast. JSON null and a missing key keep 093's service_fee_unset
  -- below; any other non-number refuses here with the same code (the primary-checkout edge maps
  -- it to its 503 service_fee_unset activation blocker, index.ts:549). 093's range check below
  -- is unchanged.
  select l.value into v_fee_raw
    from (select c.value
            from catalog.platform_config c
           where c.key = 'fee.buyer_service_bps'
           order by c.version desc
           limit 1) l;
  if jsonb_typeof(v_fee_raw) not in ('number', 'null') then
    raise exception 'precondition_failed: service_fee_unset — fee.buyer_service_bps is a JSON %, not a number; selling cannot be activated until the owner sets an integer', jsonb_typeof(v_fee_raw);
  end if;
  v_fee_bps := case when jsonb_typeof(v_fee_raw) = 'number' then (v_fee_raw #>> '{}')::numeric end;
  -- 093's read stays below byte for byte (the strip rule) and never runs:
  if false then
  -- ── 188 BLOCK R1 END
  select (c.value #>> '{}')::numeric into v_fee_bps
    from catalog.platform_config c
   where c.key = 'fee.buyer_service_bps'
   order by c.version desc limit 1;
  -- ── 188 BLOCK R2 — closes R1's never-taken branch
  end if;
  -- ── 188 BLOCK R2 END
  -- THE OWNER STOP (A5): "No service-fee percentage is hardcoded in migration
  -- 093. No percentage is invented anywhere." An unset rate must REFUSE TO
  -- QUOTE. It must never fall back to zero: that would sell the ticket at face
  -- value with no platform revenue, and settlement lines are append-only with a
  -- write-once header, so revenue not recognised at the sale can never be
  -- restated afterwards. A missing KEY reads the same as a null VALUE and is
  -- refused identically — X-12 restrictive: absent state authorizes NOTHING.
  -- Distinct and greppable on purpose; this is the error that will be seen at
  -- activation if the rate was never set, and it must name its own cause.
  if v_fee_bps is null then
    raise exception 'precondition_failed: service_fee_unset — fee.buyer_service_bps has no value; selling cannot be activated until the owner sets it';
  end if;
  -- Bare integer basis points, 0..10000 — the shape of catalog.resale_policy
  -- .price_cap_bps / .royalty_bps (078:258-261). A fractional or out-of-band
  -- value is an owner typo, and a typo in a money rate fails closed.
  if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then
    raise exception 'precondition_failed: service_fee_out_of_range — fee.buyer_service_bps must be an integer 0..10000, got %', v_fee_bps;
  end if;
  -- ---- end A5 rate resolution ----------------------------------------------

  -- Validate items and snapshot the server-authoritative price ONCE per item
  -- (§6.1: a SINGLE server snapshot — the same value backs total_minor AND the
  -- line item, so a concurrent set_ticket_type_price cannot make them diverge),
  -- then prove the buyer's ACTIVE holds cover each item's quantity for THIS
  -- session (holds belong to the buyer, are active, not expired — §6.1). Money
  -- never moves; the authoritative held→sold conversion + oversell backstop
  -- (C27) is 085/finalize, which MUST re-read hold status + re-derive capacity
  -- under the batch FOR UPDATE (forward obligation — see governance E-40).
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_tt_id := (v_item->>'ticket_type_id')::uuid;
    v_qty   := (v_item->>'quantity')::integer;
    if v_tt_id is null or v_qty is null or v_qty <= 0 then
      raise exception 'precondition_failed: bad_item';
    end if;

    select tt.price_minor into v_price
      from venue.ticket_type tt
     where tt.ticket_type_id = v_tt_id;
    if v_price is null then
      raise exception 'not_found: ticket type %', v_tt_id using errcode = 'P0002';
    end if;

    -- coverage: sum of the buyer's active, unexpired holds for batches of this
    -- ticket_type in this session must be >= the requested quantity.
    select coalesce(sum(h.quantity), 0) into v_held
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
     where h.hold_id = any(p_hold_ids)
       and h.identity_id = v_uid
       and h.status = 'active'
       and h.expires_at > now()
       and b.ticket_type_id = v_tt_id
       and b.event_session_id = p_session_id;
    if v_held < v_qty then
      raise exception 'precondition_failed: holds do not cover item (type %, need %, held %)', v_tt_id, v_qty, v_held;
    end if;

    v_total := v_total + (v_price * v_qty);
    -- carry the ONE snapshotted price forward; the line item is written from
    -- this, never re-read, so order.total_minor = Σ(order_item.unit_price × qty).
    v_snapshot := v_snapshot || jsonb_build_array(
      jsonb_build_object('tt', v_tt_id, 'qty', v_qty, 'price', v_price));
  end loop;

  -- ---- A5 — THE FEE AMOUNT, AND WHAT IT IS *NOT* --------------------------
  -- Derived "from the base in integer cents, half-up"
  -- (docs/phase2/_decisions/A_venue_money.md:115). round() on numeric is
  -- half-away-from-zero and v_total is non-negative, so that IS half-up here.
  v_fee_minor    := round(v_total::numeric * v_fee_bps / 10000)::integer;
  v_charge_total := v_total + v_fee_minor;
  --
  -- *** READ THIS BEFORE CHANGING ANYTHING BELOW — THE SINGLE MOST
  -- *** MISREADABLE LINE IN THIS MIGRATION:
  -- venue."order".total_minor STAYS FACE VALUE. THE FEE IS NEVER ADDED TO IT.
  -- Ruling A5 fixes the venue's entitlement at the configured ticket face
  -- value and subtracts no platform fee from it, because Snatch It's revenue
  -- is BUYER-FUNDED and collected at checkout, not deducted at settlement. The
  -- settlement revenue seam (093 scope item 11) reads total_minor as the
  -- venue's gross, so folding the buyer fee into that column would pay the
  -- venue the platform's own revenue — silently, in an append-only ledger with
  -- no delete and a write-once header. The fee exists ONLY on the buyer's
  -- charge: it rides out in the return below, the edge mints a PaymentIntent
  -- for charge_total_minor, and no column on venue."order" ever carries it.
  -- The insert below is therefore UNCHANGED and must stay unchanged.
  -- ---- end A5 fee amount ---------------------------------------------------

  -- Create the pending order + items in one inner block. source is server-tagged;
  -- the frozen §6.1 signature carries no source hint and the rail is dark, so 'web'
  -- is the inert placeholder (owner-owed-forward, E-39). Candidate columns stay
  -- NULL (R2B/C112 — no promoter tables until 090). A concurrent C16 replay (both
  -- submits pass the short-circuit above, the loser trips order_buyer_command_uq)
  -- returns idempotency_replay, not a raw 23505 — the 081 reserve idiom. Scoped to
  -- the INSERTs so the gate's FOR SHARE lock on identity_ext (taken above via
  -- is_deletion_pending, F-11) is held to commit, outside this savepoint.
  begin
    insert into venue."order" (buyer_id, event_session_id, org_id, status, source,
                               total_minor, currency, command_idempotency_key)
    values (v_uid, p_session_id, v_org_id, 'pending', 'web', v_total, 'USD', p_command_key)
    returning order_id into v_order_id;

    for v_item in select * from jsonb_array_elements(v_snapshot) loop
      insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor, currency)
      values (v_order_id, (v_item->>'tt')::uuid, (v_item->>'qty')::integer,
              (v_item->>'price')::integer, 'USD');
    end loop;
  exception when unique_violation then
    -- the C16 (buyer, command_key) race: the other txn committed the order first.
    select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
      from venue."order"
     where buyer_id = v_uid and command_idempotency_key = p_command_key;
    if not found then raise; end if;   -- a different unique violation (e.g. a dup item)
    -- No fee fields here either, for the same reason as the C16 short-circuit
    -- above: the winning transaction produced the quote, and this loser must
    -- not mint a second, possibly different one (R30-4).
    -- ── 198 BLOCK P3 — the same replay state as BLOCK P1 (the winner's order)
    select o.status into v_ex_status from venue."order" o where o.order_id = v_ex_id;
    select bool_and(h.status = 'active' and h.expires_at > now()) into v_ex_live
      from venue.inventory_hold h where h.order_id = v_ex_id;
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr,
                              'order_status',v_ex_status,'holds_live',v_ex_live);
    if false then
    -- ── 198 BLOCK P3 END
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
    -- ── 198 BLOCK P4
    end if;
    -- ── 198 BLOCK P4 END
  end;
  -- ── 198 BLOCK B — bind each item to the caller's named holds on ONE covering batch
  perform 1
     from venue.inventory_hold h
     join venue.inventory_batch b on b.batch_id = h.batch_id
    where h.hold_id = any(p_hold_ids)
      and h.identity_id = v_uid
      and h.status = 'active'
      and h.expires_at > now()
      and b.event_session_id = p_session_id
    order by h.hold_id
      for update of h;
  for v_item in select * from jsonb_array_elements(v_snapshot) loop
    v_tt_id := (v_item->>'tt')::uuid;
    v_qty   := (v_item->>'qty')::integer;
    select x.batch_id, x.q, x.ids
      into v_bind_bid, v_bind_qty, v_bind_ids
      from (select h.batch_id,
                   sum(h.quantity)::integer as q,
                   array_agg(h.hold_id order by h.hold_id) as ids
              from venue.inventory_hold h
              join venue.inventory_batch b on b.batch_id = h.batch_id
              left join venue."order" o on o.order_id = h.order_id
             where h.hold_id = any(p_hold_ids)
               and h.identity_id = v_uid
               and h.status = 'active'
               and h.expires_at > now()
               and b.ticket_type_id = v_tt_id
               and b.event_session_id = p_session_id
               and (h.order_id is null or o.status = 'cancelled')
               -- ── 201 BLOCK C — only a public_sale batch of a public tier counts toward coverage
               and b.release_kind = 'public_sale'
               and exists (select 1 from venue.ticket_type tt
                            where tt.ticket_type_id = b.ticket_type_id
                              and tt.visibility = 'public')
               -- ── 201 BLOCK C END
             group by h.batch_id) x
     order by (x.q >= v_qty) desc,
              case when x.q >= v_qty then x.q end,
              x.q desc,
              x.batch_id
     limit 1;
    if coalesce(v_bind_qty, 0) < v_qty then
      select coalesce(sum(h.quantity) filter (where h.order_id is not null and o.status <> 'cancelled'), 0)::integer,
             coalesce(sum(h.quantity) filter (where h.order_id is null or o.status = 'cancelled'), 0)::integer
               - coalesce(v_bind_qty, 0)
        into v_bound_units, v_other_units
        from venue.inventory_hold h
        join venue.inventory_batch b on b.batch_id = h.batch_id
        left join venue."order" o on o.order_id = h.order_id
       where h.hold_id = any(p_hold_ids)
         and h.identity_id = v_uid
         and h.status = 'active'
         and h.expires_at > now()
         and b.ticket_type_id = v_tt_id
         and b.event_session_id = p_session_id;
      -- ── 201 BLOCK N — the refusal also reports the units the buyer-inventory filter excluded
      select coalesce(sum(h.quantity), 0)::integer
        into v_kind_units
        from venue.inventory_hold h
        join venue.inventory_batch b on b.batch_id = h.batch_id
        join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
        left join venue."order" o on o.order_id = h.order_id
       where h.hold_id = any(p_hold_ids)
         and h.identity_id = v_uid
         and h.status = 'active'
         and h.expires_at > now()
         and b.ticket_type_id = v_tt_id
         and b.event_session_id = p_session_id
         and (h.order_id is null or o.status = 'cancelled')
         and not (b.release_kind = 'public_sale' and tt.visibility = 'public');
      v_other_units := v_other_units - v_kind_units;
      raise exception 'precondition_failed: holds do not cover item (type %, need %, held %)',
        v_tt_id, v_qty, coalesce(v_bind_qty, 0)
        using detail = format('bound_to_pending_order_units=%s other_batch_units=%s non_buyer_kind_units=%s',
                              v_bound_units, v_other_units, v_kind_units);
      if false then
      -- ── 201 BLOCK N END
      raise exception 'precondition_failed: holds do not cover item (type %, need %, held %)',
        v_tt_id, v_qty, coalesce(v_bind_qty, 0)
        using detail = format('bound_to_pending_order_units=%s other_batch_units=%s', v_bound_units, v_other_units);
      -- ── 201 BLOCK N2
      end if;
      -- ── 201 BLOCK N2 END
    end if;
    update venue.inventory_hold set order_id = v_order_id
     where hold_id = any(v_bind_ids);
  end loop;
  -- ── 198 BLOCK B END

  -- total_minor is FACE VALUE (the venue's entitlement and the settlement
  -- seam's gross); buyer_fee_minor is the platform's buyer-funded revenue; and
  -- charge_total_minor is the ONLY figure the PaymentIntent may be minted for.
  -- `buyer_fee` is the corpus noun for exactly this money (public.payments,
  -- 000:982-985; and the config namespace already carries
  -- refund.buyer_fee_refundable, 078:1550) — not an invented name.
  -- org_id rides out on the SUCCESS return ONLY. Its single consumer is
  -- metadata[org_id] on the PaymentIntent, which the webhook's organization arm
  -- joins on (F §3.6(1)) — and the edge cannot derive it any other way: reading
  -- venue."order" or kernel.organization with the service_role client is 42501
  -- (no table privilege exists in either schema for that role). It is
  -- DELIBERATELY ABSENT from both idempotency_replay returns: that path reuses
  -- an existing PaymentIntent and mints no new metadata, so it has no use for
  -- the value, and supplying one would invite exactly the re-derivation the fee
  -- fields were kept off those returns to prevent (R30-4).
  return jsonb_build_object('status','ok','order_id',v_order_id,
                            'org_id',v_org_id,
                            'total_minor',v_total,'currency','USD',
                            'buyer_fee_minor', v_fee_minor,
                            'charge_total_minor', v_charge_total);
end;
$function$

;

-- venue.finalize_primary_order: the 198 body + 201 BLOCKS D, E
CREATE OR REPLACE FUNCTION venue.finalize_primary_order(p_order_id uuid, p_payment_id uuid, p_command_key text, p_instrument_fingerprint text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order   venue."order"%rowtype;
  v_pay     record;
  v_state   text;
  v_item    record;
  v_batch   record;
  v_hold    record;
  v_dec     integer;
  v_need    integer;
  v_key     uuid;
  v_event   uuid;
  v_venue   uuid;
  v_atoms   uuid[] := '{}';
  v_res     jsonb;
  -- ── 198 BLOCK D — the order's own reservation
  v_bound   boolean;
  -- ── 198 BLOCK D END
  -- ── 201 BLOCK D — the order's event and session state
  v_evt_status  text;
  v_sess_status text;
  -- ── 201 BLOCK D END
begin
  select * into v_order from venue."order" where order_id = p_order_id;
  if not found then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;

  -- E-23 (085 arm), the F-6/E-8 defensive twin: an ERASED buyer acquires
  -- NOTHING — is_deletion_pending returns FALSE for ERASED and cannot carry
  -- this refusal. DELETION_PENDING COMPLETES (F-1 tests the caller — this is
  -- the service_role money path; 16b preserves mid-flight money processing).
  select ie.deletion_state into v_state
    from kernel.identity_ext ie where ie.identity_id = v_order.buyer_id;
  if v_state = 'ERASED' then
    raise exception 'precondition_failed: buyer identity is erased — no acquisition';
  end if;

  -- C35: the payment IS the authority — verified, succeeded, and the buyer's.
  select p.buyer_id, p.total, p.status into v_pay from public.payments p where p.id = p_payment_id;
  if not found then
    raise exception 'payment_unverified: payment % not found', p_payment_id;
  end if;
  if v_pay.status <> 'succeeded' then
    raise exception 'payment_unverified: payment % is %', p_payment_id, v_pay.status;
  end if;
  if v_pay.buyer_id <> v_order.buyer_id then
    raise exception 'payment_unverified: payment buyer does not match order buyer';
  end if;
  -- the payment must at least COVER the order (R1 P1 — a $1 charge cannot
  -- finalize a $500 order; the link ledger must not self-certify a mismatch).
  if v_pay.total < v_order.total_minor then
    raise exception 'payment_unverified: payment % (% minor) does not cover order % (% minor)',
      p_payment_id, v_pay.total, p_order_id, v_order.total_minor;
  end if;
  -- a payment already carrying a refund is not a finalize target (R6 P2 — a
  -- delayed webhook must not mint tickets for money that was refunded).
  if exists (select 1 from kernel.refund r where r.payment_id = p_payment_id and r.status <> 'failed') then
    raise exception 'payment_unverified: payment % already carries a refund', p_payment_id;
  end if;

  -- rank 1: the Event/Session lock (also serializes the mint's serial draw and
  -- excludes update_event_session's schedule guard — E-46(a)).
  perform 1 from catalog.event_session s where s.session_id = v_order.event_session_id for update;
  select s.event_id into v_event from catalog.event_session s where s.session_id = v_order.event_session_id;
  select e.venue_id into v_venue from catalog.event e where e.event_id = v_event;

  -- signing-key resolution (§7.1): the activation-boundary predicate, most
  -- specific scope first. NO key ⇒ fail closed (the mint would refuse anyway;
  -- resolving here yields the cleaner token at the contracted boundary).
  select k.key_id into v_key
    from kernel.signing_key k
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and (   (k.scope = 'per_event' and k.event_id = v_event)
          or (k.scope = 'per_venue' and k.venue_id = v_venue)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted';
  end if;

  -- rank 3: the order — re-check state UNDER the lock; replay short-circuits.
  select * into v_order from venue."order" where order_id = p_order_id for update;
  if v_order.status = 'paid' then
    select coalesce(array_agg(t.ticket_atom_id order by t.ticket_atom_id), '{}') into v_atoms
      from kernel.tickets t
      join kernel.ticket_ownership_log l1
        on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
     where l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id = p_order_id);
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_atoms),
                              'order_status','paid');
  end if;
  if v_order.status <> 'pending' then
    raise exception 'precondition_failed: order % is % — only a pending order finalizes', p_order_id, v_order.status;
  end if;

  -- ── 201 BLOCK E — a cancelled event or session converts and issues nothing
  select e.status, s.status into v_evt_status, v_sess_status
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
   where s.session_id = v_order.event_session_id;
  if v_evt_status = 'cancelled' then
    raise exception 'refund_required: event_cancelled — order % was paid for a cancelled event; nothing was converted or issued and the charge must be refunded', p_order_id;
  end if;
  if v_sess_status = 'cancelled' then
    raise exception 'refund_required: session_cancelled — order % was paid for a cancelled session; nothing was converted or issued and the charge must be refunded', p_order_id;
  end if;
  -- ── 201 BLOCK E END
  -- ── 198 BLOCK K1 — a bound order locks its own batches, then its own holds ascending
  v_bound := exists (select 1 from venue.inventory_hold h where h.order_id = p_order_id);
  if v_bound then
    perform 1 from venue.inventory_batch b
     where b.batch_id in (select h.batch_id from venue.inventory_hold h where h.order_id = p_order_id)
     order by b.batch_id
     for update;
    perform 1 from venue.inventory_hold h
     where h.order_id = p_order_id
     order by h.hold_id
     for update;
  else
  -- ── 198 BLOCK K1 END
  -- DETERMINISTIC batch pre-lock (R6 P1): resolve every item's batch, then take
  -- the batch locks ascending by batch_id BEFORE any per-item work, so two
  -- concurrent finalizes over the same batch set can never AB-BA deadlock.
  -- Batch attribution is HEURISTIC (E-58): 082's checkout persists no order->hold
  -- linkage on the immutable order_item, so the batch is named by the buyer's
  -- reservation for this tt/session, preferring an ACTIVE unexpired hold; a
  -- future package that persists hold_ids on the order discharges the heuristic.
  perform 1 from venue.inventory_batch b
   where b.batch_id in (
     select distinct (
       select b2.batch_id
         from venue.inventory_hold h
         join venue.inventory_batch b2 on b2.batch_id = h.batch_id
        where h.identity_id = v_order.buyer_id
          -- ── 198 BLOCK L1
          and h.order_id is null
          -- ── 198 BLOCK L1 END
          and b2.ticket_type_id = oi.ticket_type_id
          and b2.event_session_id = v_order.event_session_id
        order by (h.status = 'active' and h.expires_at > now()) desc, h.created_at desc
        limit 1)
       from venue.order_item oi where oi.order_id = p_order_id)
   order by b.batch_id
   for update;
  -- ── 198 BLOCK K2
  end if;
  -- ── 198 BLOCK K2 END

  -- per item: the E-40 hold re-read, the E-47(b) ordering (held -= live-backed
  -- BEFORE the mint's sold += q, same txn), then the mint. Batches already locked.
  for v_item in
    select oi.id, oi.ticket_type_id, oi.quantity
      from venue.order_item oi where oi.order_id = p_order_id order by oi.id
  loop
    -- ── 198 BLOCK K3 — bound order: the item's batch is its bound holds' batch; convert only those
    if v_bound then
      select b.* into v_batch
        from venue.inventory_hold h
        join venue.inventory_batch b on b.batch_id = h.batch_id
       where h.order_id = p_order_id
         and b.ticket_type_id = v_item.ticket_type_id
         and b.event_session_id = v_order.event_session_id
       order by h.hold_id
       limit 1;
      if v_batch.batch_id is null then
        raise exception 'precondition_failed: no reservation names a batch for item % (checkout guarantees coverage)', v_item.id;
      end if;
      v_dec := 0; v_need := v_item.quantity;
      for v_hold in
        select h.hold_id, h.quantity
          from venue.inventory_hold h
         where h.order_id = p_order_id and h.identity_id = v_order.buyer_id
           and h.batch_id = v_batch.batch_id and h.status = 'active'
         order by h.hold_id
         for update
      loop
        update venue.inventory_hold set status = 'converted', updated_at = now()
         where hold_id = v_hold.hold_id;
        v_dec := v_dec + v_hold.quantity;
      end loop;
      if (v_batch.capacity - (v_batch.held - v_dec) - v_batch.sold) < v_item.quantity then
        raise exception 'refund_required: hold_lapsed — order % item % needs % but its bound hold lapsed before payment and batch % has no headroom; the charge must be refunded',
          p_order_id, v_item.id, v_item.quantity, v_batch.batch_id;
      end if;
    else
    -- ── 198 BLOCK K3 END
    select b.* into v_batch
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
     where h.identity_id = v_order.buyer_id
       -- ── 198 BLOCK L2
       and h.order_id is null
       -- ── 198 BLOCK L2 END
       and b.ticket_type_id = v_item.ticket_type_id
       and b.event_session_id = v_order.event_session_id
     order by (h.status = 'active' and h.expires_at > now()) desc, h.created_at desc
     limit 1;
    if v_batch.batch_id is null then
      raise exception 'precondition_failed: no reservation names a batch for item % (checkout guarantees coverage)', v_item.id;
    end if;

    -- E-40: only LIVE holds back the held-decrement — a blind held -= q on a
    -- swept hold double-decrements. Convert ALL of the buyer's active-unexpired
    -- holds on this batch WHOLE; held -= their sum (any over-held remainder
    -- returns to free capacity). The un-backed part draws free capacity (C27).
    v_dec := 0; v_need := v_item.quantity;
    for v_hold in
      select h.hold_id, h.quantity
        from venue.inventory_hold h
       where h.identity_id = v_order.buyer_id and h.batch_id = v_batch.batch_id
         -- ── 198 BLOCK L3
         and h.order_id is null
         -- ── 198 BLOCK L3 END
         and h.status = 'active' and h.expires_at > now()
       order by h.hold_id
       for update
    loop
      update venue.inventory_hold set status = 'converted', updated_at = now()
       where hold_id = v_hold.hold_id;
      v_dec := v_dec + v_hold.quantity;
    end loop;

    -- clean oversell token BEFORE the arithmetic; C27 remains the backstop.
    if (v_batch.capacity - (v_batch.held - v_dec) - v_batch.sold) < v_item.quantity then
      raise exception 'oversell_rejected: item % needs % — batch % has no headroom', v_item.id, v_item.quantity, v_batch.batch_id;
    end if;
    -- ── 198 BLOCK K4
    end if;
    -- ── 198 BLOCK K4 END
    if v_dec > 0 then
      update venue.inventory_batch set held = held - v_dec, updated_at = now()
       where batch_id = v_batch.batch_id;                       -- E-47(b): BEFORE the mint's sold += q
    end if;

    v_res := kernel.issue_ticket_atoms(
      jsonb_build_object(
        'session_id', v_order.event_session_id, 'org_id', v_order.org_id,
        'ticket_type_id', v_item.ticket_type_id, 'batch_id', v_batch.batch_id,
        'owner_id', v_order.buyer_id, 'quantity', v_item.quantity,
        'cause', 'issue', 'cause_ref', v_item.id, 'signing_key_id', v_key),
      p_command_key || ':' || v_item.id::text);
    v_atoms := v_atoms || (select coalesce(array_agg(x.v::uuid), '{}')
                             from jsonb_array_elements_text(v_res -> 'atom_ids') x(v));
  end loop;

  update venue."order" set status = 'paid', updated_at = now() where order_id = p_order_id;

  -- the payment link — INSERTED BEFORE the resolver call (load-bearing: §17.14's
  -- read sees the fingerprint in-snapshot; SEAM-2a bars it as a parameter).
  insert into kernel.payment_native (payment_id, order_id, amount_minor, instrument_fingerprint)
  values (p_payment_id, p_order_id, v_order.total_minor, p_instrument_fingerprint);

  -- attribution freezes at order-paid (the money event). The stub NEVER raises
  -- (§17.14 — a raise here would roll back the money and the tickets).
  perform venue.resolve_order_attribution(p_order_id);

  return jsonb_build_object('status','ok','atom_ids', to_jsonb(v_atoms), 'order_status','paid');
exception when unique_violation then
  -- concurrent webhook redelivery: the winner finalized; return its atom set.
  select * into v_order from venue."order" where order_id = p_order_id;
  if v_order.status = 'paid' then
    select coalesce(array_agg(t.ticket_atom_id order by t.ticket_atom_id), '{}') into v_atoms
      from kernel.tickets t
      join kernel.ticket_ownership_log l1
        on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
     where l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id = p_order_id);
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_atoms),
                              'order_status','paid');
  end if;
  raise;
end;
$function$

;

-- ── step 3: the engine is reachable only through its definer wrapper ─────────
revoke execute on function venue.reserve_primary_inventory(uuid, integer, text) from authenticated;

-- ── step 4: POST-FLIGHT ──────────────────────────────────────────────────────
do $pc$
declare r record;
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)'))) is distinct from '079aa9b5c7185a7acdd969d4afe6d77a'
  or md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))) is distinct from '50ed88e09825c811a0aa155d06b00f32'
  or md5(pg_get_functiondef(to_regprocedure('venue.finalize_primary_order(uuid, uuid, text, text)'))) is distinct from '3c359ec14a788be8398d67210828b773' then
    raise exception 'precondition_failed: 201 self-check — a written body is not this migration''s; this file was modified'; end if;
  for r in select * from (values ('r', 'venue.reserve_primary_inventory(uuid, integer, text)'),
                                 ('c', 'venue.create_primary_checkout(uuid, jsonb, uuid[], text)'),
                                 ('f', 'venue.finalize_primary_order(uuid, uuid, text, text)'),
                                 ('w', 'public.reserve_primary_tier(uuid, uuid, integer, text)')) as t(k, sig) loop
    if exists (select 1 from pg_proc where oid = to_regprocedure(r.sig)
                 and (not prosecdef or proconfig is distinct from array['search_path=""'] or proowner <> 'postgres'::regrole))
    or (select prosecdef::text || '|' || coalesce(proconfig::text, '<none>') || '|' || proowner::regrole::text
          from pg_proc where oid = to_regprocedure(r.sig)) <> current_setting('a201.pos_' || r.k) then
      raise exception 'precondition_failed: 201 self-check — DEFINER, search_path or owner of % moved', r.sig; end if;
    if r.k <> 'r' and (select coalesce(proacl::text, '<default>') from pg_proc where oid = to_regprocedure(r.sig)) <> current_setting('a201.acl_' || r.k) then
      raise exception 'precondition_failed: 201 self-check — the EXECUTE ACL of % moved', r.sig; end if;
  end loop;
  if (select coalesce(string_agg(t.e, ',' order by t.e), '<none>')
     from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                  || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
                  || '/' || a.grantor::regrole::text as e
             from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)')) t) is distinct from current_setting('a201.acl_r_after')
  or has_function_privilege('authenticated', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE')
  or has_function_privilege('anon', 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE')
  or not has_function_privilege((select proowner from pg_proc where oid = to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)')), 'venue.reserve_primary_inventory(uuid, integer, text)', 'EXECUTE') then
    raise exception 'precondition_failed: 201 self-check — the engine''s EXECUTE entries are not the captured ones minus authenticated, a client role can still execute it, or the wrapper''s owner cannot'; end if;
  if md5(pg_get_functiondef(to_regprocedure('venue.sweep_expired_inventory_holds(integer)'))) is distinct from 'd2ed033325aa3972e9c1be48bb8f4e91'
  or md5(pg_get_functiondef(to_regprocedure('venue.release_inventory_hold(uuid, text)'))) is distinct from 'b981bef80b10455a0c45a6e908c91aec'
  or md5(pg_get_functiondef(to_regprocedure('kernel.issue_ticket_atoms(jsonb, text)'))) is distinct from '9f559af1202fa0e7d8bae0c44df93ff8'
  or md5(pg_get_functiondef(to_regprocedure('venue.cancel_pending_order(uuid, text, text)'))) is distinct from '3d7fef64c44483586f46b568cb92c610'
  or md5(pg_get_functiondef(to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'))) is distinct from 'a58bb4af1512b1cb967a9bc57a57fc13'
  or md5(pg_get_functiondef(to_regprocedure('venue.create_inventory_hold(uuid, integer, text, text)'))) is distinct from 'f177b73fadaa60234a6d416fed558d11' then
    raise exception 'precondition_failed: 201 self-check — a dependency body moved'; end if;
  if (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'venue') <> current_setting('a201.nfn') then
    raise exception 'precondition_failed: 201 self-check — the venue function count moved'; end if;
end $pc$;

commit;
