## Package 2 — reliable settlement — report

**Branch** `fix/payments-p2-settlement` @ `/Users/josetascon/snatchit-pay-p2`, 5 commits on top of `fbf8313`, not pushed, tree clean:
```
a22c8e3 feat(sweep): Phase 0 settlement reconciliation in enforce-transfer-expiry
4235298 fix(confirm-payment): settle through settle_verified_payment; refuse a foreign PaymentIntent (403); no direct writes
8685e1e fix(webhook): payment_intent.succeeded is one settle_verified_payment call; RPC error retries; every outcome terminal; canceled branch
4e2d305 feat(db): P2 verified-settlement contract — settle_verified_payment, get_unsettled_payments, cleanup never re-lists a paid listing
be230b0 test(payments): P2 failing tests — pgTAP 121, webhook/confirm/sweep vitest
```

### Files changed
- `supabase/migrations/20260906110000_settle_verified_payment.sql` (new, 385 lines) — `settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)`, `get_unsettled_payments(integer)`, `cleanup_expired_reservations()` body (000 text + N1 guard); explicit REVOKE PUBLIC/anon/authenticated → GRANT service_role.
- `supabase/rollbacks/20260906110000_settle_verified_payment_rollback.sql` (new) — drops both, restores 000 body verbatim.
- `supabase/ci/assert_public_table_grant_decisions.sql` — +2 `no-client-execute` rows.
- `supabase/functions/stripe-webhook/index.ts` — see branch list below.
- `supabase/functions/confirm-payment/index.ts` — core rewritten (header + Stripe fetch → ownership → settle).
- `supabase/functions/enforce-transfer-expiry/index.ts` — Phase 0 block (lines 183–377, banner-delimited) inserted after `let errorCount = 0;`; 3 lines added at the top of `summary`; 5 header lines. Phase 1/1b/2/2b/3 untouched.
- `supabase/tests/121_settlement.sql` (new, plan 75), `tests/settlement-webhook.test.ts` (16), `tests/settlement-confirm.test.ts` (6), `tests/settlement-sweep.test.ts` (7).
- `tests/edge-harness.test.ts` — 2-line smoke-test adjustment (not in my list; see open questions).

### Red → green evidence
| Suite | Red (before impl) | Green |
|---|---|---|
| pgTAP 121 | `plan=75 ok=0 psql_err=83` — `function public.settle_verified_payment(...) does not exist` | `plan=75 ok=75 not_ok=0 psql_err=0 PASS` |
| vitest settlement-* | 24 failed / 5 passed (e.g. F02 `expected 200 to be 500`; confirm `expected 200 to be 403`; sweep `expected [] to have length 1`) | 29/29 |
| full `npx vitest run` | — | **10 files, 158 tests passed** (baseline 7/129) |

pgTAP scenarios covered: settle twice ⇒ one transfer / `already_settled`; refund-before-success; amount_refunded = total on pending ⇒ `refunded` (pending→succeeded→refunded), listing untouched; binding mismatch ×5 calls (amount/buyer/livemode/currency) ⇒ no writes, exactly ONE review row; `not_succeeded` no writes; `canceled` pending→failed idempotent; unfulfillable via listing sold to another payment (payment stays succeeded + `unfulfillable:listing`); unfulfillable via one-success collision (payment stays pending + `unfulfillable:one_success_per_listing`); unknown pi ⇒ one review row; auction settles; `get_unsettled_payments` returns paid_unsettled / review_unfulfillable / pending_stale, excludes settled/refunded/fresh, dedupes, honours limit; cleanup leaves paid listing reserved, releases unpaid; grants (service_role EXECUTE only; anon/authenticated 42501; explicit ACL, secdef, owner postgres, search_path pinned); invariant "every succeeded payment settled or queued".

vitest: F02 (RPC error ⇒ 500 + `fail_stripe_webhook_event`, retry ⇒ settle called AGAIN ⇒ 200 + complete, pushes once); duplicate event id ⇒ `already_processed`; two events one PI ⇒ `already_settled` 200 no second push; refunded ⇒ 200 no push; unfulfillable ⇒ 200 + warn log; unknown/binding/not_succeeded ⇒ 200; no-row ⇒ 500; payment_failed + canceled: predicate `['not','status','in','("succeeded","refunded")']`, `release_reservation` params, DB error ⇒ 500 + fail; auction ⇒ no release. confirm: exact RPC params incl. `amount_refunded`/refund id from expanded charge, no payments/transfers writes; foreign buyer ⇒ 403 no RPC; not succeeded / Stripe down ⇒ 200 `stripe_verified:false` no RPC; RPC error ⇒ 500. sweep: `get_unsettled_payments {p_limit:50}` first, PI GETs with `?expand[]=latest_charge`, exact settle params `p_source:'sweep'`; fetch failure skipped+counted; unfulfillable ⇒ exactly one `POST /refunds` key `refund_unfulfillable_<payment_id>`, no `amount`, then `record_payment_refund(pi, re_, null, 22000, 'unfulfillable')`, review row resolved; row with `stripe_refund_id` not refunded; PGRST202 fallback ⇒ `payments.update({status:'refunded',refunded_at,stripe_refund_id}) .eq(pi) .not('status','in','("refunded")')`; Phase 0 before `enforce_transfer_expiry`.

### Rehearsal / probe outputs
```
scripts/rehearsal_reset.sh snatchit_p2_rehearsal → [rehearsal] REPLAY OK: 91/91 migrations applied
GATE-2  tables=27 functions=72 policies=37 triggers=24
scripts/rehearsal_test.sh → TOTAL plan=423 ok=419 not_ok=4  (060 ×2 TODO, 132 ×2 db-name — known)
                            RESULT: pgTAP suite matches the expected local baseline.
Rollback probe:
  fresh md5   cleanup=6b7ba391… get_unsettled=401897ad… settle_verified=4232cded…
  rollback    → ROLLBACK_APPLIED; only cleanup remains, md5 55772dd0… == md5 on snatchit_p1_rehearsal (000 body, verbatim)
  121         → plan=75 ok=0 psql_err=83 FAIL (function does not exist)   ✔ expected
  reapply ×2  → REAPPLIED_x2; MD5_MATCH_fresh_vs_reapply; 121 plan=75 ok=75 PASS
Grant posture (all 3): owner postgres | secdef t | {search_path=public} | anon f | authenticated f | service_role t
Manifest gate on a pgTAP-free 91/91 replay: "every public function has a recorded EXECUTE decision" / "every recorded function posture matches the catalog"
npm run typecheck → rc 0;  npm run lint → 0 errors (44 pre-existing warnings, 0 in my files)
```
**Gate-2 delta:** functions 70 → **72** (`settle_verified_payment`, `get_unsettled_payments`); tables/policies/triggers unchanged. `ci.yml` `EXPECT_FUNCS` must become 72 (lead edit).

### Webhook branches
- **Changed:** `payment_intent.succeeded` (claim branch + "already processed" fallback replaced by one RPC call; hunk `@@ -259,281 +259,141`), `payment_intent.payment_failed` (merged with the **new** `payment_intent.canceled` into one branch, status predicate + `finish(false)` on DB error, `finish(true, …)` on completion — second hunk is the single `markProcessed()` → `finish` line). `markProcessed`/`finish` bodies unchanged (semantics already correct); all my paths now go through `finish`.
- **Untouched:** `charge.dispute.created`, `charge.dispute.closed`, `charge.refunded`, `transfer.created`, `transfer.reversed`, `payout.paid`, `payout.failed`, `account.updated`, signature/lease preamble.

### Compatibility
- **Build 13 mobile:** PaymentSheet → `confirm-payment` (now: 403 only if the PI isn't the caller's — never the case for the app; else settles listing + transfer in-DB) → `mark_listing_sold`/`complete_auction_payment` (P1 wrappers find the succeeded payment, core returns `already_settled` ⇒ no error) → `ensure_transfer_exists` (transfer exists ⇒ no-op). If confirm-payment returns 500 (RPC error) the app's existing `fnError` path logs and continues to `mark_listing_sold`, which raises the P1 "No verified payment…" alert until the webhook/sweep settles — same degraded path as today.
- **Web `finalizePurchase`:** reads `stripe_verified` (kept; `true` iff PI succeeded and the contract ran); `outcome`/`transfer_id` additive. Non-2xx ⇒ its DB fallback check, unchanged.
- Response shapes/keys for 200 paths are supersets of the old ones; no client change required.

### Deploy-order dependency on Package 3
Phase 0 calls `record_payment_refund(p_payment_intent_id, p_stripe_refund_id, p_stripe_dispute_id NULL, p_amount_cents, p_source 'unfulfillable')` and falls back to the guarded `payments` update when PostgREST reports `PGRST202`/`42883` (or a "could not find … record_payment_refund" message). Verified against P3's signature in `snatchit-pay-p3` (source list includes `'unfulfillable'`; `p_amount_cents` NULL = full). The fallback is P3-guard-compatible (pending/succeeded → refunded, refund refs set once). Migration order 110000 < 120000 holds. When P3's `guard_payment_transitions` lands, every transition this contract makes is in its allow-list (verified by reading the guard).

### Deviations / design notes (need lead ratification)
1. **Amount binding scoped to `p_stripe_status='succeeded'`** — `amount_received` is 0 for canceled/processing PIs, so the literal spec would make `canceled` unreachable. Currency/livemode/metadata binding always applies. (121 E1/F1 pin this.)
2. **`pending_stale` bounded to `15 min < age < 24 h`** and ordered after the other kinds — otherwise abandoned checkouts become a permanent 50-GET Stripe loop that starves paid rows.
3. `get_unsettled_payments` **excludes `stripe_livemode = false`** rows (045 mode boundary; the live key can never fetch them). NULL-livemode rows are still listed.
4. Sweep **never refunds an unfulfillable row that already has a transfer** (logged, review row left open) — a legacy `active`-status listing with a delivered order would otherwise be auto-refunded.
5. `release_reservation` failure in payment_failed/canceled stays a logged 200 (TTL 10 min + cleanup backstop; a retry can't redo the already-claimed failed-write). DB-write failure is non-2xx per spec.
6. Partial refund (`0 < amount_refunded < total`) sets `refunded_at`/`stripe_refund_id`, leaves status, returns `refunded` — literal spec; P3's `amount_refunded_cents` will carry the amount.
7. `tests/edge-harness.test.ts` smoke test edited (expected path now `?expand[]=latest_charge`; mocked PI given `metadata.buyer_id`) — otherwise the suite is red because ownership is checked before status (403 for a PI without buyer_id). Lead-owned area; revert + re-decide if you prefer status-first.

### Not done / open questions
- `deno check` not run locally (no Deno on PATH); code follows the existing typed patterns.
- `payment_intent.canceled` must be **added to the Stripe webhook endpoint's event list** at deploy time.
- unknown_payment/binding_mismatch review rows have no consumer beyond ops (by design); the sweep only compensates `unfulfillable`.
- Review-row FK: `webhook_retries.payment_id` refs `payments(id)` — the delete-account tombstone flow (P3 `account_deletion_blockers`) should treat unresolved review rows as blockers (mentioned in plan decision 8; not mine to wire).
