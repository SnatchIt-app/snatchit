# PHASE-2 PRODUCTION STATE — RECONCILIATION OF RELEASE RECORDS (2026-09-12, read-only)

**Prepared by:** Claude B (PFA-18C coordinator) on the owner's instruction after C6 COMPLETE (`93cf3fe1bef65fc4dd8af80ec19e0884b952b10b`). **Production mutations: NONE.** Evidence: Supabase read-only SQL and function listing 2026-09-12T03:41–03:53Z; AWS reads 03:45Z (`jose-admin`, read-only); PFA-18C execution records C2–C6.
**This document authorizes nothing.** It supersedes the "current state" statements in the earlier release records listed in §4, which remain valid as history.

## 1. Production state (project `hqycwntpfoztoinemqns`)

| Layer | State | Source |
|---|---|---|
| Migration ledger | **135 rows** = 114 numeric (000–120, with the historical gaps 023/043/055/056/059/060/066) + 21 timestamped legacy rows; **numeric tip 120**. Applied in production order: 076–092 (2026-09-02), 093–109 (2026-09-04), 115–120 ops console (2026-09-08), 110–114 PFA-18C C4 (2026-09-09). **121 not applied** (`venue.get_manifest_signing_context` md5 `b14d938eab69c94768578daf8b6d1c4f` = the 114 body) | SQL 03:53Z; C4 record; ops-console deployment record |
| Trust root (DB) | `kernel.signing_key`: **one row** `00000000-0000-0000-0000-0000000000b0`, scope global, status active, algorithm **ES256**, venue null; insert guard 110 (rules 1–11); two-person recovery 111 | SQL; C3 record |
| Trust root (KMS) | D4 `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e`, `ECC_NIST_P256`, Enabled, single-region, policy v2; fingerprint D5 `562b5e87…f64415`; `Sign` total 3 (1 ceremony proof, 2 denied), 0 lifecycle events | C2 record; CloudTrail 03:45Z |
| Monitor | `signing.expected_key_fingerprint` v2 = D5 (dual control, founder B approved), `signing.expected_max_not_after` null, `signing.monitor_enabled` **true**; cron `monitor-signing-key-invariants` `23 5 * * *` active, last run 2026-09-11T05:23Z succeeded; checker `ok` / `match`; `signing_key.invariant_alert` rows 0 | C5/C6 records; SQL |
| Edge functions | **14** ACTIVE: 11 legacy (unchanged hashes) + `credential-sign` (JWT), `door-manifest` (JWT), `door-session` (no JWT) at v1 from `562fda9`; **0 requests, 0 signatures**; 24 secrets by name (six E2 signer names) | C6 record |
| Runtime principal | user `snatchit-credential-sign-runtime`: **1** Active key (2026-09-11T02:13:02Z); role `SnatchIt-CredentialSign-Runtime` (ExternalId trust; Allow `kms:Sign` on D4 only); **0** runtime `AssumeRole` ever | C6 record |
| Feature flags | `feature.native_issuance_enabled` **false** · `feature.native_scanning_enabled` **false** · `feature.native_resale_enabled` false | SQL |
| Native data | tickets, door sessions, door manifests, scan devices, door PINs, staff roles, organizations, catalog venues/events/sessions: **all 0** | SQL |
| Config | 54 distinct `catalog.platform_config` keys; only PFA-18C changes since 093–109: the three `signing.*` values above | SQL; C5 record |
| Cron | 24 jobs, 24 active | SQL |
| API exposure | PostgREST schemas `public, graphql_public, kernel, ops` as recorded by the ops-console deployment (2026-09-08); not re-read here (platform config, not a role setting) | ops-console record |
| Runtime signing activity | **none** — no `credential-sign`/`door-manifest` request, no runtime `AssumeRole`, no new KMS `Sign` | C6 record (T+0, Mac 2, T+24) |

## 2. Standing production restrictions (verbatim from the PFA-18C program; preserved until separately authorized)
"No test invocations, production signing, issuance/scanning activation, migration 121, or Model A changes are authorized." Additionally: no production venue, staff role, manifest, device or PIN creation (zero-data precondition is a live inactivity control for the dark endpoints); no additional runtime key; no policy/trust/KMS lifecycle change; no secret change; `AUTODEPLOY-VERIFIED-OFF` attestation and empty `git_branch` on every migration-bearing PR.

## 3. What this handoff does **not** authorize
Model A · M5 / T3 (first production credential) · any feature activation (issuance, scanning, resale, wallet) · further edge or migration deployment. **Migration 121** remains explicitly deferred optional hardening inside Claude A's integration sequence (after the Build 16 handset matrix; combined chain 142; PR #58 draft rev 2), to be applied only under `AUTHORIZE PFA-18C MIGRATION 121`.

## 4. Reconciliation of earlier release records (history preserved; each carries a dated pointer to this document)

| Record | Statement now superseded | Current fact |
|---|---|---|
| `PHASE2_PRODUCTION_RUNBOOK.md` (2026-09-02) | "record ledger count 107" close-out; 076–092 train | ledger 135, tip 120; 093–120 applied; trust root and dark signer live |
| `PHASE2_RELEASE_READINESS_REPORT.md` (2026-09-02) | ledger 107 post-apply; `credential-sign` "NO" deployed; KMS "–" | ledger 135; three signer/door functions deployed dark; KMS D4 live; §13 rail matrix: issuance/scanning still NO (flags false) |
| `PHASE2_DEPLOYMENT_RECORD_20260902.md` | ledger 107; 24-h close "NOT DUE" | closed by the 2026-09-04 close-out; ledger 135 |
| `PHASE2_OBSERVATION_CLOSEOUT_20260904.md` | ledger 107; `kernel.signing_key.algorithm` absent (103 unapplied); PostgREST `public, graphql_public, kernel` | 103 applied (column present, ES256 pinned); ledger 135; `ops` also exposed since 2026-09-08 |
| `PHASE2_093_109_PRODUCTION_MIGRATION_EXECUTION.md` (2026-09-04) | ledger 124 / tip 109; "KMS ceremony NOT executed"; "edges NOT deployed"; signing monitor false; cron 22 active | ledger 135 / tip 120; KMS trust root established (C2/C3); `credential-sign`/`door-manifest`/`door-session` deployed dark (C6); monitor true (C5); cron 24 active. `primary-checkout` still NOT deployed |
| `PHASE2_ROLLBACK_DECISION_TREE.md` | "rollback is legal only while CLEAN-WHILE-EMPTY holds" (076–092 guards) | Native-data emptiness still holds, but live Phase-2 facts now exist outside the 076–092 guard set: the trust-root row, the C5 config versions and approval request, and 093–120. Any DB rollback is forward-only by policy and needs its own authorization; PFA-18C rollback surfaces are listed in `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md` §5 |

The PFA-18C records (`PHASE2_PFA18C_*`) are current as of C6 COMPLETE and need no reconciliation. `PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md` is the owner's uncommitted working file and was not touched.

## 5. Dated corrections made during this reconciliation
- C6 execution record and execution-record session 28: "ledger 135 (tip `20260902003623`)" corrected to "ledger 135, numeric tip **120**" — `max(version)` had returned the lexical maximum of the 21 timestamped legacy rows, not the numeric substrate tip.
