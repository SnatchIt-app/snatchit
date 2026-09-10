# PFA-18C — C3 TRUST-ROOT DB COMMIT EXECUTION PACKAGE — **FOR OWNER REVIEW** (NOT AUTHORIZED · NOTHING EXECUTED)

**Date:** 2026-09-10 (coordinator session 18, Claude A) · **Prepared against:** production after C2 (key `45907419-8894-4582-ba79-71e9c29c549e` created, policy v2, runtime bound) and C4 (migrations 110–114 live; guard 110 enforcing).
**Nothing here was executed.** No `kernel.signing_key` row was inserted, no edge deployed, no secret written, no flag changed. **C3 requires the separate exact owner phrase `AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT`** (§1). This document is not that authorization.
Per **C18**, the owner runs the `psql` bootstrap personally; the coordinator performs only read-only read-backs (read-only MCP `execute_sql`); Device 2 does independent read-backs. **C3 does not approach T3** — it writes the trust-root row; it signs no credential and enables no issuance. Model A is required before T3, not before C3.

Evidence classes: **CLAUDE-OBSERVED**, **OWNER-RETURNED**, **OFFICIAL-DOC**.

---

## 1. Authorization scope

The owner authorizes C3 by writing exactly **`AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT`**, scoped to:
- the ceremony artifact `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` **§6.1** (`signing_key_bootstrap.sql`) at commit `66f5de60f5a3f5ed3e12665822b8719f65ca31c7`, run **verbatim** (extraction integrity anchor: the fenced `sql` block SHA-256 `380f434d07d85c1f5a7a92ad376da3843becc9019f01c4f20580d67a66eba7f6`);
- exactly these values: `KMS_HANDLE_REF` = **D4** `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e`; `PUBLIC_KEY_PEM` = Device 2's own `pub.pem` (SPKI PEM whose SHA-256(DER) = D5); `EXPECTED_FINGERPRINT` = **D5** `562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415`; `ALGORITHM` = **`ES256`** (explicit — never the column default `EdDSA`);
- one `psql … -f signing_key_bootstrap.sql` invocation producing four NOTICEs + `COMMIT`, then the §7 read-backs.

It does **not** authorize: C5 monitor arming, C6 secrets/deploy, any edge, any flag flip, any second key/row, issuance/scanning, M5/T3, Model A, or re-running C2. Rollback (§7) needs its own phrase `AUTHORIZE PFA-18C C3 ROLLBACK`.

## 2. Preconditions (all must hold seconds before the INSERT)

| # | Check | Expected | Who |
|---|---|---|---|
| G1 | `select count(*) from kernel.signing_key` | **0** | coordinator (read-only MCP) |
| G2 | guard `tg_signing_key_insert_guard` | `tgenabled='O'` (110 live) | coordinator |
| G3 | flags | `feature.native_issuance_enabled`/`native_scanning_enabled`/`signing.monitor_enabled` **false** | coordinator |
| G4 | tickets / wallet_pass / door_manifest_entry | **0 / 0 / 0** (rollback stays available) | coordinator |
| G5 | `venue.get_manifest_signing_context()` | `unavailable / no_active_global_key` | coordinator |
| G6 | KMS key D4 | `Enabled`, `ECC_NIST_P256`, `SIGN_VERIFY`, `MultiRegion false`, key policy = v2, 3 tags | coordinator + Device 2 |
| G7 | runtime role | inline `pfa18c-runtime-sign` bound to D4 only; access keys 0/0/0 | coordinator |
| G8 | `PUBLIC_KEY_PEM` on Device 2 | 91-byte DER, P-256 prefix, 0 `PRIVATE KEY`, one SPKI block, SHA-256(DER) = D5 | Device 2 |
| G9 | ledger / tip | 135 / 120 (no drift) | coordinator |

## 3. The bootstrap satisfies migration 110's guard (rules 1–11) — the INSERT will pass, not be refused

| Rule | Requirement | The §6.1 row |
|---|---|---|
| 1 | `scope='global'` | `'global'` ✓ |
| 2 | `status='active'` | `'active'` ✓ |
| 3 | `algorithm='ES256'` (explicit; no override) | `-v ALGORITHM=ES256` ✓ |
| 4 | `kms_handle_ref` a full AWS KMS key ARN | D4 (regex-verified) ✓ |
| 5 | no `PRIVATE KEY` text | pub.pem is public-only ✓ |
| 6 | SPKI PEM → 91-byte uncompressed P-256 | verified (G8) ✓ |
| 7 | advisory xact lock | taken by the trigger |
| 8 | no duplicate `key_id` | table empty ✓ |
| 9 | no active/rotating global exists | 0 rows ✓ |
| 10 | no revoked global exists | 0 rows ✓ |
| 11 | first global `key_id` = `…b0` | artifact writes `…0000b0` ✓ |

The artifact's own PRE-FLIGHT 1/2/2b/3 + POST-CHECK are a superset of the guard; both must pass in the same transaction or nothing is written.

## 4. Invocation (§6.2 — OWNER runs; stage inputs as files so no secret enters shell history; **not** the Supabase SQL editor)

```bash
cd "$CEREMONY_DIR"                      # a local dir holding signing_key_bootstrap.sql + Device 2's pub.pem
printf '%s' 'arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e' > handle.txt
openssl dgst -sha256 -hex pub.der | awk '{print $2}' > fingerprint.txt   # must read 562b5e87…
cat fingerprint.txt
psql "$PROD_DB_URL" \
  -v PUBLIC_KEY_PEM="$(cat pub.pem)" \
  -v KMS_HANDLE_REF="$(cat handle.txt)" \
  -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)" \
  -v ALGORITHM="ES256" \
  -f signing_key_bootstrap.sql
```
`$PROD_DB_URL` = the production session/pooler connection (password from the OS keychain; never pasted). **Required output — four lines then `COMMIT`:**
```
NOTICE:  PRE-FLIGHT 2 PASSED — fingerprint 562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415
NOTICE:  PRE-FLIGHT 2b PASSED — algorithm ES256
NOTICE:  PRE-FLIGHT 3 PASSED — handle accepted (value not echoed)
NOTICE:  POST-CHECK PASSED — exactly one active global key, key_id …b0, algorithm ES256
COMMIT
```
Anything else means nothing was written (every abort path leaves `count(*)=0`).

## 5. Post-commit read-backs (§7 — coordinator via read-only MCP; Device 2 independently)

| # | Check | Expected |
|---|---|---|
| 7.1 | row read-back | exactly one line; `key_id …b0`; `scope=global`; `status=active`; `fingerprint=562b5e87…`; handle not printed |
| 7.2 | resolver (global arm) | returns `…b0` as the active global key |
| 7.3 | lifecycle still parked | the **five** parked funcs (`provision_signing_key`, `rotate_signing_key`, `provision_pass_type_cert`, `rotate_pass_type_cert`, `revoke_pass_type_cert`) raise `dual_control_unavailable`; **`revoke_signing_key` is UN-parked since 106** and is expected to refuse with `insufficient_privilege` (no platform_admin/aal2), never succeed — do not read a false "NOT PARKED" |
| 7.4 | no shadow key | `1\|1\|0\|0` |
| 7.5 | immutability guard | a rolled-back `update … public_key` errors `append_only …` |
| 7.6 | window gap | `not_after`/`not_before` excluded from the immutable set (monitor is the control) — record, do not fix |
| D3C | Device 2 | `venue.get_manifest_signing_context()` (as service_role, read-only) now `status:'ok'`, `key_id …b0`, `algorithm ES256`; `get_signing_keys_door` refuses anon/authenticated; `kernel.signing_key` count 1 |
| CT | CloudTrail | **no AWS event** (C3 is DB-only); KMS `Sign` count unchanged from C2 (1 proof); no lifecycle event |

## 6. Abort conditions (stop; nothing further; report)

Any NOTICE missing or altered; `count(*)` ≠ 1 after commit or ≠ 0 immediately before; fingerprint mismatch; the artifact raises any `CEREMONY ABORT`; the guard raises any `signing_key_insert_refused`; `scope`/`status`/`algorithm`/`key_id`/handle differ from the intended values; a second row appears; any flag observed `true`; the Supabase SQL editor was used; anything asks for a secret to be pasted.

## 7. Rollback (only before the first mint; own phrase `AUTHORIZE PFA-18C C3 ROLLBACK`)

`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` §10 `signing_key_bootstrap_ROLLBACK.sql` — deletes the `…b0` row **only while** no `kernel.tickets` / `wallet_pass` / `door_manifest_entry` / `door_manifest_delta` references it (FK `ON DELETE RESTRICT` + explicit guard). Currently all references are 0, so rollback is available immediately after C3 and until the first credential mint; after that use rotation/compromise response. The KMS key is left as-is (C3 rollback does not touch AWS).

## 8. What C3 does NOT do / next

C3 writes one row. It does not arm the monitor, write secrets, deploy edges, flip flags, sign a credential, or start issuance/scanning. **Next, each separately authorized:** **C5** monitor arming (`AUTHORIZE PFA-18C MONITOR ARMING` — set `signing.expected_key_fingerprint = 562b5e87…`, `signing.monitor_enabled = true`, run `kernel.check_signing_key_invariants()` once); **C6** O1 secrets + dark edge deploy (`AUTHORIZE PFA-18C DARK DEPLOY`; the runtime access key is created only at C6); **C7/M5** pending §5d clarification; **Model A** before T3.
