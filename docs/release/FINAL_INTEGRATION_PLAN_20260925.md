# Final integration plan: DRAFT (A owns; D verifies; E supplies frontend acceptance evidence), 2026-09-25

**What this is:** a planning and repository review. It authorises nothing: no merge, apply, deploy, feature switch
or production read. Exact release commits are frozen only after implementation and the independent native review are
complete (§7). The scope decisions are gathered in §6, each with a recommendation.

**How the facts were established**
- Git and GitHub were read directly (`git ls-tree`, merge-bases, `gh pr` reads).
- Production state comes **only from execution records**, cited below. No branch or open PR is taken as evidence of
  what production runs. No production read was made.
- **Evidence limit:** the ledger figure rests on the recorded read-backs after each apply (159, 160, 161, 162), not on a
  fresh read. One fresh `count(*)` would turn that chain of records into a single measurement. That read is an owner
  call.

**Authority rule adopted for this plan:** when a registry row's status contradicts an execution record, the execution
record wins. Rows should cite the record rather than restate it (§2). D reached the same rule independently.

Short names: REG = MIGRATION_NUMBER_REGISTRY.md · MAN = PRODUCTION_APPLY_MANIFEST_20260922.md · SS =
SPRINT_STATUS_20260917.md · HO = HANDOFF_A_20260924.md · P92/P93 = the PR92/PR93 execution packages · CL =
APP_STORE_SUBMISSION_CHECKLIST_V3_20260924.md · FD = FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md · WT =
PAYMENT_STATE_WORDING_TABLE_20260924.md · BS = BLOCKING_SCOPE_RECOMMENDATION_20260924.md · DP =
docs/operations/DEPLOYMENT_PATHS.md.

Refs:
- `main` = `eadd456a` (2026-09-01).
- Gate = `release/production-gate-20260918 @ 037092f0`. It contains `main`: 0 commits behind, 906 ahead.

---

## 1. Reconciled release inventory

Recommendation codes: **REQ** = required for this release · **COND** = conditional on a feature or decision ·
**DEF** = deferred.

### 1A. Deployed to production, not on `main`

`main` does not contain the source of the code production runs (D measured this independently). Everything in this
table is on the gate.

| Item | Source | Recorded production state | Rec. |
|---|---|---|---|
| Database: 73 migrations applied since `main`'s 89: 076–120, 123, 124, 127–133, 135, 136, 139, 140, 142–146, 20260902003623, 20260906100000/110000/120000/130000, 20260909000000, 20260916000000, 147–149 | gate | ledger **162**, last row `20260924120000`, 2026-09-24 20:31:03Z (P93:249; SS:1836). Arithmetic in §2.1 | **REQ**: bring into `main` |
| Payment edge functions: create-payment-intent v48, confirm-payment v37, stripe-webhook v42, create-connect-account v35, delete-account v22, notify-transfer v8, send-push v22, notify-report v10 | gate `5b255838` | deployed 09-23 (SS:1401,1416-1422; HO:22) | **REQ** |
| enforce-transfer-expiry v41 | `e73553d2` (= gate `374103c0`) | 09-24 16:56:45Z (P92:473) | **REQ** |
| confirm-and-release v38 | gate `037092f0` | switchover 09-24 20:31:20.378Z (P93:250) | **REQ** |
| credential-sign, door-manifest, door-session v1 | `562fda9` | 09-11 (PHASE2_PRODUCTION_STATE_20260912:14); dark signing surface | **REQ** (the source must be on `main`; the feature stays dark) |
| Not deployed but on the gate: ops-refund-execute, refund-execute, payout-execute, primary-checkout, connect-onboarding | gate | not deployed (MAN:172-173) | on `main` as dark source; unchanged |
| Configuration: Vault `project_url` (09-22 23:08:30Z), cron jobids 32–36, `ops.setting` (12 rows; executors and alert delivery off) | records | SS:1395,1399,1413,1423 | nothing to merge; restated in the release record |

### 1B. Written but unmerged or unapplied migrations

| No. | Source | Implementation | Recorded production | Dependencies | Rec. |
|---|---|---|---|---|---|
| **150** `20260925000000` refund lifecycle | PR #94 @`2eebc5bf` (base: the gate) | CI green; **D PASS** | not applied | the #94 edge deploy follows the apply; then O-R1/O-R2 | **REQ** |
| **151** `20260925010000` stuck seller-win detector | PR #95 @`9a66f29d` (base: the gate) | CI green; **D PASS** | not applied | **must merge after #94** (§4 C6); apply before the first seller-win resolution | **REQ** |
| **121** manifest signing context, strict | gate tree (blob `9b3db1ba`); PR #58 is redundant | written | **not applied**, excluded by MAN:43 (applies only under `AUTHORIZE PFA-18C MIGRATION 121`) | B's PFA-18C track | **DEF** (decision D1) |
| **125** scan-device manifest sync | gate tree (`817eff22`); PR #62 is redundant | written | not applied (MAN:44, §4) | scanning is dark | **DEF** (D1) |
| **126** ops refund exactness | gate tree (`8da9ccfb`). PR #63 carries the same blob but is red and based on `release/convergence-135` | written | not applied (MAN:44) | optional B/D console track; no overlap with 150 or 151 (§2.3) | **DEF** (D1) |
| **138** operator onboarding | `ops/138-operator-onboarding @ a9aa34e6` | written | not applied; the owner ruled it stays outside the candidate (REG:34) | cannot land as "138": needs a timestamp version (§4 C6) | **DEF** |
| **141** withdraw retires the deletion notice | `fix/f-notice-1-withdraw-retires-notice @ ea547e56` | written; D and B reviewed | not applied; owner 09-17: "stays UNAPPLIED" (REG:36) | would need a timestamp version | **DEF** |
| `20260910120000` venue_api read slice | `venue/read-adapters-slice-1` | written | not applied (REG:21) | venue dashboard | **DEF** |

### 1C. Reserved or proposed, not written

| Item | Record | Dependencies | Rec. |
|---|---|---|---|
| **152**: blocking, server half | REG:51; BS §2d, §5 | the owner's approval of BS §5, then 152, then C's client half and the web read switch | **COND** on D2 (recommended: approve and include) |
| **137**: outbid | REG:32 (allocated 2026-09-17, not written) | would need a timestamp version | **DEF** |
| **Operator suspension and listing takedown** | BS §2e; CL P3:196-198; PP:112 | its own package. It conflicts with the app's kept "may remove content or suspend accounts" copy (CL P3) | **COND** on D5 |
| F-LISTING-CRITICAL-TIER-1: the critical risk tier is enforced only in the client | FD:89-107 | needs a new version extending the 119 guard | **DEF** |
| F-BASELINE-HANDLE-NEW-USER-1: production's `handle_new_user` is richer than the repo's | FD:274-285 | a numbered no-op parity migration. It is a disaster-recovery risk only | **DEF** (required before any rebuild from the repo) |
| The losing buyer is told "Order complete" after a seller-win payout | FD:228-230; WT §2i | an edge copy change plus a migration for the in-app row | **COND**: required before the first seller-win resolution (same trigger as 151) |

### 1D. Release-critical work with no migration number

| Item | Source / state | Recorded deployment | Dependencies | Rec. |
|---|---|---|---|---|
| Refund operational decisions O-R1–O-R4 | RL §B | none | 150 applied and the #94 functions deployed | **REQ**: O-R1, O-R2, O-R3 (decision). **COND**: O-R4 (may follow) |
| Web wording W-1a–W-6 plus the extra strings (FD a7) | WT §2h with its acceptance bar; **no implementer assigned** | the live site (Vercel `snatchit-web`, production branch `feature/web-accounts-foundation @ 1765bbeb`) still shows the false strings | none on the database; reads existing columns only | **REQ** (D3) |
| Admin labels (a5/a6, F1-ADMIN-1) | `admin/label-truth-conditions @ 789025f3`, based on the gate; **A PASS** | console pinned to `ab3e17f` (DEPLOYMENT_RECORD_2026-09-08:29,78) | the owner changes the console pin | **REQ** (operators will work refunds and disputes with it) |
| Admin refund console | PR #89 @`3dab1614` (draft); never run against a live database | — | O-R3 | **COND** on O-R3 choosing console execution; otherwise **DEF** |
| Admin analytics redesign (supersedes three older admin branches) | `admin/analytics-redesign @ 64f26f90` | — | — | **DEF** |
| Stripe SDK interop patch (Xcode 26.6) | `e7af5242`, on C's local `v3/midnight-app` (unpushed); **A review PASS 2026-09-25** (SPRINT_STATUS) | build-time only | none | **REQ** for any Xcode 26.6 build |
| V3 app: successor candidate | local `v3/midnight-app @ f3f08930`, 57 commits ahead of origin `404bce38`; the gate is 34 commits ahead of v3 | Build 24 failed G0; no production candidate (G2) | native review, G0, then G2 | **REQ** |
| Blocking, client and web halves | BS §2d | only C's Home fix | D2 | **COND** on D2 |
| F-PD-EXPIRY-1: the expiry job writes `buyer_confirmed: false` | FD §F-PD-EXPIRY-1; source only | live in v41 | an edge deploy; kept separate from #94 | **DEF** (audit record only; the console annotates it) |
| Onboarding flag: create-connect-account sets it true on `details_submitted` alone; the webhook uses the AND of three flags | source only; **not recorded before this plan** | cc-account v35, webhook v42 | an edge deploy | **DEF**, recorded (payout re-checks the live capability, `_shared/payouts.ts:138`) |
| Operator alerting: nobody assigned to the queues, email off, no admin push token | CL R2, P2; PP B1/B2 | off | owner | **REQ** as an operating gate (D6) |
| Policy and Terms §6 (P4), open disputes (P6), stale live intents (P5), Twilio auto-recharge (R3), gates G0–G7, V2–V5 | CL | — | owner, B, C | **REQ** submission prerequisites, tracked in CL, not here |
| Inert features: native dispute wiring, the b2 push challenge, 139 dedupe | SS:1424,1428 | shipped inert | — | **DEF**, never described as working |
| Hygiene: candidate branch CI is red (tsc compiles downloaded function source under `docs/release/evidence/…/edge_out`) | run 36172707196 | — | — | **REQ** (A: exclude the evidence path from type-checking) |
| Hygiene: stale PRs, some targeting `main` (#43 not a draft, adds a migration and has no marker; #54 has 39 migrations and a 09-09 marker), and **no branch protection on `main`** | GitHub | — | owner | **REQ** before the `main` merge (D7) |

---

## 2. Stale statements resolved

1. **The ledger reconciles exactly** (D verified independently).
   - Gate: 165 = 151 numbered + 14 timestamped.
   - Before the 09-22 apply: 135 = 130 numbered up to 120 (including the 16 four-digit `0xxx` files) + 5 timestamped
     (the four on `main` plus `20260902003623`).
   - The manifest added 24 (18 numbered, 6 timestamped), making 159. 147, 148 and 149 made 162.
   - **Unapplied gate files: exactly 121, 125 and 126.**
   - The rows marking 132, 133, 135 and `20260916000000` "production: NO" predate the manifest (MAN #8, #9, #10, #24).
2. **REG header** (lines 5, 13-16: "Production ledger 135", with PHASE2_PRODUCTION_STATE_20260912 as "canonical"):
   superseded by the manifest's execution (REG:3; SS:1399). Row statuses for 123–146 and the `2026090x` versions that
   still say "applied nowhere" are superseded the same way.
3. **Overlap check:** 126 redefines `ops.build_daily_summary`, `money_overview`, `refresh_metrics` and `refund_facts`.
   150 redefines `ops.detect_refunds` and 151 `ops.detect_release_stuck`. No overlap, so a later 126 apply cannot revert
   either (D confirmed).
4. **Row 149**'s leftover "**NOT applied anywhere.**" is superseded by the same row's "APPLIED TO PRODUCTION 2026-09-24
   20:31:03Z".
5. **Row 150**'s leftover "D review pending (owner-routed)" is superseded by D's PASS at `2eebc5bf`.
6. **Rows 121 and 125** name PRs #58 and #62 as their vehicles. Both files are already in the gate tree,
   blob-identical, so those PRs are redundant.
7. **D-INV-2 (126 appears twice):** the gate's copy is canonical. #63 carries the same blob but is red (the guard
   placeholder, and test 193 needs superuser) and is based on `release/convergence-135`. It is superseded, never merged.
8. **D-INV-3 (row 141 "contradicts itself"):** it doesn't. Every mention says unapplied ("unapplied anywhere", "stays
   UNAPPLIED", "applied nowhere"). The "APPLIED" that was flagged is the tail of "UNAPPLIED".
9. **Stripe webhook configuration has never been read.** "charge.refunded is subscribed" (RL:78,99) and the list of 11
   events come from source (CL:72). G3 stays open.
10. Other lagging statements:
    - HO:46-48 says #92 awaits R1; it was executed (HO:22).
    - AR:37 says the native build is blocked on Stripe; the patch is committed as `e7af5242` and its build is pending.
    - CL G9 is open, but the policy list (PP) decided it.
    - SS does not record G10's closure.
    - WT:131 names v40; production runs v41.
11. **Which mobile build the App Store serves is not recorded.** Build 13 was attached on 2026-08-04 and the owner was
    to resubmit (CL:43). That is the owner's fact.

## 3. Deployment triggers, one per artefact

| Artefact | What makes it reach production | Gate |
|---|---|---|
| **Database** | (a) **Merging to `main`** runs the Supabase GitHub integration (Path B, DP), which runs `db push` against production **if auto-deploy is on**; recorded off since 2026-08-27, the owner's latest visual confirmation is 2026-09-22 23:18Z. (b) The approved paths: a targeted per-file apply (file plus ledger row, with read-back), or an owner-run `db push` | a **fresh** owner visual confirmation before every migration-bearing merge to `main`; the owner's authorisation for each apply |
| **Edge functions** | Only a CLI or API deploy. No git trigger | the owner's authorisation; deploy from a detached worktree at the frozen commit; download and compare |
| **Web marketplace** | **Any push to `feature/web-accounts-foundation`** (web/DEPLOYMENT.md:8) | owner |
| **Admin console** | Pushes to `admin/operating-console`, but the Ignored Build Step builds only `ab3e17f1` (the 09-08 deployment record) | the owner changes the pin |
| **Mobile app** | Manual EAS builds. `appVersionSource: remote`; the `production` profile uses the production project and live Stripe key with autoIncrement; `eas submit` is owner-only | the owner authorises G2, the build and the submission |
| **Stripe and ops configuration** | Dashboard (webhook events), audited `ops.setting` changes, Vault | owner |
| **CI** | nothing (`ci.yml` has `contents: read`; the header says it never deploys) | — |

## 4. Compatibility requirements (these fix the ordering)

- **C1:** 150 is applied before the #94 functions are deployed, because they call `record_refund_state`.
- **C2:** 150 is backward-compatible with the deployed v41/v42. `record_payment_refund` is unchanged, the new columns
  have their own writer-only guard, and detection is seeded off. So apply, then deploy, is a safe window.
- **C3:** the Stripe `refund.*` subscription (O-R1) comes after the new stripe-webhook is live. The deployed v42
  acknowledges unknown events and discards them.
- **C4:** no client selects a column before it exists in production.
  - The V3 app selects none of 150's columns (the ruling in WT §2i).
  - Admin reads `to_jsonb(pd)`.
  - The web bar's criterion 8 covers the web.
  - **E and D run a static check of the app's reads against the production schema (the gate minus 121/125/126)
    before the freeze.**
- **C5:** 151 is independent. It must be applied before the first seller-win resolution (5 disputes open; CL P6).
- **C6:** migrations-guard's ordering rule: within each naming scheme a new version must be greater than the latest.
  - **#94 merges before #95**, or #94 fails the rule.
  - A revived 137, 138 or 141 needs a timestamp version above the latest.
- **C7:** never run `db push` against production. 121, 125 and 126 sit below the numbered tip (MAN:45-46), so the
  approved path is the targeted per-file apply.
- **C8:** the Stripe patch acts at install time only and fails the install unless the package is 0.50.3 with the
  expected file (hash-pinned to upstream `b613850f`'s bytes). It is correct on any Xcode version.
- **C9:** web, admin and mobile distribution are independent of the `main` merge: their production triggers are other
  branches, or manual.

## 5. Integration path

### 5.1 Source merges (no production effect except S7)

The release line is **the gate branch**, because production matches it (§1A).

| Step | Merge | Notes |
|---|---|---|
| S1 | #94 → gate | 150 plus its edge changes |
| S2 | #95 → gate | **after S1** (C6) |
| S3 | `admin/label-truth-conditions` → gate | fast-forward; `admin/` only |
| S4 | web wording branch → gate | written by the assigned owner; D verifies against the WT §2h bar. The web production branch's `web/` equals the gate's (verified), so the same commits also deploy the web (X9) |
| S5 | `v3/midnight-app` → gate | C first merges the gate into v3. v3 changes nothing under `supabase/`, so there are no migration conflicts. Then C pushes the 57 local commits. Merges after the native review, G0, and E's acceptance evidence |
| S6 | (if D2 is approved) 152 plus the client half | its own PRs, then D review |
| **S7** | **gate → `main`**, one PR | migration-bearing. It needs a **fresh** `AUTODEPLOY-VERIFIED-OFF`, the owner's authorisation and D's pre-merge check. Merge it **after X2–X4**, so that everything it carries is already applied except the known-pending files of D1. Post-merge check: the Supabase check reads `skipped` and the ledger is unchanged |

### 5.2 Production actions (each separately owner-authorised; D verifies each; in this order)

| Step | Kind | Action | Constraint |
|---|---|---|---|
| X1 | owner check | AUTODEPLOY visual confirmation; backup status | before X2 |
| X2 | database | apply **151** (targeted) | before the first seller-win resolution |
| X3 | database | apply **150** (targeted) | C2 |
| X4 | functions | deploy stripe-webhook and enforce-transfer-expiry from the frozen commit | after X3 (C1) |
| X5 | configuration | O-R1: add `refund.created`, `refund.updated` and `refund.failed`; read the endpoint (G3) | after X4 (C3) |
| X6 | configuration | O-R2: turn on `refund_state_detection_enabled` | after X5; O-R3 decided |
| X7 | database / Stripe | O-R4: the historical reconciliation read, then `record_refund_state(…,'reconcile')` | optional follow-on |
| X8 | configuration and deploy | admin console: merge into `admin/operating-console`, move the pin to the frozen commit | after S3 |
| X9 | deploy | web: push the fix commits to the web production branch (or, per D4, switch its production branch to `main`) | after S4 and D verification |
| X10 | source merge | S7 | after X2–X4 |
| X11 | app distribution | G2 EAS production build from the frozen v3 or gate commit, then TestFlight, the G1 phone session, and the owner submits | after S5, G0 and E's evidence; independent of X2–X10 except C4 |

## 6. Scope decisions for the owner (with recommendations)

- **D1: 121, 125 and 126 at the `main` merge.**
  - **Options:**
    - (a) Apply them before S7. 121 needs PFA-18C.
    - (b) Remove them, and the pgTAP they couple to (184, 186, 189, 190, 193), from the line merged to `main`.
    - (c) Merge them as **known-pending, targeted-apply-only** files.
  - **Recommendation: (c).** `main` then equals the gate: the tested replay world, CI-green. The deployed code reaches
    `main` without a `main`-only tree that nobody has tested. The three stay deferred, each with its owner (121 and 125
    with B's signing track, 126 with D).
  - **Condition:** the fresh AUTODEPLOY confirmation at S7, and the release record listing them as the only files on
    `main` not in the ledger.
  - (b) makes `main` equal the ledger exactly, but rewrites five test suites outside A's lane just before release.
- **D2: blocking.** Approve BS §5 and include 152, C's client half and the web read switch in this release.
  **Recommended.** The app claims block tools (CL:115). Today a block only hides the seller's listings, and Apple 1.2
  expects blocking.
- **D3: web wording.** Assign an implementer; the web surface has no owner. **Recommended: E, within the frontend
  scope**, with D verifying against WT §2h and the fix deployed by X9.
- **D4: web production branch.** **Recommended:** after S7, switch `snatchit-web`'s production branch from
  `feature/web-accounts-foundation` to `main`, so that one branch is the source of truth. Until then, X9 pushes to the
  current production branch.
- **D5: operator suspension and takedown.**
  - **Recommended:** C removes the "remove content / suspend accounts" promise for this release, unless you approve an
    operator package now.
  - The app promises it (CL P3) and no mechanism exists.
  - Operator suspension (BS §2e) is then the next backend package after 152.
- **D6: operator alerting and queues (CL R2).** Name who works `/cases` and `/reports`, and how often. **Required before
  submission.** O-R3 (failed refunds) is part of the same answer.
- **D7: repository safety before S7.**
  - **Recommended:** protect `main` (required reviews, plus the required checks including migrations-guard).
  - Close the superseded PRs: #43, #52, #54, #56, #58, #62, #63, #64, #70, #87, #11.
  - Today nothing but draft status stops #54 (39 migrations) from merging to `main`.
- **D8: deferred list confirmed as deferred:** 137, 138, 141, venue_api, F-LISTING-CRITICAL-TIER-1, handle_new_user
  parity, F-PD-EXPIRY-1, the onboarding flag, admin analytics, and #89 (unless O-R3 needs it).
- **D9: the losing buyer's "Order complete".** **Recommended:** include the copy fix with 151's timing, before any
  dispute is resolved. It needs one edge change and one migration.

## 7. Freeze procedure (after implementation and the native review)

- **What to freeze:** the gate commit after S1–S5 (and S6 if D2 is approved); the `admin/operating-console` commit for
  X8; the web commit for X9; and the EAS source commit for X11. Record each as a full sha, together with its CI run
  and headSha.
- **D verifies** the plan against D's independent inventory (`f740ab73`), then each frozen package.
- **E supplies** the frontend acceptance evidence:
  - G0 on the successor build;
  - the native-review record;
  - the static read check under C4;
  - the web-bar evidence.
  E does not take backend work.
- **Execution packages** (X2–X9) are written after the freeze, each with rollback, read-backs and D's pre-registered
  expectations, and each waits for the owner's authorisation.
