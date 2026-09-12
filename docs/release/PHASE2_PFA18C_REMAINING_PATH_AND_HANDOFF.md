# PFA-18C — REMAINING PATH FROM C5 TO COORDINATOR HANDOFF (planning document · nothing executed · no authorization implied)

> **2026-09-12 — HANDOFF STATE REACHED.** C5 and C6 are COMPLETE; the §5 definition is met except item 2 (migration 121), which the owner explicitly deferred to Claude A's integration sequence. The current gate list is `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md`; the text below is preserved as the plan of record dated 2026-09-10.

**Date:** 2026-09-10 (late) · **Coordinator:** Claude B · **Basis:** the ratified single-founder packet (`PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md` §5b/§5c/§5d, `PFA_SINGLE_FOUNDER_KMS_BOOTSTRAP.md` maturity trigger, `PFA_18C_OWNER_RATIFICATION.md`), the owner runbook, and the execution record through session 25.
**Standing state:** C1 · C2 · C3 · C4 COMPLETE. **C5 paused after C5-1** (request `05e0ff5d…` pending, expires 2026-09-13T19:59:17Z; pin v1; monitor disabled). **Migration 121** review-only (PR #58 draft, rev 2). **C6** review-only. **C7/M5** pending governance clarification. **Model A** not authorized. Issuance and scanning **false**. Consumer QA paused at D7 (Claude A/C); Build 16 handset matrix open; combined release + venue + 121 chain = 142 migrations (A). Effort figures below are estimates of active time, excluding waits.

---

## 0. Dependency map (read left → right)

```
C5 resume ──► C5 COMPLETE ─┐
121 (after D7 / Build 16 via A) ─┤ (recommended, not blocking)
                                 ├─► C6 dark deploy ─► 24 h quiet window ─► COORDINATOR HANDOFF
086↔112/113 fix (mig. 122) ──────┼─(needed only before the SCANNING flip)
                                 │
Model A (§5c) ───────────────────┴─► M5-live (= T3) ─► C8 issuance flip ─► C8 scanning flip ─► live commerce checks ─► launch
M5-iso (optional, needs a ruling + isolated infra) — evidence only; does not replace M5-live
```

## 1. Work needed to finish the backend deployment while issuance stays disabled

| # | Step | Phrase / gate | Actor | Dependencies | Effort |
|---|---|---|---|---|---|
| 1.1 | **C5 resume** — re-read request state/expiry; C5-2 founder B approval (browser console, aal2); C5-3 arm (gated on v2 = D5); C5-4 first check `ok/match`; Mac 2 config read-back; record **C5 COMPLETE** | "AUTHORIZE PFA-18C MONITOR ARMING" (in force) | owner + founder B + Mac 2 | founder B available before 2026-09-13T19:59Z (else C5-1 re-run with a new command key) | 30–45 min elapsed (B: 10 min; owner: 10 min; coordinator read-backs) |
| 1.2 | **Migration 121 integration + apply** (defensive hardening; recommended before C6, not a blocker) | "AUTHORIZE PFA-18C MIGRATION 121" | Claude A (integration), owner (apply), coordinator (read-backs) | D7 investigation and Build 16 handset matrix closed (A); PR #58 merged into the release chain (142); day-of `AUTODEPLOY-VERIFIED-OFF`; dry run lists exactly 121 | 1 h incl. CI/merge/apply/read-backs |
| 1.3 | **C6 dark deploy** — C6-1 one runtime access key; C6-2 env file (E2 contract); C6-3 `secrets set --env-file`; C6-4 deploy `credential-sign`, `door-manifest` (verify_jwt true), `door-session --no-verify-jwt`; C6-5 dark verification (zero invocations; CloudTrail 0 `AssumeRole`/`Sign`); record | "AUTHORIZE PFA-18C DARK DEPLOY" | owner (all mutations), coordinator (read-backs), Mac 2 (read-back) | C5 COMPLETE (P1); deploy commit = CI-green tip carrying E2 (`72d4e90` lineage) and the applied migrations (110–114 live; 121 if applied); detection plan (CloudTrail lookups for runtime-role `AssumeRole`/non-runtime `Sign`) ready; env file outside any repo, mode 600, deleted after use | owner 45–60 min; coordinator 20 min |
| 1.4 | **24-hour dark observation** — zero invocations, monitor cron `ok`, no alert rows, CloudTrail quiet, KMS unchanged | none (reads) | coordinator | C6 | reads only (3 × 10 min) |
| 1.5 | **Records + handoff bundle** — C5/C6 execution records, packet §5b/§6 ledger, runbook dated notes, this document updated with final state | none | coordinator | 1.1–1.4 | 1 h |
| 1.6 | **086↔112/113 expired-episode drift** (`venue.sync_scan_device_manifest` still binds a device to an expired-but-open episode while 112/113 report `open:false`) — migration **122** + rollback + test (numbering to coordinate with A), rehearsal, CI, apply | own phrase "AUTHORIZE PFA-18C MIGRATION 122" | engineering (coordinator or A), owner (apply) | **needed before the scanning flip, not before C6**; numbering coordination | 2–4 h engineering + 1 h apply cycle |

Not in this path (separate programs): payments/Connect/payout rails, consumer web/app QA (D7), Build 16 handset matrix, scanner SDK.

## 2. Verification that can run before Model A (no production credential is ever signed)

| # | Verification | What it proves | Actor | Effort |
|---|---|---|---|---|
| 2.1 | C5-4 first check + daily cron observation (`status ok`, `fingerprint match`, 0 `signing_key.invariant_alert` rows) | trust-root invariants watched; pin = D5 | coordinator (read-only MCP), Mac 2 optional | 5 min/day |
| 2.2 | Post-121 read-backs (definition md5 `333372bb…`, `strict=true`, grants, census, context `ok/…b0`) | hardening applied cleanly | coordinator + Mac 2 | 15 min |
| 2.3 | Post-C6 dark read-backs: `list_edge_functions` (3 new, correct `verify_jwt`), secrets **names** only, runtime access keys = 1, CloudTrail 0 runtime `AssumeRole`/`Sign`, edge logs boot-only | signer deployed but never exercised | coordinator + Mac 2 (Dashboard) | 20 min |
| 2.4 | **Optional STS-only assume test** from the owner's machine with the runtime key + ExternalId (`sts assume-role` → expected assumed-role ARN; **no** `kms sign`) — proves trust/ExternalId/session-name wiring; CloudTrail records one `AssumeRole` by the runtime user | STS chain works without touching the key | owner | 10 min; needs an owner decision (it uses the C6 credential outside the edge) |
| 2.5 | IAM simulator re-runs (runtime role `Sign` scoped to D4 only; ceremony/verifier lifecycle explicitDeny) | policy posture unchanged | coordinator | 5 min |
| 2.6 | pgTAP suites on the rehearsal harness for every landed migration (110–114, 121, 122) and the local C3/C5 rehearsals kept re-runnable | regression safety | coordinator | 20 min per run |
| 2.7 | Weekly CloudTrail posture: `Sign` total stays 3 (1 proof + 2 denied), 0 lifecycle events, root 0, verifier 0 mutations | no drift while dark | coordinator | 10 min/week |
| 2.8 | **M5-iso** (§5d item 1) — the same edge code on **isolated** infrastructure with a **non-production** KMS key, test runtime user/role, staging project or CI job: STS → KMS `Sign` → DER→raw → sign-after-verify → token → offline verify via `/keys` | full signing chain end-to-end without T3 | engineering + owner (setup authorizations) | setup ~1 day (test key ≈ $1/month; test principals; CI job with scoped secrets) + 1 h run. **Status: proposed for review, not approved** (see §3) |

Not runnable before Model A: any `credential-sign` call with the production key; door-manifest signing on a production episode (treated conservatively as post-Model A, §5d item 3).

## 3. Work blocked on Model A / T3 — and the approved status of M5-iso vs M5-live

**Current approved status (exact):** the packet §5d records a **genuine inconsistency** (M5 requires signing a credential before the issuance flip; no sanctioned path yields an atom before the flip; the signed credential would itself be T3) and a **proposed clarification — M5-iso + M5-live — "prepared for review (no ruling invented)"**. **Neither part has been ruled on.** C7 remains **PENDING governance clarification**; the runbook C7 row carries the 2026-09-08 R5 note that C7 as written is not executable. Until the owner rules: no M5-iso infrastructure is authorized, and M5-live is by definition T3.

| # | Item | Gate / phrase | Actor | Dependencies | Effort |
|---|---|---|---|---|---|
| 3.1 | **Owner ruling on M5**: adopt M5-iso + M5-live as written in §5d, or an alternative | written ruling recorded in the packet (dated) | owner | none | 30 min review |
| 3.2 | **Model A** (§5c): M-A1 management account (Paid, root MFA, 0 keys) → M-A2 `create-organization` → M-A3 audit account → M-A4 org audit bucket (Object Lock COMPLIANCE, retention years decided) → M-A5/6 invite + accept `652872010073` (consolidated billing consequence) → M-A7 OUs → M-A8 SCP `SnatchIt-WorkloadGuardrails` → M-A9 org trail → M-A10 verification + refusal probes (run while dark) → M-A11 Device-2 read-back from the audit account | phrase to be set by the owner (proposed: "AUTHORIZE PFA-18C MODEL A"); owner decisions: e-mail aliases, retention years (propose 3), delegated administrator, keep/stop the Model-B trail | owner (all), Mac 2 (M-A11 with a **new** audit-account verifier principal `snatchit-org-verifier` + passkey), coordinator (read-backs) | AWS account creation waits (hours–days), org invitation handshake | owner 3–5 h active over 1–2 days; coordinator 1 h; cost ≈ +$0.05–0.20/month |
| 3.3 | **M5-live = T3**: first production credential — recommended path `venue.issue_comp` on an internal test event under the activation authorization; one `credential-sign` call; one `door-manifest` call on a real open episode; CloudTrail exactly one `Sign` per call by the runtime role; offline verify via `/keys` | "AUTHORIZE PFA-18C M5" (runbook C7) **after** Model A operational and the M5 ruling | owner (+ founder B for any dual-controlled config), coordinator | 3.1, 3.2, C6, monitor armed | 1 h |
| 3.4 | **C8 issuance flip** `feature.native_issuance_enabled := true` (then, separately, `feature.native_scanning_enabled`) | owner act outside the runbook; requires M5 + M6 + Model A green; scanning flip additionally requires 1.6 (086 fix) and scanner SDK readiness | owner | 3.3; 1.6 | 15 min each + monitoring |
| 3.5 | **Live commerce checks** (Stripe live checkout on an internal event, payout posture) per the primary-ticketing activation runbook | separate program | owner + payments program | 3.4 | not estimated here |
| 3.6 | Hardening residuals (not blockers): root password-recovery events acknowledgement; account password policy; runtime key 90-day rotation procedure; CloudTrail alarms for runtime-role `AssumeRole` anomalies; optional token-verified path for `catalog.set_platform_config` (PostgREST exposure or admin-console screen) | own decisions | owner / engineering | none | 1–4 h each |

## 4. Who does what

| Actor | Remaining actions |
|---|---|
| **Owner (founder A, `jose-admin`, Mac 1)** | C5-3 arm; 121 apply; C6-1…C6-4 (access key, env file, secrets, deploys); Model A M-A1…M-A10; M5 ruling; M5-live; C8 flips; all authorizations; acknowledgement of the root password-recovery observation |
| **Second founder (B, contact@snatchitapp.com)** | **C5-2** approval (own MFA/aal2 session, browser console; must be a different principal than the proposer); any future dual-controlled config change (fingerprint re-pin, `ticket.%`/`fee.%`/`deletion.%` keys); one of the two approvers if the E4 two-person recovery is ever invoked; optionally a second org administrator in Model A |
| **Mac 2 (Device 2, verifier)** | post-C5 config read-back (Dashboard, Option A; privileged session, read-only by procedure); post-121 and post-C6 read-backs (Dashboard for DB state; `--profile verifier` for AWS: `list-access-keys` = 1 on the runtime user, key still v2, no lifecycle events); **Model A M-A11**: a new audit-account verifier principal with a passkey enrolled on Mac 2 and an independent read of the org trail/bucket; no signing, no secrets, no `PROD_DB_URL` ever |
| **Claude A / C** | D7 "Transfer not found" investigation; 121 integration into the 142-chain after Build 16; numbering coordination for 122 |
| **Coordinator (Claude B)** | read-backs, corroboration, records, packages; executes a mutation only when the owner explicitly instructs it in that turn (C4, C2-8 precedents) |

## 5. When this coordinator session is finished

**Definition — "PFA-18C bootstrap handoff complete":** all of the following are recorded in the execution record and pushed:
1. **C5 COMPLETE** (pin v2 = D5 approved by founder B, monitor armed, first check `ok/match`, Mac 2 read-back).
2. **Migration 121** applied (or explicitly deferred by the owner in writing) with read-backs.
3. **C6 COMPLETE** dark: three functions deployed, secrets present by name, one runtime access key, **zero invocations**, 24-hour quiet window, CloudTrail 0 runtime `AssumeRole`/`Sign`, monitor still `ok`.
4. Governance artifacts final: C5/C6 execution records, packet §5b/§6 ledger, runbook dated notes, this document updated to "handoff" state, the Model A package (§5c), the M5 clarification (§5d) and the C8 checklist bundled as the **T3 gate materials**.
5. Open items list handed over (§3.6, D7/Build 16, 086 fix) with owners.

At that point the production trust root and the dark signer exist, every invariant is monitored, and **every remaining step is a T3/commerce decision** (Model A, M5 ruling and M5-live, C8) or non-repository work. **Estimated remaining coordinator effort to reach that point: ~2 working sessions** (C5 ≈ 1 h elapsed once founder B is available; 121 ≈ 1 h after D7/Build 16; C6 ≈ 2 h plus the 24-hour quiet window; records ≈ 1 h), conditional on founder B's availability before 2026-09-13T19:59Z (or one C5-1 re-run) and on Claude A's integration timing.

## 6. Launch work that remains with another owner after the handoff

| Work | Owner | Depends on | Estimate |
|---|---|---|---|
| Model A (organization, audit account, SCP, org trail, Device-2 audit-account read-back) | owner (+ Mac 2) | phrase + decisions in §3.2 | 3–5 h active over 1–2 days |
| M5 ruling; M5-iso infrastructure (if adopted) | owner; engineering | ruling; test key/principals/staging or CI | 30 min ruling; ~1 day setup |
| M5-live (T3) and C8 issuance flip | owner | Model A, C6, monitor | 1–2 h + observation |
| 086↔112/113 fix (122) and scanning flip; scanner SDK readiness | engineering; owner; external | numbering with A; SDK | 2–4 h + 1 h apply; SDK not estimated |
| Live commerce checks (Stripe live checkout on an internal event, payouts) | owner + payments program | C8 | separate runbook |
| Consumer QA D7, Build 16 handset matrix, 142-chain integration | Claude A / C, owner | in progress | in progress |
| Operations: runtime key rotation (90-day, two-key overlap), CloudTrail alarms, Model-B trail retention decision, password policy, root recovery acknowledgement | owner | none | 1–4 h each |
| PFA-18A un-park (rotation/provisioning lifecycle) — long-term | governance + engineering | post-launch | not estimated |

**Not claimed:** launch readiness. It is reached only after Model A, M5-live, C8, the live commerce checks, and scanner readiness are proven — each under its own authorization.
