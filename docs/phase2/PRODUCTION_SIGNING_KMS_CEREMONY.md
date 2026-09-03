# PRODUCTION SIGNING KEY — TWO-PERSON KMS CEREMONY

**Revised 2026-09-03; not executed.**

**Status: PREPARED, NOT EXECUTED.** No production KMS material exists. No production
`kernel.signing_key` row exists. This document is the executable procedure; running it
is a separate, owner-approved act.

**Authority.** Ruling B, `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:232-249`
(ratified two-person external/KMS-backed ceremony) and the approval text at
`docs/phase2/PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:707-717`. Design analysis:
`docs/phase2/_decisions/B_signing_dual_control.md` (Option C). Rehearsal evidence:
`docs/phase2/_impl/G3_signing_rehearsal.md`.

**Every operation in this document carries exactly one marker:**

| Marker | Meaning |
|---|---|
| `READ ONLY` | Reads state. Changes nothing anywhere. |
| `LOCAL` | Runs on an operator workstation. Touches no cloud service and no database. |
| `KMS MUTATION` | Creates or changes cloud KMS state. |
| `PRODUCTION DB MUTATION` | Writes to the production Postgres database. |
| `IRREVERSIBLE AFTER MINT` | Undoable **only** until the first ticket atom is minted. |
| `OWNER APPROVAL REQUIRED` | Do not proceed without the owner's explicit, recorded go. |

> **Placeholder convention.** Every value you must supply appears as
> `<LIKE_THIS>`. **This document contains no example key, no example ARN, no
> example fingerprint, and no example secret.** Anything that looks like a real
> value would be a hazard, so none is provided. If you find yourself pasting a
> string that came from this file rather than from your KMS console, stop.

---

## 0. HARD RULES

1. **The private key is created inside KMS and never leaves it.** It is never exported,
   never written to a file, never pasted into a terminal, never stored in an env var,
   never written to any database column, and never committed. `083:36-39` states this as
   constraint C33; `PHASE_2_EDGE_FUNCTION_SPEC.md:1265-1267` states it as an absolute.
2. **The database stores two strings and nothing else:** the *public* verify key and an
   *opaque* KMS handle. Neither is signing capability.
3. **Do not un-park any signing RPC.** `kernel.provision_signing_key`,
   `rotate_signing_key`, `revoke_signing_key` and the three `pass_type_cert` RPCs stay
   fail-closed exactly as `083:375-425` and `086:714-721` left them. They carry
   `GRANT EXECUTE … TO authenticated` (`v_auth` list `083:846-854`; grant loop
   `083:870-872`); un-parking without an in-body principal check would hand key
   provisioning to every signed-in user. **This default cuts the other way too:** any new
   `kernel.*` function (e.g. the invariant-monitor checker shipped in migration 099, §9.3)
   is EXECUTE-able by `authenticated` the instant it is created unless its migration
   explicitly `revoke`s it (`docs/phase2/_impl/KJ_kms_runbook_monitor.md` §2 E11).
4. **Never pass the KMS handle to a parked RPC.** Postgres logs the failing statement at
   `log_min_error_statement=error` (the default). Calling
   `kernel.provision_signing_key(..., '<PRODUCTION_KMS_KEY_ID>', ...)` writes the handle
   into the server log for no benefit — the call raises before doing anything.
5. **Run every `LOCAL` step outside the git working tree.** `.gitignore` covers `*.pem`,
   `*.key`, `*.p8` but **not** `*.der`, `*.sig`, `*.bin`. Use a directory that is not a
   repository. See §9.4.
6. **No step in this document is performed by one person.** Where a step is marked
   *simultaneous*, both operators are physically or on-video present and both record what
   they saw.

---

## 1. WHAT THE IMPLEMENTATION ACTUALLY EXPECTS

### 1.1 The implementation is PROVIDER-AGNOSTIC. The runbook must pin the provider.

Nothing in the schema, the mint, or any RPC constrains the provider or the format:

| Thing | What the code says | What is therefore undetermined |
|---|---|---|
| `kernel.signing_key.kms_handle_ref` | `text not null` (`083:56`). No `CHECK`, no length rule, no regex, no format. | The provider, the identifier syntax, and whether the identifier pins a key *version*. |
| `kernel.signing_key.public_key` | `text not null` (`083:55`). No format constraint, no parser. | PEM vs raw base64 vs JWK. |
| Algorithm | Nothing in SQL. | Everything. |
| Validation of the pair | **None.** `guard_signing_key_immutable` is `BEFORE UPDATE` only (trigger `083:103-105`); there is no `BEFORE INSERT` trigger. The mint `kernel.issue_ticket_atoms` was replaced by 093 (envelope `093:4950-4976`, function head `093:4874`): it no longer accepts a key — it **resolves** one most-specific-first (`093:4954-4966`), refuses `no_active_signing_key` (`093:4968`), and refuses a caller-supplied key that disagrees with the resolved one (`signing_key_override_refused`, `093:4974-4976`). What it still cannot validate: key material, `not_before <= now()`, `not_after` unset-or-future (`093:4959`), and scope coherence. | Postgres cannot tell a real key from a placeholder. This is by design (it holds no key material) and it is the single most important fact in this document. |

The *architecture* — not the code — supplies the intent, at
`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md`:

- **§5.1 (`:1270-1277`)** — asymmetric signer keys, **Ed25519 preferred, ECDSA-P256
  acceptable**; the credential token is a compact signed object over
  `{ atom_id, session_id, credential_version, key_id, issued_at, exp }`, produced by
  `KMS.sign(kms_handle_ref, payload)`.
- **§5.3 (`:1291-1297`)** — custody is *"KMS/HSM (AWS KMS asymmetric, or GCP KMS, or
  CloudHSM)"*; the future edges authenticate with an IAM role in env `KMS_SIGNER_ROLE_ARN`,
  scoped to `kms:Sign` for signing and `kms:CreateKey`/`ScheduleKeyDeletion` for
  provisioning; *"No env var ever holds key material."* The env-var name is AWS-shaped,
  which is a hint and not a decision.
- **§5.2 (`:1283-1284`)** — `global` scope is *"allowed but discouraged … only for a
  controlled bootstrap."* This ceremony is that bootstrap.

**Conclusion: the implementation expects "an asymmetric signing key held in a cloud
KMS/HSM, referenced by an opaque handle." It expects nothing more specific.** Therefore
this runbook must pin down, and does pin down in §1.2:

1. the KMS provider and the exact key resource;
2. the algorithm and curve;
3. the wire format of `public_key`;
4. the syntax of `kms_handle_ref`, **including version pinning**;
5. the fingerprint function;
6. the canonical bytes over which a signature is taken.

### 1.2 THE PINNED DECISIONS — fill these in before the ceremony

`OWNER APPROVAL REQUIRED` — record the chosen values in the evidence pack (§9).

| # | Decision | Ruling | Recorded value |
|---|---|---|---|
| D1 | **Provider** — one of AWS KMS (asymmetric), GCP Cloud KMS, or CloudHSM. Nothing else is architecturally sanctioned. | `EDGE_SPEC:1291-1292` | `<PRODUCTION_KMS_PROVIDER>` |
| D2 | **Algorithm.** Ed25519 preferred; **ECDSA-P256 (SHA-256) is the ratified fallback.** Ed25519 is not offered by every provider for asymmetric signing — before choosing it, confirm it appears in your provider's *current* supported key-spec list (`aws kms create-key help` / `gcloud kms keys create --help`). **If Ed25519 is unavailable on D1's provider, use ECDSA-P256.** Do not substitute RSA; the architecture does not sanction it. | `EDGE_SPEC:1273-1274` | `<PRODUCTION_KMS_ALGORITHM>` |
| D3 | **`public_key` wire format: SPKI, PEM-armoured**, i.e. a `-----BEGIN PUBLIC KEY-----` block. Both AWS and GCP export SPKI. This is the format the fingerprint in D5 is defined over and the format §5's verification commands consume. | this runbook | fixed |
| D4 | **`kms_handle_ref` syntax: the provider's fully-qualified resource identifier, pinned to exactly one key *version*.** AWS KMS: `arn:aws:kms:<REGION>:<ACCOUNT_ID>:key/<KEY_ID>` (an AWS asymmetric CMK has one key material; "rotation" is a *new key*). GCP Cloud KMS: `projects/<P>/locations/<L>/keyRings/<KR>/cryptoKeys/<K>/cryptoKeyVersions/<V>` — **the `cryptoKeyVersions/<V>` suffix is mandatory.** A GCP handle that stops at `cryptoKeys/<K>` designates a *rotating* key whose signatures would stop verifying against the immutable `public_key` column the moment a new version becomes primary. | this runbook | `<PRODUCTION_KMS_KEY_ID>` |
| D5 | **Fingerprint: `SHA-256` over the DER-encoded SPKI bytes, lowercase hex, 64 characters.** Not over the PEM text; not over the raw point. The DB-side gate in §6 recomputes exactly this from the stored PEM. | this runbook | `<EXPECTED_PUBLIC_KEY_FINGERPRINT>` |
| D6 | **`not_after`: NULL** (no expiry). A bounded window creates a hard issuance cliff — the resolver's `not_after` predicate (now `093:4959`; same shape at `093:4069` and `085:1953`) requires `not_after > now()`, and both rotation and revoke are parked, so only a superuser SQL session could move it. Choosing a non-NULL value obliges you to name a calendar owner. | `B_signing_dual_control.md:355` | `NULL` unless the owner overrides |
| D7 | **Scope: `global`. `key_id`: `00000000-0000-0000-0000-0000000000b0`.** Both are already determined — `signing_key_scope_target_ck` (`083:64-68`) forbids any other scope for a bootstrap row that predates the catalog, and `signing_key_active_global_uq` (`083:77-78`) then permits exactly one. | `093_parts/40_config_privacy_freeze.sql` ITEM 2 | fixed |

### 1.3 What is NOT built, and therefore not in scope

`supabase/functions/` contains no `credential-sign` and no `signing-key-provision`. M1
distribution, the 086 door rail, and Apple Wallet are all unbuilt.
`feature.native_scanning_enabled` and `wallet.apple.enabled` are false. **This ceremony
does not activate scanning.** It exists because `kernel.tickets.signing_key_id` is
`NOT NULL` (`079:48`) with an `ON DELETE RESTRICT` FK (`084:52-55`) and the mint refuses
without an active in-scope key — so a ticket cannot exist at all until one honest row
does. Signature production and verification are consequently **off-database** operations
throughout this document.

Since 093, the same resolver also runs inside `venue.create_primary_checkout`
(`093:4066-4077`, gate order within the function: `payout_not_ready` at `093:4026` →
`no_active_signing_key` at `093:4076` → `service_fee_unset`). With no active key, no
primary checkout can be quoted at all — **the ceremony gates the first production QUOTE,
not the first webhook-time mint.** The key is deliberately not pinned onto the order at
quote time (`093:4077-4081`). The "buyer charged, no ticket" hazard is therefore closed
before the charge, and a webhook that still reaches finalize without a key is classified
retryable + alert by `stripe-webhook/native.ts:420-421` (`{ack:false, alert:true,
reason:'finalize_no_signing_key'}`, surfaced via Sentry `captureException`,
`index.ts:358-359`).

---

## 2. THE TWO PEOPLE

Person A and Person B are **named individuals**, recorded in the evidence pack, who do
not share credentials and are not the same human under two accounts.

### PERSON A — Key Custodian (cloud/IAM side)

| Responsibility | Marker |
|---|---|
| A1. Holds the IAM principal permitted to `kms:CreateKey` (or `cloudkms.cryptoKeys.create`). | — |
| A2. Creates the key in production KMS, using only the parameters D1/D2 record. | `KMS MUTATION` |
| A3. Signs the §5 challenge **through the handle** — never with any exported material. | `KMS MUTATION` (a `Sign` call) |
| A4. Reads the ceremony's post-checks aloud and countersigns the evidence pack. | `READ ONLY` |
| A5. **Never** holds the production database superuser credential. |  |

### PERSON B — Trust Verifier (database/verification side)

| Responsibility | Marker |
|---|---|
| B1. Exports the public key **independently**, from their own authenticated session, using their own read-only IAM principal. | `READ ONLY` |
| B2. Computes the fingerprint (D5) on their own workstation and states it aloud **before** A states theirs. | `LOCAL` |
| B3. Verifies A's challenge signature against **B's own** exported public key. | `LOCAL` |
| B4. Holds the production database credential and executes the bootstrap transaction. | `PRODUCTION DB MUTATION` |
| B5. **Never** holds `kms:CreateKey`. |  |

**On B4:** no role but `postgres` holds `INSERT` on `kernel.signing_key` — `authenticated`
gets `permission denied for table signing_key` (rehearsed, §15 ADV-3). B4 therefore names
the **superuser** credential specifically, not merely "a" database credential.

### Separation invariant

> **No single principal may both create the KMS key and write the database row.**
> A can create keys but cannot write the trust root. B can write the trust root but
> cannot create keys, and the transaction B runs aborts unless the fingerprint B was
> given matches the bytes B is writing.

### Steps that require SIMULTANEOUS presence

Both operators present, same call or same room, each reading from their own screen:

- **§4** key creation (B watches the parameters A submits).
- **§5** the binding proof — A signs, B verifies. **This is the ceremony's load-bearing step.**
- **§6** the bootstrap transaction — A reads the three `NOTICE` lines aloud from B's screen.
- **§7** post-bootstrap verification.
- **§11** any rotation.

Steps that may be done alone: nothing.

---

## 3. PRE-CEREMONY CHECKLIST

`READ ONLY` · `OWNER APPROVAL REQUIRED`

- [ ] Owner has recorded the go, in writing, referencing Ruling B.
- [ ] D1–D7 in §1.2 are filled in and countersigned.
- [ ] Person A and Person B named; their principals confirmed non-overlapping (A has no DB credential; B has no `CreateKey`).
- [ ] Migrations **093, 094 and 095 applied (ledger 110)** — not merely 093. 093's quote-time
      gate (`093:4066-4077`) and resolving mint (`093:4874-5010`) are what give this ceremony
      its semantics (§1.3); `catalog.set_platform_config` as replaced in 093 (`093:6544-…`,
      dual-control prefix set `093:6748-6751`) is what §13 step 1's single-admin kill switch
      depends on. 094/095 carry no signing reference themselves but the activation order
      applies 093→094→095 as one block, so require all three. 093 ships ITEM 2 (the bootstrap
      template) as a **commented** template and writes no row —
      `093_parts/40_config_privacy_freeze.sql:446-521`.
- [ ] Migrations **096–099 applied.** 096 (`kernel.organization_obligation_recovery`) and 097
      (cross-venue ring-fence) carry no signing reference. 098 (promoter pro-rata funding)
      carries no signing reference. **099 (`099_signing_monitor_and_executor_invokers.sql`)
      is the standing monitor this ceremony's §9.3 now points to** — see §9.3 below; it must be
      applied before step 9 of the §16 sequence so that arming the monitor is a config act, not
      a deploy.
- [ ] `feature.native_issuance_enabled` is **false**. It stays false until every other activation item is green; flipping it is a separate, later, owner-executed act.
- [ ] Confirm the table is empty:

```bash
# READ ONLY — production
psql "$PROD_DB_URL" -tAc "select count(*) from kernel.signing_key;"
# expected: 0
```

- [ ] Confirm the lifecycle is still parked (all six must raise `dual_control_unavailable`):

```bash
# READ ONLY — production. Note the deliberately inert arguments: never pass a real handle.
psql "$PROD_DB_URL" -tA -c "select kernel.provision_signing_key('global',null,'-','-',now(),'preflight','preflight');"
# expected: ERROR ... precondition_failed: dual_control_unavailable ...
```

- [ ] A clean, non-repository working directory exists on each workstation:

```bash
# LOCAL
umask 077
export CEREMONY_DIR="$HOME/snatchit-ceremony-$(date -u +%Y%m%d)"
mkdir -p "$CEREMONY_DIR" && cd "$CEREMONY_DIR"
git rev-parse --is-inside-work-tree 2>/dev/null && echo "REFUSE: inside a git repo" || echo "OK: not a repo"
```

---

## 4. PHASE 1 — CREATE THE KEY IN KMS

`KMS MUTATION` · `OWNER APPROVAL REQUIRED` · **simultaneous** · performed by **Person A**,
watched by **Person B**

Choose the block for D1. Substitute only `<…>` placeholders.

### 4a. AWS KMS

```bash
# KMS MUTATION — production account
aws kms create-key \
  --key-usage SIGN_VERIFY \
  --key-spec <PRODUCTION_KMS_KEY_SPEC> \
  --description "SnatchIt primary ticketing signer — ruling B bootstrap" \
  --tags TagKey=app,TagValue=snatchit TagKey=purpose,TagValue=ticket-signing
# Record KeyMetadata.Arn as <PRODUCTION_KMS_KEY_ID>. That ARN is the kms_handle_ref (D4).
```

`<PRODUCTION_KMS_KEY_SPEC>` is the provider's spec name for D2 (for ECDSA-P256 it is the
NIST P-256 signing spec). **Confirm the exact spelling from `aws kms create-key help`
before running — do not guess it from memory or from this document.**

Then restrict it, so no single principal can both create and sign:

```bash
# KMS MUTATION — apply a key policy granting kms:Sign ONLY to the future signer role,
# and kms:GetPublicKey to Person B's read-only principal. Person A must NOT retain
# kms:Sign beyond the §5 binding proof.
aws kms put-key-policy --key-id <PRODUCTION_KMS_KEY_ID> --policy-name default \
  --policy file://key-policy.json
```

### 4b. GCP Cloud KMS

```bash
# KMS MUTATION — production project
gcloud kms keys create <KEY_NAME> \
  --location <LOCATION> --keyring <KEYRING> \
  --purpose asymmetric-signing \
  --default-algorithm <PRODUCTION_KMS_ALGORITHM_ID> \
  --protection-level <software|hsm>

# READ ONLY — resolve the VERSION. D4 requires the version-pinned name.
gcloud kms keys versions list --key <KEY_NAME> --keyring <KEYRING> --location <LOCATION>
# <PRODUCTION_KMS_KEY_ID> =
#   projects/<P>/locations/<L>/keyRings/<KR>/cryptoKeys/<K>/cryptoKeyVersions/<V>
```

**Both operators record `<PRODUCTION_KMS_KEY_ID>` independently and compare character by
character before continuing.**

---

## 5. PHASE 2 — EXTRACT, FINGERPRINT, AND PROVE THE BINDING

**simultaneous** · this is the step that catches every "the handle points somewhere else"
failure. Postgres provably cannot catch it (`B_signing_dual_control.md:261`, threat T3).

### 5.1 Person B exports the public key — independently

`READ ONLY`

```bash
# AWS — READ ONLY
aws kms get-public-key --key-id <PRODUCTION_KMS_KEY_ID> \
  --output text --query PublicKey | base64 --decode > pub.der
openssl pkey -pubin -inform DER -in pub.der -out pub.pem
```

```bash
# GCP — READ ONLY
gcloud kms keys versions get-public-key <V> \
  --key <KEY_NAME> --keyring <KEYRING> --location <LOCATION> \
  --output-file pub.pem
openssl pkey -pubin -in pub.pem -outform DER -out pub.der
```

Sanity — it must be a *public* key of the algorithm D2 names:

```bash
# LOCAL
openssl pkey -pubin -in pub.pem -text -noout | head -3
grep -c 'PRIVATE KEY' pub.pem   # MUST print 0. If it prints anything else, STOP.
```

### 5.2 Both operators compute the fingerprint (D5) independently

`LOCAL`

```bash
# LOCAL — run this on BOTH workstations, from each operator's own pub.der
openssl dgst -sha256 -hex pub.der | awk '{print $2}'
```

**Person B says the value first. Person A then says theirs.** They must be identical, and
that value is `<EXPECTED_PUBLIC_KEY_FINGERPRINT>`. If they differ, the ceremony stops: one
of you is looking at a different key.

### 5.3 THE BINDING PROOF — Person A signs through the handle, Person B verifies

`KMS MUTATION` (one `Sign` call) · **simultaneous**

Person B generates the challenge, so A cannot pre-compute it:

```bash
# LOCAL — Person B
printf 'snatchit-ceremony %s %s' "$(date -u +%Y%m%dT%H%M%SZ)" "$(openssl rand -hex 16)" > challenge.bin
cat challenge.bin        # B reads it aloud; A pastes it into their own challenge.bin
```

Person A signs it **through the handle only**:

```bash
# AWS — KMS MUTATION (a Sign call; creates no state)
aws kms sign --key-id <PRODUCTION_KMS_KEY_ID> \
  --message fileb://challenge.bin --message-type RAW \
  --signing-algorithm <PRODUCTION_KMS_SIGNING_ALGORITHM> \
  --output text --query Signature | base64 --decode > challenge.sig
```

```bash
# GCP — KMS MUTATION
gcloud kms asymmetric-sign --version <V> \
  --key <KEY_NAME> --keyring <KEYRING> --location <LOCATION> \
  --digest-algorithm sha256 \
  --input-file challenge.bin --signature-file challenge.sig
```

Person B verifies against **B's own** `pub.pem` — never against a file A sent:

```bash
# LOCAL — ECDSA-P256 (KMS returns a DER-encoded ECDSA signature)
openssl dgst -sha256 -verify pub.pem -signature challenge.sig challenge.bin
# LOCAL — Ed25519 (raw 64-byte signature, no pre-hash)
openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in challenge.bin -sigfile challenge.sig
```

**Required output: `Verified OK` / `Signature Verified Successfully`.**

> **If this fails, `<PRODUCTION_KMS_KEY_ID>` and the exported public key are not the same
> key. STOP. Write nothing to the database.** This is the *only* control in the entire
> system that detects that condition — §12 ADV-4 records why.
>
> Rehearsed both ways: the matched pair verifies, the mismatched pair fails
> (`G3_signing_rehearsal.md`, ADV-4/5).

### 5.4 Destroy the local challenge artifacts

`LOCAL`

```bash
rm -f challenge.bin challenge.sig
# pub.pem / pub.der are PUBLIC and are kept as evidence (§9).
```

---

## 6. PHASE 3 — THE BOOTSTRAP TRANSACTION

`PRODUCTION DB MUTATION` · `IRREVERSIBLE AFTER MINT` · `OWNER APPROVAL REQUIRED` ·
**simultaneous** · executed by **Person B**, read aloud by **Person A**

### 6.1 The artifact

Save this **verbatim** as `signing_key_bootstrap.sql` in `$CEREMONY_DIR`. It is
copy/paste-complete: it takes no edits, and every real value arrives as a `psql` variable.
It refuses to write anything unless three gates pass, and it verifies the row it wrote
before it commits.

```sql
-- ===========================================================================
-- kernel.signing_key BOOTSTRAP — CEREMONY ARTIFACT. Do not edit this file.
-- Values arrive on the psql command line:
--   -v PUBLIC_KEY_PEM="$(cat pub.pem)"
--   -v KMS_HANDLE_REF="$(cat handle.txt)"
--   -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)"
-- ===========================================================================
\set ON_ERROR_STOP on
begin;

create temp table ceremony_input on commit drop as
select :'PUBLIC_KEY_PEM'::text as pem,
       :'KMS_HANDLE_REF'::text as handle,
       lower(regexp_replace(:'EXPECTED_FINGERPRINT'::text, '[^0-9a-fA-F]', '', 'g')) as expected_fpr;

-- PRE-FLIGHT 1 — bootstrap is once-only.
do $$
begin
  if exists (select 1 from kernel.signing_key) then
    raise exception 'CEREMONY ABORT: kernel.signing_key already holds % row(s) — bootstrap is a once-only act',
      (select count(*) from kernel.signing_key);
  end if;
end $$;

-- PRE-FLIGHT 2 — FINGERPRINT GATE. The bytes about to be written must hash to
-- the fingerprint the two operators verified independently, out of band.
do $$
declare v_i record; v_fpr text;
begin
  select * into v_i from ceremony_input;
  if v_i.pem !~ '-----BEGIN PUBLIC KEY-----' then
    raise exception 'CEREMONY ABORT: PUBLIC_KEY_PEM is not an SPKI PEM public-key block';
  end if;
  if v_i.pem ~ 'PRIVATE KEY' then
    raise exception 'CEREMONY ABORT: PUBLIC_KEY_PEM contains PRIVATE KEY material — stop the ceremony';
  end if;
  if length(v_i.expected_fpr) <> 64 then
    raise exception 'CEREMONY ABORT: EXPECTED_FINGERPRINT is not 64 hex characters';
  end if;
  v_fpr := encode(sha256(decode(
             regexp_replace(v_i.pem, '-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]', '', 'g'),
             'base64')), 'hex');
  if v_fpr <> v_i.expected_fpr then
    raise exception 'CEREMONY ABORT: fingerprint mismatch — computed %, expected %', v_fpr, v_i.expected_fpr;
  end if;
  raise notice 'PRE-FLIGHT 2 PASSED — fingerprint %', v_fpr;
end $$;

-- PRE-FLIGHT 3 — the handle must not be empty, a placeholder, or key material.
do $$
declare v_h text;
begin
  select handle into v_h from ceremony_input;
  if v_h is null or btrim(v_h) = '' then
    raise exception 'CEREMONY ABORT: KMS_HANDLE_REF is empty';
  end if;
  if v_h ~* '(BEGIN .*PRIVATE KEY|TODO|PLACEHOLDER|CHANGEME|<<<|>>>)' then
    raise exception 'CEREMONY ABORT: KMS_HANDLE_REF looks like a placeholder or key material';
  end if;
  raise notice 'PRE-FLIGHT 3 PASSED — handle accepted (value not echoed)';
end $$;

-- THE ROW. Exactly one, scope=global, deterministic key_id (…b0 = ruling B).
insert into kernel.signing_key
       (key_id, scope, event_id, venue_id,
        public_key, kms_handle_ref, status, not_before, not_after)
select '00000000-0000-0000-0000-0000000000b0', 'global', null, null,
       i.pem, i.handle, 'active', now(), null
  from ceremony_input i
 where not exists (select 1 from kernel.signing_key);

-- POST-CHECK — the row must satisfy the resolver used at all three sites this key
-- feeds (finalize 085:1948-1960 · checkout gate 093:4066-4074 · mint 093:4954-4966),
-- or this transaction aborts.
do $$
declare v_n int; v_ok boolean;
begin
  select count(*) into v_n from kernel.signing_key;
  if v_n <> 1 then raise exception 'CEREMONY ABORT: expected exactly 1 signing_key row, found %', v_n; end if;
  select (k.scope='global' and k.event_id is null and k.venue_id is null
          and k.status='active' and k.not_before <= now()
          and (k.not_after is null or k.not_after > now())
          and k.key_id = '00000000-0000-0000-0000-0000000000b0'
          and k.public_key = (select pem from ceremony_input)
          and k.kms_handle_ref = (select handle from ceremony_input))
    into v_ok from kernel.signing_key k;
  if not v_ok then raise exception 'CEREMONY ABORT: the row does not resolve as the active global key just supplied'; end if;
  raise notice 'POST-CHECK PASSED — exactly one active global key, key_id …b0';
end $$;

commit;
```

> **If D6 selects a non-NULL `not_after`,** change only the literal `null` in the
> `select … 'active', now(), null` line to `timestamptz '<PRODUCTION_KEY_NOT_AFTER>'`, and
> record a named calendar owner in the evidence pack. Nothing else changes.

### 6.2 Running it

```bash
# LOCAL — stage the three inputs as FILES so they never enter shell history.
cd "$CEREMONY_DIR"
printf '%s' '<PRODUCTION_KMS_KEY_ID>' > handle.txt
openssl dgst -sha256 -hex pub.der | awk '{print $2}' > fingerprint.txt
cat fingerprint.txt   # both operators confirm this equals <EXPECTED_PUBLIC_KEY_FINGERPRINT>
```

```bash
# PRODUCTION DB MUTATION — Person B runs this; Person A reads the NOTICEs aloud.
psql "$PROD_DB_URL" \
  -v PUBLIC_KEY_PEM="$(cat pub.pem)" \
  -v KMS_HANDLE_REF="$(cat handle.txt)" \
  -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)" \
  -f signing_key_bootstrap.sql
```

**Required output — all three lines, then `COMMIT`:**

```
NOTICE:  PRE-FLIGHT 2 PASSED — fingerprint <EXPECTED_PUBLIC_KEY_FINGERPRINT>
NOTICE:  PRE-FLIGHT 3 PASSED — handle accepted (value not echoed)
NOTICE:  POST-CHECK PASSED — exactly one active global key, key_id …b0
COMMIT
```

Anything else means nothing was written. Every abort path was rehearsed and each one
leaves `count(*) = 0` (`G3_signing_rehearsal.md`, §Bootstrap).

**Do not use the Supabase SQL editor for this step.** It offers no `-v` variables, so the
values end up pasted into a web console and retained in query history.

---

## 7. PHASE 4 — POST-BOOTSTRAP VERIFICATION

`READ ONLY` · **simultaneous**

### 7.1 The row is what the ceremony intended

```bash
# READ ONLY — production
psql "$PROD_DB_URL" -tAc "
select key_id || ' | scope=' || scope || ' | status=' || status
    || ' | not_before=' || not_before
    || ' | not_after=' || coalesce(not_after::text,'null')
    || ' | fingerprint=' || encode(sha256(decode(
         regexp_replace(public_key,'-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]','','g'),
         'base64')),'hex')
  from kernel.signing_key;"
```

Confirm: exactly one line; `key_id` ends `…b0`; `scope=global`; `status=active`;
`fingerprint=<EXPECTED_PUBLIC_KEY_FINGERPRINT>`. **The handle is deliberately not printed.**

### 7.2 The key resolves the way the mint and finalize resolve it

```bash
# READ ONLY — this query's `scope in ('global')` filter is only the global arm of the
# resolver, not its verbatim shape (it cannot see a per_event/per_venue shadow row — see
# §7.4 for that check). The full resolver is 085:1948-1960 = 093:4066-4074 = 093:4954-4966.
# (086:1196-1201 is the unrelated comp-issue path.)
psql "$PROD_DB_URL" -tAc "
select k.key_id, k.scope from kernel.signing_key k
 where k.status='active' and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
   and k.scope in ('global')
 order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
 limit 1;"
```

### 7.3 The lifecycle is still parked and nothing was un-parked

```bash
# READ ONLY — all six must still raise dual_control_unavailable.
for f in \
  "kernel.provision_signing_key('global',null,'-','-',now(),'p','p')" \
  "kernel.rotate_signing_key('00000000-0000-0000-0000-0000000000b0','-','-','p','p')" \
  "kernel.revoke_signing_key('00000000-0000-0000-0000-0000000000b0','p',0,'p')" \
  "kernel.provision_pass_type_cert('-','-','-','-','-',now(),now()+interval '1 day','p','p')" \
  "kernel.rotate_pass_type_cert('00000000-0000-0000-0000-000000000000','-','-','-',now(),now()+interval '1 day','p','p')" \
  "kernel.revoke_pass_type_cert('00000000-0000-0000-0000-000000000000','p','p')" ; do
  echo "== $f"; psql "$PROD_DB_URL" -tAc "select $f;" 2>&1 | grep -o 'dual_control_unavailable' || echo "!! NOT PARKED — STOP";
done
```

### 7.4 No second key, no shadow key

```bash
# READ ONLY — must print 1|1|0|0
psql "$PROD_DB_URL" -tAc "
select count(*) || '|' || count(*) filter (where scope='global' and status='active')
    || '|' || count(*) filter (where scope='per_event')
    || '|' || count(*) filter (where scope='per_venue')
  from kernel.signing_key;"
```

### 7.5 The immutability guard is live

`PRODUCTION DB MUTATION` (attempted; **it must fail**) — run inside an explicit
transaction you then roll back, so a surprising success changes nothing:

```bash
# PRODUCTION DB MUTATION — expected to ERROR. Rolls back either way.
psql "$PROD_DB_URL" <<'SQL'
begin;
update kernel.signing_key set public_key = public_key || 'X'
 where key_id='00000000-0000-0000-0000-0000000000b0';
rollback;
SQL
# expected: ERROR: append_only: signing_key identity/target/public_key/kms_handle is immutable after creation
```

### 7.6 The one live gap to record, not fix

`not_after` is deliberately **excluded** from the immutability guard's immutable-set
(`083:88-91`, which also excludes `not_before` — this runbook had never listed that). A
superuser session can still move the key's window. There is no in-band control for this;
the compensating control is the §9.3 monitor. Recorded, not fixed.

---

## 8. THE CANONICAL CREDENTIAL PAYLOAD (for whoever builds `credential-sign`)

Not executed by this ceremony; pinned here so a future implementation cannot drift.

- Fields, from `EDGE_SPEC:1276-1277`: `{ atom_id, session_id, credential_version, key_id, issued_at, exp }`.
- `key_id` is `kernel.tickets.signing_key_id`, **pinned at mint** (insert at `093:5003-5005`,
  superseding the old `083:557-559` site) and resolved from the ticket row, never by a fresh
  lookup (`EDGE_SPEC:1287-1289`).
- Signed via `KMS.sign(kms_handle_ref, canonical_payload)`. The signer must define and
  freeze a canonical byte encoding (field order, whitespace, separators) *before* the
  first credential is issued: verification is byte-exact, and a re-ordered JSON
  serialization is a different message. The rehearsal used a single compact JSON encoding
  on both sides and confirmed that a one-character change makes verification fail
  (`G3_signing_rehearsal.md`, step 7b).
- Verification is off-database. The door joins M2 (`venue.get_door_manifest` —
  `signing_key_id` only, never `public_key`, `086:860-866`) to M1 (the
  `kernel.signing_key` public projection). **`public_key` is granted to `authenticated`
  only, never to `anon`** (PFA-16, `083:114-124`) — a fact confirmed in rehearsal: `anon`
  gets `permission denied for schema kernel`.

---

## 9. AUDIT EVIDENCE

### 9.1 What to record

| Item | Where it comes from |
|---|---|
| Owner's written go, referencing Ruling B | §3 |
| D1–D7 filled in and countersigned | §1.2 |
| Full names + principals of Person A and Person B, and the confirmation that neither holds the other's capability | §2 |
| `<PRODUCTION_KMS_KEY_ID>`, recorded independently by both and compared | §4 |
| `<EXPECTED_PUBLIC_KEY_FINGERPRINT>`, stated by B first, then A | §5.2 |
| `pub.pem` and `pub.der` — public, safe to archive | §5.1 |
| The binding-proof result: challenge text, algorithm, and the literal `Verified OK` line | §5.3 |
| The three `NOTICE` lines and the `COMMIT` from the bootstrap | §6.2 |
| The §7.1–§7.5 outputs | §7 |
| The KMS `CreateKey` and `Sign` entries from the provider's own audit trail (CloudTrail / Cloud Audit Logs), which are outside either operator's control | provider |
| Timestamp and duration of the ceremony; both signatures | — |

### 9.2 What must NOT be recorded anywhere

The private key (it does not exist outside KMS), any signature over a real credential, and
any file matching `*private*`. **Screenshots of the KMS console key-detail page are
acceptable; screenshots of any "export"/"download" dialog are not.**

### 9.3 Standing monitor (`OWNER APPROVAL REQUIRED` to waive)

Rotation and revocation are unavailable in-band, so detection is the control. Prior text in
this section described a manual daily query; no mechanism actually existed. **A mechanism
now exists, dark, in migration `099_signing_monitor_and_executor_invokers.sql`:**

- Function `kernel.check_signing_key_invariants()` — `SECURITY DEFINER`, read-only,
  `EXECUTE` revoked from `public, anon, authenticated, service_role` (only the cron owner
  runs it). It never selects `kms_handle_ref`; the fingerprint is reduced to a comparison
  result (`match` / `MISMATCH` / `unpinned` / `bootstrap_row_missing`), never the hex or the
  key material itself.
- Three config keys, all owner-unset at apply (`restricted` visibility): `signing.monitor_enabled`
  (seeded `false` — the checker returns `{"status":"monitor_disabled"}` and writes nothing
  while false), `signing.expected_key_fingerprint` (seeded `null`), `signing.expected_max_not_after`
  (seeded `null`, D6's default).
- Cron job `monitor-signing-key-invariants`, daily. The job row exists from apply (owning-package
  pattern) but is inert until `signing.monitor_enabled` is set `true`.
- On an alert, a durable append-only `kernel.admin_audit` row (`action = 'signing_key.invariant_alert'`)
  plus best-effort push egress to the `notify-report` edge, event `signing_invariant_alert`
  (fans out to every `public.admin_users` row and `ADMIN_EMAIL`, and a Sentry `captureException`
  so an alert rule can page). Egress failure does not roll back the audit row.
- **Six standing invariants checked** (the four this section used to list, plus two added to
  close a gap the old text had: it claimed to alert on any status change but did not watch
  status at all):

  | Column | Expected | Closes |
  |---|---|---|
  | `total_keys` | `1` | — |
  | `scoped_keys` | `0` | the ADV-7 shadow-key signal |
  | `active_global` | `1` | — |
  | `rotating_keys` (**added**) | `0` until the first rotation | ADV-9 — a `rotating` key was previously invisible |
  | `revoked_keys` (**added**) | `0` | ADV-9 — a `revoked` flip was previously invisible |
  | `fingerprint` | `match` (a WORD, never the hex) | — |
  | `max_not_after_set` vs the pinned `signing.expected_max_not_after` | agree | §7.6's live gap |

  Full design, options considered, and the exact SQL: `docs/phase2/_impl/KJ_kms_runbook_monitor.md` §4.

Replaces the former manual-query text. §16 step 9 below is now the arming act, not a
prose reminder.

#### The arming step — `PRODUCTION CONFIG` · `OWNER APPROVAL REQUIRED` · **NOT EXECUTED**

Runs **after** §7 passes and **before** step 10 (flag flip). Requires migration 099 applied
and the `notify-report` branch deployed. Executed by a **platform_admin JWT** (the setter
refuses `postgres`) through PostgREST or an authenticated `psql` session — never the SQL
editor.

```sql
-- PRODUCTION CONFIG — OWNER APPROVAL REQUIRED. Values from the evidence pack (§9.1), not from this file.
-- 1. pin the fingerprint B stated first and A confirmed (§5.2). Lowercase hex, 64 chars.
select catalog.set_platform_config('signing.expected_key_fingerprint',
         to_jsonb('<EXPECTED_PUBLIC_KEY_FINGERPRINT>'::text), 'ceremony_b_bootstrap', '<COMMAND_KEY_1>');
-- 2. (only if D6 chose a non-NULL not_after) pin it, else skip:
-- select catalog.set_platform_config('signing.expected_max_not_after',
--          to_jsonb('<PRODUCTION_KEY_NOT_AFTER>'::text), 'ceremony_b_bootstrap', '<COMMAND_KEY_2>');
-- 3. arm
select catalog.set_platform_config('signing.monitor_enabled', 'true'::jsonb, 'ceremony_b_bootstrap', '<COMMAND_KEY_3>');
-- 4. READ ONLY — prove the monitor is green NOW, not tomorrow at 05:23 (run as postgres, the cron owner):
--    select kernel.check_signing_key_invariants();   -- expected: {"status":"ok","alerts":[],"fingerprint":"match",...}
--    Anything else: STOP; the evidence pack is not signable.
```

Expected `set_platform_config` returns: `{"status":"ok","key":…,"version":2,…}` for each
(direct path, `078:1297-1307`) — because `signing.%` is **not** in the dual-control prefix
set (`093:6748-6751`), a single platform_admin can pin, arm, and — the weakness — **disarm
or re-pin alone**. Whether `signing.%` should be dual-controlled is open; see
`docs/phase2/_impl/KJ_kms_runbook_monitor.md` §5 Q3.

A `per_event` or `per_venue` row appearing **at all** is the scope-shadowing signal (§12
ADV-7) and is a page-the-owner event, not a ticket — it now also trips `scoped_keys` above.

### 9.4 CI and repository hygiene

- `.gitignore` covers `*.pem`, `*.key`, `*.p8`. It does **not** cover `*.der`, `*.sig`, or
  `*.bin`. Run every `LOCAL` step outside any repository (the §3 check enforces this).
- No CI workflow references KMS or key material today (`grep -rniE 'kms|KMS_SIGNER' .github/workflows/` returns nothing — stale in the safe direction; this section previously said "two prose comments").
- If `credential-sign` is ever built, `KMS_SIGNER_ROLE_ARN` holds a **role ARN**, never key
  material (`EDGE_SPEC:1293-1297`).
- The fixtures in `supabase/tests/147_phase2_kernel_credential_infrastructure.sql` insert
  the literal strings `'PUBKEY'` / `'kms-handle-opaque'`. Those are deliberate
  non-keys, and they are why suite 147 must keep asserting
  `count(*) = 0` on production-shaped databases.

---

## 10. ROLLBACK — **BEFORE** THE FIRST CREDENTIAL MINT

`PRODUCTION DB MUTATION` · `OWNER APPROVAL REQUIRED`

Rollback is available **only while `kernel.tickets` holds no row referencing the key.**
The guard below enforces that; it does not merely warn.

```sql
-- ===========================================================================
-- signing_key_bootstrap_ROLLBACK.sql — deletes the bootstrap row.
-- Structurally unavailable once ANY atom pins the key
-- (kernel.tickets.signing_key_id ... ON DELETE RESTRICT, 084:52-55).
-- ===========================================================================
\set ON_ERROR_STOP on
begin;

do $$
declare v_refs int;
begin
  select count(*) into v_refs from kernel.tickets
   where signing_key_id = '00000000-0000-0000-0000-0000000000b0';
  if v_refs > 0 then
    raise exception 'ROLLBACK UNAVAILABLE: % ticket atom(s) already pin this key. The bootstrap is now permanent; use §11 rotation or §13 compromise response instead.', v_refs;
  end if;
  if exists (select 1 from kernel.wallet_pass where signing_key_id = '00000000-0000-0000-0000-0000000000b0')
     or exists (select 1 from venue.door_manifest_entry where signing_key_id = '00000000-0000-0000-0000-0000000000b0')
     or exists (select 1 from venue.door_manifest_delta where signing_key_id = '00000000-0000-0000-0000-0000000000b0') then
    raise exception 'ROLLBACK UNAVAILABLE: a wallet pass or door-manifest row references this key';
  end if;
end $$;

delete from kernel.signing_key where key_id = '00000000-0000-0000-0000-0000000000b0';

do $$
begin
  if exists (select 1 from kernel.signing_key) then
    raise exception 'ROLLBACK ABORT: kernel.signing_key is not empty after the delete';
  end if;
  raise notice 'ROLLBACK COMPLETE — kernel.signing_key is empty; the ceremony may be re-run';
end $$;

commit;
```

Also schedule the KMS key for deletion (`KMS MUTATION`, provider-specific) and record it.

**Rehearsed:** with two atoms pinned, the raw `DELETE` fails with
`violates foreign key constraint "fk_tickets_signing_key"` — the guard above simply
reports it in operator language before Postgres does.

---

## 11. WHAT BECOMES IRREVERSIBLE AFTER THE FIRST MINT

`IRREVERSIBLE AFTER MINT`

**The point of no return is the first successful `kernel.issue_ticket_atoms` call** — in
production, the first `venue.finalize_primary_order` on a paid order (`085`, untouched by
093/094/095 — `093:2838`). Not the ceremony, not the flag flip: the first atom — which
cannot be reached until a quote has passed the `093:4066` gate (§1.3).

At that instant, four doors close at once:

| # | What closes | Mechanism |
|---|---|---|
| 1 | **The row can never be deleted.** | `kernel.tickets.signing_key_id … ON DELETE RESTRICT` (`084:52-55`). Rehearsed: `DELETE` fails. |
| 2 | **`public_key` and `kms_handle_ref` can never be corrected.** | `kernel.guard_signing_key_immutable` (`083:84-101`) raises on any `UPDATE` of either — for superusers too. Rehearsed on all of `public_key`, `kms_handle_ref`, `scope`, target. |
| 3 | **Those atoms are pinned to this key forever.** | The mint writes `signing_key_id` at insert (`093:5003-5005`, superseding the old `083:557-559` site); `EDGE_SPEC:1287-1289` resolves the signer from the pin, never by fresh lookup; no re-pinning resolver exists (`088:606`, E-97). Rotation does **not** re-pin — rehearsed. |
| 4 | **Nothing can prove the key is honest after the fact.** | The mint validates only status/window/scope, and refuses a caller override (`093:4974-4976`) — it still cannot validate key material. A garbage `public_key` mints atoms no door can ever verify, and doors 1–3 mean it can be neither fixed nor removed. |

**The owner has accepted this explicitly:** *"a wrong key at launch is silent, deferred and
permanent, since the key is pinned at mint, rotation never re-pins, revoke is parked, and
the foreign key blocks deletion"* (`PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:711-717`).

**Therefore §5.3's binding proof is not a formality. It is the only thing standing between
the ceremony and a permanent, unrepairable trust root.**

Practical consequence: keep `feature.native_issuance_enabled` **false** until §7 has fully
passed and the evidence pack is signed. While it is false the mint refuses
`feature_disabled` and the bootstrap stays rollback-able. Rehearsed both directions.

---

## 12. ROTATION

`PRODUCTION DB MUTATION` · `OWNER APPROVAL REQUIRED` · **simultaneous** · same two roles,
same §4/§5 phases for the incoming key

`kernel.rotate_signing_key` is parked and stays parked. Rotation is a second ceremony.

**What rotation does and does not do:**

- Old key `active → rotating`, new key inserted `active`, in **one transaction**
  (`EDGE_SPEC:1521-1526`).
- The old row is **retained**, not deleted, not revoked. Its `public_key` stays readable,
  which is what keeps already-issued tickets verifiable.
- Existing atoms are **not** re-pinned. Rehearsed: 0 atoms moved.
- New mints resolve the new key. Rehearsed.
- Mints pinned to the now-`rotating` old key are refused with `no_active_signing_key`.
  Rehearsed.

Run §4 and §5 in full for the incoming key first, then:

```sql
-- ===========================================================================
-- signing_key_rotate.sql — CEREMONY ARTIFACT. Do not edit this file.
--   -v OLD_KEY_ID / -v NEW_KEY_ID / -v PUBLIC_KEY_PEM / -v KMS_HANDLE_REF
--   -v EXPECTED_FINGERPRINT
-- ===========================================================================
\set ON_ERROR_STOP on
begin;

create temp table rot_input on commit drop as
select :'OLD_KEY_ID'::uuid as old_key, :'NEW_KEY_ID'::uuid as new_key,
       :'PUBLIC_KEY_PEM'::text as pem, :'KMS_HANDLE_REF'::text as handle,
       lower(regexp_replace(:'EXPECTED_FINGERPRINT'::text, '[^0-9a-fA-F]', '', 'g')) as expected_fpr;

-- PRE-FLIGHT 1 — the outgoing key must exist, be ACTIVE and be the global key.
do $$
declare v_i record; v_k kernel.signing_key%rowtype;
begin
  select * into v_i from rot_input;
  select * into v_k from kernel.signing_key where key_id = v_i.old_key for update;
  if not found then raise exception 'ROTATION ABORT: OLD_KEY_ID % does not exist', v_i.old_key; end if;
  if v_k.status <> 'active' then raise exception 'ROTATION ABORT: OLD_KEY_ID is %, not active', v_k.status; end if;
  if v_k.scope <> 'global' then raise exception 'ROTATION ABORT: OLD_KEY_ID is scope %, this artifact rotates the global key only', v_k.scope; end if;
  if v_k.public_key = v_i.pem then raise exception 'ROTATION ABORT: the new public key is byte-identical to the outgoing one — no rotation occurred'; end if;
  if exists (select 1 from kernel.signing_key where key_id = v_i.new_key) then
    raise exception 'ROTATION ABORT: NEW_KEY_ID % already exists', v_i.new_key; end if;
end $$;

-- PRE-FLIGHT 2 — FINGERPRINT GATE on the incoming key.
do $$
declare v_i record; v_fpr text;
begin
  select * into v_i from rot_input;
  if v_i.pem !~ '-----BEGIN PUBLIC KEY-----' then raise exception 'ROTATION ABORT: PUBLIC_KEY_PEM is not an SPKI PEM public-key block'; end if;
  if v_i.pem ~ 'PRIVATE KEY' then raise exception 'ROTATION ABORT: PUBLIC_KEY_PEM contains PRIVATE KEY material — stop the ceremony'; end if;
  if length(v_i.expected_fpr) <> 64 then raise exception 'ROTATION ABORT: EXPECTED_FINGERPRINT is not 64 hex characters'; end if;
  v_fpr := encode(sha256(decode(regexp_replace(v_i.pem,'-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]','','g'),'base64')),'hex');
  if v_fpr <> v_i.expected_fpr then raise exception 'ROTATION ABORT: fingerprint mismatch — computed %, expected %', v_fpr, v_i.expected_fpr; end if;
  if v_i.handle is null or btrim(v_i.handle)='' or v_i.handle ~* '(BEGIN .*PRIVATE KEY|TODO|PLACEHOLDER|CHANGEME|<<<|>>>)'
    then raise exception 'ROTATION ABORT: KMS_HANDLE_REF is empty or a placeholder'; end if;
  if exists (select 1 from kernel.signing_key where kms_handle_ref = v_i.handle) then
    raise exception 'ROTATION ABORT: that KMS handle is already registered on another row — re-registration of the same key is not a rotation'; end if;
  raise notice 'ROTATION PRE-FLIGHT PASSED — incoming fingerprint %', v_fpr;
end $$;

-- capture the pre-rotation pinning census, to prove old atoms are not re-pinned.
create temp table rot_before on commit drop as
select ticket_atom_id, signing_key_id from kernel.tickets;

-- THE ROTATION — one transaction, old active→rotating, new active.
update kernel.signing_key set status='rotating'
 where key_id = (select old_key from rot_input);

insert into kernel.signing_key
       (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before, not_after)
select i.new_key, 'global', null, null, i.pem, i.handle, 'active', now(), null
  from rot_input i;

-- POST-CHECK — one active global key (the new one); the old key is retained
-- 'rotating' (NOT revoked, NOT deleted); no existing atom was re-pinned.
do $$
declare v_i record; v_n int; v_repinned int;
begin
  select * into v_i from rot_input;
  select count(*) into v_n from kernel.signing_key where status='active' and scope='global';
  if v_n <> 1 then raise exception 'ROTATION ABORT: % active global keys after rotation', v_n; end if;
  if (select status from kernel.signing_key where key_id=v_i.new_key) <> 'active'
    then raise exception 'ROTATION ABORT: the new key is not active'; end if;
  if (select status from kernel.signing_key where key_id=v_i.old_key) <> 'rotating'
    then raise exception 'ROTATION ABORT: the outgoing key is not in status rotating'; end if;
  select count(*) into v_repinned from kernel.tickets t join rot_before b using (ticket_atom_id)
   where t.signing_key_id is distinct from b.signing_key_id;
  if v_repinned <> 0 then raise exception 'ROTATION ABORT: % atom(s) were re-pinned', v_repinned; end if;
  raise notice 'ROTATION POST-CHECK PASSED — new key active, old key retained rotating, 0 atoms re-pinned';
end $$;

commit;
```

**Never set the outgoing key to `revoked` as part of a routine rotation.** `revoked` is
terminal (`083:95-98`) and, once M1/door verification exists, is the state that makes old
credentials fail closed. Routine rotation is `rotating`; revocation is §13.

---

## 13. COMPROMISE RESPONSE

Assume the KMS key, or the IAM principal that can sign with it, is compromised.

### Step 1 — STOP ISSUANCE (`PRODUCTION DB MUTATION`, minutes, in-band, works today)

The only in-band control that still functions with the lifecycle parked:

```bash
# PRODUCTION DB MUTATION — a platform_admin can execute this alone, deliberately:
# stopping the bleeding must not require a quorum.
psql "$PROD_DB_URL" -tAc "select catalog.set_platform_config('feature.native_issuance_enabled','false'::jsonb,'compromise','<COMMAND_KEY>');"
```

`feature.%` is **not** in the dual-control prefix set — the live body is now `093:6748-6751`
(the 093 replacement of `catalog.set_platform_config` added `fee.%`, `deletion.%`, `ticket.%`
to the prefix; `feature.%` still absent, superseding the old `078:1145-1147` citation), so
this is a single-admin act by design. Rehearsed: with the flag false, the mint refuses
`precondition_failed: feature_disabled` before it touches the key.

### Step 2 — REVOKE IN KMS (`KMS MUTATION`, immediate, provider-side)

Remove `kms:Sign` from every principal, then schedule the key for deletion. **This is the
control that actually stops signing.** The database has no power here.

### Step 3 — the database side, honestly

`kernel.revoke_signing_key` is **parked** — rehearsed, it raises
`dual_control_unavailable` and changes nothing, even for a platform admin. There is no
supported in-band revocation. Options, in order of preference:

1. **Rotate (§12)** to a fresh key. New issuance moves; old atoms keep verifying against
   the compromised key, which is the correct behaviour if the compromise is *custody* of
   the private key and not forgery of tickets.
2. **If forged credentials are the threat**, a superuser transaction may set
   `status='revoked'` and `not_after = now()`. The guard permits `rotating → revoked`
   and `active → revoked` (`083:95-98`); it is **terminal and irreversible**. Do this only
   with the owner's explicit go, because once door verification exists it invalidates every
   credential pinned to that key, and the atoms themselves cannot be re-pinned.
3. `venue.open_door_manifest` / door-episode force-closure on revocation is the PFA-18A
   forward obligation and **is not implemented** (`086:703-721`). Until it is, treat any
   revocation as leaving open door episodes stale for their TTL.

### Step 4 — evidence

Preserve the provider's audit trail for the compromise window before deleting the key.
Record which of options 1/2 was taken and why.

---

## 14. OLD-TICKET VERIFICATION AFTER ROTATION

The property Ruling B requires — *"Old issued tickets remain verifiable after rotation"* —
holds by construction, and was rehearsed end to end:

1. `kernel.tickets.signing_key_id` is written once at mint (`093:5003-5005`, superseding
   the old `083:557-559` site) and is not in any writer's update set thereafter.
2. The signer for an atom is resolved **from that pin**, never by a fresh lookup
   (`EDGE_SPEC:1287-1289`).
3. Rotation retains the old row with `status='rotating'` and its `public_key` intact, and
   the RLS policy is row-universal over the public projection (`083:118-124`) — so the
   verify key of a retired key stays distributable.
4. Rehearsed: a signature made before rotation still verified against the retired key's
   stored `public_key` after rotation, and failed against the new key's — which is exactly
   the required behaviour in both directions.

**The operational obligation this creates:** never delete a retired `signing_key` row, and
never let a retired row's `not_after` fall into the past unless you intend its credentials
to stop verifying. The §9.3 monitor watches `max_not_after` for this reason.

---

## 15. ADVERSARIAL REVIEW — WHAT THIS CEREMONY DOES AND DOES NOT PREVENT

Full evidence, with commands and outputs, in `docs/phase2/_impl/G3_signing_rehearsal.md`.
"PROVED" = the attack was attempted against a real replay of migrations 000–093 and the
listed outcome was observed.

| # | Attack | Verdict | Evidence / compensating control |
|---|---|---|---|
| ADV-1 | **Person A completes the ceremony alone** | **NOT PREVENTED BY THE DATABASE.** PROVED that Postgres enforces nothing: a superuser session can insert the row unaided. | Prevented **outside** the DB: A holds no production DB credential (§2 A5), and the bootstrap transaction aborts unless the fingerprint A did not compute matches. Compensating control: IAM separation + the §9.3 monitor. |
| ADV-2 | **Person B completes the ceremony alone** | **NOT PREVENTED BY THE DATABASE**, same mechanism. | B holds no `kms:CreateKey` (§2 B5), so B has no key to register. B *could* register a key from elsewhere; the compensating control is the provider audit trail (§9.1), which shows no `CreateKey` under the production principal. |
| ADV-3 | **An application admin swaps the public key** | **PREVENTED. PROVED.** As `authenticated` with `platform_admin` in the allowlist: `INSERT` / `UPDATE` / `DELETE` / window change all → `permission denied for table signing_key`. `provision`/`rotate`/`revoke` → `dual_control_unavailable`. `issue_ticket_atoms` → `permission denied for function`. | `kernel.signing_key` carries **only a column-level `SELECT`** grant to `authenticated` (`083:114-117`); no role holds `INSERT`/`UPDATE`/`DELETE`. |
| ADV-4 | **The KMS key id points at different material than the stored public key** | **NOT PREVENTABLE IN THE DATABASE. PROVED**: nothing validates the pair at `INSERT`; the guard is `BEFORE UPDATE` only. | Compensating control: the §5.3 binding proof, rehearsed in both directions (matched pair verifies; mismatched pair fails). It is the *only* detector, and it is why §5.3 is mandatory and simultaneous. |
| ADV-5 | **The DB public key diverges from the KMS key** (typo, wrong export, wrong version) | **PARTIALLY PREVENTED. PROVED.** The §6 fingerprint gate rejects any PEM that does not hash to the independently-computed fingerprint. It cannot detect a *consistently wrong* pair — that is ADV-4's job. | D4 additionally requires a version-pinned GCP handle, closing the "right key, wrong version" case. |
| ADV-6 | **A stale fingerprint is accepted** | **PREVENTED. PROVED**: supplying key 1's PEM with key 2's fingerprint aborts with `fingerprint mismatch — computed …, expected …`, and `count(*)` stays 0. | The gate compares computed-vs-expected inside the same transaction that writes. |
| ADV-7 | **The same key registered twice** | **SPLIT VERDICT.** As a second *active global* row: **PREVENTED. PROVED** — `duplicate key value violates unique constraint "signing_key_active_global_uq"`. As a `per_event` **shadow** carrying the identical public key and handle: **NOT PREVENTED. PROVED at all three resolver sites** (`per_event` outranks `global` at `085:1955-1960` = `093:4066-4074` = `093:4954-4966`) — reproduced against a live fixture on the rehearsal DB (`docs/phase2/_impl/KJ_kms_runbook_monitor.md` §2 E8: `["total_keys=2","scoped_keys=1"]`, and the checkout-time resolver returned the shadow's `key_id`). | Compensating controls: (a) no client role can insert at all (ADV-3), so this needs superuser; (b) the §9.3 monitor's `scoped_keys` invariant treats **any** `per_event`/`per_venue` row as an alert; (c) §12's rotation artifact refuses a handle already registered on another row. |
| ADV-8 | **Unauthorized activation** (a non-ceremony principal flips a key to `active`) | **PREVENTED for every client role. PROVED** — `authenticated`, `platform_admin` and `service_role` all get `permission denied`. **NOT PREVENTED for a superuser/`postgres` session.** | The compensating control is that superuser access is the deploy path itself; §9.3's `active_global` and fingerprint invariants detect the result. |
| ADV-9 | **An old key is silently disabled** (`rotating → revoked`, or `not_after` pulled into the past), breaking old tickets | **PREVENTED for client roles. PROVED** (`permission denied`). **NOT PREVENTED for a superuser**: `not_after` is deliberately outside the immutability guard's immutable-set (`083:88-91`), and `rotating → revoked` is a legal forward transition — both PROVED (the `not_after` update succeeded). | Compensating control only: the §9.3 monitor (099) alerts on `max_not_after` **and now explicitly on status** — `revoked_keys` and `rotating_keys` census columns, expected `0`/`0` until the first rotation — closing the gap the pre-099 §9.3 query left (it caught `active_global` drift only by side effect and could not see a `rotating → revoked` flip on a retired key). Recorded in §7.6 as a live gap: detection only, not prevention. |
| ADV-10 | **Malicious rotation** (rotate to an attacker key; or revoke the old key while rotating) | **PREVENTED for client roles. PROVED.** Against the §12 artifact specifically: re-registering the same key **PROVED ABORT**; a duplicate handle **ABORTS**; a non-`global` or non-`active` outgoing key **ABORTS**; re-pinning **ABORTS**. A superuser bypassing the artifact is not prevented. | The artifact makes the honest path easy and the dishonest path require deliberately not using it — which the §9.3 fingerprint invariant then surfaces. |
| ADV-11 | **A compromised KMS key** | **CONTAINED, NOT PREVENTED.** PROVED that the in-band stop works: with `feature.native_issuance_enabled=false` the mint refuses `feature_disabled` before touching the key. PROVED that `revoke_signing_key` is inert (`dual_control_unavailable`). | §13. Real revocation is a KMS/IAM act. The DB-side residual (no episode force-closure) is PFA-18A's open forward obligation. |
| ADV-12 | **`service_role` bypass** | **PREVENTED. PROVED, and strengthened by 093.** `service_role` has `BYPASSRLS=true` **and zero table privileges** on `kernel.signing_key` — `SELECT`, `INSERT` and `UPDATE` all → `permission denied for table signing_key`. RLS bypass is irrelevant without a grant. `service_role` **can** call `issue_ticket_atoms` (by design), but only against a key someone else created — and since 093 it can no longer pin a caller-supplied `signing_key_id` over the resolved one at all (`signing_key_override_refused`, `093:4974-4976`), closing the prior caller-supplied-key gap. | A leaked service-role key mints tickets under the honest key; it cannot create, alter, or shadow a signing identity. |
| ADV-13 | **CI secret leakage** | **NO LEAK FOUND. PROVED** by inspection: no workflow references KMS or key material; the ceremony runs no CI step; test fixtures use the literal non-keys `'PUBKEY'` / `'kms-handle-opaque'`. **One gap:** `.gitignore` lacks `*.der`/`*.sig`/`*.bin`. | §3's non-repository working-directory check, and §9.4. |
| ADV-14 | **Logs leak KMS references or key material** | **KEY MATERIAL: NO LEAK POSSIBLE** — the private key never reaches the database or any application process. **HANDLE: A REAL CHANNEL, PROVED as a mechanism.** No RPC returns `kms_handle_ref`; no `admin_audit` row, `notify` event, or edge function carries it (grep over `supabase/migrations/`, `supabase/functions/`, `src/`, `packages/`, `app/`). But the parked `provision_signing_key`/`rotate_signing_key` take it as a **parameter**, and Postgres logs the failing statement at `log_min_error_statement=error` (the default). | §0 rule 4: never pass the handle to a parked RPC. §6.2: never use the SQL editor. §7.1: verification never prints the handle. Residual exposure is bounded — `EDGE_SPEC:1293-1297`: the handle *"is a handle, so even its leak yields no signing ability without KMS IAM."* |

### The three things this ceremony cannot do

1. **It cannot make Postgres verify that the key is real.** Only the §5.3 binding proof can,
   and only at ceremony time. After the first mint, nothing can.
2. **It cannot stop a database superuser.** Every "NOT PREVENTED" verdict above reduces to
   this. The compensating control is the §9.3 monitor plus the operational no-direct-SQL
   policy that Ruling C already imposes.
3. **It cannot deliver in-band revocation.** PFA-18A parked it, and this ceremony
   deliberately does not un-park it. Compromise response is a KMS/IAM act plus a feature
   flag (§13).

---

## 16. ONE-PAGE SEQUENCE

| # | Step | Who | Marker |
|---|---|---|---|
| 1 | Owner go; D1–D7 recorded | Owner | `OWNER APPROVAL REQUIRED` |
| 2 | Pre-ceremony checks; `count(*) = 0`; six RPCs parked | A + B | `READ ONLY` |
| 3 | Create the key | A (B watches) | `KMS MUTATION` |
| 4 | Restrict the key policy; A drops `kms:Sign` after step 6 | A | `KMS MUTATION` |
| 5 | Export the public key independently; compute fingerprints; B states first | A + B | `READ ONLY` / `LOCAL` |
| 6 | **Binding proof** — A signs B's challenge through the handle; B verifies | A + B | `KMS MUTATION` |
| 7 | Run `signing_key_bootstrap.sql`; three NOTICEs + COMMIT | B (A reads aloud) | `PRODUCTION DB MUTATION` `IRREVERSIBLE AFTER MINT` |
| 8 | §7.1–§7.5 verification | A + B | `READ ONLY` (§7.5 rolls back) |
| 9 | Evidence pack signed; **monitor armed** — the §9.3 arming step: pin `signing.expected_key_fingerprint` (and `signing.expected_max_not_after` if D6 chose non-NULL), then `signing.monitor_enabled=true`, then confirm `kernel.check_signing_key_invariants()` returns `status:"ok"` | A + B + Owner | `PRODUCTION CONFIG` `OWNER APPROVAL REQUIRED` |
| 10 | *Later, separately:* flip `feature.native_issuance_enabled` | Owner | `PRODUCTION DB MUTATION` |

**Between steps 7 and 10 the bootstrap is still reversible (§10). After the first atom is
minted it is not (§11).**
