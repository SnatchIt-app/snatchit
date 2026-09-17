-- ============================================================================
-- 110_signing_key_insert_guard.sql — M6 (PFA-18C, REQUIRED BEFORE ISSUANCE):
-- a BEFORE INSERT guard on kernel.signing_key that makes the RATIFIED global
-- ES256 bootstrap lineage the ONLY thing an INSERT can ever produce while the
-- PFA-18A provision/rotate lifecycle and the post-revoke recovery path remain
-- parked. It closes P1-ALGO-DEFAULT (the 103 `algorithm` column default
-- 'EdDSA' can no longer survive an INSERT) and P1-REBOOTSTRAP-FAILOPEN (a bare
-- superuser INSERT after a revoke no longer succeeds — it FAILS CLOSED until the
-- gated two-person recovery mechanism is ratified and shipped by migration).
--
-- WHAT THIS MIGRATION IS. LOCAL / REHEARSAL ARTIFACT — NOT DEPLOYED, NOT
-- APPLIED TO PRODUCTION. 093–109 IMMUTABLE (LIVE-but-DARK in production). This
-- migration adds ONE kernel trigger function and ONE trigger on
-- kernel.signing_key. No public-schema object, Gate-2 untouched. Census:
-- +1 kernel fn, +1 trigger on kernel.signing_key. Next migration after 109.
-- The immutable BEFORE UPDATE guard (083, re-created by 103) is UNTOUCHED.
-- kernel.provision_signing_key / rotate_signing_key (083:375-393) stay parked
-- and UNTOUCHED. kernel.revoke_signing_key (106) UNTOUCHED.
--
-- ── SOURCES READ, NOT ASSUMED ────────────────────────────────────────────────
-- 083:49-80 (DDL: scope/status CHECKs, scope_target_ck, window_ck, the three
--   partial unique indexes incl. signing_key_active_global_uq); 083:375-393
--   (provision/rotate PARKED — raise dual_control_unavailable, ZERO writes);
-- 093:4950-4966 (the mint resolver: most-specific-first per_event > per_venue >
--   global, active + in-window); 103:69-86 (immutable UPDATE guard; status
--   forward-only; algorithm immutable); 106:174-177 (revoke sets status only);
-- PRODUCTION_SIGNING_KMS_CEREMONY.md §6.1 (the ONLY sanctioned INSERT: key_id
--   …b0 = ruling B, scope global, algorithm ES256 EXPLICIT, status active,
--   not_after NULL per D6, public_key = SPKI PEM per D3, kms_handle_ref = full
--   AWS KMS key ARN per D4); PFA_18C_REMEDIATION_AND_FINAL_RATIFICATION.md (M6:
--   "BEFORE INSERT scope/algorithm guard"; P1-REBOOTSTRAP-FAILOPEN: "a GATED
--   post-revoke re-bootstrap artifact … TWO-PERSON-MANDATORY post-T3. Until it
--   exists, post-T3 recovery has NO compliant mechanism").
--
-- ── THE RULES, IN CHECK ORDER (each has a pgTAP case in suite 176) ───────────
--   1 scope <> 'global'                        → scoped_key_parked          (Q7 below)
--   2 status <> 'active'                       → status_must_be_active
--   3 algorithm <> 'ES256'                     → algorithm_not_es256        (no bypass, no GUC)
--   4 kms_handle_ref not a full AWS KMS key ARN
--     (region, 12-digit account, key UUID)     → kms_handle_not_key_arn
--   5 public_key contains 'PRIVATE KEY'        → public_key_private_material
--   6 public_key not exactly one SPKI PUBLIC KEY PEM block whose DER is the
--     91-byte uncompressed P-256 SubjectPublicKeyInfo
--                                              → public_key_not_spki_pem /
--                                                public_key_not_p256_uncompressed
--   7 (serialize global inserts: pg_advisory_xact_lock)
--   8 key_id already present                   → duplicate_key_id
--   9 an active|rotating global row exists     → active_global_exists       (exactly one active)
--  10 a revoked global row exists, none active → post_revoke_recovery_parked (FAIL CLOSED)
--  11 no global row exists and key_id <> …b0   → bootstrap_key_id_required  (lineage)
-- Nothing in this function reads a session GUC, a config key, a role name, or
-- an env-shaped value. The ONLY way to change what it permits is a MIGRATION.
--
-- ── Q7 — SCOPED ROWS: REJECTED OUTRIGHT WHILE PROVISION/ROTATE ARE PARKED ────
-- Decision: rule 1 refuses EVERY non-global insert, unconditionally. Not a
-- "future-safe predicate" (a config flag / GUC / role test) — that would be a
-- runtime bypass of exactly the kind item 4 forbids, and there is nothing for a
-- predicate to test: the only sanctioned writers of scoped keys are
-- kernel.provision_signing_key / rotate_signing_key, and both raise
-- dual_control_unavailable BEFORE any write (083:375-393). Why the refusal must
-- be absolute rather than merely "discouraged": the mint resolver
-- (093:4954-4966) is most-specific-first, so a scoped row with a valid window
-- SHADOWS the global key for that event/venue at the very next mint, silently
-- re-pointing issuance at key material nobody ceremonied; the monitor (099)
-- treats any scoped row as the scope-shadowing signal (§9.3 ADV-7 scoped_keys).
-- When PFA-18A is un-parked, THAT migration re-creates provision/rotate with
-- real bodies AND amends this guard (e.g. permitting scoped inserts only from
-- those definer bodies, verified by a lock/GUC the definer sets itself) — a
-- reviewed migration, never a runtime switch.
--
-- ── RECOVERY CONFLICT ANALYSIS (item 6) — NO CONFLICT, FAIL CLOSED ──────────
-- The governance requirement: post-revoke recovery MUST be two-person and
-- MUST fail closed when no second qualified operator exists; today "the ONLY
-- post-revoke recovery path is a bare superuser INSERT, which has neither
-- two-person enforcement NOR fail-closed". Rule 10 IS that fail-closed. It does
-- not encode a two-person check (there is no ratified mechanism to check —
-- inventing one here would be a bypass); it parks the path, exactly as
-- provision/rotate are parked, with a code that names the un-park contract:
-- the E4 migration that ships the gated two-person recovery artifact (e.g. two
-- distinct platform_admin+aal2 approvals recorded in a kernel.ceremony_approval
-- table within a window) REPLACES rule 10 with "permitted iff that approval
-- record exists for NEW.key_id". Until then a valid-looking replacement row is
-- refused even by a superuser — which is the requirement, not a conflict.
-- Rule 11 (lineage) means the FIRST global row is always the ruling-B key_id
-- …b0 that the §6.1 artifact writes; later global rows exist only via rule 10's
-- future un-park, so "the sanctioned bootstrap key_id lineage" is enforced.
--
-- ── CONCURRENCY (item 8) ─────────────────────────────────────────────────────
-- Rule 7 takes pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'))
-- BEFORE the existence checks, so two concurrent global inserts serialize
-- inside the trigger: the second waits for the first transaction to end and its
-- SELECTs (new statement, new READ COMMITTED snapshot) then see the committed
-- row → active_global_exists (a clean refusal) rather than a race. The partial
-- unique index signing_key_active_global_uq (083) remains as defense in depth;
-- the PRIMARY KEY covers duplicate key_id if the explicit rule 8 is ever
-- bypassed. Everything is BEFORE ROW, so a refusal aborts the statement and the
-- enclosing transaction rolls back with no partial write. A revoke + replacement
-- in one transaction: the UPDATE to 'revoked' is visible to the INSERT's trigger
-- (same transaction) → rule 10 refuses the replacement (parked) — correct.
-- ============================================================================
begin;

create or replace function kernel.guard_signing_key_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  c_bootstrap_key constant uuid  := '00000000-0000-0000-0000-0000000000b0';
  -- SEQUENCE(89){ AlgorithmIdentifier{ id-ecPublicKey, prime256v1 }, BIT STRING(66, 0 unused) }
  c_p256_prefix   constant bytea := decode('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
  v_body text;
  v_der  bytea;
begin
  -- 1 scope — only global rows can be inserted while provision/rotate are parked.
  if new.scope is distinct from 'global' then
    raise exception 'signing_key_insert_refused: scoped_key_parked — per_event/per_venue keys are written only by kernel.provision_signing_key / rotate_signing_key, which are parked (PFA-18A); a scoped row would shadow the global key at the next mint (093 resolver), so no scoped INSERT path exists'
      using errcode = 'P0001';
  end if;

  -- 2 status — an inserted key is born active; 'rotating' is rotation (parked), 'revoked' is a terminal state reached only by revoke.
  if new.status is distinct from 'active' then
    raise exception 'signing_key_insert_refused: status_must_be_active — a signing key is inserted active; rotating/revoked are lifecycle states written by the (parked) lifecycle functions'
      using errcode = 'P0001';
  end if;

  -- 3 algorithm — the ratified ES256 contract (D2). The 103 column default 'EdDSA'
  --   can never survive an INSERT; there is deliberately NO override of any kind.
  if new.algorithm is distinct from 'ES256' then
    raise exception 'signing_key_insert_refused: algorithm_not_es256 — the ratified bootstrap contract is AWS KMS / ES256 (D2, PFA-PT-8); algorithm must be supplied explicitly as ES256'
      using errcode = 'P0001';
  end if;

  -- 4 kms_handle_ref — a FULL AWS KMS key ARN (D4): region, 12-digit account, key UUID. Never an alias, bare id, or placeholder.
  if new.kms_handle_ref !~ '^arn:aws:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'signing_key_insert_refused: kms_handle_not_key_arn — kms_handle_ref must be a full AWS KMS key ARN (arn:aws:kms:<region>:<12-digit account>:key/<uuid>)'
      using errcode = 'P0001';
  end if;

  -- 5 private material — never, under any label.
  if position('PRIVATE KEY' in new.public_key) > 0 then
    raise exception 'signing_key_insert_refused: public_key_private_material — public_key contains PRIVATE KEY material; stop the ceremony'
      using errcode = 'P0001';
  end if;

  -- 6 public_key — exactly one SPKI PUBLIC KEY PEM block (D3) whose DER is the
  --   91-byte uncompressed P-256 SubjectPublicKeyInfo (what AWS KMS GetPublicKey
  --   and openssl emit). The D5 fingerprint is defined over exactly these bytes.
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

  -- 7 serialize all global inserts (see CONCURRENCY above).
  perform pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'));

  -- 8 duplicate key_id — an explicit, named refusal ahead of the PRIMARY KEY.
  if exists (select 1 from kernel.signing_key k where k.key_id = new.key_id) then
    raise exception 'signing_key_insert_refused: duplicate_key_id — a signing_key row with this key_id already exists (append-only: revoked rows are never re-used)'
      using errcode = 'P0001';
  end if;

  -- 9 exactly one active global — rotation (active→rotating overlap) is parked.
  if exists (select 1 from kernel.signing_key k where k.scope = 'global' and k.status in ('active','rotating')) then
    raise exception 'signing_key_insert_refused: active_global_exists — exactly one active global signing key is permitted; rotation/replacement of a live key is parked (PFA-18A) and revocation (PFA-18B) is the only lifecycle transition'
      using errcode = 'P0001';
  end if;

  -- 10 post-revoke recovery — FAIL CLOSED (no two-person mechanism exists yet).
  if exists (select 1 from kernel.signing_key k where k.scope = 'global' and k.status = 'revoked') then
    raise exception 'signing_key_insert_refused: post_revoke_recovery_parked — a global key has been revoked; re-bootstrap requires the gated TWO-PERSON recovery artifact (PFA-18C maturity trigger / E4), which is not yet ratified or built; this rule is replaced only by that migration'
      using errcode = 'P0001';
  end if;

  -- 11 lineage — the first-ever global row is the ruling-B bootstrap key_id.
  if new.key_id <> c_bootstrap_key then
    raise exception 'signing_key_insert_refused: bootstrap_key_id_required — the initial global trust root must carry the sanctioned bootstrap key_id (ruling B, ceremony §6.1); any other key_id is not the ratified lineage'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function kernel.guard_signing_key_insert() is
  'M6 (migration 110, PFA-18C pre-issuance): BEFORE INSERT guard on kernel.signing_key. Refuses every non-global row (provision/rotate parked, PFA-18A), any status but active, any algorithm but ES256 (no override), any kms_handle_ref that is not a full AWS KMS key ARN, any public_key that is not exactly one SPKI PEM block decoding to the 91-byte uncompressed P-256 SPKI, private-key material, duplicate key_id, a second active/rotating global, ANY insert after a global revoke (post-revoke recovery parked until the two-person artifact ships), and a first global row whose key_id is not the ruling-B bootstrap id. Serializes global inserts with an advisory transaction lock. Changed only by migration; reads no GUC/config/role.';

drop trigger if exists tg_signing_key_insert_guard on kernel.signing_key;
create trigger tg_signing_key_insert_guard
  before insert on kernel.signing_key
  for each row execute function kernel.guard_signing_key_insert();

-- Zero-grant: the trigger fires on the table's behalf; no role calls this directly.
revoke all on function kernel.guard_signing_key_insert() from public, anon, authenticated, service_role;

commit;
