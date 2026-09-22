# Rollout plan v3 — refund/payout safety package and the production apply manifest (A; v1 2026-09-20, v3 2026-09-21)

**Planning only.** Nothing here is authorised by this document: every merge, apply, deploy, schedule, switch
flip and production read beyond existing authority is a separate owner act. Verification is local + CI only.
**v3 reconciles this plan with `MIGRATION_NUMBER_REGISTRY.md`, `PRODUCTION_READINESS_PLAN_8f45e9b_20260918.md`
and current GitHub state** on the owner's seven-point instruction (2026-09-21). Superseded statements are kept
in §14 and labelled; every fact below was re-read today, not carried.

## 0. Corrections in this revision (what v1/v2 got wrong)

| # | v1/v2 said | v3 says | Evidence |
|---|---|---|---|
| 1 | "143–146 ride the pending chain" while §1 listed 142 as *parked* | The database rollout is the **whole pending set of 27 files** (§3); 142 is **in it** — merged into the gate, not parked. Only 121 (deferred), 125/126 (optional, owner D-1) and 137/138/141 (not in the tree) sit outside the required set | gate tree at `26e9db09` = 162 files = production's 135 rows + 27 pending; `gh pr view 77` |
| 2 | "142 / #77: draft awaiting attestation" (registry) | **PR #77 MERGED into `release/production-gate-20260918` on 2026-09-19** (merge commit `e191cbfa`, the gate head); file blob identical to the PR head. Production apply: **NO** | `gh pr view 77`; blob compare (§4) |
| 3 | #86 head `ec4f0600` (table) vs `26e9db09` (registry) | **`26e9db09`** everywhere. Every commit after the reviewed `cf804036` is docs/script-only (A verified each against the ref: nothing under `supabase/`), so the integration proof `e6ebd800` (built on `70a4f613`) still covers the executable content exactly | `git diff --name-only 70a4f613..26e9db09 -- supabase/` = empty |
| 4 | "both switches off restores pre-package behaviour" | **False.** 143 and 145 change behaviour on apply with **no switch**; 146's recurrence semantics and columns are live on apply. Each switch disables exactly one thing (§8) | 143/145/146 bodies; 115's `detectors_enabled` |
| 5 | "Preview env vars have never been checked by anyone" | **Wrong.** They were enumerated and the privileged key removed on **2026-09-08** (D's deployment record). What is true: that check is 13 days old, and the Preview scope carries the **production Supabase URL + anon key**, so any reachable preview is a live production console for an authenticated operator — the risk is authenticated write access, not a secret key (§5) | `docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md` |
| 6 | "merge of the console PR = production deploy" | **Not by itself.** A push/merge to `admin/operating-console` creates a deployment that Vercel **cancels unless the commit SHA equals the Ignored-Build-Step pin**. The actual release act is updating that pin (or `vercel deploy --prod` from a clean checkout) — an owner act in either form (§5) | deployment record, addendum 2 |
| 8 | (v3 first draft) "`detectors_enabled=false` halts all detectors"; "Preview points at production" stated as fact | Global/per-job switches halt **scheduled** runs only; manual console runs bypass them (§8). The production-URL claim is an inference from variable names, now a checklist question (§5). Both from D's independent review of v3 | 117/144 `run_job` body; deployment record line 79 |
| 7 | §6: "steps 1–4 done … steps 3, 5, 6 remain" (self-contradictory) | Done: 1 (historical byte-verification, 2026-09-19), 2, 4. **Outstanding: 3 (backlog count AND value), 5 (deploy), 6 (rollback readiness), and a fresh byte re-verification of deployed v38 at deploy time** (§7) | — |

## 1. Exact reviewed versions

| Piece | Branch @ head | PR | Review / CI |
|---|---|---|---|
| Migrations 143–146 + rollbacks + pgTAP 210–213 + `notify-report` `ops_alert` branch | `admin/146-alert-delivery` @ **`3f579975`** (executable content = the reviewed `cf804036`; every later commit docs/local-script only, each A-verified against the ref: nothing under `supabase/`) | #86 draft | A PASS (two independent replays); CI green at `6f604efe`, `cf804036`, `70a4f613`, `26e9db09` (5461) |
| Chain 143+144+145 | `admin/chain-143-144-145` @ `07a29403` — **ancestor of #86's head** | #85 draft | A PASS; CI green (92/5425). Contained in #86 |
| 143 alone | `fix/143-ops-cron-history-bounded-reads` @ `6b700aed` — migration + rollback **blob-identical** to #86; pgTAP 210 an older revision | #82 draft | A PASS; CI green. Superseded by #86 |
| Payout starvation fix (RC edge) | `fix/payout-retry-fairness` @ `36db0c36` | #83 draft | CI green; F1–F6 on the real handler |
| **Payout fix, v38 backport** | `fix/payout-fairness-v38-backport` @ `f5e91e74` (base `main` = deployed v38) | #87 draft | RED {F1,F3,F4,F6} → 6/6; suite 6/122; CI green incl. security jobs |
| Transfer screens (app) | `fix/seller-deadline-copy` @ `131017a5` | #84 draft | A + D PASS; CI green |
| Checkout escrow line (app) | `fix/checkout-escrow-note-unknown` @ `19b6fc2b` | #81 draft | A + D PASS; CI green |
| Operator console | `admin/refund-classification-console` @ `3dab1614` (base `admin/operating-console` `562fda9a`) | none (§5) | A boundary PASS; D full evidence; push-CI green |
| 142 column | in the gate: `142_payments_amount_refunded_cents.sql` @ `e191cbfa` (= PR #77 head `e3c03d51`, blob-identical) | #77 **merged** | A; CI 89/5314 |
| Integration proof | `integration/refund-payout-round-v2` @ `e6ebd800` = `70a4f613` + `36db0c36` + `131017a5` | local | A: replay 0, census 32\|108\|37\|38, pgTAP 5455/5455, tsc 0, vitest 126/2485. **D independently:** blob-identity, last-definer md5s, switches false, 5455/5455 |

## 2. Repository merge order (re-verified at today's heads)

Into `release/production-gate-20260918`, nothing to `main`:
1. **#86** — contains #85's head as an ancestor (`git merge-base --is-ancestor 07a29403 26e9db09`: yes) → #85 auto-merges.
2. **Close #82 unmerged** — its 143 migration and rollback are blob-identical to #86's; only its 210 test is older.
3. **#83**, **#84** (disjoint files; cherry-pick and merge were conflict-free in `e6ebd800`). #81 likewise (client, disjoint).
Repo merges have no effect outside the repository.

## 3. Production apply manifest — the whole pending set, not "the four-migration package"

Production: **135 ledger rows, nothing from 121 on** (readiness plan L1; nothing applied since 2026-09-12). The gate
tree holds exactly **27 more files**. Order = file order within the pending set (numbered before timestamped),
the order every fresh replay and CI run proves. `R` = REQUIRED by the candidate (readiness plan §2a), `P` =
PARITY (production already has the end state; apply aligns the ledger), `O` = OPTIONAL track (owner D-1),
`X` = DEFERRED, `S` = this safety package.

| # | Migration | Class | Depends on / must precede | Review status | Outstanding approval |
|---|---|---|---|---|---|
| 1 | `123` transfers↔profiles FK parity | P | must be **proven a no-op** on production first ([L2]) | rehearsed; applied to sandbox | production apply |
| 2 | `124` bids↔profiles FK parity | P | same + fresh orphan count ([L10]) | rehearsed P1–P6 | production apply |
| — | `125` scanning-contract correction | O | none in this set | B's; PR #62 open draft; file in the gate tree | **owner D-1** (ride or wait) |
| — | `126` ops refund exactness | O | redefines the live console's figures (`daily_summary`/`money_overview`/`refresh_metrics`) | PR #63 open draft (base `release/convergence-135`); **file in the gate tree, blob-identical to #63's head** | **owner D-1**; D review |
| 3 | `127` release guards L1/L2 | R | RC edges use `release_reservation_for_payment` | three review rounds → `6383b8f` | apply |
| 4 | `128` register_push_token secure rebind | R | first of the 128 → 131 → 135 redefinition chain | contract v2 frozen; D pass 3 no findings | apply; **O-3** (owner) |
| 5 | `129` revoke_push_token | R | — | D: no findings | apply |
| 6 | `130` checkout supersede claim | R | precedes 132 | A approved; PR #65/#67 | apply |
| 7 | `131` session-bound push bindings | R | after 128; before 135 | D PASS; **applied on sandbox** | apply |
| 8 | `132` checkout group claim | R | after 130 | D PASS; **applied on sandbox** | apply |
| 9 | `133` edge base URL from Vault | R | **Vault `project_url` must exist in production BEFORE apply (owner ceremony)**; precedes 135; rewrites the live signing monitor 099 and the 033–035 triggers | D PASS; **applied on sandbox**; **B's sign-off on the 099/033–035 rewrite still required** | apply; ceremony; B sign-off |
| 10 | `135` push proof of possession | R | after 133 (posts via `project_url`); last of the register_push_token chain | D PASS; **applied on sandbox** | apply; **D-2** (installed clients predating b2 may stop registering tokens) |
| 11 | `136` security notices read | R | — | A; in the candidate tree | apply |
| 12 | `139` notify-report delivery claims | R | edge `notify-report` | B; D PASS | apply |
| 13 | `140` mark_transfer_sent → jsonb, attach_transfer_evidence | R | client reads `transitioned`/`already_sent` | B; D PASS | apply |
| 14 | `142` payments.amount_refunded_cents (nullable, never backfilled) | R (app) | lands before `20260906120000`, whose identical DDL is idempotent (replay-proven) | **merged (#77)**; CI 89/5314 | apply (go/no-go §12.8) |
| 15 | `143` bounded cron-history reads | S | replaces 116/117 bodies — pre-apply md5 check that production has 116/117 | A PASS ×2 | apply; **jobs-page last-run change (§10 recommends accept)** |
| 16 | `144` refund-resolution detector + closure rules | S | order-independent (extends constraint lists); switch seeded false | A PASS ×2 | apply |
| 17 | `145` job-not-running detection | S | **after 143** (built on its body); **live on apply, no switch** | A PASS ×2 | apply |
| 18 | `146` alert delivery + ack | S | after 117 (last definer of `alert_fire`); switch seeded false; nothing scheduled | A PASS ×2 | apply |
| 19 | `20260906100000` checkout reservation authority | R | RC unit; redefines `complete_auction_payment`, `mark_listing_sold`, `reserve_buy_now` | payments RC (PR #54 line) | apply |
| 20 | `20260906110000` settle_verified_payment, get_unsettled_payments | R | precedes `20260916000000` | payments RC | apply |
| 21 | `20260906120000` payout attempts, append-only refunds | R | **RC edges only** (`_shared`, `stripe-webhook`, `enforce-transfer-expiry`, `delete-account`). **Not the app:** the readiness plan §2a lists `setupDecision.ts` (`record_payment_refund`) as a client caller, but that name occurs only in a comment (C, verified by A: 0 non-comment hits under `src/`, `app/`) | payments RC | apply |
| 22 | `20260906130000` deletion sweep live-rail obligations | R | RC unit | payments RC | apply |
| 23 | `20260909000000` get_my_tickets | R | Tickets tab ships unconditionally | reviewed (go/no-go) | apply |
| 24 | `20260916000000` processing sweep arm | R | after `20260906110000`; edge `enforce-transfer-expiry` (RC body) | D PASS; **applied on sandbox** | apply |
| X | `121` manifest signing context STRICT | X | — | B; PR #58 open | **only under `AUTHORIZE PFA-18C MIGRATION 121`** — excluded from this apply |
| — | `137`, `138`, `141` | not in the tree | — | 137/141 allocated (A); 138 PARKED (D) | none — outside this release |

**What the readiness plan still requires before this apply, unchanged and not done by this package:** the
production-order rehearsal of exactly the pending set (production applied 110–114 *after* 115–120, so
LC_ALL=C replay is not the production order); the A+B compatibility review of bodies that change under the
deployed legacy edges and the installed app during the migrate→deploy window; B's sign-off on 133; owner
decisions D-1, D-2, D-3 and O-3; reads [L1]–[L11]. **Honest consequence:** 143–146 reach production only with
this whole set — or through a **subset apply (143–146 onto production-now) that does not exist as a verified
artefact today.** A can build that rehearsal on request; it is not offered as an option below because it has
not been run.

## 4. Migration 142 — repository status, production status, and who needs it

- **Repository:** PR #77 **merged** into the release gate 2026-09-19 (`e191cbfa`); the registry's "draft awaiting
  attestation" was stale and is corrected.
- **Production:** not applied (ledger unchanged since 2026-09-12).
- **Three different things, kept apart:**
  1. **The nullable column** — required by the **app release path** only (go/no-go §12.8, A′ = `142` + `140` +
     `20260909000000`, then an app build): the candidate's checkout selects `payments.amount_refunded_cents`, and
     without the column that read fails silently. It carries no writer, trigger, grant or index.
  2. **Refund-amount writers** (a `stripe-webhook` change recording the amount) — **not built**, parked on the
     partial-refund policy (§11).
  3. **The partial-refund business policy** — separate, §11.
- **Which release paths require 142:** the app build path (A′) — yes. The refund/payout DB safety package
  (143–146) — **no**. The v38 payout backport (#87) — **no**. The payments RC edges — no (they get the same
  column from `20260906120000`).

## 5. Console — Vercel evidence reconciled, deployment trigger corrected, one checklist

**Historical (2026-09-08, D's deployment record, dashboard-read then):** `SUPABASE_SERVICE_ROLE_KEY` removed
from Development/Preview/Production; no `ADMIN_SECRET*` anywhere; every scope carries only
`NEXT_PUBLIC_SUPABASE_URL` + `NEXT_PUBLIC_SUPABASE_ANON_KEY` (+ site URL/env label); Preview **Branch Tracking
disabled** (probe-push verified: no deployment created); deployment protection `ssoProtection =
all_except_custom_domains` (old deployment URLs 302 → Vercel SSO); Ignored Build Step pinned to one SHA.
**Current (2026-09-20/21, empirical):** pushing `3dab1614` created **no** snatchit-admin deployment. **Not
current:** any dashboard reading — D's token is refused for the project scope (403), and a 13-day-old reading is
not evidence of today's setting.

**What the risk actually is.** The console holds no privileged key (repo: `admin/src/lib/supabase/server.ts`
uses the anon key + the operator's cookie). A preview therefore cannot act as service-role — but the Preview scope carries
`NEXT_PUBLIC_SUPABASE_URL` + anon key, and the record lists variable **names**, not values. That it points at the
**production** project is a strong inference (one Supabase project exists; there is no console staging project;
`ENV_LABEL` is only a label), **not a recorded reading** — checklist item 3 asks for the value. If it is
production, **a reachable preview is a fully functional production console for anyone who can sign in as an
operator** (role + aal2 gates still apply), and item 1 is load-bearing. Exposure, not key leakage, is what the
settings govern.

**Deployment trigger, corrected.** Vercel's production branch is `admin/operating-console`. A push or merge to it
creates a production-target deployment that the **Ignored Build Step cancels unless the commit SHA equals the
pin**. So: a draft PR deploys nothing; a merge alone deploys nothing (canceled build); the release act is **either
updating the pinned SHA and redeploying, or `vercel deploy --prod` from a clean checkout of the approved
commit** — an owner act in both forms.

**Route:** the draft do-not-merge PR (head `3dab1614` → base `admin/operating-console`) is safe to open as a review
surface once the checklist is clean; D opens it with the header: *"DO NOT MERGE — review surface only. Merging
does not itself deploy (canceled build unless the SHA matches the Ignored-Build-Step pin); the release act is the
pin update or `vercel --prod`, both owner acts."* **Owner checklist (Vercel → snatchit-admin,
`prj_o17cASVVqqyGKPUtiklJRvAMVgNB`), one pass:**
1. Settings → Deployment Protection: previews require Vercel Authentication / SSO (`all_except_custom_domains`
   or stricter)?
2. Settings → Environments → Preview: Branch Tracking still **disabled**?
3. Settings → Environment Variables, Preview scope: still exactly `NEXT_PUBLIC_SUPABASE_URL`,
   `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_ENV_LABEL` — **no** service-role key,
   **no** `ADMIN_SECRET*`? **And read the value of `NEXT_PUBLIC_SUPABASE_URL`** (a public-class value): is it the
   production project (`hqycwntpfoztoinemqns`)? If yes, item 1 is what keeps previews from being a live
   production console.
4. Settings → Build and Deployment → Ignored Build Step: which SHA is pinned? (Tells you whether a future merge
   could build.)

## 6. Rollout sequence — seven distinct acts, each separately authorised

| Step | Act | Effect | Prerequisite |
|---|---|---|---|
| 0 | Pre-checks (read-only; each a production read under a then-current authorisation) | none | AUTODEPLOY-1 fresh dashboard check; production md5s of 116/117 bodies; `actions_enabled` value; notify-report channel config (`EMAIL_ENABLED`, `RESEND_API_KEY` presence, `ADMIN_EMAIL`); admin push-token count; readiness-plan reads [L1]–[L11]; Stripe webhook dashboard check |
| 1 | **Repository merge** (§2) | none outside git | CI green (it is) |
| 2 | **Database apply** of §3's manifest, ledger order, file + ledger row + read-back each | 143: jobs page reads bounded history (works again; "last run" = newest run); detector tick stops ~99 % of block reads. **145: job-not-running detection live on the first tick** (console-visible cases/alerts; new jobs get first-seen grace). 144: vocabulary + closure guard installed, **no cases** (switch off). 146: columns + recurrence semantics + `alert_ack` RPC installed, **nothing sent**. Plus every RC/app migration's own effect (readiness plan §3: bodies change under the deployed legacy edges during the window) | readiness-plan prerequisites (§3 tail); Vault `project_url` ceremony before 133 |
| 3 | **Edge deploy**, after the DB (migrate-then-functions) | `notify-report` gains the `ops_alert` branch; `enforce-transfer-expiry` RC body (contains the payout fix → **starved backlog pays on its first tick**); the other RC edges | backlog count + value (§7); deployed-source byte re-verification |
| 4 | **Console deploy** (pin update or CLI `--prod`) | operators can classify, record obligations, acknowledge | §5 checklist; console PR reviewed |
| 5 | **Verification window** (read-only) | — | one full cron cycle observed; jobs page; alert rows with null delivery columns; logs clean |
| 6a | **Recipient verification** | — | working push tokens for admins **or** email trio configured (notify-report counts a delivery only on push-success/email-sent; email defaults **off**) |
| 6b | **Detector activation**: `refund_resolution_detector_enabled=true` (audited `setting_set`) | R1–R4 cases open; closable only via classification + settled obligations through the console | named assignee; console deployed (RPC availability alone is not an operator workflow) |
| 6c | **Dispatcher scheduling + delivery flip**: cron entry for `ops.dispatch_alerts` (5 min, batch 20) + `alert_delivery_enabled=true` | alerts reach `public.admin_users` by push and `ADMIN_EMAIL` by email; unconfirmed deliveries retry ×5 then stay visibly `given_up` | 6a |

## 7. Option B — the narrow v38 payout backport (#87), a separate approval

Deploys **one edge function** on the deployed source; no migration, no schedule. Prerequisites, status corrected:

| # | Prerequisite | Status |
|---|---|---|
| 1 | Source = `origin/main`'s function, byte-equal to deployed v38 | **historical**: byte-verified 2026-09-19. **A fresh byte re-verification at deploy time is required** (a production read) |
| 2 | DB dependencies of the fixed query on production's shape (FK, columns, status domain) | **done** 2026-09-21 on the production-ledger-order replay |
| 3 | **Backlog count AND value** — the starved eligible payouts that will **pay out on the next scheduled tick after deploy** | **OUTSTANDING** — needs its own read authorisation; do not deploy before it is known |
| 4 | RED→GREEN on the real handler; PostgREST probe; draft PR; CI | **done** (`f5e91e74`, #87 green) |
| 5 | Deploy v38 → v39; read one sweep tick | owner act |
| 6 | Rollback readiness: v38 byte copy = `origin/main` (re-verified in 1) | ready once 1 is re-run |

**Effect on deploy:** money moves — every payout the defect was starving is released on the first 2-minute tick.
That is the intended fix, and it is why 3 precedes 5. The RC function (Option A, step 3 of §6) supersedes this
file later; the one predictable merge conflict resolves by taking the RC side, which already contains the fix.

## 8. Disable vs rollback — exactly what each switch does

| Migration | Switch | What the switch disables | What stays active regardless | Undo requires |
|---|---|---|---|---|
| 143 | **none** | — | bounded reads; "last run" = newest run | **rollback** (restores 116/117 verbatim — and the Disk IO reads with them) |
| 144 | `refund_resolution_detector_enabled` (seeded false) | only the refund-resolution detector (every trigger, manual included → no cases) | the widened vocabulary; the closure guard on refund-resolution cases (inert until such cases exist); the classify/obligation action types | rollback = **DISABLE path** when history exists: bodies restored, detector dropped, vocabulary kept, **no case/event deleted**; re-apply recovers with history intact (battery B2) |
| 145 | **none dedicated** | — | job-not-running detection on every scheduled tick. **No switch stops it against a manual run:** all three of `run_job`'s skip rules — global `detectors_enabled`, per-job `job_state.enabled` and an active `backoff_until` — sit inside `if p_trigger <> 'manual'` (117 lines 1001–1009), and the console's "Run job now" (`job_retry` → `run_job(…, 'manual')`) skips that preamble wholesale (D verified on a replay: cron → skipped `detectors_disabled`; manual → succeeded, scanned). 144's switch is different in kind, not just strength: it is checked inside the detector body, so it refuses every trigger including manual | **rollback** (restores 143's `detect_jobs`; cases kept — 145's open cases then auto-resolve as "condition no longer detected" (D executed this: row present with both events, alert recovered), which is history, not deletion — **though the closed case keeps its "not running" title, so post-rollback history reads as if the jobs recovered; they did not, the detector stopped looking**) |
| 146 | `alert_delivery_enabled` (seeded false) | only `dispatch_alerts` (posting). Scheduling is a separate cron entry that must also not exist | the nine columns; `alert_fire`'s new-incident semantics (`incident_seq` bumps on recovered→firing); `alert_ack` RPC | rollback restores 117's `alert_fire`, drops the four functions and nine columns; **alert rows kept; delivery/acknowledgement bookkeeping and the incident counter are discarded** — `ops.audit` `alert.acknowledged` rows survive; copy them first if wanted |

"Both switches off" therefore restores **only** case creation by the refund detector and alert posting. It does
not undo 143, 145, the vocabulary, the recurrence semantics or the columns. The disable/recovery battery
(`scripts/local/rollback_battery_143_146.sh`, D; run independently by A: ALL PASS) proves the rollback paths
above, including that no case history is deleted.

## 9. 144 "unclosable cases" — reconciled (unchanged)

Applying 144 creates no cases while the switch is false — for every trigger, manual included (migration body;
D's 211 G4 holds a fixture that *would* open a case, so the zero is witnessed). The classify/obligation/close
RPCs exist from 144 and return exactly the console's default roles (D, verified against the database);
**RPC availability is not an operator workflow** — the console branch `3dab1614` supplies the controls, and
before 144/146 are applied it degrades to "RPC not available yet" rather than crashing. Sequence: apply (off) →
console → flip.

## 10. Recommendations (decided here, not returned)

- **Jobs-page "last run": accept 143's newest-run semantics.** The old pick pins a job's oldest startup-timeout
  row forever, and the page has been timing out since 2026-09-08 — there is no working behaviour to preserve.
- **Alert policy:** deliver every firing kind (p1 case, job_failure, job_not_running); dispatch every 5 minutes,
  batch 20; recipients = every `public.admin_users` row by push + `ADMIN_EMAIL` by email; acknowledgement on the
  console System page (`ops.alert_ack`, aal2, audited) by whichever founder takes it — acknowledging ≠ resolving;
  after 5 unconfirmed attempts an alert is `given_up`: still firing, still visible with its last error, never
  dropped; a genuine recurrence opens a new incident with a fresh budget.

## 11. Partial-refund business policy — separate

Gates nothing in §3, §6 or §7. Gates the follow-on: refund-amount writers (webhook), automated B/C handling, R3
tooling beyond "escalate", C's held `hold/seller-refund-recorded` screen.

## 12. State of every piece

| Piece | Implemented | Integrated | Deployed | Operational |
|---|---|---|---|---|
| 143 / 144 / 145 / 146 | ✓ | ✓ (`e6ebd800`, two independent runs) | — | — (145 would be live on apply; 144/146 switch-gated) |
| Payout fix (RC) / v38 backport #87 | ✓ | ✓ | — | — (production still starves payouts) |
| notify-report `ops_alert` | ✓ | ✓ | — | — |
| App (#81, #84) | ✓ | ✓ | — (rides the app build; needs 142/140/20260909 applied first) | — |
| Console controls | ✓ | ✓ (own base) | — | — (never exercised against a live DB) |
| 142 column | ✓ | ✓ (merged in the gate) | — | — |

## 13. App-side dependencies (C confirmed 2026-09-21 by grep/diff at the heads; two corrections accepted, both verified by A)

- App delta vs Build 22 = exactly #81 ∪ #84, five files, disjoint. **#81 adds no read, rpc or invoke. #84 adds
  exactly one column to an existing read** — `payout_released_at` on the buyer's transfers select
  (`app/transfer/receive/[id].tsx`), a column production already has and Build 22's send screen already
  selected — so **no new pending-migration dependency**, stated precisely rather than as "no read change".
- **What the candidate app calls, and how it behaves against production's current schema** (object missing):
  - **fail-SOFT by design (quiet degradation, no user-facing claim):** 128 `register_push_token` + the challenge
    pair (missing → `rpc_missing` → legacy method); 129 `revoke_push_token` / `revoke_all_push_bindings`
    (a failed revoke is reported; sign-out success never faked); 131 (no distinct app call — server-side
    semantics of the 128 chain); 135 (the same challenge pair); 136 security-notice RPCs (missing → "no
    notices").
  - **fail-CLOSED with a visible neutral state:** 140 (`markSent.ts` accepts only `transitioned`/`already_sent`;
    a pre-140 reply → "Not confirmed yet" + re-read, never success); **142** (`settledRead.ts` selects
    `amount_refunded_cents`; absent → `payment_status_unknown`, "We couldn't check whether this has already been
    paid", Pay withheld — **so until 142 is applied every candidate checkout shows that state: 142 must be applied
    before the candidate reaches users**, which is the A′ order); `20260909000000` (Tickets tab; failure is its
    own classified state, empty is success).
  - **Not called:** `20260906120000` — `record_payment_refund` occurs only in a comment; the app's only relation
    to it is indirect (until the server records amounts, refunds render `refund_unconfirmed`, the production
    shape the owner device-passed as H1).
- **Nothing from 143–146** is read by any consumer screen (checked against the #85 chain diff and #86).
- Optional owner device check: D6 Send screen on the candidate (read-only). Held screen stays held (§11).

## 14. Historical notes (superseded, kept for the record)

- v1 §3 recommended "rides the readiness plan's pending chain" without listing that chain's own unfinished
  prerequisites; v3 §3 lists them.
- v1 §1 "Not in this package: 142 (parked on the partial-refund policy)" — superseded by §4: the column is
  merged and required by the app path; only the *writers* are parked.
- v2 §4 "Preview-scope env vars have never been checked by anyone" — superseded by §5.
- v2 §6 "Steps 1–4 above are done" — superseded by §7.
- v2 §10 "both switches off restores pre-package behaviour" — superseded by §8.
- v1 §5.4 "merge the console PR → Vercel production" — superseded by §5 (pin or CLI deploy is the act).
