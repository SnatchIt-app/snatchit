-- ============================================================================
-- 112_get_door_manifest_headers.sql — P1-M2-HEADER: `venue.get_door_manifest`
-- returns the manifest HEADER fields the offline predicate and both edges read
-- (`open`, `session_id`, `opened_at`, `not_after`) from the authoritative stored
-- `venue.door_manifest` row. BODY-ONLY re-create of the 086 function: same
-- signature, same authorization, same grants (preserved by create-or-replace),
-- same privacy exclusions (no public_key, no identity), same entry and delta
-- projections, same `status` strings.
--
-- WHAT THIS MIGRATION IS. LOCAL / REHEARSAL ARTIFACT — NOT DEPLOYED, NOT APPLIED
-- TO PRODUCTION. Re-creates ONE function; adds no object; census unchanged;
-- Gate-2 untouched. Next migration after 111.
--
-- ── THE DEFECT (SCANNER_VERIFIER_CONTRACT.md §7, P1-M2-HEADER) ────────────────
-- 086:843-875 returned `{status, manifest_id, manifest_version, manifest_digest,
-- max_delta_seq, entries, deltas}` and, for no episode, `{status:'no_open_episode'}`.
-- RPC §20.6.1 / door §7.5a (MP-1, BINDING) require the header to carry `open`,
-- `session_id`, `opened_at`, `not_after`: OFFLINE-VERIFY-v1's authority clause
-- (door §3.1 — "no M2, an M2 past its downloaded not_after, or an M2 for another
-- session ⇒ NO offline authority") reads `session_id` and `not_after`, and both
-- edges (`door-manifest`'s classifier, `door-session /manifest/sync`'s relay
-- consumers) key on `open`. A conforming scanner therefore had NO offline
-- authority from this RPC, and `door-manifest` mis-classified every open episode
-- as closed (returned it unsigned). Nothing here manufactures an expiry: the
-- returned `not_after`/`opened_at` are the stored, immutable row values
-- (venue.guard_door_manifest_transition forbids changing them after open).
--
-- ── CANONICAL CONFLICTS, DOCUMENTED BEFORE CHANGING ANY SEMANTICS ─────────────
-- 1. `status` for "no episode": 086 + suite 171 F5 say `no_open_episode`;
--    RPC §20.6.1 says `no_open_manifest`. KEPT `no_open_episode` (the existing,
--    compatible field; 171's reconnect-refuse assertion unchanged) and ADDED the
--    canonical `open:false` + empty `entries`/`deltas`. Consumers key on `open`;
--    both spellings are accepted by the contract (m2FromWire, the edge classifier).
-- 2. Expired-but-still-'open' episode: 086 returned it (status='open' only);
--    door §7.5 preconditions the read on "status='open' AND not_after > now()",
--    else the no-episode result. ALIGNED TO §7.5: an episode past its stored
--    `not_after` is reported `open:false` — fail closed at the source (a device
--    that already holds the older copy still refuses `manifest_expired`; nothing
--    becomes MORE permissive). The row itself is untouched (status stays 'open'
--    until a close — not_after is immutable and no expiry is written).
-- 3. `p_since_delta_seq` NULL vs non-NULL ("full snapshot" vs "deltas only",
--    §7.5): 086 always returns the entries and filters only the deltas; that
--    behaviour is PRESERVED unchanged here (it is a superset, never a narrowing).
--
-- ── NOT IN THIS MIGRATION (explicitly open) ──────────────────────────────────
-- • The door-session relay path: `has_venue_role` is caller-identity only and
--   service_role holds no EXECUTE on this function, so `door-session
--   /manifest/sync` (service_role client) cannot call it — RPC §20.6.1's
--   "service_role edge path bound to assert_door_session" needs a `_door`
--   machine RPC per 108's pattern. Recorded as P1-M2-DOOR-AUTHZ; not changed here
--   (authorization is preserved as-is).
-- • `door-manifest` signature `key_id` / M1 distribution / M1 bundle signing.
-- ============================================================================
begin;

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
  'M2 read (RPC §20.6.1 / door §7.5). 112: returns the stored header fields open/session_id/opened_at/not_after (MP1-READ-SET) alongside the unchanged 086 entry/delta projections; an episode past its stored not_after is reported open:false (door §7.5 precondition). Authorization: has_venue_role(venue,[venue_scanner,venue_manager]) — caller identity only; the service_role door path is NOT authorized here (P1-M2-DOOR-AUTHZ, open). Never public_key, never identity.';

commit;
