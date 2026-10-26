-- ============================================================================
-- 20261026100000_event_policy_shared_capacity_and_tier_windows_rollback.sql —
-- reversal of registry 162 (pgTAP 229). Assigned by Claude A 2026-10-26
-- (CONTRACTS.md §4).
--
-- Restores the APPLIED pre-162 state (159 + 176 + 160 + 161), not an older
-- baseline: the SIX venue.* bodies return to 160's text BYTE-FOR-BYTE (generated
-- from the 160 file by gen_162.py; a reformatted body restores the logic but not
-- the text, and the md5 read-back below could then not prove the rollback —
-- 127's G-4 lesson), the five venue_cmd wrappers and the five functions are
-- dropped, the three venue_api views return to their 160 (ticket_types) / 159
-- (events, event_sessions) definitions (DROP + CREATE: a view cannot lose a
-- column through CREATE OR REPLACE) with their comments and grants, and the five
-- columns are dropped ONLY when every value is NULL / the default.
--
-- Guards (each refuses with nothing changed; psql -v ON_ERROR_STOP=1 exits 3):
--   G1 the live bodies of the six venue.* functions must be 162's (md5) —
--      otherwise a later migration replaced them and this file would silently
--      undo it;
--   G2 venue_cmd must hold no wrapper OTHER than 161's six and 162's five that
--      names a function dropped here (a 163+ wrapper over set_event_age_policy,
--      say) — roll that package back first;
--   G3 the five columns must carry no data: catalog.venue.timezone all
--      'America/New_York' (the default), catalog.event.age_policy all NULL,
--      catalog.event_session.sales_capacity all NULL, venue.ticket_type.
--      sale_starts_at / sale_ends_at all NULL — a value somebody set is data,
--      and data is not dropped by a rollback (take the owner's call and a
--      snapshot first).
-- Verify: the six restored bodies hash to 160's md5 or the file raises; the
-- columns are gone; the views carry 10 / 8 / 10 columns (events = 159 rev.
-- 2026-10-26: the original seven + description).
--
-- What this re-introduces, on the record: the org arm of the six venue.*
-- writers/setters again resolves the venue's CURRENT operator (081/160 form:
-- B's owner accepted on A's event at a re-operated room, A's own owner refused
-- — 227 B9/B10 return to their pre-162 reading, so 227 as committed in this
-- package goes RED there); the per-session sales pool and the tier sale windows
-- disappear (the dashboard loses the setters: PGRST202 / undefined_function
-- until the callers are redeployed to the pre-162 contract); venue_api loses
-- the *_local / timezone / age_policy / on_sale_now columns. 229 goes RED
-- throughout; 145 A4 / 180 A5 etc. return to 90; 226 F5/F6 return to 160's
-- projection. The supabase_migrations ledger row is NOT removed here (separate,
-- owner-authorised step).
--
--   162 bodies (md5 prosrc): create_ticket_type bfc2972e6aecb2dd5a0b4bd587dcc377
--                            set_ticket_type_price 7d1cc0c9d95b99b94f17ae9ab1f86932
--                            create_inventory_batch 30424f73432699526f4424bbcbf52c73
--                            set_batch_capacity 7aa6b6d303276f44125ab91829689542
--                            set_ticket_type_visibility 69ded39de3ca710d3f12c738784a2177
--                            set_ticket_type_rank fa9da73250e877b913bc178b4644f41d
--   160 bodies (md5 prosrc): create_ticket_type bba1f015338953b1b84ab1a8ce6e1ff9
--                            set_ticket_type_price 0b349a564a50fdda0b721d097a3bb9eb
--                            create_inventory_batch abedde3ce19d1a49087ac4a5c6aaacd0
--                            set_batch_capacity 76c69e9d8625b056e67e53c1d4e34fd9
--                            set_ticket_type_visibility d3d7f28c126641188ee1e68f312624ed
--                            set_ticket_type_rank e9aa82f8d38acf2e7fe4e050d596e4fe
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $guard$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure)
       IS DISTINCT FROM 'bfc2972e6aecb2dd5a0b4bd587dcc377'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_price(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '7d1cc0c9d95b99b94f17ae9ab1f86932'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure)
       IS DISTINCT FROM '30424f73432699526f4424bbcbf52c73'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '7aa6b6d303276f44125ab91829689542'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_visibility(uuid, text, text, text)'::regprocedure)
       IS DISTINCT FROM '69ded39de3ca710d3f12c738784a2177'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_rank(uuid, smallint, text)'::regprocedure)
       IS DISTINCT FROM 'fa9da73250e877b913bc178b4644f41d' THEN
    RAISE EXCEPTION 'ROLLBACK_162_REFUSED (G1): the live venue.* bodies are not 162''s; nothing changed.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'venue_cmd'
                AND p.proname NOT IN ('create_ticket_type','set_ticket_type_price','set_ticket_type_visibility',
                                      'set_ticket_type_rank','set_batch_capacity','get_inventory_counters',
                                      'set_venue_timezone','set_event_age_policy','set_session_sales_capacity',
                                      'set_ticket_type_sale_window','ticket_type_on_sale')
                AND (p.prosrc LIKE '%set_venue_timezone%' OR p.prosrc LIKE '%set_event_age_policy%'
                     OR p.prosrc LIKE '%set_session_sales_capacity%' OR p.prosrc LIKE '%set_ticket_type_sale_window%'
                     OR p.prosrc LIKE '%ticket_type_on_sale%')) THEN
    RAISE EXCEPTION 'ROLLBACK_162_REFUSED (G2): a later venue_cmd wrapper calls a function dropped here; roll that package back first. Nothing changed.';
  END IF;
  IF (EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.venue'::regclass AND attname = 'timezone' AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM catalog.venue WHERE timezone IS DISTINCT FROM 'America/New_York'))
  OR (EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.event'::regclass AND attname = 'age_policy' AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM catalog.event WHERE age_policy IS NOT NULL))
  OR (EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.event_session'::regclass AND attname = 'sales_capacity' AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM catalog.event_session WHERE sales_capacity IS NOT NULL))
  OR (EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'venue.ticket_type'::regclass AND attname = 'sale_starts_at' AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM venue.ticket_type WHERE sale_starts_at IS NOT NULL OR sale_ends_at IS NOT NULL)) THEN
    RAISE EXCEPTION 'ROLLBACK_162_REFUSED (G3): a 162 column carries values (timezone <> default, age_policy, sales_capacity or a sale window); a rollback does not drop data. Nothing changed.';
  END IF;
END $guard$;

-- 1. the five wrappers go first (sql-language bodies are not dependency-tracked; drop them before their targets)
DROP FUNCTION IF EXISTS venue_cmd.set_venue_timezone(uuid, text, text, text);
DROP FUNCTION IF EXISTS venue_cmd.set_event_age_policy(uuid, text, text, text);
DROP FUNCTION IF EXISTS venue_cmd.set_session_sales_capacity(uuid, integer, text, text);
DROP FUNCTION IF EXISTS venue_cmd.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text);
DROP FUNCTION IF EXISTS venue_cmd.ticket_type_on_sale(uuid, timestamptz);

-- 2. the three views (ticket_types depends on ticket_type_on_sale and on the new columns; events / event_sessions on timezone / age_policy)
DROP VIEW IF EXISTS venue_api.ticket_types;
DROP VIEW IF EXISTS venue_api.events;
DROP VIEW IF EXISTS venue_api.event_sessions;

-- 3. the five functions (their grants and comments go with them)
DROP FUNCTION IF EXISTS venue.ticket_type_on_sale(uuid, timestamptz);
DROP FUNCTION IF EXISTS venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text);
DROP FUNCTION IF EXISTS catalog.set_session_sales_capacity(uuid, integer, text, text);
DROP FUNCTION IF EXISTS catalog.set_event_age_policy(uuid, text, text, text);
DROP FUNCTION IF EXISTS catalog.set_venue_timezone(uuid, text, text, text);

-- 4. the five columns (the column grants on timezone / age_policy go with them)
ALTER TABLE venue.ticket_type        DROP COLUMN IF EXISTS sale_starts_at, DROP COLUMN IF EXISTS sale_ends_at;
ALTER TABLE catalog.event_session    DROP COLUMN IF EXISTS sales_capacity;
ALTER TABLE catalog.event            DROP COLUMN IF EXISTS age_policy;
ALTER TABLE catalog.venue            DROP COLUMN IF EXISTS timezone;

-- 5. the three views back to their pre-162 text, verbatim
-- 5.1 venue_api.ticket_types — 160 PART 6 (20261022100000_venue_tier_inventory_reads_and_setters.sql)
CREATE OR REPLACE VIEW venue_api.ticket_types
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT t.ticket_type_id, t.event_id, t.kind, t.name, t.price_minor, t.currency, t.visibility,
         t.created_at, t.updated_at, t.display_rank
    FROM venue.ticket_type t;
COMMENT ON VIEW venue_api.ticket_types IS 'venue.ticket_type; caller''s RLS applies (hidden types are manager/org-plane only).';
GRANT SELECT ON venue_api.ticket_types TO authenticated;
-- 5.2 venue_api.events — 159's text as revised 2026-10-26 (20261021120000_venue_api_read_views.sql:115-120:
--     description appended as column 8; comment verbatim)
CREATE OR REPLACE VIEW venue_api.events
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT e.event_id, e.venue_id, e.org_id, e.title, e.status, e.created_at, e.updated_at,
         e.description
    FROM catalog.event e;
COMMENT ON VIEW venue_api.events IS 'catalog.event, granted columns only (description last, 078:145; no hero/genre); caller''s RLS applies.';
GRANT SELECT ON venue_api.events TO authenticated;
-- 5.3 venue_api.event_sessions — 159's text
CREATE OR REPLACE VIEW venue_api.event_sessions
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT s.session_id, s.event_id, s.session_label, s.starts_at, s.ends_at, s.doors_at,
         s.door_open_at, s.status, s.created_at, s.updated_at
    FROM catalog.event_session s;
COMMENT ON VIEW venue_api.event_sessions IS 'catalog.event_session, granted columns only; caller''s RLS applies.';
GRANT SELECT ON venue_api.event_sessions TO authenticated;

-- 6. the six venue.* bodies, VERBATIM from 20261022100000_venue_tier_inventory_reads_and_setters.sql (do not tidy)
-- 6.1 160 5.1 (081:175)
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
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern). The org arm is unchanged.
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
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

-- 6.2 160 5.2 (081:246)
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
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern). The org arm is unchanged.
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
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

-- 6.3 160 5.3 (081:320)
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
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern). The org arm is unchanged.
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
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

-- 6.4 160 5.4 (081:408)
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
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern). The org arm is unchanged.
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
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

-- 6.5 160 PART 2
create or replace function venue.set_ticket_type_visibility(
  p_ticket_type_id uuid, p_visibility text, p_reason_code text, p_command_key text)
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
  v_old    text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_visibility is null or p_visibility not in ('hidden','public','door_only') then
    raise exception 'invalid_input: bad visibility %', coalesce(p_visibility, '<null>');
  end if;
  -- the set_ticket_type_price rule (081:270-272): a visibility flip lands in the audit with a reason.
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  select tt.visibility, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
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

  -- RM-3 helper on the org arm (unchanged form of the 081 writers); the venue
  -- arm carries E-76: the venue's CURRENT operator must be the event's org.
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old = p_visibility then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,'visibility',v_old);
  end if;

  update venue.ticket_type set visibility = p_visibility, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.visibility_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('visibility', v_old), jsonb_build_object('visibility', p_visibility));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,'visibility',p_visibility);
end;
$$;

-- 6.6 160 PART 3
create or replace function venue.set_ticket_type_rank(
  p_ticket_type_id uuid, p_display_rank smallint, p_command_key text)
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
  v_old    smallint;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_display_rank is not null and (p_display_rank < 0 or p_display_rank > 999) then
    raise exception 'invalid_input: bad display_rank % (0..999 or NULL)', p_display_rank;
  end if;

  select tt.display_rank, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
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

  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old is not distinct from p_display_rank then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,'display_rank',v_old);
  end if;

  update venue.ticket_type set display_rank = p_display_rank, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  -- no reason is required for a sort-order change (as create_ticket_type 081:232).
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.rank_change', 'ticket_type', p_ticket_type_id, 'self_service',
          jsonb_build_object('display_rank', v_old), jsonb_build_object('display_rank', p_display_rank));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,'display_rank',p_display_rank);
end;
$$;

-- 7. verify: the restored bodies ARE 160's; the columns and functions are gone; the views are back
DO $verify$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure)
       IS DISTINCT FROM 'bba1f015338953b1b84ab1a8ce6e1ff9'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_price(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '0b349a564a50fdda0b721d097a3bb9eb'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure)
       IS DISTINCT FROM 'abedde3ce19d1a49087ac4a5c6aaacd0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '76c69e9d8625b056e67e53c1d4e34fd9'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_visibility(uuid, text, text, text)'::regprocedure)
       IS DISTINCT FROM 'd3d7f28c126641188ee1e68f312624ed'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_ticket_type_rank(uuid, smallint, text)'::regprocedure)
       IS DISTINCT FROM 'e9aa82f8d38acf2e7fe4e050d596e4fe' THEN
    RAISE EXCEPTION 'ROLLBACK_162_VERIFY_FAILED: a restored venue.* body does not hash to 160''s.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE NOT attisdropped AND (
               (attrelid = 'catalog.venue'::regclass AND attname = 'timezone')
            OR (attrelid = 'catalog.event'::regclass AND attname = 'age_policy')
            OR (attrelid = 'catalog.event_session'::regclass AND attname = 'sales_capacity')
            OR (attrelid = 'venue.ticket_type'::regclass AND attname IN ('sale_starts_at','sale_ends_at')))) THEN
    RAISE EXCEPTION 'ROLLBACK_162_VERIFY_FAILED: a 162 column still exists.';
  END IF;
  IF to_regprocedure('catalog.set_venue_timezone(uuid, text, text, text)') IS NOT NULL
  OR to_regprocedure('catalog.set_event_age_policy(uuid, text, text, text)') IS NOT NULL
  OR to_regprocedure('catalog.set_session_sales_capacity(uuid, integer, text, text)') IS NOT NULL
  OR to_regprocedure('venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)') IS NOT NULL
  OR to_regprocedure('venue.ticket_type_on_sale(uuid, timestamptz)') IS NOT NULL
  OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_cmd') <> 6 THEN
    RAISE EXCEPTION 'ROLLBACK_162_VERIFY_FAILED: a 162 function or wrapper still exists.';
  END IF;
  IF (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.ticket_types'::regclass AND attnum > 0 AND NOT attisdropped) <> 10
  OR (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.events'::regclass AND attnum > 0 AND NOT attisdropped) <> 8
  OR (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.event_sessions'::regclass AND attnum > 0 AND NOT attisdropped) <> 10 THEN
    RAISE EXCEPTION 'ROLLBACK_162_VERIFY_FAILED: a venue_api view does not have its pre-162 column count (10/8/10).';
  END IF;
END $verify$;

COMMIT;
