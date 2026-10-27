-- ============================================================================
-- 20261027000000_e76_door_operator_binding.sql — registry 187 / pgTAP 257 (B writes, A reviews).
-- Revision 2026-10-27 after A's CHANGES_REQUESTED review of #171 (N1, N2, N3, N4/N6, N7, N9).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Adds ONE zero-grant definer helper,
-- venue.assert_session_operator(uuid), and re-creates THIRTEEN door write/read gates body-only
-- with ONE marked block each: the E-76 operator binding ("the venue's CURRENT operator org = the
-- event's org"). kernel.has_venue_role (080) keys on the venue as a PLACE, so a venue role granted
-- under a former operator — or the new operator's staff on a former operator's event — reached
-- admission, comp issuance, manifest episodes and door setup (D finding 2026-10-26, 230 F14;
-- B verdict limit L5).
--
-- ── WHAT A'S REVIEW CORRECTED, AND IT MATTERS ───────────────────────────────────────────────
-- The first revision claimed venue.issue_comp, venue.open_door_manifest and
-- venue.close_door_manifest already carried the conjunct. THEY DO NOT: issue_comp has only
-- has_venue_role(venue_manager); the two manifest functions have has_venue_role OR
-- has_org_role(event org) OR is_platform. A proved the consequence with probes — the NEW
-- operator's manager minted a comp atom on the FORMER operator's event and opened/closed its
-- manifest. That claim came from counting keyword hits instead of reading the bodies. All three
-- are gates here now, and so is venue.mint_door_session (N3): a PIN minted before an operator
-- change otherwise keeps minting door sessions afterwards.
--
-- ── THE THIRTEEN GATES ───────────────────────────────────────────────────────────────────────
-- venue.record_scan, venue.reconcile_offline_scans (108) · venue.validate_ticket_online,
-- venue.revoke_door_pin (session = the PIN's), venue.allocate_comp, venue.check_in_guest_entry,
-- venue.close_door_manifest, venue.issue_comp (session = the allocation's) (086) ·
-- venue.create_door_pin, venue.mint_door_session (107) · venue.get_door_manifest (113) ·
-- venue.sync_scan_device_manifest (125) · venue.open_door_manifest (106).
-- NOT gated (venue-level, no session to bind): venue.register_scan_device,
-- venue.set_scan_device_status — a device matters only once a PIN (now gated) binds it to a
-- session. The rest of the family (create/upsert/remove_guest_entry, revoke_door_session,
-- get_live_device_count, preview_door_open_impact, and a PIN-lifetime cap) is registry 191.
--
-- ── TWO GATES NEEDED MORE THAN A HELPER CALL ────────────────────────────────────────────────
-- * venue.check_in_guest_entry (N1): p_session_id was accepted and NEVER used, so the gate could
--   be aimed at a session the caller operates while the write landed on an entry belonging to a
--   different one, and a legitimate caller could be refused for passing the wrong one. The
--   ENTRY's own guest_list.event_session_id is now resolved and is the authority for the operator
--   gate; a disagreeing p_session_id is refused `precondition_failed: session_mismatch`, AFTER
--   authority so it cannot be used as an oracle. Both directions are pinned in 257.
-- * venue.mint_door_session (N3): §9.6 keeps ONE opaque failure class for every mint failure, so
--   the helper's 42501 is translated into door_session_invalid rather than escaping as a second,
--   distinguishable error. The block sits AFTER the PIN match, so a wrong-operator caller must
--   already hold a valid PIN and learns nothing from the timing either.
--
-- ── TODAY'S EXPOSURE IS LOWER THAN THE GAP ──────────────────────────────────────────────────
-- 078:688-705 added the operatorship patch, but the LATEST body — 093's catalog.update_venue —
-- REFUSES an `org_id` patch with `precondition_failed: operatorship_transfer_frozen` (Decision C:
-- transfer suspended pending an atomic re-scoping verb). So no RPC can re-operate a venue right
-- now, and the reachable cases are a role row that OUTLIVES an out-of-band change and any future
-- re-scoping verb. 187 must land BEFORE that verb ships and (A, 2026-10-26) before production
-- exposure of the door-path callers. The gate is correct either way: it binds authority to the
-- CURRENT operator at call time.
--
-- Contracts unchanged: same signatures, same grants, same success shapes; only new 42501 refusals
-- (identical text to the role gate — no oracle), plus check_in_guest_entry's argument check. The
-- PUBLIC Gate-2 census is untouched (the helper is venue.*); venue census +1, carried in the pins
-- this package moves on top of D's 160/162/163 values (venue 96 -> 97, five-schema 317 -> 318).
-- Order: after D's 162/163/182 and after 183 (20261026210000); production order 125 -> 183 -> 187.
-- Discipline (as 183/190): per-gate md5 PRE-FLIGHT accepting predecessor-or-own, per-gate
-- POST-APPLY self-check, rollback restoring the thirteen bodies and dropping the helper under the
-- inverse guards plus an outside-caller guard (N9); replay-safe.
-- ============================================================================
begin;

-- ── PRE-FLIGHT (stacking guard): each gate must be its predecessor body (first apply) or this
-- migration's body (idempotent re-apply); anything else refuses.
do $pf$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.record_scan(uuid,uuid,uuid,jsonb,text)', 'fa48a67b83893e1cf4c0cbd4764a5620', '68144a168878e72c3a3888113cf4a3b8'),
    ('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)', '945af8d6446bbceb637e0e3de6499fc6', 'c18f03d7cee504f4bafe42a8875e58ec'),
    ('venue.validate_ticket_online(uuid,uuid)', 'd595ee4ab152c2a0c30ff0e0c19a8169', 'c5085c53eda7abf45c1a64233fe0fbe7'),
    ('venue.revoke_door_pin(uuid,text)', '498027d95150b8f57dd17676aff49116', '68e9e9067518d48b513dd7f1dfd88af6'),
    ('venue.allocate_comp(uuid,uuid,integer,text,text)', '8e4d779f1a4cc8158349e20b7b8bc603', '73ad103d04ce30dbf7d7238ade284a26'),
    ('venue.check_in_guest_entry(uuid,uuid,text,text)', '825c03467db92f092491ea54e71b88eb', '7b7420c1369be9ccf8d1961d84f6e2f8'),
    ('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)', '9f5ed2d7ca6eba24ef576bdcf81a577c', '37fe461eb19b259ae382fc12a26ccadc'),
    ('venue.get_door_manifest(uuid,integer)', '7c38de6f4243eb37c5b746bfbc962681', 'e195700a966a3a741b2bee53bfcf940d'),
    ('venue.sync_scan_device_manifest(uuid,uuid,integer)', '6beca3168e76bb566e456b6abd467197', 'f9d3e5279ce25534028fb1672d5d7a10'),
    ('venue.issue_comp(uuid,uuid,integer,text)', '9f7a8779b0d17f181074e3ea4b9b0008', 'be92e6ecfd92c08dad8247fffdfa1b0a'),
    ('venue.open_door_manifest(uuid,text,text)', 'd9938c21ca00fedfb0433b1094a7dddf', '9ee7766268a87b51a745666e30d290c7'),
    ('venue.close_door_manifest(uuid,text,text)', '47f556b2a6128c3eb70669d170d83629', '66d4257dbd08fa56dd1c0526a6b0903f'),
    ('venue.mint_door_session(uuid,uuid,uuid,text,text)', 'ad575d726072fb506d8a0d4dcb5b0be0', 'a22d681804b2e494df99b73a75e50f58')
  ) as t(fn, md5_a, md5_b) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 not in (r.md5_a, r.md5_b) then
      raise exception 'precondition_failed: 187 refuses to overwrite an unexpected % body (md5 %) — re-examine the migration order', r.fn, v_md5;
    end if;
  end loop;
end $pf$;

-- ── 187 BLOCK HELPER — the one place E-76 is reasoned about for the door plane
create or replace function venue.assert_session_operator(p_session_id uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
declare v_event_org uuid; v_venue_org uuid;
begin
  select e.org_id, v.org_id into v_event_org, v_venue_org
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
    left join catalog.venue v on v.venue_id = e.venue_id
   where s.session_id = p_session_id;
  -- an unknown session, a venue-less event and a venue whose CURRENT operator is not the
  -- event's org all refuse IDENTICALLY to a missing venue role (E-76; CRM §4.2(5) no oracle).
  if v_event_org is null or v_venue_org is null or v_venue_org <> v_event_org then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
end;
$$;
comment on function venue.assert_session_operator(uuid) is
  '187 (E-76 on the door plane): refuses (42501, identical to a missing venue role) unless the session''s event is operated by the venue''s CURRENT operator org (catalog.venue.org_id = catalog.event.org_id). Called by the thirteen door write/read gates right after their authority gate; venue.mint_door_session translates the refusal into its own opaque door_session_invalid (§9.6). Zero client grant.';
revoke all on function venue.assert_session_operator(uuid) from public, anon, authenticated, service_role;
-- ── 187 BLOCK HELPER END

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
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  return venue._record_scan_core(p_atom_id, p_session_id, p_actor_device_id, auth.uid(), p_scan_meta, p_command_key);
end;
$$;

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
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  return venue._reconcile_core(p_session_id, p_actor_device_id, auth.uid(), p_batch, p_command_key);
end;
$$;

create or replace function venue.validate_ticket_online(p_atom_id uuid, p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid; v_t kernel.tickets%rowtype;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  select * into v_t from kernel.tickets where ticket_atom_id = p_atom_id and event_session_id = p_session_id;
  if not found then return jsonb_build_object('status','not_found'); end if;
  return jsonb_build_object('status','ok','ticket_state', v_t.state, 'resale_state', v_t.resale_state,
    'signing_key_id', v_t.signing_key_id, 'credential_version', v_t.credential_version,
    'admissible', (v_t.state = 'active' and v_t.resale_state = 'none'
                   and not kernel.is_transfer_frozen(p_atom_id)));
end;
$$;

create or replace function venue.revoke_door_pin(p_pin_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.door_pin%rowtype;
begin
  select * into v_row from venue.door_pin where pin_id = p_pin_id for update;
  if not found then raise exception 'not_found: pin %', p_pin_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(v_row.event_session_id);
  -- ── 187 BLOCK END
  update venue.door_pin set status = 'revoked', updated_at = now() where pin_id = p_pin_id;
  -- RV-1: every door session minted from this pin dies with it, in the same txn.
  update venue.door_session set status = 'revoked', revoked_at = now(), revoked_reason = 'pin_revoked'
   where pin_id = p_pin_id and status = 'active';
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.pin_revoke', 'door_pin', p_pin_id, 'revoked');
  return jsonb_build_object('status','ok','pin_id', p_pin_id);
end;
$$;

create or replace function venue.allocate_comp(
  p_session_id uuid, p_batch_id uuid, p_quantity integer, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_id uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  if p_quantity is null or p_quantity <= 0 then raise exception 'precondition_failed: bad_quantity'; end if;
  insert into venue.comp_allocation (event_session_id, batch_id, quantity, granted_by)
  values (p_session_id, p_batch_id, p_quantity, auth.uid()) returning id into v_id;
  return jsonb_build_object('status','ok','comp_allocation_id', v_id);
end;
$$;

create or replace function venue.check_in_guest_entry(p_entry_id uuid, p_session_id uuid, p_outcome text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_entry_session uuid;   -- 187 N1: the entry's own session
begin
  if p_outcome not in ('arrived','no_show') then raise exception 'invalid_input: bad outcome'; end if;
  -- ── 187 BLOCK N1 — resolve the ENTRY's own session as well as its venue: p_session_id was
  -- accepted and never used, so the operator gate could be aimed at a session the caller operates
  -- while the write landed on an entry belonging to a different one (and a legitimate caller could
  -- be refused for passing the wrong one). The entry's session is now the authority.
  select ev.venue_id, gl.event_session_id into v_venue, v_entry_session
    from venue.guest_entry ge
   join venue.guest_list gl on gl.id = ge.guest_list_id
   join catalog.event_session es on es.session_id=gl.event_session_id
   join catalog.event ev on ev.event_id=es.event_id where ge.id = p_entry_id;
  -- ── 187 BLOCK N1 END
  if v_venue is null then raise exception 'not_found: entry %', p_entry_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office','venue_scanner']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(v_entry_session);
  -- ── 187 BLOCK END
  -- ── 187 BLOCK N1b — the caller's p_session_id must agree with the entry's own session. Checked
  -- AFTER authority and the operator gate, so an unauthorized caller cannot use it as an oracle.
  if p_session_id is not null and p_session_id <> v_entry_session then
    raise exception 'precondition_failed: session_mismatch';
  end if;
  -- ── 187 BLOCK N1b END
  update venue.guest_entry set status = p_outcome,
         checked_in_at = case when p_outcome='arrived' then now() else checked_in_at end, updated_at = now()
   where id = p_entry_id;
  return jsonb_build_object('status','ok','guest_entry_id', p_entry_id, 'outcome', p_outcome);
end;
$$;

create or replace function venue.create_door_pin(
  p_venue_id uuid, p_session_id uuid, p_label text, p_pin_plain text, p_expires_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_pin_id uuid; v_ok boolean;
begin
  -- authz: venue_manager of THIS venue.
  if not kernel.has_venue_role(p_venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  -- PIN safety envelope (NOT a frozen digit rule): reject empty/whitespace-only
  -- and oversized before the KDF. octet_length keeps multibyte under bcrypt's 72.
  if p_pin_plain is null or btrim(p_pin_plain) = '' then
    raise exception 'invalid_input: pin must be non-empty';
  end if;
  if octet_length(p_pin_plain) < 1 or octet_length(p_pin_plain) > 64 then
    raise exception 'invalid_input: pin must be 1-64 bytes';
  end if;
  if p_expires_at is null or p_expires_at <= now() then
    raise exception 'invalid_input: expires_at must be in the future';
  end if;
  -- the session must belong to THIS venue (a venue_manager of V cannot mint a PIN
  -- for another venue's session by naming V as venue_id + a foreign session_id).
  select exists (select 1 from catalog.event_session es join catalog.event ev on ev.event_id = es.event_id
                  where es.session_id = p_session_id and ev.venue_id = p_venue_id) into v_ok;
  if not v_ok then
    raise exception 'not_found: session % is not in venue %', p_session_id, p_venue_id using errcode = 'P0002';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END

  insert into venue.door_pin (venue_id, event_session_id, label, pin_hash, status, expires_at)
  values (p_venue_id, p_session_id, coalesce(p_label,'door'),
          extensions.crypt(p_pin_plain, extensions.gen_salt('bf', 12)), 'active', p_expires_at)
  returning pin_id into v_pin_id;

  -- audit WITHOUT the PIN or the hash (C9): only the non-secret selector + label.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.pin_create', 'door_pin', v_pin_id, coalesce(p_label,'door'));

  -- NEVER return the hash. Only the non-secret pin_id.
  return jsonb_build_object('status','ok','pin_id', v_pin_id, 'expires_at', p_expires_at);
end;
$$;

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
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  return venue._get_door_manifest_core(p_session_id, p_since_delta_seq);
end;
$$;

create or replace function venue.sync_scan_device_manifest(p_device_id uuid, p_session_id uuid, p_known_manifest_version integer)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.scan_device%rowtype; v_res jsonb;
begin
  select * into v_row from venue.scan_device where device_id = p_device_id for update;
  if not found then raise exception 'not_found: device %', p_device_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  -- 125: ONE read — the M2 contract read (112/113: status='open' AND not_after > now();
  -- an expired-but-open episode is open:false). The session-venue role gate inside
  -- get_door_manifest is evaluated here exactly as 086 evaluated it on return.
  -- FAIL-SAFE full sync preserved: p_known_manifest_version is the per-session
  -- EPISODE counter, NOT a delta-seq cursor, so the complete manifest is returned.
  v_res := venue.get_door_manifest(p_session_id, 0);
  -- bind the device ONLY to the episode the contract reports open, and to exactly
  -- the manifest it returned — never to a row the read refuses.
  if coalesce((v_res ->> 'open')::boolean, false) then
    update venue.scan_device
       set manifest_version = (v_res ->> 'manifest_version')::integer,
           manifest_id      = (v_res ->> 'manifest_id')::uuid,
           last_sync_at     = now(), updated_at = now()
     where device_id = p_device_id;
  end if;
  return v_res;
end;
$$;

create or replace function venue.issue_comp(
  p_comp_allocation_id uuid, p_grantee uuid, p_quantity integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_alloc venue.comp_allocation%rowtype; v_venue uuid; v_batch venue.inventory_batch%rowtype;
        v_key uuid; v_sess catalog.event_session%rowtype; v_res jsonb;
begin
  select * into v_alloc from venue.comp_allocation where id = p_comp_allocation_id for update;
  if not found then raise exception 'not_found: comp allocation %', p_comp_allocation_id using errcode = 'P0002'; end if;
  select * into v_sess from catalog.event_session where session_id = v_alloc.event_session_id;
  select ev.venue_id into v_venue from catalog.event ev where ev.event_id = v_sess.event_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(v_alloc.event_session_id);
  -- ── 187 BLOCK END
  if v_alloc.status <> 'allocated' then
    return jsonb_build_object('status','noop_replay','comp_allocation_id', p_comp_allocation_id);
  end if;
  -- the allocate->issue two-step caps issuance at the AUTHORIZED amount: issuing
  -- more than was allocated diverges authorized-vs-issued comp accounting.
  if coalesce(p_quantity, v_alloc.quantity) > v_alloc.quantity then
    raise exception 'precondition_failed: issue quantity % exceeds allocation %', coalesce(p_quantity, v_alloc.quantity), v_alloc.quantity;
  end if;
  select * into v_batch from venue.inventory_batch where batch_id = v_alloc.batch_id;
  -- resolve the active signing key for the event scope (mint precondition)
  select k.key_id into v_key from kernel.signing_key k
   where k.status='active' and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and ((k.scope='per_event' and k.event_id = v_sess.event_id)
          or (k.scope='per_venue' and k.venue_id = v_venue) or (k.scope='global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end limit 1;
  if v_key is null then raise exception 'precondition_failed: no_active_signing_key'; end if;
  -- mint via the kernel engine (cause=comp); it decrements the comp batch (sold += q).
  v_res := kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', v_alloc.event_session_id, 'org_id', (select ev.org_id from catalog.event ev where ev.event_id=v_sess.event_id),
    'ticket_type_id', v_batch.ticket_type_id, 'batch_id', v_alloc.batch_id,
    'owner_id', coalesce(p_grantee,'00000000-0000-0000-0000-0000000000f1'), 'quantity', coalesce(p_quantity, v_alloc.quantity),
    'cause','comp','cause_ref', p_comp_allocation_id, 'signing_key_id', v_key), p_command_key);
  update venue.comp_allocation set status = 'issued', granted_to_identity = p_grantee, updated_at = now()
   where id = p_comp_allocation_id;
  return jsonb_build_object('status','ok','comp_allocation_id', p_comp_allocation_id) || v_res;
end;
$$;

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
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
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

create or replace function venue.close_door_manifest(
  p_session_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_m venue.door_manifest%rowtype; v_venue uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.has_org_role((select ev.org_id from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id where es.session_id=p_session_id),
               array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open' for update;
  if not found then
    return jsonb_build_object('status','noop_replay');   -- no open episode is never an error
  end if;
  update venue.door_manifest set status = 'closed', closed_at = now(),
         closed_by = auth.uid(), close_reason = p_reason_code
   where manifest_id = v_m.manifest_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'session.door_manifest_close', 'event_session', p_session_id, p_reason_code);
  perform notify.emit_event('DoorManifestClosed', 'event_session', p_session_id,
          'door_close:' || v_m.manifest_id::text, jsonb_build_object('manifest_id', v_m.manifest_id));
  return jsonb_build_object('status','ok','manifest_id', v_m.manifest_id);
end;
$$;

create or replace function venue.mint_door_session(
  p_venue_id uuid, p_session_id uuid, p_device_id uuid, p_pin_plain text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_dev      venue.scan_device%rowtype;
  v_pin      venue.door_pin%rowtype;
  v_match    venue.door_pin%rowtype;
  v_sess_ok  boolean;
  v_secret   text;
  v_hash     text;
  v_ttl      interval;
  v_absmax   interval;
  v_grace    interval;
  v_ends     timestamptz;
  v_expires  timestamptz;
  v_dsid     uuid;
begin
  -- Basic shape before any DB work (never leak which check failed).
  if p_pin_plain is null or btrim(p_pin_plain) = '' or octet_length(p_pin_plain) > 64 then
    raise exception 'door_session_invalid' using errcode = '42501';
  end if;

  -- Resolve the device: must exist, be active, and belong to THIS venue. FOR
  -- UPDATE serializes concurrent mints/re-mints for the SAME device, so the
  -- revoke-prior-then-insert below cannot race the door_session_active_device_uq
  -- partial unique (two concurrent re-mints would otherwise both revoke then one
  -- insert would trip the unique). A first-ever mint locks nothing extra (no row).
  select * into v_dev from venue.scan_device
   where device_id = p_device_id and venue_id = p_venue_id and status = 'active'
   for update;
  -- The (venue, session) pairing must be real.
  select exists (select 1 from catalog.event_session es join catalog.event ev on ev.event_id = es.event_id
                  where es.session_id = p_session_id and ev.venue_id = p_venue_id) into v_sess_ok;

  -- Verify the PIN against every ACTIVE, unexpired PIN for (venue, session).
  -- crypt(presented, stored)=stored is bcrypt's constant-time compare. Loop so a
  -- venue may rotate PINs (multiple active) without a mint outage.
  v_match := null;
  if v_dev.device_id is not null and v_sess_ok then
    for v_pin in
      select * from venue.door_pin
       where venue_id = p_venue_id and event_session_id = p_session_id
         and status = 'active' and expires_at > now()
    loop
      if v_pin.pin_hash = extensions.crypt(p_pin_plain, v_pin.pin_hash) then
        v_match := v_pin;
        exit;
      end if;
    end loop;
  end if;

  -- OPAQUE failure for device/session/PIN — one error class, no oracle. Before
  -- raising on a miss (unknown device / session not in venue / no active PIN /
  -- wrong PIN), spend ONE bcrypt so a miss costs ~the same as a single-PIN verify
  -- — closing the armed-vs-unarmed timing side channel (the crypt loop above
  -- short-circuits when there is no candidate). p_pin_plain is already validated
  -- non-null and <=64 bytes above.
  if v_match.pin_id is null then
    perform extensions.crypt(p_pin_plain, extensions.gen_salt('bf', 12));
    raise exception 'door_session_invalid' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  -- §9.6 keeps ONE opaque class for every mint failure, so the helper's 42501 is
  -- translated rather than escaping as a second, distinguishable error. Placed AFTER the
  -- PIN match, so a wrong-operator caller must already hold a valid PIN and learns nothing
  -- new from the timing either.
  begin
    perform venue.assert_session_operator(p_session_id);
  exception when insufficient_privilege then
    raise exception 'door_session_invalid' using errcode = '42501';
  end;
  -- ── 187 BLOCK END

  -- Server-max TTL = LEAST(now()+session_ttl, absolute_max, pin.expires_at,
  -- session.ends_at + grace). Config keys may be null (dual-controlled/parked)
  -- -> safe fallbacks, same discipline as open_door_manifest's manifest_ttl.
  select (c.value #>> '{}')::interval into v_ttl    from catalog.platform_config c where c.key='door.session_ttl_interval'          order by c.version desc limit 1;
  select (c.value #>> '{}')::interval into v_absmax from catalog.platform_config c where c.key='door.session_absolute_max_interval' order by c.version desc limit 1;
  select (c.value #>> '{}')::interval into v_grace  from catalog.platform_config c where c.key='door.session_post_session_grace'    order by c.version desc limit 1;
  select es.ends_at into v_ends from catalog.event_session es where es.session_id = p_session_id;
  v_ttl    := coalesce(v_ttl, interval '8 hours');
  v_absmax := coalesce(v_absmax, interval '16 hours');
  v_grace  := coalesce(v_grace, interval '2 hours');
  v_expires := least(now() + v_ttl, now() + v_absmax, v_match.expires_at);
  if v_ends is not null then
    v_expires := least(v_expires, v_ends + v_grace);
  end if;
  if v_expires <= now() then
    -- the pin/session window has already closed — same opaque class.
    raise exception 'door_session_invalid' using errcode = '42501';
  end if;

  -- Re-mint replaces any prior active session for this (device, session) so the
  -- door_session_active_device_uq partial-unique never trips (idempotent /refresh).
  update venue.door_session set status = 'revoked', revoked_at = now(), revoked_reason = 'reminted'
   where device_id = p_device_id and event_session_id = p_session_id and status = 'active';

  -- 256-bit secret (two uuids); store ONLY md5('door_session:'||secret) — the
  -- exact hash kernel.assert_door_session recomputes. The raw secret is returned
  -- ONCE and never stored.
  v_secret := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  v_hash   := md5('door_session:' || v_secret);

  insert into venue.door_session (token_hash, device_id, event_session_id, venue_id, pin_id, expires_at)
  values (v_hash, p_device_id, p_session_id, p_venue_id, v_match.pin_id, v_expires)
  returning door_session_id into v_dsid;

  -- Return the selector + the one-time secret + the expiry. NEVER the PIN/hash.
  return jsonb_build_object('status','ok','door_session_id', v_dsid, 'secret', v_secret, 'expires_at', v_expires);
end;
$$;

-- ── POST-APPLY SELF-CHECK: every gate body must be exactly this migration's body.
do $pc$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.record_scan(uuid,uuid,uuid,jsonb,text)', '68144a168878e72c3a3888113cf4a3b8'),
    ('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)', 'c18f03d7cee504f4bafe42a8875e58ec'),
    ('venue.validate_ticket_online(uuid,uuid)', 'c5085c53eda7abf45c1a64233fe0fbe7'),
    ('venue.revoke_door_pin(uuid,text)', '68e9e9067518d48b513dd7f1dfd88af6'),
    ('venue.allocate_comp(uuid,uuid,integer,text,text)', '73ad103d04ce30dbf7d7238ade284a26'),
    ('venue.check_in_guest_entry(uuid,uuid,text,text)', '7b7420c1369be9ccf8d1961d84f6e2f8'),
    ('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)', '37fe461eb19b259ae382fc12a26ccadc'),
    ('venue.get_door_manifest(uuid,integer)', 'e195700a966a3a741b2bee53bfcf940d'),
    ('venue.sync_scan_device_manifest(uuid,uuid,integer)', 'f9d3e5279ce25534028fb1672d5d7a10'),
    ('venue.issue_comp(uuid,uuid,integer,text)', 'be92e6ecfd92c08dad8247fffdfa1b0a'),
    ('venue.open_door_manifest(uuid,text,text)', '9ee7766268a87b51a745666e30d290c7'),
    ('venue.close_door_manifest(uuid,text,text)', '66d4257dbd08fa56dd1c0526a6b0903f'),
    ('venue.mint_door_session(uuid,uuid,uuid,text,text)', 'a22d681804b2e494df99b73a75e50f58')
  ) as t(fn, md5_x) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 <> r.md5_x then
      raise exception 'precondition_failed: 187 post-apply self-check — % body (md5 %) is not the expected body; this file was modified', r.fn, v_md5;
    end if;
  end loop;
end $pc$;

commit;
