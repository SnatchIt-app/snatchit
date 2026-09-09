# Release convergence report — the 135-version production line + payments RC + v2 consumer UI

Date: 2026-09-09 · Branch: `release/convergence-135` · Author: payments & release integration

**Nothing in this report was deployed. No migration was applied to production, no Stripe setting,
cron schedule or production flag was changed, no KMS key was created, native issuance stays dark,
and nothing was merged into `main`.** Every production interaction below is a read-only query or
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
- `477226f` — the merge of `b6580cf` with the four conflicts resolved.
- Convergence head: see the tip of the branch; the report commit follows the merge.

## 3. Migration inventory and version conflicts

**No filename collision exists.** The two lines add disjoint versions:

| Source | Versions added | Schema touched |
|---|---|---|
| admin/native line | `110`–`114` (signing/door), `115`–`120` (ops console, `119` listing-block guard) | `ops.*` + exactly one `public` function and trigger (119) |
| payments RC | `20260906100000`, `…110000`, `…120000`, `…130000` | `public.*` + a body-only replace of `kernel.sweep_deletion_pending` |

Canonical order is `LC_ALL=C` filename sort, so every numeric version sorts before every timestamped
one: `000…120` → `20260714…` → `20260730…`×2 → `20260731…` → `20260902003623` → `20260906100000…130000`.
Total **139**.

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
  native issuance is enabled and no KMS key was created.

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
| **Fresh DB, canonical `LC_ALL=C` order** (139 migrations, `110`–`114` before `115`–`120`) | **6/6 PASS** — chain applies clean; Gate-2 census `30 \| 87 \| 37 \| 33`; payments tables, ops console, 119's guard and `settle_verified_payment` all present |
| **Production's actual order**: 124-version line → `115`–`120` → `110`–`114` (= 135) → the four payment migrations | **7/7 PASS** — census at 109 is production's `27\|70\|37\|26`; census at the production tip is `27\|71\|37\|27`; after the release `30\|87\|37\|33` |
| **Order independence** | **2/2 PASS** — identical Gate-2 census *and* identical function-definition hash (`56793098ac862824d1edea056b0ead76`) across both orders |
| Payments RC production-order + rollback battery (`payments_rc_prod_order_rehearsal.sh`) | **63/63 PASS** on the converged tree — including rollback gates, in-transaction archive, deploy-window duplicate hazard, restore, and no-double-pay |
| Repo unit tests (root) | **1515/1515 PASS**, 58 files |
| Admin console unit tests (`admin/`) | **96/96 PASS**, 15 files |
| Typecheck | clean |
| Lint | 0 errors, 29 warnings |
| Environment pairing gate | OK (4 profiles) |
| `scripts/rehearsal_reset.sh` Gate-2 read-out | `tables=30 functions=87 policies=37 triggers=33` — matches the new `EXPECT_*` |

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
4. **Partial refunds are invisible to the ops console.** The RC introduces
   `payments.amount_refunded_cents` and an append-only refund ledger; migrations 116–120 read only
   `status='refunded'` and `refunded_at`, so a partially refunded payment still reports as unrefunded in
   ops summaries and money reports. Not a merge conflict and not a regression — a reporting gap the
   admin console should close before refunds are enabled.
5. **`auction-media` legacy evidence** (§7) — 27 objects awaiting a remediation change and an owner
   decision on the 7 unreferenced objects.
6. **Twilio Account SID rotation** decision still open from the publish work.

## 9. Drift observed after this convergence was built — read this before merging anything

`publish/ui-v2-integration` has moved since the head this task pinned. It is now `597533e`, two commits
ahead of `b6580cf`:

| Commit | When | What |
|---|---|---|
| `ca5d56b` | 2026-09-08 23:04 −04 | cherry-pick: filter-sheet footer row divides instead of overflowing |
| `597533e` | 2026-09-09 01:09 −04 | new migration `20260909000000_kernel_my_tickets_read` + rollback + `supabase/tests/176_my_tickets_read.sql` |

`release/convergence-135` was built from `b6580cf` as specified, so it does **not** contain these. Do
not fast-forward or naively merge them — three concrete hazards:

1. **The function count collides at the same number for different reasons.** `597533e` raises
   `EXPECT_FUNCS` 86 → **87** because `20260909000000` adds `public.get_my_tickets`. This convergence
   raises it 86 → **87** because migration `119` adds `public.guard_listing_seller_not_blocked`. A
   merge that sees "87 on both sides" and takes either one is wrong: the correct converged value is
   **88**, and Gate-2 would fail on a tree carrying both.
2. **A pgTAP filename number is taken twice.** The converged tree already has
   `supabase/tests/176_signing_key_insert_guard.sql` (admin line); `597533e` adds
   `supabase/tests/176_my_tickets_read.sql`. Both would run, but the numbering no longer identifies a
   test — renumber one before merging.
3. **A new migration version lands after the four payment migrations.** `20260909000000` sorts last in
   the canonical chain, making it 140 migrations. The rehearsal in §6 covers 139; it must be re-run.

Recommended order of operations: land this convergence first, then rebase the two UI commits on top of
it, renumber the test, set `EXPECT_FUNCS: 88` (and `162`'s P2 assertion to 88), and re-run
`scripts/release/convergence_prod_order_rehearsal.sh`.
