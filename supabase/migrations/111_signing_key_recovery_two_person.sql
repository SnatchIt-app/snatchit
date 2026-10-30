-- ============================================================================
-- 111_signing_key_recovery_two_person.sql — E4 (PFA-18C maturity trigger):
-- the GATED, TWO-PERSON post-revoke re-bootstrap path for the global signing
-- key. Replaces migration 110's rule 10 ("post_revoke_recovery_parked", fail
-- closed, no mechanism) with "permitted iff TWO distinct platform_admin+aal2
-- approvals for THIS key_id AND THIS public-key fingerprint are recorded in a
-- durable, append-only approval table and are unexpired (30-minute window)".
-- Everything else 110 enforces is preserved byte-for-byte in semantics.
--
-- WHAT THIS MIGRATION IS. LOCAL / REHEARSAL ARTIFACT — NOT DEPLOYED, NOT
-- APPLIED TO PRODUCTION. Adds ONE kernel table (append-only, no client access),
-- THREE kernel functions (pure fingerprint helper, approve, execute) and
-- RE-CREATES 110's guard (rule 10 only). No public-schema object; Gate-2
-- untouched. Census: +1 kernel table (31→32; five-schema relations 78→79),
-- +3 kernel fns (150→153; five-schema routines 289→292), +1 trigger on the new
-- table (the shared 076 kernel.raise_append_only — no new trigger function),
-- 0 policies. Next migration after 110.
--
-- ── WHY A DEDICATED TABLE, NOT kernel.approval_request ───────────────────────
-- kernel.approval_request (077:267-297) is the repository's established dual-
-- control substrate and its separation-of-duties design is copied here
-- (distinct identities, bounded expiry, command idempotency). It is NOT reused
-- because its `action` / `subject_kind` CHECK constraints are frozen money
-- vocabularies ('refund.issue','payout.request','config.set_money_key' /
-- 'order','settlement','config_key'); extending them would alter 077's
-- immutable semantics and every money function that lists/approves those rows.
-- A signing-key trust-root decision is a different authority domain.
--
-- ── PRECONDITIONS (both functions AND the guard, under the same advisory lock) ─
--   • zero active|rotating global keys            (else active_global_exists)
--   • EXACTLY ONE revoked global key               (0 ⇒ recovery_not_applicable:
--     that is initial-bootstrap territory — use the §6.1 ceremony, this path
--     can never create the first key; >1 ⇒ recovery_lineage_exceeded: a
--     second-generation recovery is beyond the ratified lineage and needs its
--     own ratification + migration — NOT silently widened here)
--   • the proposed key_id does not exist            (else duplicate_key_id)
--
-- ── TWO-PERSON CONTROL ───────────────────────────────────────────────────────
--   approve_signing_key_recovery(key_id, fingerprint, reason, command_key):
--     platform_admin (kernel.is_platform) on an aal2 session (106 idiom, verbatim);
--     one unexpired approval per identity per (key_id, fingerprint)
--     (duplicate_approver); replay of the same identity+command_key is a
--     no-op; a reused command_key for a different proposal is refused.
--   execute_signing_key_recovery(key_id, public_key PEM, kms ARN, reason, command_key):
--     platform_admin+aal2; the CALLER MUST BE ONE OF THE APPROVERS
--     (executor_not_approver) — a third principal cannot drive the insert;
--     the fingerprint of the supplied PEM must equal the approved fingerprint
--     (fingerprint_mismatch); inserts the row (algorithm 'ES256' EXPLICIT,
--     scope global, status active, not_after NULL) — the re-created guard then
--     re-validates EVERYTHING (scope, status, ES256, ARN, PEM/P-256, private
--     material, duplicate, zero-active, exactly-one-revoked, two approvals).
--   The guard is the authority: a bare superuser INSERT with two valid
--   approvals also passes (the approvals ARE the control); one without them
--   is refused post_revoke_recovery_unapproved. There is no role, GUC, config
--   or env override anywhere in this path.
--
-- ── NOT A SINGLE-FOUNDER BYPASS ──────────────────────────────────────────────
--   Two DISTINCT auth identities, each platform_admin, each on its own aal2
--   session, are required; the same identity approving twice is refused and
--   the session id of each approval is recorded as evidence. RESIDUAL
--   (disclosed): one human controlling two admin identities defeats
--   distinctness — that is the same residual every two-account scheme has and
--   is DETECTABLE (admin_audit rows name both identities and sessions), not
--   preventable, consistent with PFA-18C's stated guarantee. The maturity
--   trigger's organisational half ("a second qualified operator exists") is
--   governance, not code.
--
-- ── INITIAL BOOTSTRAP UNAFFECTED ─────────────────────────────────────────────
--   On an EMPTY keyring the guard ignores approvals entirely (rule 11: the
--   first row must be the ruling-B key_id …b0) and approve() refuses
--   recovery_not_applicable. PFA-18A provision/rotate stay parked; PFA-18B
--   revoke (106) is untouched.
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — pure fingerprint helper. Returns the D5 fingerprint (lowercase hex
-- SHA-256 over the DER SPKI) IFF the text is exactly one SPKI PUBLIC KEY PEM
-- block that decodes to the 91-byte uncompressed P-256 SubjectPublicKeyInfo and
-- carries no private material; otherwise NULL. Never raises. Zero-grant.
-- ============================================================================
create or replace function kernel.signing_key_p256_pem_fingerprint(p_pem text)
returns text language plpgsql immutable strict security definer set search_path = ''
as $$
declare
  c_p256_prefix constant bytea := decode('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
  v_body text;
  v_der  bytea;
begin
  if position('PRIVATE KEY' in p_pem) > 0 then return null; end if;
  v_body := substring(p_pem from '^[[:space:]]*-----BEGIN PUBLIC KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-----END PUBLIC KEY-----[[:space:]]*$');
  if v_body is null then return null; end if;
  begin
    v_der := decode(regexp_replace(v_body, '[\r\n]', '', 'g'), 'base64');
  exception when others then
    return null;
  end;
  if v_der is null or length(v_der) <> 91
     or substring(v_der from 1 for 26) <> c_p256_prefix
     or get_byte(v_der, 26) <> 4 then
    return null;
  end if;
  return encode(sha256(v_der), 'hex');
end;
$$;
revoke all on function kernel.signing_key_p256_pem_fingerprint(text) from public, anon, authenticated, service_role;
comment on function kernel.signing_key_p256_pem_fingerprint(text) is
  'E4/M6: D5 fingerprint (sha256 over DER SPKI, lowercase hex) of exactly one uncompressed-P-256 SPKI PEM block; NULL for anything else. Pure, never raises.';

-- ============================================================================
-- PART 2 — the durable approval table. APPEND-ONLY. NO CLIENT ACCESS.
-- ============================================================================
create table if not exists kernel.signing_key_recovery_approval (
  approval_id            uuid primary key default gen_random_uuid(),
  key_id                 uuid not null,
  public_key_fingerprint text not null check (public_key_fingerprint ~ '^[0-9a-f]{64}$'),
  approver_identity      uuid not null references auth.users(id) on delete restrict,
  approver_aal           text not null check (approver_aal = 'aal2'),
  approver_session       text,                                   -- jwt session_id claim, evidence only
  reason_code            text not null check (reason_code ~ '^[A-Za-z0-9._:-]{1,64}$'),
  command_key            text not null check (command_key ~ '^[A-Za-z0-9._:-]{1,64}$'),
  approved_at            timestamptz not null default now(),
  expires_at             timestamptz not null,
  created_at             timestamptz not null default now(),
  constraint signing_key_recovery_approval_window_ck
    check (expires_at > approved_at and expires_at <= approved_at + interval '30 minutes'),
  constraint signing_key_recovery_approval_command_uq unique (approver_identity, command_key)
);
create index if not exists signing_key_recovery_approval_proposal_idx
  on kernel.signing_key_recovery_approval (key_id, public_key_fingerprint, expires_at);

alter table kernel.signing_key_recovery_approval enable row level security;
revoke all on kernel.signing_key_recovery_approval from public, anon, authenticated, service_role;
-- No policy on purpose: RLS-enabled + zero policies + zero grants ⇒ no client or
-- service_role path at all. Only the SECURITY DEFINER functions below (owner)
-- and a superuser can read or write it.

drop trigger if exists tg_signing_key_recovery_approval_append_only on kernel.signing_key_recovery_approval;
create trigger tg_signing_key_recovery_approval_append_only
  before update or delete on kernel.signing_key_recovery_approval
  for each row execute function kernel.raise_append_only();

comment on table kernel.signing_key_recovery_approval is
  'E4 (PFA-18C maturity trigger): append-only record of platform_admin+aal2 approvals for a post-revoke global signing-key recovery, keyed by (key_id, D5 public-key fingerprint). Two DISTINCT identities within the 30-minute window are required by kernel.guard_signing_key_insert. No client/service_role access; RLS on, no policies.';

-- ============================================================================
-- PART 3 — approve. One call per approver. Serialized with the guard's lock.
-- ============================================================================
create or replace function kernel.approve_signing_key_recovery(
  p_key_id uuid, p_public_key_fingerprint text, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  c_window   constant interval := interval '30 minutes';
  v_uid      uuid := auth.uid();
  v_claims   jsonb;
  v_aal      text;
  v_session  text;
  v_active   integer;
  v_revoked  integer;
  v_prev     kernel.signing_key_recovery_approval%rowtype;
  v_id       uuid;
  v_count    integer;
  v_expires  timestamptz;
begin
  -- (1) authz — platform_admin on an aal2 session (106 idiom, verbatim).
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin only (E4: signing-key recovery approval)' using errcode = '42501';
  end if;
  v_claims := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb;
  v_aal := v_claims ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to approve a signing-key recovery';
  end if;
  v_session := v_claims ->> 'session_id';

  -- (2) inputs.
  if p_key_id is null then
    raise exception 'invalid_input: key_id required';
  end if;
  if p_public_key_fingerprint is null or p_public_key_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_input: public_key_fingerprint must be 64 lowercase hex chars (D5: sha256 over DER SPKI)';
  end if;
  if p_reason_code is null or p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;

  -- (3) serialize with every other keyring writer (same lock as the guard).
  perform pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'));

  -- (4) idempotent replay: same identity + same command_key ⇒ the original approval.
  select * into v_prev from kernel.signing_key_recovery_approval
   where approver_identity = v_uid and command_key = p_command_key;
  if found then
    if v_prev.key_id = p_key_id and v_prev.public_key_fingerprint = p_public_key_fingerprint then
      select count(distinct approver_identity) into v_count from kernel.signing_key_recovery_approval
       where key_id = p_key_id and public_key_fingerprint = p_public_key_fingerprint and expires_at > now();
      return jsonb_build_object('status','noop_replay','approval_id', v_prev.approval_id, 'key_id', p_key_id,
                                'approvals', v_count, 'expires_at', v_prev.expires_at);
    end if;
    raise exception 'signing_key_recovery_refused: command_key_reused — this command_key already approved a different proposal';
  end if;

  -- (5) preconditions — this path can NEVER create the first key and NEVER a
  -- second-generation one.
  if exists (select 1 from kernel.signing_key k where k.key_id = p_key_id) then
    raise exception 'signing_key_recovery_refused: duplicate_key_id — a signing_key row with this key_id already exists (append-only; revoked rows are never re-used)';
  end if;
  select count(*) into v_active  from kernel.signing_key k where k.scope = 'global' and k.status in ('active','rotating');
  select count(*) into v_revoked from kernel.signing_key k where k.scope = 'global' and k.status = 'revoked';
  if v_active > 0 then
    raise exception 'signing_key_recovery_refused: active_global_exists — recovery applies only after a revoke has left zero active global keys';
  end if;
  if v_revoked = 0 then
    raise exception 'signing_key_recovery_refused: recovery_not_applicable — no revoked global key exists; the INITIAL bootstrap is the §6.1 ceremony, never this path';
  end if;
  if v_revoked > 1 then
    raise exception 'signing_key_recovery_refused: recovery_lineage_exceeded — more than one revoked global key; a second-generation recovery is beyond the ratified lineage and requires its own ratification + migration';
  end if;

  -- (6) one UNEXPIRED approval per identity per proposal.
  if exists (select 1 from kernel.signing_key_recovery_approval a
              where a.key_id = p_key_id and a.public_key_fingerprint = p_public_key_fingerprint
                and a.approver_identity = v_uid and a.expires_at > now()) then
    raise exception 'signing_key_recovery_refused: duplicate_approver — this identity already holds an unexpired approval for this proposal; the SECOND approval must come from a DIFFERENT platform_admin';
  end if;

  -- (7) record.
  v_expires := now() + c_window;
  insert into kernel.signing_key_recovery_approval
    (key_id, public_key_fingerprint, approver_identity, approver_aal, approver_session, reason_code, command_key, approved_at, expires_at)
  values (p_key_id, p_public_key_fingerprint, v_uid, 'aal2', v_session, p_reason_code, p_command_key, now(), v_expires)
  returning approval_id into v_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'signing_key.recovery_approve', 'signing_key', p_key_id, p_reason_code,
          jsonb_build_object('revoked_global', v_revoked, 'active_global', v_active),
          jsonb_build_object('approval_id', v_id, 'fingerprint', p_public_key_fingerprint, 'expires_at', v_expires,
                             'session', v_session, 'command_key', p_command_key));

  select count(distinct approver_identity) into v_count from kernel.signing_key_recovery_approval
   where key_id = p_key_id and public_key_fingerprint = p_public_key_fingerprint and expires_at > now();
  return jsonb_build_object('status','approved','approval_id', v_id, 'key_id', p_key_id,
                            'approvals', v_count, 'expires_at', v_expires);
end;
$$;
revoke all on function kernel.approve_signing_key_recovery(uuid,text,text,text) from public, anon, service_role;
grant execute on function kernel.approve_signing_key_recovery(uuid,text,text,text) to authenticated;
comment on function kernel.approve_signing_key_recovery(uuid,text,text,text) is
  'E4: records ONE platform_admin+aal2 approval for a post-revoke global signing-key recovery proposal (key_id + D5 fingerprint), valid 30 minutes. Preconditions: zero active global, exactly one revoked global, key_id unused. Same identity twice ⇒ duplicate_approver. Never inserts a key.';

-- ============================================================================
-- PART 4 — execute. Caller must be one of the (≥2 distinct) approvers.
-- ============================================================================
create or replace function kernel.execute_signing_key_recovery(
  p_key_id uuid, p_public_key text, p_kms_handle_ref text, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_aal       text;
  v_fp        text;
  v_active    integer;
  v_revoked   integer;
  v_approvers uuid[];
  v_existing  kernel.signing_key%rowtype;
begin
  -- (1) authz — platform_admin + aal2.
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin only (E4: signing-key recovery execution)' using errcode = '42501';
  end if;
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to execute a signing-key recovery';
  end if;

  -- (2) inputs. The PEM/ARN are re-validated by the guard; the fingerprint is
  -- derived here so a mismatch against the APPROVED fingerprint is named.
  if p_key_id is null then
    raise exception 'invalid_input: key_id required';
  end if;
  if p_reason_code is null or p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;
  v_fp := kernel.signing_key_p256_pem_fingerprint(p_public_key);
  if v_fp is null then
    raise exception 'signing_key_recovery_refused: public_key_not_p256_spki_pem — public_key must be exactly one SPKI PUBLIC KEY PEM block of an uncompressed P-256 key with no private material';
  end if;
  if p_kms_handle_ref is null or p_kms_handle_ref !~ '^arn:aws:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'signing_key_recovery_refused: kms_handle_not_key_arn — kms_handle_ref must be a full AWS KMS key ARN';
  end if;

  -- (3) serialize (same lock as approve + the guard; advisory xact locks are re-entrant).
  perform pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'));

  -- (4) idempotent replay: the SAME actor + command_key already recovered THIS key with THIS fingerprint.
  select * into v_existing from kernel.signing_key where key_id = p_key_id;
  if found then
    if v_existing.scope = 'global'
       and kernel.signing_key_p256_pem_fingerprint(v_existing.public_key) = v_fp
       and exists (select 1 from kernel.admin_audit au
                    where au.action = 'signing_key.recovery_execute' and au.subject_id = p_key_id
                      and au.actor_identity = v_uid and au.after ->> 'command_key' = p_command_key) then
      return jsonb_build_object('status','noop_replay','key_id', p_key_id, 'key_status', v_existing.status, 'fingerprint', v_fp);
    end if;
    raise exception 'signing_key_recovery_refused: duplicate_key_id — a signing_key row with this key_id already exists';
  end if;

  -- (5) preconditions (the guard re-checks them; named here for the caller).
  select count(*) into v_active  from kernel.signing_key k where k.scope = 'global' and k.status in ('active','rotating');
  select count(*) into v_revoked from kernel.signing_key k where k.scope = 'global' and k.status = 'revoked';
  if v_active > 0 then
    raise exception 'signing_key_recovery_refused: active_global_exists — an active global key exists; recovery applies only after a revoke';
  end if;
  if v_revoked = 0 then
    raise exception 'signing_key_recovery_refused: recovery_not_applicable — no revoked global key; the INITIAL bootstrap is the §6.1 ceremony, never this path';
  end if;
  if v_revoked > 1 then
    raise exception 'signing_key_recovery_refused: recovery_lineage_exceeded — more than one revoked global key; requires its own ratification + migration';
  end if;

  -- (6) two DISTINCT unexpired approvals for THIS key_id + THIS fingerprint; caller must be one of them.
  select array_agg(distinct a.approver_identity) into v_approvers
    from kernel.signing_key_recovery_approval a
   where a.key_id = p_key_id and a.public_key_fingerprint = v_fp and a.approver_aal = 'aal2' and a.expires_at > now();
  if coalesce(cardinality(v_approvers), 0) < 2 then
    -- Distinguish a wrong-key from a missing-approval: if approvals exist for
    -- this key_id under ANOTHER fingerprint, the supplied PEM is not the
    -- approved one.
    if exists (select 1 from kernel.signing_key_recovery_approval a
                where a.key_id = p_key_id and a.public_key_fingerprint <> v_fp and a.expires_at > now()) then
      raise exception 'signing_key_recovery_refused: fingerprint_mismatch — the supplied public key does not match the fingerprint the approvers approved';
    end if;
    raise exception 'signing_key_recovery_refused: post_revoke_recovery_unapproved — two distinct unexpired platform_admin+aal2 approvals for this key_id and fingerprint are required (30-minute window)';
  end if;
  if not (v_uid = any(v_approvers)) then
    raise exception 'signing_key_recovery_refused: executor_not_approver — only one of the approving platform_admins may execute the recovery';
  end if;

  -- (7) the insert — algorithm ES256 EXPLICIT; the guard re-validates everything.
  insert into kernel.signing_key
    (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  values (p_key_id, 'global', null, null, p_public_key, p_kms_handle_ref, 'ES256', 'active', now(), null);

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'signing_key.recovery_execute', 'signing_key', p_key_id, p_reason_code,
          jsonb_build_object('revoked_global', v_revoked, 'active_global', v_active),
          jsonb_build_object('fingerprint', v_fp, 'approvers', cardinality(v_approvers), 'command_key', p_command_key));

  return jsonb_build_object('status','recovered','key_id', p_key_id, 'fingerprint', v_fp, 'approvals', cardinality(v_approvers));
end;
$$;
revoke all on function kernel.execute_signing_key_recovery(uuid,text,text,text,text) from public, anon, service_role;
grant execute on function kernel.execute_signing_key_recovery(uuid,text,text,text,text) to authenticated;
comment on function kernel.execute_signing_key_recovery(uuid,text,text,text,text) is
  'E4: inserts the recovery global key (ES256 explicit) IFF two distinct unexpired platform_admin+aal2 approvals exist for this key_id + the D5 fingerprint of the supplied PEM, the caller is one of the approvers, zero active and exactly one revoked global key exist. The 110/111 guard re-validates everything.';

-- ============================================================================
-- PART 5 — re-create the guard: rule 10 becomes the two-person check. Rules
-- 1-9 and 11 are byte-identical in semantics to migration 110.
-- ============================================================================
create or replace function kernel.guard_signing_key_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  c_bootstrap_key constant uuid  := '00000000-0000-0000-0000-0000000000b0';
  c_p256_prefix   constant bytea := decode('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
  v_body      text;
  v_der       bytea;
  v_fp        text;
  v_revoked   integer;
  v_approvers integer;
begin
  -- 1 scope
  if new.scope is distinct from 'global' then
    raise exception 'signing_key_insert_refused: scoped_key_parked — per_event/per_venue keys are written only by kernel.provision_signing_key / rotate_signing_key, which are parked (PFA-18A); a scoped row would shadow the global key at the next mint (093 resolver), so no scoped INSERT path exists'
      using errcode = 'P0001';
  end if;
  -- 2 status
  if new.status is distinct from 'active' then
    raise exception 'signing_key_insert_refused: status_must_be_active — a signing key is inserted active; rotating/revoked are lifecycle states written by the (parked) lifecycle functions'
      using errcode = 'P0001';
  end if;
  -- 3 algorithm — no override of any kind
  if new.algorithm is distinct from 'ES256' then
    raise exception 'signing_key_insert_refused: algorithm_not_es256 — the ratified bootstrap contract is AWS KMS / ES256 (D2, PFA-PT-8); algorithm must be supplied explicitly as ES256'
      using errcode = 'P0001';
  end if;
  -- 4 kms_handle_ref
  if new.kms_handle_ref !~ '^arn:aws:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'signing_key_insert_refused: kms_handle_not_key_arn — kms_handle_ref must be a full AWS KMS key ARN (arn:aws:kms:<region>:<12-digit account>:key/<uuid>)'
      using errcode = 'P0001';
  end if;
  -- 5 private material
  if position('PRIVATE KEY' in new.public_key) > 0 then
    raise exception 'signing_key_insert_refused: public_key_private_material — public_key contains PRIVATE KEY material; stop the ceremony'
      using errcode = 'P0001';
  end if;
  -- 6 public_key: exactly one SPKI PEM block, 91-byte uncompressed P-256 SPKI
  v_body := substring(new.public_key from '^[[:space:]]*-----BEGIN PUBLIC KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-----END PUBLIC KEY-----[[:space:]]*$');
  if v_body is null then
    raise exception 'signing_key_insert_refused: public_key_not_spki_pem — public_key must be exactly one -----BEGIN PUBLIC KEY----- … -----END PUBLIC KEY----- block (SPKI PEM, D3)'
      using errcode = 'P0001';
  end if;
  begin
    v_der := decode(regexp_replace(v_body, '[\r\n]', '', 'g'), 'base64');
  exception when others then
    v_der := null;
  end;
  if v_der is null or length(v_der) <> 91
     or substring(v_der from 1 for 26) <> c_p256_prefix
     or get_byte(v_der, 26) <> 4 then
    raise exception 'signing_key_insert_refused: public_key_not_p256_uncompressed — the PEM must decode to the 91-byte uncompressed P-256 SubjectPublicKeyInfo (id-ecPublicKey / prime256v1 / 0x04 point) that ES256 verification pins'
      using errcode = 'P0001';
  end if;
  -- 7 serialize
  perform pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'));
  -- 8 duplicate key_id
  if exists (select 1 from kernel.signing_key k where k.key_id = new.key_id) then
    raise exception 'signing_key_insert_refused: duplicate_key_id — a signing_key row with this key_id already exists (append-only: revoked rows are never re-used)'
      using errcode = 'P0001';
  end if;
  -- 9 exactly one active global
  if exists (select 1 from kernel.signing_key k where k.scope = 'global' and k.status in ('active','rotating')) then
    raise exception 'signing_key_insert_refused: active_global_exists — exactly one active global signing key is permitted; rotation/replacement of a live key is parked (PFA-18A) and revocation (PFA-18B) is the only lifecycle transition'
      using errcode = 'P0001';
  end if;
  -- 10 (E4, migration 111) post-revoke recovery — TWO-PERSON GATED.
  select count(*) into v_revoked from kernel.signing_key k where k.scope = 'global' and k.status = 'revoked';
  if v_revoked > 0 then
    if v_revoked > 1 then
      raise exception 'signing_key_insert_refused: recovery_lineage_exceeded — more than one revoked global key; a second-generation recovery is beyond the ratified lineage and requires its own ratification + migration'
        using errcode = 'P0001';
    end if;
    v_fp := encode(sha256(v_der), 'hex');
    select count(distinct a.approver_identity) into v_approvers
      from kernel.signing_key_recovery_approval a
     where a.key_id = new.key_id and a.public_key_fingerprint = v_fp
       and a.approver_aal = 'aal2' and a.expires_at > now();
    if coalesce(v_approvers, 0) < 2 then
      raise exception 'signing_key_insert_refused: post_revoke_recovery_unapproved — re-bootstrap after a revoke requires TWO distinct platform_admin+aal2 approvals (kernel.approve_signing_key_recovery) for this key_id AND this public-key fingerprint, both unexpired (30-minute window) — E4 / PFA-18C maturity trigger'
        using errcode = 'P0001';
    end if;
    return new;  -- the approved recovery row; rule 11 is for the FIRST row only
  end if;
  -- 11 lineage — the first-ever global row is the ruling-B bootstrap key_id
  if new.key_id <> c_bootstrap_key then
    raise exception 'signing_key_insert_refused: bootstrap_key_id_required — the initial global trust root must carry the sanctioned bootstrap key_id (ruling B, ceremony §6.1); any other key_id is not the ratified lineage'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function kernel.guard_signing_key_insert() from public, anon, authenticated, service_role;
comment on function kernel.guard_signing_key_insert() is
  'M6 (110) + E4 (111): BEFORE INSERT guard on kernel.signing_key. Rules 1-9/11 as 110; rule 10 now permits a post-revoke recovery row IFF exactly one revoked global exists, zero active, and TWO distinct unexpired platform_admin+aal2 approvals (kernel.signing_key_recovery_approval) match this key_id and the D5 fingerprint of the inserted PEM. No GUC/config/role override.';

commit;
