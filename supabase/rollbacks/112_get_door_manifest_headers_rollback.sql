-- ============================================================================
-- 112_get_door_manifest_headers_rollback.sql — mechanical reversal of migration
-- 112 (P1-M2-HEADER). MECHANICAL-REVERSIBILITY REHEARSAL ONLY (production is
-- forward-only). Re-creates migration 086's `venue.get_door_manifest` body
-- VERBATIM (this text is generated from 086_venue_door_and_scan.sql, not
-- hand-copied): no header fields, expired-open episodes returned, the bare
-- `{status:'no_open_episode'}` no-episode result. Grants are preserved by
-- create-or-replace. Idempotent.
-- ============================================================================
begin;

create or replace function venue.get_door_manifest(p_session_id uuid, p_since_delta_seq integer default 0)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_m venue.door_manifest%rowtype; v_venue uuid; v_entries jsonb; v_deltas jsonb;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open'
   order by manifest_version desc limit 1;
  if not found then
    return jsonb_build_object('status','no_open_episode');
  end if;
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
  return jsonb_build_object('status','ok','manifest_id', v_m.manifest_id, 'manifest_version', v_m.manifest_version,
    'manifest_digest', v_m.manifest_digest, 'max_delta_seq', v_m.max_delta_seq,
    'entries', v_entries, 'deltas', v_deltas);
end;
$$;

comment on function venue.get_door_manifest(uuid, integer) is
  'M2 read — 086 body restored by the 112 rollback (rehearsal only): no open/session_id/opened_at/not_after header fields.';

commit;
