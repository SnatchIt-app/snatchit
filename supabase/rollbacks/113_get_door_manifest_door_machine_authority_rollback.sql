-- ============================================================================
-- 113_get_door_manifest_door_machine_authority_rollback.sql — mechanical
-- reversal of migration 113 (P1-M2-DOOR-AUTHZ). MECHANICAL-REVERSIBILITY
-- REHEARSAL ONLY (production is forward-only). Drops the machine entrypoint and
-- the zero-grant core, and re-creates migration 112's `venue.get_door_manifest`
-- body VERBATIM (generated from 112_get_door_manifest_headers.sql, not
-- hand-copied). Grants on the staff RPC are preserved by create-or-replace.
-- Census returns to venue 83 / five-schema 292. Idempotent.
-- ============================================================================
begin;

drop function if exists venue.get_door_manifest_door(uuid,uuid,text,uuid,integer);

create or replace function venue.get_door_manifest(p_session_id uuid, p_since_delta_seq integer default 0)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_m venue.door_manifest%rowtype; v_venue uuid; v_entries jsonb; v_deltas jsonb;
begin
  -- authorization — unchanged from 086 (caller identity; RLS §11.4 staff arm).
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;

  -- the open, UNEXPIRED episode (door §7.5 precondition; conflict 2 above).
  select * into v_m from venue.door_manifest
   where session_id = p_session_id and status = 'open' and not_after > now()
   order by manifest_version desc limit 1;
  if not found then
    return jsonb_build_object('open', false, 'status', 'no_open_episode',
                              'entries', '[]'::jsonb, 'deltas', '[]'::jsonb);
  end if;

  -- entry / delta projections — unchanged from 086 (no public_key, no identity; PFA-24).
  select coalesce(jsonb_agg(jsonb_build_object(
           'ticket_atom_id', e.ticket_atom_id, 'serial_no', e.serial_no, 'ticket_type_id', e.ticket_type_id,
           'credential_version', e.credential_version, 'signing_key_id', e.signing_key_id,
           'ticket_state', e.ticket_state, 'resale_state', e.resale_state) order by e.serial_no), '[]'::jsonb)
    into v_entries from venue.door_manifest_entry e where e.manifest_id = v_m.manifest_id;
  select coalesce(jsonb_agg(jsonb_build_object(
           'seq', d.seq, 'ticket_atom_id', d.ticket_atom_id, 'op', d.op, 'serial_no', d.serial_no,
           'ticket_type_id', d.ticket_type_id, 'credential_version', d.credential_version,
           'signing_key_id', d.signing_key_id, 'ticket_state', d.ticket_state, 'resale_state', d.resale_state) order by d.seq), '[]'::jsonb)
    into v_deltas from venue.door_manifest_delta d
   where d.manifest_id = v_m.manifest_id and d.seq > coalesce(p_since_delta_seq, 0);

  -- header — the stored row, verbatim (MP1-READ-SET header: session_id, not_after).
  return jsonb_build_object(
    'open', true, 'status', 'ok',
    'manifest_id', v_m.manifest_id, 'manifest_version', v_m.manifest_version,
    'session_id', v_m.session_id, 'opened_at', v_m.opened_at, 'not_after', v_m.not_after,
    'manifest_digest', v_m.manifest_digest, 'max_delta_seq', v_m.max_delta_seq,
    'entries', v_entries, 'deltas', v_deltas);
end;
$$;

comment on function venue.get_door_manifest(uuid, integer) is
  'M2 read — 112 body restored by the 113 rollback (rehearsal only): role gate + inline read; no machine path.';

drop function if exists venue._get_door_manifest_core(uuid,integer);

commit;
