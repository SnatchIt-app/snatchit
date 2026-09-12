-- ============================================================================
-- 107_door_pin_kdf_unpark_rollback.sql — revert migration 107.
-- Restores the PARKED venue.create_door_pin (086:918-930) and
-- venue.mint_door_session (086:955-969). The pgcrypto extension is LEFT in place
-- (dropping a shared extension is unsafe and out of scope; it is harmless when
-- unused). CLEAN-WHILE-EMPTY: 107 stored no PIN in a rolled-back window.
-- ============================================================================
begin;

create or replace function venue.create_door_pin(
  p_venue_id uuid, p_session_id uuid, p_label text, p_pin_plain text, p_expires_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: door_pin_kdf_unavailable — door-PIN slow-KDF mechanism not yet ratified (PFA-26); door PIN creation is parked fail-closed';
end;
$$;

create or replace function venue.mint_door_session(
  p_venue_id uuid, p_session_id uuid, p_device_id uuid, p_pin_plain text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: door_pin_kdf_unavailable — door-session mint depends on the parked door-PIN mechanism (PFA-26); parked fail-closed';
end;
$$;

commit;
