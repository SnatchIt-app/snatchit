-- ============================================================================
-- 20261027015000_venue_session_capacity_read.sql — an identity-free STAFF READ
-- of a session's shared sales pool (catalog.event_session.sales_capacity, 162)
-- and its allocation, so the dashboard's pool editor can show the numbers
-- BEFORE catalog.set_session_sales_capacity refuses.
--
-- Registry 166 / pgTAP 233 — assigned by Claude A 2026-10-26 (registry 166/233).
-- A reviews before this leaves draft. DARK: applied nowhere (local rehearsal
-- clones only); exposes no schema, flips no flag, seeds no config key, writes no
-- row. venue_api / venue_cmd stay unexposed (owner setting); `venue` is never
-- exposed to a client.
-- ORDER: applies only AFTER 159 (20261021120000, venue_api), 161 (20261022110000,
-- venue_cmd) and 162 (20261026100000: catalog.event_session.sales_capacity and
-- catalog.set_session_sales_capacity, whose arithmetic and authority this read
-- restates) — the pre-flight below refuses otherwise. Stack order 159 → 176 →
-- 160 → 161 → 162 → 163 → 182 → 164 → 166 → 165 (164 and 165 touch none of
-- these objects). Roll back 166 BEFORE 162/161/159: 161's rollback refuses while
-- venue_cmd holds a function it did not create, 159's while venue_api holds a
-- view it did not create.
--
-- WHAT THIS MIGRATION IS (163 PART A's shape, mirrored object for object):
--   venue.get_session_capacity(p_session_id uuid)
--     returns table(session_id uuid, sales_capacity integer, allocated integer,
--                   remaining_to_allocate integer, capacity_hint integer)
--     STABLE SECURITY DEFINER plpgsql, search_path=''. Exactly one row for an
--     authorized caller; unknown session and unauthorized caller raise the SAME
--     'not_found: session <id>' (P0002) — no existence oracle, never numbers for
--     a stranger; auth.uid() NULL raises 42501 'insufficient_privilege:
--     authentication required' (163's form). The read refuses nothing else: a
--     completed/cancelled session is readable (the setter refuses to CHANGE it;
--     reading it changes nothing).
--   venue.list_session_capacity()
--     returns table(same five columns) STABLE SECURITY DEFINER LANGUAGE sql,
--     search_path=''. One row per catalog.event_session the CALLER may read under
--     the same authority rule, evaluated per session; sessions the caller may not
--     read are OMITTED (never raised); auth.uid() NULL = zero rows. Ordered by
--     starts_at, session_id.
--   venue_api.session_capacity — security_invoker + security_barrier VIEW over
--     venue.list_session_capacity(), explicit column list, SELECT to
--     authenticated only, owner = the migration runner (postgres) like 159's
--     eight and 163's session_admissions. venue_api stays views-only.
--   venue_cmd.get_session_capacity(p_session_id uuid) — the 161-form LANGUAGE sql
--     STABLE SECURITY INVOKER wrapper, identical argument list and result type,
--     so the dashboard reaches the single-session read through its command
--     transport (next to venue_cmd.set_session_sales_capacity, 162).
--
-- THE NUMBERS (each one is the setter's own arithmetic, so the editor can predict
-- the setter's verdict exactly — 233 Section C proves every boundary):
--   sales_capacity        = catalog.event_session.sales_capacity (NULL = unlimited).
--   allocated             = coalesce(SUM(venue.inventory_batch.capacity), 0) over
--                           EVERY batch of the session, every release_kind
--                           (public_sale, promoter_hold, comp, door, presale) —
--                           the exact sum set_session_sales_capacity compares in
--                           'below_allocated (new=% < allocated=%)' and
--                           create_inventory_batch in 'session_capacity_exceeded
--                           (allocated=% + new=% > sales_capacity=%)'. So: the
--                           lowest pool the setter accepts is `allocated`, and
--                           `allocated - 1` is refused.
--   remaining_to_allocate = sales_capacity - allocated; NULL when sales_capacity
--                           is NULL. The largest new batch create_inventory_batch
--                           accepts is `remaining_to_allocate`; one more seat is
--                           refused session_capacity_exceeded. It is NOT clamped:
--                           the setter and the batch writers keep it >= 0 under
--                           the session row lock; a negative value could only come
--                           from an out-of-band write and is shown as it is.
--   capacity_hint         = catalog.venue.capacity_hint of the EVENT's venue (NULL
--                           = no ceiling); the highest pool the setter accepts is
--                           capacity_hint, and capacity_hint + 1 is refused
--                           'above_venue_capacity (new=% > capacity_hint=%)'.
-- IDENTITY-FREE: no per-batch row, no batch id, no held, no sold, no tier, no
-- name, no actor. Five numbers per session. `allocated` is a SUM of capacities —
-- the figure the setter already returns to the same callers in its result JSON
-- ('allocated'), and capacity_hint is world-readable (078:124 column grant).
-- E-29 posture: raw per-batch capacity/held/sold stay withheld from every client
-- role (081:1011-1018); this read exposes only the session aggregate, and only to
-- the setter's own authority set.
--
-- AUTHORITY — EXACTLY the setter's (162 PART 7, catalog.set_session_sales_capacity,
-- read and copied; the 'not_found' raise replaces its 42501 so unknown and
-- unauthorized are indistinguishable):
--   kernel.has_org_role(event.org_id, ['org_owner','org_admin'])      -- the EVENT's org (R3, 088:1629)
--   OR (kernel.has_venue_role(event.venue_id, ['venue_manager'])
--       AND exists (select 1 from catalog.venue v
--                    where v.venue_id = event.venue_id and v.org_id = event.org_id))   -- E-76
--   org_finance / org_marketing, venue_finance / venue_box_office / venue_scanner /
--   venue_marketing / venue_promoter_manager, a cross-venue manager, a fan: refused
--   as not_found (the setter refuses them 42501 — they cannot change the pool, so
--   they get no number to plan with). On a RE-OPERATED room (venue.org_id moved
--   out of band; the RPC path is frozen — Decision C) the read answers exactly as
--   the setter does today: the event's own org_owner/org_admin read; the former-
--   operator manager is refused on the former operator's event (E-76) and accepted
--   on the new operator's event; the new operator's owner is refused on the former
--   operator's event. 233 pins those as STATUS QUO (165 flips) — 165 (E-76 on the
--   catalog event bodies) is where any change to that rule lands, setter and read
--   together.
--
-- WHY A DEFINER FUNCTION AND NOT A security_invoker VIEW OVER THE TABLES:
-- catalog.event_session.sales_capacity carries NO client column grant (162, E-29)
-- and venue.inventory_batch.capacity is withheld from every client role (081), so
-- an invoker view could not read either; widening those grants would hand every
-- authenticated caller (fans included — the batch SELECT policy has a public arm)
-- the raw figures. The authority lives in the definer bodies; venue_api.
-- session_capacity is security_invoker over the SET-RETURNING function (the caller
-- must hold EXECUTE on it and USAGE on venue — both true for authenticated:
-- 076:78 and the grants below).
--
-- GRANT DECISIONS (every one; the CI grant gates read `public` only, so pgTAP 233
-- is the gate for these objects, 228 sweeps the venue_cmd schema and 226 the
-- venue_api schema):
--   venue.get_session_capacity(uuid)        EXECUTE : authenticated ONLY. REVOKE ALL
--   venue.list_session_capacity()                      FROM PUBLIC, anon, authenticated,
--                                                      service_role first (067: a bare
--                                                      REVOKE FROM PUBLIC is not enough
--                                                      once role grants exist; the local
--                                                      replay shim's function default
--                                                      reaches public only, CI's fresh
--                                                      stack has none — the explicit
--                                                      service_role REVOKE makes the
--                                                      outcome identical on both), then
--                                                      GRANT EXECUTE TO authenticated.
--                                                      anon: NONE (076/E-30 walls anon
--                                                      from venue anyway). service_role:
--                                                      NONE — no server-side caller (the
--                                                      edges never plan a pool). PUBLIC:
--                                                      NONE. No proacl left DEFAULTED.
--   venue_cmd.get_session_capacity(uuid)    EXECUTE : authenticated ONLY (161 PART 7
--                                                      pattern; same REVOKE list). anon /
--                                                      PUBLIC / service_role: NONE. Schema
--                                                      USAGE unchanged (161: authenticated
--                                                      only).
--   venue_api.session_capacity              SELECT  : authenticated ONLY (159 pattern:
--                                                      REVOKE ALL FROM PUBLIC, anon,
--                                                      authenticated, service_role, then
--                                                      GRANT SELECT TO authenticated). No
--                                                      INSERT/UPDATE/DELETE, no column
--                                                      grant. Owner = the migration
--                                                      runner (postgres), as 159/163.
--   default privileges                               : none stored (161's reasoning).
--   catalog.event_session.sales_capacity / venue.inventory_batch.capacity
--                                                    : grants UNCHANGED (still no client
--                                                      column grant) — 233 does not
--                                                      widen them; the definer reads them.
--   catalog.set_session_sales_capacity / venue.create_inventory_batch /
--   venue.set_batch_capacity                         : bodies and grants UNCHANGED (162).
--
-- FOUR-FILE RULE (CLAUDE.md): the grant-decision manifest and expected_grants.txt
-- read `public` only (the manifest's B2 fails closed on a row for a function
-- outside public), so no row is added; a dated scope note names every object here
-- with its posture and the pgTAP that asserts it. Gate-2 census (ci.yml) reads
-- `public` only: unchanged 35|130|37|49 (dated comment line). Rollback:
-- supabase/rollbacks/20261027015000_venue_session_capacity_read_rollback.sql —
-- drops the view, the wrapper and the two venue functions (nothing else), IF
-- EXISTS, idempotent, rc 0.
-- PINS THIS MIGRATION MOVES (measured by running every supabase/tests/*.sql on the
-- stacked clone; the census commit names each): venue function count +2 (96 ->
-- 98), five-schema routine census +2 (317 -> 319), venue_api views +1 (9 -> 10)
-- and +5 columns (226 — F's, edited in this package), venue_cmd +1 (14 -> 15, 228
-- — D's), 140 PFA-1's named caller-authorized venue list (+get_session_capacity,
-- list_session_capacity).
--
-- VERIFICATION (after apply):
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue';      -- 98 (was 96)
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue_cmd';  -- 15 (was 14)
--   select count(*) from pg_views where schemaname='venue_api';                                               -- 10 (was 9)
--   select p.oid::regprocedure, p.proacl from pg_proc p
--    where p.oid in ('venue.get_session_capacity(uuid)'::regprocedure, 'venue.list_session_capacity()'::regprocedure,
--                    'venue_cmd.get_session_capacity(uuid)'::regprocedure);                                    -- {postgres=X/postgres,authenticated=X/postgres} x3
--   select relacl from pg_class where oid = 'venue_api.session_capacity'::regclass;                           -- {postgres=arwdDxtm/postgres,authenticated=r/postgres}
-- LOCKS / RUNTIME: CREATE FUNCTION / CREATE VIEW / GRANT only; no table is
-- touched, no row is read or written. lock_timeout 3s.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ============================================================================
-- PRE-FLIGHT — 159 (venue_api), 161 (venue_cmd) and 162 (the pool column + its setter)
-- ============================================================================
DO $pre$
BEGIN
  IF to_regnamespace('venue_api') IS NULL THEN
    RAISE EXCEPTION 'ORDER_166_REFUSED: schema venue_api (159, 20261021120000) is absent; apply 159 first';
  END IF;
  IF to_regnamespace('venue_cmd') IS NULL THEN
    RAISE EXCEPTION 'ORDER_166_REFUSED: schema venue_cmd (161, 20261022110000) is absent; apply 160 then 161 first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute
                  WHERE attrelid = 'catalog.event_session'::regclass AND attname = 'sales_capacity' AND NOT attisdropped)
     OR to_regprocedure('catalog.set_session_sales_capacity(uuid, integer, text, text)') IS NULL THEN
    RAISE EXCEPTION 'ORDER_166_REFUSED: catalog.event_session.sales_capacity / catalog.set_session_sales_capacity (162, 20261026100000) are absent; apply 162 first';
  END IF;
END $pre$;

-- ============================================================================
-- PART 1 — venue.get_session_capacity: one session, one row, or P0002
-- ============================================================================
create or replace function venue.get_session_capacity(p_session_id uuid)
returns table (
  session_id            uuid,
  sales_capacity        integer,
  allocated             integer,
  remaining_to_allocate integer,
  capacity_hint         integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_pool      integer;
  v_allocated integer;
  v_hint      integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  select e.org_id, e.venue_id, es.sales_capacity
    into v_org_id, v_venue, v_pool
    from catalog.event_session es
    join catalog.event e on e.event_id = es.event_id
   where es.session_id = p_session_id;

  -- catalog.set_session_sales_capacity's authority block (162 PART 7), verbatim: the EVENT's
  -- org plane, or the bound venue_manager while the room's CURRENT operator is the event's org
  -- (E-76). Unknown and unauthorized raise the SAME error: no existence oracle, no numbers.
  if v_org_id is null
     or not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
             or (kernel.has_venue_role(v_venue, array['venue_manager'])
                 and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;

  -- the setter's own sum (162 PART 7 / 9.3): every batch of the session, every release_kind.
  select coalesce(sum(b.capacity), 0) into v_allocated
    from venue.inventory_batch b where b.event_session_id = p_session_id;
  -- the setter's own ceiling: the EVENT's venue (NULL = no ceiling).
  select v.capacity_hint into v_hint from catalog.venue v where v.venue_id = v_venue;

  return query
    select p_session_id, v_pool, v_allocated, v_pool - v_allocated, v_hint;
end;
$$;
comment on function venue.get_session_capacity(uuid) is
  '166: identity-free staff read of one session''s shared sales pool — sales_capacity (NULL = unlimited), allocated = SUM(inventory_batch.capacity) over every batch of the session (the setter''s below_allocated sum), remaining_to_allocate = sales_capacity - allocated (NULL when unlimited), capacity_hint of the event''s venue (the setter''s above_venue_capacity ceiling). Authority = catalog.set_session_sales_capacity''s: org_owner/org_admin of the EVENT''s org or the bound venue_manager (E-76). Unknown and unauthorized sessions raise the same P0002.';

-- ============================================================================
-- PART 2 — venue.list_session_capacity: every session the caller may read
-- ============================================================================
create or replace function venue.list_session_capacity()
returns table (
  session_id            uuid,
  sales_capacity        integer,
  allocated             integer,
  remaining_to_allocate integer,
  capacity_hint         integer)
language sql
stable
security definer
set search_path = ''
as $$
  select es.session_id,
         es.sales_capacity,
         coalesce(a.allocated, 0)::integer,
         es.sales_capacity - coalesce(a.allocated, 0)::integer,
         vh.capacity_hint
    from catalog.event_session es
    join catalog.event e on e.event_id = es.event_id
    left join catalog.venue vh on vh.venue_id = e.venue_id
    left join lateral (
      select sum(b.capacity)::integer as allocated
        from venue.inventory_batch b
       where b.event_session_id = es.session_id) a on true
   where auth.uid() is not null
     and (kernel.has_org_role(e.org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(e.venue_id, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = e.venue_id and v.org_id = e.org_id)))
   order by es.starts_at, es.session_id
$$;
comment on function venue.list_session_capacity() is
  '166: the same five numbers for every event_session the caller may read (same authority as get_session_capacity, evaluated per session; unauthorized sessions are omitted, never raised; unauthenticated = zero rows). Ordered by starts_at, session_id. The base of venue_api.session_capacity.';

-- ============================================================================
-- PART 3 — venue_api.session_capacity: F's read surface, views-only schema
-- ============================================================================
CREATE OR REPLACE VIEW venue_api.session_capacity
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint
    FROM venue.list_session_capacity() c;
COMMENT ON VIEW venue_api.session_capacity IS
  '166: identity-free shared-pool numbers per session the caller may read (venue.list_session_capacity): sales_capacity (NULL = unlimited), allocated (every batch, every release_kind), remaining_to_allocate (NULL when unlimited), capacity_hint. No batch, no held/sold, no actor.';
REVOKE ALL ON venue_api.session_capacity FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON venue_api.session_capacity TO authenticated;

-- ============================================================================
-- PART 4 — venue_cmd.get_session_capacity: the 161-form invoker wrapper
-- ============================================================================
create or replace function venue_cmd.get_session_capacity(p_session_id uuid)
returns table (
  session_id            uuid,
  sales_capacity        integer,
  allocated             integer,
  remaining_to_allocate integer,
  capacity_hint         integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint
    from venue.get_session_capacity(p_session_id) c
$$;
comment on function venue_cmd.get_session_capacity(uuid) is
  '166: invoker wrapper -> venue.get_session_capacity. Same P0002 for unknown and unauthorized sessions.';

-- ============================================================================
-- PART 5 — ACLs: strip PUBLIC/anon/authenticated/service_role, grant exactly authenticated
-- ============================================================================
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue.get_session_capacity(uuid)',
    'venue.list_session_capacity()',
    'venue_cmd.get_session_capacity(uuid)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end $$;

-- ============================================================================
-- POST-FLIGHT — the exact ACLs, or nothing commits
-- ============================================================================
DO $post$
DECLARE
  v_fn  regprocedure;
  v_bad text := '';
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['venue.get_session_capacity(uuid)'::regprocedure,
                              'venue.list_session_capacity()'::regprocedure,
                              'venue_cmd.get_session_capacity(uuid)'::regprocedure] LOOP
    IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR has_function_privilege('anon', v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', v_fn, 'EXECUTE')
       OR (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
             FROM pg_proc p WHERE p.oid = v_fn) THEN
      v_bad := v_bad || ' ' || v_fn::text;
    END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated', 'venue_api.session_capacity', 'SELECT')
     OR has_table_privilege('authenticated', 'venue_api.session_capacity', 'INSERT, UPDATE, DELETE')
     OR has_table_privilege('anon', 'venue_api.session_capacity', 'SELECT')
     OR has_table_privilege('service_role', 'venue_api.session_capacity', 'SELECT')
     OR has_table_privilege('public', 'venue_api.session_capacity', 'SELECT') THEN
    v_bad := v_bad || ' venue_api.session_capacity';
  END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'MIGRATION_166_POSTFLIGHT_FAILED: unexpected ACL on%', v_bad;
  END IF;
END $post$;

COMMIT;
