# PFA-18C — DARK PRE-CEREMONY AUDIT (final)

**Date:** 2026-09-05/06 · **Branch:** `feature/venue-native-and-product-v2` · **Audited tree:** commit `1f3fc19` (tests + runbook corrections) on top of `ade9af9`
**Scope:** migrations 110–114 and their rollbacks, `credential-sign` / `door-session` / `door-manifest` edges, SCANNER-CONTRACT-v1 (`_shared/offline-verify.ts`), the E2 KMS runtime provider (`credential-sign/kms-taxonomy.ts`, `kms.ts`), the production ceremony artifacts (`docs/release/pfa18c_artifacts/`, runbook `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`).
**Standing:** LOCAL / REHEARSAL ONLY. Nothing here was deployed; no production database call, no AWS call or resource, no secret, no billing change, no activation. Production stays at ledger 124 / numeric tip 109 / 0 signing keys / dark (last read-only precheck recorded in the execution record; not re-read for this audit by design).
**Owner runbook (deliverable 8):** `docs/release/PHASE2_PFA18C_OWNER_CEREMONY_RUNBOOK.md`.

Evidence classes: **REPO-VERIFIED** (read from the tree at the audited commit), **REHEARSAL-OBSERVED** (run against the local rehearsal database this session), **CI-OBSERVED** (GitHub Actions run), **OWNER-RETURNED** (earlier, quoted), **NOT OBSERVED** (stated as such).

---

## 1. Migrations 110–114 — order, rollbacks, checksums, census, replay / idempotence

**Canonical apply order** (harness = `LC_ALL=C` filename sort; positions in the full list): 110 (#120) → 111 (#121) → 112 (#122) → 113 (#123) → 114 (#124). All five are the numeric tail; nothing sorts between them. REPO-VERIFIED.

**Rollback order:** strictly reverse — 114 → 113 → 112 → 111 → 110. Note the dependency: 111's rollback re-creates the 110 guard body verbatim (rule 10 reverts to "parked, no approvals mechanism"), so 111 must be rolled back before 110; 113's rollback restores 112's staff body verbatim; 114 drops two functions and touches nothing else. REPO-VERIFIED + REHEARSAL-OBSERVED.

| # | Migration | sha256[0:16] | Rollback | sha256[0:16] | Objects | Census delta |
|---|---|---|---|---|---|---|
| 110 | `110_signing_key_insert_guard.sql` | `3134f6f63e4ff1b1` | `110_signing_key_insert_guard_rollback.sql` | `933a2941cdc14070` | +`kernel.guard_signing_key_insert()` + BEFORE INSERT trigger | kernel fns 149→150; five-schema 288→289 |
| 111 | `111_signing_key_recovery_two_person.sql` | `d13cf6cba2b08742` | `111_…_rollback.sql` | `1c4a282779467225` | +table `kernel.signing_key_recovery_approval` (RLS on, zero policies/grants) + 3 kernel fns; guard re-created (rule 10 = two approvals) | kernel tables 31→32; kernel fns 150→153; five-schema 289→292 |
| 112 | `112_get_door_manifest_headers.sql` | `97d33d0862a6c8da` | `112_…_rollback.sql` (086 body, generated) | `ba1061893c18cb1a` | body-only re-create `venue.get_door_manifest` | none |
| 113 | `113_get_door_manifest_door_machine_authority.sql` | `32d42324b2b21667` | `113_…_rollback.sql` (112 body, generated) | `4b9551535ed03f6e` | +`venue._get_door_manifest_core` (zero grant) +`venue.get_door_manifest_door` (service_role); staff RPC body-only | venue fns 83→85; five-schema 292→294 |
| 114 | `114_signing_key_door_delivery_and_manifest_signing_context.sql` | `9974eb91fd51acba` | `114_…_rollback.sql` | `f61fee26fad6c378` | +`venue.get_signing_keys_door` +`venue.get_manifest_signing_context` (both service_role-only) | venue fns 85→87; five-schema 294→296 |

Gate-2 public census unchanged throughout: tables 27 / functions 70 / policies 37 / triggers 26 (fresh replay, REHEARSAL-OBSERVED). The 140 anon/PUBLIC/authenticated sweep is unmoved (every new function revokes PUBLIC; none grants anon/authenticated). Census assertions moved and re-derived from the live catalog: 141 F2 (+2 authenticated for 111), 141 C1, 143/144/148/142/154 kernel counts (153), 144 A15 / 145 A4 / 148 B5 (venue 87), 148 B2 / 156 A20 / 157 A46 (five-schema 296), 176–180 own A-blocks.

**Replay / idempotence (REHEARSAL-OBSERVED, this session):**
- Fresh `scripts/rehearsal_reset.sh` through 114 → `kernel 153 · venue 87 · five-schema 296 · kernel tables 32 · insert guard present`; chain-definition hash (md5 over the nine 110–114 function definitions) **`4d20f9f6cee6d69ccee2791066adbfb4`**.
- Reverse rollback chain, census after each step: 114→ `153|85|294|32|1|748ae0f8…` · 113→ `153|83|292|32|1|8d288b9e…` · 112→ `153|83|292|32|1|005a591a…` · 111→ `150|83|289|31|1|9d2863d3…` · 110→ `149|83|288|31|0|78419b22…` (guard gone).
- Reapply chain 110→114: `9d2863d3…` → `005a591a…` → `8d288b9e…` → `748ae0f8…` → **`4d20f9f6…`** — every intermediate hash equals the corresponding rollback-state hash and the final hash equals the fresh-replay hash. Double-apply of 112/113/114 individually produced identical hashes (earlier this session). Suites 176/177/178/179/180 after the chain: 51/67/41/45/42 all green.
- Full pgTAP after the chain (fresh run, ended 2026-09-06T00:51:44Z): **plan 3941 · ok 3937 · not_ok 4** — only the documented local deltas 060×2 / 132×2.
- G-4 (`scripts/ci/assembled_migration_integrity.sh`): PASS.

**Production state of these five:** NOT applied (ledger 124, numeric tip 109). Each carries `AUTODEPLOY-VERIFIED-OFF` obligations per the standing merge rule; the owner runbook lists the apply order and the read-backs.

## 2. M1 delivery through `/keys`

REPO-VERIFIED (114 body, `door-session/index.ts` `handleKeys`, `pure.ts` `buildKeysMachineCall`) + REHEARSAL-OBSERVED (180 B/C, evidence fixture `door_keys*`).

- **Route:** `POST …/door-session/keys`, body `{session_id, device_id}`, bearer `DoorSession <door_session_id>.<secret>`. Edge preamble = parse bearer → per-door-session rate limit (60/60, uuidv5 principal) → `kernel.assert_door_session` (opaque-auth gate) → device-id cross-check → machine call.
- **Binding:** the RPC `venue.get_signing_keys_door(session, door_session_id, token, device)` re-asserts the door session in the database and derives `(device, event_session)` itself; body ids are cross-checks only. A mismatch, wrong token, unknown id, revoked or expired door session, inactive device or PIN ⇒ the ONE opaque `42501 door_session_invalid` (180 C1–C4, E2; evidence `door_keys_wrong_token/_wrong_session/_service_role_no_credentials`).
- **Scope selection:** rows where `scope='global'` OR (`per_event` AND `event_id` = the bound session's event) OR (`per_venue` AND `venue_id` = the bound session's venue). All statuses and windows are returned (active / rotating / revoked / future `not_before`) — the verifier applies `key_revoked` / `key_window`; the RPC never pre-filters so a device can refuse a revoked key by name. Unrelated event and venue rows are absent (180 B4–B6, B9; evidence: 6 rows, `e_other_unrelated` and `v_other_unrelated` absent).
- **Projection:** exactly `key_id, scope, event_id, venue_id, public_key, algorithm, status, not_before, not_after` per row (180 B7; evidence asserts the sorted key set per row). Never `kms_handle_ref`, identity, or private material (180 B8; fixture leak scan clean). Envelope `{session_id, event_id, venue_id, generated_at, keys}` → `m1FromDoorKeysResponse` (fails closed on a bare array or missing `keys`).
- **Denial:** anon and authenticated (even with VALID door credentials) ⇒ `42501 permission denied for function` (grant class, not role; 180 C5–C6); service_role without credentials ⇒ `door_session_invalid`; the staff path is unchanged (authenticated reads the table projection; `kms_handle_ref` still fenced — 180 C7–C8, A7–A9).
- **Status/window handling on the device:** `m1FromWire` → `M1Entry` (`not_after NULL` ⇒ +∞); `offlineVerify` step 1 / `verifyDoorManifestSignature` refuse `key_revoked`, then `key_window`, then `alg_mismatch`, then `malformed_public_key`. Rotating keys stay verifiable in window. Evidence: boundaries on real rows (rotating key verifiable AT `not_after`, refused after; future key refused before `not_before`, window-ok at it).

## 3. Door-manifest signing

REPO-VERIFIED (`door-manifest/index.ts` steps 4–7, `pure.ts`, `_shared/offline-verify.ts`) + REHEARSAL-OBSERVED (evidence artifact, 180 D) + `tests/m5-mocked-signer-rehearsal.test.ts`.

- **Canonical digest bytes:** `canonicalManifestDigestBytes(open)` = `JSON.stringify({manifest_id, manifest_version, session_id, not_after, manifest_digest})` in that key order, UTF-8 — byte-identical to the scanner's `canonicalDoorManifestSignedBytes` (parity unit test). `not_after`/`session_id` are the stored `venue.door_manifest` row values (112; `not_after` immutable by trigger). Never manufactured at fetch.
- **Database-derived identity:** `venue.get_manifest_signing_context()` (114, service_role, called only after the caller was authorized by `venue.get_door_manifest`) returns the single active global `kernel.signing_key` row: `key_id, kms_handle_ref, algorithm, public_key, key_status, not_before, not_after`, or `unavailable` with a stable code (`no_active_global_key | ambiguous_active_global_key | key_window | algorithm_not_es256`). The env-only `DOOR_MANIFEST_KMS_HANDLE_REF` inference no longer exists in the tree (grep: only the comment naming its removal).
- **ES256 + active/window re-pin at the edge:** `classifyManifestSigningContext(v, now)` re-checks `algorithm === 'ES256'`, `key_status === 'active'`, `not_before ≤ now < not_after`; any deviation ⇒ `500 manifest_signing_key_unavailable` / `manifest_signing_context_malformed`, KMS never reached. The row's `public_key` is normalized by the shared `normalizeSpkiPublicKey` (P1-PUBKEY-FORMAT) BEFORE signing; a non-P-256 SPKI ⇒ `manifest_signing_key_malformed`, never KMS.
- **Sign-then-verify binding proof:** `kmsSigner.sign(row.kms_handle_ref, bytes, 'ES256')` → `verifyEs256WithWebCrypto(normalizedRowKey, bytes, sig)`; `false` ⇒ `500 manifest_signing_unhealthy`, Sentry, no retry, nothing emitted. Rehearsed with a mocked signer: a handle bound to a different key fails here on both edges; and if such an artifact were emitted anyway the scanner refuses `signature_invalid`. Combined with E2's key-ARN scope check (`kms_handle_scope_mismatch`: region + role account must match the ARN), a signature can leave the edge only if it verifies under the public key of the row whose `key_id` it names.
- **Envelope:** `signature = {value: base64(raw R‖S 64 bytes), algorithm:'ES256', key_id}` — exactly three fields, built from primitives (`buildSignatureEnvelope`); no handle, no public key, no identity (PFA-24) in the response.
- **Opaque errors and redaction:** caller authorization failures from `get_door_manifest` ⇒ `403 insufficient_privilege` with no existence leak; closed ⇒ `200 {manifest, signature:null}`; malformed ⇒ `500 manifest_malformed`; KMS taxonomy ⇒ `kms_unavailable (503, Retry-After 5) | kms_security_error (500) | kms_unconfigured (500)`; every Sentry/log payload carries stable codes and non-secret selectors only — the E2 core allow-lists STS/KMS error identifiers and never surfaces bodies that restate the key ARN or principal; `door-session` scrubs the bearer secret from any error text (`redactSecret`) and its log field set is fixed. Fixtures: leak scan for `kms_handle_ref`, ARN, PEM private material, secrets, `token_hash`, `door_session:` preimage — clean.

## 4. The end-to-end state machine (credential → offline verify → M2 sync → online scan → offline reconcile)

REPO-VERIFIED; each edge in the chain is rehearsed by pgTAP and vitest; the whole chain is not executed live (no Deno, no KMS).

```
[owner app]  credential-sign (staff/owner JWT, verify_jwt)                        ── dark until KMS_PROVIDER=aws + key row
   1 auth (JWT → auth.uid())  2 rate limit 30/60 fail-closed  3 body {ticket_atom_id}
   4 kernel.get_ticket_signing_context(atom)  → owner gate (not_owner), terminal gate (atom_terminal),
     PINNED key_id (kernel.tickets.signing_key_id; never a fresh scope lookup) → {key_id, kms_handle_ref, public_key, algorithm, ttl, exp}
   5 canonical payload (typ/kid/alg header; 5 claims) 6 kms:Sign(handle) 6b sign-after-verify under public_key 7 token
[device, online]  door-session /mint (venue PIN + device → bearer)  → /keys (M1)  → /manifest/sync (M2 full, then since_delta_seq)
   each relay: bearer → rate limit → assert_door_session → machine RPC RE-asserts, derives bound (device, session)
   M2 = venue.get_door_manifest_door → _get_door_manifest_core (open+unexpired episode by STORED not_after; entries; deltas > since)
   door-manifest (staff JWT) signs the M2 header with the active global key → {manifest, signature{value,algorithm,key_id}}
[device, offline]  OFFLINE-VERIFY-v1 (`offlineVerify`): decode token (malformed_token) → step 1 M1[kid] (unknown_key/key_revoked/key_window/
   alg_mismatch/malformed_public_key/signature_invalid) → exp → authority (no_manifest/manifest_expired/wrong_session by BOUND session)
   → 3b atom in applied M2, not revoked, credential_version match (stale_version) → 3c token.key_id == M2[atom].signing_key_id
   → local admitted set (duplicate) → ADMIT (device-attributed)
[device, online scan]  /scan → venue.record_scan_door → _record_scan_core: feature.native_scanning_enabled gate → session admitting gate
   → kernel.mark_ticket_scanned (custody state machine) → venue.scan row; first-in-wins duplicate
[device, back online]  /offline-batch → venue.reconcile_offline_scans_door → _reconcile_core: deterministic order, per-item isolation,
   item session ≠ bound session ⇒ conflict, each item → _record_scan_core ⇒ {admitted, duplicates, conflicts}
[revocation]  kernel.revoke_signing_key (platform_admin+aal2) → status revoked, force-closes open episodes (105/109) → reconnecting devices lose
   M2 authority; devices offline across the revoke keep admitting until their downloaded not_after (accepted residual, door §8.2.1);
   next M1 refresh refuses the key by name (key_revoked).
```

Invariants that hold across the chain (each pinned by a test): the actor and the key are server-derived (JWT / pinned row / door session), never body fields; scope is decided by the door session (108/113/114) — the machine can EXECUTE but cannot pick device/session/key; the same normalizer, algorithm pin, status/window and canonical-bytes rules are used by the edge that signs and the verifier that checks; every non-contract shape fails closed before any signer call; `feature.native_issuance_enabled` / `feature.native_scanning_enabled` are independent kill switches that refuse `feature_disabled` before any key is touched.

## 5. M6 / "M7" — recovery and revocation gates (exact parked / owner-gated points)

"M7" is **not** a label in the ratification; this section reads it as the revocation + post-revoke recovery pair (E4) alongside M6.

| Gate | Where | State in the tree | State in production | Who can pass it |
|---|---|---|---|---|
| M6 insert guard (rules 1–11) | 110 `kernel.guard_signing_key_insert`, BEFORE INSERT on `kernel.signing_key` | implemented, rehearsal-tested (176: 51) | **NOT applied** — required BEFORE ISSUANCE (ratification), does not block the dark bootstrap | nobody bypasses it: global-only, active-only, ES256-only, full KMS ARN, no private material, exactly one P-256 SPKI PEM, advisory-locked, no duplicate key_id, one active global, rule 10 post-revoke parked, rule 11 first row must be `…b0` |
| Post-revoke recovery | 111 `approve_/execute_signing_key_recovery` + guard rule 10 | implemented, rehearsal-tested (177: 67) | **NOT applied** | two DISTINCT platform_admin identities each on aal2, approvals within 30 min, executor must be an approver, fingerprint-bound; refused until exactly one revoked global key exists and zero active |
| Revocation | 106 `kernel.revoke_signing_key` | un-parked | **applied** (numeric tip 109) | single platform_admin on aal2 (PFA-18B), `p_ack_live_credentials` acknowledgement; terminal; force-closes open episodes (105/109) |
| Provision / rotate | `kernel.provision_signing_key`, `kernel.rotate_signing_key` | **parked** (`dual_control_unavailable`) | parked | nobody (PFA-18A forward obligation) |
| Pass-type certs | `provision_/rotate_/revoke_pass_type_cert` | parked | parked | nobody |
| Bootstrap INSERT | runbook §6.1 artifact (ruling B key_id `…b0`, explicit `ALGORITHM=ES256`) | M4 fixed | not run | owner, personally, under C18, only after the "AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT" checkpoint |
| Monitor arming | `signing.expected_key_fingerprint`, `signing.expected_max_not_after`, `signing.monitor_enabled` (099) | seeded null/false | seeded null/false | owner config act after §7 verification (dual-control prefix per 102 P3) |
| Issuance / scanning | `feature.native_issuance_enabled`, `feature.native_scanning_enabled` | false | false | owner, separately, after M5 + M6 + Model A |

Runbook defects found and corrected (dated notes, historical text retained): §7.3's "all six must raise dual_control_unavailable" loop would print a false STOP for `revoke_signing_key`; §13 Step 3 described revoke as parked and force-close as unimplemented. Commit `1f3fc19`.

## 6. M5 — rehearsal with a mocked signer, and the minimum live proof

**Rehearsed now (`tests/m5-mocked-signer-rehearsal.test.ts`, 7; plus `credential-sign-sts-provider.test.ts` 27 and `credential-sign-kms.test.ts` for the adapter):** with the KMS adapter replaced by an in-process ES256 signer that records handle + algorithm, both edges run their complete path — context → canonical bytes → sign(handle from the row) → sign-after-verify → token / envelope → verifier side. Proven: the edges hand the DB-derived handle (never an env value) and `ES256` to the signer; a MIS-BOUND handle fails sign-after-verify on both edges and would be refused `signature_invalid` by the scanner; no-active-key / EdDSA / window / private-material contexts never reach the signer; D5 fingerprint = SHA-256 over the normalizer's DER. E2 tests cover STS AssumeRole (temporary-only, identity check, early refresh, single-flight, retry classes), KMS response validation (wrong algorithm / wrong key echoed ⇒ SECURITY), key-ARN scope, and redaction.

**Minimum live proof still required after an authorized ceremony (NOT rehearsable; the E5 acceptance):** one `credential-sign` call (dark deploy with `KMS_PROVIDER=aws`, E2 role env set) for ONE throwaway atom on a non-saleable test event ⇒ token returned, sign-after-verify PASS in the deployed edge (log outcome `signed`); CloudTrail shows exactly ONE `Sign` by the runtime role on the exact key ARN and none by any other principal; `feature.native_issuance_enabled` stays `false` throughout; the token verifies offline with M1 read through `/keys` from a real door session. Then one `door-manifest` call on a real open episode ⇒ `signed`, and `verifyDoorManifestSignature` passes against `/keys` M1 (second `Sign` event). Both recorded in the execution record with the CloudTrail event ids.

## 7. Signed M1 bundles (edge §5.4.2)

**Status: intentionally deferred (not implemented).** Protection that applies today: staff/client M1 = TLS + PostgREST auth (`authenticated`) + RLS column fence; door-device M1 = TLS + the door-session bearer gate re-asserted in the database (`assert_door_session`, 114) + the service_role-only machine RPC. A tampering adversary therefore needs to break TLS or Supabase auth, not merely observe traffic. Residual: a compromised Supabase project or edge could serve a substituted keyring; a signed bundle would let a device detect that using a key it already trusts.

**Precise protocol change if adopted later (identified, not made):** (1) a new signed artifact type `M1-BUNDLE-SIG-v1` — canonical bytes = `JSON.stringify({generated_at, session_id, keys:[rows sorted by key_id]})` with the 9-field rows in a fixed key order, signed ES256 by the active global key, envelope `{value, algorithm, key_id}`; (2) trust-anchor rule: a device may only verify a bundle with a key it ALREADY holds (first-run bootstrap of the anchor is out-of-band — pinned in the app build or the door PIN QR), otherwise a substituted bundle would self-certify; (3) verifier changes: `m1FromDoorKeysResponse` gains a mandatory signature check before the keyring is accepted; (4) edge change: `door-session /keys` needs KMS access (today only `credential-sign` and `door-manifest` sign), which widens the runtime role's blast radius to a third function — an owner decision (M3 scope); (5) governance: SCANNER-CONTRACT-v1 §2 and edge §5.4.2 wording, plus a KOFFLINE/KEDGES ratification note. None of these are semantics changes to existing artifacts; they add one artifact type and one verifier precondition.

## 8. Owner runbook

Delivered as a single document: `docs/release/PHASE2_PFA18C_OWNER_CEREMONY_RUNBOOK.md` (preflight read-only checks, artifacts to capture, mutations requiring explicit authorization, post-mutation verification, abort/rollback conditions, Free-plan no-go conditions).

---

## Evidence summary (this audit session)

| Check | Result | Class |
|---|---|---|
| Fresh replay through 114 | Gate-2 27/70/37/26; kernel 153 · venue 87 · five-schema 296; chain hash `4d20f9f6…` | REHEARSAL-OBSERVED |
| Reverse rollback 114→110, reapply 110→114 | every intermediate census + hash inverts exactly; final hash identical | REHEARSAL-OBSERVED |
| pgTAP 176/177/178/179/180 after the chain | 51/67/41/45/42, all green | REHEARSAL-OBSERVED |
| Full pgTAP (fresh, ended 2026-09-06T00:51:44Z) | plan 3941 · ok 3937 · not_ok 4 (060×2/132×2 documented) | REHEARSAL-OBSERVED |
| Vitest | 22 files, **803 passed (803)** (incl. `m5-mocked-signer-rehearsal` 7) | REHEARSAL-OBSERVED |
| typecheck / lint | clean / 0 errors (45 pre-existing warnings) | REHEARSAL-OBSERVED |
| G-4 | PASS | REHEARSAL-OBSERVED |
| Secret scan over committed fixture + files | clean | REHEARSAL-OBSERVED |
| CI (incl. Deno type-check of all three edges) | run **34002456147** at `1f3fc19`: Deno type-check success · Typecheck/Lint/Unit success · Migrations success · Web build success | CI-OBSERVED |
| Production state | ledger 124, tip 109, 0 keys, dark — from the last recorded precheck; **not re-read this session** | NOT OBSERVED (by design) |

## Unresolved risks

1. **CreateKey is NO-GO in account 652872010073 while the Free plan is kept** (owner decision, P0-FREEPLAN): hard horizon 2027-03-05 + 90-day erase; Object-Lock COMPLIANCE retention ends with account closure. Nothing in this audit changes that.
2. **No live KMS / Deno execution locally:** the edge code paths are proven by unit tests, CI type-check, and real-RPC output — not by a live request. M5 live proof remains outstanding (§6).
3. **Signed M1 bundles deferred** (§7): keyring integrity rests on TLS + auth gates.
4. **Model A (separate audit account + SCP) required before T3; account layout must be settled BEFORE CreateKey** (SCPs do not bind an Organizations management account).
5. **Operational bindings the ceremony must get right** (D3/D4/D5, E2 role scope): enforced after the fact by 110's guard, the 099 monitor, E2's scope check and the edges' sign-after-verify — a wrong binding fails closed rather than silently, but still costs a re-ceremony.
6. **Migrations 110–114 are unapplied in production**; the merge-to-main rule (`AUTODEPLOY-VERIFIED-OFF`, empty `git_branch`) must be honoured for every one.
7. **Rehearsal fixtures share one throwaway PEM across keyring rows**; identity is pinned by `key_id`/status/window, not distinct material — a fixture limitation only.

## Implemented / rehearsal-tested / deployed / operationally-verified

| Item | Implemented | Rehearsal-tested | Deployed | Operationally verified |
|---|---|---|---|---|
| 110 M6 insert guard | yes | yes (176; concurrency probe) | no | no |
| 111 two-person recovery | yes | yes (177) | no | no |
| 112 M2 header | yes | yes (178; real RPC evidence) | no | no |
| 113 door machine authority | yes | yes (179; real RPC evidence) | no | no |
| 114 M1 delivery + manifest key identity | yes | yes (180; real artifact verification) | no | no |
| E2 KMS runtime provider | yes | yes (mocked network) | no | no |
| credential-sign / door-session / door-manifest edges | yes | unit + CI Deno type-check | no | no |
| SCANNER-CONTRACT-v1 + golden fixtures | yes | yes | n/a (contract) | external scanner: not built |
| M5 end-to-end credential-sign | mocked rehearsal only | yes (mocked) | no | **no — requires the ceremony** |
| Ceremony artifacts (IAM/S3/KMS policies) | drafted | n/a | **not applied to AWS** | no |
| Signed M1 bundles | no (deferred, §7) | — | — | — |
