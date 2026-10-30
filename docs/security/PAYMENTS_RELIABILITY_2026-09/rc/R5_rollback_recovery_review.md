# RC2 review B — rollback & recovery integrity (20260906100000..130000), partial-refund focus

Read-only. Worktree `/Users/josetascon/snatchit-rc` @ 5e3cbc7 (code = 972619f). Evidence DBs (dropped after): `snatchit_rbrev_rehearsal` (full `payments_rc_prod_order_rehearsal.sh` run: **51/51 PASS**, log `scratchpad/rbrev_prodsim.log`) and `snatchit_rbrev2_rehearsal` (all migrations via `scripts/rehearsal_reset.sh`, then fixtures T1..T10 → detection → archive prototype → rollback 4→1 → old-code SQL replicas → re-apply → restore → checks). Scripts/outputs: `scratchpad/rbrev_0{1,1b,2,3,4}_*.sql|.out`, `rbrev_05_followup.out`, `rbrev_06_ordering.out`, `rbrev_rollback.out`, `rbrev_reapply.out`.

Deployed-edge references = `scratchpad/deployed/<fn>/<fn>/index.ts` (production source). Old payout idempotency key = `payout_${transferId}_${destination}_src` (10ad9e4 `_shared/payout-logic.ts:24-26`, used at `payouts.ts:135`; the old POST carries **no `transfer_group`**). New key = `payout_${transferId}_a${attemptNo}` (`payout-logic.ts:27-31`).

**Premise correction.** The deployed `stripe-webhook` `charge.refunded` branch (`index.ts:705-735`) marks the payment `refunded` on **any** `charge.refunded`, partial included — it never reads `amount_refunded` (grep: no match). Old-code semantics for a partial refund are therefore "seller gets nothing" (status ≠ succeeded → `confirm-and-release:426-431` PAYMENT_NOT_SUCCEEDED manual_review), not "only full refunds". The rollback hazard is the *opposite* direction for facts the NEW code recorded (below).

---

## 1. Inventory — new-code state lost / orphaned / re-interpreted per rollback

Census: 30|86|37|32 → 27|70|37|26 (prodsim F4). Rollback order tested 130000→120000→110000→100000 (`rbrev_rollback.out`, 0 errors).

### 130000 rollback (`20260906130000_…_rollback.sql:7-208`)
| State | Fate | Old-code re-interpretation | Evidence |
|---|---|---|---|
| BP-13 arm in `kernel.sweep_deletion_pending` (mig `130000:159-168`) | removed (body → 078 verbatim) | identities held ONLY by BP-13 (paid_no_transfer, unpaid_seller_obligation, pending_refund, unresolved_review, open_payout_attempt, open_manual_review, pending_payment) are **tombstoned next tick**: ERASED is terminal (PFA-3), org roles deleted, listings cancelled | D6 → S6: `other_user` DELETION_PENDING/BP-13 → after rollback `{"tombstoned":1}`, `ERASED`, still party to 1 unsettled transfer + 1 captured-pending payment (`rbrev_03_post.out`) |
| `identity_ext.deletion_block_reason = 'BP-13…'` | text survives until next sweep overwrites/clears | n/a | — |
| `public.account_deletion_block_reason` | dropped | none | — |
| Header claim "Package 3 predicate unaffected" (`:5-6`) | true only in 4→3 order; see §4 ordering | | O2 |

### 120000 rollback (`20260906120000_…_rollback.sql:29-73`, single txn)
| State | Fate | Old-code re-interpretation | Evidence |
|---|---|---|---|
| `payments.amount_refunded_cents` (mig `:306`) | **DROPPED with values** (`:64-71`; header `:13-16` says "by design") | old edges read `amount, seller_fee, status` only (`confirm-and-release:405-409`, `expiry:525-526`); a partially refunded `succeeded` row is paid **full seller net** | S1: T1 `pi_fixture_b` 2500 refunded → post-rollback `seller_net_cents_old_edge_pays=9000`, `record_transfer_payout(...)=t`; C8 |
| `payment_refunds` (append-only ledger, `:308-339`) | DROPPED (`:57`) | no old reader; per-refund amounts/ids unrecoverable from DB | F3 CSV only |
| `payout_attempts` all states (`:174-205`) | DROPPED (`:58`) incl. `claimed/requested/unknown` (in-flight POST, lease, key), `succeeded` (key+frozen params), `failed`, `reversal_required` | old Phase 2b (`expiry:791-806`) re-selects every `auto_released/buyer_confirmed` row with `stripe_transfer_id IS NULL` and POSTs under the **old key** → second Stripe transfer for any attempt whose a1 POST actually landed; nothing in DB can detect it | D1 (E requested, F unknown) → S2 lists E,F as candidates; C5 |
| `payout_attempts.state='reversal_required'` (mig `:766-815, 869-873`) | DROPPED; the paired `payout_decisions` row survives (039 table) with `evidence.attempt_id` dangling | old edges only READ `payout_decisions` to dedupe their own insert (`confirm-and-release:367-374`, `expiry:584-591`); **never a gate**; no reversal worker exists | D5/D9 → S3 |
| `payout_decisions` manual_review rows w/ new reason codes (PAID_DURING_DISPUTE, DUPLICATE_TRANSFER, REFUNDED_AFTER_PAYOUT, PARTIAL_REFUND_AFTER_PAYOUT, DISPUTE_LOST_AFTER_PAYOUT) | survive | side effect: old `recordManualReviewOnce`/`payoutDeferred` skip their own row (any prior manual_review exists) — later old-code failures become log-only | S3 |
| `account_deletions` phase ledger (`:989-1005`) | DROPPED (`:56`) | deployed delete-account is the OR-17 tombstone flow (does not use it) → mid-flow rows (phase archived/cleaned/storage) simply vanish; users half-cleaned have no record | D7 → S7 |
| `transfers_stripe_transfer_id_uniq` (`:297-299`) | DROPPED (`:61`) | F-2 reopens: two rows may carry one `tr_`; **re-apply aborts** (`:285-295`) until fixed by hand | S10 → re-apply ERROR "duplicates (tr_WINDOW_DUP x2)" |
| `trg_guard_payment_transitions`, `trg_reset_payment_guard_bypass`, GUC `app.bypass_payment_guard` (`:350-452`) | DROPPED | `refunded` no longer terminal: deployed webhook `payment_intent.succeeded` (`:267-273`, `.neq('status','succeeded')`) and confirm-payment (`:215-224`, no status predicate) can flip refunded→succeeded on a late/replayed event → row becomes payable | S8/S9: `pi_m1` refunded → `succeeded` |
| RPCs `record_payment_refund`, `claim_…`, `mark_payout_requested`, `record_payout_attempt_result`, `reconcile_…`, `flag_payout_reversal_required`, `account_deletion_blockers` | DROPPED (`:40-46`) | new edges → PGRST202 (fail-closed for payouts; **500 loop for webhook charge.refunded/dispute.closed** until old webhook redeployed) | header `:8-11` |
| Refund monotonicity on `stripe_refund_id/refunded_at` (`:418-422`) | gone | old webhook overwrites nothing (`.neq refunded`) but records only `refunds.data[0].id` | — |

### 110000 rollback (`20260906110000_…_rollback.sql:27-48`, **autocommit, no txn**)
| State | Fate | Old-code re-interpretation | Evidence |
|---|---|---|---|
| `webhook_retries` review rows `unknown_payment:*`, `binding_mismatch:*`, `unfulfillable:*` (mig `110000:158-170, 210-224, 318-342`) | survive (069 table) | **no deployed edge reads `webhook_retries`** (grep of all 6 deployed index.ts: none) → `unfulfillable` = buyer charged, listing sold to another, no transfer → old expiry Phase 1 refunds only `status='expired'` transfers (`expiry:185-231`) → **captured money orphaned forever**; `binding_mismatch` pending rows: old create-payment-intent may retire (pending→failed), buyer charged | D3 → S4 (`pi_h2` pending, 0 transfers, unresolved) |
| `payments.status='failed'` + `failed_at` from `settle_verified_payment('canceled')` (`:286-294`) | survive as data | old code treats `failed` as re-mintable (webhook payment_failed no-op); harmless | T7 |
| `cleanup_expired_reservations` N1 guard (`:426-447`) | reverted to 000 body | paid-but-unsettled listing with lapsed hold is **re-listed**; old `reserve_buy_now` hands it to a second buyer for `p_minutes` (unbounded); old `mark_listing_sold` refuses the payer ("not reserved by you") | D4 → S5: listing I active → reserved by `admin_user` 10 h → payer refused |
| `get_unsettled_payments` work list | dropped | reconciliation sweep gone; F02 backlog (D4: `pi_fixture_a/b`, `pi_i1`) has no settler except client `confirm-payment` | D4 |
| `settle_verified_payment` promotion `paid_at/payment_method` coalesce | data survives | — | F7 |

### 100000 rollback (`20260906100000_…_rollback.sql:23-124`, autocommit)
| State | Fate | Old-code re-interpretation | Evidence |
|---|---|---|---|
| Reservations made under fixed 10-min rule | rows valid | old `reserve_buy_now` (`:76-112`): `p_minutes` unbounded, re-call extends, multi-hold, no rate limit (F04) | E2a'/S5 |
| `rate_limits` rows for action `reserve_buy_now` | survive | harmless | — |
| "sold in fact" (succeeded payment ⇒ unreservable; `100000:292-295, 306-310, 333-336`) | gone | paid rows sweepable/reservable again (MAJOR-1 reopens) | S5 |
| `settle_listing_for_payment` | DROPPED (`:124`) | if 110000 still applied → `settle_verified_payment` fails at **runtime** only | O1 |
| `mark_listing_sold` payment gate (`100000:193-203`) | 0590 body: reservation-holder gate, no payment check (F03) | | — |
| Transfers created by the core (`ON CONFLICT (payment_id) DO NOTHING`) | survive | old webhook/confirm-payment INSERT collides 23505 → benign | E1c |

---

## 2. Money-safety of OLD code on post-rollback data

**Q: can old confirm-and-release pay FULL seller net on a partially refunded payment? YES, silently.**
Trace (deployed `confirm-and-release/index.ts`): `251-255` selects `transfers(id, seller_id, buyer_id, payment_id, listing_id, status, payout_released_at, disputed_at, payout_risk_tier)` — no `payout_review_status`; gates: `320-325` dispute (`status==='disputed' || disputed_at!==null`), `328-333` `status!=='buyer_confirmed'`, `336-345` `payout_released_at!==null`; `405-409` selects `payments(amount, seller_fee, status, stripe_payment_intent_id)`; `426-431` only `status!=='succeeded'` defers; `460` `sellerNetCents = amount - seller_fee`; `477-485` re-check (status/disputed/payout_released_at); POST; `587-589` `record_transfer_payout` whose WHERE (`0564:58-66`) checks only `stripe_transfer_id IS NULL AND payout_released_at IS NULL AND (disputed_at IS NULL OR dispute_resolution='resolved_seller_paid')`. Same in `enforce-transfer-expiry:525-541, 547-564, 567, 675-679`. The **only** partial-refund gate in the whole system is `claim_payout_attempt` (`120000:637-644` PAYMENT_PARTIALLY_REFUNDED) + `mark_payout_requested` (`:692-694`) — both dropped, and the fact they read is dropped. Proof: S1 (`rbrev_03_post.out`): `pi_fixture_b` refunded 2500 → post-rollback row shows `succeeded / 9000`, `SELECT amount_refunded_cents` → `column does not exist`, `record_transfer_payout(transfer_b,'tr_t1_OLD_FULL_NET') = t`. Platform holds 8500 and pays 9000.

**039 hold semantics — is there any hold the rollback could insert that OLD code honours?** Only for `seller_sent` rows: `apply_manual_review` (`039:254-270`) writes `payout_review_status='manual_review'` **only where `status='seller_sent'`**, and only `get_auto_release_candidates` (`039:157-158, 194-195`) honours it (Phase 2 fresh releases). For `buyer_confirmed`/`auto_released` rows (the D2 set) neither edge reads `payout_review_status`; `apply_manual_review` returns **false** (H test: `f` for both `d1` auto_released and `transfer_b` buyer_confirmed). The only stop every old path honours is the **dispute freeze** `freeze_transfer_for_dispute` (`status='disputed'`, `disputed_at`) — a fabricated dispute with no `disputes` row (H: `frozen=t, real_dispute_rows=0`, Phase-2b candidates → 0). It also blocks buyer confirmation. Conclusion: no legitimate DB hold exists for old code; D2 rows must be **operator-settled before** the rollback (pay reduced net by hand + `record_transfer_payout`, or complete the refund).

**Can old webhook double-record?** `transfer.created` is log-only (`:737-746`) → cannot record payouts at all (so payouts made by the NEW edge whose `record_payout_attempt_result` never ran — the `unknown` class — are never healed; the row stays unpaid → old Phase 2b re-POSTs). `charge.refunded` is idempotent on status (`.neq('status','refunded')`) but marks a **partial** as `refunded` (`:716-724`); under the still-present guard (edge-first window) the write is **REFUSED** when a refund id already exists (T10a: "refund facts are monotonic") → old edge `markProcessed({error})` → event acked → **fact lost**; without a refund id it is accepted (T10b) → `refunded` with `amount_refunded_cents 1000 < 11000` (D8/C6), terminal. `payment_intent.succeeded` `.neq('status','succeeded')` flips a `refunded` row back to `succeeded` once the guard is gone (S8: `pi_m1 → succeeded`) — the "double-record" that matters: a refunded order becomes payable (transfer pending → seller sends → confirm → 9000).

**Can old expiry sweep auto-release something the new code flagged?** YES: (a) every D2 row (partial refund before payout) — new code left it unpaid with **no marker on `transfers`**; old Phase 2b pays it (S2 candidate set). (b) every in-flight/unknown attempt (D1) — re-POST under a different key (E, F in S2). (c) `unfulfillable` payments — not paid (no transfer) but never refunded either (S4). (d) `reversal_required` rows — cannot be re-paid (tr_ set), but the reversal obligation has no worker and the identity can be tombstoned (S6).

---

## 3. Archive-in-rollback design (`rollback_archive`) — prototype ran (`rbrev_02_pre.sql` A-section, `rbrev_04_restore.sql`)

Archive **inside the same transaction as the DROPs** (120000 rollback is already `BEGIN…COMMIT`; 100000/110000/130000 are not — wrap them or run with `psql -1`). Tables (all `CREATE TABLE … AS SELECT *, now() archived_at`):
1. `payments_refund_facts` (id, pi, status, total, amount_refunded_cents, refunded_at, stripe_refund_id, failed_at, paid_at) — WHERE `amount_refunded_cents IS NOT NULL OR status IN ('refunded','failed')`; cheaper and better: **all payments (id,status)** to detect window transitions.
2. `payout_attempts` full rows, **all states** (the `idempotency_key` is the only record of which Stripe key was used).
3. `payment_refunds` full.
4. `account_deletions` full.
5. `payout_decisions_new` (`evidence ? 'attempt_id' OR reason_codes && {new codes}`) — survives anyway; archived for C3 cross-check.
6. `webhook_retries_review` (`rpc_name IN ('settle_verified_payment','transfer.created')`) with `resolved` snapshot.
7. `transfers_money` baseline (id, status, stripe_transfer_id, payout_released_at, disputed_at) — needed for C4/C8 window detection.
8. `listings_reservation` baseline (status, reserved_by, reserved_until) — window re-list/re-sale detection.
9. `identity_bp13` (`identity_ext` rows with BP-13 reason) — C9.
10. `manifest` (archived_at, git commit, ledger versions, counts, operator).
Prototype counts: 5|3|4|1|1|2|1 (`rbrev_02_pre.out`).

Restore (forward migration, guarded `IF to_regclass('rollback_archive.payout_attempts') IS NOT NULL`): `INSERT … ON CONFLICT DO NOTHING` for 2/3/4 (C1 = t); `UPDATE payments SET amount_refunded_cents = archived WHERE current IS NULL` (NULL→x is the one guard-legal transition; C2 = empty); **expire restored leases** (`lease_expires_at = now()`) — otherwise `claim` raises PAYOUT_ATTEMPT_IN_PROGRESS for 10 min (C11 → C11b); leave restored open attempts open so `claim` returns `needs_reconcile=true` (C11b) — but see "cannot".

Completeness SQL (all in `rbrev_04_restore.sql`, must hold before cron re-schedule / edges enabled): C1 counts; C2 `sum(payment_refunds.amount_cents) = amount_refunded_cents`; C3 succeeded/reversal_required attempt `tr_` = row `tr_`; **C4 window payouts** (`t.stripe_transfer_id IS NOT NULL AND baseline NULL AND no attempt with that tr_`) → 3 rows in test; **C5 restored open attempts whose row got a window `tr_`** → 2 rows; **C6 `refunded` with `amount_refunded_cents < total`** → 1; C7 refunded-in-window with no ledger row; **C8 partially refunded payment paid in full in window** → 1 (realized overpayment → needs a REVERSAL decision, not a hold); C9 window tombstones → 1; C10 gate works again (T1 claim → ALREADY_RELEASED).

**Cannot be restored (only Stripe knows):**
- Whether an in-flight `requested`/`unknown` a1 POST created a Stripe transfer. After a window payout under the old key, both `reconcile(NULL)` (→ `failed` while `tr_WINDOW_DUP` sits on the row) and `record_payout_attempt_result(att, row tr)` (→ attributes the old-key transfer to the new-key attempt) **mis-state** the ledger (C11c). Only `GET /v1/transfers?…` filtered by `metadata[transfer_id]` (both old and new POSTs set it) proves 1 vs 2 transfers.
- Frozen params of window payouts (destination/amount/key at POST time) — synthesizable only approximately (`actor='restore:window'`, key `payout_<id>_<dest>_src`).
- The second refund's id/amount when the guard refused the old webhook write (T10a) — not in DB at all.
- `refunded` set on a partial by old webhook (C6) — terminal; correction needs `app.bypass_payment_guard` + Stripe `charge.amount_refunded`.
- Tombstoned identities (C9): ERASED terminal, roles deleted, listings cancelled.
- Listings re-sold in the window (S5): second buyer's hold/payment on a paid listing.
- Anything that happened between archive and DROP if not in one transaction (110000/100000/130000 rollback files).

---

## 4. When rollback becomes unsafe; rollback vs forward-fix per failure class

**Exact point:** the first NEW-code fact that old code re-interprets — in practice the first `payout_attempts` row or first `record_payment_refund` after P3-d (edges deployed). Before P3-d the SQL rollback is data-safe (release plan §1 order). After P3-d, rollback is safe **only if every detector is empty at rollback time and stays empty** (cron unscheduled, payout edges offline, webhook endpoint disabled):
```sql
-- D1 in-flight POSTs (must be 0; reconcile against Stripe by metadata[transfer_id], not transfer_group alone)
SELECT count(*) FROM payout_attempts WHERE state IN ('claimed','requested','unknown');
-- D2 partial refund + unpaid releasable transfer (must be 0; operator-settle BEFORE rollback — no DB hold exists old code honours)
SELECT count(*) FROM payments p JOIN transfers t ON t.payment_id=p.id WHERE coalesce(p.amount_refunded_cents,0)>0 AND p.status='succeeded'
   AND t.stripe_transfer_id IS NULL AND t.payout_released_at IS NULL AND t.status IN ('pending','seller_sent','buyer_confirmed','auto_released');
-- D3 unresolved review rows (unfulfillable must be refunded first; binding_mismatch resolved)
SELECT count(*) FROM webhook_retries WHERE resolved IS NOT TRUE AND rpc_name IN ('settle_verified_payment','transfer.created');
-- D4 paid-unsettled (drain via sweep before 110000 rollback; pre-existing F02 rows are re-listed by 000 cleanup)
SELECT count(*) FROM payments p JOIN listings l ON l.id=p.listing_id WHERE p.status='succeeded' AND p.mode IN ('buy_now','auction') AND l.status<>'sold';
-- D5 reversal obligations (accept only with an operator ticket per row)
SELECT count(*) FROM payout_attempts WHERE state='reversal_required';
-- D6 BP-13-only identities (must be 0 or their deletion withdrawn before 130000 rollback)
SELECT count(*) FROM kernel.identity_ext WHERE deletion_state='DELETION_PENDING' AND deletion_block_reason LIKE 'BP-13%';
-- D7 mid-flight deletions
SELECT count(*) FROM account_deletions WHERE phase<>'done';
-- D8 inconsistent refund facts from the edge-first window
SELECT count(*) FROM payments WHERE status='refunded' AND coalesce(amount_refunded_cents,total)<total;
-- P (re-apply blocker) duplicates created while the unique index was gone
SELECT stripe_transfer_id FROM transfers WHERE stripe_transfer_id IS NOT NULL GROUP BY 1 HAVING count(*)>1;
```
Test values pre-rollback: D1=2, D2=2, D3=2, D4=3, D5=1, D6=1, D7=1, D8=1 (`rbrev_02_pre.out`).

Ordering hazards (`rbrev_06_ordering.out`): 100000 rollback before 110000 → DROP succeeds, `settle_verified_payment` fails at runtime (`function public.settle_listing_for_payment(uuid) does not exist`) — every webhook/confirm-payment 500s. 120000 rollback before 130000 → `account_deletion_block_reason` still present, raises per identity inside the sweep → fails closed (`WARNING … account_deletion_blockers(uuid) does not exist`, identity stays DELETION_PENDING with **no reason recorded**).

| Failure class | Rollback | Forward-fix | Recommendation |
|---|---|---|---|
| Bad edge | Edge-only revert. For `create-payment-intent`/`delete-account`: fine (schema is a superset). For `confirm-and-release`/`enforce-transfer-expiry`: reverting reopens D2 overpay + F07/F08 (old edges never call `claim_payout_attempt`) → not clean. For `stripe-webhook`: old branch loses partial facts under the guard (T10a) and 500-loops on refunded→succeeded redeliveries. | Hotfix edge; meanwhile kill switch = `cron.unschedule` + `REVOKE EXECUTE ON claim_payout_attempt FROM service_role` (instant, reversible, keeps ledger) or disable the Stripe endpoint (3-day retry buffer). | **Forward-fix**; edge revert only for P1/delete-account edges. Never touch SQL. |
| Bad RPC logic | Package rollback drops ledgers to fix a body. | `CREATE OR REPLACE` body-only hotfix migration (+ its own rollback = previous body). If money-moving: REVOKE EXECUTE first. | **Forward-fix**. |
| Bad schema (guard/index too strict, blocks a legit writer) | Package rollback. | `ALTER TABLE … DISABLE TRIGGER trg_guard_payment_transitions` / `DROP INDEX` of the one object; keep column+ledgers. | **Forward-fix (surgical)**; package rollback only if the offending object cannot be isolated, and only with D1..D8 = 0. |
| Data corruption (wrong facts written by new code) | Destroys the ledger needed to diagnose; old code re-interprets survivors (S1, S5, S8). | Freeze workers, correct with `app.bypass_payment_guard`/`bypass_transfer_guard` + audit row (`payout_decisions`/`webhook_retries`), re-enable. | **Never rollback.** |

Net: rollback is an option only in the P3-b..P3-d gap; after the first live payout attempt or refund it is an incident amplifier, and the release plan should say so (§3 line 68 currently reads as a supported path "51/51").

---

## 5. Gaps in `scripts/release/payments_rc_prod_order_rehearsal.sh` §F (lines 190-231) vs the above

1. **Partial-refund overpay untested.** F0 (`:193`) refunds `pi_legacy_e`, whose transfer is `pending`; F8 (`:219`) pays E5, which has no refund. No assertion that old code pays 9000 on a 2500-refunded `buyer_confirmed`/`auto_released` row (S1). F10 (`:223`) only asserts the column is gone.
2. **Drain covers one `requested` attempt reconciled to `failed`** (`:199-205`); no `unknown` state, no lapsed-lease attempt, no "a1 POST landed but was never recorded" case → the double-POST class (S2/C5) is never exercised, and `reconcile(NULL)` is asserted as the answer although the old key/no-`transfer_group` search cannot prove absence.
3. **No pre-rollback gates for D2/D3/D4/D5/D6/D7/D8** — only D1 (F2'). The `unknown_payment` review row created at `:195` is left orphaned with no assertion; no paid-unsettled drain before the 110000 rollback.
4. **F14 (`:230`) is a hand-typed `UPDATE … = 500`**, not a restore from `payments_refunded.csv`; no C2 check (ledger sum = column); `account_deletions.csv` exported (`:210`) but never re-imported.
5. **No window simulation**: nothing runs old-code writes between rollback and re-apply (S5 re-list/re-sale, S8 resurrect, S10 duplicate `tr_` → re-apply abort, T10 guard-refused webhook write). F15 (`:231`) shows a window payout (`tr_post_rb`) but does not flag that it has **no attempt row** (C4) nor that a restored open attempt on the same transfer would need Stripe evidence (C5).
6. **F9 (`:222`) checks only the buyer (BP-7-held)**; no BP-13-only identity → the 130000 tombstone regression (S6) is invisible. E8b proves BP-13 fires pre-rollback but nobody is released by its removal in the fixture.
7. **Rollback files run without `-1`** (`:214`); 100000/110000/130000 rollbacks have no `BEGIN/COMMIT` → a mid-file failure leaves a half-restored function set; not rehearsed. Out-of-order runs (O1/O2) not rehearsed (negative tests).
8. `MONEY_BEFORE` (`:212`) and F6 cover `tr_`/`payout_released_at` only — refund facts (`amount_refunded_cents`, `payment_refunds`) are explicitly *not* "money facts" in F6 although they change what is owed.
9. Old-webhook semantics on the new schema in the edge-first window (T10a/b) are not in §E or §F: the rehearsal assumes old edges are "compatible" because their writes are accepted, but the refund-reference guard refuses the deployed `charge.refunded` write whenever a refund id already exists.
10. Release plan §3 (`04_RELEASE_PLAN.md:66-70`) rows P1/P2/130000 carry no drain preconditions; P2's "review rows stay (harmless, ops-visible)" (`:69`) is wrong for `unfulfillable` rows (captured money with no refunder, S4); P3 (`:68`) says "money facts on transfers SURVIVE" — true, and incomplete (refund facts do not).
