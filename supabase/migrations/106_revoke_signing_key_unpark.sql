-- ============================================================================
-- 106_revoke_signing_key_unpark.sql — PFA-18B: un-park kernel.revoke_signing_key
-- under SINGLE platform_admin + aal2 control (emergency tightening), wiring the
-- already-built §5.6 force-close mechanism (kernel.force_close_key_manifests,
-- migration 105) and closing the "open_door_manifest opens on revoked trust"
-- residual the door-plane readiness report identified.
--
-- WHAT THIS MIGRATION IS. DARK / unapplied / undeployed. Production is at ledger
-- 107 (through 092); 093-105 are authored, NOT applied. 093-105 are IMMUTABLE —
-- this migration re-creates TWO functions via CREATE OR REPLACE (kernel.
-- revoke_signing_key, parked in 086:714-721; venue.open_door_manifest,
-- 086:728-808). No new object, no signature change, no grant change (both are
-- already granted — revoke to authenticated, open to authenticated), no
-- public-schema object, Gate-2 untouched, function census UNCHANGED (both
-- re-created). Next migration after 105.
--
-- ── OWNER DIRECTION (PFA-18B, OWNER DIRECTION RECEIVED — this train) ─────────
-- Revocation REDUCES authority: it activates no key, rotates into no new trust
-- root, expands no capability. It is therefore permitted under SINGLE
-- platform_admin control (an emergency tightening), asymmetric with PROVISION
-- and ROTATE, which STAY parked / dual-control-gated (PFA-18A). This migration
-- un-parks ONLY the revoke leg. provision_signing_key / rotate_signing_key
-- (083:375-393) are untouched and still raise dual_control_unavailable.
--
-- ── REQUIRED REVOKE BEHAVIOR (train §5) ─────────────────────────────────────
--  1. platform_admin only + aal2 (the 085/096 step-up idiom, verbatim).
--  2. explicit reason_code (validated to the audit charset).
--  3. target key locked FOR UPDATE.
--  4. legal forward-only transition (guard_signing_key_immutable: revoked is
--     terminal; active|rotating -> revoked is legal).
--  5. status := 'revoked' (forward-only, terminal). The signer refuses on
--     status<>'active' (get_ticket_signing_context 103:162) and the M1 keyring
--     distributes status, so an offline verifier refuses the revoked key too.
--     not_after is deliberately NOT rewritten (revocation is not expiry, and
--     not_after=now() would break signing_key_window_ck for a key whose
--     not_before is the same instant).
--  6. audit (kernel.admin_audit signing_key.revoke).
--  7. every in-scope OPEN door episode force-closed via
--     kernel.force_close_key_manifests (105) -> DoorManifestInvalidated (#44,
--     REQ/durable) per episode.
--  8. no NEW manifest may open relying on the revoked key (the open_door_manifest
--     re-create below + the in-scope session lock here = the race close).
--  9. the signer already refuses a non-active / out-of-window key
--     (get_ticket_signing_context 103:162) and resolves ONLY the atom's pinned
--     key with NO fallback (103:137-160) — no change needed, re-proven in test.
-- 10. deterministic result {status, key_id, key_status, manifests_closed}.
--
-- ── THE OPEN/REVOKE RACE (report residual, closed here) ─────────────────────
-- open_door_manifest snapshots each atom's pinned signing_key_id. If a NEW
-- episode opened AFTER a revoke commit for a session whose atoms are pinned to
-- the revoked key, that episode would carry revoked trust. Close, on a SINGLE
-- lock order (catalog.event_session = rank 1, no key-row lock in open):
--   * revoke locks EVERY in-scope non-terminal event_session FOR UPDATE (rank 1,
--     ascending session_id) BEFORE it flips the key and force-closes. A
--     concurrent open holds / then waits on the SAME session row.
--       - open-before-revoke: open commits on the still-active key; revoke then
--         acquires the session lock and its force-close (105, which re-scans
--         open episodes) closes the just-opened episode + emits #44.
--       - revoke-before-open: revoke commits (key='revoked'); open then acquires
--         the lock, re-reads, and its NEW revoked-key precondition refuses.
--   * open_door_manifest gains a precondition: refuse to open when ANY atom of
--     the session is pinned to a revoked signing key. Under the rank-1 session
--     lock this reads the committed key state.
-- Both revoke and cancel_event acquire sessions in ascending session_id order,
-- so no deadlock (revoke never locks the event row cancel_event locks first).
-- The genuinely-disconnected-scanner residual (a device that never reconnects
-- holds its own downloaded not_after) is unchanged and bounded by
-- door.manifest_ttl_interval — the honest offline residual (PFA-PT-9 item 4).
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — kernel.revoke_signing_key: the real body (PFA-18B). Signature frozen
-- (086:714-715 / RPC §20.7.5): (p_key_id, p_reason_code, p_ack_live_credentials,
-- p_command_key). Granted to authenticated already (086 v_auth); platform_admin
-- is enforced in-body. NOT service_role.
-- ============================================================================
create or replace function kernel.revoke_signing_key(
  p_key_id uuid, p_reason_code text, p_ack_live_credentials integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_aal    text;
  v_k      kernel.signing_key%rowtype;
  v_live   integer;
  v_closed integer;
begin
  -- (1) authz: a platform_admin, on an aal2 (step-up) session. Emergency
  -- tightening under SINGLE control (PFA-18B) — no dual-control approval row.
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin only (PFA-18B: revoke is single-control emergency tightening)' using errcode = '42501';
  end if;
  -- aal2 step-up (085/096 idiom, verbatim). Absent claim => step_up_unavailable
  -- (never treated as satisfied); aal1 => step_up_required.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to revoke a signing key';
  end if;
  -- (2) explicit reason_code, constrained to the immutable-audit charset.
  if p_reason_code is null or p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;

  -- (3) lock the target key.
  select * into v_k from kernel.signing_key where key_id = p_key_id for update;
  if not found then
    raise exception 'not_found: signing_key %', p_key_id using errcode = 'P0002';
  end if;

  -- (idempotency) a revoked key is terminal: a replay is a safe no-op and does
  -- NOT re-close, re-emit or re-audit. Checked BEFORE the ack so replay never
  -- fails on a now-zero live count.
  if v_k.status = 'revoked' then
    return jsonb_build_object('status','noop_replay','key_id', p_key_id, 'key_status','revoked', 'manifests_closed', 0);
  end if;

  -- (8) serialize against a concurrent open_door_manifest: lock EVERY in-scope
  -- session FOR UPDATE (rank 1, ascending session_id) BEFORE the key flip and
  -- BEFORE the ack count. A concurrent open holds / then blocks on the SAME
  -- session row, so it either commits first (and its episode is force-closed
  -- below) or blocks until revoke commits (and then its revoked-key precondition
  -- refuses). We lock ALL in-scope sessions — NOT only non-terminal ones — so
  -- this set is a SUPERSET of what kernel.force_close_key_manifests will lock
  -- (in-scope sessions WITH an open manifest, no status filter): were we to skip
  -- a terminal session that still holds an open episode (reachable if a cancel
  -- ran between 088 and the 109 force-close trigger), force_close could later
  -- grab a lower-id session AFTER we hold a higher-id one, deadlocking with
  -- cancel_event. Locking every in-scope session ascending keeps ONE monotonic
  -- acquisition order across revoke, force_close and cancel_event. For a global
  -- key this briefly locks all sessions — acceptable for a platform-wide
  -- emergency (a global key is the bootstrap-only case).
  perform 1
    from catalog.event_session es
    join catalog.event ev on ev.event_id = es.event_id
   where (v_k.scope = 'global')
      or (v_k.scope = 'per_venue' and ev.venue_id = v_k.venue_id)
      or (v_k.scope = 'per_event' and ev.event_id = v_k.event_id)
   order by es.session_id
   for update of es;

  -- (7-pre) the "live credentials" acknowledgement = the count of OPEN in-scope
  -- door episodes that this revoke will force-close, computed UNDER the lock just
  -- taken so it is the exact set force_close will act on (advisory: enforced only
  -- when the caller supplies it; an emergency script may pass null; the
  -- grant_door_freeze_override ack pattern).
  select count(*)::int into v_live
    from catalog.event_session es
    join catalog.event ev on ev.event_id = es.event_id
    join venue.door_manifest dm on dm.session_id = es.session_id and dm.status = 'open'
   where (v_k.scope = 'global')
      or (v_k.scope = 'per_venue' and ev.venue_id = v_k.venue_id)
      or (v_k.scope = 'per_event' and ev.event_id = v_k.event_id);
  if p_ack_live_credentials is not null and p_ack_live_credentials <> v_live then
    raise exception 'precondition_failed: unacknowledged_live_credentials (ack % vs open in-scope episodes %)', p_ack_live_credentials, v_live;
  end if;

  -- (5) forward-only transition to revoked. status='revoked' is the authority:
  -- get_ticket_signing_context (103:162) refuses on status<>'active', and the M1
  -- keyring distributes status so an offline verifier refuses a revoked key too.
  -- We deliberately do NOT rewrite not_after — revocation is not expiry, and
  -- setting not_after=now() would violate signing_key_window_ck whenever
  -- not_before==now() (a fresh key revoked in the same instant). The
  -- immutability guard permits active|rotating -> revoked; revoked is terminal.
  update kernel.signing_key
     set status = 'revoked',
         updated_at = now()
   where key_id = p_key_id;

  -- (6) audit BEFORE the cascade (the revoke intent is durable even if a later
  -- required emit aborts the txn — which would also abort the revoke, correctly).
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'signing_key.revoke', 'signing_key', p_key_id, p_reason_code,
          jsonb_build_object('status', v_k.status, 'scope', v_k.scope),
          jsonb_build_object('status','revoked','ack_live_credentials', p_ack_live_credentials,'open_in_scope_episodes', v_live,'command_key', p_command_key));

  -- (7) force-close every open in-scope episode (105 mechanism): pulls each to
  -- status='closed'/close_reason='key_revoked' and emits DoorManifestInvalidated
  -- (#44, REQ/durable) per episode. Re-locks in-scope sessions-with-open-episodes
  -- (already held above -> no-op). Returns the count closed.
  v_closed := kernel.force_close_key_manifests(p_key_id, 'key_revoked');

  -- (10) deterministic result. not_after is left as-is (revocation != expiry;
  -- status='revoked' is the authority the signer and the keyring both honour).
  return jsonb_build_object('status','ok','key_id', p_key_id, 'key_status','revoked', 'manifests_closed', v_closed);
end;
$$;

comment on function kernel.revoke_signing_key(uuid,text,integer,text) is
  'PFA-18B (owner-directed, single platform_admin + aal2): revoke a signing key — an emergency tightening. Locks the key, flips status active|rotating->revoked forward-only (the signer then refuses it on status<>active; no fallback to another key for already-pinned atoms), audits, and force-closes every OPEN in-scope door episode via kernel.force_close_key_manifests (#44 DoorManifestInvalidated per episode). Serializes against open_door_manifest and cancel_event by locking all in-scope sessions FOR UPDATE (ascending, a superset of force_close''s set) before the key flip, so no new episode opens on revoked trust and the acquisition order stays monotonic (no deadlock). Idempotent: a revoked key replays as noop. provision/rotate STAY parked under PFA-18A.';

-- ============================================================================
-- PART 2 — venue.open_door_manifest: refuse opening an episode whose session
-- has atoms pinned to a REVOKED signing key. Body-only re-create of 086:728-808;
-- the ONLY change is the added revoked-key precondition (right after the role
-- gate, before the terminal-status gate). Every other line — the session lock,
-- authz, idempotency, snapshot build, freeze engage, audit, emit, the
-- unique_violation replay handler — is reproduced verbatim from 086.
-- ============================================================================
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
    -- a terminal/cancelled session cannot open a door episode
    if v_sess.status in ('cancelled','ended','completed') then
      raise exception 'precondition_failed: session_terminal (%)', v_sess.status;
    end if;
  end if;
  -- idempotency: an already-open episode returns it (state guard); command replay.
  -- This precedes the revoked-key check so a REPLAY of an already-open episode
  -- (which legitimately exists) returns noop_replay rather than refusing — the
  -- revoked-key precondition gates only a genuinely NEW open.
  if exists (select 1 from venue.door_manifest m where m.session_id = p_session_id and m.status = 'open') then
    select manifest_id into v_mid from venue.door_manifest where session_id = p_session_id and status = 'open';
    return jsonb_build_object('status','noop_replay','manifest_id', v_mid);
  end if;
  -- 106 / PFA-18B open-on-revoked-trust close: a NEW door episode must never open
  -- carrying credentials pinned to a REVOKED key. Read under the rank-1 session
  -- lock, so a committed revoke (which locked this session first) is visible.
  -- Rotate to a fresh active key before reopening. (An empty session — no atoms
  -- yet — passes; there is nothing to admit on revoked trust.)
  if exists (select 1 from kernel.tickets t
              join kernel.signing_key k on k.key_id = t.signing_key_id
              where t.event_session_id = p_session_id and k.status = 'revoked') then
    raise exception 'precondition_failed: signing_key_revoked — the session has atoms pinned to a revoked signing key; rotate to an active key before reopening the door';
  end if;

  select (c.value #>> '{}')::interval into v_ttl from catalog.platform_config c
   where c.key = 'door.manifest_ttl_interval' order by c.version desc limit 1;
  v_first := (v_sess.door_open_at is null);
  select coalesce(max(manifest_version),0)+1 into v_ver from venue.door_manifest where session_id = p_session_id;

  -- the complete base snapshot: EVERY atom of the session, EVERY state (PFA-24:
  -- signing_key_id only, no public_key, no identity).
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

  -- first open engages the door freeze (sole door_open_at write via engage_door_freeze)
  if v_first then
    perform catalog.engage_door_freeze(p_session_id, v_opened_at);
    perform market.on_door_freeze_engaged(p_session_id, v_mid);           -- 088 stub (drains market)
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
