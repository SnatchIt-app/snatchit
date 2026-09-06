-- ============================================================================
-- 114_signing_key_door_delivery_and_manifest_signing_context.sql — closes
-- SCANNER_VERIFIER_CONTRACT.md §7 P2-M1-DELIVERY (a bearer-only door device had
-- no way to read M1: the kernel.signing_key public projection is granted to
-- `authenticated` only, PFA-16) and P2-MANIFEST-KEY (the door-manifest edge had
-- no canonical source for the identity of the key it signs with — it read an
-- env-only handle, DOOR_MANIFEST_KMS_HANDLE_REF, that named no key_id).
--
-- WHAT THIS MIGRATION IS. LOCAL / REHEARSAL ARTIFACT — NOT DEPLOYED, NOT APPLIED
-- TO PRODUCTION. Adds TWO venue functions, both service_role-only (PUBLIC, anon,
-- authenticated explicitly revoked). No table, no grant on kernel.signing_key
-- changes (the 083/103 staff/client column projection + policy are untouched).
-- No public-schema object, Gate-2 untouched. CENSUS: venue functions 85 -> 87;
-- five-schema routines 294 -> 296 (144 A15, 145 A4, 148 B2/B5, 156 A20, 157 A46,
-- 180 A-block re-derived from the live catalog). Next after 113.
--
-- ── ONE AUTHORITY: kernel.signing_key ────────────────────────────────────────
-- Both functions read kernel.signing_key and nothing else — the SAME registry
-- the staff/client M1 projection is served from. No second registry, no
-- env-only identifier: the key the door-manifest edge names in
-- `signature.key_id` is the key whose `kms_handle_ref` it signs with, because
-- both come from ONE row returned by ONE call.
--
-- PART 1 — venue.get_signing_keys_door(session, door_session_id, token, device)
--   MACHINE MAY EXECUTE, DOOR SESSION DECIDES SCOPE (108/113 pattern):
--   kernel.assert_door_session is the sole gate; the read is bound to the
--   RETURNED (device, event_session). Rows: every `global` key + `per_event`
--   keys of the bound session's event + `per_venue` keys of its venue — ALL
--   statuses and windows (a verifier needs `revoked`/`rotating`/future rows to
--   refuse `key_revoked`/`key_window` rather than `unknown_key`; door §3.1 M1
--   refresh semantics). Unrelated events/venues are never returned. Exactly the
--   PFA-16 + 103 public projection per row: key_id, scope, event_id, venue_id,
--   public_key, algorithm, status, not_before, not_after — NEVER kms_handle_ref,
--   never identity, never private material (none exists in the database).
--
-- PART 2 — venue.get_manifest_signing_context()
--   The door-manifest edge's ONLY source of the manifest-signing key identity
--   (the analogue of 102 get_ticket_signing_context for credentials). The
--   manifest key IS the platform trust root: the single active `global` key
--   (083 partial unique index signing_key_active_global_uq guarantees ≤ 1).
--   Returns `{status:'ok', key_id, scope, kms_handle_ref, algorithm, public_key,
--   key_status, not_before, not_after}` — kms_handle_ref is a KMS handle (full
--   key ARN per runbook D4 / 110 guard), NOT key material, and the edge never
--   returns it to a client — or `{status:'unavailable', code}` with a stable
--   code: no_active_global_key | ambiguous_active_global_key | key_window |
--   algorithm_not_es256. service_role only: the edge calls it AFTER the caller
--   was authorized by venue.get_door_manifest (has_venue_role).
--
-- ── OPERATIONAL BINDING THE CEREMONY MUST SATISFY (documented, not assumed) ──
--   (a) runbook D4: the §6.1 bootstrap INSERT's kms_handle_ref = the FULL ARN of
--       the KMS key created at CreateKey (110 guard: arn:aws:kms:<region>:<acct>:key/<uuid>);
--   (b) runbook D3/D5: public_key = the SPKI PEM exported from THAT key; its
--       SHA-256(DER) = signing.expected_key_fingerprint (099 monitor);
--   (c) E2 signer scope: the runtime role's account + region must equal the
--       ARN's (kms-taxonomy kms_handle_scope_mismatch otherwise — SECURITY);
--   (d) the edge's sign-after-verify: every emitted manifest signature is
--       verified under THIS row's public_key before it leaves the edge — a
--       handle that does not correspond to the row fails closed
--       (sign_verify_failed), so a mis-bound ceremony cannot emit a signature
--       that names a key it was not made with.
--
-- NOT IN THIS MIGRATION (explicitly open): signed M1 bundles (edge §5.4.2);
-- M1 integrity remains TLS + the door-session gate.
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — venue.get_signing_keys_door (service_role MACHINE path). VOLATILE
-- (assert_door_session touches last_seen_at).
-- ============================================================================
create or replace function venue.get_signing_keys_door(
  p_session_id uuid, p_door_session_id uuid, p_session_token text, p_device_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_bound_device uuid; v_bound_session uuid; v_event uuid; v_venue uuid; v_keys jsonb;
begin
  -- the ONLY gate: the door session token. Returns the bound (device, session);
  -- a body device/session that disagrees raises the same opaque door_session_invalid.
  select device_id, event_session_id into v_bound_device, v_bound_session
    from kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token);
  -- scope from the BOUND session, never a body field.
  select es.event_id, ev.venue_id into v_event, v_venue
    from catalog.event_session es join catalog.event ev on ev.event_id = es.event_id
   where es.session_id = v_bound_session;
  -- the public projection ONLY (PFA-16 + 103 columns), for the bound scope.
  select coalesce(jsonb_agg(jsonb_build_object(
           'key_id', k.key_id, 'scope', k.scope, 'event_id', k.event_id, 'venue_id', k.venue_id,
           'public_key', k.public_key, 'algorithm', k.algorithm, 'status', k.status,
           'not_before', k.not_before, 'not_after', k.not_after) order by k.not_before, k.key_id), '[]'::jsonb)
    into v_keys
    from kernel.signing_key k
   where k.scope = 'global'
      or (k.scope = 'per_event' and k.event_id = v_event)
      or (k.scope = 'per_venue' and k.venue_id = v_venue);
  return jsonb_build_object('session_id', v_bound_session, 'event_id', v_event, 'venue_id', v_venue,
                            'generated_at', now(), 'keys', v_keys);
end;
$$;
comment on function venue.get_signing_keys_door(uuid,uuid,text,uuid) is
  'MACHINE M1 read (service_role, door-session edge /keys): kernel.assert_door_session is the sole gate; the keyring is read for the RETURNED bound session (global + per_event of its event + per_venue of its venue, ALL statuses/windows so a verifier can refuse key_revoked/key_window). Exactly the PFA-16+103 public projection per row — never kms_handle_ref, never identity. MACHINE MAY EXECUTE; DOOR SESSION DECIDES SCOPE. Closes P2-M1-DELIVERY.';
revoke all on function venue.get_signing_keys_door(uuid,uuid,text,uuid) from public, anon, authenticated;
grant execute on function venue.get_signing_keys_door(uuid,uuid,text,uuid) to service_role;

-- ============================================================================
-- PART 2 — venue.get_manifest_signing_context (service_role, door-manifest
-- edge). STABLE (reads only).
-- ============================================================================
create or replace function venue.get_manifest_signing_context()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_k kernel.signing_key%rowtype; v_n integer;
begin
  select count(*) into v_n from kernel.signing_key k where k.scope = 'global' and k.status = 'active';
  if v_n = 0 then
    return jsonb_build_object('status', 'unavailable', 'code', 'no_active_global_key');
  end if;
  if v_n > 1 then
    -- unreachable under signing_key_active_global_uq; fail closed rather than pick one.
    return jsonb_build_object('status', 'unavailable', 'code', 'ambiguous_active_global_key');
  end if;
  select * into v_k from kernel.signing_key k where k.scope = 'global' and k.status = 'active';
  if v_k.not_before > now() or (v_k.not_after is not null and v_k.not_after <= now()) then
    return jsonb_build_object('status', 'unavailable', 'code', 'key_window', 'key_id', v_k.key_id);
  end if;
  if v_k.algorithm <> 'ES256' then
    return jsonb_build_object('status', 'unavailable', 'code', 'algorithm_not_es256', 'key_id', v_k.key_id);
  end if;
  return jsonb_build_object(
    'status', 'ok', 'key_id', v_k.key_id, 'scope', v_k.scope,
    'kms_handle_ref', v_k.kms_handle_ref, 'algorithm', v_k.algorithm, 'public_key', v_k.public_key,
    'key_status', v_k.status, 'not_before', v_k.not_before, 'not_after', v_k.not_after);
end;
$$;
comment on function venue.get_manifest_signing_context() is
  'The door-manifest edge''s ONLY source of the manifest-signing key identity (DOOR-MANIFEST-SIG-v1 signature.key_id): the single active global kernel.signing_key row — key_id, kms_handle_ref (a KMS handle per runbook D4, NOT key material; never returned to a client), algorithm (must be ES256), public_key (the edge verifies every signature under it before responding), window. Stable unavailable codes: no_active_global_key | ambiguous_active_global_key | key_window | algorithm_not_es256. service_role only. Closes P2-MANIFEST-KEY.';
revoke all on function venue.get_manifest_signing_context() from public, anon, authenticated;
grant execute on function venue.get_manifest_signing_context() to service_role;

commit;
