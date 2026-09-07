# RC2 — Agent C: mixed-version (non-atomic edge deploy) compatibility review

Read-only. Code: `/Users/josetascon/snatchit-rc` @ `972619f` (HEAD `5e3cbc7` = docs only; `git diff --stat 972619f HEAD -- supabase/` empty).
OLD = production byte copies under `scratchpad/deployed/<fn>/<fn>/index.ts` (v45/v34/v39/v34/v36/v19 per `00_BASELINE.md:36-46`); OLD `_shared/payouts.ts`
= `git show eadd456:…` (baseline says `_shared/*` identical to main). NEW schema = all four `20260906*` migrations.
psql evidence: rehearsal DB `snatchit_mixrev_rehearsal` (all 128 migrations, LC_ALL=C order; Gate-2 30|86|37|32), fixtures `tap.seed_core()` + extras;
transcripts `scratchpad/mixrev_scenarios.out` (X1–X16) and `scratchpad/mixrev_scenarios2.out` (X11/X12/X17/X18 redo, Q1–Q15). DB dropped after writing this.
Section E of `scripts/release/payments_rc_prod_order_rehearsal.sh:124-187` (E1–E8) is NOT repeated; cited where it already proves a cell.

Abbreviations: CPI create-payment-intent · CP confirm-payment · WH stripe-webhook · ETE enforce-transfer-expiry · CR confirm-and-release · DA delete-account.
Migrations: P1 = `…100000`, P2 = `…110000`, P3 = `…120000`, P3b = `…130000`.

---

## 1. Per-edge write inventory (OLD vs NEW) and whether the NEW schema accepts the OLD call

### 1.1 Inventory

| Edge | OLD writes (deployed) | NEW writes (972619f) | NEW schema accepts OLD call? |
|---|---|---|---|
| CPI | `payments` INSERT pending (`:571`); UPDATE `status='failed'` on a dead pending row (`:467`, predicate `status='pending'`); reads `check_rate_limit`(`:39`), `kernel.is_deletion_pending`(`:268`), `listings`(`:298`; checks only `status==='reserved'`, **never the holder**, `:330`) | same INSERT (`:756`) + retire UPDATEs `pending→failed` after a Stripe cancel succeeded (`:253`, `:616`, `:647`, via `retirePendingIntents :229-262` / `cancelPaymentIntentBestEffort :267-285`); reads succeeded rows for sold-in-fact (`:435`) | YES. `pending→failed` and INSERT are unguarded/allowed (`120000:350-437`). No RPC signature involved. |
| CP | `payments` UPDATE `status='succeeded', paid_at, payment_method` WHERE pi AND buyer — **no status predicate** (`:217-224`); `transfers` INSERT direct (`:261`) | ONE RPC `settle_verified_payment(...)` (`:269-280`); 403 when caller ≠ PI buyer (`:240-263`); 500 on RPC error (`:292-302`) | YES with one refusal: `refunded→succeeded` now RAISES (X1/X2c: `payments.status transition refunded -> succeeded is not allowed`); old code logs and continues (`:226`). `succeeded→succeeded` rewriting `paid_at/payment_method` accepted (X2a); `failed→succeeded` accepted (X2b). Direct transfer INSERT accepted (E2b) and later adopted by the core (E2c', X17). |
| WH | lease `claim/complete/fail_stripe_webhook_event` (`:182,:232,:237`); `payment_intent.succeeded`: UPDATE `succeeded` WHERE `status<>'succeeded'` (`:268-273`) → `mark_listing_sold`/`complete_auction_payment(metadata.listing_id, metadata.buyer_id)` (`:405`) → `transfers` INSERT (`:435`, 23505 benign); fallback branch INSERT from metadata (`:332`); `payment_failed`: UPDATE `failed` WHERE not succeeded/refunded (`:509-514`), `release_reservation` (`:537`); `dispute.created`: `freeze_transfer_for_dispute` (`:609`), `disputes` upsert (`:631`); `dispute.closed`: `disputes` UPDATE (`:674`), lost → `payments` UPDATE `refunded, refunded_at` WHERE `status<>'refunded'` (`:692-696`); `charge.refunded`: `payments` UPDATE `refunded, refunded_at, stripe_refund_id?` WHERE `status<>'refunded'` (`:717-724`); `transfer.created`: log only (`:737-746`); `transfer.reversed`: `mark_transfer_reversed` (`:756`); `payout.*`, `account.updated` (`:772-860`); unknown type → ack (`:862-865`) | same lease; `payment_intent.succeeded` → `settle_verified_payment` (`:286-297`; non-settling outcomes are terminal 200, RPC errors 500); `payment_failed` **or** `payment_intent.canceled` → UPDATE `failed` WHERE `status NOT IN (succeeded,refunded)` (`:370-374`), `release_reservation` (`:398`); dispute.created freeze failure now 500 (`:476-483`); dispute.closed lost → `record_payment_refund(pi, NULL, dispute_id, amount, 'dispute_lost')` (`:616-622`) + `flag_payout_reversal_required` on a paid transfer (`:636-640`); `charge.refunded` → per-refund `record_payment_refund` (`:690-696`, charge re-fetched with `expand[]=refunds` `:675-682`); `transfer.created` with `metadata.attempt_id` → `record_payout_attempt_result(...,'succeeded')` (`:727-732`), unknown attempt → `webhook_retries` review row + 200 (`:740-756`) | YES except: (a) `payment_intent.succeeded` on a `refunded` row → UPDATE RAISES → `finish(false)` → **500 retry loop** until WH-new (X1; contract answers `refunded`, 200 — X1b). (b) `mark_listing_sold(listing, metadata.buyer_id)` is now payment-gated (P1): passes when metadata buyer = row buyer (X11d, E1), RAISES `No verified payment found…` when metadata is not the row's buyer (X11) → 500 loop until WH-new (contract → `binding_mismatch`, 200 + review row, X11c/d). (c) dispute-lost / charge.refunded direct UPDATEs accepted (`succeeded→refunded`, `pending→refunded` allowed `120000:392-399`; X3a, X4a) but write no `payment_refunds` row / `amount_refunded_cents`; a later `record_payment_refund` with the same `re_`/`dp_` id heals both (X3a2/3, X4b/c). (d) `transfers` INSERT on a listing the core already settled → 23505, treated as success (E1c). |
| ETE | Phase 1 `enforce_transfer_expiry()` (`:188`), Stripe `/refunds` key `refund_expiry_<transfer_id>` (`:259-270`), `payments` UPDATE `refunded, refunded_at, stripe_refund_id` **by id, no predicate** (`:277-283`); Phase 1b query `payments.stripe_refund_id IS NULL` (`:367-374`), UPDATE WHERE `status='succeeded'` (`:398-406`), quarantine `stripe_livemode=false` (`:422-425`); Phase 2 `get_auto_release_candidates` (`:723`), `apply_auto_release/apply_payout_hold/apply_manual_review` (`:739-763`), `payout_decisions` INSERT (`:480`, `:592`); payout = `createSellerPayout` (old key `payout_<transfer>_<destination>_src`, `payout-logic.ts@eadd456:24-26`; POST body has `source_transaction` + `metadata[transfer_id]`, **no `transfer_group`, no attempt id**, `payouts.ts@eadd456:135-143`) then `record_transfer_payout` (`:676`); Phase 2b `transfers` query `status in (auto_released,buyer_confirmed) AND stripe_transfer_id IS NULL AND payout_released_at IS NULL AND disputed_at IS NULL` (+15-min quiet for buyer_confirmed) (`:792-808`) | **Phase 0 (new)**: `get_unsettled_payments(50)` (`:271`), Stripe GET per row, `settle_verified_payment` (`:305`), `webhook_retries` resolve/mark (`:333,:342,:366,:386`), `retireOtherPendingIntents` cancels + `pending→failed` (`:222-259`), unfulfillable → Stripe `/refunds` key `refund_unfulfillable_<payment_id>` (`:405-412`) + `record_payment_refund(...,'unfulfillable')` (`:417-423`; fallback direct UPDATE only if the RPC is missing `:425-446`); Phase 1 same RPC + `record_payment_refund(...,'expiry')` (`:573-579`); Phase 1b query without the `stripe_refund_id IS NULL` filter (`:665-670`), skip by `fullyRefunded()` (`:209-210`, `:679`), `record_payment_refund` (`:697`); Phase 2/2b via `executePayoutAttempt` (`_shared/payouts.ts:354-512`: `claim_payout_attempt :360` → `findTransferByAttempt` / `reconcile_payout_attempt :393` → legacy pre-flight `findTransferByLegacyMetadata :404-424` → `mark_payout_requested :444` → POST with `transfer_group`, `metadata[attempt_id]`, key `payout_<id>_a<n>` (`:172-186`, `payout-logic.ts:27-32`) → `record_payout_attempt_result :453/:478/:504`); Phase 2b also sweeps expired-lease `payout_attempts` (`:1091-1112`) | YES except: Phase 1 unpredicated UPDATE on a row already refunded by new code RAISES (`refund facts are monotonic`) even with the same `re_` id because `refunded_at` changes (X6, X6b) — old code logs and counts refunded (`:285-293`); unreachable in practice because `:230-239` skips `status='refunded' OR stripe_refund_id` first. Phase 1b OLD predicate excludes partially-refunded rows (X7c=0 vs NEW X7d=1) — divergence, no double money. Payout path: `record_transfer_payout` unchanged (E4, X13). Old code never reads `payout_attempts` (X14c) — see §1.2 row 3. |
| CR | `confirm_transfer_received` (`:206`); reads transfer/payment/profile (`:252,:406,:435`), final recheck (`:477`); `createSellerPayout` (old key) → `record_transfer_payout` (`:587`); `payout_decisions` INSERT (`:375`, `:626`) | `confirm_transfer_received` (`:197`); `executePayoutAttempt` (`:386`); `payout_decisions` (`:357`, `:401`) | YES (`record_transfer_payout` body unchanged, `0561`; E4, X13). New `transfers_stripe_transfer_id_uniq` (`120000:297`) only bites if two transfer rows receive one `tr_` — impossible with the per-transfer key. |
| DA | `check_rate_limit` (`:94`); `kernel.request_account_deletion` / `withdraw_account_deletion` via caller JWT (`:162`). No money writes. | + read-only `account_deletion_blockers(p_user_id)` (`:139`), errors → `obligations_check:'unavailable'` and the request still proceeds (`:126-153`) | YES (nothing changes for OLD). NEW is deployable before P3 (degrades to `unavailable`). |

Unchanged RPC bodies the OLD edges depend on — none is redefined by the four RC files (grep of `CREATE … FUNCTION` in `20260906*` lists only the new/renamed set); md5 census X15: `record_transfer_payout b934ff16`, `ensure_transfer_exists cab98cf6`, `release_reservation 7ffb369e`, `enforce_transfer_expiry 7b5bc6ed`, `apply_auto_release 51398b5b`, `get_auto_release_candidates 37703553`, `claim/complete/fail_stripe_webhook_event 4b735cc8/dc49882c/a170d4d4`, `freeze_transfer_for_dispute d2fd3e85`, `mark_transfer_reversed 4719cfc7`, `confirm_transfer_received 00d318aa`, `check_rate_limit 99f33053`.

### 1.2 Pairwise matrix — (X NEW, Y OLD) sharing a lifecycle

| # | X new | Y old | Shared path | Failure / duplication mode | Verdict |
|---|---|---|---|---|---|
| 1 | WH | CP | payment settle | CP-old promotes with no amount/metadata check (`:217`) and inserts the transfer; listing stays `reserved` until the client's `mark_listing_sold`. WH-new then `settle_verified_payment` → `settled`, adopts the existing transfer (E2c, E2c'; X17). Order reversed (WH-new first): CP-old UPDATE `succeeded→succeeded` is a no-op rewrite (X2a), its INSERT hits 23505 and is logged (`:274-280`). If WH-new returned `binding_mismatch` (amount ≠ total) CP-old still promotes because Stripe said `succeeded` → listing sells via the client's `mark_listing_sold` while the review row stays open → user blocked by `unresolved_review` (X11f) until ops resolves. Refunded row: CP-old raises, logs, then `.single()` finds no succeeded row → 200 (`:245-250`). | Safe. Pre-existing trust gap in CP-old, no new double write. |
| 2 | CP | WH | payment settle | Both lock `payments` FOR UPDATE (contract `110000:§1`) vs WH-old UPDATE → serialize. WH-old first: promote → `mark_listing_sold` (P1 gate passes, E1) → INSERT; CP-new → `already_settled`. CP-new first: WH-old UPDATE matches 0 rows → fallback branch → `transfer_exists` → 200 (`:292-321`). Interleaved (WH-old promoted, CP-new settles between WH's two statements): WH's `mark_listing_sold` → `already_settled`, INSERT 23505 benign. WH-old on `refunded` row → 500 loop (X1) — CP-new is unaffected. | Safe. |
| 3 | CR | ETE | payout | CR-new opens an attempt (key `…_a1`, X14). ETE-old Phase 2b lists the same transfer after 15 min if `stripe_transfer_id` is still NULL (query ignores `payout_attempts`, X14c) and POSTs under the OLD key (`payout_<id>_<acct>_src`, X14d) → **two real Stripe transfers** whenever CR-new's record is late/failed or its attempt is `unknown` (E7 shape: detected as `DUPLICATE_TRANSFER`/`reversal_required`, money already moved). Bound: both POSTs carry `source_transaction` (old `payouts.ts@eadd456:140`, new `:176`); Stripe caps transfers per source charge at the charge amount minus prior transfers, and under 10/10 fees a second `amount−seller_fee` exceeds the remaining `buyer_fee+seller_fee` — expected refusal, **not proven here (no network)**. | **UNSAFE while the cron can fire.** Only the cron pause prevents it (R2 NOTE-7). Fix by ordering: deploy ETE before CR (§3). |
| 4 | ETE | CR | payout | CR-old records via `record_transfer_payout` → ETE-new `claim_payout_attempt` → `ALREADY_RELEASED` (X13, E4b). CR-old "Payout sent but record update failed" (`:600-614`): ETE-new 2b claims after 15 min, legacy pre-flight lists the destination's transfers and matches `metadata.transfer_id` (`payouts.ts:253-292, :404-424`; no lower bound — neither caller passes `createdAfterEpoch`) → `reconcile_payout_attempt` writes the `tr_` → healed, no POST. Residual: buyer re-taps confirm ≥15 min later while a new attempt is `requested` → CR-old passes its recheck (`stripe_transfer_id` NULL, `:477-486`) and POSTs the old key concurrently — same Stripe source-charge bound as #3. | Safe (residual bounded by Stripe). |
| 5 | CPI | CP | reservation / PI | `reserve_buy_now(…, p_minutes)` still accepted, window server-fixed (E2a/E2a'). CPI-new binds the PI to the live holder (`:406-470`) and retires other buyers' pending PIs only after Stripe confirmed the cancel (`:267-285`) → CP-old on a canceled PI: Stripe status ≠ succeeded → writes nothing, 200 `stripe_verified:false` (`:180-198`); the client's `mark_listing_sold` then gets `No verified payment found` (P1). Retired row `pending→failed` accepted (X12); if Stripe later reports success for a `failed` row, CP-old's UPDATE `failed→succeeded` is allowed (X2b) — money wins. A third buyer cannot re-reserve a paid-but-unsettled listing (`This listing has already been sold.`, X12b) and `cleanup_expired_reservations` no longer re-lists it (X12c). | Safe. |
| 6 | WH | ETE | refund / transfer events | ETE-old Phase 1 refunds and writes `refunded/refunded_at/stripe_refund_id` directly; WH-new `charge.refunded` for the same `re_` → `record_payment_refund` → ledger row + `amount_refunded_cents`, no raise (X3a). ETE-old Phase 1 racing after WH-new wrote → RAISES monotonic (X6) → old logs, counts refunded; money safe (idempotent refund key). WH-new `transfer.created` from ETE-old's POST has no `attempt_id` → log only (`:713-722`). | Safe. |
| 7 | ETE | WH | settle / refund / transfer events | WH-old promote+`mark_listing_sold` vs ETE-new Phase 0 contract on the same PI → row lock serializes; both idempotent. WH-old `charge.refunded` direct UPDATE vs ETE-new `record_payment_refund` — both orders OK (X3a, X3b; the old predicate `status<>'refunded'` matches 0 rows after the new write). WH-old `dispute.closed lost` direct UPDATE → ETE-new claim → `PAYMENT_NOT_SUCCEEDED`; no payout. **WH-old `transfer.created` is ack-only** → an ETE-new attempt whose record failed stays `requested`; healed by 2b after the 10-min lease via `findTransferByAttempt` (transfer_group) — no event needed. | Safe. |
| 8 | WH | CR | payout events | `transfer.created` from CR-old POST → no `attempt_id` → log only. `dispute.closed lost` → `record_payment_refund` + `flag_payout_reversal_required` uses `transfers.stripe_transfer_id`, which CR-old sets via `record_transfer_payout` → flagged correctly (X3a4 analogue). | Safe. |
| 9 | CR | WH | payout events | CR-new POST carries `metadata[attempt_id]`; WH-old acks `transfer.created` without recording (`:737-746`). If CR-new dies between POST and record: attempt stays `requested`; healed only by ETE-**new** 2b. With ETE-old live and the cron firing → row #3. | Safe iff ETE is new or cron paused. |
| 10 | CPI | WH | PI lifecycle | CPI-new's cancels emit `payment_intent.canceled` → WH-old: unsubscribed today; if subscribed early, ack-only (`:862`) and the row is already `failed`. WH-old `payment_intent.succeeded` for a buyer whose PI CPI-new refused: the PI cannot succeed after a confirmed cancel; if the cancel was refused the row stays `pending` and WH-old promotes + `mark_listing_sold(metadata.buyer)` → P1 gate passes for the row's own buyer (X11d) — money wins over the reservation (decision 1). | Safe. |
| 11 | ETE | CP | settle | CP-old shape (succeeded + direct transfer, listing reserved, client never called `mark_listing_sold`) is `paid_unsettled` after 5 min and Phase 0 settles it (X17: `settled`, 1 transfer). | Safe (heals F02). |
| 12 | DA | any | deletion | Read-only predicate; before P3 → `unavailable` + Sentry, request still accepted (`:139-146`). BP-13 is evaluated by the sweep from P3b regardless of DA version (E8b, X16). | Safe. |
| 13 | any | DA | deletion | DA-old has no money writes; nothing to conflict. | Safe. |
| 14 | (P1 applied, CPI still old — P1-c failed) | — | reservation | CPI-old never checks the holder (`:330`); a non-holder can mint and pay; P1's `mark_listing_sold` requires *that caller's* succeeded payment → the payer settles (money wins); the holder's later payment collides on `idx_payments_one_success_per_listing` → CP-old logs 23505, WH-old 500-loops until WH-new (`unfulfillable` → 200 + review). | Not worse than today (F01/F03 remain until P1-c). |

---

## 2. Incoming Stripe webhooks during the deploy

**Event coverage.** OLD handles 10 types (`:261,:501,:566,:663,:705,:737,:748,:772,:783,:795`); anything else → `markProcessed()` + 200 (`:862-868`), i.e. **terminal**. NEW handles the same 10 plus `payment_intent.canceled` (`:361`). The live endpoint is subscribed to the 10 (`08_STRIPE_WEBHOOK_SUBSCRIPTION.md`); `payment_intent.canceled` is added at P2-d **after** WH-new — correct, because an event acked by WH-old is `processed_at`-terminal and a resend is a no-op (X9a3 `already_processed`).

**Lease semantics (`064`, unchanged, X9).** `claim` → `claimed` only when `processed_at IS NULL` and no live lease (300 s, `LEASE_SECONDS` both versions). After OLD `finish(true)`/`markProcessed()` → resend → `already_processed` (X9a3), **no reprocessing through the contract**. After OLD `finish(false)`/`markProcessed({error})` (lease released, `attempt_count+1`, `last_error` kept) → the next Stripe retry or a resend by WH-new → `claimed` (X9b3) → contract runs. A delivery inside another's live lease → `in_flight` 409 (X9c2). `get_incomplete_webhook_events(300, 100)` lists unfinished events with `lease_state` released/abandoned/in_flight (X9e; first arg is lease seconds — `0` marks everything abandoned).

**Event received by WH-old that the NEW schema expects ledgered.**

| Event | WH-old does | Ledger gap on NEW schema | Later `stripe events resend` to WH-new |
|---|---|---|---|
| `payment_intent.succeeded`, row pending/failed | UPDATE `succeeded` (no amount/metadata/livemode check) → `mark_listing_sold`(metadata) → INSERT transfer → 200 | none if metadata = row (E1; X11d). Amount mismatch is promoted silently (no review row). | `already_processed` → **no-op**. Reconciliation is the sweep (`paid_unsettled`), not a resend. |
| `payment_intent.succeeded`, row `refunded` | UPDATE RAISES (X1) → 500, lease released, retried by Stripe for 3 days | none needed | WH-new claims the released lease → `refunded` outcome → 200 (X1b). Loop ends at WH-new deploy. |
| `payment_intent.succeeded`, metadata buyer ≠ row buyer | promoted, then `mark_listing_sold` RAISES (X11) → 500 loop | promotion without binding check | WH-new → `binding_mismatch` → review row, 200 (X11c/d). Row stays `succeeded`; Phase 0 `paid_unsettled` will *not* settle it (contract returns `binding_mismatch` again) — operator resolves. |
| `payment_intent.succeeded`, no `payments` row | fallback: `payment_not_found` → 200 terminal (`:299-306`) | no `unknown_payment` review row | no-op (`already_processed`). Detect with Stripe: `stripe payment_intents list --limit 100` vs `payments.stripe_payment_intent_id`. |
| `charge.refunded` | UPDATE `refunded, refunded_at, stripe_refund_id` (first refund id only, `:711`) — also for a **partial** refund | no `payment_refunds` row, `amount_refunded_cents` NULL; partial recorded as full (pre-existing) | `already_processed`. If replay is forced (Dashboard re-send creates a NEW event id) → `record_payment_refund` heals ledger + `amount_refunded_cents` (X3a2/3) and flags a paid transfer `REFUNDED_AFTER_PAYOUT` (X3a4). |
| `charge.dispute.closed` lost | UPDATE `refunded, refunded_at` (`:692`) | no dispute ledger row; **no `flag_payout_reversal_required`** on a paid transfer | same-id resend → no-op. New event id → `record_payment_refund(dp_)` + flag (X4b/c). Until then the reversal is invisible to `account_deletion_blockers`' `open_manual_review` arm (it still blocks via `pending_refund`/`unsettled` if the payout wasn't released). |
| `transfer.created` with `metadata.attempt_id` (only after CR/ETE-new exist) | log-only, 200 | attempt not recorded by the event | no-op; `payout_attempts` reconciled by ETE-new 2b via `transfer_group` after the 10-min lease. |
| `payment_intent.canceled` (only if subscribed early) | unhandled → 200 terminal | row stays `pending` | no-op; `pending_stale` (15 min–2 h) settles it `canceled→failed` (X8); older rows via `scripts/release/reconcile_pending_intents.sh` (`12_PRE_SUBSCRIPTION_…md`). |

**Replay safety of WH-new on a resend of an event WH-new itself processed:** `already_processed` (X9a3). On an event whose lease WH-old released: contract is state-guarded — promotion `status NOT IN (succeeded,refunded)`, transfer `ON CONFLICT DO NOTHING`, review rows idempotent per (payment, prefix) (`110000:§1`); `record_payment_refund` idempotent on `re_`/`(payment, dp_)` (`120000:504-513`); `record_payout_attempt_result` same-id replay → `recorded:false` (`120000:765-769`, E6).

---

## 3. Interrupted deployment

`supabase functions deploy` is per-function atomic (a function is either the old or the new version); a multi-name invocation deploys sequentially, so every intermediate state is a prefix of the order. `stripe-webhook` must keep `verify_jwt=false` (`docs/payout-rollout.md:40`, `PRE_TESTFLIGHT_FINAL_AUDIT.md:50`) — deploying it with JWT verification on makes every Stripe delivery 401 (Stripe sends no JWT).

### 3.1 States in the 04 §1 order (P1-a → P1-c → P2-a → P3-a/b/b2/b3 → pause cron → CP, CR, ETE, WH, DA → resume → P2-d)

| State | (a) incoming webhooks | (b) build-13 client | (c) cron sweep if it fires |
|---|---|---|---|
| P1-a applied, P1-c failed (CPI old) | WH-old fine (E1) | reserve OK (E2a); CPI-old lacks holder binding (F03 still open) | ETE-old fine |
| P1-c done, P2-a failed | as above | CPI-new fine (uses no P2 object) | fine |
| P2-a done, P3-b failed | WH-old fine; **no** guard yet → `refunded→succeeded` overwrite still possible (F05) | fine | ETE-old fine; `cleanup_expired_reservations` N1 active |
| P3-b done, P3-b2 failed | WH-old: refunded-row 500 loops (X1), metadata-mismatch loops (X11) — **money safe** | fine | ETE-old fine (`record_transfer_payout` unchanged) |
| S0: all four applied, cron paused, all edges old | as above | fine (E2, E4) | if it fires: fine — no NEW payout writer exists yet |
| S1 + CP new | fine (matrix #2) | CP-new 403s a caller who is not the PI's buyer (`:240-263`) — new behaviour, correct | fine |
| S2 + CR new | fine | fine | **UNSAFE**: matrix #3 (X14) — old sweep vs new attempts, different keys |
| S3 + ETE new | fine (matrix #7) | fine | fine; first run = §4 backlog |
| S4 + WH new | fine | fine | fine |
| S5 + DA new | fine | fine | fine |

The plan's order has exactly one intermediate state (S2) whose safety rests on the cron being paused. Swapping CR and ETE removes it: CR-old + ETE-new is safe (matrix #4), ETE-old + CR-new is not (#3).

### 3.2 Recommended order and stop/resume checks

```
P1-a  apply 20260906100000        → §4 P1 query (04 §4) shows core a=f s=f n=f; wrappers a=t s=t n=f
P1-c  deploy create-payment-intent → functions list: create-payment-intent version = 46 (was 45)
P2-a  apply 20260906110000        → select proname from pg_proc where proname in ('settle_verified_payment','get_unsettled_payments') → 2 rows
P3-a  duplicates query (04 §1)    → 0 rows
P3-b  apply 20260906120000        → trg_guard_payment_transitions present; payout_attempts empty
P3-b2 apply 20260906130000        → select to_regprocedure('public.account_deletion_block_reason(uuid)') is not null
P3-b3 legacy orphan reconcile     → Q9 (§4) reviewed row by row
D1    deploy delete-account        → canary: no money interplay; proves CLI/auth; version 20
D2    deploy confirm-payment       → version 35; smoke: POST with a foreign PI → 403
D3    deploy stripe-webhook        → version 40; verify_jwt still false; next real event: stripe_webhook_events.processed_at set
PAUSE select cron.unschedule('enforce-transfer-expiry');  wait ≥ 5 min (2-min cadence + 150 s wall clock)
      select start_time, end_time, status from cron.job_run_details where jobid in (select jobid from cron.job where jobname='enforce-transfer-expiry') order by start_time desc limit 2;  -- last start_time older than 5 min
      select count(*) from public.payout_attempts where state in ('claimed','requested','unknown');   -- 0 (nothing new exists yet)
      §4 Q1–Q15 triage (this is the ONLY point the backlog can still be shaped)
D4    deploy enforce-transfer-expiry → version 37
D5    deploy confirm-and-release     → version 35
D6    curl -s -X POST "$SUPABASE_URL/functions/v1/enforce-transfer-expiry" -H "Authorization: Bearer $INTERNAL_CRON_SECRET"  -- one manual run; read summary JSON (reconciled_* keys present = new code)
RESUME select cron.schedule('enforce-transfer-expiry','*/2 * * * *', $$ …014_frequent_cron_schedules.sql:29-36 verbatim… $$);
P2-d  stripe webhook_endpoints update we_… (all 11 events, 08_…md)
```

Interruption anywhere: **stop, do not re-run the whole list.** Resume check = `supabase functions list --project-ref hqycwntpfoztoinemqns` (version column vs the expected +1 per function above) + `select jobname, active from cron.job where jobname='enforce-transfer-expiry'` (must be absent/inactive between PAUSE and RESUME) + `select * from public.get_incomplete_webhook_events(300,100)` (rows with `attempt_count>1` are WH-old loops that WH-new will drain; none should persist >1 h after D3) + Stripe: `stripe events list --limit 20 --type payment_intent.succeeded` → `pending_webhooks: 0` on events older than 5 min. If an interruption lands between D4 and D5, the cron may already be resumed (CR-old + ETE-new is safe); if it lands between PAUSE and D4, keep it paused — ETE-old + a live cron is the pre-release state and safe as long as CR is still old.

---

## 4. Cron resumption — first sweep after the migrations

**OLD ETE first run (fires before D4, e.g. pause missed):** Phase 1 identical to today (direct `succeeded→refunded` accepted; no ledger row, `fullyRefunded()` later reads `status='refunded'` consistently). Phase 1b unchanged (misses partial-refund remainders, X7c). Phase 2/2b: no `payout_attempts` rows written; `record_transfer_payout` unchanged; no livemode check on the row (relies on the Stripe pre-flight). No new herd, no new double-payout unless a NEW payout writer coexists (matrix #3).

**NEW ETE first run:** every phase is re-entrant, but three things move money on legacy rows on the *first* tick:

1. **Phase 0 settles every `paid_unsettled` row regardless of age** (`110000` work list: `status='succeeded'`, `paid_at < now()-5min`, listing not sold OR no transfer; `stripe_livemode=false` excluded, NULL count-only). A legacy sold-listing-without-transfer becomes `already_settled` **and receives a fresh `transfers` row `pending`, `expires_at = now()+24h`** (X10b/c) → Phase 1 expires and **refunds** it ~24 h later unless the seller marks it sent (X10d). Bounded at 50 rows / run (1 Stripe GET each).
2. **Phase 0 refunds `unfulfillable` captures without a transfer in the same iteration** (`:350-451`: listing cancelled / sold to another payment / auction not won): Stripe `POST /refunds` (full), key `refund_unfulfillable_<payment_id>`. Legacy candidates = Q13.
3. **Phase 1b refunds the remaining balance of partially refunded expired transfers** that the old predicate skipped (X7c=0 → X7d=1); Stripe refuses over-refunds, but this is new money movement — Q3.

Also: legacy `auto_released`/`buyer_confirmed` rows with `stripe_livemode` NULL/false → `claim_payout_attempt` raises `PAYMENT_NOT_LIVE` (`120000:631-633`) → one `manual_review` decision each (queue noise, Q5 `not_live`). Phase 2 `get_auto_release_candidates` has no LIMIT (`039:150-158`); each release costs up to 6 Stripe calls (legacy pre-flight ≤3 pages + account + PI + POST) → a large backlog can hit the edge wall clock mid-run; attempts left `requested` are reconciled next tick (10-min lease). Double payout on legacy orphans (P3-b3 set) is prevented by the legacy pre-flight (`payouts.ts:404-424`, X13 for the recorded case).

**Exact SQL before `cron.schedule` (all validated on the rehearsal DB, `mixrev_scenarios2.out` Q1–Q15):**

```sql
-- Q1  Phase-0 work list the first tick will see (kind, count, oldest)
SELECT kind, count(*), min(coalesce(paid_at, now())) FROM public.get_unsettled_payments(1000) GROUP BY kind ORDER BY kind;
-- Q12 paid_unsettled older than 7 days: each row is a 24h-then-refund clock the moment the cron resumes — decide per row
SELECT u.stripe_payment_intent_id, u.listing_id, u.paid_at FROM public.get_unsettled_payments(1000) u WHERE u.kind='paid_unsettled' AND coalesce(u.paid_at, now()) < now() - interval '7 days';
-- Q13 rows Phase 0 will REFUND on the first tick (unfulfillable, no transfer)
SELECT u.stripe_payment_intent_id, u.kind,
       CASE WHEN l.auction_status='cancelled' THEN 'cancelled'
            WHEN EXISTS (SELECT 1 FROM public.transfers t WHERE t.listing_id=u.listing_id AND t.payment_id<>u.payment_id) THEN 'sold_to_other_payment'
            WHEN u.mode='auction' AND (l.auction_status<>'ended' OR l.winner_user_id IS DISTINCT FROM p.buyer_id) THEN 'auction_not_won' END AS why
  FROM public.get_unsettled_payments(1000) u JOIN public.payments p ON p.id=u.payment_id JOIN public.listings l ON l.id=u.listing_id
 WHERE u.kind IN ('paid_unsettled','review_unfulfillable')
   AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id=u.payment_id)
   AND (l.auction_status='cancelled'
        OR EXISTS (SELECT 1 FROM public.transfers t WHERE t.listing_id=u.listing_id AND t.payment_id<>u.payment_id)
        OR (u.mode='auction' AND (l.auction_status<>'ended' OR l.winner_user_id IS DISTINCT FROM p.buyer_id)));
-- Q2  Phase-1 backlog
SELECT count(*) FROM public.transfers WHERE status='pending' AND expires_at < now();
-- Q3  Phase-1b backlog incl. partial-refund remainders the new code WILL refund
SELECT count(*) AS expired_unrefunded_live, count(*) FILTER (WHERE p.stripe_refund_id IS NOT NULL) AS partial_remainders
  FROM public.transfers t JOIN public.payments p ON p.id=t.payment_id
 WHERE t.status='expired' AND p.status='succeeded' AND p.stripe_livemode = true AND coalesce(p.amount_refunded_cents,0) < p.total;
-- Q4  Phase-2 candidates due (no LIMIT in the RPC; >20 → run D6 manually first and watch the summary)
SELECT count(*) FROM public.get_auto_release_candidates();
-- Q5  Phase-2b stuck rows; not_live → PAYMENT_NOT_LIVE manual_review rows
SELECT t.status, count(*), count(*) FILTER (WHERE p.stripe_livemode IS DISTINCT FROM true) AS not_live
  FROM public.transfers t JOIN public.payments p ON p.id=t.payment_id
 WHERE t.status IN ('auto_released','buyer_confirmed') AND t.stripe_transfer_id IS NULL AND t.payout_released_at IS NULL AND t.disputed_at IS NULL GROUP BY t.status;
-- Q6  open attempts (expect 0 before the first new run)
SELECT state, count(*), count(*) FILTER (WHERE lease_expires_at < now()) AS lease_expired FROM public.payout_attempts WHERE state IN ('claimed','requested','unknown') GROUP BY state;
-- Q7  webhook loops left by WH-old
SELECT event_type, lease_state, count(*) FROM public.get_incomplete_webhook_events(300, 1000) GROUP BY event_type, lease_state;
-- Q8  review queue
SELECT split_part(error_message, ':', 1) AS prefix, count(*) FROM public.webhook_retries WHERE resolved IS NOT TRUE GROUP BY 1;
-- Q9  P3-b3 legacy orphans (04 §1)
SELECT id, seller_id, status FROM public.transfers WHERE status IN ('buyer_confirmed','auto_released') AND stripe_transfer_id IS NULL ORDER BY created_at;
-- Q10 MINOR-4 pre-enable (120000 header): legacy failed payouts that may hide a lost-response duplicate
SELECT t.id, d.decided_at, d.evidence FROM public.transfers t JOIN public.payments p ON p.id=t.payment_id JOIN public.payout_decisions d ON d.transfer_id=t.id
 WHERE t.stripe_transfer_id IS NULL AND p.stripe_livemode = true AND 'PAYOUT_TRANSFER_FAILED' = ANY(d.reason_codes) ORDER BY d.decided_at;
-- Q15 legacy_unknown_mode (never fetched; ops only)
SELECT count(*) FROM public.get_unsettled_payments(1000) WHERE kind='legacy_unknown_mode';
```

Disposition for Q12 rows that were delivered/paid out-of-band: insert the truthful `transfers` row (status `buyer_confirmed`/`auto_released`, `payout_released_at`, `stripe_transfer_id`) **before** resuming → the row leaves the work list, the contract returns `already_settled` without creating a 24 h obligation, and a later claim raises `ALREADY_RELEASED` (X18b/c/d/e). Rows genuinely undelivered: let Phase 0 settle them — the 24 h expiry-refund is the intended behaviour.

---

## 5. Stop/resume checklist (whole deploy)

| # | Step | Command | Expected |
|---|---|---|---|
| 1 | Source | `cd /Users/josetascon/snatchit-rc && git rev-parse HEAD && git status --porcelain` | `5e3cbc7…` (edges = 972619f), clean |
| 2 | Baseline versions | `supabase functions list --project-ref hqycwntpfoztoinemqns` | CPI 45, CP 34, WH 39, CR 34, ETE 36, DA 19 |
| 3 | P3 pre-flight | `SELECT stripe_transfer_id, count(*) FROM public.transfers WHERE stripe_transfer_id IS NOT NULL GROUP BY 1 HAVING count(*)>1;` | 0 rows |
| 4 | Apply P1 | `supabase db push --linked --include-all` (plans exactly 4 versions) or SQL editor, one file | 04 §4 P1 query: core a=f s=f n=f; 3 wrappers a=t s=t n=f |
| 5 | Deploy CPI | `supabase functions deploy create-payment-intent --project-ref hqycwntpfoztoinemqns` | list → CPI 46 |
| 6 | Smoke CPI | build-13 buy-now on a test listing | 200 with `clientSecret`; a second buyer → 409 `already reserved by another buyer` |
| 7 | Apply P2 | as #4 | `settle_verified_payment`, `get_unsettled_payments` present, svc_x=t auth_x=f |
| 8 | Apply P3 + P3b | as #4 | `trg_guard_payment_transitions`, `transfers_stripe_transfer_id_uniq`, `account_deletion_block_reason(uuid)` present; `SELECT count(*) FROM payout_attempts` = 0 |
| 9 | Legacy orphans | Q9; per row `stripe transfers list --destination <acct> --limit 100` and match `metadata.transfer_id`; `SELECT record_transfer_payout('<id>','<tr_>')` where found | Q9 count after = rows with no Stripe transfer only |
| 10 | Deploy DA (canary) | `supabase functions deploy delete-account …` | DA 20; `POST {action:'withdraw'}` on a test account → 200 |
| 11 | Deploy CP | `supabase functions deploy confirm-payment …` | CP 35; `POST {payment_intent_id:<other buyer's pi>}` → 403 `This payment does not belong to you.` |
| 12 | Deploy WH | `supabase functions deploy stripe-webhook --no-verify-jwt …` | WH 40; `stripe webhook_endpoints retrieve we_…` → 10 events, `status: enabled`; next `payment_intent.succeeded` row in `stripe_webhook_events` has `processed_at` |
| 13 | WH loops drained | `SELECT event_id, event_type, attempt_count, last_error FROM public.get_incomplete_webhook_events(300,100);` (15 min after #12) | no row with `attempt_count>1` older than 15 min |
| 14 | Pause cron | `SELECT cron.unschedule('enforce-transfer-expiry');` then wait ≥5 min | `SELECT count(*) FROM cron.job WHERE jobname='enforce-transfer-expiry'` = 0; `cron.job_run_details` last `start_time` > 5 min ago |
| 15 | Backlog triage | §4 Q1–Q15 | Q6 = 0; Q12/Q13 reviewed row by row (insert truthful transfers per X18 where delivered); Q4 noted |
| 16 | Deploy ETE | `supabase functions deploy enforce-transfer-expiry …` | ETE 37 |
| 17 | Deploy CR | `supabase functions deploy confirm-and-release …` | CR 35 |
| 18 | Manual first sweep | `curl -s -X POST "$SUPABASE_URL/functions/v1/enforce-transfer-expiry" -H "Authorization: Bearer $INTERNAL_CRON_SECRET"` | JSON with `reconciled_settled/reconciled_refunded/reconciled_errors/...` keys; `errors` explained by Q-rows |
| 19 | Attempt ledger sane | `SELECT state, count(*) FROM public.payout_attempts GROUP BY 1; SELECT * FROM public.payout_decisions WHERE decided_at > now()-interval '30 min' AND decision='manual_review';` | no `unknown` older than 10 min after a second manual run; `reversal_required` = 0 |
| 20 | Resume cron | `SELECT cron.schedule('enforce-transfer-expiry','*/2 * * * *', $$<014_frequent_cron_schedules.sql:29-36 verbatim>$$);` | `SELECT jobname, active FROM cron.job WHERE jobname='enforce-transfer-expiry'` → t; two consecutive `run complete` log lines |
| 21 | Stripe event add | `stripe webhook_endpoints update we_… --enabled-events …` (11 events, 08 doc) | `retrieve` shows 11 incl. `payment_intent.canceled` |
| 22 | Pending-intent backfill | `scripts/release/reconcile_pending_intents.sh` (dry run, then `--apply` per 12 doc) | printed `settle_verified_payment(...)` statements reviewed; `succeeded` ones applied first |
| 23 | 24 h watch | Q7, Q8, `SELECT state,count(*) FROM payout_attempts GROUP BY 1`, Sentry | no `unknown`/`reversal_required` growth; `binding_mismatch`/`unknown_payment` rows triaged |

**Rollback of an edge alone** (any step 10–17): redeploy the previous version from the Dashboard/CLI history; the NEW schema accepts every OLD write except `refunded→succeeded` and the unpredicated Phase-1 rewrite (both log-and-continue in old code). Rolling back ETE while CR is new re-opens matrix #3 → pause the cron first.

---

## Findings not covered by section E (new in this review)

1. **S2 in the plan's own order depends solely on the cron pause** (matrix #3, X14). Deploy ETE before CR; the pause then guards only the ETE switch itself.
2. **First new sweep creates 24 h refund clocks on legacy paid-unsettled rows** (X10) and **refunds unfulfillable legacy captures immediately** (Phase 0 `:350-451`) — triage Q12/Q13 before `cron.schedule`; X18 is the operator disposition for delivered-out-of-band rows.
3. **`stripe events resend` cannot re-drive an event WH-old already completed** (X9a3); only events WH-old *failed* are re-claimed (X9b3). Reconciliation of old-webhook-processed events is Phase 0, not resend.
4. WH-old on the P3 schema **500-loops** two classes (refunded row X1; metadata buyer ≠ row buyer X11) until WH-new — money safe, noisy; drained automatically after step 12 (check #13).
5. Phase 1b of ETE-new refunds partial-refund remainders the old code skipped (X7) — new money movement on the first tick; Q3 enumerates it.
6. `delete-account` new is deployable at any point (informational read, `unavailable` fallback) — use it as the deploy canary.

## Addendum — concurrent uncommitted edits observed in the worktree (19:51:38, not mine)

`git status` in `/Users/josetascon/snatchit-rc` shows 7 modified files written during this review (after the rehearsal DB was built from the committed files). Reviewed for impact on the above:
- `20260906110000` `get_unsettled_payments`: `stripe_livemode=false` rows admitted only when `current_setting('app.allow_test_mode_money', true)='on'` (sandbox GUC; production unset) — §4 unchanged for production.
- `20260906120000` `claim_payout_attempt`: same GUC admits `stripe_livemode=false`; NULL still `PAYMENT_NOT_LIVE` — §4 Q5 note unchanged. `record_payout_attempt_result`: `error` evidence appended under `subsequent` instead of overwritten — state machine and `recorded` semantics unchanged (matrix #7/#9, E6/E7 hold).
- `delete-account/index.ts`: comment-only. `app/settings/index.tsx`, docs 09/10/11: outside scope.
Everything in §1–§5 is stated against committed `972619f`; none of the pending edits alters a verdict. Re-run `scripts/release/payments_rc_prod_order_rehearsal.sh` after they land (D3 hash check will change).
