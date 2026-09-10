# PFA-18C — C2 CREATEKEY EXECUTION PACKAGE — **READY FOR OWNER AUTHORIZATION** (NOT AUTHORIZED · NOTHING EXECUTED)

> **RESULT (dated note 2026-09-10): EXECUTED AND COMPLETE** — see `PHASE2_PFA18C_C2_EXECUTION_RECORD.md` (key `45907419-8894-4582-ba79-71e9c29c549e`, policy v2, runtime bound, one successful proof `Sign` + two denied `Sign` probes). Coordinator label for the execution portion: **Claude B** (owner instruction 2026-09-10); the preparation-date label "Claude A" below is historical and preserved.

**Date:** 2026-09-09 (coordinator session 17, Claude A) · **Branch:** `feature/venue-native-and-product-v2` · **Prepared against:** production after C4 (migrations 110–114 applied 2026-09-09T04:22:52Z) and the C1 Phase-1 gate closed (M2 SATISFIED, rev 3).
**Nothing in this document was executed.** No KMS key was created, no challenge was signed, no DB row was added, no edge was deployed, no Supabase secret was written, no AWS or production mutation occurred. AWS and production state at the end of this session are identical to the state recorded after C4 (§2).
**C2 requires the separate exact owner phrase: `AUTHORIZE PFA-18C CREATEKEY`** (§4.1). This package is not that authorization.

Evidence classes: **CLAUDE-OBSERVED** (coordinator read-only reads this session), **OWNER-RETURNED** (prior Device-2/owner statements), **REHEARSAL** (local, throwaway keys), **OFFICIAL-DOC**.

Governance in force, unchanged: C18 (the founder runs every AWS/DB mutation; the coordinator reads back only), R5 (no pre-T3 exception; the §5.3 challenge signature is a KMS `Sign` over a Device-2 nonce and is **not** a production credential; C7/M5 stays pending), Model A before T3, never weaken the MFA trust condition, never collect passwords/OTPs/secrets/ExternalId.

---

## 0. Deliverable summary

| Item | Status |
|---|---|
| **C1-10** | **COMPLETE** — recorded 2026-09-09T04:03Z (gate report rev 3). **No Device-2 step is missing.** No new Device-2 activity was performed or needed this session; nothing was re-run (§1). |
| **M2** | **FULLY SATISFIED** (retrieval integrity, verifier identity, Device-2 passkey enrolled and used, independent read-back, refusal probes, CloudTrail read-back, coordinator corroboration with `mfaAuthenticated: "true"` on 84/84 verifier events and 0 successful verifier mutations). |
| **M1 (Model B)** | COMPLETE · **C1 PHASE-1 GATE** CLOSED · **C4** APPLIED + VERIFIED · **C2** NOT BEGUN · **C3/C5/C6** not begun · **C7** pending clarification · **Model A** before T3 |
| **C2 package** | This document — reviewed sequence from the packet (`6372538` §5b) + P3′ (2026-09-08) + the post-110–114 updates U1–U12 (§3). |
| **Owner phrase for the key-creation mutation** | **`AUTHORIZE PFA-18C CREATEKEY`** — scoped as in §4.1 |
| **AWS / production state** | **UNCHANGED** (§2: `kms list-keys` `[]`; 0 `CreateKey`/`PutKeyPolicy`/`ScheduleKeyDeletion`/`DisableKey` events since 2026-09-08; root `[]`; verifier no events since 04:03Z; runtime user 0 events ever; ledger 135 · tip 120 · `kernel.signing_key` 0 · guard enabled · recovery rows 0 · tickets 0 · issuance/scanning/monitor `false` · fingerprint `null`). |

---

## 1. C1-10 / M2 — status and Device-2 evidence summary (no secrets, QR values, passwords, tokens, or ExternalId)

The independent C1-10 procedure (packet §5a′ D2-0…D2-8; handoff `PFA18C_DEVICE2_RETRIEVAL_HANDOFF.md`) was executed by the owner-operator on Device 2 on 2026-09-08/09 and corroborated by the coordinator read-only. Per C18 the coordinator cannot operate Device 2; the record below is what was done and verified, step by step, against the request's five items.

| Requested item | Step | Result | Evidence class |
|---|---|---|---|
| Retrieve the exact pinned commit `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd` | D2-4 | **PASS** — 10/10 manifest files retrieved from the pinned commit; none of the three C2-only files downloaded | OWNER-RETURNED; digests CLAUDE-OBSERVED (re-verified this session: every pinned digest still equals the `git show c4f562d:…` digest and the HEAD digest — §6) |
| Verify every listed artifact hash | D2-4 | **PASS** — all ten SHA-256 values reproduced on Device 2 | OWNER-RETURNED |
| Verify the verifier identity | D2-3 | **PASS** — `sts get-caller-identity --profile verifier` → `arn:aws:iam::652872010073:user/snatchit-kms-verifier`; `GetCallerIdentity` 03:56:06Z CLAUDE-OBSERVED under the verifier identity, `mfaAuthenticated: "true"` | both |
| Enroll the Device-2 passkey | D2-2 | **PASS** — one MFA device on the verifier: `arn:aws:iam::652872010073:u2f/user/snatchit-kms-verifier/verifier-device2-passkey-6UJX6DTACNAOFIWOQQHF7RNEOA` (re-read 05:12:01Z; still the only device); `ConsoleLogin` `MFAUsed: Yes` with that identifier at 03:51:35Z and 03:55:08Z (us-east-2) | CLAUDE-OBSERVED |
| Run only the permitted read-only checks | D2-5, D2-6, D2-7 | **PASS** — D2-5 read-backs all `readOnly: true`, every diff empty; D2-6 refusal probes `PutBucketVersioning`/`AssumeRole`/`CreateAccessKey`/`AddTags` → `AccessDenied`, `CreateAlias` → `NotFoundException` (non-discriminating; P3′ at C2); D2-7 `LookupEvents` ×7 and final `kms ListKeys` → `[]`; **0 successful verifier mutations** | OWNER-RETURNED + CLAUDE-OBSERVED (CloudTrail) |
| Coordinator corroboration | D2-8 | **PASS** — gate report rev 3 (`PHASE2_PFA18C_C1_PHASE1_GATE_REPORT.md`), execution record sessions 12–14 | CLAUDE-OBSERVED |

**Verifier state now (CLAUDE-OBSERVED 05:12:01Z):** access keys `[]` (also `[]` on `snatchit-credential-sign-runtime` and `jose-admin`); attached policies exactly `SnatchIt-KMS-Verifier-ReadOnly` + `SignInLocalDevelopmentAccess`; roles `SnatchIt-KMS-Ceremony`, `SnatchIt-CredentialSign-Runtime` (the runtime role still has **no** permissions policy, inline or attached — as designed until C2); trail `snatchit-audit-trail` `IsLogging: true`, no delivery error.

**Residual (unchanged, not blocking):** the out-of-window root password-recovery events of 2026-09-08T01:17–01:18Z remain recorded for owner acknowledgement; no account password policy (hardening note).

---

## 2. Fresh read-only state (CLAUDE-OBSERVED, this session)

| Read | Result | UTC |
|---|---|---|
| `sts get-caller-identity` (coordinator) | `arn:aws:iam::652872010073:user/jose-admin` | 05:12:01 |
| `kms list-keys` / `kms list-aliases` | `[]` / only the 12 `alias/aws/*` service aliases (no customer alias) | 05:12:01 |
| CloudTrail since 2026-09-08T00:00Z: `CreateKey`, `PutKeyPolicy`, `ScheduleKeyDeletion`, `DisableKey`, `CreateGrant` | **0 each** | 05:12:38 |
| CloudTrail `CreateAlias` ×3 / `CreateAccessKey` ×2 since 2026-09-08 | exactly the known denied probes: `a99105a8…` (P3, ceremony role, 09-08 04:32Z), `a7899dcf…` and `c9b23820…` (D2-6, verifier); `14c7eee4…` and `f390806f…` (D2-6, verifier) — nothing new | 05:12:38 |
| verifier events since 04:03Z / runtime-user events ever / root since 09-08T02:40Z | `[]` / 0 / `[]` | 05:12:38 |
| `jose-admin` since 04:03Z | 23 events, all read-only (`ListKeys`, `LookupEvents`, list/get calls, one `CreateOAuth2Token` = the coordinator's `aws login` refresh); **0 with `readOnly: false`** | 05:12:38 |
| Production DB (read-only MCP) | ledger **135** · numeric tip **120** · `kernel.signing_key` **0** · `tg_signing_key_insert_guard` `tgenabled = 'O'` · `kernel.signing_key_recovery_approval` **0** rows · `kernel.tickets` **0** · `venue.get_manifest_signing_context()` → `{"status":"unavailable","code":"no_active_global_key"}` · census **153 / 87 / 32** | 05:15:00 |
| `catalog.platform_config` | `feature.native_issuance_enabled` **false** · `feature.native_scanning_enabled` **false** · `signing.monitor_enabled` **false** · `signing.expected_key_fingerprint` **null** · `signing.expected_max_not_after` **null** (all version 1) | 05:15:xx |
| Repository | consol tip `4e40f504a3e2a869869ee4e84987a8e896371fc8` (pushed); `git diff --stat c4f562d HEAD -- docs/release/pfa18c_artifacts/` **empty**; admin-console `562fda9…` clean | 05:11 |

**Statement:** AWS and production state were unchanged by this session. Every command run was a read (`get`, `list`, `describe`, `lookup-events`, `simulate-principal-policy`, `select`).

---

## 3. Review of the C2 package against production after migrations 110–114 — required updates

The previously reviewed C2 text (packet `6372538` §5b row "C2", plus the 2026-09-08 P3′ addition) predates C4. Production now enforces migration 110's BEFORE INSERT guard (rules 1–11) and exposes 114's `venue.get_manifest_signing_context()`. The following updates are **required**; U1–U6, U9, U10 are incorporated into §4 of this package; U7, U8, U11 are governance-text edits made in this commit; U12 is unchanged forward work.

| # | Finding | Update |
|---|---|---|
| **U1** | Guard rule 4 accepts `kms_handle_ref` only if it matches `^arn:aws:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` — a full key ARN; never an alias, bare id, or placeholder. | C2 records D4 = `KeyMetadata.Arn` verbatim and validates it with **exactly that regex** on both devices (C2-1, D2C-3) before C2 ends, so C3 cannot fail on the handle. (Rehearsed: a key ARN passes; an alias ARN and a bare id are rejected — §5.) |
| **U2** | Guard rule 6 accepts `public_key` only as exactly one SPKI PEM block whose DER is **91 bytes** with prefix `3059301306072a8648ce3d020106082a8648ce3d03010703420004` (id-ecPublicKey / prime256v1 / uncompressed `0x04` point); rule 5 refuses any `PRIVATE KEY` text. The §6.1 PRE-FLIGHT 2 recomputes SHA-256 over the base64-decoded PEM body — which must equal D5 (SHA-256 of `pub.der`). | Added explicit checks at D2C-4 (and mirrored on the primary): `wc -c pub.der` = 91, 27-byte prefix equality, `grep -c 'PRIVATE KEY' pub.pem` = 0, and a three-way D5 equality (`pub.der` hash = PEM→DER hash = base64-stripped-PEM hash). Rehearsed locally with a throwaway P-256 key: all three hashes equal (§5). |
| **U3** | Guard rule 11 makes `00000000-0000-0000-0000-0000000000b0` the only admissible first global `key_id` (ruling B); the §6.1 artifact already writes it (`insert … select '…b0', 'global', null, null, pem, handle, algorithm, 'active', now(), null`). | **Tag set change (owner to confirm):** add the informational tag `snatchit:db_key_id = 00000000-0000-0000-0000-0000000000b0` (and `snatchit:program = pfa18c`) to the key at creation so the KMS object carries the DB lineage id it will be bound to. Permission-neutral: the ceremony role's `AllowTagAtCreate` conditions only on `aws:RequestTag/snatchit:purpose` (simulator: allowed with the purpose tag present, implicitDeny without — §5); no policy anywhere conditions on the added keys. If the owner rejects the addition, delete the two extra `TagKey=…` pairs from C2-1; nothing else changes. |
| **U4** | 114's `venue.get_manifest_signing_context()` returns the active global row's `kms_handle_ref` to the door-manifest edge, and the E2 signer-scope check requires the runtime role's account + region to equal the ARN's. | The key **must** be created in `us-east-1` in `652872010073` (the profile pins both). Recorded as a C2 expected value (D4 prefix `arn:aws:kms:us-east-1:652872010073:key/`). Until C3 the function correctly returns `unavailable / no_active_global_key` — that is the expected post-C2 read, not a defect. |
| **U5** | Order actually executed: **C4 before C3** (owner's authorization of 2026-09-09). The runbook C4 row's precondition "C3 done" and §D "After C4 … returns `status:'ok'`" describe the other order. | Dated notes added to the runbook (this commit). Consequence for C2/C3: the guard is live for the C3 insert; the §6.1 artifact satisfies rules 1–11 (scope global, status active, ES256 explicit, full ARN, SPKI PEM, `…b0`, first row, no revoked row). C3 remains separately authorized ("AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT"). |
| **U6** | Reviewed text expected CloudTrail `PutKeyPolicy ×2`. `CreateKey --policy` sets v1 inside the `CreateKey` event; only v2 produces a `PutKeyPolicy` event. | Expected CloudTrail set corrected: `CreateKey` ×1, `Sign` ×1 success (proof) + the denied `Sign` probes, `PutKeyPolicy` ×1 (v2), `PutRolePolicy` ×1 (`jose-admin`), `CreateAlias` ×1 `AccessDenied` (P3′), `Verify` `AccessDenied` ×2, `GetPublicKey` by verifier/ceremony/coordinator; **0** `ScheduleKeyDeletion`/`DisableKey`/`CreateGrant`. |
| **U7** | Packet §6 status ledger was stale ("C1 not started", "110–114 no"). | Updated in this commit. |
| **U8** | Packet §5b C2 row pointed to `6372538` §5b prose. | Now points to this package. |
| **U9** | P3′ as written = live `create-alias` + live `verify` as the ceremony role. Live lifecycle probes (`ScheduleKeyDeletion`, `DisableKey`) against the production key are not acceptable even when a deny is expected. | P3′ keeps the two live probes (both explicit identity denies; worst case one removable alias / nothing) and adds the **read-only IAM simulator on the real ARN** for the whole lifecycle deny set of both principals (pre-run now on a placeholder ARN — every lifecycle action `explicitDeny`, §5). Verifier live probes on the real key: `sign`, `verify`, `create-alias` (now discriminating), `tag-resource`. |
| **U10** | The generic ceremony doc §4a uses `--tags TagKey=app,… TagKey=purpose,TagValue=ticket-signing` and a different description. The ceremony role's `AllowTagAtCreate` requires **`snatchit:purpose = ticket-signing`**; with the doc's `purpose` key the request would be refused (simulator: `implicitDeny` for `aws:RequestTag/purpose`) and no key created. | The PFA-18C package governs: tag key `snatchit:purpose`, description "Snatch It ticket-signing trust root (PFA-18C)". Trap recorded here and in the runbook. |
| **U11** | 114 L121 non-STRICT `select … into v_k` (edge fails closed; fix before C6); 086↔112/113 expired-episode drift (before scanning activation). | Unchanged; not C2 blockers. Guard rule 9 keeps ≤ 1 active global row, so the non-STRICT select cannot misbehave after C3. |
| **U12** | Model A required before T3 — not before C2/C3. C7/M5 pending §5d clarification. | Unchanged. C2 does not approach T3 (no credential is signed; issuance stays `false`). |

---

## 4. C2 package — CreateKey + §5.3 binding proof + P3′ + v2 + runtime binding

### 4.1 Authorization scope

The owner authorizes C2 by writing exactly **`AUTHORIZE PFA-18C CREATEKEY`**, scoped to:
- this package at its recorded commit (execution record session 17), and the artifacts `kms_key_policy_v1_binding_proof.json` `e0560a960a28d146476bbdfd35654949f9aeebad9ce69d7cc488d1f5d7515dc1`, `kms_key_policy_v2_final.json` `430677d0510ed67987d04a012223fe947ccd0fa1948044215cb52dbf775b2d9d`, `m3_runtime_role_policy.json` `bb3a2c4f86f532d2d0743e4755e9aaa67fd77d3997a820c211efbb90b0517b52` (placeholder; filled locally with D4 only), unchanged since pin `c4f562d…`;
- the exact key specification, description and tag set of §4.4 (the owner strikes the two informational tags if not wanted — U3);
- these mutations, in this order, each by the named principal: C2-1 `CreateKey` (ceremony role) · C2-5 one `Sign` over Device 2's challenge (ceremony role) · C2-3/C2-6 the P3′ probes (expected denials) · C2-7 `PutKeyPolicy` v2 (ceremony role; F1 fallback `jose-admin`, logged) · C2-8 `PutRolePolicy` on `SnatchIt-CredentialSign-Runtime` (`jose-admin`).

It does **not** authorize: the C3 DB insert, C5 monitor arming, C6 secrets/deploy, any access key, any alias, grant, rotation, deletion (rollback needs its own phrase, §4.10), any change to the artifacts, `--bypass-policy-lockout-safety-check`, any Sign other than the single proof, issuance/scanning, payments, PFA-18A, Organizations/Model A.

### 4.2 Principals, sessions, devices

| Role | Principal | Session |
|---|---|---|
| Ceremony (mutations C2-1, C2-5, C2-7, probes) | `arn:aws:iam::652872010073:role/SnatchIt-KMS-Ceremony` via profile `snatchit-ceremony` (`role_arn`, `source_profile = snatchit-admin`, `role_session_name = pfa18c-ceremony`, `mfa_serial = …:mfa/jose-admin-totp`, `duration_seconds = 3600`, `region = us-east-1`) | CLI prompts for the TOTP; identity must read `arn:aws:sts::652872010073:assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony`. **1-hour session** — if it expires mid-C2, re-run `get-caller-identity` (new TOTP) and continue; record the second `AssumeRole` event. |
| Admin (C2-8 `PutRolePolicy`; F1 fallback; rollback) | `jose-admin` via `snatchit-admin` (`aws login` session, ≤ 12 h) | primary machine |
| Verifier (Device 2, read-only + refusal probes) | `snatchit-kms-verifier` via profile `verifier` (Device 2 only; fresh passkey login) | Device 2 |
| Coordinator (read-only corroboration) | `jose-admin` read calls only | primary machine |

Never used: root; any access key; the runtime user (no key exists until C6).

### 4.3 Preflight (all must pass minutes before C2-1; any failure ⇒ do not start)

| # | Who | Check | Expected |
|---|---|---|---|
| P1 | coordinator | `git -C /Users/josetascon/snatchit-consol rev-parse HEAD`; `git status --porcelain` shows only the owner's two pre-existing uncommitted files; `shasum -a 256` of the three C2 artifacts | tip = the session-17 commit or later with **identical** artifact digests (§6) |
| P2 | Device 2 | retrieve, from GitHub at pin `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd`, exactly: `docs/release/pfa18c_artifacts/kms_key_policy_v1_binding_proof.json`, `…/kms_key_policy_v2_final.json`, `…/m3_runtime_role_policy.json`; and this package at its session-17 commit | digests `e0560a96…`, `430677d0…`, `bb3a2c4f…` (full values §6) |
| P3 | Device 2 | `aws logout --profile verifier`; console sign-in with the Device-2 passkey; `aws login --profile verifier --region us-east-1`; `aws sts get-caller-identity --profile verifier` | verifier ARN; coordinator later confirms `ConsoleLogin MFAUsed: Yes` + `mfaAuthenticated: "true"` |
| P4 | owner | `aws sts get-caller-identity --profile snatchit-ceremony --no-cli-pager` (TOTP prompt) | assumed-role ARN `…/SnatchIt-KMS-Ceremony/pfa18c-ceremony` |
| P5 | owner + Device 2 + coordinator | `aws kms list-keys --region us-east-1` from all three | `[]` |
| P6 | coordinator | production: `select count(*) from kernel.signing_key` = 0; ledger 135; guard `O`; flags `false`; `get_manifest_signing_context()` = `no_active_global_key` | as §2 |
| P7 | coordinator | `iam get-role` ×2, `iam list-role-policies SnatchIt-CredentialSign-Runtime` `[]`, `iam list-access-keys` ×3 `[]`, `cloudtrail get-trail-status` `IsLogging: true` | as §1 |
| P8 | coordinator | CloudTrail: 0 `CreateKey`/`PutKeyPolicy`/`ScheduleKeyDeletion`/`DisableKey` since 2026-09-08; root `[]` | as §2 |
| P9 | owner | `$ART` set: `export ART=/Users/josetascon/snatchit-consol/docs/release/pfa18c_artifacts`; `jq -S . $ART/kms_key_policy_v1_binding_proof.json >/dev/null` (valid JSON); `mkdir -p $HOME/pfa18c-local` | ok |

### 4.4 Exact key specification

| Parameter | Value | Why |
|---|---|---|
| Region / account | `us-east-1` / `652872010073` | R1; E2 signer-scope (U4) |
| `KeySpec` | `ECC_NIST_P256` | D2 = ES256; ceremony role condition `kms:KeySpec` |
| `KeyUsage` | `SIGN_VERIFY` | condition `kms:KeyUsage` |
| `Origin` | `AWS_KMS` | condition `kms:KeyOrigin`; no import, no custom key store, no XKS |
| `MultiRegion` | `false` (`--no-multi-region`) | condition `kms:MultiRegion` |
| `BypassPolicyLockoutSafetyCheck` | `false` (`--no-bypass-policy-lockout-safety-check`) | condition; F1 |
| `Description` | `Snatch It ticket-signing trust root (PFA-18C)` | reviewed package text |
| **Tag set (exact)** | `snatchit:purpose = ticket-signing` (**permission-bearing** — required by `AllowTagAtCreate`, the tag-scoped read/PutKeyPolicy/Sign allows, and the P3′ design) · `snatchit:program = pfa18c` (informational, U3) · `snatchit:db_key_id = 00000000-0000-0000-0000-0000000000b0` (informational, U3) | tag values are public metadata; no secret |
| Key policy at creation | `kms_key_policy_v1_binding_proof.json` (`e0560a96…`) — v1: root→IAM delegation minus all crypto ops; ceremony `Sign` (ECDSA_SHA_256) + `PutKeyPolicy/GetKeyPolicy/DescribeKey` (F1 lockout safety) — both **REMOVED_IN_V2**; runtime role `Sign` (ECDSA_SHA_256, RAW); verifier + ceremony reads | principals exist since 2026-09-08 (F2 satisfied) |
| Key policy final | `kms_key_policy_v2_final.json` (`430677d0…`) — ceremony keeps reads only; runtime `Sign` only; nobody has `Verify` | C2-7 |
| Alias | **none, ever** (D4 is the ARN; guard rule 4 rejects aliases) | — |
| Grants / automatic rotation | none / not applicable to asymmetric keys | — |
| Expected `KeyMetadata` | `KeyState Enabled`, `KeyManager CUSTOMER`, `SigningAlgorithms ["ECDSA_SHA_256"]`, `MultiRegion false`, `Origin AWS_KMS`, `KeySpec ECC_NIST_P256`, `KeyUsage SIGN_VERIFY` | abort on any difference (A3) |

### 4.5 Exact commands and read-backs (owner runs; coordinator and Device 2 read back)

`D4` below = the `Arn` returned by C2-1, pasted into a shell variable on each device (`D4=arn:aws:kms:us-east-1:652872010073:key/<uuid>`). It is public.

**C2-1 — CreateKey (ceremony role; the only creation mutation)**
```bash
export ART=/Users/josetascon/snatchit-consol/docs/release/pfa18c_artifacts
aws kms create-key \
  --profile snatchit-ceremony --region us-east-1 --no-cli-pager --output json \
  --key-spec ECC_NIST_P256 --key-usage SIGN_VERIFY --origin AWS_KMS \
  --no-multi-region --no-bypass-policy-lockout-safety-check \
  --description "Snatch It ticket-signing trust root (PFA-18C)" \
  --tags TagKey=snatchit:purpose,TagValue=ticket-signing TagKey=snatchit:program,TagValue=pfa18c TagKey=snatchit:db_key_id,TagValue=00000000-0000-0000-0000-0000000000b0 \
  --policy file://$ART/kms_key_policy_v1_binding_proof.json \
  --query KeyMetadata
```
Record: `KeyId`, **`Arn` = D4**, `CreationDate`, `KeySpec`, `KeyUsage`, `Origin`, `MultiRegion`, `KeyState`, `KeyManager`, `SigningAlgorithms`. Then validate D4 on the spot:
```bash
D4='<paste Arn>'; echo "$D4" | grep -Eq '^arn:aws:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' && echo D4-FORMAT-OK || echo ABORT-A3
echo "$D4" | grep -q '^arn:aws:kms:us-east-1:652872010073:key/' && echo D4-SCOPE-OK || echo ABORT-A3
```

**C2-2 — immediate read-backs (ceremony role; coordinator mirrors as `jose-admin`; Device 2 as verifier)**
```bash
aws kms describe-key --profile snatchit-ceremony --key-id "$D4" --query 'KeyMetadata.[KeySpec,KeyUsage,Origin,MultiRegion,KeyState,KeyManager,SigningAlgorithms]'
aws kms get-key-policy --profile snatchit-ceremony --key-id "$D4" --policy-name default --output text --query Policy \
  | jq -S 'walk(if type=="array" and all(.[]; type!="object") then sort else . end)' > /tmp/live_v1.json
jq -S 'walk(if type=="array" and all(.[]; type!="object") then sort else . end)' $ART/kms_key_policy_v1_binding_proof.json | diff - /tmp/live_v1.json && echo V1-DIFF-EMPTY
aws kms list-resource-tags --profile snatchit-ceremony --key-id "$D4" --query 'Tags[].[TagKey,TagValue]' --output text | sort
aws kms list-keys --profile snatchit-ceremony --query 'length(Keys)'          # 1
aws kms list-aliases --profile snatchit-ceremony --query 'Aliases[?!starts_with(AliasName,`alias/aws/`)]'   # []
```
Expected tags (sorted): `snatchit:db_key_id 00000000-0000-0000-0000-0000000000b0` · `snatchit:program pfa18c` · `snatchit:purpose ticket-signing`.

**C2-3 — P3′-a: alias denial on the real key (ceremony role)**
```bash
aws kms create-alias --profile snatchit-ceremony --alias-name alias/pfa18c-probe --target-key-id "$D4"
```
Expected: `AccessDeniedException … explicit deny in an identity-based policy`. If it **succeeds** ⇒ abort A7 (rollback: `jose-admin` `aws kms delete-alias --alias-name alias/pfa18c-probe`; investigate before anything else).

**C2-4 — public key, D5 fingerprint, guard-format checks (Device 2 first, then the primary independently)** — commands in §4.7 D2C-4; the primary repeats them with `--profile snatchit-ceremony`. Device 2 states D5 first; primary and coordinator each compute their own; all three must be identical.

**C2-5 — §5.3 binding proof (one `Sign`; not a production credential — R5)**
Device 2 mints and reads the challenge aloud (D2C-5). Owner recreates it byte-for-byte on the primary (`printf '%s' '<challenge text>' > challenge.bin`; `shasum -a 256 challenge.bin` must equal Device 2's value), then:
```bash
aws kms sign --profile snatchit-ceremony --key-id "$D4" \
  --message fileb://challenge.bin --message-type RAW --signing-algorithm ECDSA_SHA_256 \
  --output text --query Signature | tee challenge.sig.b64 | base64 --decode > challenge.sig
cat challenge.sig.b64      # public; transfer to Device 2 out of band (read/paste); also record it as evidence
```
Device 2 verifies against **its own** `pub.pem` (D2C-5) → `Verified OK`; altered message → `Verification failure`; throwaway key → `Verification failure`.

**C2-6 — P3′-b: verify denial (ceremony role) + verifier probes**
```bash
aws kms verify --profile snatchit-ceremony --key-id "$D4" --message fileb://challenge.bin --message-type RAW \
  --signature fileb://challenge.sig --signing-algorithm ECDSA_SHA_256      # expected AccessDeniedException (explicit deny)
```
Device 2 runs D2C-6 (`sign`, `verify`, `create-alias`, `tag-resource` as the verifier → all `AccessDenied`).

**C2-7 — key policy v2 (ceremony role; F1 fallback `jose-admin`, never the bypass flag)**
```bash
aws kms put-key-policy --profile snatchit-ceremony --key-id "$D4" --policy-name default --policy file://$ART/kms_key_policy_v2_final.json
aws kms get-key-policy --profile snatchit-ceremony --key-id "$D4" --policy-name default --output text --query Policy \
  | jq -S 'walk(if type=="array" and all(.[]; type!="object") then sort else . end)' > /tmp/live_v2.json
jq -S 'walk(if type=="array" and all(.[]; type!="object") then sort else . end)' $ART/kms_key_policy_v2_final.json | diff - /tmp/live_v2.json && echo V2-DIFF-EMPTY
```
If `put-key-policy` returns `MalformedPolicyDocumentException … lockout` for the ceremony role: run the same command with `--profile snatchit-admin` (logged as the F1 fallback); still never `--bypass-policy-lockout-safety-check`.

**C2-8 — runtime role binding to the exact ARN (`jose-admin`; the ceremony role is denied `iam:*`)**
```bash
jq --arg arn "$D4" '.Statement[0].Resource = $arn' $ART/m3_runtime_role_policy.json > $HOME/pfa18c-local/m3_runtime_role_policy.filled.json
grep -c "$D4" $HOME/pfa18c-local/m3_runtime_role_policy.filled.json   # 1
grep -c '<' $HOME/pfa18c-local/m3_runtime_role_policy.filled.json     # 0
shasum -a 256 $HOME/pfa18c-local/m3_runtime_role_policy.filled.json  # record (non-secret: it contains only the ARN)
aws iam put-role-policy --profile snatchit-admin --role-name SnatchIt-CredentialSign-Runtime --policy-name pfa18c-runtime-sign \
  --policy-document file://$HOME/pfa18c-local/m3_runtime_role_policy.filled.json
aws iam get-role-policy --profile snatchit-admin --role-name SnatchIt-CredentialSign-Runtime --policy-name pfa18c-runtime-sign --query PolicyDocument \
  | jq -S . | diff - <(jq -S . $HOME/pfa18c-local/m3_runtime_role_policy.filled.json) && echo RUNTIME-POLICY-DIFF-EMPTY
aws iam list-role-policies --profile snatchit-admin --role-name SnatchIt-CredentialSign-Runtime   # ["pfa18c-runtime-sign"]
```
The ExternalId in the runtime role trust is **never** read, printed, or transferred.

**C2-9 — post-v2 negatives (ceremony role) and simulator (read-only, `jose-admin`)**
```bash
aws kms sign --profile snatchit-ceremony --key-id "$D4" --message fileb://challenge.bin --message-type RAW --signing-algorithm ECDSA_SHA_256   # expected AccessDeniedException (no key-policy grant)
aws iam simulate-principal-policy --profile snatchit-admin --policy-source-arn arn:aws:iam::652872010073:role/SnatchIt-KMS-Ceremony \
  --action-names kms:CreateAlias kms:DeleteAlias kms:UpdateAlias kms:Verify kms:ScheduleKeyDeletion kms:DisableKey kms:CreateGrant kms:UntagResource --resource-arns "$D4" \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]'          # every row explicitDeny
aws iam simulate-principal-policy --profile snatchit-admin --policy-source-arn arn:aws:iam::652872010073:user/snatchit-kms-verifier \
  --action-names kms:Sign kms:Verify kms:CreateAlias kms:TagResource kms:ScheduleKeyDeletion kms:DisableKey kms:PutKeyPolicy --resource-arns "$D4" \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]'          # every row explicitDeny
aws iam simulate-principal-policy --profile snatchit-admin --policy-source-arn arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime \
  --action-names kms:Sign --resource-arns "$D4" \
  --context-entries ContextKeyName=kms:SigningAlgorithm,ContextKeyValues=ECDSA_SHA_256,ContextKeyType=string ContextKeyName=kms:MessageType,ContextKeyValues=RAW,ContextKeyType=string \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]'          # allowed (IAM side; key policy v2 also allows)
aws iam simulate-principal-policy --profile snatchit-admin --policy-source-arn arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime \
  --action-names kms:Sign kms:DescribeKey --resource-arns arn:aws:kms:us-east-1:652872010073:key/00000000-0000-0000-0000-000000000000 \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]'          # Sign implicitDeny (other key); DescribeKey explicitDeny
```

**C2-10 — CloudTrail corroboration (coordinator; Device 2 mirrors with `--profile verifier`)** — allow ≤ 15 min index lag:
`CreateKey` ×1 by `pfa18c-ceremony` (`sessionContext.attributes.mfaAuthenticated: "true"`, `sessionIssuer SnatchIt-KMS-Ceremony`), `Sign` ×1 success by `pfa18c-ceremony` and the denied `Sign` probes (ceremony post-v2 ×1, verifier ×1), `Verify` `AccessDenied` ×2, `CreateAlias` `AccessDenied` ×2 (ceremony, verifier), `TagResource` `AccessDenied` ×1 (verifier), `PutKeyPolicy` ×1 (v2; by `pfa18c-ceremony` or, if F1 fallback, `jose-admin` — recorded either way), `PutRolePolicy` ×1 by `jose-admin`, `GetPublicKey` by verifier/ceremony/`jose-admin`; **0** `ScheduleKeyDeletion`/`DisableKey`/`CreateGrant`/`EnableKey`; root `[]`; every verifier event `mfaAuthenticated: "true"`.

**C2-11 — C3 compatibility precheck (read-only; no DB write)** — coordinator re-reads production (`signing_key` 0, ledger 135, guard `O`, flags `false`) and records, for C3: D4 (passes rule 4), `pub.pem` (rules 5/6 verified at C2-4), `ALGORITHM=ES256` (rule 3), D5. **C3 is not started** — it needs "AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT".

### 4.6 P3′ — alias / verify denial probes (summary)

| Probe | Principal | Command | Expected | If wrongly allowed |
|---|---|---|---|---|
| P3′-a | ceremony | `create-alias alias/pfa18c-probe → D4` (C2-3) | `AccessDenied` (explicit identity deny `DenyKeyLifecycleMutationDuringCeremony`) | one alias; `jose-admin` `delete-alias`; **abort A7** |
| P3′-b | ceremony | `verify` with the proof signature (C2-6) | `AccessDenied` (explicit identity deny; no key-policy `Verify` for anyone) | nothing changes; **abort A7** |
| P3′-c | verifier (Device 2) | `sign` / `verify` / `create-alias` / `tag-resource` on D4 (D2C-6) | `AccessDenied` ×4 (explicit `DenyEverythingThatCouldMutateOrSign`) | alias/tag removable by `jose-admin`; **abort A7** |
| P3′-d | ceremony, post-v2 | `sign` (C2-9) | `AccessDenied` (implicit — key policy no longer grants) | **abort A12** |
| P3′-e | simulator (read-only) | lifecycle deny set on D4 for ceremony + verifier; runtime `Sign` scoped to D4 only (C2-9) | as listed | **abort A7/A12** |

P3 (2026-09-08, `NotFoundException`) stays INCONCLUSIVE; P3′-a/-c on the real key are the discriminating replacements.

### 4.7 Device-2 verification procedure for C2 (M2 independent verification; verifier profile only)

| Step | Action | Expected |
|---|---|---|
| D2C-0 | retrieve the three C2-only artifacts at pin `c4f562d…` + this package (P2); `shasum -a 256` each | digests §6 |
| D2C-1 | fresh passkey session (P3); `aws sts get-caller-identity --profile verifier` | verifier ARN |
| D2C-2 | `aws kms list-keys --profile verifier` **immediately before** the owner runs C2-1 | `[]` |
| D2C-3 | after C2-1, with D4 received out of band: `describe-key` (7 fields as §4.4), `get-key-policy` normalized diff vs v1 → empty, `list-resource-tags` → the exact three, `list-keys` → 1, `list-aliases` → no non-`alias/aws/` entry; D4 regex + `us-east-1:652872010073` prefix check | all as expected |
| D2C-4 | `aws kms get-public-key --profile verifier --key-id "$D4" --output text --query PublicKey \| base64 --decode > pub.der`; `wc -c pub.der` → **91**; `head -c 27 pub.der \| xxd -p \| tr -d '\n'` → `3059301306072a8648ce3d020106082a8648ce3d03010703420004`; `openssl pkey -pubin -inform DER -in pub.der -out pub.pem`; `grep -c 'PRIVATE KEY' pub.pem` → 0; `openssl pkey -pubin -in pub.pem -text -noout \| head -3` → `Public-Key: (256 bit)`; **D5** = `openssl dgst -sha256 -hex pub.der \| awk '{print $2}'`; cross-checks `openssl pkey -pubin -in pub.pem -outform DER \| shasum -a 256` and `sed -e '/-----/d' pub.pem \| tr -d '\n' \| base64 --decode \| shasum -a 256` → all three equal; **Device 2 states D5 first** | 64 lowercase hex; identical on all devices |
| D2C-5 | `printf 'snatchit-ceremony %s %s' "$(date -u +%Y%m%dT%H%M%SZ)" "$(openssl rand -hex 16)" > challenge.bin; cat challenge.bin; shasum -a 256 challenge.bin` (read both aloud); after the owner's C2-5: `printf '%s' '<signature base64>' \| base64 --decode > challenge.sig`; `openssl dgst -sha256 -verify pub.pem -signature challenge.sig challenge.bin` → **`Verified OK`**; `cp challenge.bin altered.bin; printf 'x' >> altered.bin; openssl dgst -sha256 -verify pub.pem -signature challenge.sig altered.bin` → `Verification failure`; `openssl ecparam -name prime256v1 -genkey -noout -out wrong.pem; openssl pkey -in wrong.pem -pubout -out wrong_pub.pem; openssl dgst -sha256 -verify wrong_pub.pem -signature challenge.sig challenge.bin` → `Verification failure`; then `rm -f wrong.pem altered.bin` (keep `pub.pem`, `pub.der`, `challenge.bin`, `challenge.sig` as public evidence until recorded, then §5.4 cleanup of the challenge files) | PASS / FAIL / FAIL |
| D2C-6 | verifier refusal probes on the real key: `aws kms sign --profile verifier --key-id "$D4" --message fileb://challenge.bin --message-type RAW --signing-algorithm ECDSA_SHA_256`; `aws kms verify --profile verifier --key-id "$D4" --message fileb://challenge.bin --message-type RAW --signature fileb://challenge.sig --signing-algorithm ECDSA_SHA_256`; `aws kms create-alias --profile verifier --alias-name alias/pfa18c-probe --target-key-id "$D4"`; `aws kms tag-resource --profile verifier --key-id "$D4" --tags TagKey=probe,TagValue=x` | `AccessDenied` ×4 |
| D2C-7 | after C2-7/C2-8: `get-key-policy` normalized diff vs v2 → empty; `jq --arg arn "$D4" '.Statement[0].Resource = $arn' m3_runtime_role_policy.json > filled.json`; `aws iam get-role-policy --profile verifier --role-name SnatchIt-CredentialSign-Runtime --policy-name pfa18c-runtime-sign --query PolicyDocument \| jq -S . \| diff - <(jq -S . filled.json)` → empty; `aws iam get-role --profile verifier --role-name SnatchIt-CredentialSign-Runtime --query 'Role.AssumeRolePolicyDocument.Statement[0].[Principal.AWS,Action,keys(Condition.StringEquals)]'` → `[runtime user ARN, "sts:AssumeRole", ["sts:ExternalId"]]` (value never printed); `describe-key` → `Enabled`; `list-keys` → 1; `list-access-keys` ×3 → `[]` | all as expected |
| D2C-8 | `aws cloudtrail lookup-events --profile verifier --lookup-attributes AttributeKey=EventName,AttributeValue=CreateKey --start-time <C2 start>` → exactly 1 (by `pfa18c-ceremony`); same for `PutKeyPolicy` (1), `PutRolePolicy` (1), `ScheduleKeyDeletion`/`DisableKey` (0); `AttributeValue=root` → `[]` | matches C2-10 |
| D2C-9 | coordinator corroboration (`jose-admin`, read-only): every D2C read repeated; verifier session `mfaAuthenticated: "true"` on all events; production darkness re-read (`signing_key` 0, ledger 135, flags `false`) | recorded in the execution record; **C2 CLOSED** only if every row above passed |

### 4.8 Evidence to record / never record

Record (execution record + this package's result section): `KeyMetadata` (all fields), D4, D5, the three tags, v1/v2 diff results, the challenge text and its SHA-256, the signature base64, the three verify outcomes, every probe's error code, the filled runtime-policy digest, CloudTrail event ids for `CreateKey`/`Sign`/`PutKeyPolicy`/`PutRolePolicy` and the denied probes, timestamps, and which principal ran each step.
Never record: TOTP codes, passwords, `aws login` tokens, session credentials, the runtime ExternalId, any private material (none exists — the key never leaves KMS), Device-2 QR/enrolment values.

### 4.9 Abort conditions (stop; no further mutation; report; owner decides)

| # | Condition |
|---|---|
| A1 | ceremony identity is not `assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony`, or no TOTP prompt occurred |
| A2 | `CreateKey` errors (`AccessDenied`, `MalformedPolicyDocument`, `LimitExceeded`…) — no key exists; **do not retry with a changed spec, policy, tag key, or the bypass flag**; return to review |
| A3 | any `KeyMetadata` field differs from §4.4, D4 fails the regex, or D4 is not in `us-east-1:652872010073` |
| A4 | key-policy read-back ≠ v1 (before C2-7) or ≠ v2 (after) |
| A5 | tag set ≠ the exact three (or the exact one, if the owner struck U3) |
| A6 | `list-keys` ≠ exactly 1 customer key, or any non-`alias/aws/` alias exists |
| A7 | any P3′ probe **succeeds** |
| A8 | `pub.der` ≠ 91 bytes, prefix mismatch, `PRIVATE KEY` text, or the three D5 computations disagree |
| A9 | D5 differs between Device 2, primary, and coordinator |
| A10 | proof `Verified OK` fails, or the altered-message / wrong-key control **passes** |
| A11 | `PutKeyPolicy` v2 fails for the ceremony role **and** for the `jose-admin` fallback |
| A12 | post-v2 ceremony `Sign` still succeeds |
| A13 | CloudTrail shows `CreateKey` by any other principal, more than one `CreateKey`, any `ScheduleKeyDeletion`/`DisableKey`/`CreateGrant`, or any root event |
| A14 | any step needs a credential outside the designated principal, or anything asks for a secret/OTP/ExternalId to be pasted or shown |
| A15 | production changes during C2 (`signing_key` ≠ 0, ledger ≠ 135, any flag ≠ `false`, guard not `O`) |
| A16 | ceremony session expired and the re-assume fails (leave the key as-is; record; resume only after review) |

### 4.10 Rollback (only if C2 aborted after C2-1; requires its own phrase **`AUTHORIZE PFA-18C C2 ROLLBACK`**)

The key exists but nothing references it (no DB row — C3 never ran; no edge; no secret). Rollback is by `jose-admin` (the key policy's root→IAM delegation covers lifecycle; the ceremony role and verifier are explicitly denied):
1. if C2-8 ran: `aws iam delete-role-policy --profile snatchit-admin --role-name SnatchIt-CredentialSign-Runtime --policy-name pfa18c-runtime-sign`;
2. if an alias/tag was wrongly created: `aws kms delete-alias --alias-name alias/pfa18c-probe` / `aws kms untag-resource --key-id "$D4" --tag-keys probe`;
3. `aws kms schedule-key-deletion --profile snatchit-admin --key-id "$D4" --pending-window-in-days 7` → record `KeyState PendingDeletion`, `DeletionDate`; Device 2 reads `describe-key` back;
4. the retired ARN is **never** reused; a re-run needs a fresh `AUTHORIZE PFA-18C CREATEKEY` and produces a new D4/D5. `CancelKeyDeletion` inside the window is possible but also requires an owner decision.
Cost: a pending-deletion key is not billed; an enabled key is ~USD 1/month prorated.

### 4.11 Post-C2 state (expected) and next

One enabled `ECC_NIST_P256` key, policy v2, three tags, no alias/grant; runtime role bound to D4 with `Sign` only; ceremony role reads only; verifier reads only; `kernel.signing_key` still **0**; `get_manifest_signing_context()` still `no_active_global_key`; flags `false`; edges not deployed; no secret written. **Next, each separately authorized:** C3 (`AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT` — §6.1 artifact with D4 / `pub.pem` / D5 / `ES256`), C5, C6; C7 pending §5d; Model A before T3.

---

## 5. Tests performed for this package (read-only / local; CLAUDE-OBSERVED 05:17Z)

**IAM policy simulator (read-only, placeholder ARN `…:key/00000000-0000-0000-0000-000000000000`, no resource tags):**

| Principal | Action(s) | Context | Decision |
|---|---|---|---|
| ceremony | `kms:CreateKey` | KeySpec ECC_NIST_P256, KeyUsage SIGN_VERIFY, KeyOrigin AWS_KMS, MultiRegion false, Bypass false | **allowed** |
| ceremony | `kms:CreateKey` | same but Bypass **true** / KeySpec **RSA_2048** | implicitDeny / implicitDeny |
| ceremony | `kms:TagResource` | `aws:RequestTag/snatchit:purpose = ticket-signing` / `aws:RequestTag/purpose = ticket-signing` | **allowed** / implicitDeny (U10 trap confirmed) |
| ceremony | `CreateAlias`, `DeleteAlias`, `UpdateAlias`, `Verify`, `ScheduleKeyDeletion`, `DisableKey`, `CreateGrant`, `UntagResource`, `Decrypt` | — | **explicitDeny** ×9; `iam:PutRolePolicy`, `sts:AssumeRole` implicitDeny |
| ceremony | `Sign`, `PutKeyPolicy`, `GetPublicKey`, `DescribeKey` | `aws:ResourceTag/snatchit:purpose = ticket-signing`, SigningAlgorithm ECDSA_SHA_256 | **allowed** ×4 (tag-scoped, as reviewed) |
| verifier | `GetPublicKey`, `DescribeKey`, `GetKeyPolicy`, `ListResourceTags` | — | allowed ×4 (`ListAliases` shows implicitDeny only because the simulator bound a key ARN to a `*`-resource action; the policy allows it on `*`) |
| verifier | `Sign`, `Verify`, `CreateAlias`, `TagResource`, `ScheduleKeyDeletion`, `DisableKey`, `PutKeyPolicy` | — | **explicitDeny** ×7 |
| runtime role (today) | `Sign`, `GetPublicKey` | — | implicitDeny ×2 (no permissions policy until C2-8) |

**Local rehearsal (throwaway P-256 key, OpenSSL 3.6.3; deleted afterwards):** `pub.der` = **91** bytes; prefix = `3059301306072a8648ce3d020106082a8648ce3d03010703420004`; `PRIVATE KEY` count 0; `Public-Key: (256 bit)`; D5 computed three ways identical (`pub.der`, PEM→DER, base64-stripped PEM — i.e. the §6.1 PRE-FLIGHT 2 recomputation); challenge format produced 51 bytes; DER signature 71 bytes; matched pair **`Verified OK`**; altered message **`Verification failure`**; wrong key **`Verification failure`**; guard rule-4 regex: key ARN PASS, alias ARN REJECT, bare id REJECT. Command syntax confirmed against `aws-cli/2.36.40` (`--no-multi-region`, `--no-bypass-policy-lockout-safety-check`, `--message-type`, `--signing-algorithm`).

Not tested (impossible without the key; deferred to C2 itself): the real lockout-safety evaluation of v1 at `CreateKey` and of v2 at `PutKeyPolicy` (F1 fallback stands), KMS's own DER output (expected 91 bytes for `ECC_NIST_P256`), CloudTrail attribution of the assumed-role session.

---

## 6. Artifact hashes (SHA-256; CLAUDE-OBSERVED at HEAD `4e40f504…` and at pin `c4f562d…` — identical)

```
e0560a960a28d146476bbdfd35654949f9aeebad9ce69d7cc488d1f5d7515dc1  docs/release/pfa18c_artifacts/kms_key_policy_v1_binding_proof.json   (C2)
430677d0510ed67987d04a012223fe947ccd0fa1948044215cb52dbf775b2d9d  docs/release/pfa18c_artifacts/kms_key_policy_v2_final.json           (C2)
bb3a2c4f86f532d2d0743e4755e9aaa67fd77d3997a820c211efbb90b0517b52  docs/release/pfa18c_artifacts/m3_runtime_role_policy.json            (C2, placeholder)
1fddd53beee238063da99a26db3f301c546ee9c111685c5a5f630e0f930bd4d5  docs/release/pfa18c_artifacts/m1_ceremony_role_policy.json           (live, unchanged)
89540f612449a3e540f851f1e62082b2c3263e2a9849f6b0f4fcbbec41baf4b7  docs/release/pfa18c_artifacts/m1_ceremony_role_trust.json            (live, unchanged)
3082cc74824ef68c47cd2fc39caf0d45b7765f2880936cdb8bb0d08a2cb46889  docs/release/pfa18c_artifacts/m2_verifier_policy.json                (live, unchanged)
a1cb864406c73fc674fc264e8a73efe93ebdbbf5f4aed0a05a9ee94641569c9f  docs/release/pfa18c_artifacts/m3_runtime_user_policy.json            (live, unchanged)
8ebd036a5a71c914b5c8f44589505c9ba71dc5907e0e856403ed0961e5412fd8  docs/release/pfa18c_artifacts/m3_runtime_role_trust.json             (placeholder; live has the ExternalId — never printed)
76addba388521b9c04806ab81d560e1563ae59a75b33ea3fe61ed0cd2b4392f0  docs/release/pfa18c_artifacts/m1_audit_bucket_policy.json            (live, unchanged)
9a4c5a8dad1f6bc7f6a8cb5510e3f8af9e5ec5065fedf75c0997e48698ef7ab0  docs/release/pfa18c_artifacts/m1_object_lock_configuration.json      (live, unchanged)
505fe850bdcf6cc8336d8e53d37514eea4a28df40810f24475096f76d813443c  docs/release/pfa18c_artifacts/README.md
f19f9df4f953217379cdee6704822fa7fd6c122a3b2b5f9ef1c59c10f04c387b  docs/release/pfa18c_artifacts/model_a/scp_workload_guardrails.json   (Model A, not for C2)
f5ba7074e24229989fb594983358dbf1ee1b6758384183ff296c565c6717d93e  docs/release/pfa18c_artifacts/model_a/org_audit_bucket_policy.json   (Model A, not for C2)
```
Production migrations relied on (applied, digests as authorized): 110 `3134f6f63e4ff1b100120508152eb696d9acf101a5a109e37a8938ba3d1f7390` (guard), 114 `9974eb91fd51acba9786c60366460e53a304807129600f46a197740b21455cee` (signing context).

---

## 7. Mutation ledger (this session)

AWS: **none** (reads + `simulate-principal-policy` only). KMS: **not created**; 0 keys. Production DB: **none** (read-only `select`s). Secrets / edges / flags: **none / not deployed / unchanged**. Local: throwaway rehearsal keys in the session scratchpad, deleted. Repository: this package; packet §5b C2 row + §6 ledger; runbook dated notes; execution record session 17.
