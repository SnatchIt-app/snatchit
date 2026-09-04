-- ============================================================================
-- 108_door_machine_scan_authority.sql — close the service_role door-session
-- authorization gap the door-plane readiness report named (§9.5 conformance):
-- the door-session edge (verify_jwt:false, no auth.uid()) must be able to record
-- scans and reconcile offline batches, but venue.record_scan /
-- venue.reconcile_offline_scans authorize on has_venue_role(auth.uid()), which is
-- null on the service_role path. Grant the MACHINE the right to EXECUTE while the
-- DOOR SESSION decides scope — never a generic service-role bypass.
--
-- WHAT THIS MIGRATION IS. DARK / unapplied / undeployed. 093-107 IMMUTABLE. This
-- migration adds FOUR venue functions and re-creates the two existing scan RPCs
-- to delegate to shared cores. No public-schema object, Gate-2 untouched. It
-- CHANGES the venue function census (+4) and adds two service_role grants; the
-- two cores are zero-grant. Next migration after 107.
--
-- ── THE INVARIANT: MACHINE MAY EXECUTE, DOOR SESSION DECIDES SCOPE ───────────
-- The two machine entrypoints (record_scan_door, reconcile_offline_scans_door)
-- are service_role-granted, but they authorize NOTHING themselves: they call
-- kernel.assert_door_session(device, session, door_session_id, token) — the
-- SAME token gate the edge already uses — which returns the BOUND (device_id,
-- event_session_id). Every downstream write uses the RETURNED bound values, never
-- a body field. assert_door_session already refuses a token whose bound device or
-- session disagrees with the request (086:547, opaque door_session_invalid), so a
-- body device/session override is caught at the gate; scan_meta.device_id is
-- additionally rejected. service_role therefore CANNOT pick an arbitrary
-- atom/session/device — only what a live door session authorizes.
--
-- ── STRUCTURE (shared cores, two authorized entrypoints each) ────────────────
--   venue._record_scan_core(atom, session, device, actor_identity, meta, key)
--     — the 104 record_scan body verbatim (flag gate, terminal-session gate,
--       mark_ticket_scanned delegation, scan insert, first-in-wins) MINUS the
--       has_venue_role gate; takes the actor explicitly (auth.uid() for humans,
--       NULL for the machine — the scan row is then device-attributed, satisfying
--       scan_attribution_ck). ZERO grant.
--   venue._reconcile_core(session, device, actor_identity, batch, key)
--     — the 105 reconcile loop verbatim (deterministic order, per-item isolation,
--       session cross-check, {admitted,duplicates,conflicts}) MINUS the role
--       gate, delegating each item to _record_scan_core. ZERO grant.
--   venue.record_scan (authenticated)         = role gate -> _record_scan_core(auth.uid()).
--   venue.reconcile_offline_scans (authenticated) = role gate -> _reconcile_core(auth.uid()).
--   venue.record_scan_door (service_role)     = assert_door_session -> _record_scan_core(NULL, bound).
--   venue.reconcile_offline_scans_door (service_role) = assert_door_session -> _reconcile_core(NULL, bound).
-- Behavior for the authenticated paths is byte-identical to 104/105 (same gates,
-- same result shapes); the cores just centralize the body so the machine paths
-- reuse it without a role gate.
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — venue._record_scan_core: the authorization-free scan body. Callers
-- MUST have already authorized (role gate OR door-session assertion). ZERO grant.
-- ============================================================================
create or replace function venue._record_scan_core(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_actor_identity_id uuid,
  p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_session_status text; v_res jsonb; v_result text; v_scan_id uuid;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  -- terminal-session gate (104): a cancelled/completed (or unknown) session must
  -- not admit. X-12 restrictive — a null status (vanished session) fails closed.
  select es.status into v_session_status
    from catalog.event_session es where es.session_id = p_session_id;
  if v_session_status is null or v_session_status in ('cancelled','completed') then
    raise exception 'precondition_failed: session_not_admitting (status=%)', coalesce(v_session_status,'missing');
  end if;
  -- lifecycle transition (single-writer choke point).
  begin
    v_res := kernel.mark_ticket_scanned(p_atom_id, p_session_id, coalesce(p_scan_meta, '{}'::jsonb));
    v_result := 'admitted';
  exception when others then
    v_result := case when sqlerrm like '%not_active%' or sqlerrm like '%wrong_session%' then 'invalid'
                     when sqlerrm like '%listed_locked%' then 'invalid'
                     else 'invalid' end;
  end;
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, p_actor_identity_id, v_result,
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result);
exception when unique_violation then
  -- C41 first-in-wins: a second admitted inbound scan is a duplicate.
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, p_actor_identity_id, 'duplicate',
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate');
end;
$$;
comment on function venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text) is
  'INTERNAL (zero grant): the authorization-free admission body (104 record_scan minus the role gate). Callers MUST pre-authorize (venue.record_scan role gate, or venue.record_scan_door via kernel.assert_door_session). Terminal-session gate + mark_ticket_scanned + first-in-wins; actor passed explicitly (NULL on the machine path -> device-attributed).';
revoke all on function venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text) from public, anon, authenticated, service_role;

-- ============================================================================
-- PART 2 — venue._reconcile_core: the authorization-free reconcile loop (105
-- body minus the role gate). ZERO grant.
-- ============================================================================
create or replace function venue._reconcile_core(
  p_session_id uuid, p_actor_device_id uuid, p_actor_identity_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_item       jsonb;
  v_atom       uuid;
  v_item_sess  uuid;
  v_res        jsonb;
  v_result     text;
  v_admitted   integer := 0;
  v_duplicates integer := 0;
  v_conflicts  integer := 0;
begin
  for v_item in
    select elem
      from jsonb_array_elements(coalesce(p_batch, '[]'::jsonb)) elem
     order by (elem->>'server_receipt_at')::timestamptz nulls last,
              (elem->>'device_boot_id') nulls last,
              (elem->>'scan_sequence')::bigint nulls last,
              (elem->>'ticket_atom_id')
  loop
    -- Per-item isolation: the atom cast is INSIDE the block, so a non-UUID
    -- ticket_atom_id (e.g. "garbage") is caught as a conflict rather than
    -- raising invalid_text_representation OUTSIDE the handler and poisoning the
    -- whole batch (adversarial finding — the cast was outside in 105/086).
    begin
      v_atom := (v_item->>'ticket_atom_id')::uuid;
      v_item_sess := nullif(v_item->>'session_id','')::uuid;
      if v_item_sess is not null and v_item_sess <> p_session_id then
        raise exception 'precondition_failed: batch_session_mismatch — item session % is not the asserted session %', v_item_sess, p_session_id
          using errcode = 'P0001';
      end if;
      v_res := venue._record_scan_core(v_atom, p_session_id, p_actor_device_id, p_actor_identity_id, v_item, p_command_key || ':' || v_atom::text);
      v_result := v_res->>'result';
      if    v_result = 'admitted'  then v_admitted   := v_admitted + 1;
      elsif v_result = 'duplicate' then v_duplicates := v_duplicates + 1;
      else                              v_conflicts  := v_conflicts + 1;
      end if;
    exception when others then
      v_conflicts := v_conflicts + 1;
    end;
  end loop;
  return jsonb_build_object('status','ok','admitted', v_admitted,
                            'duplicates', v_duplicates, 'conflicts', v_conflicts);
end;
$$;
comment on function venue._reconcile_core(uuid,uuid,uuid,jsonb,text) is
  'INTERNAL (zero grant): the authorization-free offline-reconcile loop (105 reconcile_offline_scans minus the role gate). Deterministic order, per-item isolation, session cross-check, {admitted,duplicates,conflicts}; delegates each item to venue._record_scan_core. Callers MUST pre-authorize.';
revoke all on function venue._reconcile_core(uuid,uuid,uuid,jsonb,text) from public, anon, authenticated, service_role;

-- ============================================================================
-- PART 3 — venue.record_scan (authenticated): unchanged behavior — role gate,
-- then the core. Signature + grant frozen (086/104).
-- ============================================================================
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
comment on function venue.record_scan(uuid,uuid,uuid,jsonb,text) is
  'Admission ledger write (086/104): flag gate then venue_scanner/venue_manager gate then venue._record_scan_core (which re-checks the flag + the terminal-session gate + first-in-wins). credential_version currency stays at C37/the verifier (frozen §7.5/§1223). Behaviorally equivalent to 104 (same check order: flag before role).';

-- ============================================================================
-- PART 4 — venue.reconcile_offline_scans (authenticated): unchanged behavior —
-- role gate, then the core. Signature + grant frozen (086/105).
-- ============================================================================
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
comment on function venue.reconcile_offline_scans(uuid,uuid,jsonb,text) is
  'RPC §9.5 (086/105): venue_scanner/venue_manager gate then venue._reconcile_core. Deterministic order, per-item isolation, {admitted,duplicates,conflicts}. Behavior byte-identical to 105.';

-- ============================================================================
-- PART 5 — venue.record_scan_door (service_role machine path). The door-session
-- token is the sole authorization; scope is 100% server-derived from
-- kernel.assert_door_session. Body p_device_id/p_session_id are cross-checks the
-- assertion verifies; the scan uses the RETURNED bound values. scan_meta.device_id
-- is rejected (defense in depth — the core never reads it anyway).
-- ============================================================================
create or replace function venue.record_scan_door(
  p_atom_id uuid, p_session_id uuid, p_door_session_id uuid, p_session_token text,
  p_device_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_bound_device uuid; v_bound_session uuid;
begin
  -- a body-supplied device_id inside scan_meta is an override attempt — reject.
  if p_scan_meta ? 'device_id' then
    raise exception 'invalid_input: scan_meta.device_id is not accepted (the device is derived from the door session)';
  end if;
  -- the ONLY gate: the door session token. Returns the bound (device, session);
  -- a body device/session that disagrees raises the same opaque door_session_invalid.
  select device_id, event_session_id into v_bound_device, v_bound_session
    from kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token);
  -- use the BOUND scope, never the body fields.
  return venue._record_scan_core(p_atom_id, v_bound_session, v_bound_device, null, p_scan_meta, p_command_key);
end;
$$;
comment on function venue.record_scan_door(uuid,uuid,uuid,text,uuid,jsonb,text) is
  'MACHINE scan path (service_role, door-session edge): kernel.assert_door_session is the sole gate; the scan uses the RETURNED bound (device, session), never a body field (a mismatch raises opaque door_session_invalid). scan_meta.device_id rejected. Delegates to venue._record_scan_core with a NULL actor (device-attributed). MACHINE MAY EXECUTE; DOOR SESSION DECIDES SCOPE.';
revoke all on function venue.record_scan_door(uuid,uuid,uuid,text,uuid,jsonb,text) from public, anon, authenticated;
grant execute on function venue.record_scan_door(uuid,uuid,uuid,text,uuid,jsonb,text) to service_role;

-- ============================================================================
-- PART 6 — venue.reconcile_offline_scans_door (service_role machine path).
-- ============================================================================
create or replace function venue.reconcile_offline_scans_door(
  p_session_id uuid, p_door_session_id uuid, p_session_token text,
  p_device_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_bound_device uuid; v_bound_session uuid;
begin
  select device_id, event_session_id into v_bound_device, v_bound_session
    from kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token);
  -- the batch is reconciled against the BOUND session/device; a per-item
  -- session_id that disagrees is isolated as a conflict inside _reconcile_core
  -- (never attributed to the asserted session). Per-item device_id is never read
  -- (the bound device is authoritative), so it cannot override scope.
  return venue._reconcile_core(v_bound_session, v_bound_device, null, p_batch, p_command_key);
end;
$$;
comment on function venue.reconcile_offline_scans_door(uuid,uuid,text,uuid,jsonb,text) is
  'MACHINE offline-reconcile path (service_role, door-session edge): kernel.assert_door_session is the sole gate; the batch reconciles against the RETURNED bound (device, session), never a body field. A per-item session mismatch is isolated as a conflict; per-item device_id is never read. Delegates to venue._reconcile_core with a NULL actor.';
revoke all on function venue.reconcile_offline_scans_door(uuid,uuid,text,uuid,jsonb,text) from public, anon, authenticated;
grant execute on function venue.reconcile_offline_scans_door(uuid,uuid,text,uuid,jsonb,text) to service_role;

commit;
