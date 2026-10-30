-- ============================================================================
-- 106_revoke_signing_key_unpark_rollback.sql — revert migration 106.
-- Restores the PARKED kernel.revoke_signing_key (086:714-721) and the pre-106
-- venue.open_door_manifest (086:728-808, without the revoked-key precondition).
-- CLEAN-WHILE-EMPTY: 106 changed no data, only two function bodies.
-- ============================================================================
begin;

create or replace function kernel.revoke_signing_key(
  p_key_id uuid, p_reason_code text, p_ack_live_credentials integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); signing-key revocation is parked, no key state changes and no episode is force-closed';
end;
$$;

create or replace function venue.open_door_manifest(
  p_session_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_sess   catalog.event_session%rowtype;
  v_venue  uuid;
  v_mid    uuid;
  v_ver    integer;
  v_count  integer;
  v_ttl    interval;
  v_first  boolean;
  v_opened_at timestamptz;
begin
  select * into v_sess from catalog.event_session where session_id = p_session_id for update;   -- rank 1
  if not found then raise exception 'not_found: session %', p_session_id using errcode = 'P0002'; end if;
  select ev.venue_id into v_venue from catalog.event ev where ev.event_id = v_sess.event_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.has_org_role((select ev.org_id from catalog.event ev where ev.event_id = v_sess.event_id),
               array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: venue_manager / org_owner|admin / platform_admin only' using errcode = '42501';
  end if;
  if v_sess.status not in ('announced','live','on_sale','scheduled') then
    if v_sess.status in ('cancelled','ended','completed') then
      raise exception 'precondition_failed: session_terminal (%)', v_sess.status;
    end if;
  end if;
  if exists (select 1 from venue.door_manifest m where m.session_id = p_session_id and m.status = 'open') then
    select manifest_id into v_mid from venue.door_manifest where session_id = p_session_id and status = 'open';
    return jsonb_build_object('status','noop_replay','manifest_id', v_mid);
  end if;

  select (c.value #>> '{}')::interval into v_ttl from catalog.platform_config c
   where c.key = 'door.manifest_ttl_interval' order by c.version desc limit 1;
  v_first := (v_sess.door_open_at is null);
  select coalesce(max(manifest_version),0)+1 into v_ver from venue.door_manifest where session_id = p_session_id;

  select count(*)::int into v_count from kernel.tickets t where t.event_session_id = p_session_id;

  insert into venue.door_manifest (manifest_id, session_id, venue_id, manifest_version, status,
         opened_by, open_reason_code, not_after, entry_count, manifest_digest, command_idempotency_key)
  values (gen_random_uuid(), p_session_id, v_venue, v_ver, 'open',
          coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), p_reason_code,
          now() + coalesce(v_ttl, interval '12 hours'), v_count,
          md5(p_session_id::text || ':' || v_ver::text || ':' || now()::text), p_command_key)
  returning manifest_id, opened_at into v_mid, v_opened_at;

  insert into venue.door_manifest_entry (manifest_id, ticket_atom_id, serial_no, ticket_type_id,
         credential_version, signing_key_id, ticket_state, resale_state)
  select v_mid, t.ticket_atom_id, t.serial_no, t.ticket_type_id, t.credential_version,
         t.signing_key_id, t.state, t.resale_state
    from kernel.tickets t where t.event_session_id = p_session_id;

  if v_first then
    perform catalog.engage_door_freeze(p_session_id, v_opened_at);
    perform market.on_door_freeze_engaged(p_session_id, v_mid);
  end if;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'session.door_manifest_open',
          'event_session', p_session_id, p_reason_code);
  perform notify.emit_event('DoorManifestOpened', 'event_session', p_session_id,
          'door_open:' || v_mid::text, jsonb_build_object('manifest_id', v_mid, 'version', v_ver, 'entry_count', v_count));

  return jsonb_build_object('status','ok','manifest_id', v_mid, 'manifest_version', v_ver, 'entry_count', v_count);
exception when unique_violation then
  select manifest_id into v_mid from venue.door_manifest
   where session_id = p_session_id and command_idempotency_key = p_command_key;
  if v_mid is not null then return jsonb_build_object('status','idempotency_replay','manifest_id', v_mid); end if;
  raise;
end;
$$;

commit;
