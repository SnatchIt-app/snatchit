-- ============================================================================
-- supabase/rollbacks/20261027000000_e76_door_operator_binding_rollback.sql
-- Rollback for registry 187: restores the NINE predecessor gate bodies VERBATIM (108/086/
-- 107/113/125 as they stand after 183) and drops venue.assert_session_operator(uuid).
-- Guarded like the migration: pre-flight accepts 187's body or the predecessor body per
-- gate; post-restore asserts the predecessor md5 per gate.
-- ============================================================================
begin;
do $pf$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.record_scan(uuid,uuid,uuid,jsonb,text)', '68144a168878e72c3a3888113cf4a3b8', 'fa48a67b83893e1cf4c0cbd4764a5620'),
    ('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)', 'c18f03d7cee504f4bafe42a8875e58ec', '945af8d6446bbceb637e0e3de6499fc6'),
    ('venue.validate_ticket_online(uuid,uuid)', 'c5085c53eda7abf45c1a64233fe0fbe7', 'd595ee4ab152c2a0c30ff0e0c19a8169'),
    ('venue.revoke_door_pin(uuid,text)', '68e9e9067518d48b513dd7f1dfd88af6', '498027d95150b8f57dd17676aff49116'),
    ('venue.allocate_comp(uuid,uuid,integer,text,text)', '73ad103d04ce30dbf7d7238ade284a26', '8e4d779f1a4cc8158349e20b7b8bc603'),
    ('venue.check_in_guest_entry(uuid,uuid,text,text)', 'fe01bd1bca452f63957972f9990bcb52', '825c03467db92f092491ea54e71b88eb'),
    ('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)', '37fe461eb19b259ae382fc12a26ccadc', '9f5ed2d7ca6eba24ef576bdcf81a577c'),
    ('venue.get_door_manifest(uuid,integer)', 'e195700a966a3a741b2bee53bfcf940d', '7c38de6f4243eb37c5b746bfbc962681'),
    ('venue.sync_scan_device_manifest(uuid,uuid,integer)', 'f9d3e5279ce25534028fb1672d5d7a10', '6beca3168e76bb566e456b6abd467197')
  ) as t(fn, md5_a, md5_b) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 not in (r.md5_a, r.md5_b) then
      raise exception 'precondition_failed: 187 rollback refuses to overwrite an unexpected % body (md5 %) — re-examine the migration order', r.fn, v_md5;
    end if;
  end loop;
end $pf$;

create or replace function venue.record_scan(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_flag boolean;
begin
  -- Preserve 104's observable check ORDER: the native-scanning flag gate runs
  -- FIRST, BEFORE the venue-role gate, so an unprivileged caller sees the same
  -- feature_disabled (not insufficient_privilege) while the feature is dark — no
  -- new error oracle. (The core re-checks the flag; the double-read is cheap and
  -- keeps the core self-contained for the machine path.)
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  return venue._record_scan_core(p_atom_id, p_session_id, p_actor_device_id, auth.uid(), p_scan_meta, p_command_key);
end;
$$;



create or replace function venue.reconcile_offline_scans(
  p_session_id uuid, p_actor_device_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  return venue._reconcile_core(p_session_id, p_actor_device_id, auth.uid(), p_batch, p_command_key);
end;
$$;



create or replace function venue.validate_ticket_online(p_atom_id uuid, p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid; v_t kernel.tickets%rowtype;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_t from kernel.tickets where ticket_atom_id = p_atom_id and event_session_id = p_session_id;
  if not found then return jsonb_build_object('status','not_found'); end if;
  return jsonb_build_object('status','ok','ticket_state', v_t.state, 'resale_state', v_t.resale_state,
    'signing_key_id', v_t.signing_key_id, 'credential_version', v_t.credential_version,
    'admissible', (v_t.state = 'active' and v_t.resale_state = 'none'
                   and not kernel.is_transfer_frozen(p_atom_id)));
end;
$$;



create or replace function venue.revoke_door_pin(p_pin_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.door_pin%rowtype;
begin
  select * into v_row from venue.door_pin where pin_id = p_pin_id for update;
  if not found then raise exception 'not_found: pin %', p_pin_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update venue.door_pin set status = 'revoked', updated_at = now() where pin_id = p_pin_id;
  -- RV-1: every door session minted from this pin dies with it, in the same txn.
  update venue.door_session set status = 'revoked', revoked_at = now(), revoked_reason = 'pin_revoked'
   where pin_id = p_pin_id and status = 'active';
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.pin_revoke', 'door_pin', p_pin_id, 'revoked');
  return jsonb_build_object('status','ok','pin_id', p_pin_id);
end;
$$;



create or replace function venue.allocate_comp(
  p_session_id uuid, p_batch_id uuid, p_quantity integer, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_id uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'precondition_failed: bad_quantity'; end if;
  insert into venue.comp_allocation (event_session_id, batch_id, quantity, granted_by)
  values (p_session_id, p_batch_id, p_quantity, auth.uid()) returning id into v_id;
  return jsonb_build_object('status','ok','comp_allocation_id', v_id);
end;
$$;



create or replace function venue.check_in_guest_entry(p_entry_id uuid, p_session_id uuid, p_outcome text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid;
begin
  if p_outcome not in ('arrived','no_show') then raise exception 'invalid_input: bad outcome'; end if;
  select ev.venue_id into v_venue from venue.guest_entry ge
   join venue.guest_list gl on gl.id = ge.guest_list_id
   join catalog.event_session es on es.session_id=gl.event_session_id
   join catalog.event ev on ev.event_id=es.event_id where ge.id = p_entry_id;
  if v_venue is null then raise exception 'not_found: entry %', p_entry_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office','venue_scanner']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update venue.guest_entry set status = p_outcome,
         checked_in_at = case when p_outcome='arrived' then now() else checked_in_at end, updated_at = now()
   where id = p_entry_id;
  return jsonb_build_object('status','ok','guest_entry_id', p_entry_id, 'outcome', p_outcome);
end;
$$;



create or replace function venue.create_door_pin(
  p_venue_id uuid, p_session_id uuid, p_label text, p_pin_plain text, p_expires_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_pin_id uuid; v_ok boolean;
begin
  -- authz: venue_manager of THIS venue.
  if not kernel.has_venue_role(p_venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  -- PIN safety envelope (NOT a frozen digit rule): reject empty/whitespace-only
  -- and oversized before the KDF. octet_length keeps multibyte under bcrypt's 72.
  if p_pin_plain is null or btrim(p_pin_plain) = '' then
    raise exception 'invalid_input: pin must be non-empty';
  end if;
  if octet_length(p_pin_plain) < 1 or octet_length(p_pin_plain) > 64 then
    raise exception 'invalid_input: pin must be 1-64 bytes';
  end if;
  if p_expires_at is null or p_expires_at <= now() then
    raise exception 'invalid_input: expires_at must be in the future';
  end if;
  -- the session must belong to THIS venue (a venue_manager of V cannot mint a PIN
  -- for another venue's session by naming V as venue_id + a foreign session_id).
  select exists (select 1 from catalog.event_session es join catalog.event ev on ev.event_id = es.event_id
                  where es.session_id = p_session_id and ev.venue_id = p_venue_id) into v_ok;
  if not v_ok then
    raise exception 'not_found: session % is not in venue %', p_session_id, p_venue_id using errcode = 'P0002';
  end if;

  insert into venue.door_pin (venue_id, event_session_id, label, pin_hash, status, expires_at)
  values (p_venue_id, p_session_id, coalesce(p_label,'door'),
          extensions.crypt(p_pin_plain, extensions.gen_salt('bf', 12)), 'active', p_expires_at)
  returning pin_id into v_pin_id;

  -- audit WITHOUT the PIN or the hash (C9): only the non-secret selector + label.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.pin_create', 'door_pin', v_pin_id, coalesce(p_label,'door'));

  -- NEVER return the hash. Only the non-secret pin_id.
  return jsonb_build_object('status','ok','pin_id', v_pin_id, 'expires_at', p_expires_at);
end;
$$;



create or replace function venue.get_door_manifest(p_session_id uuid, p_since_delta_seq integer default 0)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid;
begin
  -- authorization — unchanged from 086/112 (caller identity; RLS §11.4 staff arm).
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  return venue._get_door_manifest_core(p_session_id, p_since_delta_seq);
end;
$$;



create or replace function venue.sync_scan_device_manifest(p_device_id uuid, p_session_id uuid, p_known_manifest_version integer)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.scan_device%rowtype; v_res jsonb;
begin
  select * into v_row from venue.scan_device where device_id = p_device_id for update;
  if not found then raise exception 'not_found: device %', p_device_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- 125: ONE read — the M2 contract read (112/113: status='open' AND not_after > now();
  -- an expired-but-open episode is open:false). The session-venue role gate inside
  -- get_door_manifest is evaluated here exactly as 086 evaluated it on return.
  -- FAIL-SAFE full sync preserved: p_known_manifest_version is the per-session
  -- EPISODE counter, NOT a delta-seq cursor, so the complete manifest is returned.
  v_res := venue.get_door_manifest(p_session_id, 0);
  -- bind the device ONLY to the episode the contract reports open, and to exactly
  -- the manifest it returned — never to a row the read refuses.
  if coalesce((v_res ->> 'open')::boolean, false) then
    update venue.scan_device
       set manifest_version = (v_res ->> 'manifest_version')::integer,
           manifest_id      = (v_res ->> 'manifest_id')::uuid,
           last_sync_at     = now(), updated_at = now()
     where device_id = p_device_id;
  end if;
  return v_res;
end;
$$;



drop function if exists venue.assert_session_operator(uuid);

do $pc$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.record_scan(uuid,uuid,uuid,jsonb,text)', 'fa48a67b83893e1cf4c0cbd4764a5620'),
    ('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)', '945af8d6446bbceb637e0e3de6499fc6'),
    ('venue.validate_ticket_online(uuid,uuid)', 'd595ee4ab152c2a0c30ff0e0c19a8169'),
    ('venue.revoke_door_pin(uuid,text)', '498027d95150b8f57dd17676aff49116'),
    ('venue.allocate_comp(uuid,uuid,integer,text,text)', '8e4d779f1a4cc8158349e20b7b8bc603'),
    ('venue.check_in_guest_entry(uuid,uuid,text,text)', '825c03467db92f092491ea54e71b88eb'),
    ('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)', '9f5ed2d7ca6eba24ef576bdcf81a577c'),
    ('venue.get_door_manifest(uuid,integer)', '7c38de6f4243eb37c5b746bfbc962681'),
    ('venue.sync_scan_device_manifest(uuid,uuid,integer)', '6beca3168e76bb566e456b6abd467197')
  ) as t(fn, md5_x) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 <> r.md5_x then
      raise exception 'precondition_failed: 187 rollback post-restore self-check — % body (md5 %) is not the expected body; this file was modified', r.fn, v_md5;
    end if;
  end loop;
end $pc$;

commit;
