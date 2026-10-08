# Final integration plan: DRAFT, revision 2 (A owns; D verifies; E supplies frontend acceptance evidence), 2026-09-26

Revision 1 was verified by D against D's independent inventory (originally `f740ab73`, now lost; D's labelled reconstruction is on `review/d-records-20261005 @ 7554d913`). **Revision 2 addresses the owner's six
corrections of 2026-09-26** (§5.1 point 1 wording, §5.2B 152, §5.1 merge method, §5.3 combined-candidate verification,
§6.2 critical-tier deferral, §8 PR dispositions). D is verifying revision 2.

**Scope statements (owner, 2026-09-26):**
- The admin-label release is separate from the larger admin presentation work (analytics redesign and so on).
- F is handling the isolated venue demonstration.
- Venue production integration remains separate from this release (#52, `venue_api`).

**What this is:** a planning and repository review. It authorises nothing: no merge, apply, deploy, feature switch
or production read. Exact release commits are frozen only after implementation and the independent native review are
complete (§7). The owner decisions are consolidated in §6.0, with the detail in §6.1–§6.2.

**How the facts were established**
- Git and GitHub were read directly (`git ls-tree`, merge-bases, `gh pr` reads).
- Production state comes **only from execution records**, cited below. No branch or open PR is taken as evidence of
  what production runs. No production read was made.
- **Evidence limit:** the ledger figure rests on the recorded read-backs after each apply (159, 160, 161, 162), not on a
  fresh read. One fresh `count(*)` would turn that chain of records into a single measurement. That read is an owner
  call.

**Provenance (D's addition A-2):**
- This plan, BLOCKING_SCOPE_RECOMMENDATION_20260924.md and registry row 152 exist **only on
  `release/candidate-20260918`** (the records line), not on the gate. Anyone executing from a gate checkout reads them
  from the candidate.
- The candidate's `ci.yml` census is stale (31|96|37|35), because the candidate is a docs line. The CI census that
  counts is the gate's: 32|108|37|38 at `037092f0`, and 34|111|37|40 after S1 (151 adds no object).
- XB0's census deltas are computed from the gate as it stands when 152 is written.

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
| Database source: the gate has **76 migration files that `main` lacks** (165 vs 89). Per the records, **73 of them are already in the production ledger**: 076–120, 123, 124, 127–133, 135, 136, 139, 140, 142–146, 20260902003623, 20260906100000/110000/120000/130000, 20260909000000, 20260916000000, 147–149. The other 3 (121, 125, 126) are not | gate | recorded ledger **162**, last row `20260924120000`, 2026-09-24 20:31:03Z (P93:249; SS:1836). Arithmetic in §2.1. No fresh read | **REQ**: bring the source into `main`. **Adding a file to `main` is not applying it**: see §3 and S7 |
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
| **152**: blocking, server half | REG:51; BS §2d, §5 | the owner's approval of BS §5, then 152 **as a timestamp file** (§4 C10), then C's client half and the web read switch; sequence in §5.2B | **COND** on D2 (recommended: approve and include) |
| **137**: outbid | REG:32 (allocated 2026-09-17, not written) | would need a timestamp version | **DEF** |
| **Operator suspension and listing takedown** | BS §2e; CL P3:196-198; PP:112 | its own package. It conflicts with the app's kept "may remove content or suspend accounts" copy (CL P3) | **COND** on D5 |
| F-LISTING-CRITICAL-TIER-1: the critical risk tier is enforced only in the client | FD:89-107 | needs a new version extending the 119 guard, plus a tier-refresh scheduler | **DEF**, with its own justification in §6.2 |
| F-BASELINE-HANDLE-NEW-USER-1: production's `handle_new_user` is richer than the repo's | FD:274-285 | a numbered no-op parity migration. It is a disaster-recovery risk only | **DEF** (required before any rebuild from the repo) |
| The losing buyer is told "Order complete" after a seller-win payout | FD:228-230; WT §2i | an edge copy change plus a migration for the in-app row | **COND**: required before the first seller-win resolution (same trigger as 151) |

### 1D. Release-critical work with no migration number

| Item | Source / state | Recorded deployment | Dependencies | Rec. |
|---|---|---|---|---|
| Refund operational decisions O-R1–O-R4 | RL §B | none | 150 applied and the #94 functions deployed | **REQ**: O-R1, O-R2, O-R3 (decision). **COND**: O-R4 (may follow) |
| Web wording W-1a–W-6 plus the extra strings (FD a7) | WT §2h with its acceptance bar; **no implementer assigned** | the live site (Vercel `snatchit-web`, production branch `feature/web-accounts-foundation @ 1765bbeb`) still shows the false strings | none on the database; reads existing columns only | **REQ** (D3) |
| Admin labels (a5/a6, F1-ADMIN-1) | `admin/label-truth-conditions @ 789025f3`, based on the gate; **A PASS**. Released **separately** from the admin presentation work (§5.1 S3) | console pinned to `ab3e17f` (DEPLOYMENT_RECORD_2026-09-08:29,78) | the owner changes the console pin | **REQ** (operators will work refunds and disputes with it) |
| Admin refund console | PR #89 @`3dab1614` (draft); never run against a live database | — | O-R3 | **COND** on O-R3 choosing console execution; otherwise **DEF** |
| Admin analytics redesign (supersedes three older admin branches) | `admin/analytics-redesign @ 64f26f90` | — | — | **DEF** |
| Stripe SDK interop patch (Xcode 26.6) | `e7af5242`, on C's local `v3/midnight-app` (unpushed); **A review PASS 2026-09-25** (SPRINT_STATUS) | build-time only | none | **REQ** for any Xcode 26.6 build |
| V3 app: successor candidate | local `v3/midnight-app @ f3f08930`, 57 commits ahead of origin `404bce38`; the gate is 34 commits ahead of v3. B's native review of `f3f08930` is pending on that install (AR:24) | Build 24 failed G0; no production candidate (G2) | B's review of `f3f08930`, then the combined-candidate verification (§5.3), then G2 | **REQ** |
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
| **Database** | (a) **A merge to `main` executes migrations only if the Supabase GitHub integration's auto-deploy is on at that moment** (Path B, DP). Its last recorded state is off: `git_branch ""` since 2026-08-27 by API reads on 09-18/22/24, and the owner's latest visual confirmation at 2026-09-22 23:18Z. **The current setting is unverified.** If off, a merge executes nothing; the `Supabase Preview` check reads `skipped`, as observed 2026-08-27. If on, the integration runs the CLI's `db push` sequence against production, and what it would attempt depends on the ledger at that time: per the records, only versions missing from the ledger, i.e. 121, 125, 126, and 150/151 if they are not yet applied. How the CLI treats files below the remote tip, apply or refuse, is not established. **The plan never relies on it.** (b) The approved paths: a targeted per-file apply (file plus ledger row, with read-back), or an owner-run `db push` | a **fresh** owner visual confirmation before every migration-bearing merge to `main`; the owner's authorisation for each apply |
| **Edge functions** | Only a CLI or API deploy. No git trigger | the owner's authorisation; deploy from a detached worktree at the frozen commit; download and compare |
| **Web marketplace** | **Any push to `feature/web-accounts-foundation`** (web/DEPLOYMENT.md:8) | owner |
| **Admin console** | Pushes to `admin/operating-console`, but the Ignored Build Step builds only `ab3e17f1` (the 09-08 deployment record) | the owner changes the pin |
| **Mobile app** | Manual EAS builds. `appVersionSource: remote`; the `production` profile uses the production project and live Stripe key with autoIncrement; `eas submit` is owner-only | the owner authorises G2, the build and the submission |
| **Stripe and ops configuration** | Dashboard (webhook events), audited `ops.setting` changes, Vault | owner |
| **CI** | nothing (`ci.yml` has `contents: read`; the header says it never deploys) | — |

## 4. Compatibility requirements (these fix the ordering)

- **C1:** 150 is applied before the #94 functions are deployed, because they call `record_refund_state`.
- **C2:** 150 is backward-compatible with the deployed v41/v42.
  - **150 does not redefine `record_payment_refund`**, the writer v41/v42 call. That can be checked with one grep of
    the migration.
  - The three new columns are `NOT NULL DEFAULT 0`, behind their own writer-only guard.
  - Detection is seeded off.
  - So apply, then deploy, is a safe window (D verified).
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
- **C10 (only if D2 selects blocking):**
  - **Versioning.** The "152" package must be issued as a **timestamp file** after `20260925010000`, not as
    `152_*.sql`. It redefines `public.reserve_buy_now`, whose current body comes from timestamped `20260906100000` (the
    last definer in LC_ALL=C order). A numbered file sorts before it, so a fresh replay would silently overwrite 152's
    refusal: the 134 trap (REG "Versioned by TIMESTAMP"). The registry keeps 152 as its ID.
  - **Ordering.** Every client that calls `listings_feed`, `listing_view_state()` or `user_view_state()` (the V3 app,
    and the web after its switch) must reach users only **after** the database change is applied, per C4.
  - **Old clients** keep working: they still read `listings`, and a refused bid surfaces as their generic error
    (BS §5).
  - **Rollback boundary.** Once a client that reads the new objects is distributed, rolling back those read objects
    would break it. The rollback is then limited to the enforcement parts (trigger and refusal), and the read objects
    stay.

## 5. Integration path

### 5.1 Source merges (no production effect except S7)

The release line is **the gate branch**, because production matches it (§1A).

**Precondition P0, before S1: repository safety. CORRECTED 2026-10-05; see MAIN_PROTECTION_PROPOSAL_20261005.md.**
- **`main` is protected,** by the repository ruleset `main-protection` (id 21624091), active since 2026-08-27 with no
  bypass actors. A and D had read only the classic protection API, which returns 404, so revision 2's "nothing
  mechanical stops those merges" was **wrong**.
- **The ruleset enforces:**
  - a PR is required (0 approvals);
  - five required checks: `Immutability + ordering`, `Migrations apply cleanly (fresh DB)`,
    `Typecheck / Lint / Unit tests`, `Web build (Next.js)`, `Secret scan (TruffleHog)`;
  - linear history;
  - squash or rebase merges only;
  - no deletion and no force-push.
- **Eleven open PRs target `main` today,** dependabot #96 included:
  - #43 and #11 are **blocked** by failing required checks;
  - #54 and #87 are drafts;
  - dependabot #53, #57, #59, #60, #61 and #96 are mergeable with one click.
- **Per the records, neither #43 nor #54 would apply anything** under either auto-deploy setting: #54's 39 migration
  files equal the gate's, and #43's version is in the ledger.
- **The residual risk** is a deliberate merge of a dependency bump, or an un-drafted #54, outside the release line.
- **Decisions:** the owner's PR-1–PR-7 in the proposal (required checks, strict policy, merge method, reviews, bypass,
  and rulesets for the gate and the two deploy branches).
- Closing the superseded PRs is separate hygiene, disposed of per PR in §8, with every head kept recoverable.

**Integration method, for every step:**
- A GitHub PR into the gate, merged with a **merge commit**: no squash, no rebase. The reviewed commit ids (`2eebc5bf`,
  `9a66f29d`, `789025f3`, and the frozen v3 sha) then stay in history unchanged.
- After each merge: CI green at the merge commit, **plus a diff check**. Every file the branch changed equals the
  branch's version, every other file equals the previous gate tip, and every file changed on both sides is inspected.
- Any later gate advance means the trial below is re-run.

**Trial evidence, 2026-09-26.** A local merge in a scratch worktree, nothing pushed, starting from `037092f0`, in this
order:

| Step | Trial merge commit | Conflicts | Branch files | Both-sided files | Mismatches / unexpected changes |
|---|---|---|---|---|---|
| S1 #94 | `89b2edca` | none | 13 | 0 | 0 / 0 |
| S2 #95 | `8a32e822` | none | 3 | 0 | 0 / 0 |
| S3 admin-label | `090d89d7` | none | 3 | 0 | 0 / 0 |
| S5 v3 `f3f08930` | `2771be10` | none | 235 | 3 | 0 / 0 |

- **The three both-sided files at S5** are `holdState.ts`, `CheckoutNative.tsx` and `checkout-escrow-note-unknown.test.ts`.
  They are an artefact of a criss-cross history, with two merge-bases, `131017a5` and `19b6fc2b`. The gate-side
  changes to them are the owner's 2026-09-19 escrow-line commits `bbd3e1bf`, `9eebcac2` and `19b6fc2b`, and **all
  three are ancestors of `f3f08930`**. v3's files contain that logic (`showEscrowNote` / `ESCROW_NOTE_COPY` present),
  so the result, which equals v3's version, loses nothing.
- **S3 is not a fast-forward** once S1 and S2 have landed. The label branch is based on `037092f0`, and the trial
  shows it merges without conflict and with exactly its 3 files.

| Step | Merge | Notes |
|---|---|---|
| S1 | #94 → gate | 150 plus its edge changes |
| S2 | #95 → gate | **after S1** (C6) |
| S3 | `admin/label-truth-conditions` → gate (merge commit) | puts the label source on the release line. **The console release is a separate path; see below** |
| S4 | web wording branch → gate | written by the assigned owner; D verifies against the WT §2h bar. The web production branch's `web/` equals the gate's (verified), so the same commits also deploy the web (X9) |
| S5 | `v3/midnight-app` → gate (merge commit) | after B's review of the v3 candidate (**now `d5217530`**, 2026-10-06; superseded: `f3f08930`; C's batch2 is separate) and the combined-candidate verification (§5.3) on the accepted candidate. C pushes the local commits first. v3 changes nothing under `supabase/` |
| S6 | (if D2) the 152 package, then C's client half, then the web read switch | their own PRs; D reviews; §5.2B |
| **S7** | **gate → `main`**, one PR. **The current ruleset allows only squash or rebase, with linear history; a merge commit needs the owner's PR-3** (MAIN_PROTECTION_PROPOSAL §2) | migration-bearing. It **adds 76 files to `main`, plus 150/151 and 152 if merged**. Whether any of them **executes** depends on the auto-deploy setting and the ledger at that moment (§3). **Precondition: a fresh owner visual confirmation that auto-deploy is off**, recorded as `AUTODEPLOY-VERIFIED-OFF`, together with the owner's authorisation and D's pre-merge check. Merge it **after X2–X4** (and XB1 if D2), so that everything it carries is already in the ledger except D1's known-pending files. Post-merge check: the `Supabase Preview` check reads `skipped`, and a ledger read (owner-authorised) is unchanged |

**Admin console release path**, separate from S3 and from the larger admin work.
- The console serves `ab3e17f`.
- Method: cherry-pick the label commits onto `ab3e17f` (`cherry-pick -x`), verify patch identity, then move the console
  pin to the result (X8).
- **Trial, 2026-09-26:** both commits apply cleanly on `ab3e17f`. Their patch-ids equal `004af0b0` and `789025f3`. The
  result passes the admin suite 117/117 with `tsc` exit 0.
- The only `admin/` difference between `ab3e17f` and the gate is `admin/scripts/acceptance/gate-probe.mjs`, which is not
  console code. So the release ships the label change and nothing else of the admin tree.
- The gate still receives the same patches via S3. The two commit identities are recorded as one change.
- **Built and reviewed (2026-10-06):** D's `admin/label-console-release @ 1058c882` (= `ab3e17f1` + `72ac2c52` +
  `1058c882`), **A PASS**.
  - Patch-ids equal `004af0b0` / `789025f3`.
  - Its **tree is identical** (`f7fa07d9…`) to A's independent re-trial of the same cherry-picks.
  - 3 files vs the pin; `tsc` 0, eslint 0, admin 117/117.
- **One change, two identities:** gate `004af0b0` + `789025f3` (through S3) and console `72ac2c52` + `1058c882` (through
  X8) are the same patches.
- X8 (moving the console pin) is the owner's configuration change.
- **Landing commit (2026-10-06):** `1058c882` is not a fast-forward of `admin/operating-console` (`562fda9a`, 5 commits past
  the served `ab3e17f`: docs and `gate-probe.mjs`). D's `efe03fca` (= `562fda9a` + the same two patches) is, with
  `admin/src`/`admin/tests` trees identical to `1058c882`'s (A verified). X8 = pin to `efe03fca`, **then** push it.
  Rollback: Instant Rollback to `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`, then the pin back. EXECUTION_SHEET_20261006.md §3.

### 5.2 Production actions (each separately owner-authorised; D verifies each; in this order)

| Step | Kind | Action | Constraint |
|---|---|---|---|
| X1 | owner check | AUTODEPLOY visual confirmation; backup status | before X2 |
| X2 | database | apply **150** (targeted) | C2. File order (D's finding): the ledger's insertion order then matches the LC_ALL=C replay order |
| X3 | database | apply **151** (targeted) | independent (C5); before the first seller-win resolution |
| X4 | functions | deploy stripe-webhook and enforce-transfer-expiry from the frozen commit | after X2 (C1) |
| X5 | configuration | O-R1: add `refund.created`, `refund.updated` and `refund.failed`; read the endpoint (G3) | after X4 (C3) |
| X6 | configuration | O-R2: turn on `refund_state_detection_enabled` | after X5; O-R3 decided |
| X7 | database / Stripe | O-R4: the historical reconciliation read, then `record_refund_state(pi, re_…, status, amount, failure_reason, source, 'reconcile')` (`'reconcile'` is the `p_observed_via` argument, not the source) | optional follow-on |
| X8 | configuration and deploy | admin console: the protected PR merge of `efe03fca` (cancelled by the current pin), verify the exact merge commit, then the pin plus a Redeploy of that commit with the Ignore Build Step kept (EXECUTION_SHEET_20261006 §3; exception: pin, then push `efe03fca`, then protect) | after the label change is reviewed; independent of S1–S7 |
| X9 | deploy | web: the fast-forward `fd0da772` (`e7130f04`'s three commits cherry-picked onto `1765bbeb`; `web/` tree identical) merged by PR into the web production branch after its ruleset (EXECUTION_SHEET_20261006 §2) | after W1; independent of S4 |
| X10 | source merge | S7 | after X2–X4 (and XB1 if D2) |
| X11 | app distribution | G2 EAS production build from the frozen v3 or gate commit, then TestFlight, the G1 phone session, and the owner submits | after S5, G0 and E's evidence; independent of X2–X10 except C4 |

### 5.2B If D2 selects blocking: the 152 sequence, added to the production actions

| Step | Kind | Action | Constraint / verification |
|---|---|---|---|
| XB0 | source | the 152 server package: `users_blocked()`, the `BEFORE INSERT` trigger on `bids`, the `reserve_buy_now` refusal (`BLOCKED_PARTY`), `listings_feed`, `listing_view_state()`, `user_view_state()`, the index `user_blocks(blocked_id, blocker_id)`, grants and the four CI files, and a guarded rollback that restores `20260906100000`'s `reserve_buy_now` body. Issued as a **timestamp file** (C10) | pgTAP 219: refusals in both directions; the exemptions (pre-block reservation, existing orders, a winning bid that predates the block, reports); direction-free outputs; `user_blocks` RLS unchanged. Mutants with predicted kill sets. CI green. **D PASS**. Merged as S6 |
| XB1 | database | apply 152 (targeted) | independent of 150/151. Read-back: function md5s, the view definition, trigger and index presence, grants, census. **Rehearse in the sandbox first**: no production behavioural test that touches real users |
| XB2 | client | C's client half in the V3 candidate. It reads `listings_feed`, `listing_view_state` and `user_view_state`, and maps `BLOCKED_PARTY` | part of the combined candidate (§5.3). **Distributed only after XB1** (C10) |
| XB3 | web | the web read switch to `listings_feed` (the web owner), deployed by X9 | **after XB1**; D verifies against BS §2d |
| XB4 | rollback boundary | from XB2's distribution on, the rollback is limited to the enforcement parts (C10) | recorded in the execution package |

### 5.3 Verifying the final combined candidate

- **B's native review of `f3f08930` is preserved as the review of that tree.** It is recorded as pending on that install
  (AR:24); it covers `f3f08930` and nothing later.
- **The combined candidate is a different tree:** the gate after S1–S5, plus S6 if D2. Earlier UI acceptance does not
  carry over to anything changed since, so the candidate is verified in its own right:
  1. **Changed-surface inventory.** `git diff --stat f3f08930..<candidate>` restricted to `app/` and `src/`, every file
     classified. The trial shows the backend and admin merges change no app file. Only the blocking client half (S6)
     and any later C commits would.
  2. **CI green at the candidate:** the pgTAP count predicted in advance, vitest, typecheck, lint, Deno.
  3. **The static client-read check (C4)** at the candidate against the production schema: the gate minus
     121/125/126, plus whatever XB1 adds, only if XB1 precedes distribution.
  4. **Native build of the candidate**, from a fresh install where the Stripe patch applies and matches upstream's
     hash, on "SN V3 393x852". The log is retained with its exit status.
  5. **Delta acceptance:**
     - B and E re-review every screen whose source changed since `f3f08930`.
     - The blocking states are new and need full acceptance: the unavailable listing and profile, the `BLOCKED_PARTY`
       refusal, "Blocked user", and the entry points.
     - E supplies the evidence; E does no backend work.
  6. **D verifies** the backend items and the C4 check.
  7. **Only then G2:** an EAS production build from exactly the candidate sha, owner-authorised.

## 6. Owner decisions

### 6.0 Consolidated list

1. **P0 (corrected):** `main` is already protected by a ruleset. Decide PR-1–PR-7 in MAIN_PROTECTION_PROPOSAL_20261005.md. **PR-3 (allowing a merge commit for S7) is needed before S7.** The closures are in the proposal's §3 table, with every head kept recoverable.
2. **D1:** merge 121, 125 and 126 into `main` as known-pending, targeted-apply-only files. Recommended: (c).
3. **D2:** blocking. Approve and include, with the 152 sequence in §5.2B. Recommended.
4. **D3:** assign the web wording fixes. Recommended: E, with D verifying.
5. **D4:** switch the web production branch to `main` after S7. Recommended.
6. **D5:** suspension and takedown. Remove the app's promise for this release, unless you approve the operator package
   now. Recommended.
7. **D6:** who works `/cases`, `/reports` and failed refunds, and how often (O-R3). Required before submission.
8. **D9:** fix the losing buyer's "Order complete" before any dispute is resolved. Recommended.
9. **D10:** defer server enforcement of the critical risk tier, accepting the stated consequence and mitigation (§6.2),
   or include it with a refresh scheduler. Recommended: defer.
10. **D8:** confirm the remaining deferrals (§6.1).
11. **At each production step:** the separate authorisations in §5.2 and §5.2B.

### 6.1 Detail

- **D1: 121, 125 and 126 at the `main` merge.**
  - **Options:**
    - (a) Apply them before S7. 121 needs PFA-18C.
    - (b) Remove them, and the pgTAP they couple to (184, 186, 189, 190, 193), from the line merged to `main`.
    - (c) Merge them as **known-pending, targeted-apply-only** files.
  - **Recommendation: (c).**
    - **Decisive (D):** under migrations-guard rule 4 (migrations-guard.yml:377-395), a migration added later must be
      above the latest of its scheme, and the numbered tip is 146. So (b) does not defer 121, 125 and 126; it makes
      them **unrevivable under their numbers**, returnable only as renamed timestamp files.
    - `main` then also equals the gate: the tested replay world, CI-green. The deployed code reaches `main` without a
      `main`-only tree that nobody has tested. The three stay deferred, each with its owner (121 and 125
    with B's signing track, 126 with D).
  - **Condition:** the fresh AUTODEPLOY confirmation at S7, and the release record listing them as the only files on
    `main` not in the ledger.
  - **Merge method (2026-10-05):** the current `main` ruleset allows only squash or rebase. **D1 holds under either a
    merge commit (PR-3) or a squash:** both leave `main` tree-equal to the gate. A squash loses only the lineage.
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
- **D7: repository safety** is precondition P0 in §5.1: a live hazard, not a scope choice.
- **D8: deferred list, confirmed as deferred:** 137, 138, 141, venue_api (venue production integration is separate),
  handle_new_user parity, F-PD-EXPIRY-1, the onboarding flag, the admin presentation work (analytics), and #89 (unless
  O-R3 needs it). The critical-tier guard has its own justification in §6.2.
- **D9: the losing buyer's "Order complete".** **Recommended:** include the copy fix with 151's timing, before any
  dispute is resolved. It needs one edge change and one migration.

### 6.2 D10: server enforcement of the critical risk tier (F-LISTING-CRITICAL-TIER-1), deferral justified

**What an older or modified client can do.**
- `can_create_listing` refuses `risk_tier = 'critical'` (013:50), but only the clients call it.
- The server's insert path checks own `seller_id`, `stripe_onboarding_complete` and `phone_verified()` (RLS 070:36-39),
  plus the 119 `BEFORE INSERT` guard, which refuses only `is_listing_blocked = true`.
- So a critical-tier seller who is **not admin-blocked** can create a listing with a direct PostgREST insert using their
  own session. An older client that skips `can_create_listing` would do the same.

**Server protections that already exist.**
- **An operator block is server-enforced** by the 119 guard, and is a payout HIGH signal (`SELLER_BLOCKED`).
- **Buyer-silent sales never auto-release for this tier.** The payout policy classifies `risk_tier = 'critical'` as HIGH
  → manual_review, "never auto-release, operator must act" (`_shared/payout-policy.ts`, `SELLER_RISK_TIER_CRITICAL`).
- **A buyer's report freezes the payout**, since disputed rows are excluded from every release path.
- **Payment is held on the platform** (separate charges and transfers) until a payout is recorded.

**What is not protected.** A buyer's **positive confirmation** releases the payout regardless of tier ("confirm-and-release
always releases absent a dispute", payout-policy header). A later chargeback then falls to the reversal path
(`flag_payout_reversal_required`).

**Why defer rather than add the guard now.**
- The tier is recomputed only by `get_auto_release_candidates`; there is no scheduler (FD:100).
- That recompute (039:161) runs **only for sellers already inside the auto-release candidate window**: `seller_sent`,
  `auto_release_at` past, no hold, not manual_review (D's addition A-1).
- So a seller whose sales are all buyer-confirmed may **never** have their tier recomputed. The one unprotected case
  (buyer confirms) is also the case that never triggers a refresh.
- So a guard would enforce a possibly stale value. It could refuse a seller whose tier has since healed, or miss one
  whose tier has since risen.
- The meaningful fix is **one package**: a refresh scheduler plus the guard.
- It is also a listing-restriction policy, which is the owner's call.

**Release consequence if deferred, stated plainly.** A critical-tier seller who is not admin-blocked can list by bypassing
the app. Their sales are protected on buyer silence (manual review) and on a buyer report (frozen payout), but **not**
when a buyer confirms receipt. Exposure is bounded to confirmed sales by such sellers before an operator blocks them.

**Mitigation available now, no new code:** the operator procedure (D6) includes blocking any seller who reaches the
critical tier. The block is server-enforced (119).

**Recommendation:** defer, with this consequence and mitigation accepted. Scheduler plus guard is the first post-release
package.

## 7. Freeze procedure (after implementation and the native review)

- **What to freeze, each as a full sha with its CI run and headSha:**
  - the combined candidate: the gate after S1–S5, and S6 if D2 (§5.3);
  - the console commit for X8: `ab3e17f` + the label cherry-picks, patch-identical to `004af0b0`/`789025f3`;
  - the web commit for X9;
  - the EAS source commit for X11, which equals the combined candidate.
- **D verifies** the plan against D's independent inventory (reconstruction at `7554d913`; the original `f740ab73` is lost), then each frozen package. The 150/151 package is `docs/release/packages/150_151_20261005/`.
- **E supplies** the frontend acceptance evidence:
  - G0 on the successor build;
  - the native-review record;
  - the static read check under C4;
  - the web-bar evidence.
  E does not take backend work.
- **Execution packages** (X2–X9) are written after the freeze, each with rollback, read-backs and D's pre-registered
  expectations, and each waits for the owner's authorisation.

## 8. Superseded PRs: where each one's changes went

**Method:** per PR,
- whether its head is an ancestor of the gate (`git merge-base --is-ancestor`);
- and, over the files the PR changes against its merge-base with its own base, a comparison of the PR-head blob with
  the gate blob.

**Recoverability:**
- Closing a PR keeps `refs/pull/<n>/head` on GitHub.
- **No branch is deleted.**
- Recommended before closing: an `archive/pr-<n>` tag at each head (a git write needing the owner's go).
- PRs into `main` are the P0 hazard. The rest are hygiene.

| PR | Head → base | Head in gate? | File comparison | Where its intent went / why superseded | Action |
|---|---|---|---|---|---|
| #54 | `fix/payments-reliability @a77d3686` → **main** | **yes** | 516 files: 454 same, 62 later gate edits | fully in the gate; reaches `main` via S7 | close after P0 |
| #43 | `chore/admin-relist-rpc @fba3b515` → **main** | no | its `20260902003623` blob **differs** from the gate's; the rollback is absent from the gate | version `20260902003623` is in production's pre-apply ledger (one of the 5 timestamped rows, SS:1393), and the gate carries a copy that CI replays. **Which copy matches production's applied body is not established** (the ledger records the version, not the file). Either way #43 is not the vehicle: merging it would put a second, divergent copy on `main`. Before S7, D compares the gate copy's function body with the recorded production baseline, where one exists | close after P0 |
| #87 | `fix/payout-fairness-v38-backport @f5e91e74` → **main** | no | enforce-transfer-expiry differs; its test is absent from the gate | a `main`-based hotfix, deployed as v39 on 09-22 (SS:1376), then superseded by the gate's v40/v41, which carry the fairness predicates ("FAIRNESS … owner item 1, 2026-09-19" in Phase 2b) | close after P0; keep the branch (the v39 source) |
| #11 | `repo/purge-obsolete-admin @eec7a717` → **main** | no | 48 changed files: 41 deletions, 7 modifications; **the gate still has all 41 deleted files** | **not incorporated**: an unreviewed docs purge made before the docs reorganisation | close as stale (not merged); a docs cleanup can be redone later against the current tree |
| #56 | `publish/ui-v2-integration @597533e1` → `release/payments-converged-rc` | yes | 183 files: 110 same, 72 later edits, 1 deleted later | fully in the gate | close |
| #58 | `fix/121-… @030a922b` → `admin/operating-console` | yes | 3/3 identical | 121 is in the gate, blob-identical (D1) | close |
| #62 | `fix/125-… @fc4f1130` → `admin/operating-console` | yes | 3/3 identical | 125 is in the gate, blob-identical (D1) | close |
| #63 | `fix/126-… @db2f95f1` → `release/convergence-135` | yes | 4 same; test 193 differs (the gate has the CI-safe version) | 126 is in the gate (D-INV-2) | close |
| #64 | `fix/l1-edge-coupling @5bcea692` → `fix/127-…` | yes | 1 same, 4 later gate edits | in the gate | close |
| #70 | `fix/132-pending-before-intent @74a43712` → the candidate | yes | 8 same, 3 later edits | 132 is in the gate and applied (MAN #8) | close |
| #9, #53, #57, #59, #60, #61 | dependabot bumps → **main** (not drafts) | no | no migration files | not superseded: routine dependency updates against `main`. Merging them now would move `main` off the release line | **keep open; do not merge before S7.** After the freeze, re-evaluate each against the release line through review (P0 then enforces review) |
| #52 | `feature/venue-native-and-product-v2 @9aed686c` → `phase2/consolidation` | no | 334 files: 264 same, 43 differ, **27 absent from the gate**, all records: B's PFA-18C execution records and `PHASE2_PRODUCTION_STATE_20260912.md` | **not purely superseded, and not a `main` hazard.** It is the venue/Phase-2 vehicle, and venue production integration is separate | **keep open**. Before any closure, copy the 27 records onto the records line (A) |
