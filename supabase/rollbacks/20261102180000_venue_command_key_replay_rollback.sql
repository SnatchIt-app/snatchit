-- ============================================================================
-- venue_command_key_replay_rollback.sql — rollback of registry 204 (DB-6) / pgTAP 273.
-- Restores the applied predecessors of the five bodies 204 replaces (prosrc / pg_get_functiondef md5):
--   catalog.create_event(uuid,text,jsonb,text)            204 d4412bd702a938a18d4de28da68fbb70 -> 078 e48b7093e3a92f3b396450565d9f3261 / 02314a386f05a3dd459482caf07375b8
--   catalog.create_event_session(uuid,jsonb,text)         204 8ce6b96c396f577adbf6be707b1433b3 -> e76 ee243b12a8b51c7692a8f6ed22506a34 / 560bd7d37e9f6de01e1d8db2c60b1fcf
--   catalog.publish_event(uuid,text,text)                 204 3243d8a053e81181d6c54fe1f05d5288 -> 202 0f7d65e79fc24cc5feed1048575d3e27 / f30eaca23ae71a33243e39a6c8c5a8fd
--   venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)
--                                                         204 a9e9d11d0619b03d22bb1f920901d2a8 -> 162 9fd9b5f50b0c66afe7a0842e1e8104b9 / dc5cf9c96e8cfb97074f6b5e8e502ea9
--   venue.allocate_comp(uuid,uuid,integer,text,text)      204 fd475aaf290c34405b0037f35547d358 -> 187 269206489452fd2e8ea62afd4d1913f9 / 73ad103d04ce30dbf7d7238ade284a26
-- publish_event goes back to 202's body (fee-read alignment), never e76's. Roll this file back BEFORE 202's, 187's,
-- e76's or 162's rollback (each asserts its own body).
-- INVERSE MD5 GUARD: per function, a 204 body is restored, a predecessor body is left alone (rollback re-run = no-op),
-- anything else refuses naming the function and both md5s seen, with nothing changed. CREATE OR REPLACE only: no drop,
-- no CASCADE, no grant re-stated; the post-check proves the predecessor md5s and every captured attribute (ACL,
-- SECURITY DEFINER, search_path, owner, volatility, COMMENT) unchanged. No row is touched: receipt digests already in
-- the append-only kernel.admin_audit stay and are inert (the predecessor bodies never read them).
-- The bodies below are the predecessors' pg_get_functiondef text byte for byte (dumped from a clone of origin/main
-- c093bada's chain + 202).
-- ============================================================================
begin;
set local lock_timeout = '3s';

do $pf$
declare
  r      record;
  v_src  text;
  v_def  text;
  v_st   text;
  v_n    integer;
  v_cap  jsonb := '[]'::jsonb;
begin
  for r in
    select * from (values
      ('catalog.create_event(uuid,text,jsonb,text)', 'catalog', 'create_event',
       'e48b7093e3a92f3b396450565d9f3261', '02314a386f05a3dd459482caf07375b8', 'd0cc74b90d40fa57f092ef59a8791d49', 'd4412bd702a938a18d4de28da68fbb70'),
      ('catalog.create_event_session(uuid,jsonb,text)', 'catalog', 'create_event_session',
       'ee243b12a8b51c7692a8f6ed22506a34', '560bd7d37e9f6de01e1d8db2c60b1fcf', '33b0d32e2a3b4269ad2fc9ae173066e1', '8ce6b96c396f577adbf6be707b1433b3'),
      ('catalog.publish_event(uuid,text,text)', 'catalog', 'publish_event',
       '0f7d65e79fc24cc5feed1048575d3e27', 'f30eaca23ae71a33243e39a6c8c5a8fd', 'fe9bc5f0f91611a064b1cdef5143efec', '3243d8a053e81181d6c54fe1f05d5288'),
      ('venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)', 'venue', 'set_ticket_type_sale_window',
       '9fd9b5f50b0c66afe7a0842e1e8104b9', 'dc5cf9c96e8cfb97074f6b5e8e502ea9', 'a417a4acb7523b8a1d35c8fc3a025432', 'a9e9d11d0619b03d22bb1f920901d2a8'),
      ('venue.allocate_comp(uuid,uuid,integer,text,text)', 'venue', 'allocate_comp',
       '269206489452fd2e8ea62afd4d1913f9', '73ad103d04ce30dbf7d7238ade284a26', 'd35f9a24869a91b70755dcd75613f410', 'fd475aaf290c34405b0037f35547d358')
    ) as t(sig, nsp, name, pred_src, pred_def, own_src, own_def)
  loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = r.nsp and p.proname = r.name;
    if to_regprocedure(r.sig) is null or v_n <> 1 then
      raise exception 'ROLLBACK_204_REFUSED: % — expected exactly one %.% overload with this signature (overloads %); nothing changed',
        r.sig, r.nsp, r.name, v_n;
    end if;
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_src, v_def
      from pg_proc p where p.oid = to_regprocedure(r.sig);
    v_st := case when v_src = r.own_src and v_def = r.own_def then 'own'
                 when v_src = r.pred_src and v_def = r.pred_def then 'pred' end;
    if v_st is null then
      raise exception 'ROLLBACK_204_REFUSED: % has prosrc % / functiondef %, neither 204''s body (% / %) nor the predecessor (% / %); nothing changed',
        r.sig, v_src, v_def, r.own_src, r.own_def, r.pred_src, r.pred_def;
    end if;
    v_cap := v_cap || jsonb_build_array((
      select jsonb_build_object('sig', r.sig, 'state', v_st, 'def', v_def, 'want_src', r.pred_src, 'want_def', r.pred_def,
               'acl', coalesce(p.proacl::text, '<null>'), 'secdef', p.prosecdef,
               'cfg', coalesce(p.proconfig::text, '<null>'), 'owner', p.proowner::regrole::text,
               'vol', p.provolatile::text, 'cmt', coalesce(md5(obj_description(p.oid, 'pg_proc')), '<none>'))
        from pg_proc p where p.oid = to_regprocedure(r.sig)));
  end loop;
  perform set_config('rollback_204.preflight', v_cap::text, true);
  raise notice '204 rollback pre-check: %',
    (select string_agg((e ->> 'sig') || '=' || left(e ->> 'def', 8) || case when e ->> 'state' = 'pred' then ' (already the predecessor)' else ' (204 -> predecessor)' end, ', ')
       from jsonb_array_elements(v_cap) e);
end $pf$;

do $r1$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.create_event(uuid,text,jsonb,text)'))) = 'd4412bd702a938a18d4de28da68fbb70' then
    execute $pred204$CREATE OR REPLACE FUNCTION catalog.create_event(p_venue_id uuid, p_title text, p_first_session jsonb, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid;
  v_org_id   uuid;
  v_approval text;
  v_allowed  boolean := false;
  v_event_id uuid;
  v_session  jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'precondition_failed: title required';
  end if;

  select v.org_id, v.approval_status
    into v_org_id, v_approval
    from catalog.venue v where v.venue_id = p_venue_id;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;
  if v_approval <> 'approved' then
    raise exception 'precondition_failed: venue is not approved';
  end if;

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- org_id is SERVER-DERIVED from catalog.venue.org_id (denormalised for the
  -- authz hot path and kept consistent by THIS function); status := 'draft'.
  insert into catalog.event (venue_id, org_id, title, status)
  values (p_venue_id, v_org_id, trim(p_title), 'draft')
  returning event_id into v_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.create', 'event', v_event_id, 'self_service',
          null, jsonb_build_object('venue_id', p_venue_id, 'status', 'draft'));

  -- A1: an event has >= 1 session, enforced by the create flow rather than by a
  -- table constraint.
  v_session := coalesce(p_first_session, '{}'::jsonb);
  return jsonb_build_object(
    'status','ok',
    'event_id', v_event_id,
    'session_id',
    (catalog.create_event_session(v_event_id, v_session,
                                  p_command_key || ':implicit-session') ->> 'session_id')::uuid);
end;
$function$
$pred204$;
    raise notice '204 rollback: catalog.create_event(uuid,text,jsonb,text) restored to 078';
  else
    raise notice '204 rollback: catalog.create_event(uuid,text,jsonb,text) already carries its predecessor (no-op)';
  end if;
end $r1$;

do $r2$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.create_event_session(uuid,jsonb,text)'))) = '8ce6b96c396f577adbf6be707b1433b3' then
    execute $pred204$CREATE OR REPLACE FUNCTION catalog.create_event_session(p_event_id uuid, p_session jsonb, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_status     text;
  v_allowed    boolean := false;
  v_session_id uuid;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_label      text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_session is null or jsonb_typeof(p_session) <> 'object' then
    raise exception 'invalid_input: session must be a json object';
  end if;

  select e.org_id, e.venue_id, e.status
    into v_org_id, v_venue_id, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(v_venue_id, array['venue_manager'])
      -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
      -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
      and exists (select 1 from catalog.venue v
                   where v.venue_id = v_venue_id and v.org_id = v_org_id);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_label  :=  p_session ->> 'session_label';
  v_starts := (p_session ->> 'starts_at')::timestamptz;
  v_ends   := (p_session ->> 'ends_at')::timestamptz;
  v_doors  := (p_session ->> 'doors_at')::timestamptz;
  if v_starts is null then
    raise exception 'invalid_input: starts_at required';
  end if;
  if v_ends is not null and v_ends <= v_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;

  -- home_region and status are SERVER-DERIVED; session_version defaults to 1 and
  -- is never a parameter (its sole writer is catalog.update_event_session, 079).
  insert into catalog.event_session
         (event_id, session_label, starts_at, ends_at, doors_at, status, home_region)
  values (p_event_id, v_label, v_starts, v_ends, v_doors, 'scheduled', 'us-east')
  returning session_id into v_session_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.create', 'event_session', v_session_id, 'self_service',
          null, jsonb_build_object('event_id', p_event_id, 'starts_at', v_starts));

  return jsonb_build_object('status','ok','session_id',v_session_id);
end;
$function$
$pred204$;
    raise notice '204 rollback: catalog.create_event_session(uuid,jsonb,text) restored to e76 (165)';
  else
    raise notice '204 rollback: catalog.create_event_session(uuid,jsonb,text) already carries its predecessor (no-op)';
  end if;
end $r2$;

do $r3$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.publish_event(uuid,text,text)'))) = '3243d8a053e81181d6c54fe1f05d5288' then
    execute $pred204$CREATE OR REPLACE FUNCTION catalog.publish_event(p_event_id uuid, p_target_status text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid          uuid;
  v_org_id       uuid;
  v_venue        uuid;
  v_status       text;
  v_ok           boolean;
  -- 102 / A8a' SALEABLE gate scratch — declared here, used only inside the
  -- on_sale branch below.
  v_org_status   text;
  v_org_ref      text;
  v_org_ready    boolean;
  v_signing_key  uuid;
  v_fee_bps      numeric;
  v_fee_raw      jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_target_status not in ('announced','on_sale','live','completed') then
    raise exception 'invalid_input: bad target_status % (cancellation is catalog.cancel_event)', p_target_status;
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
              -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
              and exists (select 1 from catalog.venue v
                           where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- legal FORWARD transition only (draft→announced→on_sale→live→completed).
  v_ok := (v_status = 'draft'     and p_target_status = 'announced')
       or (v_status = 'announced' and p_target_status = 'on_sale')
       or (v_status = 'on_sale'   and p_target_status = 'live')
       or (v_status = 'live'      and p_target_status = 'completed');
  if not v_ok then
    raise exception 'precondition_failed: illegal_transition (% -> %)', v_status, p_target_status;
  end if;

  -- on_sale requires >=1 ticket_type WITH a batch — no empty on-sale.
  if p_target_status = 'on_sale' then
    if not exists (
      select 1 from venue.ticket_type tt
       join venue.inventory_batch b on b.ticket_type_id = tt.ticket_type_id
      where tt.event_id = p_event_id) then
      raise exception 'precondition_failed: empty_inventory';
    end if;

    -- ---- 102 / A8a' — SALEABLE STATIC GATE LADDER, IN ORDER ---------------

    -- 1. ORG NOT SUSPENDED/UNAPPROVED. Mirrors create_primary_checkout's G2a
    -- (093:3982-4021) character-for-character: a suspended or not-yet-
    -- approved org must not be able to open sales, for the identical reason
    -- checkout refuses it at quote time. X-12 restrictive: unknown authorizes
    -- NOTHING (null status, from a vanished org row, refuses too).
    select o.status, o.stripe_connect_account_ref, o.connect_transfers_active
      into v_org_status, v_org_ref, v_org_ready
      from kernel.organization o
     where o.org_id = v_org_id;
    if v_org_status is null or v_org_status not in ('approved','active') then
      raise exception 'precondition_failed: org_not_saleable — a % organization may not go on sale', coalesce(v_org_status,'missing');
    end if;

    -- 2. CONNECT NOT READY. Mirrors G2 (093:4023-4026): a bound ref with dead
    -- transfer capability is not ready, and a live-looking flag with no ref
    -- has nowhere to send money. Both operands required.
    if v_org_ref is null or coalesce(v_org_ready, false) is not true then
      raise exception 'precondition_failed: connect_not_ready';
    end if;

    -- 3. SIGNING NOT READY. The same resolver query shape as
    -- kernel.issue_ticket_atoms (093:4952-4966) and create_primary_checkout's
    -- G2b (093:4066-4074): most-specific-first, per_event -> per_venue ->
    -- global, active and in-window. A signer trust root must exist for this
    -- event BEFORE sales open — this does not provision one (the KMS
    -- ceremony is a separate, un-parked act this migration does not touch).
    select k.key_id into v_signing_key
      from kernel.signing_key k
     where k.status = 'active'
       and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
       and (   (k.scope = 'per_event' and k.event_id = p_event_id)
            or (k.scope = 'per_venue' and k.venue_id = v_venue)
            or (k.scope = 'global'))
     order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
     limit 1;
    if v_signing_key is null then
      raise exception 'precondition_failed: signing_not_ready — an active signing key must resolve for the event scope before it can go on sale';
    end if;

    -- 4. FEE POLICY UNSET. Mirrors A5 (093:4093-4105): fee.buyer_service_bps
    -- must never fall back to zero — a missing key reads the same as a null
    -- value and both refuse.
    -- Registry 202: read and gated exactly as venue.create_primary_checkout
    -- reads and gates the rate since 188 (20261027031000:362-371 and :391-399),
    -- so an event goes on sale only with a rate checkout would quote on. The
    -- NEWEST version is picked first (a LIMIT subquery) and only that value is
    -- cast, so no older version can raise under any plan. A newest value that
    -- is not a JSON number refuses, and so does one outside the integer range
    -- 0..10000 (0 is accepted, as checkout accepts it). Every refusal keeps the
    -- fee_policy_unset token, which the venue dashboard maps.
    select l.value into v_fee_raw
      from (select c.value
              from catalog.platform_config c
             where c.key = 'fee.buyer_service_bps'
             order by c.version desc
             limit 1) l;
    if jsonb_typeof(v_fee_raw) not in ('number', 'null') then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON %, not a number; this event cannot go on sale until the owner sets an integer', jsonb_typeof(v_fee_raw);
    end if;
    v_fee_bps := case when jsonb_typeof(v_fee_raw) = 'number' then (v_fee_raw #>> '{}')::numeric end;
    if v_fee_bps is null then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it';
    end if;
    if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got %; this event cannot go on sale until the owner corrects it', v_fee_bps;
    end if;

    -- ---- end 102 / A8a' SALEABLE gate ladder ------------------------------
  end if;

  update catalog.event set status = p_target_status, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.status', 'event', p_event_id, 'publish',
          jsonb_build_object('status', v_status), jsonb_build_object('status', p_target_status));

  return jsonb_build_object('status','ok','event_status',p_target_status);
end;
$function$
$pred204$;
    raise notice '204 rollback: catalog.publish_event(uuid,text,text) restored to 202';
  else
    raise notice '204 rollback: catalog.publish_event(uuid,text,text) already carries its predecessor (no-op)';
  end if;
end $r3$;

do $r4$
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)'))) = 'a9e9d11d0619b03d22bb1f920901d2a8' then
    execute $pred204$CREATE OR REPLACE FUNCTION venue.set_ticket_type_sale_window(p_ticket_type_id uuid, p_sale_starts_at timestamp with time zone, p_sale_ends_at timestamp with time zone, p_reason_code text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_status    text;
  v_old_start timestamptz;
  v_old_end   timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_sale_starts_at is not null and p_sale_ends_at is not null and p_sale_ends_at <= p_sale_starts_at then
    raise exception 'invalid_input: sale_ends_at must be after sale_starts_at';
  end if;

  select tt.sale_starts_at, tt.sale_ends_at, e.org_id, e.venue_id, e.status
    into v_old_start, v_old_end, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class (081:279)
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
  -- event.org_id, the 088:1629 cancel_event helper. The venue arm carries E-76 (160).
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old_start is not distinct from p_sale_starts_at and v_old_end is not distinct from p_sale_ends_at then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,
                              'sale_starts_at',v_old_start,'sale_ends_at',v_old_end);
  end if;

  update venue.ticket_type
     set sale_starts_at = p_sale_starts_at, sale_ends_at = p_sale_ends_at, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.sale_window_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('sale_starts_at', v_old_start, 'sale_ends_at', v_old_end),
          jsonb_build_object('sale_starts_at', p_sale_starts_at, 'sale_ends_at', p_sale_ends_at));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,
                            'sale_starts_at',p_sale_starts_at,'sale_ends_at',p_sale_ends_at);
end;
$function$
$pred204$;
    raise notice '204 rollback: venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text) restored to 162';
  else
    raise notice '204 rollback: venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text) already carries its predecessor (no-op)';
  end if;
end $r4$;

do $r5$
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.allocate_comp(uuid,uuid,integer,text,text)'))) = 'fd475aaf290c34405b0037f35547d358' then
    execute $pred204$CREATE OR REPLACE FUNCTION venue.allocate_comp(p_session_id uuid, p_batch_id uuid, p_quantity integer, p_reason_code text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_venue uuid; v_id uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  if p_quantity is null or p_quantity <= 0 then raise exception 'precondition_failed: bad_quantity'; end if;
  insert into venue.comp_allocation (event_session_id, batch_id, quantity, granted_by)
  values (p_session_id, p_batch_id, p_quantity, auth.uid()) returning id into v_id;
  return jsonb_build_object('status','ok','comp_allocation_id', v_id);
end;
$function$
$pred204$;
    raise notice '204 rollback: venue.allocate_comp(uuid,uuid,integer,text,text) restored to 187';
  else
    raise notice '204 rollback: venue.allocate_comp(uuid,uuid,integer,text,text) already carries its predecessor (no-op)';
  end if;
end $r5$;

do $pc$
declare
  v_cap jsonb := nullif(current_setting('rollback_204.preflight', true), '')::jsonb;
  e     jsonb;
  q     record;
begin
  if v_cap is null or jsonb_array_length(v_cap) <> 5 then
    raise exception 'ROLLBACK_204_POSTCHECK_FAILED: the pre-check capture is missing — run this file as one transaction';
  end if;
  for e in select * from jsonb_array_elements(v_cap) loop
    select md5(p.prosrc) as src, md5(pg_get_functiondef(p.oid)) as def, coalesce(p.proacl::text, '<null>') as acl,
           p.prosecdef, coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner,
           p.provolatile::text as vol, coalesce(md5(obj_description(p.oid, 'pg_proc')), '<none>') as cmt,
           (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n
      into q from pg_proc p where p.oid = to_regprocedure(e ->> 'sig');
    if q.src is distinct from e ->> 'want_src' or q.def is distinct from e ->> 'want_def' then
      raise exception 'ROLLBACK_204_POSTCHECK_FAILED: % md5 % / % is not the predecessor % / %',
        e ->> 'sig', coalesce(q.src, '<absent>'), coalesce(q.def, '<absent>'), e ->> 'want_src', e ->> 'want_def';
    end if;
    if (q.acl, q.prosecdef, q.cfg, q.owner, q.vol, q.cmt) is distinct from
       (e ->> 'acl', (e ->> 'secdef')::boolean, e ->> 'cfg', e ->> 'owner', e ->> 'vol', e ->> 'cmt') or q.n <> 1 then
      raise exception 'ROLLBACK_204_POSTCHECK_FAILED: % posture changed (acl % -> %, secdef % -> %, cfg % -> %, owner % -> %, vol % -> %, comment % -> %, overloads %)',
        e ->> 'sig', e ->> 'acl', q.acl, e ->> 'secdef', q.prosecdef, e ->> 'cfg', q.cfg, e ->> 'owner', q.owner,
        e ->> 'vol', q.vol, e ->> 'cmt', q.cmt, q.n;
    end if;
  end loop;
  raise notice '204 rollback post-check: % ok',
    (select string_agg((x ->> 'sig') || '=' || left(x ->> 'want_def', 8), ' ') from jsonb_array_elements(v_cap) x);
end $pc$;

commit;
