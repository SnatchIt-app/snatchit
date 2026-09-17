# PFA-18C — C3 TRUST-ROOT DB COMMIT EXECUTION RECORD — **COMPLETE** (2026-09-10)

**Authorization:** owner phrase **"AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT"** (2026-09-10), scoped to package rev 3 (`PHASE2_PFA18C_C3_TRUST_ROOT_DB_COMMIT_EXECUTION_PACKAGE.md`): one guarded INSERT via the pinned §6.1 artifact (commit `1f3fc19d295e101fb680393e4bd99db8b2f2cc5f`, block SHA-256 `380f434d07d85c1f5a7a92ad376da3843becc9019f01c4f20580d67a66eba7f6`, 118 lines), `key_id …b0`, ES256, the verified KMS ARN and D5, plus the specified rolled-back refusal probes. Owner decisions recorded: Option A for Mac 2 (Dashboard + Supabase MFA; privileged session, read-only by procedure), V-1 acknowledged, live `revoke_signing_key` probe omitted (definition review instead).
**Coordinator:** Claude B. **C18 honoured:** the owner ran the bootstrap and the probes personally on Mac 1; Mac 2 verified independently; the coordinator read back only.
**Prerequisite event (same day):** production database password reset under "AUTHORIZE PFA-18C DB PASSWORD RESET" — inventory `PHASE2_PFA18C_DB_PASSWORD_RESET_IMPACT_INVENTORY.md`; V1–V5, V8 validated; the only updated consumer was the owner's shell `PROD_DB_URL`.

Evidence classes: **OWNER-RETURNED**, **CLAUDE-OBSERVED** (read-only MCP as `postgres`, AWS reads).

---

## 1. Result — the trust root is registered

| Item | Value (CLAUDE-OBSERVED 19:09–19:28Z unless noted) |
|---|---|
| Rows | **exactly one** `kernel.signing_key` row; `1\|1\|0\|0` (total / active global / per_event / per_venue) |
| key_id | `00000000-0000-0000-0000-0000000000b0` (ruling B; guard rule 11) |
| scope / status / algorithm | `global` / `active` / **`ES256`** (explicit; the column default `EdDSA` was not inherited) |
| kms_handle_ref | `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e` (D4, verified) |
| public_key fingerprint (D5) | `562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415` — recomputed from the stored PEM by the §7.1 query and by the monitor's own formula; equals Device 2's, the primary's and the coordinator's independent exports |
| window | `not_before = created_at = 2026-09-10T19:07:50.431202Z`; `not_after null` (D6) |
| Resolver (§7.2 global arm) | `…b0 \| global` |
| `venue.get_manifest_signing_context()` | `status ok`, `key_id …b0`, `algorithm ES256`, `key_status active`, `not_after null`, `kms_handle_ref` = D4 |
| Flags | `feature.native_issuance_enabled` **false**, `feature.native_scanning_enabled` **false**, `signing.monitor_enabled` **false**, `signing.expected_key_fingerprint` **null** |
| References | tickets / wallet_pass / door_manifest_entry / door_manifest_delta = **0/0/0/0** (rollback §10 still available) |
| Machine RPC grants | `get_signing_keys_door`, `get_door_manifest_door`, `get_manifest_signing_context` → **service_role only** |
| Ledger / recovery rows | 135 / 0 |
| AWS | **no event from C3**: 0 CreateKey/PutKeyPolicy/PutRolePolicy/ScheduleKeyDeletion/DisableKey/CreateGrant/CreateAlias/Sign since 19:00Z; `Sign` total since 2026-09-08 unchanged at **3** (1 proof success + 2 denied probes); key `Enabled ECC_NIST_P256` |
| **C3** | **COMPLETE** |

## 2. Execution trail

| Step | Who | Evidence | Status |
|---|---|---|---|
| Steps 0–2 (connection, artifact, inputs) | owner (Mac 1) | `project_match=True mode=session PASS`; `0\|135\|…=O\|0\|false`; `ARTIFACT-PASS` (conditional on sha `380f434d…` and 118 lines); `PEM-DER-MATCH`; `der=91 private=0 blocks=1 D5=562b5e87… pemsha=cf5da142…`; `INPUTS-PASS`; `handle=`D4; `fingerprint=`D5 | PASS |
| Final gate re-read | coordinator | 19:06:21–25Z: G1 0 · G2 triggers O/O/O · G3 false/null · G4 0/0/0/0 · G5 135/120 + `no_active_global_key` · G6 key v2 · G7 bound | PASS |
| **Step 3 bootstrap** | **owner (Mac 1)** | `psql -X -v ON_ERROR_STOP=1 … -f signing_key_bootstrap.sql` on the session pooler; identity line `app=Supavisor`, **backend_pid 463167**, backend_start 19:07:50.19Z; row `created_at` 19:07:50.43Z; NOTICE/COMMIT/exit lines stated by the owner as passed | **COMMITTED** |
| Outcome determination | coordinator | 19:09:14Z, separate read-only session: `n=1, exact_row=true`; backend 463167 `idle`, `holds_xid false`, no `xact_start` ⇒ committed, nothing in flight (rev-3 §7 procedure, applied without assuming the paste) | PASS |
| §8A read-backs | coordinator | A1–A7 (§1), 7.3-def true, ledger 135, recovery 0 | PASS |
| Mac 2 A1–A7 | owner / Device 2 (Dashboard, Supabase MFA) | all passed (OWNER-RETURNED) | PASS |
| §8B P-7.5 immutability | owner (Mac 1, `postgres`, `begin…rollback`) | `append_only` error; fingerprint unchanged; `PROBE-7.5-PASS` (OWNER-RETURNED); coordinator re-read 19:28Z: `1\|1`, fingerprint `562b5e87…` | refused, rolled back |
| §8B P-7.3 five parked lifecycle calls | owner (Mac 1, `begin…rollback` each) | five `dual_control_unavailable`; `1\|1`; `PROBE-7.3-PASS` (OWNER-RETURNED) | refused, rolled back |
| `revoke_signing_key` | — | **not called** (owner-acknowledged deviation); definition review: platform_admin + aal2 enforced before the first write | definition-review evidence |
| CloudTrail | coordinator | no AWS event from C3 (§1) | PASS |

## 3. Recorded limitations and corrections (dated 2026-09-10)
- **L-1 pooler application_name:** Supavisor does not forward the client `application_name` (`PGAPPNAME`) to the server backend; the identity line showed `app=Supavisor`. Correlation used the captured server pid (463167) + timestamps. Package §3/§7.2 amended by this note.
- **V-1 (C2, historical):** Device 2 verified the final v2 key policy, not the interim v1 — acknowledged by the owner.
- **C-5 (C4 record):** the C4 apply authenticated via the CLI login role, not a keychain DB password.
- **Ceremony doc §7.3 (stale since 106):** `revoke_signing_key` is un-parked; the loop's "NOT PARKED — STOP" is a false alarm for it; the package's definition review replaces the live call.
- The owner's step-3 paste did not include the NOTICE/COMMIT/exit lines verbatim; the outcome was determined read-only (§2) and the owner stated the output and probes passed.

## 4. Mutation ledger (C3)
Production DB: **one row inserted** into `kernel.signing_key` (`…b0`) by the owner via the pinned artifact (one transaction). Write attempts, refused and rolled back: 1 UPDATE (immutability probe), 5 parked lifecycle calls. Config/flags: **unchanged** (monitor not armed; issuance/scanning false). AWS: **none**. Secrets / edges: **none / not deployed**. Repository: this record, package rev 3, execution-record sessions 20–21, packet rows.

## 5. Next (each separately authorized)
**C5 monitor arming** — package `PHASE2_PFA18C_C5_MONITOR_ARMING_EXECUTION_PACKAGE.md` (for review) — requires **"AUTHORIZE PFA-18C MONITOR ARMING"** and, because the fingerprint pin is dual-controlled since migration 102, a second platform_admin's approval. Then C6 (dark deploy), C7/M5 pending §5d, Model A before T3.
