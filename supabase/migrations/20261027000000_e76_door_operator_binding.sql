-- ============================================================================
-- 20261027000000_e76_door_operator_binding.sql — registry 187 / pgTAP 257 (B writes, A reviews).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Adds ONE zero-grant definer
-- helper, venue.assert_session_operator(uuid), and re-creates NINE door write/read
-- gates body-only with ONE marked block each: the E-76 operator binding ("the venue's
-- CURRENT operator org = the event's org"), already present on the settlement/read
-- arms (087/088/090/093/094) and on venue.issue_comp / open_door_manifest /
-- close_door_manifest, was ABSENT here: kernel.has_venue_role (080) keys on the venue
-- as a PLACE, so a venue role granted under a former operator — or the new operator's
-- staff on a former operator's event — reached admission and door setup (D finding
-- 2026-10-26, 230 F14; B verdict limit L5).
--
-- TODAY'S EXPOSURE IS LOWER THAN THE GAP (verified 2026-10-26, D's relay checked against
-- the chain): 078:688-705 added the operatorship patch, but the LATEST body — 093's
-- catalog.update_venue — REFUSES an `org_id` patch with `precondition_failed:
-- operatorship_transfer_frozen` (Decision C: transfer suspended pending an atomic
-- re-scoping verb). So no RPC can re-operate a venue right now, and the reachable cases are
-- a role row that OUTLIVES an out-of-band change and any future re-scoping verb. 187 must
-- therefore land BEFORE that verb ships, and (A, 2026-10-26) before production exposure of
-- the door-path callers — not merely before a second organization/venue. The gate below is
-- correct either way: it binds authority to the CURRENT operator at call time.
--
-- Gates (latest bodies re-created verbatim + the block): venue.record_scan (108),
-- venue.reconcile_offline_scans (108), venue.validate_ticket_online (086),
-- venue.revoke_door_pin (086; session = the PIN's), venue.allocate_comp (086),
-- venue.check_in_guest_entry (086), venue.create_door_pin (107),
-- venue.get_door_manifest (113), venue.sync_scan_device_manifest (125).
-- NOT changed (venue-level, no event to bind): venue.register_scan_device,
-- venue.set_scan_device_status — a device matters only once a PIN (now E-76 gated)
-- binds it to a session. NOT changed (machine path): mint_door_session /
-- assert_door_session / *_door RPCs authorize by the door-session token minted from a
-- PIN that create_door_pin now E-76 gates; residual = the PIN's own lifetime
-- (≤ 1 day in the fixtures; door.session_ttl 12 h) — recorded, A's call.
-- Contracts unchanged: same signatures, same grants, same success shapes; only a new
-- 42501 refusal (identical text to the role gate — no oracle). Gate-2 census: the
-- public function census is untouched (the helper is venue.*); venue census +1.
-- Order: after 183 (20261026210000) and after D's 162/163 (their wrappers call
-- record_scan / validate_ticket_online and keep their contracts). Required before any
-- second organization/venue (G08); not a Nov 30 blocker.
-- BLOCK PLACEMENT. Each gate's block sits immediately AFTER its existing venue-role gate,
-- so the observable check ORDER is unchanged. ONE exception: venue.create_door_pin's role
-- gate is on p_venue_id and it owns a session-in-venue check that must keep answering
-- first ('not_found: session % is not in venue %', 107:145) — 173 P5 pins that — so its
-- block follows THAT check. 187 therefore only ever ADDS a refusal; it never changes
-- which refusal an already-refused call receives.
--
-- CENSUS PINS. The helper is the first function this lane adds, so the frozen counters
-- move by exactly one: venue 87 -> 88 and the five-schema routine census 305 -> 306. Ten
-- pins across seven suites are bumped in this package, each with a dated derivation line
-- (145 A4, 144 A15, 148 B2/B5, 157 A46, 156 A20, 179 A8/A9, 180 A5/A6). The PUBLIC
-- Gate-2 census (ci.yml EXPECT_FUNCS=116) is untouched — the helper lives in `venue`.
--
-- Discipline (as 183): md5 PRE-FLIGHT accepting predecessor-or-own per gate, POST-APPLY
-- self-check per gate, rollback restoring the nine applied bodies and dropping the
-- helper with the inverse guards; replay-safe.
-- ============================================================================
begin;

-- ── PRE-FLIGHT (stacking guard): each gate must be its predecessor body (first apply)
-- or this migration's body (idempotent re-apply); anything else refuses.
do $pf$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('venue.record_scan(uuid,uuid,uuid,jsonb,text)', 'fa48a67b83893e1cf4c0cbd4764a5620', '68144a168878e72c3a3888113cf4a3b8'),
    ('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)', '945af8d6446bbceb637e0e3de6499fc6', 'c18f03d7cee504f4bafe42a8875e58ec'),
    ('venue.validate_ticket_online(uuid,uuid)', 'd595ee4ab152c2a0c30ff0e0c19a8169', 'c5085c53eda7abf45c1a64233fe0fbe7'),
    ('venue.revoke_door_pin(uuid,text)', '498027d95150b8f57dd17676aff49116', '68e9e9067518d48b513dd7f1dfd88af6'),
    ('venue.allocate_comp(uuid,uuid,integer,text,text)', '8e4d779f1a4cc8158349e20b7b8bc603', '73ad103d04ce30dbf7d7238ade284a26'),
    ('venue.check_in_guest_entry(uuid,uuid,text,text)', '825c03467db92f092491ea54e71b88eb', 'fe01bd1bca452f63957972f9990bcb52'),
    ('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)', '9f5ed2d7ca6eba24ef576bdcf81a577c', '37fe461eb19b259ae382fc12a26ccadc'),
    ('venue.get_door_manifest(uuid,integer)', '7c38de6f4243eb37c5b746bfbc962681', 'e195700a966a3a741b2bee53bfcf940d'),
    ('venue.sync_scan_device_manifest(uuid,uuid,integer)', '6beca3168e76bb566e456b6abd467197', 'f9d3e5279ce25534028fb1672d5d7a10')
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
  '187 (E-76 on the door plane): refuses (42501, identical to a missing venue role) unless the session''s event is operated by the venue''s CURRENT operator org (catalog.venue.org_id = catalog.event.org_id). Called by the nine door write/read gates right after their venue-role gate. Zero client grant.';
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
declare v_venue uuid;
begin
  if p_outcome not in ('arrived','no_show') then raise exception 'invalid_input: bad outcome'; end if;
  select ev.venue_id into v_venue from venue.guest_entry ge
   join venue.guest_list gl on gl.id = ge.guest_list_id
   join catalog.event_session es on es.session_id=gl.event_session_id
   join catalog.event ev on ev.event_id=es.event_id where ge.id = p_entry_id;
  if v_venue is null then raise exception 'not_found: entry %', p_entry_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office','venue_scanner']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
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
    ('venue.check_in_guest_entry(uuid,uuid,text,text)', 'fe01bd1bca452f63957972f9990bcb52'),
    ('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)', '37fe461eb19b259ae382fc12a26ccadc'),
    ('venue.get_door_manifest(uuid,integer)', 'e195700a966a3a741b2bee53bfcf940d'),
    ('venue.sync_scan_device_manifest(uuid,uuid,integer)', 'f9d3e5279ce25534028fb1672d5d7a10')
  ) as t(fn, md5_x) loop
    v_md5 := md5(pg_get_functiondef(r.fn::regprocedure));
    if v_md5 <> r.md5_x then
      raise exception 'precondition_failed: 187 post-apply self-check — % body (md5 %) is not the expected body; this file was modified', r.fn, v_md5;
    end if;
  end loop;
end $pc$;

commit;
