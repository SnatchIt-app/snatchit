# PFA-18C — C2 CREATEKEY EXECUTION RECORD — **COMPLETE** (2026-09-09 → 2026-09-10)

**Authorization:** owner phrase **"AUTHORIZE PFA-18C CREATEKEY"** (2026-09-09), scoped to `docs/release/PHASE2_PFA18C_C2_CREATEKEY_EXECUTION_PACKAGE.md` at `6455dc28366e5c0c02e164608ca5c60a599a011a` with the owner-confirmed parameters (us-east-1 · ECC_NIST_P256 · SIGN_VERIFY · AWS_KMS · single-region · lockout check on · tags `snatchit:purpose=ticket-signing`, `snatchit:program=pfa18c`, `snatchit:db_key_id=00000000-0000-0000-0000-0000000000b0`).
**Coordinator:** Claude B (label per owner instruction 2026-09-10; entries dated 2026-09-09 in the execution record carry the historical label "Claude A" — preserved, not rewritten). **C18 honoured:** every AWS mutation except C2-8 was run by the owner under the ceremony role; C2-8 (`PutRolePolicy`) was run by the coordinator with the owner's `jose-admin` login session on the owner's explicit instruction; Device 2 (verifier) performed the independent verification; the coordinator corroborated read-only.
**Not done (unchanged, still unauthorized):** C3 DB insert · C5 · C6 · secrets · edges · flags · M5/T3 · Model A · any access key · any alias/grant/deletion.

Evidence classes: **OWNER-RETURNED** (primary + Device 2), **CLAUDE-OBSERVED** (coordinator reads; CloudTrail; read-only MCP).

---

## 1. Result

| Item | Value |
|---|---|
| Key ARN (D4) | `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e` |
| Key ID | `45907419-8894-4582-ba79-71e9c29c549e` · created 2026-09-09T05:44:33.137Z |
| Final key state | `Enabled` · `ECC_NIST_P256` · `SIGN_VERIFY` · `AWS_KMS` · `MultiRegion false` · `KeyManager CUSTOMER` · `SigningAlgorithms [ECDSA_SHA_256]` · description `Snatch It ticket-signing trust root (PFA-18C)` · exactly one customer key · **no alias** · **no grant** · tags exactly the three |
| Key policy | **v2 final** (`kms_key_policy_v2_final.json` `430677d0…`) — normalized diff empty on the primary (owner), the coordinator, and Device 2; v1 (`e0560a96…`) was live only between 05:44:33Z and 06:35:16Z on 2026-09-09 |
| Runtime binding | `SnatchIt-CredentialSign-Runtime` inline `pfa18c-runtime-sign` = `m3_runtime_role_policy.json` (`bb3a2c4f…`) with D4 filled (filled-file SHA-256 `5706ebfa…`); attached `[]`; trust unchanged (runtime user + `sts:ExternalId`, value never read) |
| Public key (D5) | SHA-256(DER SPKI) = **`562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415`**; DER 91 bytes, P-256, one PEM block, 0 private material; identical on Device 2, primary, coordinator |
| §5.3 binding proof | **PASS** — Device-2 nonce (kept private), **one** successful KMS `Sign` by the ceremony role (RAW, ECDSA_SHA_256), signature 70 bytes SHA-256 `83c3938e…`; `Verified OK` on primary and Device 2 against their own exports; altered-message and wrong-key controls FAIL. **Not a production credential (R5); T3 not reached.** |
| P3′ | **PASS** — -a ceremony `CreateAlias` denied ×2 (`e44887e2…`, `bf23dd9b…`); -b ceremony `Verify` denied (06:33:12Z); -c verifier `Sign`/`Verify`/`CreateAlias`/`TagResource` denied (06:34:09–10Z); -d ceremony post-v2 `Sign` denied (`e7a4ac69…`, 2026-09-10T17:11:30Z, error names D4: "no resource-based policy allows the kms:Sign action"); -e simulator: lifecycle deny set explicitDeny for ceremony and verifier; runtime `Sign` allowed only on D4 with ECDSA_SHA_256+RAW |
| **C2** | **COMPLETE (2026-09-10T17:20Z evidence; D2C-7 verdicts OWNER-RETURNED 2026-09-10)** |

## 2. KMS `Sign` events — the one success vs the two denied probes (CLAUDE-OBSERVED)

| UTC | Event ID | Principal | MFA | keyId / msgType / alg | Outcome | Meaning |
|---|---|---|---|---|---|---|
| 2026-09-09 06:20:13 | `ca5a2602-a9a6-4dc9-967d-37616efd9c37` | `assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony` | true | D4 / RAW / ECDSA_SHA_256 | **Success** | the single §5.3 challenge signature |
| 2026-09-09 06:34:09 | `76bff95c-760b-44a4-b82a-e2f493a84ea5` | `user/snatchit-kms-verifier` | true | absent (KMS omits on deny) | AccessDenied | D2C-6 probe |
| 2026-09-10 17:11:30 | `e7a4ac69-565c-4bb5-8878-bb1908f83478` | `assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony` | true | absent; errorMessage names D4 | AccessDenied | C2-9 post-v2 probe |

No other `Sign` event exists since 2026-09-08. (CloudTrail classifies KMS `Sign` as `readOnly: true` — AWS's classification, noted.)

## 3. Step ledger

| Step | Who | Evidence | Status |
|---|---|---|---|
| Preflight P1–P9 | coordinator / owner / Device 2 | 05:31Z reads; artifacts unchanged; 0 keys | PASS |
| C2-1 CreateKey | owner (ceremony, TOTP) | `13b0dd38-b378-4820-bcbf-8e4fdc3cfc7c` 05:44:33Z, MFA, request = spec/tags/description/bypass false; `AssumeRole` `2f7cc9d0…` 05:44:21Z serial `…:mfa/jose-admin-totp` | PASS |
| C2-2 read-backs | coordinator | describe/tags/v1 diff empty/public key/one key/no alias | PASS |
| C2-3 P3′-a | owner | `CreateAlias` AccessDenied `e44887e2…` 05:56:52Z (and a second attempt `bf23dd9b…` 06:01:54Z) | PASS |
| C2-4 / D2C-4 | Device 2 + primary | DER 91, private 0, D5 match (Device 2 first) | PASS |
| C2-5 proof | Device 2 + owner | §2 row 1; verify outcomes OWNER-RETURNED | PASS |
| C2-6 / D2C-6 | owner + Device 2 | `Verify` denied 06:33:12Z (ceremony) & 06:34:09Z (verifier); verifier `Sign`/`CreateAlias`/`TagResource` denied | PASS |
| C2-7 v2 | owner (ceremony) | `PutKeyPolicy` `6b3d8526-62fe-4955-a2e6-55f5c94d3d6b` 06:35:16Z, bypass false, no F1 fallback; diffs empty ×3 | PASS |
| C2-8 runtime binding | coordinator (jose-admin, owner-instructed) | `PutRolePolicy` `944261d5-a411-419f-95cc-484de1ebb11a` 06:40:34Z; diff empty; simulator scoped | PASS |
| C2-9 P3′-d | owner (ceremony re-assumed `45469ee6…` 2026-09-10T17:07:37Z) | §2 row 3 — confirmed from the trail, not inferred | PASS |
| C2-10 CloudTrail | coordinator | exactly 1 `CreateKey`, 1 `PutKeyPolicy`, 1 `PutRolePolicy`; 0 `ScheduleKeyDeletion`/`DisableKey`/`EnableKey`/`CreateGrant`/`DeleteAlias`/`UpdateAlias`/`UntagResource`/`CreateAccessKey`/`AttachRolePolicy`/`DeleteRolePolicy`/`UpdateAssumeRolePolicy`/`DeleteRole`; root 0; only ceremony `AssumeRole`s carry the TOTP serial; other `AssumeRole`s = AWS `resource-explorer-2` service role (benign) | PASS |
| C2-11 precheck | coordinator | D4 passes guard rule 4; pub.pem passes rules 5/6; D5 = §6.1 recomputation; production dark (signing_key 0, ledger 135, tip 120, guard `O`, flags false) | PASS |
| D2C-7 verdicts | Device 2 (OWNER-RETURNED 2026-09-10) | artifacts `kms_key_policy_v2_final.json` OK, `m3_runtime_role_policy.json` OK; **`V2-DIFF-EMPTY`**; **`RUNTIME-DIFF-EMPTY`**; trust = runtime user / `sts:AssumeRole` / `sts:ExternalId` present; key `Enabled ECC_NIST_P256 MultiRegion false`; exactly one key; access keys 0/0/0. Trail: verifier `ConsoleLogin` 2026-09-10T17:10:27Z `MFAUsed: Yes` (Device-2 passkey); read calls 17:12–17:13Z all `readOnly true`, `mfaAuthenticated true` | PASS |
| D2C-8 | Device 2 (OWNER-RETURNED) | counts match §2 and C2-10 | PASS |
| D2C-9 | coordinator | this record | PASS |

## 4. Variances and dated corrections (evidence preserved; nothing rewritten)

- **V-1 (D2C-3 policy v1 not read by Device 2).** CloudTrail shows the verifier's D2C-3 calls at 05:58Z (`DescribeKey`, `ListKeys`, `ListResourceTags`, `ListAliases`, `GetPublicKey`) but **no `GetKeyPolicy`**; Device 2 therefore did not diff the interim v1 policy. v1 was independently verified by the coordinator (diff empty, 05:53Z) and superseded 41 minutes later; Device 2 independently verified the **final** v2 (D2C-7). Classified **non-blocking** for M2 (the persisting state is Device-2-verified); recorded for the owner, who may reopen.
- **V-2 (ARN transcription).** Two owner messages wrote the ARN without `:key/`; the AWS-verified D4 (with `:key/`) was used for every read, comparison and the runtime binding.
- **C-1 (coordinator label).** 2026-09-10: the owner directs the label **Claude B** for the C2 execution/C3 preparation; historical entries dated 2026-09-09 keep "Claude A".
- **C-2 (tooling).** The first C2-2 read pass forced `--output json` inside a helper and double-encoded text outputs (empty-input hash `e3b0c442…` discarded); repeated with explicit `--output text`. Same error class as C1.
- **C-3 (Sign classification).** Wherever a summary said "three Sign events", read: **one successful challenge Sign + two denied Sign probes** (§2).

## 5. Mutation ledger (C2, total)

AWS — owner (ceremony role, MFA): `CreateKey` ×1, `Sign` ×1 (proof), `PutKeyPolicy` ×1 (v2). Coordinator (`jose-admin`, owner-instructed): `PutRolePolicy` ×1. Denied probes (no effect): `CreateAlias` ×3, `Verify` ×2, `Sign` ×2, `TagResource` ×1. **KMS: one key, Enabled, policy v2, 3 tags, no alias/grant; no deletion scheduled.** IAM: one inline policy on the runtime role; **no access key**; no trust change. **Production DB: none. Secrets: none. Edges: none. Flags: unchanged (false).** Repository: package, record entries, this file.

## 6. Next

**C3** — trust-root DB commit — package `docs/release/PHASE2_PFA18C_C3_TRUST_ROOT_DB_COMMIT_EXECUTION_PACKAGE.md` (corrected 2026-09-10; for owner review) — requires **"AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT"**. Then C5, C6 (own phrases); C7 pending §5d; Model A before T3.
