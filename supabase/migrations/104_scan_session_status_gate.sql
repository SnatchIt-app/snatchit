-- ============================================================================
-- 104_scan_session_status_gate.sql — close the confirmed door P0: a cancelled
-- (or completed) event session's still-active atoms are admissible, because
-- venue.record_scan never checks the session's status.
--
-- WHAT THIS MIGRATION IS. DARK / unapplied / undeployed. Body-only re-create of
-- venue.record_scan (086:1070-1109) that adds ONE precondition — the session
-- must not be in a terminal status — before it delegates to
-- kernel.mark_ticket_scanned. Replay-safe (create or replace). No new object,
-- no signature change, no grant change, no public-schema object, Gate-2
-- untouched, kernel/venue function census unchanged. Next migration after 103.
--
-- ── THE DEFECT (adversarial door finding P0-1) ──────────────────────────────
-- catalog.cancel_event (088:1602-1793) voids every atom WITH refund lineage but
-- DELIBERATELY SKIPS comp/import-mint atoms (no order item, nothing to refund),
-- with the explicit comment "the cancelled session already denies their scan"
-- (088:1607). It also sets catalog.event_session.status='cancelled' (088:1793).
-- But NOTHING denies their scan: kernel.mark_ticket_scanned (079:408-447) checks
-- only session match / state='active' / resale_state='none', and venue.
-- record_scan (086:1070-1109) checks only the native-scanning flag and the venue
-- role. So a comp/guest atom of a PUBLICLY CANCELLED event stays state='active'
-- forever and is admissible — online, and (until its manifest not_after) offline.
-- Executed reading of both functions confirms neither reads event_session.status.
--
-- ── WHY A TERMINAL-STATUS GATE, NOT status='live' ──────────────────────────
-- The frozen contract (PHASE_2_RPC_FUNCTION_CONTRACTS.md §7.5, admit-gate (1))
-- states "the session is `live` — venue.record_scan's own precondition, and the
-- only thing that stops admission." Read literally that is a status='live'
-- gate — but NOTHING in 076-103 ever writes event_session.status='live'
-- (093:781-784 records this exact fact: "the only writer of that column is
-- 088:1793, which writes 'cancelled'"; a completed-session writer does not
-- exist either). A status='live' precondition would therefore refuse 100% of
-- admissions (every session sits at its 'scheduled' default, 078:186). The
-- faithful, non-breaking reading — and the one that makes cancel_event's own
-- 088:1607 assertion TRUE — is a TERMINAL-status gate: refuse admission when the
-- session is 'cancelled' or 'completed', allow 'scheduled' and 'live'. This is
-- fail-closed on the two states that mean "this session must not admit anyone"
-- and touches nothing about the normal scheduled/live flow. The literal-'live'
-- vs terminal-status wording is reconciled for the owner in PFA-PT-9.
--
-- SCOPE OF THE FIX (what it does and does NOT close):
--   * ONLINE admission of a cancelled/completed session: CLOSED here.
--   * OFFLINE admission from an M2 manifest downloaded BEFORE the cancel: NOT
--     closed by this migration — an offline device holds a frozen snapshot and
--     this DB gate cannot reach it. That residual is bounded by the manifest
--     not_after (door.manifest_ttl_interval, seeded "12 hours") and is the same
--     class as the §5.6 revocation-force-close obligation (kernel.revoke_
--     signing_key is parked, PFA-18A) — see the report's OFFLINE section. This
--     migration deliberately does not un-park that mechanism.
--   * credential_version currency at the commit: NOT added here — the frozen
--     contract (§7.5 / §1223) places version-currency at C37 (online verify /
--     the verifier), by design; record_scan takes no version and this migration
--     does not change its signature. See the report's P0-2 discussion.
--
-- Everything else in venue.record_scan — the flag gate, the venue-role gate,
-- the mark_ticket_scanned delegation, the result mapping, the scan insert, the
-- unique_violation first-in-wins handler, the return shape — is reproduced
-- verbatim from 086:1070-1109. Diffable: strip the session-status block and the
-- two bodies are identical except the extended SELECT.
-- ============================================================================
begin;

create or replace function venue.record_scan(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_venue uuid; v_session_status text; v_res jsonb; v_result text; v_scan_id uuid;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  -- Resolve the venue AND the session status in one read. X-12 restrictive: an
  -- unknown/absent session (null status, from a vanished session row) is refused
  -- too — a scan whose session cannot be established is not an admissible scan.
  select ev.venue_id, es.status into v_venue, v_session_status
    from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- 104 / door P0-1 (frozen contract §7.5 admit-gate 1). A terminal session must
  -- not admit: 'cancelled' (cancel_event 088:1793 — the case its own 088:1607
  -- comment assumed was already denied here) and 'completed' both mean the door
  -- is closed. 'scheduled'/'live' pass. A null status (unknown session) fails
  -- closed.
  if v_session_status is null or v_session_status in ('cancelled','completed') then
    raise exception 'precondition_failed: session_not_admitting (status=%)', coalesce(v_session_status,'missing');
  end if;
  -- the lifecycle transition (single-writer choke point). A repeat/terminal atom
  -- raises inside mark_ticket_scanned → mapped to a 'duplicate'/'invalid' scan row.
  begin
    v_res := kernel.mark_ticket_scanned(p_atom_id, p_session_id, coalesce(p_scan_meta, '{}'::jsonb));
    v_result := 'admitted';
  exception when others then
    v_result := case when sqlerrm like '%not_active%' or sqlerrm like '%wrong_session%' then 'invalid'
                     when sqlerrm like '%listed_locked%' then 'invalid'
                     else 'invalid' end;
  end;
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, auth.uid(), v_result,
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result);
exception when unique_violation then
  -- C41 first-in-wins: a second admitted inbound scan is a duplicate.
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, auth.uid(), 'duplicate',
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate');
end;
$$;

comment on function venue.record_scan(uuid,uuid,uuid,jsonb,text) is
  'Admission ledger write (086), now gated on session status (104 / door P0-1 / contract §7.5): refuses session_not_admitting when the event_session is cancelled/completed (or unknown). Delegates the atom lifecycle to kernel.mark_ticket_scanned under the atom lock; first-in-wins via the scan partial-unique. credential_version currency is enforced at C37/the verifier, not here (frozen §7.5/§1223).';

commit;
