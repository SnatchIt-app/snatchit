# Consolidated rollout plan — refund/payout safety package (A, 2026-09-20; updated 2026-09-21)

**Planning only.** Nothing here is authorised by this document: every merge, apply, deploy, schedule,
switch flip and production read beyond existing authority is a separate owner act. Prepared under the
owner's 2026-09-20 instruction; verification below is local + CI only.

## 1. Exact versions to release

| Piece | Branch @ head | PR | State |
|---|---|---|---|
| Migrations 143–146 + rollbacks + pgTAP 210–213 + `notify-report` `ops_alert` branch | `admin/146-alert-delivery` @ `70a4f613` | #86 (draft) | implemented, A-reviewed, CI green |
| Payout starvation fix (edge, `enforce-transfer-expiry` Phase 2b selection) | `fix/payout-retry-fairness` @ `36db0c36` | #83 (draft) | implemented, CI green |
| **Payout fix, v38 backport** (deployable against production today) | `fix/payout-fairness-v38-backport` @ `f5e91e74` (base `main`) | #87 (draft) | implemented 2026-09-21: RED {F1,F3,F4,F6} on unfixed v38 → 6/6 GREEN on the real handler; full suite 6 files / 122; typecheck 0 |
| Transfer screens (mobile client) | `fix/seller-deadline-copy` @ `131017a5` | #84 (draft) | implemented, CI green |
| Operator console: classify / obligations / acknowledge / delivery truth | `admin/refund-classification-console` @ `3dab1614` | none yet (§4) | implemented, A boundary review PASS, push-CI green |
| **Integration proof (this plan's evidence)** | `integration/refund-payout-round-v2` @ `e6ebd800` = `70a4f613` + `36db0c36` + `131017a5` | local only | A: replay RESET 0 · census 32\|108\|37\|38 · pgTAP **5455/5455** · typecheck 0 · vitest **126 files / 2485**. **Independently re-verified by D (2026-09-21):** migrations/rollbacks/notify-report blob-identical to the reviewed heads, last-definer function md5s intact (incl. `alert_fire` `d42f697b`), both switches seed false, D's own fresh replay **5455/5455** |

**Not in this package:** PR #81 (independent client fix, same lanes below apply), 138 (parked), 142 /
`amount_refunded_cents` (parked on the partial-refund policy, §9), C's `hold/seller-refund-recorded` screen (same).

## 2. Overlapping PRs — merge order and retargeting

All five PRs already target `release/production-gate-20260918`; no retargeting is needed.

1. **Merge #86 first.** Its head contains PR #85's head (`07a29403`) as an ancestor, so GitHub marks **#85
   merged automatically** — nothing lands twice.
2. **Close #82 unmerged** with a comment: its 143 migration and rollback are **file-identical** in #86
   (verified by blob hash); only its pgTAP 210 is an older revision, superseded by #86's. Merging #82 after
   #86 would be a no-op at best and a test regression at worst.
3. **Then merge #83 and #84** (either order; disjoint files — the cherry-pick and merge in the integration
   proof were both conflict-free).
4. **Nothing merges to `main` in this step.** Gate → production is §5, under AUTODEPLOY-1 and
   `docs/operations/DEPLOYMENT_PATHS.md`.

## 3. What the database rollout actually is (scope)

Production's ledger is **135 rows, nothing from 121 on** (`PRODUCTION_READINESS_PLAN_8f45e9b_20260918.md` L1);
143–146 therefore **join the existing pending set** and apply in pending-file order — after the numbered
121–142 files, before the timestamped ones — exactly the order every fresh replay and CI run has proven.
- **Recommended: this package rides the readiness plan's pending chain.** A cherry-picked "143–146 only onto
  production-now" is **not verified**: pending migrations between (e.g. 126's ops rewiring) sit under 144's
  feet in every tested order, and no rehearsal of the subset combination exists. I will build one only if you
  choose that route; until then treat the subset as unavailable, not merely unrecommended.
- **The one piece that can go ahead of the chain is the payout fix, as an edge-only backport** (§6): it needs
  no new database object.

## 4. Console branch — route and the actual deployment trigger

- Reviewed head `3dab1614`, based on the **live** console base `admin/operating-console` @ `562fda9a`; all 11
  files under `admin/`; boundary review PASS (the close-guard mirror is display-only and matches 144's guard
  read; the database refusal is always shown verbatim).
- **The deployment trigger is a commit reaching `admin/operating-console`** (push or merge) — Vercel deploys
  the console's production from that branch. **Opening a draft PR creates no commit on the base and does not
  deploy.** What a PR *can* do is build a **preview** of the head branch, subject to the Vercel project's
  settings — and the head branch is already pushed, so any branch-preview behaviour is already in effect.
- **Route:** D confirms in the Vercel dashboard that (a) preview deployments are access-protected and (b)
  preview env does not point write-capable credentials at production; then D opens a **draft, do-not-merge PR**
  (head → `admin/operating-console`) as the review surface. The merge is step §5.4 and only then deploys.
  (CI itself already ran green on the push — CI runs on every non-main push — so the PR is for review, not signal.)
- **Status 2026-09-21, final: the console PR stays unopened — the Vercel check is an OWNER item.** D's API token
  is refused for the project scope (403 on `get_project`/`filter_project_envs` for `snatchit-admin`,
  `prj_o17cASVVqqyGKPUtiklJRvAMVgNB`), and D correctly declined to substitute inference for the dashboard
  (AUTODEPLOY-1's own rule). What D holds, at its real strength: pushing `3dab1614` created **no**
  snatchit-admin deployment (current, empirical); D's 2026-09-08 deployment record says Preview branch-tracking
  was disabled and SSO protection `all_except_custom_domains` (12 days stale); the Preview-scope env vars have
  **never been checked by anyone**. **Owner's one-minute check — Vercel → snatchit-admin → Settings:**
  (1) Deployment Protection: Vercel Authentication ON for Preview? (2) Environments → Preview: Branch Tracking
  still disabled? (3) Environment Variables, Preview scope: anything write-capable pointing at the production
  Supabase project? Only (3) makes a preview dangerous on its own; (1)/(2) govern exposure. After a clean check,
  D opens the draft PR.

## 5. Rollout sequence (each numbered step separately owner-authorised)

0. **Pre-checks (read-only, existing authority class):** fresh AUTODEPLOY-1 dashboard check on merge day;
   production md5 check that `ops.job_health`/`ops.detect_jobs`/`ops.alert_fire` bodies equal 116/117 (the
   registry carries the expected values); read `actions_enabled`'s production value; read `ADMIN_EMAIL` on the
   deployed function config. The Stripe webhook dashboard check (§1 of the refund plan) remains open — it
   affects how much R2/R4 detection is worth, not the mechanics below.
1. **Repo merges into the gate** (§2). Effect: none outside the repo.
2. **Database apply** of the pending chain through 146 in ledger order, per the readiness plan's method
   (file + ledger row + read-back per migration: md5s, grants, census). Switches land **OFF**:
   `refund_resolution_detector_enabled=false`, `alert_delivery_enabled=false`. What changes behaviour at this
   step: the jobs page reads bounded history (no more 8 s timeout; "last run" = newest run, §8), the detector
   tick stops causing ~99 % of disk block reads, and **145's job-not-running detection goes live by design** —
   it opens console-visible cases/alerts for genuinely dead jobs (new jobs get a first-seen grace); nothing
   pages anyone.
3. **Edge deploys, after the DB (migrate-then-functions is mandatory):** `notify-report` (additive `ops_alert`
   branch) and `enforce-transfer-expiry` (the RC body, which includes the payout fix — superseding the §6
   backport if that shipped earlier). Prerequisite for the payout fix going live either way: **§6.3, the
   backlog count.**
4. **Console deploy:** merge the console PR → Vercel production. The console tolerates pre-146 rows (parser
   nulls), so order vs step 2 is safe either way; after is cleaner.
5. **Verification window (read-only):** jobs page loads; last-run values sane; detector run duration and block
   reads down; `ops.alert` rows carry delivery columns (all null); edge logs clean; one full cron cycle observed.
6. **Activation — separate authorisations, one at a time, in this order:**
   a. `refund_resolution_detector_enabled=true` (audited `setting_set`) — R1–R4 cases start opening, with a
      **named assignee** agreed before the flip (closure requires classification + settled obligations).
   b. `alert_delivery_enabled=true` **and** schedule `ops.dispatch_alerts` (new cron entry — a schedule change,
      owner-gated). Recommended: every 5 minutes, `p_limit` 20 (§8).

## 6. Payout fix against production's current database — exact prerequisites

**A green release-branch build proves nothing here**: between deployed v38 (= `origin/main`, byte-verified
2026-09-19) and the fix branch sit **2,043 inserted lines** of RC edge code (payout attempt protocol, Phase 0
settlement reconciliation, the 134 processing arm). Two routes:

- **Route A — with the package (step 5.3):** deploy the RC function after the full pending chain is applied.
  Its assumptions are the chain's; the integration proof covers the combination.
- **Route B — ahead of the package (recommended if the release date is not near):** a **backport of only the
  Phase 2b selection change onto the v38 source**. Prerequisites, in order:
  1. Source = `origin/main`'s `enforce-transfer-expiry` (re-verify byte-equality with the deployed v38 at build
     time); the diff vs v38 must be the Phase 2b(a)+(b) selection alone.
  2. DB dependencies of the fixed query, **verified today on the production-ledger-order replay**
     (`a8f_prodshape_rehears`): `transfers.payment_id → payments` FK exists (the `payments!inner` embed needs
     it); all 9 transfers columns + `disputed_at` present; the status check admits `auto_released` and
     `buyer_confirmed`. ✓ all present.
  3. **The backlog count (owner authorisation still open):** deploying the fix makes the starved eligible
     payouts **pay out on the next 2-minute tick**. Count them first so the money that will move is known
     before it moves, not after.
  4. Local: the F1–F6 fairness tests ported to the v38 handler, RED on v38, green on the backport; the
     PostgREST probe re-run against the prod-shape DB; Deno type-check; draft do-not-merge PR, CI green.
  5. Owner deploys the function (v38 → v39); reads one sweep tick in the edge logs.
  6. Rollback: redeploy the recorded v38 source (byte-copy kept); no migration, no data.
  **Route B is built: PR #87 @ `f5e91e74`** (2026-09-21). Steps 1–4 above are done and recorded in the PR; steps 3 (backlog count), 5 and 6 remain owner acts. The release-merge conflict on this one file resolves by taking the RC side, which already contains the fix.

## 7. 144 "unclosable cases" — reconciled

Applying 144 creates **no** cases: the detector is skipped for **every** trigger, manual included, while
`refund_resolution_detector_enabled` is false (verified in the migration body), and the switch is seeded false.
Even once cases exist, the classify/obligation/close RPCs are in 144 itself and callable by role
(admin/risk/support) — D's "unclosable by anyone" was precisely "no console control existed", which
`3dab1614` fixes. The enforced sequencing is simply: **apply 144 (off) → deploy console → flip the switch** —
the order §5 already has.

## 8. Recommendations (decided here, not returned)

- **Jobs-page "last run" (#82/#86 behaviour change): accept.** The old pick pins a job's oldest startup-timeout
  row as "last run" forever, hiding newer runs — and the page has been timing out since 2026-09-08 anyway, so
  there is no working behaviour to preserve. "Newest run" is what an operator means.
- **Alert delivery policy: deliver every firing alert kind** (p1 cases, job_failure, job_not_running — the set
  is already curated and incident semantics prevent storms; R5 pins it). Cadence 5 minutes, batch 20.
  **Recipients:** push to every `public.admin_users` row (both founders) + email to `ADMIN_EMAIL`
  (deployed default `support@snatchitapp.com` — confirm the env at deploy). **Acknowledgement:** whichever
  founder takes it acknowledges on the console System page (`ops.alert_ack`, aal2, audited, with note);
  acknowledging is not resolving. **Retry exhaustion:** after 5 unconfirmed attempts an alert is counted
  `given_up` — it stays firing on the System page with its last error, is never silently dropped, and a genuine
  recurrence (recovered → fires again) opens a new incident with a fresh attempt budget.

## 9. Partial-refund business policy — kept separate

**Nothing in this rollout depends on it.** It gates only the follow-on package: recording refund amounts at the
source (142's column + a webhook change), any automated payout for partially-refunded orders (case B), automated
remainder refunds (case C), R3 resolution tooling beyond "escalate", and C's held refund-recorded screen.
Until then, R-cases are classified and resolved by support per the refund resolution plan.

## 10. History preservation, rollback and disable

- **Disable before rollback, always:** both switches off restores pre-package behaviour without touching data.
- 143 rollback: restores 116/117 bodies verbatim (md5-verified). 145: restores 143's `detect_jobs`; cases kept.
- 144 rollback: **never deletes case history** — with any refund-resolution history present it runs as a
  DISABLE (bodies restored, detector dropped, vocabulary kept because the rows need it).
- 146 rollback: alert rows kept; **delivery/acknowledgement bookkeeping is discarded** — the rollback says so
  and `ops.audit`'s `alert.acknowledged` rows (the durable record a person saw it) survive; copy them out first
  if wanted.
- Payout fix rollback: redeploy v38 (Route B) / previous function version (Route A). Console rollback: Vercel
  redeploy of the previous production deployment.

## 11. State of every piece (implemented ≠ integrated ≠ deployed ≠ operational)

| Piece | Implemented | Integrated | Deployed | Operational |
|---|---|---|---|---|
| 143 Disk-IO bounded reads | ✓ | ✓ (`e6ebd800`) | — | — |
| 144 detector + closure rules | ✓ | ✓ | — | — (switch off even after deploy) |
| 145 job-not-running | ✓ | ✓ | — | — (live on apply, console-only) |
| 146 alert delivery + ack | ✓ | ✓ | — | — (switch + schedule both absent) |
| Payout starvation fix | ✓ | ✓ | — | — (production still starves payouts) |
| Payout fix v38 backport (#87) | ✓ | ✓ (applies to deployed v38 directly) | — | — |
| notify-report `ops_alert` | ✓ | ✓ | — | — |
| Transfer screens (client) | ✓ | ✓ | — (rides next authorised app build) | — |
| Operator console controls | ✓ | ✓ (own base) | — | — (and never exercised against a live DB) |

## 12. App-side consolidation (C, 2026-09-21, verified by C on GitHub; recorded at C's backlog 3af30759)

- App delta vs Build 22 (`05d85732`) = exactly **#81 ∪ #84, five files, disjoint**; no other branch in the
  package changes app code. Both PRs double-PASSed (A + D), CI green, mergeable, no open review threads.
- C re-confirmed every app invariant against the chain: nothing under `ops.*` reaches a consumer screen; the
  obligation vocabulary never surfaces in the app; refund copy stays amount-gated; transfer reads fail closed.
- **Optional owner verification (C's one proposed device check, read-only, no fixture writes):** on the
  candidate build, open sandbox order D6's Send screen as the seller — expected: "Send window has passed —
  checking this order's status", then the server-checked wording. Every other device-observable delta rests on
  the automated evidence (RED-first tests; 31 mutants at #84, 18 at #81) and is stated as such.
- C's held screen (`hold/seller-refund-recorded` @ `938423e0`) stays out, pending the partial-refund policy (§9).
