-- ============================================================================
-- supabase/rollbacks/20261027035000_door_schedule_conformance_rollback.sql
-- Rollback for registry 190: restores the 086 PART 9 body of catalog.set_session_door_schedule
-- VERBATIM (authority after the boundary test, free-text freeze message, no custody guards, no
-- audit row, two-key result). Guarded like the migration: the pre-flight accepts 190's body or
-- the 086 body; the post-restore asserts the 086 md5. Nothing else is touched — 190 adds no
-- object, so there is nothing to drop.
-- WARNING, stated plainly: rolling back re-opens the §20.6.5 gap. A later doors_at move on a
-- session that already has atoms becomes possible again with no reason code and no audit row,
-- which pushes the implicit freeze backstop later (the C6 overlap). Prefer a forward fix.
-- ============================================================================
begin;
do $pf$
declare v_md5 text := md5(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure));
begin
  if v_md5 not in ('68d48676a48bf3d1b440a2e6be40a83e', 'ff724eaf52e7713773c8e301a4b9d448') then
    raise exception 'precondition_failed: 190 rollback refuses to overwrite an unexpected catalog.set_session_door_schedule body (md5 %)', v_md5;
  end if;
end $pf$;

create or replace function catalog.set_session_door_schedule(
  p_session_id uuid, p_doors_at timestamptz, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row catalog.event_session%rowtype;
begin
  select * into v_row from catalog.event_session where session_id = p_session_id for update;
  if not found then raise exception 'not_found: session %', p_session_id using errcode = 'P0002'; end if;
  -- once the door has actually opened, the schedule is frozen.
  if v_row.door_open_at is not null then
    raise exception 'precondition_failed: door already opened — schedule is frozen';
  end if;
  if not (kernel.has_org_role((select ev.org_id from catalog.event ev where ev.event_id = v_row.event_id),
            array['org_owner','org_admin'])
          or kernel.has_venue_role((select ev.venue_id from catalog.event ev where ev.event_id = v_row.event_id),
            array['venue_manager'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update catalog.event_session set doors_at = p_doors_at, updated_at = now() where session_id = p_session_id;
  return jsonb_build_object('status','ok','session_id', p_session_id);
end;
$$;

do $pc$
declare v_md5 text := md5(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure));
begin
  if v_md5 <> 'ff724eaf52e7713773c8e301a4b9d448' then
    raise exception 'precondition_failed: 190 rollback post-restore self-check — the restored body (md5 %) is not the 086 body; this file was modified', v_md5;
  end if;
end $pc$;
commit;
