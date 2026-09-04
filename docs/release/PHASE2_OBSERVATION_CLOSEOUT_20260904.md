# PHASE-2 DARK SUBSTRATE (076–092) — 24-HOUR OBSERVATION CLOSE-OUT (READ-ONLY)

Prepared: 2026-09-04 · Author: Claude A (this preflight session) · Production mutations: NONE (read-only)

> **WHY THIS DOCUMENT EXISTS.** The deployment record (docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md)
> captured **checkpoint 1** (~0.9 h of 24) and ended "24-hour close: NOT DUE (target ~2026-09-03T20:45Z).
> Next checkpoint: the close-out." **No close-out artifact was ever written.** This document supplies the
> required read-only close-out evidence. It does NOT infer PASS from elapsed time — it records ACTUAL
> production telemetry gathered read-only over the window (cron run history, ledger, flags, native-data
> counts, drift). Owner acceptance of this close-out is the governance step that closes the gate.

## Window
- SUBSTRATE DEPLOYED: 2026-09-02 20:41:58Z → 20:43:31Z (migrations 076–092; ledger 90 → 107).
- OBSERVATION TARGET CLOSE: ~2026-09-03T20:45Z (24 h).
- EVIDENCE GATHERED: 2026-09-04 (>24 h elapsed; telemetry below spans the full window and beyond).

## Read-only evidence (Supabase MCP, project hqycwntpfoztoinemqns)
| Criterion | Observed | Expected | Result |
|---|---|---|---|
| Migration ledger rows | 107 | 107 | PASS |
| Migration tip | 20260902003623 (through 092) | through 092 | PASS |
| 093–109 applied | 0 | 0 | PASS |
| Signing keys | 0 | 0 | PASS |
| kernel.signing_key.algorithm column | absent | absent (103 unapplied) | PASS |
| Native data (tickets / door_pin / door_session / scan) | 0 / 0 / 0 / 0 | 0 | PASS |
| Native money rows (payout/refund/market_sale native) | 0 (per checkpoint 1 + 093–109 unapplied) | 0 | PASS |
| Phase-2 native edges deployed | 0 (11 legacy edges only) | 0 | PASS |
| feature.native_issuance_enabled | false | false (DARK) | PASS |
| feature.native_scanning_enabled | false | false (DARK) | PASS |
| Owner-unset keys (signing.monitor_enabled, signing.expected_key_fingerprint, fee.buyer_service_bps, deletion.post_event_hold_hours, payout.executor_enabled) | NULL | NULL | PASS |
| cron.job | 19 total / 19 active | 19 | PASS |
| cron.job_run_details (last 48 h) | 0 failed / 15,956 succeeded | 0 failures | PASS |
| Migration drift (093+ objects present in prod) | none (force_close_key_manifests / force_close_session_manifests / record_scan_door / algorithm all absent) | none | PASS |
| Legacy row counts vs pre-apply snapshot | unchanged (checkpoint 1) | unchanged | PASS |

## Notes carried forward (not observation failures)
- **PostgREST exposure** = `public, graphql_public, kernel` (kernel reachable, anon walled 42501, venue/market not exposed) — the dark-apply cutover state, unchanged.
- **Legacy secret exposure** flagged during deploy (management-API GET returned the project JWT secret to a session transcript): tracked as an OWNER-GATED credential-rotation item, sequenced AFTER a publishable-key mobile build; NOT part of this substrate's health and NOT a blocker to a dark migration. Recorded here so it is not lost.
- **8 Dependabot advisories** on the default branch — pre-existing, dependency-level, unrelated to the substrate.

## Determination
- **TECHNICAL OBSERVATION CRITERIA: PASS** — over the full window and beyond, the 076–092 substrate ran
  with zero cron failures, zero migration drift, zero native/native-money data, feature flags DARK, and
  owner-gated keys NULL. No error-severity anomaly observed.
- **GOVERNANCE STATUS: OWNER ACCEPTANCE REQUIRED.** This read-only close-out records the evidence; the
  owner's acceptance of it is the step that formally closes the 24-hour observation gate and is a
  precondition for authorizing the 093→109 dark migration.

CLOSE-OUT RESULT: **TECHNICAL PASS — PENDING OWNER ACCEPTANCE.**
