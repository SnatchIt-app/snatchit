# Converged release candidate — branch convergence, three-way comparison, policy decision, proofs

Branch `release/payments-converged-rc` (worktree `snatchit-rc`). Base: Phase-2 commit
`10ad9e4280c48d8e7283ba3b1e804f6625df662b` = the state production runs (see §1). Merged:
PR #54 head `31128c160fbec88c37f4628547baa3149f2dbea7`. Everything below was verified against
files at those commits, not against agent summaries (the three review reports are in `rc/`).

## 1. What production actually runs (read-only inspection, 2026-09-06)

| Surface | Production | `main` (eadd456) | Phase-2 `10ad9e4` |
|---|---|---|---|
| Migration ledger | 124 versions: 000..075, 4× 202607/08 website forms, 076..109, `20260902003623` | 89 versions (through 075 + website forms) | identical to production (110..114 exist only in later commits, never applied) |
| `create-payment-intent` v45 | Phase-2 F-5 acquisition guard | lacks the guard | byte-identical to production |
| `confirm-and-release` v34 | Phase-2 F-5 inbound-transfer guard | lacks the guard | byte-identical |
| `delete-account` v19 | OR-17 tombstone (kernel.request/withdraw_account_deletion) | physical delete | byte-identical |
| `stripe-webhook` v39, `confirm-payment` v34, `enforce-transfer-expiry` v36 | = `main` | = production | **webhook differs**: a native-rail arm (`native.ts`, `native-dispute.ts`, `metadata.rail` dispatch, kernel/venue clients) that was NEVER deployed |
| `_shared/*` used by the six | = `main` | = production | `offline-verify.ts` extra (unused by the six) |

`main` is one web-only commit ahead of the Phase-2 merge-base (eadd456: public events API + three
`packages/*/tsconfig.json`), so `main` ⊂ RC except that commit's web files, which merge cleanly.

**Consequence.** PR #54 as originally cut (main + packages) would have REGRESSED production: it
re-deployed a physical-delete `delete-account` and edges without the deletion guards. The RC is
built from production's commit instead and carries `main`'s payments work on top. Full detail:
`rc/R1_edge_three_way_comparison.md`.

## 2. Production-only behaviours and how each survives

| Behaviour (production) | In RC | Proof |
|---|---|---|
| F-5 acquisition guard in `create-payment-intent` (kernel.is_deletion_pending → 403, fail-open pre-077) | kept verbatim (auto-merged; sits after auth/rate-limit, before the draft's reservation checks) | `git diff 10ad9e4 -- supabase/functions/create-payment-intent` shows only P1 additions |
| F-5 inbound-transfer guard in `confirm-and-release` (caller-JWT `kernel.identity_ext` read) | kept verbatim | same |
| OR-17 tombstone `delete-account` (request/withdraw, always accepts, `{success:true,…}`) | kept verbatim + additive `pending_obligations` / `obligations_check` | `tests/delete-account.test.ts` (11) pins the caller-JWT kernel client, the response shape, no `deleteUser`/`delete_account_cleanup` |
| Phase-2 deletion sweep BP-1..BP-12 precedence and hook semantics | untouched; BP-13 appended LAST | `141_phase2_identity_orgs_deletion.sql` 213/213 (O24 BP-7, O25 BP-6, Q3 hooks NULL), `125` 28/28 |
| Phase-2 native webhook arm | **NOT carried** (never deployed; paused expansion) | RC webhook = deployed + P2/P3 only |

## 3. The one business-policy decision (owner)

**Question.** When a person requests account deletion while they still have an unsettled live-rail
money obligation (a paid order with no transfer, an unpaid payout, a pending refund, an open
dispute or review), should the request be (A) refused with 409 until it settles, or (B) accepted
into DELETION_PENDING with the obligation enforced at the terminal?

- **(A) Refuse at request time** — the draft PR #54 semantics (fail-closed 409, blockers listed;
  the independent edge reviewer also recommended this). Changes the ratified OR-17 "always
  accepts" machine and the deployed client contract (`{success:true}` on request); leaves a
  person unable to start the grace window for obligations only the platform can settle (a held
  payout, a pending refund).
- **(B) Accept, enforce at the terminal** — **IMPLEMENTED.** `kernel.request_account_deletion`
  keeps always-accepting; the sweep gains BP-13 (`public.account_deletion_block_reason`), evaluated
  after BP-1..BP-12, so no identity with an unsettled live-rail obligation is ever tombstoned; the
  edge returns the same predicate as `pending_obligations` (informational) so the client can say
  what must settle. A predicate read failure at the edge does not block the request (the terminal
  re-checks, fail-closed); a predicate failure inside the sweep fails that identity closed.

**Recommendation: (B).** It preserves deployed behaviour, the ratified machine and build-13
compatibility, and it protects the money at the only place erasure actually happens. Switching to
(A) is a small, isolated edge change (refuse when `pending_obligations` is non-empty) that can be
made later without touching the database. Both protections are proven in `125` (§4).

## 4. Both protections remain effective — `supabase/tests/125_deletion_sweep_live_rail.sql` (28)

1. Sweep body = 078 verbatim + one BP-13 call site after BP-12; every hook untouched (no BP-13 text
   in any `kernel.deletion_blockers_*`); `account_deletion_block_reason` is service_role-only.
2. Predicate: NULL for a clean identity; `BP-13: … (paid_no_transfer)` / `(active_transfer)` for
   obligated ones; the money HOOK stays NULL for the same identity.
3. End to end: request accepted (OR-17) → sweep tombstones NOTHING, records `BP-13: …
   paid_no_transfer` → full refund via `record_payment_refund` → predicate NULL → sweep tombstones
   → `deletion_state = ERASED`.
4. Phase-2 arm still fires after BP-13 is added: an identity with only a live reservation is held on
   BP-8. Plus 141 (BP-7/BP-6 order, Q3) unchanged.

## 5. Independent review dispositions (round 2)

| Report | Finding | Disposition | Where |
|---|---|---|---|
| R1 edges | production-only behaviours (3 edges) must survive | ACCEPTED — §2 | delete-account, guards |
| R1 edges | request-time 409 gate | NOT ADOPTED — policy (B), §3 | — |
| R2 financial | MAJOR-1 native_primary shape breaks guard / blockers / contract | FIXED: NULL-safe guard; `not_external_rail` outcome (no writes); external-rail-only blockers and work list; confirm-payment 409 | 120000, 110000, confirm-payment; 121/123/124 R2 tests |
| R2 | MAJOR-2 refund after payout never flags reversal | FIXED: `record_payment_refund` → `flag_payout_reversal_required` (`REFUNDED_AFTER_PAYOUT` / `PARTIAL_REFUND_AFTER_PAYOUT`) | 120000; 122 R2 |
| R2 | MINOR-3 payout ignores partial refunds | FIXED: `PAYMENT_PARTIALLY_REFUNDED` refuses automatic payout (owner decision, playbook) | 120000, payouts.ts; 122 R2 |
| R2 | MINOR-4 cumulative refund double-ledgered | FIXED: contract ledgers the increment under the newest refund id | 110000; 121 R2-B |
| R2 | MINOR-5 dispute freeze failure ACKed; no last-moment re-check | FIXED: non-2xx; `mark_payout_requested` re-checks dispute/refund/paid | webhook, 120000; 122 R2, vitest |
| R2 | MINOR-6 captures >2h after PI creation fall off `pending_stale` | OPEN (documented): the 15 min–2 h window is a deliberate review-round-1 choice; late captures are covered by the buyer's `confirm-payment` and by `account_deletion_blockers.pending_payment`; a widened window with Stripe-side PI cancellation is a follow-up | 04 §6 |
| R2 | NOTE-7 deploy-window double payout | MITIGATED: legacy-aware pre-flight (below) + release step "pause payout cron during P3-d" | payouts.ts, 04 §1 |
| R2 | NOTE-8/9 alerts for review rows; `reversal_required` after a won dispute | OPEN (ops follow-ups) | 04 §6 |
| R3 release | 132 deltas = database-name literal; CI green because its DB is `postgres` | FIXED: `current_database()`; `known_notok` list empty | 132, rehearsal_test.sh |
| R3 | legacy orphan double-pay on first new-code payout | FIXED: `findTransferByLegacyMetadata` (destination listing, `metadata.transfer_id`) before every first POST; listing failure ⇒ no POST | payouts.ts; payout-races (3 new) |
| R3 | open attempt at rollback time ⇒ old edge re-POSTs | PROCEDURE: drain → export → roll back (rehearsed, §6 F) | 04 §3, rehearsal script |
| R3 | MIN_FILES/MIN_ASSERTIONS stale; rollbacks never run in CI | FIXED ratchets 59/4046; rollback rehearsal is a release-time script (CI follow-up) | ci.yml |

## 6. Proofs (all local, isolated; nothing against production)

- **Fresh replay of the full converged chain**: 128/128, `GATE-2 30|86|37|32`; full pgTAP
  **4046/4046** (59 files, incl. every Phase-2 suite); vitest **854/854**; typecheck clean.
- **Reverse rollback 4→3→2→1→reapply** on the RC chain: census and function hash invert exactly at
  every step and return to the fresh hash; second apply idempotent.
- **Production-order upgrade rehearsal** (`scripts/release/payments_rc_prod_order_rehearsal.sh`,
  **51/51**): production's 124 versions in production's order (`27|70|37|26`), legacy live data
  seeded (paid via `record_transfer_payout`, released-unpaid, in-flight pending checkout,
  paid-but-unsettled capture, a DELETION_PENDING buyer held on BP-7); the four migrations applied
  → `30|86|37|32`, **zero live-row mutation**, function definitions identical to the fresh replay.
- **Intermediate states**: old webhook (promote → `mark_listing_sold` → its own transfer INSERT
  colliding benignly) ✓; old client `reserve_buy_now(…, p_minutes)` accepted, window server-fixed ✓;
  old `confirm-payment` writes then the NEW webhook settles with ONE transfer ✓; old
  `confirm-and-release` (`record_transfer_payout`) still records, new claim ⇒ `ALREADY_RELEASED` ✓;
  paid-unsettled legacy capture listed and settled ✓; deploy-window races: same tr_ recorded by
  both codes ⇒ no review; two different tr_ ⇒ `reversal_required` + `DUPLICATE_TRANSFER` ✓; kernel
  sweep unchanged for the buyer (BP-7 before BP-13) ✓; BP-13 names the seller's obligations ✓.
- **Rollback with new financial records**: drain (open attempt → failed), export four CSVs, roll
  back 4→1 → census/hash = pre-upgrade, **every transfer keeps its tr_/payout_released_at**,
  settled listings stay sold, old `record_transfer_payout` works, deletion machine intact,
  `amount_refunded_cents` gone (CSV = ledger of record) → re-apply → re-import (row counts equal)
  → the re-imported ledger sees the legacy-paid transfer as `ALREADY_RELEASED`.

## 7. Not executed here (and the minimum to do it)

- **Stripe sandbox end-to-end.** No non-production Supabase project exists (the only project is
  production; "Never treat the existing Supabase project as staging"). Minimum: a second Supabase
  project (Pro plan for Branching or a plain free project) linked to a Stripe **test-mode** account
  with Connect enabled; `supabase db push` of the RC chain; deploy the seven edges with test keys;
  a Stripe test webhook endpoint subscribed to the eleven events (`08_STRIPE_WEBHOOK_SUBSCRIPTION.md`);
  one buyer + one Connect test seller; run: buy-now → PaymentSheet 3DS card → webhook settles →
  confirm-and-release payout → refund → dispute (`4000000000000259`) → account deletion request +
  sweep. Expected DB facts are the same assertions the pgTAP suites make.
- **Device runs** (PaymentSheet, Apple Pay): same environment; build 13 against the test project.
- **Deno type-check** locally (no Deno on this host): CI job `deno-check`.
