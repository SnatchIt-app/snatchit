# PFA-18C — FINAL COORDINATOR HANDOFF (2026-09-12) — TRUST ROOT LIVE · SIGNER DARK · REMAINING LAUNCH GATES

**Coordinator:** Claude B · **Owner:** founder A (`jose-admin`, Mac 1) · **Basis:** execution record sessions 1–28, C2/C3/C4/C5/C6 execution records, the ratified packet, the owner runbook, `PHASE2_PFA18C_REMAINING_PATH_AND_HANDOFF.md` (plan of record, 2026-09-10).
**Nothing in this document authorizes anything.** Every remaining step needs its own owner phrase; the coordinator executes a mutation only on explicit instruction in that turn (C18).

## 1. What exists in production now (all verified, read-only, 2026-09-12T03:41–03:46Z)

| Layer | State | Evidence |
|---|---|---|
| KMS trust root D4 | `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e`, `ECC_NIST_P256`, Enabled, single-region, policy v2; `Sign` total 3 (1 proof + 2 denied), 0 lifecycle events since creation | C2 record; T+24 CloudTrail |
| Principals | ceremony role (proof only), verifier user (0 keys, read-only), runtime user `snatchit-credential-sign-runtime` (**1** Active key, created 2026-09-11T02:13:02Z) → `SnatchIt-CredentialSign-Runtime` (ExternalId trust; inline `pfa18c-runtime-sign`: Allow `kms:Sign` on D4 only); 0 runtime `AssumeRole` ever | C1/C6 records |
| DB trust root | `kernel.signing_key` `00000000-0000-0000-0000-0000000000b0` global/active/ES256; guard 110 rules 1–11; migrations 110–114 applied; ledger **135**, tip `20260902003623` | C3/C4 records |
| Monitor | `signing.expected_key_fingerprint` v2 = D5 (dual-controlled, approved by founder B), `signing.expected_max_not_after` null, `signing.monitor_enabled` true; cron job 27 `23 5 * * *`, last run 2026-09-11T05:23Z succeeded; checker `ok/match`, 0 alert rows | C5/C6 records |
| Dark signer | 14 edge functions: `credential-sign` (JWT), `door-manifest` (JWT), `door-session` (no JWT) at v1, hashes as reviewed; 24 secrets by name (six E2 names); **0 requests, 0 signatures** | C6 record |
| Data | tickets/door_session/door_manifest/scan_device/door_pin/staff_role/organization/catalog.venue/event/event_session all **0**; `feature.native_issuance_enabled` **false**; `feature.native_scanning_enabled` **false** | C6 record |

**Standing controls that must not silently erode before T3:** the zero-data precondition (a production venue/staff role/manifest/device/PIN would make door-manifest and door-session reachable by an authorized caller); both feature flags false; no additional runtime key; no policy/trust change; `AUTODEPLOY-VERIFIED-OFF` discipline and empty `git_branch` on every migration PR.

## 2. Bootstrap handoff definition — status

| # | Definition item (remaining-path §5) | Status |
|---|---|---|
| 1 | C5 COMPLETE (pin v2 = D5 by founder B, monitor armed, first check ok/match, Mac 2 read-back) | **MET** 2026-09-11 |
| 2 | Migration 121 applied, or explicitly deferred by the owner in writing | **DEFERRED by the owner** (2026-09-11) to Claude A's integration after the Build 16 handset matrix; PR #58 draft rev 2 (`030a922b…`), combined chain 142; hardening, not a blocker |
| 3 | C6 COMPLETE dark (3 functions, secrets by name, 1 key, 0 invocations, 24 h quiet, CloudTrail 0 runtime AssumeRole/Sign, monitor ok) | **MET** 2026-09-12 |
| 4 | Governance artifacts final (C5/C6 records, packet §5b ledger, runbook dated notes, remaining-path in handoff state, Model A package §5c, M5 clarification §5d, C8 checklist) | **MET** — records pushed this session; §5c/§5d/C8 materials unchanged in the packet as the T3 gate bundle |
| 5 | Open items list with owners | §4 below |

## 3. Remaining launch gates (in order; each under its own phrase)

| Gate | Phrase / decision | Actor | Preconditions | Coordinator role |
|---|---|---|---|---|
| **G1 — Migration 121** (defensive STRICT read in `venue.get_manifest_signing_context`) | `AUTHORIZE PFA-18C MIGRATION 121` | Claude A (integrate into the 142-chain after Build 16), owner (apply) | PR #58 merged; day-of `AUTODEPLOY-VERIFIED-OFF`; dry run lists exactly `121_…`; `git_branch ""` | read-backs: md5 `333372bbbe7dd8fe1a95db4de66ea4c6`, `strict=true`, grants service_role-only, ledger 136, context `ok/…b0`; suites 180/189 green |
| **G2 — M5 ruling** | written owner ruling in the packet §5d (adopt M5-iso + M5-live, or an alternative) | owner | none | record; prepare the M5-iso package only if adopted |
| **G3 — Model A** (organization, audit account, Object-Lock bucket, SCP, org trail, Device-2 audit read) | proposed `AUTHORIZE PFA-18C MODEL A`; owner decisions on e-mail aliases, retention years, delegated admin, Model-B trail | owner (M-A1…M-A10), Mac 2 (M-A11 with new `snatchit-org-verifier` + passkey) | none technical; account-creation and invitation waits | packages + read-backs; no mutation |
| **G4 — M5-live = T3** (first production credential on an internal test event via `venue.issue_comp`; one `credential-sign`, one `door-manifest`; exactly one `Sign` each) | `AUTHORIZE PFA-18C M5` | owner (+ founder B for any dual-controlled config) | G2, G3, C6 (done), monitor armed (done) | CloudTrail/edge-log/`/keys` read-backs |
| **G5 — C8 issuance flip** `feature.native_issuance_enabled := true` | owner act outside the runbook | owner | G4 green; M6; Model A operational | read-backs; monitor |
| **G6 — Migration 122** (086↔112/113 expired-episode drift in `venue.sync_scan_device_manifest`) | `AUTHORIZE PFA-18C MIGRATION 122` | engineering (coordinator or A), owner (apply) | numbering with Claude A; rehearsal + CI | migration/rollback/test; **required before G7, not before G5** |
| **G7 — C8 scanning flip** `feature.native_scanning_enabled := true` | owner act | owner | G5, G6, scanner SDK readiness | read-backs |
| **G8 — Live commerce checks** (Stripe live checkout on an internal event, payout posture) | primary-ticketing activation runbook | owner + payments program | G5 | separate program |

**Not claimed:** launch readiness. It is reached only after G3–G8 are proven under their own authorizations.

## 4. Open items and owners (non-gating unless stated)

| Item | Owner | Note |
|---|---|---|
| Root `PasswordRecoveryRequested/Completed` 2026-09-08T01:17–01:18Z (out of window) | owner | acknowledgement still outstanding in the record |
| Account password policy; CloudTrail alarm on runtime-role `AssumeRole`/non-runtime `Sign`; runtime key 90-day rotation (two-key overlap procedure) | owner / engineering | hardening residuals |
| Weekly dark posture read (Sign total 3, 0 lifecycle, 0 runtime AssumeRole, 1 key, monitor ok, counts 0, flags false) until T3 | coordinator on request | remaining-path §2.7; ~10 min |
| Daily monitor cron observation (next run 2026-09-12T05:23Z) | coordinator on request / Mac 2 | egress path (`notify-report`) still untested by a real alert |
| Optional STS-only assume test (remaining-path §2.4) | owner decision | uses the C6 credential outside the edge; records one runtime `AssumeRole` — would change the "0 ever" baseline; decide before running |
| Admin CLI session expiry (`aws login`) | owner | re-authenticate before any coordinator AWS read-back; the coordinator never authenticates |
| Local `~/pfa18c-local` placeholder artifacts and C3 directory | owner | keep or remove at the owner's discretion; key/env files already unlinked |
| Uncommitted owner docs `PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md`, `docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md` | owner | never committed by the coordinator |
| D7 "Transfer not found", Build 16 handset matrix, 142-chain integration, numbering for 121/122 | Claude A / C, owner | in progress |
| PFA-18A un-park (rotation/provisioning lifecycle) | governance + engineering | post-launch |

## 5. Rollback surfaces still available (each needs its own phrase)
- C6: `AUTHORIZE PFA-18C C6 ROLLBACK` — secrets unset (six names) → functions delete (three slugs) → delete the C6-1 access key; KMS/roles/trust/DB/monitor untouched.
- C5: `AUTHORIZE PFA-18C MONITOR DISARM` — `signing.monitor_enabled := false` (single admin); fingerprint un-pin is dual-controlled.
- C3/C4: production is forward-only; DB rollbacks need their own authorization and the rollback files in `supabase/rollbacks/`.
- C2: key lifecycle actions are explicit-denied to the ceremony/verifier principals by design; any KMS lifecycle change is an owner act under a new phrase.

## 6. Record locations
`docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md` (sessions 1–28) · `…_C2_EXECUTION_RECORD.md` · `…_C3_EXECUTION_RECORD.md` · `…_C4_EXECUTION_RECORD.md` · `…_C5_EXECUTION_RECORD.md` · `…_C6_EXECUTION_RECORD.md` · `…_121_FORWARD_FIX_PACKAGE.md` (rev 2; PR #58) · `…_EXECUTION_READINESS_PACKET.md` (§5b ledger, §5c Model A, §5d M5) · `…_OWNER_CEREMONY_RUNBOOK.md` (dated notes) · `…_REMAINING_PATH_AND_HANDOFF.md` (plan of record).
