-- ============================================================================
-- 107_door_pin_kdf_unpark.sql — PFA-26-UNPARK: un-park venue.create_door_pin and
-- venue.mint_door_session using an in-DB pgcrypto bcrypt slow-KDF, keeping the
-- FROZEN create/mint signatures. The edge rate-limiter (door-session edge,
-- venue||device, 5/60, fail-closed) is the brute-force control for the
-- low-entropy PIN (PFA-26-UNPARK owner direction, this train).
--
-- WHAT THIS MIGRATION IS. DARK / unapplied / undeployed. Production is at ledger
-- 107 (through 092); 093-106 authored, NOT applied. 093-106 are IMMUTABLE. This
-- migration (a) ensures the pgcrypto extension exists in the `extensions` schema
-- and (b) re-creates TWO parked functions via CREATE OR REPLACE
-- (venue.create_door_pin 086:918-930, venue.mint_door_session 086:955-969). No
-- signature change (PFA-26 froze them), no grant change (create_door_pin ->
-- authenticated, mint_door_session -> service_role, both from 086), no new
-- function object, no public-schema object, Gate-2 untouched, function census
-- UNCHANGED. Next migration after 106.
--
-- ── OWNER DIRECTION (PFA-26-UNPARK, OWNER DIRECTION RECEIVED — this train) ────
-- Launch Door PIN uses pgcrypto bcrypt, cost 12, per-hash random salt. The
-- frozen DB-facing create/mint signatures stay intact (the PIN arrives at the DB
-- and is hashed there). Argon2id is NOT required for launch (optional future
-- hardening). Requirements: no plaintext/reversible PIN storage; bcrypt verifier
-- only; cost encoded in the stored verifier; constant-time crypt compare through
-- pgcrypto; no PIN in logs/audit/Sentry; verifier never returned to a client;
-- rotate by revoke + recreate, never in-place rewrite (revoke_door_pin, 086,
-- unchanged).
--
-- ── WHY pgcrypto / extensions ───────────────────────────────────────────────
-- pgcrypto is a Supabase-sanctioned extension (production HAS it installed; the
-- rehearsal bootstrap installs it WITH SCHEMA extensions). bcrypt's modular-crypt
-- output ('$2a$12$<22-char-salt><31-char-hash>') stores algorithm + cost + salt
-- inline, so verification needs no separate salt/version column and future cost
-- changes need no schema change. Functions keep search_path='' and call
-- extensions.crypt / extensions.gen_salt fully qualified. bcrypt silently
-- truncates at 72 bytes, so the PIN is capped well under that (§ validation).
--
-- ── PIN FORMAT (train §9: do NOT invent an unfrozen rule) ────────────────────
-- The frozen architecture defines door_pin.pin_hash as a LOW-ENTROPY secret
-- requiring a slow KDF, but fixes NO length/charset/digit-count. This migration
-- therefore enforces ONLY a safety envelope — non-empty, not whitespace-only,
-- and 1..64 bytes (comfortably under bcrypt's 72-byte truncation) — and does NOT
-- impose a 4-/6-digit or digits-only rule (that stays an owner/product decision).
-- Malformed input is rejected BEFORE the expensive KDF.
-- ============================================================================
begin;

-- pgcrypto lives in the `extensions` schema on Supabase and in the rehearsal
-- bootstrap. Idempotent: a no-op where it already exists (prod, CI, rehearsal).
create extension if not exists pgcrypto with schema extensions;

-- ============================================================================
-- PART 1 — venue.create_door_pin: bcrypt-hash the PIN at creation. Signature
-- frozen (086:918-919): (p_venue_id, p_session_id, p_label, p_pin_plain,
-- p_expires_at, p_command_key). venue_manager only (matches revoke_door_pin +
-- the door_pin RLS). The session must belong to the venue (cross-tenant guard).
-- ============================================================================
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

comment on function venue.create_door_pin(uuid,uuid,text,text,timestamptz,text) is
  'PFA-26-UNPARK (owner-directed): create a door PIN, hashing p_pin_plain with pgcrypto bcrypt cost 12 (per-hash salt, algorithm+cost inline in pin_hash). venue_manager only; the session must belong to the venue. Rejects empty/oversized PIN before the KDF (no frozen digit rule invented). NEVER stores plaintext, NEVER returns the hash, NEVER logs the PIN. Rotate by revoke_door_pin + create anew (no in-place change).';

-- ============================================================================
-- PART 2 — venue.mint_door_session: verify p_pin_plain against the active PIN(s)
-- for (venue, session) with a constant-time crypt compare and mint a tokenized
-- door session. Signature frozen (086:955-956): (p_venue_id, p_session_id,
-- p_device_id, p_pin_plain, p_command_key). service_role only (the door-session
-- edge, verify_jwt:false) — the PIN IS the authorization; there is no auth.uid().
-- Token contract matches kernel.assert_door_session (086:538): the stored
-- token_hash = md5('door_session:' || secret); the edge presents the secret as
-- p_session_token. OPAQUE failure: a wrong PIN / wrong device / wrong session /
-- absent PIN all raise the SAME door_session_invalid (no existence oracle, §9/§10).
-- ============================================================================
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

comment on function venue.mint_door_session(uuid,uuid,uuid,text,text) is
  'PFA-26-UNPARK (owner-directed): verify a door PIN (pgcrypto bcrypt constant-time crypt compare) and mint a tokenized door session. service_role only (the door-session edge, verify_jwt:false — the PIN is the sole authorization). Stores token_hash=md5(''door_session:''||secret) matching kernel.assert_door_session; returns the 256-bit secret ONCE. Wrong PIN / wrong device / wrong session / absent PIN all raise the SAME opaque door_session_invalid (no existence oracle). Re-mint revokes any prior active session for the (device, session). Never stores plaintext, never returns the hash, never logs the PIN.';

commit;
