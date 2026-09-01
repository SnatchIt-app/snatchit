-- ============================================================================
-- 083_kernel_credential_infrastructure.sql — PHASE 2, PACKAGE 083 (family G)
--
-- Frozen baseline phase2-architecture-v2 (06fd5ec). Branch base 456aaa71 (082
-- merged). Migrations 076–082 are hash-locked and untouched.
--
-- WHAT THIS PACKAGE IS (derived from plan §8/083, registry row 083, schema §1.7 +
-- WALLET §11.1-§11.6, RPC §7.1/§17.13/§17.23/§20.7.3-4, RLS §7.7/§16.8, dsm §2 BP-2,
-- ODR16 #19, R2 rows 5/8; two independent derivation passes reconciled):
--
--   the credential + Apple-Wallet + mint substrate. The DB-side REFERENCE to the
--   asymmetric signing key (public key + opaque KMS handle — NO private key on any
--   row, C33); the Apple Pass-Type-ID cert reference; the wallet-pass registry +
--   device registrations + APNs push ledger; the MINT ENGINE kernel.issue_ticket_atoms
--   (moved from 081 by C114/R2B — it reads kernel.signing_key and pins signing_key_id
--   on every atom); the venue.append_door_manifest_delta SEAM-2 no-op stub (body 086);
--   and the kernel.deletion_blockers_wallet BP-2 body (OR-17).
--
-- DARK: native issuance stays OFF (feature.native_issuance_enabled=false, 078 seed —
--   issue_ticket_atoms is inert behind it at its callers) and Wallet stays OFF
--   (wallet.apple.enabled=false, 078 seed — the kill switch is NOT role-bypassable;
--   even platform_admin gets precondition_failed('wallet_disabled')). 083 lands the
--   engines fully wired but doubly dark; the primary mint caller (finalize_primary_order)
--   is 085 and the scan surface is 086.
--
-- OWNER RULINGS carried by this package:
--   PFA-16 — anon reads of signing_key.public_key are undeliverable under the immutable
--     076 kernel schema wall (the PFA-14 class). Fail-closed: the public projection is
--     GRANTed to `authenticated` only; anon door/verification reads the verify key via
--     the 086 manifest/public surface. NO anon grant here (076 boundary unchanged).
--   PFA-17 — kernel.revoke_signing_key is authored in 086 (its body force-closes 086
--     door_manifest episodes + emits via 092). 083 ships provision + rotate ONLY.
--   PFA-18 — the signing-key lifecycle (provision/rotate) is DUAL-CONTROLLED via
--     kernel.approval_request, parallel to pass_type_cert.
--
-- C33 — NO private key material on any row: signing_key.public_key is the verify key;
--   pass_type_cert.{certificate_pem,wwdr_cert_pem} are PUBLIC certs; every kms_handle_ref
--   is an opaque KMS handle only; wallet_pass.auth_token_* and wallet_pass_device.push_token_enc
--   are envelope-encrypted per-pass/per-device BEARER tokens (not signing keys). No RPC
--   returns any secret column; the secret columns are granted to service_role only.
--   Signed tokens are produced only by the credential-sign edge fn calling KMS.
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — kernel.signing_key (schema §1.7; C33 key-reference, NO secret)
-- ============================================================================
create table if not exists kernel.signing_key (
  key_id          uuid primary key default gen_random_uuid(),
  scope           text not null default 'per_event'
                  check (scope in ('per_event','per_venue','global')),
  event_id        uuid references catalog.event(event_id) on delete restrict,
  venue_id        uuid references catalog.venue(venue_id) on delete restrict,
  public_key      text not null,                                  -- verify key, distributable
  kms_handle_ref  text not null,                                  -- opaque KMS handle/ARN, NOT key material
  status          text not null default 'active'
                  check (status in ('active','rotating','revoked')),
  not_before      timestamptz not null,
  not_after       timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- scope/target coherence: exactly the matching target set for the scope.
  constraint signing_key_scope_target_ck check (
    (scope = 'per_event'  and event_id is not null and venue_id is null)
    or (scope = 'per_venue' and venue_id is not null and event_id is null)
    or (scope = 'global'    and event_id is null and venue_id is null)
  ),
  constraint signing_key_window_ck check (not_after is null or not_after > not_before)
);

-- one ACTIVE key per scope target (rotation flips old→rotating, new→active in one txn).
create unique index if not exists signing_key_active_event_uq
  on kernel.signing_key (event_id) where status = 'active' and scope = 'per_event';
create unique index if not exists signing_key_active_venue_uq
  on kernel.signing_key (venue_id) where status = 'active' and scope = 'per_venue';
create unique index if not exists signing_key_active_global_uq
  on kernel.signing_key ((true)) where status = 'active' and scope = 'global';
create index if not exists signing_key_event_status_idx on kernel.signing_key (event_id, status);
create index if not exists signing_key_venue_status_idx on kernel.signing_key (venue_id, status);

-- IMM guard: public_key/kms_handle_ref/scope/target are immutable after creation;
-- only status (forward-only active→rotating→revoked) and not_after transition.
create or replace function kernel.guard_signing_key_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.public_key <> old.public_key or new.kms_handle_ref <> old.kms_handle_ref
     or new.scope <> old.scope
     or new.event_id is distinct from old.event_id or new.venue_id is distinct from old.venue_id
     or new.not_before <> old.not_before then
    raise exception 'append_only: signing_key identity/target/public_key/kms_handle is immutable after creation'
      using errcode = 'P0001';
  end if;
  -- forward-only status: active -> rotating|revoked ; rotating -> active|revoked ; revoked terminal
  if old.status = 'revoked' and new.status <> 'revoked' then
    raise exception 'append_only: signing_key status is forward-only (revoked is terminal)' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_signing_key_immutable on kernel.signing_key;
create trigger tg_signing_key_immutable before update on kernel.signing_key
  for each row execute function kernel.guard_signing_key_immutable();
drop trigger if exists tg_signing_key_updated_at on kernel.signing_key;
create trigger tg_signing_key_updated_at before update on kernel.signing_key
  for each row execute function kernel.set_updated_at();

alter table kernel.signing_key enable row level security;
revoke all on kernel.signing_key from anon, authenticated;
-- PFA-16: the public projection is readable by AUTHENTICATED only (076 gives anon no
-- kernel USAGE; anon verification is delivered via the 086 manifest surface). NOT anon.
grant select (key_id, scope, event_id, venue_id, public_key, status, not_before, not_after)
  on kernel.signing_key to authenticated;

drop policy if exists kernel_signing_key_sel_public on kernel.signing_key;
create policy kernel_signing_key_sel_public on kernel.signing_key for select to authenticated
  using (true);   -- row-visible to any signed-in principal; kms_handle_ref withheld by the column grant

-- ============================================================================
-- PART 2 — kernel.pass_type_cert (WALLET §11.3; public certs + opaque KMS handle)
--   Deny-all, ZERO policies (doors never verify the Apple signature).
-- ============================================================================
create table if not exists kernel.pass_type_cert (
  pass_type_cert_id     uuid primary key default gen_random_uuid(),
  pass_type_identifier  text not null,                            -- e.g. pass.com.snatchit.ticket
  team_identifier       text not null,
  certificate_pem       text not null,                            -- PUBLIC cert
  wwdr_cert_pem         text not null,                            -- PUBLIC Apple intermediate
  kms_handle_ref        text not null,                            -- opaque handle, NOT key material
  status                text not null default 'active'
                        check (status in ('active','rotating','revoked','expired')),
  not_before            timestamptz not null,
  not_after             timestamptz not null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint pass_type_cert_window_ck check (not_after > not_before)
);

create unique index if not exists pass_type_cert_active_uq
  on kernel.pass_type_cert (pass_type_identifier) where status = 'active';
create index if not exists pass_type_cert_expiry_idx on kernel.pass_type_cert (status, not_after);

create or replace function kernel.guard_pass_type_cert_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.pass_type_identifier <> old.pass_type_identifier or new.team_identifier <> old.team_identifier
     or new.certificate_pem <> old.certificate_pem or new.wwdr_cert_pem <> old.wwdr_cert_pem
     or new.kms_handle_ref <> old.kms_handle_ref
     or new.not_before <> old.not_before or new.not_after <> old.not_after then
    raise exception 'append_only: pass_type_cert identity/cert/handle/window is immutable after creation'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_pass_type_cert_immutable on kernel.pass_type_cert;
create trigger tg_pass_type_cert_immutable before update on kernel.pass_type_cert
  for each row execute function kernel.guard_pass_type_cert_immutable();
drop trigger if exists tg_pass_type_cert_updated_at on kernel.pass_type_cert;
create trigger tg_pass_type_cert_updated_at before update on kernel.pass_type_cert
  for each row execute function kernel.set_updated_at();

alter table kernel.pass_type_cert enable row level security;
revoke all on kernel.pass_type_cert from anon, authenticated;
-- deny-all, ZERO policies. Secret + cert columns are service_role/platform only.

-- ============================================================================
-- PART 3 — kernel.wallet_pass (WALLET §11.1; the pass artifact registry)
--   Zero-policy; owner reads a 5-column projection via RPC only. Secret columns
--   (auth_token_enc/hash, serial_no_opaque) to service_role only, no RPC returns them.
-- ============================================================================
create table if not exists kernel.wallet_pass (
  wallet_pass_id             uuid primary key default gen_random_uuid(),
  ticket_atom_id             uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  holder_identity_id         uuid not null references auth.users(id) on delete restrict,   -- snapshot at mint (BP-2)
  generation                 integer not null check (generation >= 1),
  serial_no_opaque           text not null check (length(serial_no_opaque) >= 20),
  pass_type_cert_id          uuid not null references kernel.pass_type_cert(pass_type_cert_id) on delete restrict,
  auth_token_enc             bytea not null,                       -- envelope-encrypted bearer token
  auth_token_hash            text not null,                        -- for constant-time compare
  credential_version_at_build integer not null check (credential_version_at_build >= 0),
  signing_key_id             uuid not null references kernel.signing_key(key_id) on delete restrict,
  status                     text not null default 'issued'
                             check (status in ('issued','superseded','revoked','consumed','invalidated','expired')),
  status_reason_code         text,
  built_at                   timestamptz not null default now(),
  last_updated_at            timestamptz not null default now(),
  command_idempotency_key    text not null,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  constraint wallet_pass_last_updated_ck check (last_updated_at >= built_at),
  constraint wallet_pass_atom_generation_uq unique (ticket_atom_id, generation),
  constraint wallet_pass_serial_uq unique (serial_no_opaque),
  constraint wallet_pass_holder_command_uq unique (holder_identity_id, command_idempotency_key)
);

-- the structural half of the Wallet non-negotiable: at most ONE live pass per atom.
create unique index if not exists wallet_pass_live_atom_uq
  on kernel.wallet_pass (ticket_atom_id) where status = 'issued';
create index if not exists wallet_pass_atom_idx on kernel.wallet_pass (ticket_atom_id);
create index if not exists wallet_pass_status_updated_idx on kernel.wallet_pass (status, last_updated_at);

-- IMM guard: identity columns frozen after insert; status forward-only; only
-- last_updated_at (+ status/status_reason_code transition) mutable. DELETE denied.
create or replace function kernel.guard_wallet_pass_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'append_only: wallet_pass is never deleted (status transition only)' using errcode = 'P0001';
  end if;
  if new.wallet_pass_id <> old.wallet_pass_id or new.ticket_atom_id <> old.ticket_atom_id
     or new.holder_identity_id <> old.holder_identity_id or new.generation <> old.generation
     or new.serial_no_opaque <> old.serial_no_opaque or new.pass_type_cert_id <> old.pass_type_cert_id
     or new.auth_token_enc <> old.auth_token_enc or new.auth_token_hash <> old.auth_token_hash
     or new.credential_version_at_build <> old.credential_version_at_build
     or new.signing_key_id <> old.signing_key_id or new.built_at <> old.built_at
     or new.command_idempotency_key <> old.command_idempotency_key then
    raise exception 'append_only: wallet_pass identity columns are immutable after mint' using errcode = 'P0001';
  end if;
  -- status forward-only: issued -> terminal; no reverse; no terminal->terminal.
  if old.status <> 'issued' and new.status <> old.status then
    raise exception 'append_only: wallet_pass status is forward-only from issued (% is terminal)', old.status
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_wallet_pass_immutable on kernel.wallet_pass;
create trigger tg_wallet_pass_immutable before update or delete on kernel.wallet_pass
  for each row execute function kernel.guard_wallet_pass_immutable();
drop trigger if exists tg_wallet_pass_updated_at on kernel.wallet_pass;
create trigger tg_wallet_pass_updated_at before update on kernel.wallet_pass
  for each row execute function kernel.set_updated_at();

alter table kernel.wallet_pass enable row level security;
revoke all on kernel.wallet_pass from anon, authenticated;
-- deny-all, ZERO policies. Owner reads via kernel RPC (definer projection); no venue/org read.

-- ============================================================================
-- PART 4 — kernel.wallet_pass_device (WALLET §11.2; Apple device registrations)
-- ============================================================================
create table if not exists kernel.wallet_pass_device (
  registration_id            uuid primary key default gen_random_uuid(),
  wallet_pass_id             uuid not null references kernel.wallet_pass(wallet_pass_id) on delete restrict,
  device_library_identifier  text not null,
  push_token_enc             bytea not null,                       -- envelope-encrypted APNs token
  registered_at              timestamptz not null default now(),
  unregistered_at            timestamptz,
  last_push_at               timestamptz,
  last_push_result           text,
  push_failure_count         integer not null default 0 check (push_failure_count >= 0),
  created_at                 timestamptz not null default now(),
  constraint wallet_pass_device_uq unique (wallet_pass_id, device_library_identifier),
  constraint wallet_pass_device_unreg_ck check (unregistered_at is null or unregistered_at >= registered_at)
);

create index if not exists wallet_pass_device_live_idx
  on kernel.wallet_pass_device (wallet_pass_id) where unregistered_at is null;

create or replace function kernel.guard_wallet_pass_device_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'append_only: wallet_pass_device is never deleted (unregister sets a timestamp)' using errcode = 'P0001';
  end if;
  if new.registration_id <> old.registration_id or new.wallet_pass_id <> old.wallet_pass_id
     or new.device_library_identifier <> old.device_library_identifier
     or new.push_token_enc <> old.push_token_enc or new.registered_at <> old.registered_at then
    raise exception 'append_only: wallet_pass_device identity is immutable after registration' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_wallet_pass_device_immutable on kernel.wallet_pass_device;
create trigger tg_wallet_pass_device_immutable before update or delete on kernel.wallet_pass_device
  for each row execute function kernel.guard_wallet_pass_device_immutable();

alter table kernel.wallet_pass_device enable row level security;
revoke all on kernel.wallet_pass_device from anon, authenticated;
-- audit-only: deny-all, ZERO policies.

-- ============================================================================
-- PART 5 — kernel.wallet_pass_push_log (WALLET §11.4; AO APNs attempt ledger)
-- ============================================================================
create table if not exists kernel.wallet_pass_push_log (
  push_log_id     uuid primary key default gen_random_uuid(),
  wallet_pass_id  uuid not null references kernel.wallet_pass(wallet_pass_id) on delete restrict,
  registration_id uuid references kernel.wallet_pass_device(registration_id) on delete restrict,
  trigger_kind    text not null,
  cause_ref       uuid,
  attempted_at    timestamptz not null default now(),
  outcome         text not null check (outcome in ('sent','rejected','unregistered','error')),
  apns_status     integer,
  apns_reason     text,
  created_at      timestamptz not null default now(),
  constraint wallet_pass_push_log_dedup_uq unique (wallet_pass_id, trigger_kind, cause_ref, registration_id)
);

drop trigger if exists tg_wallet_pass_push_log_append_only on kernel.wallet_pass_push_log;
create trigger tg_wallet_pass_push_log_append_only before update or delete on kernel.wallet_pass_push_log
  for each row execute function kernel.raise_append_only();

alter table kernel.wallet_pass_push_log enable row level security;
revoke all on kernel.wallet_pass_push_log from anon, authenticated;
revoke update, delete on kernel.wallet_pass_push_log from service_role;   -- AO
-- audit-only: deny-all, ZERO policies.

-- ============================================================================
-- PART 6 — the private .pkpass storage bucket (public=false, zero policies)
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('pkpass', 'pkpass', false)
on conflict (id) do nothing;
-- ZERO storage.objects policies: access is service_role/definer only (the credential-sign
-- edge fn mints short-TTL signed URLs). No anon/authenticated verb is granted.

-- ============================================================================
-- PART 7 — venue.append_door_manifest_delta — SEAM-2 no-op stub (C113/R2B).
--   Signature frozen by SEAM-2a; real body in 086 (writes venue.door_manifest).
--   Placed here because the earliest caller is kernel.issue_ticket_atoms (083).
--   At 083 venue.door_manifest does not exist, so no episode can be open and the
--   contracted degenerate case is a silent no-op (RPC §17.13/§6.3).
-- ============================================================================
create or replace function venue.append_door_manifest_delta(
  p_session_id uuid, p_atoms uuid[], p_op text, p_cause_ref uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op; body 086 (SEAM-2a: touches no relation, adds no edge)

-- ============================================================================
-- PART 8 — kernel.deletion_blockers_wallet — SEAM-2 body (born 077; BP-2, OR-17).
--   BP-2: a LIVE wallet pass (holder_identity_id = :id AND status='issued') blocks
--   tombstone entry. Cleared by supersede (transfer) or the lifecycle sweep. The
--   signature is the 077 stub's, byte-for-byte.
-- ============================================================================
create or replace function kernel.deletion_blockers_wallet(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$
  select 'BP-2: live wallet pass — resolves when the pass is superseded on transfer or reconciled (consumed/invalidated/expired)'
   where exists (
     select 1 from kernel.wallet_pass w
      where w.holder_identity_id = p_identity
        and w.status = 'issued'
   );
$$;

-- ============================================================================
-- PART 9 — the DUAL-CONTROLLED credential lifecycle — FAIL-CLOSED PARKED (PFA-18A).
--   PFA-18 requires dual control for signing-key + pass-type-cert lifecycle ops;
--   the frozen mechanism (kernel.approval_request, 077) cannot represent credential
--   approvals (its action/subject_kind closed sets are money-only, immutable) — the
--   PFA-4 impossibility class. Per the owner (PFA-18A): preserve the dual-control
--   REQUIREMENT, reject single-control fallback, do NOT mutate 077, do NOT overload
--   its vocabulary. Until a credential-compatible dual-control mechanism is ratified,
--   each affected RPC keeps a frozen-faithful signature and FAILS CLOSED with a stable
--   precondition_failed — ZERO credential mutation / key activation / cert activation /
--   partial approval / authority escalation. (pass_type_cert signatures are derived —
--   the corpus lists the trio by name only, §17.23 — pending the real bodies; E-41.)
-- ============================================================================
create or replace function kernel.provision_signing_key(
  p_scope text, p_scope_id uuid, p_public_key text, p_kms_handle_ref text,
  p_not_before timestamptz, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); provisioning is parked, no key is activated';
end;
$$;

create or replace function kernel.rotate_signing_key(
  p_old_key_id uuid, p_public_key text, p_kms_handle_ref text,
  p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); rotation is parked, no key is activated';
end;
$$;

create or replace function kernel.provision_pass_type_cert(
  p_pass_type_identifier text, p_team_identifier text, p_certificate_pem text,
  p_wwdr_cert_pem text, p_kms_handle_ref text, p_not_before timestamptz,
  p_not_after timestamptz, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); provisioning is parked, no cert is activated';
end;
$$;

create or replace function kernel.rotate_pass_type_cert(
  p_old_cert_id uuid, p_certificate_pem text, p_wwdr_cert_pem text,
  p_kms_handle_ref text, p_not_before timestamptz, p_not_after timestamptz,
  p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); rotation is parked, no cert is activated';
end;
$$;

create or replace function kernel.revoke_pass_type_cert(
  p_cert_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); revocation is parked, no cert state changes';
end;
$$;

-- ============================================================================
-- PART 10 — kernel.issue_ticket_atoms — THE MINT ENGINE (moved 081→083, C114/R2B).
--   SSCAS #1 mint leg (§7.1). DOUBLY DARK + activation-boundary fail-closed:
--     (1) native issuance gate — refuse feature_disabled while the flag is false;
--     (2) an ACTIVE kernel.signing_key must resolve for the scope — else fail closed
--         (precondition_failed). No key can be provisioned while the lifecycle is
--         parked (PFA-18A), so the mint cannot run — and it NEVER auto-creates a key.
--   Writes: kernel.tickets (N, state='active', credential_version=0, signing_key_id),
--   kernel.ticket_ownership_log (N, sequence=1, from NULL, cause), venue.inventory_batch
--   (sold += N — the C27 CHECK held+sold<=capacity is the oversell backstop; the
--   held-decrement is 085/finalize's job, E-40), venue.inventory_movement (issue).
--   NO secret written (C33 — only signing_key_id). Where an open door episode exists
--   it calls venue.append_door_manifest_delta (the 083 no-op stub until 086).
-- ============================================================================
create or replace function kernel.issue_ticket_atoms(p_ctx jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_session  uuid;
  v_org      uuid;
  v_tt       uuid;
  v_batch    uuid;
  v_owner    uuid;
  v_qty      integer;
  v_cause    text;
  v_cause_ref uuid;
  v_key      uuid;
  v_flag     boolean;
  v_serial   integer;
  v_atom     uuid;
  v_atoms    uuid[] := '{}';
  v_ex       uuid[];
  i          integer;
begin
  v_actor := coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1');  -- SN-SYSTEM for import/sweep
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  v_session   := (p_ctx->>'session_id')::uuid;
  v_org       := (p_ctx->>'org_id')::uuid;
  v_tt        := (p_ctx->>'ticket_type_id')::uuid;
  v_batch     := (p_ctx->>'batch_id')::uuid;
  v_owner     := (p_ctx->>'owner_id')::uuid;
  v_qty       := (p_ctx->>'quantity')::integer;
  v_cause     := (p_ctx->>'cause');
  v_cause_ref := (p_ctx->>'cause_ref')::uuid;
  v_key       := (p_ctx->>'signing_key_id')::uuid;

  if v_cause not in ('issue','comp','door_sale','import') then
    raise exception 'precondition_failed: bad_cause %', v_cause;
  end if;
  if v_qty is null or v_qty <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;
  if v_owner is null or v_batch is null or v_session is null then
    raise exception 'precondition_failed: incomplete context';
  end if;

  -- NATIVE ISSUANCE GATE — the mint is inert while the flag is false (dark).
  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c
   where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  -- IDEMPOTENCY: a replay of a succeeded mint returns the original atoms. The mint's
  -- ownership-log entry is ALWAYS cause='issue' (the ownership_log_from_identity_check
  -- requires cause='issue' for the from-NULL sequence-1 row); the business cause lives
  -- in the movement + the state_transition jsonb.
  select array_agg(l.ticket_atom_id order by l.ticket_atom_id) into v_ex
    from kernel.ticket_ownership_log l
   where l.cause = 'issue' and l.cause_ref = v_cause_ref;
  if v_ex is not null and array_length(v_ex, 1) > 0 then
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_ex));
  end if;

  -- ACTIVATION BOUNDARY (§7.1): an ACTIVE signing_key must resolve for the scope.
  -- Fail closed if the pinned key is missing/inactive — NEVER auto-create one.
  if v_key is null or not exists (
    select 1 from kernel.signing_key k
     where k.key_id = v_key and k.status = 'active'
       and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
  ) then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted';
  end if;

  -- lock the batch (C27 choke-point) and mint N atoms.
  perform 1 from venue.inventory_batch b where b.batch_id = v_batch for update;
  if not found then
    raise exception 'not_found: batch %', v_batch using errcode = 'P0002';
  end if;

  select coalesce(max(t.serial_no), 0) into v_serial
    from kernel.tickets t where t.event_session_id = v_session;

  for i in 1..v_qty loop
    insert into kernel.tickets (event_session_id, org_id, ticket_type_id, serial_no,
                                current_owner_id, state, credential_version, signing_key_id)
    values (v_session, v_org, v_tt, v_serial + i, v_owner, 'active', 0, v_key)
    returning ticket_atom_id into v_atom;
    v_atoms := v_atoms || v_atom;

    insert into kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity,
                                             cause, cause_ref, actor_identity, command_idempotency_key,
                                             credential_version_after, state_transition)
    values (v_atom, 1, null, v_owner, 'issue', v_cause_ref, v_actor, p_command_key || ':' || v_atom::text,
            0, jsonb_build_object('from', null, 'to', 'active', 'mint_cause', v_cause));
  end loop;

  -- convert to sold. The C27 CHECK (held+sold<=capacity) is the oversell backstop;
  -- 085/finalize releases the matching hold (held -= N) — forward obligation E-40.
  update venue.inventory_batch set sold = sold + v_qty, updated_at = now()
   where batch_id = v_batch;

  insert into venue.inventory_movement (batch_id, movement_kind, delta_held, delta_sold,
                                        cause, cause_ref, actor_identity)
  values (v_batch, 'issue', 0, v_qty, v_cause, v_cause_ref, v_actor);

  -- where an open door episode exists, feed the manifest delta (no-op stub until 086).
  perform venue.append_door_manifest_delta(v_session, v_atoms, 'add', v_cause_ref);

  return jsonb_build_object('status','ok','atom_ids', to_jsonb(v_atoms));
end;
$$;

-- ============================================================================
-- PART 11 — the crypto-dependent wallet RPCs — FAIL-CLOSED PARKED (PFA-20).
--   The wallet bearer-token envelope-encryption mechanism (auth_token_enc/
--   push_token_enc) AND the token-hash primitive (auth_token_hash) are
--   under-specified in the frozen corpus — no primitive, no key source, no crypto
--   extension (owner-ruled: DO NOT INVENT CRYPTOGRAPHY). Every wallet RPC that
--   generates/encrypts a token OR authenticates by hashing one is affected: mint,
--   register, get_build_context, list_updated, unregister. Each keeps its frozen
--   signature and FAILS CLOSED. Wallet is also dark (wallet.apple.enabled=false),
--   so the wallet_disabled refusal is the operative one today; the crypto park is
--   the second fence for when the kill switch flips. ZERO token material is
--   generated, hashed, encrypted, or stored on the parked path.
-- ============================================================================
create or replace function kernel.mint_wallet_pass(p_atom_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'wallet.apple.enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: wallet_disabled';   -- kill switch, NOT role-bypassable
  end if;
  raise exception 'precondition_failed: token_encryption_unavailable — wallet bearer-token crypto mechanism not yet ratified (PFA-20); mint is parked, no token is generated/hashed/encrypted';
end;
$$;

create or replace function kernel.register_wallet_pass_device(
  p_serial text, p_auth_token text, p_device_library_identifier text, p_push_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'wallet.apple.enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: wallet_disabled';
  end if;
  raise exception 'precondition_failed: token_encryption_unavailable — wallet bearer-token crypto mechanism not yet ratified (PFA-20); registration is parked, no token is hashed/encrypted';
end;
$$;

create or replace function kernel.get_wallet_pass_build_context(p_serial text, p_auth_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'wallet.apple.enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: wallet_disabled';
  end if;
  raise exception 'precondition_failed: token_encryption_unavailable — wallet token-auth crypto mechanism not yet ratified (PFA-20); serve is parked, no token is hashed/compared';
end;
$$;

create or replace function kernel.list_updated_wallet_passes(
  p_device_library_identifier text, p_auth_token text, p_since timestamptz)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'wallet.apple.enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: wallet_disabled';
  end if;
  raise exception 'precondition_failed: token_encryption_unavailable — wallet token-auth crypto mechanism not yet ratified (PFA-20); serve is parked, no token is hashed/compared';
end;
$$;

create or replace function kernel.unregister_wallet_pass_device(
  p_serial text, p_auth_token text, p_device_library_identifier text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'wallet.apple.enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: wallet_disabled';
  end if;
  raise exception 'precondition_failed: token_encryption_unavailable — wallet token-auth crypto mechanism not yet ratified (PFA-20); unregister is parked, no token is hashed/compared';
end;
$$;

-- ============================================================================
-- PART 12 — the non-crypto wallet lifecycle RPCs (buildable — no token auth/crypto).
--   These operate by wallet_pass_id / ticket_atom_id, never by a bearer token, so
--   they carry no crypto dependency. Inert today (no pass can be minted while the
--   crypto is parked), but structurally correct for when Wallet activates.
-- ============================================================================
-- supersede: mark the live pass(es) for an atom as superseded. Called from the
-- OUTBOX CONSUMER (never inside a custody txn) — Wallet can never block a transfer.
create or replace function kernel.supersede_wallet_passes_for_atom(p_atom_id uuid, p_reason_code text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_n integer;
begin
  update kernel.wallet_pass
     set status = 'superseded', status_reason_code = coalesce(p_reason_code, 'superseded'),
         last_updated_at = now()
   where ticket_atom_id = p_atom_id and status = 'issued';
  get diagnostics v_n = row_count;
  return jsonb_build_object('status','ok','superseded', v_n);
end;
$$;

create or replace function kernel.touch_wallet_pass(p_wallet_pass_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  update kernel.wallet_pass set last_updated_at = now() where wallet_pass_id = p_wallet_pass_id;
  return jsonb_build_object('status','ok');
end;
$$;

-- support path (leaked file / lost device): revoke a pass + unregister its devices.
create or replace function kernel.revoke_wallet_pass(
  p_wallet_pass_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid; v_status text;
begin
  v_uid := auth.uid();
  if not kernel.is_platform(array['platform_admin','platform_support']) then
    raise exception 'insufficient_privilege: platform_admin or platform_support required' using errcode = '42501';
  end if;
  select status into v_status from kernel.wallet_pass where wallet_pass_id = p_wallet_pass_id for update;
  if v_status is null then
    raise exception 'not_found: wallet_pass %', p_wallet_pass_id using errcode = 'P0002';
  end if;
  if v_status <> 'issued' then
    return jsonb_build_object('status','noop_replay');   -- already terminal
  end if;
  update kernel.wallet_pass set status = 'revoked', status_reason_code = coalesce(p_reason_code,'revoked'),
         last_updated_at = now() where wallet_pass_id = p_wallet_pass_id;
  update kernel.wallet_pass_device set unregistered_at = now()
   where wallet_pass_id = p_wallet_pass_id and unregistered_at is null;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(v_uid,'00000000-0000-0000-0000-0000000000f1'), 'wallet_pass.revoke', 'wallet_pass',
          p_wallet_pass_id, coalesce(p_reason_code,'revoked'),
          jsonb_build_object('status', v_status), jsonb_build_object('status','revoked'));
  return jsonb_build_object('status','ok');
end;
$$;

-- cron reconciliation: pass status follows the atom's terminal state. NOT load-bearing.
create or replace function kernel.sweep_wallet_pass_lifecycle()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_n integer;
begin
  update kernel.wallet_pass w
     set status = case t.state when 'scanned' then 'consumed'
                               when 'voided'  then 'invalidated'
                               when 'expired' then 'expired' end,
         status_reason_code = 'atom_' || t.state,
         last_updated_at = now()
    from kernel.tickets t
   where t.ticket_atom_id = w.ticket_atom_id
     and w.status = 'issued'
     and t.state in ('scanned','voided','expired');
  get diagnostics v_n = row_count;
  return jsonb_build_object('status','ok','reconciled', v_n);
end;
$$;

-- append an APNs push attempt to the AO ledger; update the device's push stats.
create or replace function kernel.record_wallet_push_result(
  p_wallet_pass_id uuid, p_registration_id uuid, p_trigger_kind text,
  p_cause_ref uuid, p_outcome text, p_apns_status integer, p_apns_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  insert into kernel.wallet_pass_push_log (wallet_pass_id, registration_id, trigger_kind,
                                           cause_ref, outcome, apns_status, apns_reason)
  values (p_wallet_pass_id, p_registration_id, p_trigger_kind, p_cause_ref, p_outcome, p_apns_status, p_apns_reason)
  on conflict (wallet_pass_id, trigger_kind, cause_ref, registration_id) do nothing;
  if p_registration_id is not null then
    if p_outcome = 'sent' then
      update kernel.wallet_pass_device set last_push_at = now(), last_push_result = p_outcome
       where registration_id = p_registration_id;
    elsif p_outcome in ('rejected','unregistered') then
      -- permanent APNs failure: unregister the device.
      update kernel.wallet_pass_device
         set unregistered_at = coalesce(unregistered_at, now()), last_push_at = now(),
             last_push_result = p_outcome, push_failure_count = push_failure_count + 1
       where registration_id = p_registration_id;
    else
      update kernel.wallet_pass_device set last_push_at = now(), last_push_result = p_outcome,
             push_failure_count = push_failure_count + 1
       where registration_id = p_registration_id;
    end if;
  end if;
  return jsonb_build_object('status','ok');
end;
$$;

-- ============================================================================
-- PART 13 — function EXECUTE grants
-- ============================================================================
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'kernel.provision_signing_key(text, uuid, text, text, timestamptz, text, text)',
    'kernel.rotate_signing_key(uuid, text, text, text, text)',
    'kernel.provision_pass_type_cert(text, text, text, text, text, timestamptz, timestamptz, text, text)',
    'kernel.rotate_pass_type_cert(uuid, text, text, text, timestamptz, timestamptz, text, text)',
    'kernel.revoke_pass_type_cert(uuid, text, text)',
    'kernel.issue_ticket_atoms(jsonb, text)',
    'kernel.mint_wallet_pass(uuid, text)',
    'kernel.register_wallet_pass_device(text, text, text, text)',
    'kernel.get_wallet_pass_build_context(text, text)',
    'kernel.list_updated_wallet_passes(text, text, timestamptz)',
    'kernel.unregister_wallet_pass_device(text, text, text)',
    'kernel.supersede_wallet_passes_for_atom(uuid, text)',
    'kernel.touch_wallet_pass(uuid)',
    'kernel.revoke_wallet_pass(uuid, text, text)',
    'kernel.sweep_wallet_pass_lifecycle()',
    'kernel.record_wallet_push_result(uuid, uuid, text, uuid, text, integer, text)',
    'venue.append_door_manifest_delta(uuid, uuid[], text, uuid)'
    -- kernel.deletion_blockers_wallet keeps its 077 grant (definer, no client EXEC).
  ];
  -- caller-authorized (fan): mint_wallet_pass. Credential lifecycle is EDGE-FRONTED
  -- (G-7) — authenticated at the edge; the parked bodies fail closed regardless.
  v_auth constant text[] := array[
    'kernel.mint_wallet_pass(uuid, text)',
    'kernel.revoke_wallet_pass(uuid, text, text)',
    'kernel.provision_signing_key(text, uuid, text, text, timestamptz, text, text)',
    'kernel.rotate_signing_key(uuid, text, text, text, text)',
    'kernel.provision_pass_type_cert(text, text, text, text, text, timestamptz, timestamptz, text, text)',
    'kernel.rotate_pass_type_cert(uuid, text, text, text, timestamptz, timestamptz, text, text)',
    'kernel.revoke_pass_type_cert(uuid, text, text)'
  ];
  -- machine-only (edge web-service / outbox consumer / cron / mint leg).
  v_svc constant text[] := array[
    'kernel.issue_ticket_atoms(jsonb, text)',
    'kernel.register_wallet_pass_device(text, text, text, text)',
    'kernel.get_wallet_pass_build_context(text, text)',
    'kernel.list_updated_wallet_passes(text, text, timestamptz)',
    'kernel.unregister_wallet_pass_device(text, text, text)',
    'kernel.supersede_wallet_passes_for_atom(uuid, text)',
    'kernel.touch_wallet_pass(uuid)',
    'kernel.sweep_wallet_pass_lifecycle()',
    'kernel.record_wallet_push_result(uuid, uuid, text, uuid, text, integer, text)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
  end loop;
  foreach v_fn in array v_auth loop
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
  foreach v_fn in array v_svc loop
    execute format('grant execute on function %s to service_role', v_fn);
  end loop;
end $$;

commit;
