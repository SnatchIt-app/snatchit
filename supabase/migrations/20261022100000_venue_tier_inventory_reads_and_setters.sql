-- ============================================================================
-- 20261022100000_venue_tier_inventory_reads_and_setters.sql — S1 tiers and
-- inventory (DB slice): tier visibility/rank setters, the staff inventory
-- counters read, display_rank, and the E-76 current-operator binding on the
-- venue arm of the four 081 writers.
--
-- Registry 160 / pgTAP 227 — assigned by Claude A 2026-10-22 (registry 573850a4).
-- A reviews before this leaves draft. DARK: applied nowhere (local rehearsal
-- clones only); exposes no schema, flips no flag, seeds no config key. venue_api
-- and venue_cmd stay unexposed (owner setting). No PFA control is bypassed; no
-- disabled reader is exposed.
--
-- ORDER (registry 573850a4): applies only AFTER 159 (20261021120000, F's
-- venue_api read views — part 6 re-creates venue_api.ticket_types and fails fast
-- if 159 is absent) and BEFORE 161 (20261022110000, the venue_cmd transport,
-- whose wrappers call the functions created here).
--
-- WHAT THIS MIGRATION IS (S1 build plan 2a-2h; S1_slice.json scope (a)-(d)):
--  1. venue.ticket_type.display_rank smallint NULL, CHECK 0..999. Additive; 081
--     is untouched; the table-level SELECT grant (081:988) already covers the new
--     column, so a fan reads the rank of a PUBLIC tier exactly as it reads its
--     name, and nothing else changes in who reads what (pgTAP 227 F1-F5).
--  2. venue.set_ticket_type_visibility(p_ticket_type_id uuid, p_visibility text,
--     p_reason_code text, p_command_key text) returns jsonb. The setter the
--     dashboard copy promises (EventSetup.tsx:150 "flip tiers public") and no 081
--     RPC delivered: the only ticket_type writers were 081:175 and 081:246.
--     Visibility in ('hidden','public','door_only'); reason required (the
--     set_ticket_type_price rule, 081:270-272); FOR UPDATE of the tier joined to
--     catalog.event; completed/cancelled -> 'precondition_failed: event_terminal';
--     same value -> {status:'noop'} and NO audit row; otherwise UPDATE + one
--     kernel.admin_audit row 'ticket_type.visibility_change' with before/after.
--  3. venue.set_ticket_type_rank(p_ticket_type_id uuid, p_display_rank smallint,
--     p_command_key text) returns jsonb. Same authority, same terminal refusal,
--     audit 'ticket_type.rank_change' (reason_code 'self_service': no reason is
--     required, as create_ticket_type 081:232). 0..999 or NULL (NULL clears the
--     rank — unranked is a state the dashboard renders, not an error).
--  4. venue.get_inventory_counters(p_event_id uuid) returns table(batch_id,
--     ticket_type_id, event_session_id, release_kind, capacity, held, sold,
--     remaining). STABLE SECURITY DEFINER, search_path ''. The staff read E-29
--     intended: 081:1011-1018 withholds capacity/held/sold from EVERY client role
--     ("venue staff read the raw counters through the batch/capacity RPC RESULT
--     JSON, never a table SELECT") and no 081 RPC returned them for an event.
--     Unknown and unauthorized events raise the SAME 'not_found' (P0002): the
--     dashboard renders "Couldn't load", never zero, and the function is not an
--     existence oracle. NO column grant is added on venue.inventory_batch.
--  5. Body-only CREATE OR REPLACE of venue.create_ticket_type (081:175),
--     set_ticket_type_price (081:246), create_inventory_batch (081:320) and
--     set_batch_capacity (081:408) at their EXACT signatures. The bodies are
--     byte-copies of 081 (generated mechanically from the 081 file; the rollback
--     restores the byte-identical 081 text and asserts its md5) with exactly ONE
--     change each: the venue arm `kernel.has_venue_role(v_venue, ['venue_manager'])`
--     is conjoined with `exists (select 1 from catalog.venue v where v.venue_id =
--     v_venue and v.org_id = v_org_id)` — E-76, the 088:1628-1631 cancel_event
--     pattern. The org arm (has_org_role_over_venue) is UNCHANGED: whether it
--     should also bind to the event's org is A's call (227 B9/B10 pin the status
--     quo so A sees exactly what the unchanged arm does on a re-operated room).
--     Execute grants unchanged (081:1074-1113 stay as applied).
--  6. CREATE OR REPLACE VIEW venue_api.ticket_types (159) with display_rank
--     appended as the LAST column; security_invoker + security_barrier kept; the
--     view's ACL (SELECT to authenticated) and comment persist across the
--     replace. 226 F5/F6 pin the old projection: the one-hunk update is F's
--     (delivered as a patch in D's evidence dir, never applied to 226 by D).
--  7. REVOKE ALL FROM PUBLIC, anon, authenticated and GRANT EXECUTE TO
--     authenticated on the three new functions (the 081 PART 16 pattern). Nothing
--     for anon (076/E-30 walls anon from venue anyway) and nothing for
--     service_role (the four 081 writers grant it nothing either).
--
-- AUTHORITY of the two setters (one expression, the post-E-76 writer form):
--   kernel.has_org_role_over_venue(v_venue, ['org_owner','org_admin'])
--   OR (kernel.has_venue_role(v_venue, ['venue_manager']) AND venue.org_id = event.org_id)
-- AUTHORITY of the counters read (the conservative intersection; see below):
--   kernel.has_org_role_over_event(e, ['org_owner','org_admin','org_finance'])
--   OR (kernel.has_event_role(e, ['venue_manager','venue_finance']) AND venue.org_id = event.org_id)
--
-- E-76 ENUMERATION (A's instruction 3, 2026-10-22; the full table is in D's
-- evidence dir, E76_CALLER_ENUMERATION.md). The conjunct NARROWS the accepted
-- input set, so every caller of the four writers was enumerated on ce1c9737 and
-- on the read-only refs A named:
--   - chain (supabase/migrations): no caller besides 081's own definitions/grants;
--   - supabase/functions/* edges: none; ops console / ops.*: none;
--   - src/lib/venue/client.ts:160/180/197/212: a PostgREST passthrough with no
--     importer anywhere and `venue` is not an exposed schema — never called;
--   - F's dashboard (origin/venue/production-readiness): demo ids and copy only
--     (CreateEventWizard.tsx:61/90, preview.ts:107-108); venue/src issues no
--     .rpc() call and preview.ts:59 keeps writesEnabled=false on the database source;
--   - scripts/rehearsal_m2_evidence.sql:41-42 and pgTAP 145,146,147,148,149,150,
--     153,154,155,157,164,168,169,170,171,172,174,175,178,179: every event was
--     created by catalog.create_event, which stamps event.org_id FROM the venue
--     (078:866-868), with no operatorship change before the writer call (153
--     re-operates its venue only at 153:1090, after its writer calls, for
--     cancel_event's own E-76 test), and every caller is the org_owner that
--     created the org (the ORG arm, unchanged here).
--   How venue.org_id <> event.org_id arises at all: ONLY catalog.update_venue
--   with patch key org_id (078:684-704) — a platform_admin-only, audited TENANCY
--   MOVE that does not re-stamp the venue's existing events. That is the state
--   E-76 closes for cancel_event (088) and, with this migration, for the four
--   writers and the two new setters. No existing caller is newly refused;
--   227 B1-B4 (negative) and B5-B8 (positive) pin it.
--
-- COUNTER READERS — OWNER DECISION ITEM (not settled). The default here is the
-- conservative intersection of 081's inventory_batch read arms (org_owner/
-- org_admin/org_finance + venue_manager/venue_finance). venue_scanner is in
-- 081's batch RLS arm but is excluded here; venue_box_office is excluded. The
-- owner decides which roles read raw counters; widening is a one-array change
-- plus 227 E11/E12.
--
-- FOUR-FILE RULE (CLAUDE.md): the grant-decision manifest and expected_grants.txt
-- read `public` only (159 added no row for the same reason; the manifest's B2
-- fails closed on a row for a function outside public), so no row is added;
-- pgTAP 227 A8/A9 pin the exact EXECUTE ACL of the three functions and A16 the
-- view's ACL, the way 226 F1/F2 do for venue_api. The Gate-2 census (ci.yml)
-- reads `public` only: unchanged (a dated comment line records it).
-- PINS THIS MIGRATION MOVES (existing pgTAP files D does not edit; the one-hunk
-- updates are delivered as patch files in D's evidence dir for their owners):
--   venue function count 87 -> 90: 144 A15, 145 A4, 148 B5, 180 A5;
--   five-schema routine census 305 -> 308: 148 B2, 157 A46, 180 A6;
--   140 #27 (named caller-authorized venue functions): + the three new names;
--   226 F5 (55 -> 56 columns) and F6 (exp_ticket_types): + display_rank.
-- Every other suite in the sweep (141, 146, 149, 150, 168) is unchanged. Rollback:
-- supabase/rollbacks/20261022100000_venue_tier_inventory_reads_and_setters_rollback.sql
-- — restores the four 081 bodies verbatim (md5-asserted both ways), drops the
-- three functions, restores 159's view, drops display_rank only when it is all
-- NULL, and refuses while venue_cmd (161) exists.
--
-- VERIFICATION (after apply):
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue';   -- 90 (was 87)
--   select attname from pg_attribute where attrelid='venue_api.ticket_types'::regclass and attnum>0 and not attisdropped order by attnum;  -- …, display_rank last
--   select proname, md5(prosrc) from pg_proc where oid in ('venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure, ...);
--   -- expected post-160 md5s: create_ticket_type bba1f015338953b1b84ab1a8ce6e1ff9 · set_ticket_type_price 0b349a564a50fdda0b721d097a3bb9eb
--   --                        create_inventory_batch abedde3ce19d1a49087ac4a5c6aaacd0 · set_batch_capacity 76c69e9d8625b056e67e53c1d4e34fd9
--   -- pre-160 (081) md5s:   create_ticket_type fa7e5142616ff9f4cf7fcfcdedbb6a41 · set_ticket_type_price a09ecad391c8614dc722db33c99f57d3
--   --                        create_inventory_batch a623aa97364549a17eabe414da1ca713 · set_batch_capacity 325c25eb1dc363e3d12ceefd081e8e4e
-- LOCKS / RUNTIME: ADD COLUMN (nullable, no default) takes a brief ACCESS
-- EXCLUSIVE on venue.ticket_type with no rewrite (the CHECK validates existing
-- rows, all NULL); CREATE OR REPLACE FUNCTION/VIEW take brief locks; no data
-- is read or written.
-- ============================================================================
BEGIN;

-- ============================================================================
-- PART 1 — venue.ticket_type.display_rank (additive)
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'venue.ticket_type'::regclass
                    and attname = 'display_rank' and not attisdropped) then
    alter table venue.ticket_type
      add column display_rank smallint
        constraint ticket_type_display_rank_check check (display_rank between 0 and 999);
  end if;
end $$;
comment on column venue.ticket_type.display_rank is
  'Dashboard sort rank of the tier within its event (0..999; NULL = unranked). Set only by venue.set_ticket_type_rank (160). Read by every role that reads the row (081:988 table grant).';

-- ============================================================================
-- PART 2 — venue.set_ticket_type_visibility (S1 F1/F4: the setter; S5 enforces
-- visibility at purchase time)
-- ============================================================================
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
comment on function venue.set_ticket_type_visibility(uuid, text, text, text) is
  '160: tier visibility setter (hidden|public|door_only). org_owner/org_admin of the venue''s org or the venue_manager of the venue while it operates the event''s org (E-76). Reason required; terminal events refused; same value = noop without audit.';

-- ============================================================================
-- PART 3 — venue.set_ticket_type_rank (S1 F1: display order)
-- ============================================================================
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
comment on function venue.set_ticket_type_rank(uuid, smallint, text) is
  '160: tier display_rank setter (0..999; NULL clears). Same authority and terminal rule as set_ticket_type_visibility; no reason code; same value = noop without audit.';

-- ============================================================================
-- PART 4 — venue.get_inventory_counters (S1 F2/F3: the staff read E-29 intended)
-- ============================================================================
create or replace function venue.get_inventory_counters(p_event_id uuid)
returns table (
  batch_id         uuid,
  ticket_type_id   uuid,
  event_session_id uuid,
  release_kind     text,
  capacity         integer,
  held             integer,
  sold             integer,
  remaining        integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  select e.org_id, e.venue_id into v_org_id, v_venue
    from catalog.event e where e.event_id = p_event_id;

  -- OWNER DECISION ITEM (header): the conservative intersection of 081's batch
  -- read arms. Unknown and unauthorized raise the SAME error — no existence
  -- oracle, never zeros (the dashboard renders "Couldn't load").
  if v_org_id is null
     or not (kernel.has_org_role_over_event(p_event_id, array['org_owner','org_admin','org_finance'])
             or (kernel.has_event_role(p_event_id, array['venue_manager','venue_finance'])
                 and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  return query
    select b.batch_id, b.ticket_type_id, b.event_session_id, b.release_kind,
           b.capacity, b.held, b.sold, b.remaining
      from venue.inventory_batch b
      join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
     where tt.event_id = p_event_id
     order by b.event_session_id, b.ticket_type_id, b.batch_id;
end;
$$;
comment on function venue.get_inventory_counters(uuid) is
  '160: raw per-batch counters (capacity/held/sold/remaining) of one event for org_owner/org_admin/org_finance and the bound venue_manager/venue_finance (E-29 staff read; reader set is an owner decision). Unknown and unauthorized events raise the same P0002.';

-- ============================================================================
-- PART 5 — E-76 on the four 081 writers (body-only replaces at the exact
-- signatures; bodies are byte-copies of 081 with ONE substitution each — see
-- the header). The rollback restores the 081 text verbatim.
-- ============================================================================

-- 5.1 venue.create_ticket_type (081:175)
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

-- 5.2 venue.set_ticket_type_price (081:246)
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

-- 5.3 venue.create_inventory_batch (081:320)
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

-- 5.4 venue.set_batch_capacity (081:408)
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

-- ============================================================================
-- PART 6 — venue_api.ticket_types: 159's projection + display_rank LAST
-- (CREATE OR REPLACE keeps the view's ACL and comment; options re-stated)
-- ============================================================================
CREATE OR REPLACE VIEW venue_api.ticket_types
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT t.ticket_type_id, t.event_id, t.kind, t.name, t.price_minor, t.currency, t.visibility,
         t.created_at, t.updated_at, t.display_rank
    FROM venue.ticket_type t;

-- ============================================================================
-- PART 7 — function ACLs (081 PART 16 pattern: strip PUBLIC, grant exactly)
-- ============================================================================
revoke all on function venue.set_ticket_type_visibility(uuid, text, text, text) from public, anon, authenticated;
revoke all on function venue.set_ticket_type_rank(uuid, smallint, text)          from public, anon, authenticated;
revoke all on function venue.get_inventory_counters(uuid)                       from public, anon, authenticated;
grant execute on function venue.set_ticket_type_visibility(uuid, text, text, text) to authenticated;
grant execute on function venue.set_ticket_type_rank(uuid, smallint, text)          to authenticated;
grant execute on function venue.get_inventory_counters(uuid)                       to authenticated;

COMMIT;
