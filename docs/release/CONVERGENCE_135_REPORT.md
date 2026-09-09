# Release convergence report — the 135-version production line + payments RC + v2 consumer UI

Date: 2026-09-09 · Branch: `release/convergence-135` · Author: payments & release integration

**Nothing in this report was deployed. No migration was applied to production, no Stripe setting,
cron schedule or production flag was changed, **no KMS key was created by this work**, native issuance
stays dark, and nothing was merged into `main`.**

> **2026-09-09 addendum.** A ticket-signing KMS key now EXISTS in AWS — created by the owner's PFA-18C
> C2–C5 ceremony, outside this release work:
> `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e` (ECC_NIST_P256,
> ECDSA_SHA_256). Evidence and read-only corroboration are in
> `docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md` §SESSION 8. It changes nothing
> here: the key is **not** in `kernel.signing_key` (still 0 rows), all three native gates are still
> `false`, and no native edge is deployed. C3 remains unauthorized. Every production interaction below is a read-only query or
API read.

---

## 1. Heads and working trees inspected before any edit

| Line | Ref | Head | Worktree | Tree state |
|---|---|---|---|---|
| Production-aligned admin/native | `admin/operating-console` | `562fda9` | `/Users/josetascon/snatchit-admin-console` | clean |
| Payments RC | `release/payments-converged-rc` = `fix/payments-reliability` | `a77d368` | `/Users/josetascon/snatchit-pay` | clean |
| Consumer UI integration | `publish/ui-v2-integration` | `b6580cf` | `/Users/josetascon/snatchit-rc` | clean |
| Convergence (new) | `release/convergence-135` | see §2 | `/Users/josetascon/snatchit-converge` | new worktree |

`a77d368` is an ancestor of `b6580cf`, so merging the UI branch carries the reviewed payments RC
with it — one merge, not two. The merge base of all three is `10ad9e42`, the Phase-2 production
commit. `main` was **not** used as a baseline anywhere.

Production facts confirmed read-only on 2026-09-09:

- `supabase_migrations.schema_migrations`: **135 rows**, numeric tip `120`, max version `20260902003623`.
- Branch record for `hqycwntpfoztoinemqns`: `git_branch: ""` — the AUTODEPLOY-1 binding is still off.
- Edge functions deployed: **11** (`auto-finalize-auctions`, `confirm-and-release`, `confirm-payment`,
  `create-connect-account`, `create-payment-intent`, `delete-account`, `enforce-transfer-expiry`,
  `notify-report`, `notify-transfer`, `send-push`, `stripe-webhook`). No native edge and no
  `ops-refund-execute` is deployed.

## 2. Branch and commits

- Branch: **`release/convergence-135`**, based on `562fda9` (production-aligned 135 line).
- `477226f` — the merge of `b6580cf` (payments RC + v2 consumer UI), four conflicts resolved.
- `ce81942`, `54f7a93`, `dde4453` — rehearsal harness, report, CI evidence.
- `2f5b800` — the merge of `597533e` (tickets RPC + filter-sheet fix); see §9 and §10.

## 3. Migration inventory and version conflicts

**No filename collision exists.** The two lines add disjoint versions:

| Source | Versions added | Schema touched |
|---|---|---|
| admin/native line | `110`–`114` (signing/door), `115`–`120` (ops console, `119` listing-block guard) | `ops.*` + exactly one `public` function and trigger (119) |
| payments RC | `20260906100000`, `…110000`, `…120000`, `…130000` | `public.*` + a body-only replace of `kernel.sweep_deletion_pending` |
| consumer line | `20260909000000` (tickets ownership read) | one `public` function + its grant; reads `kernel.tickets` |

Canonical order is `LC_ALL=C` filename sort, so every numeric version sorts before every timestamped
one: `000…120` → `20260714…` → `20260730…`×2 → `20260731…` → `20260902003623` → `20260906100000…130000`
→ `20260909000000`. Total **140**, with the tickets migration last.

Production's *actual* order is different and was rehearsed as such (§6): the four 2026-07 website-form
migrations landed between `075` and `076`; `20260902003623` landed before `093`; the ops console
`115`–`120` was deployed 2026-09-08; the signing/door ceremony `110`–`114` was applied 2026-09-09
**after** it. The chain is order-independent — proven, not assumed.

### Semantic (non-filename) interactions examined

| Pair | Verdict |
|---|---|
| `120_ops_console_refund_semantics` vs `20260906120000_payout_attempts_and_refund_monotonic` | No object collision — 120 creates only `ops.*` functions; the RC creates only `public.*`. Every ops reference to refunds is a **read**. |
| `ops-refund-execute` edge vs the RC's refund ledger | Compatible by design: the edge only POSTs to Stripe; `payments.status='refunded'` is written by `stripe-webhook`'s `charge.refunded` branch, which the RC routes through `record_payment_refund` (idempotent on `re_`, monotonic `amount_refunded_cents`). |
| `119_listing_block_insert_guard` vs `20260906100000_checkout_reservation_authority` | Disjoint: 119 is `BEFORE INSERT` only; the RC governs `UPDATE` (reservation/sold). |
| `118` proof-docs operator-read policy vs deletion/tombstone | Storage-schema policy only; no interaction with OR-17. |
| `20260906130000` vs Phase-2 deletion | Body-only `CREATE OR REPLACE` of the deployed `kernel.sweep_deletion_pending`, adding the BP-13 arm on the **external** rail. Tombstone flow preserved. |

## 4. Shared-file conflicts and how each was decided

Four files were modified on both sides. **None was resolved by taking a branch wholesale.**

| File | Admin side | Payments/UI side | Decision |
|---|---|---|---|
| `supabase/tests/162_payout_reversal_and_obligation_recovery.sql` | functions 70→71, triggers 26→27 (119) | functions 70→86, triggers 26→32, tables 27→30 | **Summed**: functions **87**, triggers **33**, tables **30**. Choosing either side would have asserted a catalog that neither branch produces. |
| `.github/workflows/ci.yml` Gate-2 `EXPECT_*` | 27/71/37/27 | 30/86/37/32 | **Summed**: `30/87/37/33`, with both provenance comments kept. |
| `.github/workflows/ci.yml` deno-check | blocking checks for the signing/door/ops edges and their pure modules | closed-world `deployed`(11, blocking) + `native`(7, advisory) | **Restructured into three tiers.** `ops-refund-execute` appeared in *neither* of the RC's lists, so the RC's closed-world check would have failed the job on this tree. Now: 11 deployed (blocking) + 4 production-aligned (`credential-sign`, `door-manifest`, `door-session`, `ops-refund-execute`, blocking) + 4 never-deployed native-arm edges (`connect-onboarding`, `payout-execute`, `primary-checkout`, `refund-execute`, advisory). The shared pure modules of both sides are checked together, blocking. |
| `.github/workflows/ci.yml` deno-check header/notes | signing-train provenance | F18 rationale + BLOCKING-since note | Union of both comments. |
| `supabase/tests/132_replay_parity.sql` | adds 118's `proof-docs operator read` policy to the storage set and its md5 | parameterises the pg_cron database literal to `current_database()` | Auto-merged; **verified** both changes survive (2 policy entries, 4 `current_database()` call sites, both message strings updated). |
| `supabase/ci/assert_public_table_grant_decisions.sql` | +1 decision (119's guard) | +3 tables, +16 function decisions | Auto-merged; **verified** all 20 entries present. |

### Preservation checks

- **Phase-2 deletion/tombstone** — `kernel.sweep_deletion_pending` retained, BP-13 arm added on the
  external rail only; `delete-account` edge untouched by the admin side.
- **Payment acquisition guards** — `20260906100000`/`110000` intact; `guard_payment_transitions`,
  `settle_verified_payment` and `settle_listing_for_payment` all present in the converged catalog.
- **Payout and refund integrity** — the attempt ledger, append-only refund facts and monotonic
  `amount_refunded_cents` all present; the rollback battery re-verified end to end (§6).
- **Native webhook arm stays excluded** — `stripe-webhook` contains **no** `kernel.*` or native call
  site (verified by grep); the four native-arm edges remain undeployed and non-blocking in CI; no
  native issuance is enabled, and this release work created no KMS key. (A KMS key does exist in AWS as
  of 2026-09-09 from the separate PFA-18C ceremony — see the addendum at the top of this report. It is
  not referenced by anything in this tree, is not in `kernel.signing_key`, and gates nothing here.)

## 5. Release blockers addressed

| Blocker | Root cause | Fix |
|---|---|---|
| PR #55 autodeploy attestation | The line read `AUTODEPLOY-VERIFIED-OFF: 2026-09-09 (owner visual confirmation …)`. `migrations-guard.yml:241` requires `^\s*AUTODEPLOY-VERIFIED-OFF:\s*YYYY-MM-DD\s*$` — the trailing parenthetical made it fail. | Line rewritten **date-only**; the provenance moved to the following paragraph. Verified against the workflow's own regex. |
| PR #54 attestation | Placeholder `<owner fills in after confirming in the Supabase dashboard>` — never a date, so `Immutability + ordering` failed. | Set to `2026-09-09`, resting on the owner's dashboard confirmation already recorded on PR #55 plus a read-only re-read showing `git_branch: ""`. Basis stated on a separate line. |
| PR #56 "Migrations apply cleanly (fresh DB)" failure | **Not a test result.** `failed to bind host port for 0.0.0.0:54322 … address already in use`; the stack never booted and the pgTAP suite never ran. | `ci.yml` now frees the stack ports (`supabase stop`, remove any container publishing 54322 or named `supabase_*`) before `supabase start`, and retries the boot once. A genuine migration error still fails both attempts. |
| PR #54 admin preview (`Vercel – snatchit-admin` failed) | The project's Root Directory is `admin`, which exists only on `admin/operating-console`. Vercel validates the root directory **before** running the Ignored Build Step, so the SHA-pinned guard never executes on other branches → `NOW_SANDBOX_WORKER_ROOTDIR_NOT_EXIST`. | Already fixed at project scope on 2026-09-08 (Preview → Branch Tracking disabled); PR #54's red check is a pre-change artifact. On **this** branch the condition cannot recur: the converged tree contains `admin/`. No Vercel setting was changed by this work. |

## 6. Rehearsal results (all local; nothing applied anywhere else)

New harness: `scripts/release/convergence_prod_order_rehearsal.sh` (loopback-only, database name must
contain `rehears`, scrubs every remote connection variable).

| Rehearsal | Result |
|---|---|
| **Fresh DB, canonical `LC_ALL=C` order** (140 migrations, `110`–`114` before `115`–`120`) | **7/7 PASS** — chain applies clean; Gate-2 census `30 \| 88 \| 37 \| 33`; payments tables, ops console, 119's guard, `settle_verified_payment`, and `get_my_tickets()` zero-argument/authenticated-only all present |
| **Production's actual order**: 124-version line → `115`–`120` → `110`–`114` (= 135) → the four payment migrations → the tickets migration | **9/9 PASS** — census at 109 is production's `27\|70\|37\|26`; at the production tip `27\|71\|37\|27`; after the payment migrations `30\|87\|37\|33`; after the tickets migration `30\|88\|37\|33` |
| **Order independence** | **2/2 PASS** — identical Gate-2 census *and* identical function-definition hash (`ecdecf3a72b3d03bc877e7551daf07b2`) across both orders |
| Payments RC production-order + rollback battery (`payments_rc_prod_order_rehearsal.sh`) | **63/63 PASS** on the converged tree — including rollback gates, in-transaction archive, deploy-window duplicate hazard, restore, and no-double-pay |
| Repo unit tests (root, incl. the ported filter-sheet tests) | **1531/1531 PASS**, 59 files |
| Admin console unit tests (`admin/`) | **96/96 PASS**, 15 files |
| Typecheck | clean |
| Lint | 0 errors, 29 warnings |
| Environment pairing gate | OK (4 profiles) |
| `scripts/rehearsal_reset.sh` Gate-2 read-out | `tables=30 functions=88 policies=37 triggers=33` — matches the new `EXPECT_*` |
| Web build (Next.js) | success |
| Grant-decisions closed-world manifest | passes after adding `get_my_tickets()` (§9) |

### CI on this branch — run 34314381166, all jobs green

Pushed 2026-09-09; every job succeeded, including the two that were previously red or unrunnable.

| Job | Result |
|---|---|
| **Migrations apply cleanly (fresh DB)** | **success** — the stack booted (the port fix works), Gate-2 read back `tables=30 functions=87 policies=37 triggers=33`, matching the summed `EXPECT_*` exactly |
| **pgTAP database security suite** | **`Files=70, Tests=4678 … Result: PASS`, all tests successful** — the full suite on the real Supabase stack, which is what the local harness cannot reproduce |
| **Deno type-check (edge functions)** | **success** — `deno check OK: 15 entrypoints (11 deployed + 4 production-aligned)`; the never-deployed native arm reported 10 type errors as a **warning only**, exactly as intended |
| Typecheck / Lint / Unit tests | success |
| Admin console (Next.js) | success |
| Web build (Next.js) | success |

CI's 4678 passing assertions confirm the local pgTAP result below is a harness artefact and not a
property of this tree.

**Re-run after the tickets/filter-sheet integration — run 34315327074, all jobs green:**

| Job | Result |
|---|---|
| Migrations apply cleanly (fresh DB) | success — Gate-2 `tables=30 functions=88 policies=37 triggers=33` |
| pgTAP database security suite | **`Files=71, Tests=4698 … Result: PASS`** (+1 file, +20 assertions — the renumbered `187_my_tickets_read.sql` ran) |
| Deno type-check (edge functions) | success — `deno check OK: 15 entrypoints`; native arm advisory-only, unchanged |
| Typecheck / Lint / Unit tests · Admin console · Web build | success |

**Migration immutability + ordering.** `migrations-guard.yml` is `pull_request`-only, so its checks were
run locally against base `562fda9` from the workflow's own step bodies: immutability (no existing
migration modified, deleted or renamed), name format, version-prefix uniqueness, prefix-freeness and
monotonic ordering — **all pass, zero `::error::`**. The separate G-4 gate,
`scripts/ci/assembled_migration_integrity.sh --require-committed`, also passes: every assembled
migration is exactly its committed assembler's output over exactly the committed slices.

### Local pgTAP: a harness limitation, not a convergence regression

The local no-Docker pgTAP runner reports 6–7 files passing and the rest erroring at fixture setup with
`Cannot set server-controlled listing columns on insert.` **This is pre-existing and branch-independent**:
the identical failure reproduces on `snatchit_rehears_184` (built from the admin line alone) and on
`snatchit_rc_rehearsal` (built from the payments RC alone). The fixtures need the PostgREST role/GUC
context that only CI's real Supabase stack provides, which is why the `db` job — not this harness — is
the authoritative fresh replay. Deno is not installed on this host, so the edge type-check is likewise
CI-only. Both facts are limitations of the local environment and are unchanged by this convergence.

## 7. Read-only audit — legacy evidence in the public `auction-media` bucket

Read-only. **No object was moved, copied, renamed or deleted, and no bucket or storage policy was
changed.**

| Bucket | Public | Objects | Size |
|---|---|---|---|
| `auction-media` | **yes** | 134 | 75 MB |
| `avatars` | yes | 11 | 1.8 MB |
| `proof-docs` | no | 29 | 21 MB |
| `crm-exports`, `pkpass` | no | 0 | — |

Classification of the 134 objects in the public bucket:

| Kind | Count | Size | Owner folders | Date range |
|---|---|---|---|---|
| Listing cover image (legitimately public) | 100 | 34 MB | 8 | 2026-02-21 → 2026-08-05 |
| **`listings.proof_of_ownership_path`** | **16** | 29 MB | 6 | 2026-04-03 → 2026-06-08 |
| **`transfers.transfer_evidence_path`** | **11** | 12 MB | 4 | 2026-04-03 → 2026-07-02 |
| Unreferenced | 7 | 1.1 MB | 4 | 2026-02-21 → 2026-08-05 |

**Finding.** 27 ownership-proof and transfer-evidence documents — 41 MB across 8 distinct owner
folders — sit in a bucket whose policy is `public read public buckets` for `auction-media` and
`avatars`. Anyone who knows or can enumerate the object path can fetch them without authentication;
the private-bucket policies that gate `proof-docs` (owner read, transfer-party read, and 118's
operator read) do not apply to them. These are ticket-ownership documents: screenshots and
confirmations that typically carry names, order numbers and barcodes.

**Scope is closed, not growing.** The cutover to the private `proof-docs` bucket happened: of the 35
listings carrying a proof path, 19 are already private and 16 are legacy; of the 17 transfers with an
evidence path, 6 are private and 11 are legacy. The newest legacy object is 2026-07-02 and nothing has
landed in `auction-media` as evidence since.

**Not remediated here, by instruction.** Remediation is a data-movement operation (copy to
`proof-docs`, repoint `listings.proof_of_ownership_path` / `transfers.transfer_evidence_path`, then
delete the public copies) and it interacts with the deletion/tombstone machine — a tombstoned account's
evidence must not be resurrected into a new bucket. It should be its own change with its own rollback,
and it needs an owner decision on whether the 7 unreferenced objects are deleted or archived.

## 8. Remaining blockers

1. **Owner approvals still outstanding** — deletion amendment PFA-32 signature; adding
   `payment_intent.canceled` to the Stripe webhook subscription; legacy orphan reconciliation plus the
   payout-cron pause during the edge deploy; the AUTODEPLOY attestation now stands date-only on #54/#55
   but the *apply* itself remains unauthorised.
2. **Physical-device retest** of the consumer UI on the converged tree. The device evidence recorded so
   far (D3/D4 + auth-logo) was gathered on build `d9b7c85b` from `9942a94`; cases D1, D2, D5–D11 are
   still untested on a device.
3. ~~CI has not yet run on this branch.~~ **Cleared** — run 34314381166 is green on every job,
   including the fresh-DB replay (4678 pgTAP assertions) and the Deno type-check.
4. **Partial refunds are invisible to the ops console** — see §11. Recorded, deliberately not fixed
   here; close it before refund execution is enabled.
5. **`auction-media` legacy evidence** (§7) — 27 objects awaiting a remediation change and an owner
   decision on the 7 unreferenced objects.
6. **Twilio Account SID rotation** decision still open from the publish work.

## 9. Consumer branch integrated — tickets RPC + filter-sheet fix (2026-09-09)

`origin/publish/ui-v2-integration` at `597533e` was merged into this branch after the base convergence
was verified. It brought two commits:

| Commit | What |
|---|---|
| `ca5d56b` | filter-sheet footer row divides instead of overflowing (`FilterSheet.tsx`, `Sheet.tsx`, `ui/index.ts`, `app/_dev/foundation.tsx`, + `tests/filter-sheet-action-bar.test.ts`) |
| `597533e` | migration `20260909000000_kernel_my_tickets_read` + its rollback + pgTAP suite + GATE-2 updates |

Everything §1–§8 established is preserved: the 110–120 lineage, payments P1–P3, the deletion/tombstone
machine, payout and refund integrity, the native-arm exclusion, and the 139-migration order — the
tickets migration is appended as **140**, last in the canonical chain.

### The count trap this merge contained, and how it was resolved

Both lines had independently moved `EXPECT_FUNCS` to **87**, for **different** objects: the admin line
because `119` adds `public.guard_listing_seller_not_blocked`, the consumer line because
`20260909000000` adds `public.get_my_tickets`. Git saw `87` on both sides of the count line and
auto-merged it silently — only the *comment* conflicted. A tree carrying both objects has **88**.

Per the integration requirement, the numbers were taken from the catalog of an actual replay, not from
either branch's text. A fresh replay of all 140 migrations reads:

```
GATE-2  tables=30 functions=88 policies=37 triggers=33
```

`ci.yml` `EXPECT_*` and `supabase/tests/162` (P2) are now `30 / 88 / 37 / 33`. Tables, policies and
triggers are unchanged because the tickets migration is additive and read-only — one function plus its
grant, no table, policy or trigger.

### A real gap in the incoming work, fixed here

`supabase/ci/assert_public_table_grant_decisions.sql` is closed-world over public functions, and
`public.get_my_tickets()` had no row in it. Run against the replayed 140-migration database it failed:

> `ERROR: Public function(s) with NO recorded EXECUTE decision: get_my_tickets().`

Added as `('get_my_tickets()', 'authenticated-execute')` — the same posture as the precedent
`get_my_profile()`. The manifest's posture check then passes ("every recorded function posture matches
the catalog"), which independently confirms the migration's `REVOKE … FROM PUBLIC, anon` +
`GRANT EXECUTE … TO authenticated` is what the catalog actually holds.

### Tickets contract, verified

| Requirement | Evidence |
|---|---|
| Zero-argument, owner-scoped RPC | `public.get_my_tickets()` takes no arguments and binds to `auth.uid()`; fail-closed when it is NULL. Asserted in the rehearsal (`F7`) and in `187`. |
| Authenticated-only execution | `REVOKE ALL … FROM public, anon` then `GRANT EXECUTE … TO authenticated`; confirmed against the live catalog by the grant-decisions posture check and by `F7` (`authenticated` yes, `anon` no). |
| Cross-user reads impossible | Structural: the body's only ownership predicate is `auth.uid()`; no argument exists through which another user could be named. |
| Empty native issuance returns a valid empty result | Native issuance is dark, so `kernel.tickets` is empty and the function returns the defined empty set — the migration header states this and `187` asserts it. |
| No QR / barcode / Wallet behaviour | No `qr`, `barcode`, `wallet` or `pkpass` token appears anywhere in the migration; it projects a status vocabulary only, and carries no payment or Stripe identifier. |

## 10. Duplicate pgTAP number — decision

Both lines contributed a suite numbered `176`:

- `176_signing_key_insert_guard.sql` — admin/native line, pairs with migration `110` inside the
  contiguous `176`–`186` block that covers migrations `110`–`120`, and is cited by
  `docs/phase2/M6_MIGRATION_110_SPEC_AND_REVIEW.md`.
- `176_my_tickets_read.sql` — the incoming tickets suite.

**Decision: the incoming suite was renumbered to `187_my_tickets_read.sql`; nothing was deleted.**
Renaming the established file would have broken the `176`–`186` ↔ `110`–`120` mapping and an existing
document reference. `187` is the next free number and is also the correct ordinal: `20260909000000` is
the last migration in the chain. The rename was done with `git mv` (history preserved), the suite's own
header records the renumber and its reason, and the reference in
`docs/product-v2/RC_TICKETS_RPC_AND_FILTER_SHEET.md` was updated.

## 11. Partial-refund reporting gap (recorded, not fixed)

Migrations `116`–`120` build the ops console's money reporting on `payments.status = 'refunded'` and
`payments.refunded_at` only. The payments RC introduces `payments.amount_refunded_cents` and an
append-only `payment_refunds` ledger, and marks a payment `'refunded'` **only when the refunded amount
reaches its total**. Consequently a *partially* refunded payment is reported by the ops console as not
refunded at all: it is absent from refunded-volume sums, from the refunded count, and from the daily
summary's refund basis.

This is a reporting gap, not a data-integrity defect — the ledger and `amount_refunded_cents` hold the
correct facts, and refund monotonicity is enforced regardless of what the console displays. It is
**not** addressed in this task: no reporting was changed and refunds remain disabled. It should be
closed before refund execution is enabled, since an operator would otherwise be looking at figures that
understate refunds.

