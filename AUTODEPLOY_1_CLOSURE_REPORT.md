# AUTODEPLOY-1 — Incident Closure Report

**Verdict: AUTODEPLOY-1 CLOSED** (2026-08-27). The owner disabled automatic deployment; the change is
independently confirmed at the API level and by changed behaviour on two merges to `main`. See §6
and §7 for what that does and does not prove.

| | |
|---|---|
| Incident | Migration `071` was applied to the production database by merging PR #14, not by a deploy command |
| Severity | HIGH (process) |
| Production ledger before this work | **85** |
| Production ledger now | **85** |
| Schema changed during this investigation | **None** |
| Migrations authored | **None** — no `072`, no test migration |
| PRs merged | **#16 then #15**, both docs/CI only, both after the fix |

---

## 1. Root cause

**Supabase Branching is connected to this repository with git `main` bound to the production
project.** On every push to `main`, Supabase's own infrastructure runs the CLI's `db push` sequence
against production and applies anything pending in `supabase/migrations/`.

`supabase branches list` returns exactly one entry:

```
id=99b9a6ff-16dc-4570-9749-cfedf99c8372
name=main   is_default=true   git_branch=main   persistent=false
project_ref=hqycwntpfoztoinemqns   parent_project_ref=hqycwntpfoztoinemqns
created_at=2026-08-24T15:18:09Z
```

`parent_project_ref` **equals** `project_ref`, and the branch's connection details resolve to
`db.hqycwntpfoztoinemqns.supabase.co` — the production host. **This is not a preview branch.** The
GitHub check it produces is named "Supabase **Preview**", which is what made it easy to dismiss.

Answering the four candidates posed:

| | Candidate | Finding |
|---|---|---|
| A | Supabase "Deploy to production" was ON | **Cannot be confirmed programmatically.** No Management API or CLI surface exposes the toggle. This is the owner boundary. |
| B | another GitHub integration setting caused it | **No.** Only two GitHub Apps act on this repo: Vercel (web only — every GitHub *deployment* record is `vercel[bot]`, environment `Preview`) and Supabase. |
| C | **the linked-`main` branch itself has automatic production migration promotion** | **YES — this is the responsible control.** The branch record above binds git `main` to the production project. |
| D | some other mechanism applied 071 | **No.** Ruled out by the database's own logs (§2). |

C is the mechanism. Whether it is exposed to the owner as a distinct "deploy to production" switch
or is inherent to the branching connection is the part only the dashboard can answer — hence A stays
unconfirmed and the verdict stays OPEN.

## 2. Timeline

| Time (UTC) | Event | Source |
|---|---|---|
| 2026-08-24 15:18:09 | Supabase branch record created, `git_branch=main`, bound to the production project | `supabase branches list` |
| 2026-08-27 00:35:52→00:35:59 | Supabase check on `main` `75d701e` — **FAILURE**: *"Remote migration versions not found in local migrations directory"* | GitHub check-runs API |
| 2026-08-27 03:36:40→03:36:50 | Supabase check on `main` `aa0626d` — success, **no effect** (ledger already 84/84, nothing pending) | GitHub check-runs API |
| 2026-08-27 ~15:05 | Pre-merge snapshot: ledger **84**, `guard_proof_status` `prosecdef=t`, `search_path=public`, trigger `BEFORE UPDATE` | direct SQL |
| **15:10:54** | **PR #14 squash-merged to `main` (`7ff83f8`)** | `gh pr view 14 --json mergedAt` |
| 15:11:26 | Supabase check starts on `7ff83f8` | GitHub check-runs API |
| **15:11:33.961** | Session `6a9053a5.2fb950` opens as `postgres` from `2600:1f18:…` (AWS) and runs `CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations` | `postgres_logs` |
| 15:11:33.962–33.970 | `ALTER TABLE … ADD COLUMN IF NOT EXISTS statements` / `name` | `postgres_logs` |
| 15:11:34.106–34.259 | `CREATE FUNCTION` → `COMMENT` → `DROP TRIGGER` → `CREATE TRIGGER` → `REVOKE` — the whole of `071` | `postgres_logs` |
| 15:11:34 | Supabase check completes, conclusion `success` | GitHub check-runs API |
| ~15:13 | Ledger reads **85**, `071` present, new body live | direct SQL |

**298 milliseconds, one session, no human in the loop.**

The opening three statements are the decisive fingerprint: `CREATE TABLE IF NOT EXISTS
supabase_migrations.schema_migrations` followed by `ADD COLUMN IF NOT EXISTS statements` / `name` is
the Supabase CLI's migration bootstrap. Nothing but a `db push` emits that sequence. It ran as
`postgres` from an AWS address — not the temporary login role a locally-run CLI mints, and not the
MCP session.

**How this went unnoticed for three days.** The integration fired on every `main` push from
2026-08-24. It was harmless only by accident: while the Scheme-B ledger mismatch stood it **failed
closed** (`75d701e`), and once the ledger was reconciled there was simply nothing pending until
`071`. The one red check was read as a preview-environment problem. Nobody connected a red
"Supabase Preview" check to a refused production deployment.

**Near-miss.** `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` had warned since before this that
enabling auto-deploy during the mismatch would "re-apply 040–068 to production". The integration was
already enabled the whole time. It did not re-apply them only because the mismatch pointed the safe
way — remote versions absent locally, which the CLI refuses — rather than the reverse.

## 3. Blast radius of the unintended deploy

Migrations only. Nothing else was deployed:

- **Edge Functions were NOT deployed.** All 11 functions were last updated between 2026-08-04 and
  2026-08-06; none changed on 2026-08-27. The branch record's `FUNCTIONS_DEPLOYED` status is a stale
  label from 2026-08-24, not evidence of a deploy. (Worth knowing: the same integration is capable
  of deploying functions, so this is a latent path, not an absent one.)
- **Exactly one migration was applied**, and it was the reviewed artifact — SHA-256 `f3fb38d1…`,
  live body byte-identical to source, verified in `071_PRODUCTION_VERIFICATION_REPORT.md`.
- **Gate-2 object counts unchanged**: 27 tables / 68 functions / 37 policies / 23 triggers.
- **Ledger gained exactly one row**; repo and ledger remain 1:1 (both md5
  `4783033000cc5cb11e03271330cbd049`).
- **Pre-Scheme-B backup intact**: 79 rows.

The outcome was authorized — you approved applying 071. What was unauthorized was the *path*: the
gate between "merge" and "apply" did not exist.

## 4. Repository documentation — what was wrong and what changed

The repository asserted in several places that merges do not deploy. Two distinct errors:

1. **Unverified claims stated as fact.** I asserted "Supabase auto-deploy remains OFF" in the
   GO/NO-GO report and the Scheme-B pre-repair report. I never checked it. There is no way I *could*
   have checked it programmatically — which made it exactly the kind of claim that required an owner
   confirmation rather than an assertion.
2. **A conditional prohibition that had silently expired.** The engineering standards and the
   execution protocol both said auto-deploy must stay off *until the migration history is
   reconciled*. That reconciliation completed on 2026-08-26, so as written both documents had
   turned into permission.

Separately, `.github/workflows/*` correctly said CI does not touch production — true, and not the
point. The repository had no concept of a second deployment path.

| File | Change |
|---|---|
| `docs/operations/DEPLOYMENT_PATHS.md` | **NEW — canonical.** Both paths side by side, how to recognise Path B in evidence, the rule, the required sequence, approved apply paths, owner dashboard navigation, incident history. |
| `CLAUDE.md` | New "Deployment paths" section above the stop-and-ask triggers. |
| `AGENTS.md` | Rewrote "Deployment rules" opening; noted that "prefer Git-based deployments" does **not** extend to migrations; corrected the Supabase section's description of the branch entity. |
| `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` | §6 prohibition made **unconditional**, with the reason; §5's version-discipline note marked resolved so it can no longer be read as lifting §6. |
| `docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` | §1 statement superseded; §2 step 10 split into **10a deploy-path precondition** and **10b explicit apply**, with the full required order. |
| `.github/workflows/README.md` | "Intentionally deferred" scoped to GitHub Actions, with a block-quote naming Path B. |
| `.github/workflows/ci.yml` | Header comment corrected — "Nothing in THIS WORKFLOW deploys", plus the Path B warning. |
| `PHASE_2_IMPLEMENTATION_GO_NO_GO.md` | §15 correction block; the "auto-deploy OFF ✅" row flipped to ❌ with a pointer. |
| `SCHEME_B_PRE_REPAIR_REPORT.md`, `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` | Correction notes; the reconciliation doc's warning annotated with the fact that it was already too late. |

The wording required by the task appears verbatim in the canonical doc, CLAUDE.md, AGENTS.md and the
engineering standards:

> **GitHub Actions CI is non-production. The Supabase GitHub integration is a separate deployment
> path and must remain configured so production migrations are owner-gated.**

## 5. Deployment precondition — documented *and* enforced

Documentation is what failed here, so the precondition is also mechanical.

`migrations-guard.yml` — already a **required** status check, so this takes effect immediately —
now fails any PR that touches `supabase/migrations/**` unless the PR **description** contains:

```
AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD
```

The workflow already triggers on `edited`, so the check re-runs when the description is updated.
Verified against 8 cases before shipping: valid line passes (including CRLF and leading indent);
absent, empty body, missing date, malformed date, and the token mid-sentence all fail.

**What this check does and does not prove.** It proves a human recorded an acknowledgement. It does
**not** prove auto-deploy is off — CI cannot read the Supabase dashboard, and the workflow says so
in its own comment. A green check is not evidence about the setting. This is a forcing function
against merging on autopilot, not a control.

The PR body is passed via `env:` rather than interpolated into the `run:` block — a PR description
is attacker-controlled text and `${{ }}` inside `run:` is a shell-injection sink.

Required order, now in the protocol:

> PR reviewed → staging verified → **owner confirms auto-deploy OFF** → merge → explicit
> owner-authorized apply → live verification

## 6. Owner action required — this is the only thing blocking closure

I stopped at this boundary rather than routing around it. There is no Management API or CLI surface
for the toggle; `supabase branches list` / `get` return the branch record and its connection secrets,
but not the deploy-on-merge setting.

```
Supabase Dashboard  →  https://supabase.com/dashboard/project/hqycwntpfoztoinemqns
  →  Project Settings  →  Integrations  →  GitHub
     (equivalently: the Branching section, where the production-branch binding lives)
```

Find the connection to `SnatchIt-app/snatchit` and the production-branch / deploy-on-merge behaviour
bound to `main`. Configure it so **merging to `main` does not apply database migrations to
production**.

**Recommendation: disconnect the GitHub integration entirely** while Phase 2 is pending. Nothing in
the current workflow depends on it. Its complete observed contribution to date is one silent no-op,
one red check that was misread, and one unreviewed production migration. If branching is wanted
later, reconnect it deliberately with a non-production branch binding.

### DONE — owner confirmation, 2026-08-27

**Owner turned automatic deployment off.** Reported in session at ~15:49 UTC.

That statement is corroborated by an API-level state change I did **not** have to take on trust.
The Supabase branch record moved as follows:

| field | before (15:05) | after (15:49) |
|---|---|---|
| `git_branch` | `"main"` | **`""`** |
| `updated_at` | `2026-08-24T15:47:27Z` | **`2026-08-27T15:49:25Z`** |
| `is_default` | `true` | `true` (unchanged) |
| `project_ref` / `parent_project_ref` | equal | equal (unchanged) |

**The git binding is severed.** The field that made merges to `main` reach production is now empty.
The branch record itself still exists and still points at the production project — it is the *link
to git* that was removed, which is the link that mattered.

Not captured: the verbatim dashboard label and its previous state. Worth recording for the audit
trail if you still have it, but the API evidence above is the stronger artefact and the closure does
not depend on the label.

### Also worth your attention while you are in there

`supabase branches get <id>` returns the project's **live `service_role` key, anon key, JWT secret
and pooled Postgres URL** in plaintext. I ran it during this investigation, so those values appeared
in this session's transcript. They were not sent anywhere, and this is your own session — but if
this transcript is ever shared, rotate the service-role key and JWT secret first.

## 7. Verification of the fix — executed

Two merges to `main` after the fix, neither migration-bearing, no test migration created.

| | `#16` → `ff36444` | `#15` → `e332a21` |
|---|---|---|
| Supabase check on the `main` commit | **`skipped`** | **`skipped`** |
| Production ledger after | **85** | **85** |
| Ledger md5 after | `4783033000cc5cb11e03271330cbd049` | same |
| Backup rows | 79 | 79 |
| `guard_proof_status` still `prosecdef=false` | ✓ | ✓ |
| Trigger still `BEFORE INSERT OR UPDATE` | ✓ | ✓ |
| Tables / functions / policies | 27 / 68 / 37 | unchanged |

**The behavioural comparison is the useful part, and it is like-for-like.** Merge `aa0626d`
(2026-08-27 03:36) was also docs/CI-only with **nothing pending**, and the integration returned
**`success`** — it processed the push and found nothing to do. The same shape of merge now returns
**`skipped`**: the integration no longer processes pushes to `main` at all. That is a change in the
control, not merely a change in outcome.

### What this proves, and what it does not

**Proven:**
- The git↔branch binding is gone at the API level (§6) — `git_branch` is empty.
- The integration's response to a push to `main` changed from processing (`success`) to not
  processing (`skipped`), on comparable merges.
- Two merges to `main` completed with production bit-identical: ledger 85, same md5, backup 79,
  Gate-2 counts unchanged, `071` intact.

**Not proven:** that a *migration-bearing* merge would not deploy. Both merges had nothing pending,
so on their own they are consistent with "off" and with "on but idle" — precisely the ambiguity that
hid this defect for three days. This is why the §6 evidence carries the closure and §7 corroborates
it, not the reverse. I did not and will not create a throwaway migration to probe production.

**The first genuine test will be the H-1 migration**, and it is now gated: the required
`migrations-guard` check will refuse it without `AUTODEPLOY-VERIFIED-OFF`, and the apply will be an
explicit owner-authorized step per §5. Verify the ledger goes 85 → 86 **only** at that explicit
apply, and not at the merge.

## 8. PR status

| PR | Contents | Migration/schema changes | State |
|---|---|---|---|
| [#16](https://github.com/SnatchIt-app/snatchit/pull/16) | Docs corrections, canonical `DEPLOYMENT_PATHS.md`, workflow comment fixes, the enforced precondition | **None** — no file under `supabase/migrations/` touched | **Merged** → `main` `ff36444` |
| [#15](https://github.com/SnatchIt-app/snatchit/pull/15) | `071_PRODUCTION_VERIFICATION_REPORT.md` | **None** — one added `.md` file, verified by `git diff --name-only` against `main` | **Merged** → `main` `e332a21` |

Neither was migration-bearing, so neither tripped the new precondition check and neither could cause
a migration to be applied. Both were held until §6 was confirmed, per the absolute rule, then merged
in that order — #16 first, because it carries the rule and the enforcement.

Ledger read **85** before, between, and after. `main` is now `e332a21`.

## 9. Remaining risk

| | Risk |
|---|---|
| **Closed** | ~~The control itself is unverified and possibly still live.~~ Disabled by the owner and confirmed at the API level (§6); behaviour on `main` changed from `success` to `skipped` (§7). |
| **Residual** | The fix has not been exercised against a *migration-bearing* merge, and deliberately will not be probed. The H-1 migration is the first real test; it is gated by the required check and an explicit apply step. Watch that the ledger moves 85 → 86 only at the apply, never at the merge. |
| **Residual** | The branch record still exists and still points at the production project (`parent_project_ref == project_ref`); only `git_branch` was cleared. If the integration is ever reconnected, this binding is what to re-check — a reconnect could silently restore the old behaviour. |
| **Latent** | The same integration can deploy **Edge Functions**. It did not during the incident, but the money-critical functions (`stripe-webhook`, `confirm-and-release`, `create-payment-intent`) were in scope of whatever the setting governed. With the git binding cleared this path is closed too, by the same mechanism — worth re-checking on any reconnect. |
| **Partial** | The new CI gate proves acknowledgement, not configuration. It cannot be strengthened without an API for the setting. |
| **Unchanged** | **H-1 (HIGH)** — `guard_listing_state_columns` / `guard_listing_identity_columns` are UPDATE-only and do not protect INSERT. Deliberately **not** bundled here. Still blocks Phase 2 GO. Not authored in this session. |
| **Unchanged** | MONEY-1 (Medium), REPLAY-1 (Medium), DRIFT-1 (Low) — see `071_PRODUCTION_VERIFICATION_REPORT.md` §9. |
| **Minor** | `CLAUDE.md` §Commands still names **Supabase CLI 2.75.0** for fresh-DB replay; the pinned CLI is **2.115.0** and CI installs `latest`. Three different versions in play. Not touched here — out of scope for this incident, but worth a pass. |

---

## Verdict

**AUTODEPLOY-1 CLOSED.**

Root cause identified with database-level evidence (Supabase Branching bound git `main` to the
production project; the CLI's `db push` bootstrap ran as `postgres` from AWS 39 s after the merge).
Blast radius bounded to one migration — the reviewed artifact — with Edge Functions excluded on
evidence. Automatic deployment disabled by the owner and confirmed independently: `git_branch`
cleared from `"main"` to `""`, and the integration's response to a push to `main` changed from
`success` to `skipped` on a like-for-like merge. Documentation corrected in nine files with a new
canonical reference. The precondition is both documented and mechanically enforced in a required
check.

Production ledger **85** throughout — before the investigation, between the two merges, and after.
**No schema changed. No migration authored.** The rule stands: on this repository a merge must never
again be the apply.

The one thing that would make this airtight — a migration-bearing merge that does *not* deploy — is
deliberately left untested rather than probed against production. It will be answered for real by
H-1.

Per instruction, work stops here. **H-1 is not authored and Phase 2 is not started.**
