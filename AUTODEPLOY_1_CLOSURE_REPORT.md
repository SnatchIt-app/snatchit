# AUTODEPLOY-1 — Incident Closure Report

**Verdict: AUTODEPLOY-1 OPEN.**

Everything that can be done from the repository is done. Closure requires one owner action that
has no API or CLI surface — a visual confirmation in the Supabase dashboard. Until that happens,
**no migration-bearing PR may merge to `main`.**

| | |
|---|---|
| Incident | Migration `071` was applied to the production database by merging PR #14, not by a deploy command |
| Severity | HIGH (process) |
| Production ledger before this work | **85** |
| Production ledger now | **85** |
| Schema changed during this investigation | **None** |
| Migrations authored | **None** — no `072`, no test migration |
| PRs merged | **None** |

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

Then tell me what you saw, and I will record it below and re-run §7.

```
Setting found (verbatim label):        ____________________________________
Previous state:                        ____________________________________
New state:                             ____________________________________
Confirmed by / date:                   ____________________________________
```

### Also worth your attention while you are in there

`supabase branches get <id>` returns the project's **live `service_role` key, anon key, JWT secret
and pooled Postgres URL** in plaintext. I ran it during this investigation, so those values appeared
in this session's transcript. They were not sent anywhere, and this is your own session — but if
this transcript is ever shared, rotate the service-role key and JWT secret first.

## 7. Verification of the fix — deferred, and honestly scoped

To be run **after** §6, not before.

**What a docs-only merge can prove:** that a merge to `main` completes with the production ledger
unchanged at **85**, and that the Supabase check either does not run or runs without applying
anything. PR #15 is exactly this signal and is already staged for it (§8).

**What it cannot prove:** that a *migration-bearing* merge would no longer deploy. A docs-only PR
has nothing pending for `db push` to apply, so a clean result is consistent both with "auto-deploy is
now off" and with "auto-deploy is still on but had nothing to do" — which is precisely the state
that hid this defect for three days. **A docs-only merge is corroborating evidence, not proof.**

I will not create a throwaway migration to probe production. The only proof that would satisfy the
question is the owner's direct view of the setting, which is why §6 is the closure gate and this
section is not.

Ledger check, before and after any merge: `select count(*) from supabase_migrations.schema_migrations`
→ must read **85** both times.

## 8. PR status

| PR | Contents | Migration/schema changes | State |
|---|---|---|---|
| [#15](https://github.com/SnatchIt-app/snatchit/pull/15) | `071_PRODUCTION_VERIFICATION_REPORT.md` | **None** — one added `.md` file, verified by `git diff --name-only` against `main` | **Open, not merged.** Cleared to merge once §6 is confirmed. |
| **#16 (this change)** | Docs corrections, canonical `DEPLOYMENT_PATHS.md`, workflow comment fixes, the enforced precondition | **None** — no file under `supabase/migrations/` touched | **Open, not merged.** |

Neither is migration-bearing, so neither trips the new precondition check, and neither can cause a
migration to be applied. Both are nonetheless held until §6, per the absolute rule.

Merge order once closure is confirmed: **#16 first** (it carries the rule and the enforcement), then
**#15**. Confirm the ledger reads 85 after each.

## 9. Remaining risk

| | Risk |
|---|---|
| **Open** | The control itself is unverified and possibly still live. **This is AUTODEPLOY-1.** Any migration-bearing merge before §6 repeats the incident. |
| **Latent** | The same integration can deploy **Edge Functions**. It did not this time, but the money-critical functions (`stripe-webhook`, `confirm-and-release`, `create-payment-intent`) are in scope for whatever the setting governs. Confirm that too while in the dashboard. |
| **Partial** | The new CI gate proves acknowledgement, not configuration. It cannot be strengthened without an API for the setting. |
| **Unchanged** | **H-1 (HIGH)** — `guard_listing_state_columns` / `guard_listing_identity_columns` are UPDATE-only and do not protect INSERT. Deliberately **not** bundled here. Still blocks Phase 2 GO. Not authored in this session. |
| **Unchanged** | MONEY-1 (Medium), REPLAY-1 (Medium), DRIFT-1 (Low) — see `071_PRODUCTION_VERIFICATION_REPORT.md` §9. |
| **Minor** | `CLAUDE.md` §Commands still names **Supabase CLI 2.75.0** for fresh-DB replay; the pinned CLI is **2.115.0** and CI installs `latest`. Three different versions in play. Not touched here — out of scope for this incident, but worth a pass. |

---

## Verdict

**AUTODEPLOY-1 OPEN** — pending the owner confirmation in §6.

Root cause identified with database-level evidence, blast radius bounded, documentation corrected,
precondition documented and mechanically enforced. Production ledger **85** before and after this
work; **no schema changed**; **no migration authored**; **nothing merged**.

Per instruction, work stops here. H-1 is not authored and Phase 2 is not started.
