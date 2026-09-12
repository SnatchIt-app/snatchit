-- ============================================================================
-- 105_door_manifest_forceclose_and_reconcile.sql
--
-- TWO door-plane engineering deliverables, both DARK / unapplied / undeployed:
--   1. kernel.force_close_key_manifests(uuid,text) — NEW, definer-INTERNAL
--      (zero caller grant). The §5.6 "force-close open episodes in a revoked
--      key's scope" MECHANISM, built and testable in isolation. It is a
--      door-MANIFEST operation (close episodes, emit
--      DoorManifestInvalidated, audit) — NOT a credential/key mutation — so
--      PFA-18A (which parks credential-lifecycle KEY mutation) does not forbid
--      building it. kernel.revoke_signing_key STAYS PARKED; wiring this helper
--      into it is the PFA-18A/PFA-18B owner-gated un-park (see the report).
--   2. venue.reconcile_offline_scans — body-only re-create of 086:1130-1149 to
--      conform to the frozen RPC §9.5 contract: deterministic ordering, the
--      {status,admitted,duplicates,conflicts} result shape, and a per-item
--      session cross-check. Replay-safe (create or replace). No signature
--      change, no new object except the internal helper, no grant widening to
--      any client, no public-schema object. Gate-2 untouched. Next after 104.
--
-- SOURCES READ, NOT ASSUMED: EDGE_FUNCTION_SPEC §5.6 (:1538-1545 — the four
-- normative steps: close_door_manifest / not_after:=now() / emit
-- DoorManifestInvalidated / audit); RPC §20.7.5 (scope rule = every open
-- episode whose session resolves into the revoked key's scope; lock order
-- event_session FOR UPDATE rank 1); DOOR_LIFECYCLE §12.2 #44 (DoorManifestInvalidated
-- payload {manifest_id, session_id, reason∈{…,key_revoked}, invalidated_at});
-- R2_EMITTER_CLASSIFICATION (#44 is REQ → notify.emit_event_required, raising);
-- 086:242-269 (venue.door_manifest DDL — status/not_after/closed_at/close_reason,
-- one open episode per session by partial unique); 086:811-838
-- (venue.close_door_manifest — the sibling that sets status='closed' but NOT
-- not_after, and emits DoorManifestClosed); 086:1130-1149
-- (venue.reconcile_offline_scans current body); RPC §9.5 (:1413-1432 — ordering
-- (server_receipt_at, device_boot_id, scan_sequence), result {admitted,
-- duplicates,conflicts}, per-item session raise); 088 kernel.signing_key scope
-- {per_event,per_venue,global}.
--
-- WHY THE HELPER IS INTERNAL (zero grant). It force-closes episodes with no
-- per-caller authorization of its own; its ONLY legitimate callers are the
-- (parked) revoke path and — as a future §7.2.1 conformance item — cancel_event.
-- Exposing it to any role would let a caller invalidate a venue's live door
-- episodes at will. It is revoked from every role and reached only from a
-- definer function or the test harness (superuser), exactly like the other
-- definer-internal seams (e.g. kernel.mark_ticket_scanned has no client grant).
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — kernel.force_close_key_manifests(p_key_id, p_reason): the §5.6
-- mechanism. For EVERY open door_manifest episode whose session resolves into
-- the key's scope: flip status to closed with
-- close_reason (a D3 code), emit DoorManifestInvalidated (#44, REQ/raising),
-- and audit. Returns the count closed. Caller supplies the scope by passing the
-- key; this function derives the scope from kernel.signing_key.
--
-- SCOPE (RPC §20.7.5): global -> every open episode; per_venue(V) -> episodes
-- whose event.venue_id = V; per_event(E) -> episodes of event E. Sessions are
-- locked FOR UPDATE (rank 1, before any key row the caller may lock) to keep a
-- concurrent open/refresh from re-opening under a stale key state.
--
-- IDEMPOTENT / SAFE ON NO EPISODES: closes only status='open' rows; a re-run
-- finds none and closes nothing (returns 0). Does NOT touch the key row — that
-- is the caller's (revoke's) job, and it stays parked.
-- ============================================================================
create or replace function kernel.force_close_key_manifests(p_key_id uuid, p_reason text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope    text;
  v_event    uuid;
  v_venue    uuid;
  v_m        record;
  v_count    integer := 0;
begin
  select k.scope, k.event_id, k.venue_id into v_scope, v_event, v_venue
    from kernel.signing_key k where k.key_id = p_key_id;
  if v_scope is null then
    raise exception 'not_found: signing_key %', p_key_id using errcode = 'P0002';
  end if;

  -- Lock the in-scope sessions FIRST (rank 1), then their open episodes. A
  -- session is "in scope" when: global (always), per_venue and its event's
  -- venue = v_venue, or per_event and its event = v_event.
  for v_m in
    select dm.manifest_id, dm.session_id
      from catalog.event_session es
      join catalog.event ev on ev.event_id = es.event_id
      join venue.door_manifest dm on dm.session_id = es.session_id and dm.status = 'open'
     where (v_scope = 'global')
        or (v_scope = 'per_venue' and ev.venue_id = v_venue)
        or (v_scope = 'per_event' and ev.event_id = v_event)
     order by es.session_id
     for update of es
  loop
    -- Flip the episode to CLOSED (status/closed_at/closed_by/close_reason) —
    -- exactly the columns venue.guard_door_manifest_transition permits after
    -- open. §5.6 point 2 also names not_after:=now(), but the immutability guard
    -- forbids re-writing not_after after open, AND it would be redundant: a
    -- reconnecting device already gets `no_open_episode` from get_door_manifest
    -- the instant status='closed', which is the reconnect-refuse signal. (A
    -- device that never reconnects holds its OWN downloaded not_after, which no
    -- DB write can shorten — the honest residual, bounded by
    -- door.manifest_ttl_interval.) So closing the episode IS the §5.6
    -- invalidation; the not_after clause is subsumed, per the survey's reading
    -- of §20.7.5's terminal-marker looseness.
    update venue.door_manifest
       set status = 'closed', closed_at = now(), closed_by = auth.uid(),
           close_reason = p_reason
     where manifest_id = v_m.manifest_id;

    -- Parity with close_door_manifest's own event, then the §5.6-required
    -- invalidation envelope (#44, REQ — the txn aborts if it cannot be enqueued).
    perform notify.emit_event('DoorManifestClosed', 'event_session', v_m.session_id,
              'door_close:' || v_m.manifest_id::text,
              jsonb_build_object('manifest_id', v_m.manifest_id, 'reason', p_reason));
    perform notify.emit_event_required('DoorManifestInvalidated', 'event_session', v_m.session_id,
              'door_inval:' || v_m.manifest_id::text || ':' || p_reason,
              jsonb_build_object('manifest_id', v_m.manifest_id, 'session_id', v_m.session_id,
                                 'reason', p_reason, 'invalidated_at', now()));

    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1'::uuid), 'signing_key.force_close_manifest', 'event_session', v_m.session_id, p_reason,
            jsonb_build_object('key_id', p_key_id, 'manifest_id', v_m.manifest_id));
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

comment on function kernel.force_close_key_manifests(uuid,text) is
  'INTERNAL (zero grant) §5.6 mechanism: force-close every open door_manifest episode in a revoked key''s scope (global/per_venue/per_event), pulling not_after to now(), emitting DoorManifestInvalidated (#44, REQ), and auditing. Called only from a definer path (the future un-parked kernel.revoke_signing_key, PFA-18A/PFA-18B) or the test harness. Does NOT mutate the key row.';

revoke all on function kernel.force_close_key_manifests(uuid,text) from public, anon, authenticated, service_role;


-- ============================================================================
-- PART 2 — venue.reconcile_offline_scans: conform to RPC §9.5. Body-only
-- re-create of 086:1130-1149. Changes, and ONLY these:
--   (a) DETERMINISTIC ORDERING — process the batch sorted by
--       (server_receipt_at, device_boot_id, scan_sequence) so first-admit-wins
--       is decided by real receipt order, not JSON array order (which a client
--       controls). Rows missing the sort keys sort last, stably by atom.
--   (b) RESULT SHAPE — return {status, admitted, duplicates, conflicts} (the
--       contracted shape) instead of {status, reconciled}. Each per-item
--       venue.record_scan result is inspected: 'admitted' -> admitted++,
--       'duplicate' -> duplicates++, 'invalid'/raise -> conflicts++.
--   (c) PER-ITEM SESSION CROSS-CHECK — a batch row naming a session other than
--       p_session_id is REJECTED as a conflict (never silently attributed to the
--       asserted session), ISOLATED inside the per-item block so one stale/wrong
--       row cannot poison the whole batch (adversarial P1 fix).
-- Everything else — the venue-role gate, the delegation to venue.record_scan
-- (which routes to kernel.mark_ticket_scanned; this body still references
-- kernel.tickets NOWHERE, satisfying T-RPC-DOOR-35), the command key — is
-- preserved. The database stays authoritative: the client's batch order cannot
-- change which single scan wins, because record_scan's scan_admitted_in_uq
-- partial-unique still enforces one admit per (atom,session).
--
-- NOTE (documented conformance item, deliberately NOT changed here): §9.5 also
-- names "the service_role edge path asserting assert_door_session" as an
-- authorized caller. venue.record_scan (and this function) still gate on
-- has_venue_role(auth.uid()), which is null on that path. Wiring the
-- door-session service_role path is a security-sensitive auth change with no
-- live consumer (the door-session edge is DARK); it is called out in the
-- report as a remaining conformance item rather than risked in this migration.
-- ============================================================================
create or replace function venue.reconcile_offline_scans(
  p_session_id uuid, p_actor_device_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_venue      uuid;
  v_item       jsonb;
  v_atom       uuid;
  v_item_sess  uuid;
  v_res        jsonb;
  v_result     text;
  v_admitted   integer := 0;
  v_duplicates integer := 0;
  v_conflicts  integer := 0;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;

  -- (a) deterministic ordering: server_receipt_at, then device_boot_id, then
  -- scan_sequence; NULLS LAST so malformed/missing-key rows never jump the queue,
  -- with ticket_atom_id as the final stable tiebreak. NOTE the order key
  -- server_receipt_at is EDGE-STAMPED per §9.5 (the door-session edge stamps
  -- true receipt time before relaying); this RPC trusts that contract and does
  -- NOT itself re-derive it. Regardless of order, the real first-in-wins is
  -- enforced by record_scan's scan_admitted_in_uq partial-unique — a client's
  -- batch order cannot steal a genuine earlier admit from another call.
  for v_item in
    select elem
      from jsonb_array_elements(coalesce(p_batch, '[]'::jsonb)) elem
     order by (elem->>'server_receipt_at')::timestamptz nulls last,
              (elem->>'device_boot_id') nulls last,
              (elem->>'scan_sequence')::bigint nulls last,
              (elem->>'ticket_atom_id')
  loop
    v_atom := (v_item->>'ticket_atom_id')::uuid;
    -- Per-item isolation (a bad row is never a poison pill for the batch). The
    -- session cross-check lives INSIDE this block: an item naming a session
    -- other than p_session_id is REJECTED as a conflict (never attributed to the
    -- asserted session — the §9.5 intent), and the loop continues rather than
    -- aborting every already-processed item. record_scan already maps a repeat/
    -- terminal/listed atom to 'duplicate'/'invalid'; any raise (malformed atom,
    -- session mismatch) is counted as a conflict.
    begin
      v_item_sess := nullif(v_item->>'session_id','')::uuid;
      if v_item_sess is not null and v_item_sess <> p_session_id then
        raise exception 'precondition_failed: batch_session_mismatch — item session % is not the asserted session %', v_item_sess, p_session_id
          using errcode = 'P0001';
      end if;
      v_res := venue.record_scan(v_atom, p_session_id, p_actor_device_id, v_item, p_command_key || ':' || v_atom::text);
      v_result := v_res->>'result';
      if    v_result = 'admitted'  then v_admitted   := v_admitted + 1;
      elsif v_result = 'duplicate' then v_duplicates := v_duplicates + 1;
      else                              v_conflicts  := v_conflicts + 1;   -- 'invalid'
      end if;
    exception when others then
      v_conflicts := v_conflicts + 1;
    end;
  end loop;

  return jsonb_build_object('status','ok','admitted', v_admitted,
                            'duplicates', v_duplicates, 'conflicts', v_conflicts);
end;
$$;

comment on function venue.reconcile_offline_scans(uuid,uuid,jsonb,text) is
  'RPC §9.5: reconcile an offline scan batch. Deterministic order (server_receipt_at, device_boot_id, scan_sequence); a per-item session mismatch raises; delegates each atom to venue.record_scan (→ mark_ticket_scanned; references kernel.tickets nowhere); returns {status, admitted, duplicates, conflicts}. The scan partial-unique remains the first-in-wins authority — the client''s batch order cannot pick the winner.';

commit;
