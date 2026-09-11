# PFA-18C — C5 MONITOR ARMING EXECUTION RECORD — **COMPLETE (coordinator-verified 2026-09-11T01:49Z; Mac 2 final read-back recorded below when returned)**

**Authorization:** owner phrase **"AUTHORIZE PFA-18C MONITOR ARMING"** (2026-09-10), scoped to package §1 (`PHASE2_PFA18C_C5_MONITOR_ARMING_EXECUTION_PACKAGE.md`): `signing.expected_key_fingerprint` → D5 under dual control, `signing.expected_max_not_after` unchanged (null, D6), `signing.monitor_enabled` → true, first `kernel.check_signing_key_invariants()` must be `ok`/`match`. Owner confirmations: Option A for Mac 2; local rehearsal first (`PHASE2_PFA18C_C5_LOCAL_REHEARSAL_RECORD.md`, PASS). **Coordinator:** Claude B. **C18:** founder A ran C5-1 and C5-3 on Mac 1 (authenticated psql session with their own platform_admin claims); founder B personally ran C5-2 on Mac 2 in their own MFA/aal2 admin-portal session (token never left the browser); the coordinator read back only.
**Not done:** no flag change (issuance/scanning false), no secret, no edge, no AWS change, no M5/T3.

## 1. Result

| Item | Value |
|---|---|
| `signing.expected_key_fingerprint` | **v2 = `562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415`** (= D5 = SHA-256 of the `…b0` row's DER SPKI), effective 2026-09-11T01:39:50Z, visibility `restricted` copied forward; v1 null retained (append-only) |
| `signing.expected_max_not_after` | v1 null (unchanged, D6) |
| `signing.monitor_enabled` | **v2 = true**, effective 2026-09-11T01:47:34Z (direct single-admin path) |
| Dual control | request `05e0ff5d-1044-40c9-b32d-c5db1c171976`: proposed by founder A `2b117757…` (2026-09-10T19:59:17Z, command key `pfa18c-c5-pin-1`), **approved by founder B `3b7b50af…`** (2026-09-11T01:39:50Z, `applied_version 2`), distinct approver, aal2 session; pending requests after: 0 |
| **C5-4 first check** (CLAUDE-OBSERVED 01:49:35Z, `postgres`) | `{"status":"ok","alerts":[],"fingerprint":"match","total_keys":1,"scoped_keys":0,"active_global":1,"rotating_keys":0,"revoked_keys":0,"max_not_after_set":false,"deduped":false}` |
| Alert rows | `signing_key.invariant_alert` **0** |
| Audit trail | `config.money_key_proposed` (A, 2026-09-10T19:59:17Z) → `config.money_key_approved` (B, 2026-09-11T01:39:50Z) → `config.change` (A, 2026-09-11T01:47:34Z, reason `pfa18c_c5_arm`) |
| Cron | `monitor-signing-key-invariants` active, `23 5 * * *` → first scheduled run 2026-09-11T05:23Z |
| Trust root / flags | `kernel.signing_key` `1|1`; issuance false; scanning false |
| AWS | unchanged (see §2) |

## 2. Step ledger

| Step | Who | Evidence | Status |
|---|---|---|---|
| Preconditions | coordinator | 2026-09-10T19:55:38Z all PASS (G1–G9) | PASS |
| C5-1 propose | founder A (Mac 1) | `{"status":"parked","version":1,"request_id":"05e0ff5d…"}`, COMMIT; read-back 20:00:51Z: pending, proposed = D5, audit proposed | PASS |
| Pause | owner | 2026-09-10 20:46Z — founder B unavailable; state recorded (`PHASE2_PFA18C_C5_PAUSE_HANDOFF.md`) | — |
| Resume pre-read | coordinator | 2026-09-11T01:27:15Z: pending, not expired (66.5 h left), proposed = D5, founder B admin + 1 MFA factor, signed in 01:24:46Z | PASS |
| C5-2 approve | **founder B (Mac 2, in person)** | `200 {"status":"approved","request_id":"05e0ff5d…","applied_version":2}`; read-back 01:41:10Z: approved, distinct approver, v2 = D5, audit approved | PASS |
| C5-3 arm | founder A (Mac 1) | `{"key":"signing.monitor_enabled","status":"ok","version":2,"request_id":null}`, COMMIT | PASS |
| C5-4 first check | coordinator | §1 | PASS |
| Mac 2 pre-arm read-back | founder B / owner | *(not returned separately; the C5-2 result and the coordinator read-back cover v2 = D5 and the distinct approver)* | recorded as coordinator-verified |
| Mac 2 final read-back | founder B / owner | **pending — issued 2026-09-11T01:5xZ** (monitor v2 true; audit order; alert rows 0) | pending |

## 3. Facts recorded
- The setter's dual-control path (102) worked in production exactly as rehearsed: parked → second distinct platform_admin on aal2 → `applied_version 2`; the approver applied the version itself.
- `catalog.set_platform_config` first production use: three audit rows, no `config.change` before C5-3.
- Egress not exercised (no alert) — `notify-report` remains untested by the monitor; a real alert would push to `admin_users` (2), `ADMIN_EMAIL` and Sentry.
- Coordinator read-backs used the read-only MCP as `postgres`; `check_signing_key_invariants()` writes nothing when `ok`.

## 4. Rollback / disarm
Kill switch `signing.monitor_enabled := false` (single admin, own phrase `AUTHORIZE PFA-18C MONITOR DISARM`). Un-pinning/re-pinning the fingerprint is dual-controlled by design.

## 5. Next (each separately authorized)
C6 dark deploy (`AUTHORIZE PFA-18C DARK DEPLOY`; prerequisites in `PHASE2_PFA18C_C6_DARK_DEPLOY_REVIEW_PACKAGE.md`; migration 121 recommended first, not blocking); daily monitor observation from 05:23Z; Model A before T3; M5 ruling pending (§5d).
