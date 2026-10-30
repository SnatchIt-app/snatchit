-- ============================================================================
-- 113_get_door_manifest_door_machine_authority.sql — close P1-M2-DOOR-AUTHZ
-- (SCANNER_VERIFIER_CONTRACT.md §7): the door-session edge's `/manifest/sync`
-- relays through a service_role client, but `venue.get_door_manifest` (086/112)
-- authorizes on has_venue_role(auth.uid()) — null on that path — and holds no
-- service_role grant, so the relay was refused 42501 (178 A2/D4). Same closure
-- as migration 108 gave the scan/reconcile relays: MACHINE MAY EXECUTE, DOOR
-- SESSION DECIDES SCOPE — never a generic service-role bypass.
--
-- WHAT THIS MIGRATION IS. LOCAL / REHEARSAL ARTIFACT — NOT DEPLOYED, NOT APPLIED
-- TO PRODUCTION. Adds TWO venue functions (one zero-grant core, one service_role
-- machine entrypoint) and re-creates the 112 staff RPC body-only to delegate to
-- the core. No public-schema object, Gate-2 untouched. CENSUS: venue functions
-- 83 -> 85; five-schema routine count 292 -> 294 (suites 144 A15, 145 A4, 148 B5,
-- 156 A20 moved by exactly these two, re-derived from the live catalog). The 140
-- anon/PUBLIC/authenticated sweep is unmoved: the core revokes PUBLIC and every
-- client role; the machine entrypoint is service_role-only. Next after 112.
--
-- ── THE INVARIANT (108 verbatim): MACHINE MAY EXECUTE, DOOR SESSION DECIDES SCOPE
-- The machine entrypoint is service_role-granted but authorizes NOTHING itself:
-- it calls kernel.assert_door_session(device, session, door_session_id, token)
-- — the SAME token gate the edge already uses — which returns the BOUND
-- (device_id, event_session_id). The manifest is fetched for the RETURNED bound
-- session, never for a body field. assert_door_session refuses (opaque
-- door_session_invalid, 42501) an unknown id, a wrong token, an expired or
-- revoked session, an inactive device, an expired/revoked PIN, and a body
-- device/session that disagrees with the bound row — so caller-supplied
-- identifiers are cross-checks only. The edge's own earlier assert is the
-- rate-limit + opaque-auth gate; THIS database-side assert is the authorization
-- of record, so credentials invalidated between the two checks are refused here.
--
-- ── STRUCTURE (shared core, two authorized entrypoints) ──────────────────────
--   venue._get_door_manifest_core(session, since)      — the 112 read body
--     verbatim (open+unexpired episode by stored not_after; header from the
--     stored row; entry/delta projections; no public_key/identity) MINUS the
--     role gate. ZERO grant (PUBLIC, anon, authenticated, service_role all revoked).
--   venue.get_door_manifest (authenticated, UNCHANGED grants/authz)
--                                                       = has_venue_role gate -> core.
--   venue.get_door_manifest_door (service_role)         = assert_door_session -> core(bound).
-- The staff response is byte-identical to 112 (same header, stored not_after,
-- privacy exclusions, delta semantics — suite 178 is unchanged and still passes).
--
-- ── NOT IN THIS MIGRATION (explicitly open) ──────────────────────────────────
-- M1 distribution to door devices, `door-manifest` signature.key_id, signed M1
-- bundles — SCANNER_VERIFIER_CONTRACT.md §7 P2-MANIFEST-KEY / P2-M1-DELIVERY /
-- P3-M1-SIGNING.
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — venue._get_door_manifest_core: the authorization-free read body.
-- Callers MUST have already authorized (staff role gate OR door-session
-- assertion). ZERO grant. STABLE (reads only).
-- ============================================================================
create or replace function venue._get_door_manifest_core(p_session_id uuid, p_since_delta_seq integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_m venue.door_manifest%rowtype; v_entries jsonb; v_deltas jsonb;
begin
  -- the open, UNEXPIRED episode (door §7.5 precondition; 112 conflict 2).
  select * into v_m from venue.door_manifest
   where session_id = p_session_id and status = 'open' and not_after > now()
   order by manifest_version desc limit 1;
  if not found then
    return jsonb_build_object('open', false, 'status', 'no_open_episode',
                              'entries', '[]'::jsonb, 'deltas', '[]'::jsonb);
  end if;

  -- entry / delta projections — unchanged from 086/112 (no public_key, no identity; PFA-24).
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
comment on function venue._get_door_manifest_core(uuid, integer) is
  'INTERNAL (zero grant): the authorization-free M2 read body (112 get_door_manifest minus the role gate). Callers MUST pre-authorize (venue.get_door_manifest role gate, or venue.get_door_manifest_door via kernel.assert_door_session). Stored header (open/session_id/opened_at/not_after), door §7.5 not_after > now() precondition, entry/delta projections, no public_key/identity — all unchanged from 112.';
revoke all on function venue._get_door_manifest_core(uuid, integer) from public, anon, authenticated, service_role;

-- ============================================================================
-- PART 2 — venue.get_door_manifest (authenticated staff path): body-only
-- re-create — the 112 role gate, then the core. Grants preserved by
-- create-or-replace (authenticated EXECUTE; service_role NONE — unchanged).
-- ============================================================================
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
comment on function venue.get_door_manifest(uuid, integer) is
  'M2 read, STAFF path (RPC §20.6.1 / door §7.5). 113: role gate (has_venue_role(venue,[venue_scanner,venue_manager]) — caller identity only) then venue._get_door_manifest_core; response byte-identical to 112 (stored header open/session_id/opened_at/not_after, not_after > now() precondition, no public_key/identity). The service_role door path is venue.get_door_manifest_door (113), never this function.';

-- ============================================================================
-- PART 3 — venue.get_door_manifest_door (service_role MACHINE path). The
-- door-session token is the sole authorization; scope is 100% server-derived
-- from kernel.assert_door_session. Body p_device_id/p_session_id are
-- cross-checks the assertion verifies; the manifest is read for the RETURNED
-- bound session. VOLATILE (assert_door_session touches last_seen_at).
-- ============================================================================
create or replace function venue.get_door_manifest_door(
  p_session_id uuid, p_door_session_id uuid, p_session_token text,
  p_device_id uuid, p_since_delta_seq integer default 0)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_bound_device uuid; v_bound_session uuid;
begin
  -- the ONLY gate: the door session token. Returns the bound (device, session);
  -- a body device/session that disagrees raises the same opaque door_session_invalid.
  select device_id, event_session_id into v_bound_device, v_bound_session
    from kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token);
  -- read for the BOUND session, never the body field.
  return venue._get_door_manifest_core(v_bound_session, p_since_delta_seq);
end;
$$;
comment on function venue.get_door_manifest_door(uuid,uuid,text,uuid,integer) is
  'MACHINE M2 read (service_role, door-session edge /manifest/sync): kernel.assert_door_session is the sole gate; the manifest is read for the RETURNED bound session, never a body field (a mismatch raises opaque door_session_invalid). Delegates to venue._get_door_manifest_core. MACHINE MAY EXECUTE; DOOR SESSION DECIDES SCOPE. Closes P1-M2-DOOR-AUTHZ.';
revoke all on function venue.get_door_manifest_door(uuid,uuid,text,uuid,integer) from public, anon, authenticated;
grant execute on function venue.get_door_manifest_door(uuid,uuid,text,uuid,integer) to service_role;

commit;
