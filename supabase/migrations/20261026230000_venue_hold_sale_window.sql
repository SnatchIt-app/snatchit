-- ============================================================================
-- 20261026230000_venue_hold_sale_window.sql — registry 185 / pgTAP 255 (A writes; D reviews the 162 interplay).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Body-only CREATE OR REPLACE of
-- venue.reserve_primary_inventory(uuid, integer, text) and venue.create_inventory_hold(uuid, integer,
-- text, text) at their exact signatures. Each new body = its APPLIED predecessor (081 PART 10 / PART 11;
-- no migration on the stacked tree 159 -> 176 -> 160 -> 161 -> 162 replaces either — measured with
-- pg_get_functiondef on a clone) + ONE marked block. No new function, no signature change, no grant
-- change, no table, no public-schema object; Gate-2 census, grant-decision manifest and
-- expected_grants.txt unchanged (+0). Replay-safe: CREATE OR REPLACE behind an md5 pre-flight that
-- accepts only the predecessor or this file's own body. ORDER: after 162 (20261026100000), whose
-- predicate it calls; the pre-flight refuses any other body.
--
-- ── THE RULING (A, 2026-10-26; planning CONTRACTS.md §2 C2 "Sale windows") ───────────────────
-- A tier's sale window (162: venue.ticket_type.sale_starts_at / sale_ends_at, read through
-- venue.ticket_type_on_sale) is enforced when a hold is CREATED; outside it the hold is refused.
-- Checkout (venue.create_primary_checkout) does not re-check — it requires covering holds, and a
-- hold obtained in-window may be paid within its TTL. Comps (allocate_comp / issue_comp, 086) do
-- not call either function and are not changed.
--
-- ── WHAT CHANGES (each spot marked `185 BLOCK W`) ─────────────────────────────────────────────
--   reserve_primary_inventory — after the idempotency replay (a replay of a hold that succeeded
--     in-window still returns idempotency_replay + the original hold_id + expiry after the window
--     closes) and after the dark-flag / event / session gates (feature_disabled, not_on_sale,
--     session_terminal keep answering first); BEFORE the per-user cap lock, the TTL read and every
--     inventory/hold write: NOT venue.ticket_type_on_sale(<the batch's tier>, now()) ->
--     'precondition_failed: tier_not_on_sale' (162 defines no refusal code; this is the new one).
--   create_inventory_hold — after the staff authority check (a non-staff caller is still 42501
--     first), BEFORE the TTL read and every write: the same refusal. 081 gives this function no
--     replay branch — a replay is answered by its unique_violation handler at the INSERT
--     ('precondition_failed: idempotency_replay', no hold_id) — so the block skips the window when
--     the caller already holds a row under p_command_key (inventory_hold_command_uq's own key), and
--     such a replay reaches 081's answer unchanged.
-- Semantics are 162's predicate verbatim: starts inclusive, ends exclusive, NULL = open on that
-- side; a hidden tier is never on sale; the event must be on_sale/live. Consequences, recorded for
-- review and pinned by 255: (1) a buyer can no longer hold a HIDDEN tier's batch (081 allowed it);
-- (2) staff holds (create_inventory_hold, which had no event gate) are refused on hidden tiers and on
-- events that are not on_sale/live. Both follow from calling the predicate the ruling names.
-- The read takes no lock on the tier row (the setter locks it FOR UPDATE): a hold is judged at its
-- own transaction's now(), the instant semantics of every other gate in these bodies.
--
-- ── SOURCES READ, NOT ASSUMED ─────────────────────────────────────────────────────────────────
-- 081:527-664 / 672-757 (the two bodies; this file carries their pg_get_functiondef text from the
-- stacked clone, byte-equal), 081:157 (inventory_hold_command_uq unique (identity_id,
-- command_idempotency_key)), 162 PART 8 (ticket_type_on_sale: STABLE SECURITY DEFINER,
-- search_path=''; EXECUTE authenticated only — these definer bodies call it as the owner, as 162's
-- GRANT DECISIONS anticipate), 086 PART 18 (comps), CONTRACTS.md §2 C2 (gate order, refusal style).
--
-- ── GRANTS / FOUR-FILE RULE ──────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE keeps owner, proacl, prosecdef and proconfig; nothing is restated. The CI grant
-- gates read `public` only: no manifest row, no expected_grants line, Gate-2 census +0 (counted
-- before/after on the stacked clone). The post-apply self-check asserts definer, search_path and the
-- exact ACL captured by the pre-flight.
--
-- ── MD5 — md5(pg_get_functiondef(...)) ──────────────────────────────────────────────────────
--   reserve_primary_inventory  predecessor 3538344c0418c7b322accafdee76f0f6   185 d30669daef75abe15725aa0b04a107b0
--   create_inventory_hold      predecessor f177b73fadaa60234a6d416fed558d11   185 ae2d7634878c368d531b96699ff9db99
-- Strip rule: delete every line from '-- ── 185 BLOCK W …' through '-- ── 185 BLOCK W END' (both
-- markers included) and the predecessor is reproduced byte for byte (255 A12/A13).
--
-- ROLLBACK: supabase/rollbacks/20261026230000_venue_hold_sale_window_rollback.sql restores both
-- predecessor bodies verbatim (inverse guard + post-restore self-check). Roll 185 back BEFORE 162:
-- 162's rollback drops venue.ticket_type_on_sale, which these bodies call, and its G2 guard looks at
-- venue_cmd callers only (plpgsql records no dependency), so it would not refuse.
-- VERIFICATION (after apply):
--   select md5(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure));        -- d30669daef75abe15725aa0b04a107b0
--   select md5(pg_get_functiondef('venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure));       -- ae2d7634878c368d531b96699ff9db99
-- LOCKS / RUNTIME: CREATE OR REPLACE FUNCTION only; no data read or written; lock_timeout 3s.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT (stacking guard): each body being replaced must be EXACTLY its applied predecessor
-- (first apply) or EXACTLY this migration's body (idempotent re-apply). Anything else is a later change
-- (or a hotfix) that CREATE OR REPLACE would silently overwrite — refuse; the single transaction then
-- changes nothing. The ACLs are captured (transaction-local) for the post-apply self-check.
do $pf$
declare
  v_r text := md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)')));
  v_c text := md5(pg_get_functiondef(to_regprocedure('venue.create_inventory_hold(uuid, integer, text, text)')));
begin
  if v_r is null or v_r not in ('3538344c0418c7b322accafdee76f0f6',   -- 081 body (predecessor on the stacked tree)
                                'd30669daef75abe15725aa0b04a107b0') then -- this migration's body (re-apply)
    raise exception 'precondition_failed: 185 refuses to overwrite an unexpected venue.reserve_primary_inventory body (md5 %) — re-examine the migration order; nothing changed', coalesce(v_r, '<missing>');
  end if;
  if v_c is null or v_c not in ('f177b73fadaa60234a6d416fed558d11',   -- 081 body (predecessor on the stacked tree)
                                'ae2d7634878c368d531b96699ff9db99') then -- this migration's body (re-apply)
    raise exception 'precondition_failed: 185 refuses to overwrite an unexpected venue.create_inventory_hold body (md5 %) — re-examine the migration order; nothing changed', coalesce(v_c, '<missing>');
  end if;
  perform set_config('a185.acl_r', (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure), true);
  perform set_config('a185.acl_c', (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure), true);
end $pf$;

-- ── venue.reserve_primary_inventory: the 081 body + 185 BLOCK W
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
$function$;

-- ── venue.create_inventory_hold: the 081 body + 185 BLOCK W
CREATE OR REPLACE FUNCTION venue.create_inventory_hold(p_batch_id uuid, p_quantity integer, p_hold_kind text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid     uuid;
  v_flag    boolean;
  v_org_id  uuid;
  v_venue   uuid;
  v_held    integer;
  v_cap     integer;
  v_sold    integer;
  v_ttl     interval;
  v_hold_id uuid;
  v_expires timestamptz;
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

  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  select e.org_id, e.venue_id, b.held, b.capacity, b.sold
    into v_org_id, v_venue, v_held, v_cap, v_sold
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = p_batch_id
   for update of b;
  if v_org_id is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;

  -- Staff authority (distinct from the buyer hold, never fans).
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;
  -- ── 185 BLOCK W — tier sale window (A's ruling 2026-10-26, CONTRACTS C2): refuse when the batch's
  -- tier is not on sale at now() by D's 162 predicate venue.ticket_type_on_sale; after the staff
  -- authority check, before the TTL and every write below. 081 gives this function no replay branch:
  -- a replay is answered by the unique_violation handler at the INSERT. So a key this caller
  -- already holds (inventory_hold_command_uq) skips the window and reaches that answer unchanged.
  if not exists (select 1 from venue.inventory_hold h
                  where h.identity_id = v_uid and h.command_idempotency_key = p_command_key)
     and not venue.ticket_type_on_sale(
           (select b.ticket_type_id from venue.inventory_batch b where b.batch_id = p_batch_id), now()) then
    raise exception 'precondition_failed: tier_not_on_sale';
  end if;
  -- ── 185 BLOCK W END

  begin
    select (c.value #>> '{}')::interval into v_ttl from catalog.platform_config c
     where c.key = 'inventory.hold_ttl_interval' order by c.version desc limit 1;
  exception when others then v_ttl := null;
  end;
  if v_ttl is null then
    raise exception 'precondition_failed: hold_ttl_unset';
  end if;
  v_expires := now() + v_ttl;

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
  values (p_batch_id, 'hold', p_quantity, 0,
          case p_hold_kind when 'comp' then 'comp' else 'admin_action' end, v_hold_id, v_uid);

  return jsonb_build_object('status','ok','hold_id',v_hold_id);
exception when unique_violation then
  raise exception 'precondition_failed: idempotency_replay';
end;
$function$;

-- ── POST-APPLY SELF-CHECK: the bodies just written must be EXACTLY this migration's (a modified copy
-- of this file would pass the pre-flight as a "re-apply" and overwrite; this makes it fail its own
-- transaction), and owner-visible attributes must be unchanged: SECURITY DEFINER, search_path='',
-- and the EXECUTE ACL captured by the pre-flight. Outside the functions, so their md5 does not move.
do $pc$
begin
  if md5(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure)) <> 'd30669daef75abe15725aa0b04a107b0'
  or md5(pg_get_functiondef('venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure)) <> 'ae2d7634878c368d531b96699ff9db99' then
    raise exception 'precondition_failed: 185 post-apply self-check — a written body is not this migration''s; this file was modified';
  end if;
  if exists (select 1 from pg_proc
              where oid in ('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure, 'venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure)
                and (not prosecdef or proconfig is distinct from array['search_path=""']))
  or (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure) <> current_setting('a185.acl_r')
  or (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure) <> current_setting('a185.acl_c') then
    raise exception 'precondition_failed: 185 post-apply self-check — SECURITY DEFINER, search_path or the EXECUTE ACL moved';
  end if;
end $pc$;

commit;
