# Scheme B — Pre-Repair Report

> **STATUS: PRODUCTION LEDGER UNTOUCHED.** No `supabase migration repair` command has been executed.
> No `supabase_migrations.schema_migrations` row has been inserted, deleted, or updated.
> ~~Supabase auto-deploy remains OFF.~~ **Corrected 2026-08-27 (AUTODEPLOY-1): this was asserted
> from documentation, never verified, and was false — the Supabase GitHub integration was active.
> The ledger claims in this report are unaffected and remain verified.** Migration `071` has not
> been authored *(as of this report; authored and applied 2026-08-27)*.

## 1–2. Repository and branch
| | |
|---|---|
| Base `main` | `46aa9a3` |
| Branch | `repo/migration-normalization-schemeB` @ **`30694ec`** (PR **#12**) |
| Commits | 3, all authored and committed by `SnatchIt-app <gnvprod@gmail.com>` |
| History integrity | The earlier tamper commit `47ea6d3` (author `t <t@t>`, from a test harness that copied the worktree's `.git` pointer file) was removed by rebuilding the branch. `054`'s blob is identical to `main`'s (`bdbe603c…`). Independently confirmed by both reviewers. |

## 3. Pinned tooling
**Supabase CLI `2.115.0`**, pinned in `.github/workflows/ci.yml`. Never `latest`. Chosen because its ordering behaviour was verified against the normalized chain; `2.116.0` shipped the same day and is unverified. Upgrades require a deliberate PR: bump pin → fresh replay green → Gate-2 parity green → merge.

## 4–5. Scheme B mapping — 16 renames (not 17)
`023→0230 · 023b→0231 · 055→0550 · 055b→0551 · 055c→0552 · 055d→0553 · 056a→0561 · 056b→0562 · 056c→0563 · 056d→0564 · 059→0590 · 059b→0591 · 060→0600 · 060b→0601 · 066→0660 · 066a→0661`, plus 8 companion files in `supabase/rollbacks/` (24 renames total).

**The expected count was wrong and was corrected against reality:** there is **no `056` parent file** in the chain (only `056a`–`056d`), so this is 11 letter-suffixed files + **5** parents. `0560` is left permanently unused to record that.

## 6. Content-hash proof
- `git diff --find-renames=100%` → **24 × R100**, **0 insertions, 0 deletions**
- Independent **SHA-256** comparison old→new → **24/24 byte-identical**
- `--no-renames --diff-filter=M` over `supabase/**/*.sql` → **0 files modified**
- Agent E, independently: the **sorted multiset of all 84 migration blobs is identical** between `main` and the branch (`e7fc2583…`) — nothing changed even in non-renamed files
- Agent F, independently: the `supabase/migrations` **tree SHA is identical** at `da08454` and `8f967b6` (`e036e1c9…`) — the history rebuild left the SQL payload untouched

## 7. Prefix ambiguity
**0 prefix relationships** (was 7 under Scheme A). 0 duplicates. 0 letter-suffixed versions remaining.

## 8. Ordering proof
`sorted(filenames)` yields the same version sequence as `sorted(versions)` — **true**. Agent F checked all **6,972** ordered pairs: **0 disagreements**.

```
022  < 0230 < 0231 < 024
054  < 0550 < 0551 < 0552 < 0553 < 0561 < 0562 < 0563 < 0564 < 057
058  < 0590 < 0591 < 0600 < 0601 < 061
065  < 0660 < 0661 < 067  < 068  < 069  < 070 < 2026…
```

Agent E established the strongest form of this: the rename is an **identity permutation** — every migration holds the same index 0–83 before and after — so out-of-order execution is structurally impossible. CI's actual apply order is byte-identical to `sorted(filenames)`.

**Ordering model, stated explicitly:** correct under **text (lexicographic)** comparison — what the Supabase CLI (both implementations) and the ledger's `text` version column use. It is **not integer-safe** (`0230`→230 would sort after `070`→70); that is a documented, deliberate trade-off, and "migration versions are compared as text" is recorded as an invariant.

## 9. Fresh replay — CI run `33021382018`, job `98352316081`
```
migration files on disk : 84
applied by the CLI      : 84
duplicate versions      : 0
"Skipping migration"    : 0 occurrences
```
Falsification check (Agent F): the **pre-normalization** chain applied only **66 of 84** and failed with `ERROR: function public.sync_listing_current_bid() does not exist`, because `066a` was silently skipped. The proof distinguishes the broken state from the fixed one.

## 10. Gate-2 parity
`tables=27 functions=68 policies=37 triggers=23` — asserted by **equality** (`-eq`, not a floor), matching the certified Phase-0 baseline **and** live production (verified read-only).

**Known-differing classes, documented and deliberately not asserted:** indexes (production 90 / fresh 93) and storage policies (production 11 / fresh 17). Both were recorded at Gate-2 certification as out-of-band residuals. A fresh replay is therefore *equivalent on the certified classes*, not byte-identical to production.

## 11. Migration guard
**Green in CI on the final SHA** (run `33021554518`): all 16 renames verified content-identical by blob hash, uniqueness OK, prefix-freeness OK, monotonic OK.

Local matrix — **13/13 correct**, executed against an isolated clone with no `rm -f` prefix (proving the workflow cleans its own state):

| Case | Expected | Result |
|---|---|---|
| 1 Approved Scheme-B renames | PASS | **PASS** |
| 2 Approved rename **+ content edit** | FAIL | **FAIL** |
| 3 Unapproved historical rename | FAIL | **FAIL** |
| 4 Historical deletion | FAIL | **FAIL** |
| 5 Normal new `071_` | PASS | **PASS** |
| 6 Back-dated `043_` | FAIL | **FAIL** |
| 7 Duplicate version prefix | FAIL | **FAIL** |
| 8 Historical content modification | FAIL | **FAIL** |
| 9 Rename target added, source not deleted | FAIL | **FAIL** |
| 10 New `0700_` (prefix of `070`) | FAIL | **FAIL** |
| 11 New `202607312246531_` (extends a timestamp) | FAIL | **FAIL** |
| 12 New `0231_`, no matching deletion | FAIL | **FAIL** |
| 13 **Subset** rename (`066a`→`0661` only) | FAIL | **FAIL** |

The guard is now strictly stronger than before this PR: it enforces **prefix-freeness**, which it never did — the invariant the normalization exists to create.

## 12–13. Production ledger — current and proposed
**BEFORE (verified read-only, unchanged):** 79 rows — 39 numeric (`001`–`039`) + 40 timestamps. Zero letter-suffixed versions. Zero Scheme-B versions present.

**PROPOSED AFTER:** **84 rows**, exactly 1:1 with the repository's 84 migration files.

## 14. Exact repair commands
- **Phase A — 42 ×** `supabase migration repair --status applied <version>`
- **Phase B — 37 ×** `supabase migration repair --status reverted <version>` (36 superseded timestamps + `023`, which is now `0230`)
- All **158** version arguments verified integer-parseable; the two lists are disjoint; no duplicate targets. Agent E confirmed Phase A ≡ exactly the pending set and Phase B ≡ exactly the orphan set — no no-ops in either direction.

Full lists: `PHASE_2_MIGRATION_REPAIR_EXECUTION_PLAN.md`.

## 15. Partial-failure recovery
`set -euo pipefail` plus a **hard checkpoint asserting 121 rows** between Phase A and Phase B.

Without it, the worst realistic interleaving is: Phase A aborts partway unnoticed, Phase B runs anyway, and ~37 already-applied migrations are left looking **pending** — a later `supabase db push` would then **re-execute them against live production**, including `040_web_accounts_foundation`, `045_payments_stripe_livemode`, and `070_reconcile_rls_policies_and_triggers`. This was Agent F's finding; it is the single most dangerous scenario in the plan and is prevented by two lines.

## 16. Rollback
Exact inverse command list, Phase B reversed first. Restores precisely the 79-row version set (simulated by both reviewers).

**Honest limitation:** rollback is **not lossless at row level**. The 37 rows to be deleted carry populated `statements`/`created_by` content (~107 KB across 54 statements; `created_by` on 36 of 37). `--status applied` recreates a version row, not that content. **Byte-identical restoration requires the mandatory pre-repair snapshot** (`create table … as select *`), now a hard precondition. This is archival metadata only — the repair is ledger-only, so production schema and all business data are untouched either way.

## 17. Reviewer verdicts
| Reviewer | Verdict |
|---|---|
| Agent E — Database / Migration | **DATABASE REVIEW — ACCEPT** |
| Agent F — Adversarial Staff Engineer | **SCHEME B ACCEPTED** |

Agent F's first pass was **REJECT** (H-1: the guard never enforced prefix-freeness — `0700_evil.sql` passed). Fixed, re-verified, verdict lifted by F itself.

Findings raised across both rounds and closed: H-1 prefix-freeness · M-1/E-3 rename-target bypass · L-1 "any tool" overclaim · M-2 `-ge`→`-eq` · M-3 index/storage-policy overclaim · M-4 partial-repair hazard · M-5 rollback precondition · E-1 incomplete backup · E-2/F-R-2 guard state file never truncated · F-R-1 subset-rename hole · tamper commit.

## 18. CI
| Job | Result |
|---|---|
| Migrations apply cleanly (fresh DB) | **pass** |
| Typecheck / Lint / Unit tests | **pass** |
| Web build (Next.js) | **pass** |
| Migrations guard (run `33021554518`) | **pass** |

## 19. Open risks
1. **Governance gap (new, worth acting on separately):** the guard's `paths:` filter is evaluated against the triggering push's delta, so a later commit that does **not** touch `supabase/migrations/**` leaves the guard un-run for that SHA. Making it a *required* check without addressing this would deadlock PRs that legitimately never touch migrations. Recommend a `paths`-less trigger with an internal early-exit, before adding it to branch protection.
2. **Repair-time precondition:** `043_profiles_select_column_restriction.sql` must remain uncommitted — committing it changes the 84 count and both repair lists.
3. The `Security` workflow (CodeQL / Dependency Review) still does not report on this PR; unrelated to Scheme B and tracked separately.
4. Docker was unavailable locally, so the fresh replay was executed in CI rather than on this machine. CI uses the pinned CLI in a clean environment, which satisfies the requirement.

## Verdict

# SCHEME B READY FOR PRODUCTION LEDGER REPAIR

All preparation is complete and independently verified. The remaining step mutates the production migration ledger and is **not authorized by this work**.
