-- ============================================================================
-- 20261030090000_venue_hold_release_and_staff_grant_gate_first.sql — registry 193 / pgTAP 262.
-- Pre-Stage-8 hardening (D writes; A allocated 2026-10-30; E reviews). DRAFT: applied nowhere.
--
-- WHAT THIS MIGRATION IS. Body-only `create or replace` of TWO existing functions. Same
-- signatures, same SECURITY DEFINER / search_path = '' shape, same ACL (owner + authenticated;
-- create or replace keeps it, and the post-flight asserts it). No new object, no grant, census
-- unchanged (+0 everywhere), Gate-2 counters unchanged. Applied migrations 080/081 are not edited.
--
-- WHY (D/G4-EXPOSURE-CENSUS-20261030.md §G4-1-split; E's condition on #2). Exposing `venue` to
-- PostgREST (Stage 3) makes both definer bodies directly callable by `authenticated`. Each decided
-- something about the target BEFORE deciding who the caller is:
--   1. venue.release_inventory_hold (081 PART 12) read the hold, returned
--      {status: noop_replay, hold_status} for any non-active hold, and only then checked holder /
--      staff — any authenticated caller holding a hold id learned its private status (holds are
--      owner/staff-only under RLS). Its gate was also skipped for ANY NULL-uid session.
--   2. venue.grant_staff_role (080 PART 3) answered self_grant, not_found venue, venue_archived,
--      not_found identity and identity_erased before the role gate — any authenticated caller could
--      test whether a user uuid is registered and whether its account was erased.
--
-- THE CHANGE (each in a marked "193" block; everything else is the predecessor text):
--   1. release_inventory_hold: the GATE runs first, before the hold's existence, status or lock.
--      * a NULL uid passes only for a service_role JWT (public.request_is_service_role()) or a
--        session carrying NO JWT at all — request.jwt.claims NULL or '' (the convention the
--        migrations and 000_helpers' tap.logout use for the trusted service path): the pg_cron
--        tick that runs venue.sweep_expired_inventory_holds (081 PART 13). PostgREST always sets
--        the claims from the verified JWT, so through the API a NULL uid passes only as
--        service_role; an `authenticated` JWT without `sub` now refuses 42501. (The helper alone
--        reads '' as "some JWT" and would refuse the '' persona — 145 E2's sweep runs there.)
--      * a uid caller must be the holder or venue staff (venue_manager / venue_scanner, unchanged).
--        An unknown hold, someone else's active hold and someone else's released/expired hold all
--        answer the SAME refusal: 42501 'insufficient_privilege: not the holder or venue staff'.
--      * after the gate the 081 text is unchanged: batch lock (rank 2), hold re-read under lock,
--        terminal-state noop_replay, sweep: -> expired, counters, movement, unique_violation
--        noop. `not_found: hold` is now reachable only on the service/sweep path.
--      public.release_primary_hold (167) keeps its own owner pre-check and its own P0002 answer for
--      a foreign/unknown id (it never reaches the engine for those), so 234 is unaffected.
--   2. grant_staff_role: the GATE (unchanged logic, incl. the AUTHZ-M7 tier guard) runs right after
--      argument validation (command key, label), before any read of the venue row or the target.
--      An unknown venue refuses like an unauthorized one. Then, for authorized callers only:
--      self_grant, not_found venue, venue_archived, and ONE identity refusal —
--      'not_found: identity <id>' (P0002) — for BOTH a missing auth.users row and an ERASED
--      tombstone (E's condition: the answer never reveals a deletion). The FOR SHARE read of
--      kernel.identity_ext is kept (080's F-11 / E-26 race construction), so a grant still cannot
--      resurrect authority for a tombstone.
--
-- Behaviour for every authorized caller is unchanged (results, rows, audit, idempotency); only
-- the order of refusals and the two collapsed messages differ. pgTAP 144 (grant) and 234 (167's
-- wrapper) pass unchanged; 262 pins the new behaviour with negative controls.
--
-- Discipline (as 183/187/190/192): md5 PRE-FLIGHT accepting the applied predecessor or 193's own
-- body; POST-APPLY self-check of body md5 + posture; rollback restores the 080/081 bodies verbatim
-- under the inverse guard. Predecessor md5s were read from a production-equal clone (fingerprint ==
-- production post-Stage 1, D/STAGE1-POSTAPPLY-VERDICT-20261030.md) and equal CI's replay.
-- OUT OF SCOPE: K-1 (registry 194) and the G4-1 gate-first sweep of the other 30 functions.
-- ============================================================================
begin;

-- ── PRE-FLIGHT (stacking guard, the 183/187/190 pattern): each body must be its applied
-- predecessor (081 PART 12 / 080 PART 3: first apply) or 193's own body (idempotent re-apply).
do $pf$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.release_inventory_hold(uuid,text)',      '56f5f27a875f47039244879b6973b94a', '32d667a5453460b116a646049d1ce066'),
    ('venue.grant_staff_role(uuid,uuid,text,text)',   'c6b6b7c1c4cf43dd81e406afa609f4fb', '3923ba5f9aba4512872693a0588bf353')
  ) as t(fn, md5_pred, md5_own) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 not in (r.md5_pred, r.md5_own) then
      raise exception 'MIGRATION_193_REFUSED: unexpected % body (md5 %) — a later change landed first; re-examine the order', r.fn, v_md5;
    end if;
  end loop;
end $pf$;

create or replace function venue.release_inventory_hold(
  p_hold_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_batch   uuid;
  v_qty     integer;
  v_status  text;
  v_holder  uuid;
  v_venue   uuid;
  v_new     text := 'released';
  v_rem     integer;
begin
  v_uid := auth.uid();
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- ── 193 GATE — authority before the hold's existence, status or lock is consulted.
  -- A NULL uid passes only for a service_role JWT or a session with no JWT at all
  -- (NULL or '' claims: the scheduler's sweep). A caller with a uid must be the holder
  -- or venue staff; an unknown hold refuses exactly like a foreign one.
  if v_uid is null then
    if not (public.request_is_service_role()
            or (nullif(current_setting('request.jwt.claims', true), '') is null
                and nullif(current_setting('request.jwt.claim.role', true), '') is null)) then
      raise exception 'insufficient_privilege: not the holder or venue staff'
        using errcode = '42501';
    end if;
  else
    select h.identity_id, e.venue_id
      into v_holder, v_venue
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
      join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
      join catalog.event e on e.event_id = tt.event_id
     where h.hold_id = p_hold_id;
    if v_holder is distinct from v_uid
       and not kernel.has_venue_role(v_venue, array['venue_manager','venue_scanner']) then
      raise exception 'insufficient_privilege: not the holder or venue staff'
        using errcode = '42501';
    end if;
  end if;
  -- ── 193 GATE END

  -- 081 lock order: resolve the batch, lock it (rank 2), then lock and re-read the hold.
  select h.batch_id into v_batch from venue.inventory_hold h where h.hold_id = p_hold_id;
  if v_batch is null then
    raise exception 'not_found: hold %', p_hold_id using errcode = 'P0002';
  end if;
  perform 1 from venue.inventory_batch b where b.batch_id = v_batch for update;  -- rank 2
  select h.quantity, h.status
    into v_qty, v_status
    from venue.inventory_hold h where h.hold_id = p_hold_id
    for update;                                          -- authoritative under lock

  -- terminal-state idempotency: a double-release is a no-op.
  if v_status <> 'active' then
    return jsonb_build_object('status','noop_replay','hold_status',v_status);
  end if;

  -- the sweep passes 'sweep:'||hold_id and drives the 'expired' transition.
  if p_command_key like 'sweep:%' then v_new := 'expired'; end if;

  update venue.inventory_hold set status = v_new, updated_at = now()
   where hold_id = p_hold_id;
  update venue.inventory_batch set held = held - v_qty, updated_at = now()
   where batch_id = v_batch
  returning (capacity - held - sold) into v_rem;

  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (v_batch, 'release', -v_qty, 0, 'admin_action', p_hold_id, v_uid);

  return jsonb_build_object('status','ok','remaining',v_rem);
exception when unique_violation then
  -- the movement idempotency key already exists: this hold was released by a
  -- concurrent path. Report the no-op, do not surface a raw 23505.
  return jsonb_build_object('status','noop_replay','hold_status','released');
end;
$$;

create or replace function venue.grant_staff_role(
  p_venue_id uuid, p_identity_id uuid, p_role text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_status   text;
  v_allowed  boolean := false;
  v_inserted integer := 0;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- p_role re-validated in-body against the 080 CHECK set (C36).
  if p_role not in ('venue_manager','venue_finance','venue_box_office',
                    'venue_marketing','venue_promoter_manager','venue_scanner') then
    raise exception 'precondition_failed: bad_role %', p_role;
  end if;

  -- ── 193 GATE — authority from the venue id and the caller alone, before any read of
  -- the venue row or the target identity. An unknown venue refuses like an unauthorized one.
  -- AUTHZ-M7 tier guard unchanged: venue_manager is granted from the org plane.
  if p_role = 'venue_manager' then
    v_allowed := kernel.has_org_role_over_venue(p_venue_id, array['org_owner','org_admin'])
              or kernel.is_platform(array['platform_admin']);
    if not v_allowed
       and kernel.has_venue_role(p_venue_id, array['venue_manager']) then
      raise exception 'precondition_failed: tier_guard — venue_manager is granted from the org plane';
    end if;
  else
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager'])
              or kernel.has_org_role_over_venue(p_venue_id, array['org_owner','org_admin'])
              or kernel.is_platform(array['platform_admin']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required'
      using errcode = '42501';
  end if;
  -- ── 193 GATE END

  -- No self-grant (I-11/H-2).
  if p_identity_id = v_uid then
    raise exception 'precondition_failed: self_grant';
  end if;

  select v.approval_status into v_status
    from catalog.venue v where v.venue_id = p_venue_id;
  if v_status is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;
  if v_status = 'archived' then
    raise exception 'precondition_failed: venue_archived';
  end if;

  -- ── 193 — no such identity and an ERASED tombstone give ONE refusal, so the answer never
  -- reveals a deletion. FOR SHARE on identity_ext is the 080 F-11 construction (E-26).
  declare
    v_del text;
  begin
    select e.deletion_state into v_del
      from kernel.identity_ext e
     where e.identity_id = p_identity_id
     for share;
    if v_del = 'ERASED'
       or not exists (select 1 from auth.users u where u.id = p_identity_id) then
      raise exception 'not_found: identity %', p_identity_id using errcode = 'P0002';
    end if;
  end;
  -- ── 193 END

  -- Admin-plane lock, outside the six ranks; PK makes a re-grant noop_replay.
  perform 1 from venue.staff_role s
    where s.venue_id = p_venue_id and s.identity_id = p_identity_id
    for update;
  insert into venue.staff_role (venue_id, identity_id, role, granted_by)
  values (p_venue_id, p_identity_id, p_role, v_uid)
  on conflict on constraint staff_role_pk do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return jsonb_build_object('status','noop_replay','venue_id',p_venue_id,
                              'identity_id',p_identity_id,'role',p_role);
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.staff_role.grant', 'identity', p_identity_id, 'staff_grant',
          (select coalesce(jsonb_agg(s.role order by s.role), '[]'::jsonb)
             from venue.staff_role s
            where s.venue_id = p_venue_id and s.identity_id = p_identity_id
              and s.role <> p_role),
          (select jsonb_agg(s.role order by s.role)
             from venue.staff_role s
            where s.venue_id = p_venue_id and s.identity_id = p_identity_id));

  return jsonb_build_object('status','ok','venue_id',p_venue_id,
                            'identity_id',p_identity_id,'role',p_role);
end;
$$;

-- ── POST-APPLY SELF-CHECK: exactly 193's bodies; signature, SECURITY DEFINER, search_path and
-- the ACL (owner + authenticated) unchanged — create or replace adds no object and no grant.
do $pc$
declare r record; v_md5 text; v_acl text; v_ok boolean;
begin
  for r in select * from (values
    ('venue.release_inventory_hold(uuid,text)',    '32d667a5453460b116a646049d1ce066'),
    ('venue.grant_staff_role(uuid,uuid,text,text)', '3923ba5f9aba4512872693a0588bf353')
  ) as t(fn, md5_own) loop
    select md5(pg_get_functiondef(p.oid)),
           (select string_agg(e.entry, ',' order by e.entry)
              from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                           || ':' || a.privilege_type as entry
                      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) e),
           p.prosecdef and p.proconfig = array['search_path=""']
      into v_md5, v_acl, v_ok
      from pg_proc p where p.oid = r.fn::regprocedure;
    if v_md5 <> r.md5_own then
      raise exception 'POSTFLIGHT_193_FAILED: % body md5 % is not 193''s — this file was modified', r.fn, v_md5;
    end if;
    if v_acl <> 'authenticated:EXECUTE,postgres:EXECUTE' or not v_ok then
      raise exception 'POSTFLIGHT_193_FAILED: % posture changed (acl %, definer+search_path %)', r.fn, v_acl, v_ok;
    end if;
  end loop;
end $pc$;

commit;
