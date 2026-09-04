-- ============================================================================
-- 109_terminal_session_manifest_forceclose.sql — PFA-PT-9 item 2: when an event
-- session becomes terminal (cancelled/completed), force-close its open door
-- episode and emit DoorManifestInvalidated (#44). Wired as a TRIGGER on
-- catalog.event_session.status rather than by rewriting catalog.cancel_event —
-- the narrowest, safest wiring (train §12): it changes ZERO money bytes, so G4/G5
-- and every refund/void path are non-regressed BY CONSTRUCTION, and it binds
-- EVERY writer of the terminal status (present and future), not just cancel_event.
--
-- WHAT THIS MIGRATION IS. DARK / unapplied / undeployed. 093-108 IMMUTABLE. This
-- migration adds ONE kernel function (session-scoped force-close), ONE catalog
-- trigger function, and ONE trigger on catalog.event_session. No public-schema
-- object, Gate-2 untouched. Census: +1 kernel fn, +1 catalog fn, +1 trigger.
-- Next migration after 108.
--
-- ── WHY A TRIGGER, NOT A cancel_event REWRITE (train §12/§13) ────────────────
-- catalog.cancel_event (088:1612-1809) is a large money function; its own
-- §7.2.1 comment (088:1607) ASSUMED "the cancelled session already denies their
-- scan" but never closed the manifest. Re-creating those ~200 money bytes just to
-- add one force-close call risks a money regression. Instead, an AFTER UPDATE OF
-- status trigger fires exactly when 088:1793 sets a session 'cancelled' (the only
-- writer of that value — confirmed by the 104 analysis) and closes the episode in
-- the SAME transaction. Money non-regression is guaranteed: no economic byte
-- changes. A future 'completed' writer is covered too; per train §13, NO fake
-- completion writer is invented here — only 'cancelled' is currently reachable,
-- and this is documented, not simulated.
--
-- ── ATOMICITY / ORDER ───────────────────────────────────────────────────────
-- The trigger runs inside cancel_event's txn, after the per-session voids/refunds
-- and the status flip, with the session row already locked (088:1636). The #44
-- emit is REQUIRED (raising) — if it cannot enqueue, the whole cancel aborts,
-- which is correct (cancel already emits required event_cancelled/refund_requested).
-- The helper re-locks the session FOR UPDATE (no-op when already held) so it is
-- also safe to call from any future path. It touches ONLY venue.door_manifest +
-- the outbox + admin_audit — never money, never another session.
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — kernel.force_close_session_manifests(p_session_id, p_reason): the
-- session-scoped sibling of kernel.force_close_key_manifests (105). Closes the
-- OPEN episode for ONE session (at most one by door_manifest_open_uq; a loop for
-- safety), emits DoorManifestClosed + DoorManifestInvalidated (#44, REQ), audits.
-- Returns the count closed. Idempotent (no open episode -> 0, no writes). ZERO
-- grant — reached only from a definer path (the terminal-status trigger) or the
-- test harness (superuser), exactly like force_close_key_manifests.
-- ============================================================================
create or replace function kernel.force_close_session_manifests(p_session_id uuid, p_reason text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_m record; v_count integer := 0;
begin
  -- rank 1: lock the session (no-op if the caller already holds it).
  perform 1 from catalog.event_session es where es.session_id = p_session_id for update;
  for v_m in
    select dm.manifest_id, dm.session_id
      from venue.door_manifest dm
     where dm.session_id = p_session_id and dm.status = 'open'
     order by dm.manifest_id
     for update
  loop
    update venue.door_manifest
       set status = 'closed', closed_at = now(), closed_by = auth.uid(),
           close_reason = p_reason
     where manifest_id = v_m.manifest_id;

    perform notify.emit_event('DoorManifestClosed', 'event_session', v_m.session_id,
              'door_close:' || v_m.manifest_id::text,
              jsonb_build_object('manifest_id', v_m.manifest_id, 'reason', p_reason));
    perform notify.emit_event_required('DoorManifestInvalidated', 'event_session', v_m.session_id,
              'door_inval:' || v_m.manifest_id::text || ':' || p_reason,
              jsonb_build_object('manifest_id', v_m.manifest_id, 'session_id', v_m.session_id,
                                 'reason', p_reason, 'invalidated_at', now()));

    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1'::uuid), 'session.force_close_manifest',
            'event_session', v_m.session_id, p_reason,
            jsonb_build_object('manifest_id', v_m.manifest_id));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
comment on function kernel.force_close_session_manifests(uuid,text) is
  'INTERNAL (zero grant): force-close the OPEN door episode of a single session (terminal-session §7.2.1), emitting DoorManifestInvalidated (#44, REQ) + a DoorManifestClosed parity event + audit. Session-scoped sibling of kernel.force_close_key_manifests (105). Called only from a definer path (the terminal-status trigger) or the test harness. Idempotent; touches only venue.door_manifest + outbox + audit — never money.';
revoke all on function kernel.force_close_session_manifests(uuid,text) from public, anon, authenticated, service_role;

-- ============================================================================
-- PART 2 — the terminal-status trigger on catalog.event_session. Fires only on a
-- real transition INTO 'cancelled'/'completed' (WHEN old.status distinct). It
-- calls the session-scoped force-close with a D3-style reason. AFTER UPDATE so
-- the status is already committed-in-txn; STATEMENT-safe as a row trigger because
-- cancel_event flips one session per iteration.
-- ============================================================================
create or replace function catalog.tg_session_terminal_force_close()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform kernel.force_close_session_manifests(
    new.session_id,
    case when new.status = 'cancelled' then 'event_cancelled' else 'session_completed' end);
  return null;   -- AFTER trigger: return value ignored
end;
$$;

-- definer-internal: the trigger fires as the table owner, so no role needs
-- EXECUTE. Revoke the default PUBLIC grant (076 discipline + catalog F1/F3 census).
revoke all on function catalog.tg_session_terminal_force_close() from public, anon, authenticated, service_role;

drop trigger if exists tg_session_terminal_force_close on catalog.event_session;
create trigger tg_session_terminal_force_close
  after update of status on catalog.event_session
  for each row
  when (new.status in ('cancelled','completed') and old.status is distinct from new.status)
  execute function catalog.tg_session_terminal_force_close();

comment on function catalog.tg_session_terminal_force_close() is
  'PFA-PT-9 item 2: on an event_session transition INTO cancelled/completed, force-close its open door episode via kernel.force_close_session_manifests (#44 DoorManifestInvalidated). Wires terminal-session invalidation without touching the cancel_event money body. Only ''cancelled'' is currently reachable (088:1793); ''completed'' is covered defensively (no writer exists yet — train §13).';

commit;
