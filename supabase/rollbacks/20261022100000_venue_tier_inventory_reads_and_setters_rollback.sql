-- ============================================================================
-- 20261022100000_venue_tier_inventory_reads_and_setters_rollback.sql — reversal
-- of registry 160 (pgTAP 227). Assigned by Claude A 2026-10-22 (registry 573850a4).
--
-- Restores the APPLIED pre-160 state, not an older baseline: the four 081
-- writer bodies return to 081's text BYTE-FOR-BYTE (generated from the 081
-- file; a reformatted body restores the logic but not the text, and the md5
-- read-back below would then be unable to prove the rollback — 127's G-4
-- lesson), the three new functions are dropped, venue_api.ticket_types returns
-- to 159's definition (DROP + CREATE: a view cannot lose a column through
-- CREATE OR REPLACE), and display_rank is dropped ONLY when every value is NULL.
--
-- Guards (each refuses with nothing changed):
--   G1 the live writer bodies must be 160's (md5) — otherwise a later migration
--      replaced them and this file would silently undo it;
--   G2 venue_cmd (161) must not exist — its wrappers call the functions dropped
--      here; roll back 161 first;
--   G3 display_rank must be all NULL — a rank somebody set is data, and data is
--      not dropped by a rollback (take the owner's call and a snapshot first).
-- Verify: the four restored bodies hash to 081's md5 or the file raises.
--
-- What this re-introduces, on the record: the venue arm of the four writers
-- again accepts a venue_manager of a room whose CURRENT operator is not the
-- event's org (the E-76 gap); the dashboard loses the setters and the counters
-- read (PGRST202 / undefined_function until the callers are redeployed to the
-- pre-160 contract). 227 goes RED at A1-A14 and B1-B4; 145 A4 / 180 A5 return
-- to 87; 226 F5/F6 return to 159's projection. The supabase_migrations ledger
-- row is NOT removed here (separate, owner-authorised step).
--
--   160 bodies (md5 prosrc): create_ticket_type bba1f015338953b1b84ab1a8ce6e1ff9
--                            set_ticket_type_price 0b349a564a50fdda0b721d097a3bb9eb
--                            create_inventory_batch abedde3ce19d1a49087ac4a5c6aaacd0
--                            set_batch_capacity 76c69e9d8625b056e67e53c1d4e34fd9
--   081 bodies (md5 prosrc): create_ticket_type fa7e5142616ff9f4cf7fcfcdedbb6a41
--                            set_ticket_type_price a09ecad391c8614dc722db33c99f57d3
--                            create_inventory_batch a623aa97364549a17eabe414da1ca713
--                            set_batch_capacity 325c25eb1dc363e3d12ceefd081e8e4e
-- ============================================================================
BEGIN;

DO $guard$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure)
       IS DISTINCT FROM 'bba1f015338953b1b84ab1a8ce6e1ff9'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_price(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '0b349a564a50fdda0b721d097a3bb9eb'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure)
       IS DISTINCT FROM 'abedde3ce19d1a49087ac4a5c6aaacd0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '76c69e9d8625b056e67e53c1d4e34fd9' THEN
    RAISE EXCEPTION 'ROLLBACK_160_REFUSED (G1): the live writer bodies are not 160''s; nothing changed.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'venue_cmd') THEN
    RAISE EXCEPTION 'ROLLBACK_160_REFUSED (G2): schema venue_cmd (161) exists and its wrappers call the functions dropped here; roll back 161 first. Nothing changed.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'venue.ticket_type'::regclass AND attname = 'display_rank' AND NOT attisdropped)
     AND EXISTS (SELECT 1 FROM venue.ticket_type WHERE display_rank IS NOT NULL) THEN
    RAISE EXCEPTION 'ROLLBACK_160_REFUSED (G3): venue.ticket_type.display_rank carries values; a rollback does not drop data. Nothing changed.';
  END IF;
END $guard$;

-- 1. the three new functions go (their grants and comments go with them)
DROP FUNCTION IF EXISTS venue.set_ticket_type_visibility(uuid, text, text, text);
DROP FUNCTION IF EXISTS venue.set_ticket_type_rank(uuid, smallint, text);
DROP FUNCTION IF EXISTS venue.get_inventory_counters(uuid);

-- 2. the four 081 writer bodies, VERBATIM from 081_venue_inventory.sql (do not tidy)
-- 2.1 081:175
create or replace function venue.create_ticket_type(
  p_event_id uuid, p_kind text, p_name text, p_price_minor integer,
  p_visibility text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_org_id  uuid;
  v_venue   uuid;
  v_status  text;
  v_tt_id   uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_kind not in ('admission','table') then
    raise exception 'invalid_input: bad kind %', p_kind;
  end if;
  if p_visibility not in ('hidden','public','door_only') then
    raise exception 'invalid_input: bad visibility %', p_visibility;
  end if;
  if p_price_minor is null or p_price_minor <= 0 then
    raise exception 'precondition_failed: bad_price';
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- RM-3: org->venue inheritance is expressed ONLY through the sanctioned
  -- helper, never a direct has_org_role on the denormalised event.org_id
  -- (which IS the venue's org). Reconciles §5.1's has_org_role spelling to the
  -- ratified helper-derived discipline; functionally identical (E-31 note).
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  insert into venue.ticket_type (event_id, kind, name, price_minor, visibility)
  values (p_event_id, p_kind, p_name, p_price_minor, coalesce(p_visibility,'hidden'))
  returning ticket_type_id into v_tt_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.create', 'ticket_type', v_tt_id, 'self_service',
          null, jsonb_build_object('event_id', p_event_id, 'kind', p_kind,
                                   'price_minor', p_price_minor, 'visibility', p_visibility));

  return jsonb_build_object('status','ok','ticket_type_id',v_tt_id);
exception when unique_violation then
  raise exception 'precondition_failed: duplicate_name';
end;
$$;

-- 2.2 081:246
create or replace function venue.set_ticket_type_price(
  p_ticket_type_id uuid, p_price_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
  v_status text;
  v_old    integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_price_minor is null or p_price_minor <= 0 then
    raise exception 'precondition_failed: bad_price';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  select tt.price_minor, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- C9 money-consequential live-table recheck (never a JWT claim); RM-3 helper.
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old = p_price_minor then
    return jsonb_build_object('status','noop_replay','ticket_type_id',p_ticket_type_id,
                              'price_minor',v_old);
  end if;

  -- Binds only orders created AFTER it — orders snapshot unit_price_minor at
  -- checkout (§6.1), so this cannot re-price a pending/paid order, a refund or a
  -- settlement line. That property lives in venue.order_item (082), not here.
  update venue.ticket_type set price_minor = p_price_minor, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.price_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('price_minor', v_old),
          jsonb_build_object('price_minor', p_price_minor));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,
                            'price_minor',p_price_minor);
end;
$$;

-- 2.3 081:320
create or replace function venue.create_inventory_batch(
  p_ticket_type_id uuid, p_session_id uuid, p_release_kind text,
  p_capacity integer, p_shard_count integer, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_tt_event  uuid;
  v_s_event   uuid;
  v_batch_id  uuid;
  v_evstatus  text;
  v_sharded   boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_release_kind not in ('public_sale','promoter_hold','comp','door','presale') then
    raise exception 'invalid_input: bad release_kind %', p_release_kind;
  end if;
  if p_capacity is null or p_capacity <= 0 then
    raise exception 'precondition_failed: bad_capacity';
  end if;

  -- Sharding is deferred (E-32): the aggregate counter is oversell-safe and no
  -- contention exists while native issuance is dark. Refuse rather than create
  -- inert shard rows that would break the §3.3 Σshard==batch reconciliation.
  if coalesce(p_shard_count, 0) > 0 then
    raise exception 'precondition_failed: sharding_deferred (MVP ships the unsharded counter; schema §3.3 is MVP-optional)';
  end if;

  select tt.event_id, e.org_id, e.venue_id, e.status into v_tt_event, v_org_id, v_venue, v_evstatus
    from venue.ticket_type tt join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id;
  if v_tt_event is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  -- refuse a batch on a terminal event (symmetry with create_ticket_type; a
  -- batch on a completed/cancelled event can never reach on_sale anyway).
  if v_evstatus in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;
  select s.event_id into v_s_event from catalog.event_session s where s.session_id = p_session_id;
  if v_s_event is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  -- type & session must belong to the SAME event.
  if v_tt_event <> v_s_event then
    raise exception 'precondition_failed: type_session_event_mismatch';
  end if;

  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- sharding deferred: is_sharded is always false, no shard rows (E-32).
  v_sharded := false;
  insert into venue.inventory_batch
         (ticket_type_id, event_session_id, release_kind, capacity, held, sold, is_sharded)
  values (p_ticket_type_id, p_session_id, p_release_kind, p_capacity, 0, 0, v_sharded)
  returning batch_id into v_batch_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'inventory.batch.create', 'inventory_batch', v_batch_id, 'self_service',
          null, jsonb_build_object('ticket_type_id', p_ticket_type_id, 'session_id', p_session_id,
                                   'release_kind', p_release_kind, 'capacity', p_capacity,
                                   'shards', coalesce(p_shard_count,0)));

  return jsonb_build_object('status','ok','batch_id',v_batch_id,
                            'capacity',p_capacity,'is_sharded',v_sharded);
end;
$$;

-- 2.4 081:408
create or replace function venue.set_batch_capacity(
  p_batch_id uuid, p_new_capacity integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_org_id   uuid;
  v_venue    uuid;
  v_cap      integer;
  v_held     integer;
  v_sold     integer;
  v_sharded  boolean;
  v_delta    integer;
  v_room     integer;
  v_take     integer;
  r          record;
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
  if p_new_capacity is null or p_new_capacity <= 0 then
    raise exception 'precondition_failed: bad_capacity';
  end if;

  select b.capacity, b.held, b.sold, b.is_sharded, e.org_id, e.venue_id
    into v_cap, v_held, v_sold, v_sharded, v_org_id, v_venue
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = p_batch_id
   for update of b;                                     -- rank 2
  if v_org_id is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;

  -- Authority: venue_manager OR org_owner/admin. NO platform arm — a platform
  -- capacity edit on a venue's room is not a support action (§20.3.2).
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- THE REFUSAL FLOOR (C27, absolute): capacity may never drop below what is
  -- already committed. No force flag, no override role, no platform bypass.
  if p_new_capacity < v_held + v_sold then
    raise exception 'precondition_failed: below_committed (new=% < held+sold=%)',
      p_new_capacity, v_held + v_sold;
  end if;

  if v_cap = p_new_capacity then
    return jsonb_build_object('status','noop_replay','batch_id',p_batch_id,
                              'capacity',v_cap,'held',v_held,'sold',v_sold,
                              'remaining',v_cap - v_held - v_sold);
  end if;

  v_delta := p_new_capacity - v_cap;
  if v_sharded then
    if v_delta > 0 then
      -- grow: put the whole delta on the lowest shard (Σ shard.capacity stays = batch).
      update venue.inventory_batch_shard
         set capacity = capacity + v_delta, updated_at = now()
       where batch_id = p_batch_id and shard_no = (
         select min(shard_no) from venue.inventory_batch_shard where batch_id = p_batch_id);
    else
      -- shrink: draw down ascending shard_no, only from each shard's own room
      -- (capacity - held - sold); raise if the distribution can't be satisfied.
      v_take := -v_delta;
      for r in select shard_no, capacity, held, sold from venue.inventory_batch_shard
                where batch_id = p_batch_id order by shard_no for update loop
        exit when v_take = 0;
        v_room := r.capacity - r.held - r.sold;
        if v_room > 0 then
          declare v_cut integer := least(v_room, v_take);
          begin
            update venue.inventory_batch_shard set capacity = capacity - v_cut, updated_at = now()
             where batch_id = p_batch_id and shard_no = r.shard_no;
            v_take := v_take - v_cut;
          end;
        end if;
      end loop;
      if v_take > 0 then
        raise exception 'precondition_failed: shard_distribution_unsatisfiable';
      end if;
    end if;
  end if;

  update venue.inventory_batch set capacity = p_new_capacity, updated_at = now()
   where batch_id = p_batch_id;

  -- C27: every capacity delta has a ledger row — an edit IS a delta.
  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'capacity_change', 0, 0, 'admin_action', gen_random_uuid(), v_uid);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'inventory.capacity.change', 'inventory_batch', p_batch_id, p_reason_code,
          jsonb_build_object('capacity', v_cap), jsonb_build_object('capacity', p_new_capacity));

  return jsonb_build_object('status','ok','batch_id',p_batch_id,'capacity',p_new_capacity,
                            'held',v_held,'sold',v_sold,'remaining',p_new_capacity - v_held - v_sold);
end;
$$;

-- 3. venue_api.ticket_types back to 159 (view before column: the view depends on it)
DROP VIEW IF EXISTS venue_api.ticket_types;
ALTER TABLE venue.ticket_type DROP COLUMN IF EXISTS display_rank;
-- 159's text, verbatim (20261021120000_venue_api_read_views.sql):
CREATE OR REPLACE VIEW venue_api.ticket_types
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT t.ticket_type_id, t.event_id, t.kind, t.name, t.price_minor, t.currency, t.visibility,
         t.created_at, t.updated_at
    FROM venue.ticket_type t;
COMMENT ON VIEW venue_api.ticket_types IS 'venue.ticket_type; caller''s RLS applies (hidden types are manager/org-plane only).';
GRANT SELECT ON venue_api.ticket_types TO authenticated;

-- 4. verify: the restored bodies ARE 081's
DO $verify$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure)
       IS DISTINCT FROM 'fa7e5142616ff9f4cf7fcfcdedbb6a41'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_price(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM 'a09ecad391c8614dc722db33c99f57d3'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure)
       IS DISTINCT FROM 'a623aa97364549a17eabe414da1ca713'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '325c25eb1dc363e3d12ceefd081e8e4e' THEN
    RAISE EXCEPTION 'ROLLBACK_160_VERIFY_FAILED: a restored writer body does not hash to 081''s.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'venue.ticket_type'::regclass AND attname = 'display_rank' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'ROLLBACK_160_VERIFY_FAILED: display_rank still exists.';
  END IF;
  IF (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.ticket_types'::regclass AND attnum > 0 AND NOT attisdropped) <> 9 THEN
    RAISE EXCEPTION 'ROLLBACK_160_VERIFY_FAILED: venue_api.ticket_types does not have 159''s nine columns.';
  END IF;
END $verify$;

COMMIT;
