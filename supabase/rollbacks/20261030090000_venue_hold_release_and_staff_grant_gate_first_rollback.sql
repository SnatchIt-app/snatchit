-- ============================================================================
-- supabase/rollbacks/20261030090000_venue_hold_release_and_staff_grant_gate_first_rollback.sql
-- Rollback for registry 193: restores the 081 PART 12 body of venue.release_inventory_hold and the
-- 080 PART 3 body of venue.grant_staff_role VERBATIM. Guarded like the migration: the pre-flight
-- accepts 193's body or the predecessor; the post-restore asserts the predecessor md5s and the
-- unchanged ACL. 193 adds no object, so there is nothing to drop.
-- WARNING, stated plainly: rolling back re-opens both disclosures — any authenticated caller learns
-- a foreign hold's status by id (and any NULL-uid session passes the hold gate), and grant_staff_role
-- again reveals whether a user uuid exists or was erased, to callers with no authority. Prefer a
-- forward fix.
-- ============================================================================
begin;

do $pf$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.release_inventory_hold(uuid,text)',      'b981bef80b10455a0c45a6e908c91aec', '56f5f27a875f47039244879b6973b94a'),
    ('venue.grant_staff_role(uuid,uuid,text,text)',   '3923ba5f9aba4512872693a0588bf353', 'c6b6b7c1c4cf43dd81e406afa609f4fb')
  ) as t(fn, md5_193, md5_pred) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 not in (r.md5_193, r.md5_pred) then
      raise exception 'ROLLBACK_193_REFUSED: unexpected % body (md5 %) — not 193''s and not the predecessor', r.fn, v_md5;
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

  -- Resolve the batch id (holds never move batches, so an unlocked read is
  -- safe), then lock the BATCH first (rank 2, the frozen §5.5 order), THEN
  -- lock and RE-READ the hold row. The prior form read status on an unlocked
  -- SELECT and checked the STALE snapshot — two concurrent releases both saw
  -- 'active' and both decremented held; benign in 081 (the movement UNIQUE
  -- aborts the second) but a latent oversell once a converter lands (082/083).
  select h.batch_id into v_batch from venue.inventory_hold h where h.hold_id = p_hold_id;
  if v_batch is null then
    raise exception 'not_found: hold %', p_hold_id using errcode = 'P0002';
  end if;
  perform 1 from venue.inventory_batch b where b.batch_id = v_batch for update;  -- rank 2
  select h.quantity, h.status, h.identity_id
    into v_qty, v_status, v_holder
    from venue.inventory_hold h where h.hold_id = p_hold_id
    for update;                                          -- authoritative under lock

  -- terminal-state idempotency: a double-release is a no-op.
  if v_status <> 'active' then
    return jsonb_build_object('status','noop_replay','hold_status',v_status);
  end if;

  -- Authority: the holder, OR venue staff, OR the definer sweep (auth.uid() NULL
  -- inside the scheduler-invoked sweep — the sweep is service_role/DEF, so it
  -- passes the NULL-uid branch below).
  select e.venue_id into v_venue
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = v_batch;
  if v_uid is not null
     and v_uid <> v_holder
     and not kernel.has_venue_role(v_venue, array['venue_manager','venue_scanner']) then
    raise exception 'insufficient_privilege: not the holder or venue staff'
      using errcode = '42501';
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

  -- p_role re-validated in-body against the 080 CHECK set: venue_door and
  -- venue_promoter are the superseded labels and raise; the label sets are
  -- disjoint by scope, so an org_* or platform_* label raises too (C36).
  if p_role not in ('venue_manager','venue_finance','venue_box_office',
                    'venue_marketing','venue_promoter_manager','venue_scanner') then
    raise exception 'precondition_failed: bad_role %', p_role;
  end if;

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
  if not exists (select 1 from auth.users u where u.id = p_identity_id) then
    raise exception 'not_found: identity %', p_identity_id using errcode = 'P0002';
  end if;
  -- dsm §1.3: ERASED is terminal, and INV #23's CLEANED disposition ("a
  -- tombstone holds no authority") is stable only if no writer can recreate
  -- the row post-tombstone — without this, any manager resurrects authority
  -- for an erased account the sweep just cleaned (erratum E-26; the E-23
  -- principle applied to the one 080 verb that confers authority on a
  -- counterparty). DELETION_PENDING is deliberately NOT refused: roles are not
  -- blockers, and the freeze surface (dsm §3.2) names no staff-grant refusal.
  -- The check takes FOR SHARE on the target's identity_ext row — the F-11
  -- construction: the deletion sweep's terminal entry holds FOR UPDATE on the
  -- same row across its BP evaluation AND the INV #23 cleanup, so either this
  -- grant commits first (and the tombstone's cleanup removes the fresh row) or
  -- the tombstone commits first (and this check reads ERASED and refuses).
  -- Without the lock, a grant that observed DELETION_PENDING could commit
  -- after the tombstone: ERASED ∧ holds-authority — proven with a real
  -- interleave before this lock was added (erratum E-26).
  -- A target with NO identity_ext row has never requested deletion; there is
  -- nothing to race, and a later request finds the row and cleans it.
  declare
    v_del text;
  begin
    select e.deletion_state into v_del
      from kernel.identity_ext e
     where e.identity_id = p_identity_id
     for share;
    if v_del = 'ERASED' then
      raise exception 'precondition_failed: identity_erased — a tombstone holds no authority';
    end if;
  end;
  -- The target need NOT already be org-affiliated: is_org_affiliate is a
  -- scoping input, never an authorizing one (RM-6).

  -- AUTHZ-M7 — the venue-plane tier guard. venue_manager is one of only three
  -- principals that may open_door_manifest (O-4): a venue_manager minting
  -- another venue_manager is minting a custody-boundary principal. The org
  -- tier above the venue is the correct minter (MD-15), and it already reaches
  -- every venue through the §1.1a helper — never a re-inlined org_id join.
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

do $pc$
declare r record; v_md5 text; v_acl text;
begin
  for r in select * from (values
    ('venue.release_inventory_hold(uuid,text)',    '56f5f27a875f47039244879b6973b94a'),
    ('venue.grant_staff_role(uuid,uuid,text,text)', 'c6b6b7c1c4cf43dd81e406afa609f4fb')
  ) as t(fn, md5_pred) loop
    select md5(pg_get_functiondef(p.oid)),
           (select string_agg(e.entry, ',' order by e.entry)
              from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                           || ':' || a.privilege_type as entry
                      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) e)
      into v_md5, v_acl
      from pg_proc p where p.oid = r.fn::regprocedure;
    if v_md5 <> r.md5_pred then
      raise exception 'ROLLBACK_193_POSTCHECK_FAILED: % restored body md5 % is not the predecessor''s', r.fn, v_md5;
    end if;
    if v_acl <> 'authenticated:EXECUTE,postgres:EXECUTE' then
      raise exception 'ROLLBACK_193_POSTCHECK_FAILED: % ACL changed (%)', r.fn, v_acl;
    end if;
  end loop;
end $pc$;

commit;
