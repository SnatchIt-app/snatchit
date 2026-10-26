-- ============================================================================
-- supabase/rollbacks/20261026230000_venue_hold_sale_window_rollback.sql
-- Rollback for registry 185 (20261026230000). Restores the APPLIED predecessor body of
-- venue.reserve_primary_inventory (081 PART 10, as pg_get_functiondef printed it on the stacked clone)
-- VERBATIM: buyer holds are no longer refused outside a tier's sale window. Nothing else moves — 185
-- never touched venue.create_inventory_hold (f177b73fadaa60234a6d416fed558d11); owner, ACL, SECURITY DEFINER and search_path are
-- kept by CREATE OR REPLACE and asserted by the post-restore self-check; no data is touched.
-- Guard: the pre-flight accepts only 185's body (rollback) or the predecessor (idempotent re-run) and
-- refuses anything else with nothing changed.
--   reserve_primary_inventory  185 d30669daef75abe15725aa0b04a107b0 -> predecessor 3538344c0418c7b322accafdee76f0f6
-- ORDER: a later rollback of 162 must run after 185's rollback (162's drops venue.ticket_type_on_sale,
-- which 185's body calls).
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT (inverse of 185's guard): the body being restored over must be EXACTLY 185's (rollback) or
-- already the predecessor (idempotent re-run); anything else is a later change this rollback must not
-- destroy — refuse; nothing changes. ACL captured for the post-restore self-check.
do $pf$
declare
  v_r text := md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)')));
begin
  if v_r is null or v_r not in ('d30669daef75abe15725aa0b04a107b0',   -- 185 body
                                '3538344c0418c7b322accafdee76f0f6') then -- 081 body (already rolled back)
    raise exception 'precondition_failed: 185 rollback refuses to overwrite an unexpected venue.reserve_primary_inventory body (md5 %); nothing changed', coalesce(v_r, '<missing>');
  end if;
  perform set_config('a185.acl_r', (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure), true);
end $pf$;

-- ── venue.reserve_primary_inventory: the 081 body, verbatim
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

-- ── POST-RESTORE SELF-CHECK: the body is EXACTLY the predecessor; definer, search_path and ACL unchanged.
do $pc$
begin
  if md5(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure)) <> '3538344c0418c7b322accafdee76f0f6' then
    raise exception 'precondition_failed: 185 rollback post-restore self-check — the restored venue.reserve_primary_inventory body is not the predecessor; this file was modified';
  end if;
  if exists (select 1 from pg_proc
              where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure
                and (not prosecdef or proconfig is distinct from array['search_path=""']))
  or (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure) <> current_setting('a185.acl_r') then
    raise exception 'precondition_failed: 185 rollback post-restore self-check — SECURITY DEFINER, search_path or the EXECUTE ACL moved';
  end if;
end $pc$;

commit;
