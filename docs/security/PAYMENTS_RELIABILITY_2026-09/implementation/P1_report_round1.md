**Package 1 report — Agent A** (worktree `/Users/josetascon/snatchit-pay-p1`, branch `fix/payments-p1-checkout-authz`, 3 commits on top of 35cbdf6, not pushed, tree clean)

## Files changed
- `supabase/migrations/20260906100000_checkout_reservation_authority.sql` (new)
- `supabase/rollbacks/20260906100000_checkout_reservation_authority_rollback.sql` (new; 0590 bodies extracted programmatically, not retyped)
- `supabase/ci/assert_public_table_grant_decisions.sql` (+1 row `settle_listing_for_payment(uuid)` → `no-client-execute`, after `set_updated_at()`)
- `supabase/functions/create-payment-intent/index.ts`
- `supabase/tests/120_reservation_lifecycle.sql` (new, plan 49)
- `supabase/tests/110_money_authz_matrix.sql` (#18 succeeded-payment fixture; **#17 expected message changed** — see deviations)
- `tests/checkout-intent.test.ts` (new, 10 tests)

Commits: `4e34a18` failing tests → `676e494` migration+rollback+manifest → `5804b9a` edge. No 4th commit: no test edits were needed after implementation.

## Red → green evidence
**pgTAP 120** (rehearsal DB `snatchit_p1_rehearsal`)
- Pre-migration: `plan=49 ok=8 not_ok=12 psql_err=36` (A2/A4/A6/A9/A10/B1-B4/C3/C4/C6 fail; the core does not exist → file aborts).
- Post-migration: `plan=49 ok=49 not_ok=0 psql_err=0`.
- Covers: p_minutes 525600 ⇒ ≤10 min (A1-2); holder re-reserve keeps window (A3-4); second listing releases first (A5-7); 20th allowed / 21st refused with exact message, no state change (A8-10); unpaid holder / unpaid winner cannot settle (B1-4); settle ⇒ sold + one transfer, wrapper twice ⇒ still one, core ⇒ `already_settled`, payments untouched (C1-9); lapsed reservation + foreign live hold both settle on buy_now (D1-5); paid winner refused while foreign hold live (E1-3); core: pending ⇒ throws, sold-to-other ⇒ `unfulfillable`, cancelled ⇒ `unfulfillable`, non-winner ⇒ `unfulfillable` with reservation untouched (F1-8); grants/owner/secdef/search_path, direct call by authenticated and service_role ⇒ 42501, wrappers still authenticated-EXECUTE (G1-10).

**pgTAP 110**: pre `ok=17 not_ok=1` (#17 caught 'not reserved by you') → post `18/18`.

**vitest `tests/checkout-intent.test.ts`**: pre `5 failed | 5 passed` (foreign holder, expired-cancel, foreign hold on auction, sold auction, reserved_until metadata) → post `10/10`. Asserts exact listing filter/select columns, payments lookup filters `[listing_id, buyer_id, mode, status=pending]`, `POST /payment_intents/{id}/cancel`, update `{status:'failed'}` with `[eq id, eq status pending]`, zero inserts / zero PI creates on refusal, idempotency key `pi_<L>_<B>_<mode>_<total>_c<cus>`, response key set unchanged, 10/10 fee numbers.

## Rollback → reapply probe
```
fresh replay md5(prosrc):  complete_auction_payment e9d9175c…  mark_listing_sold e408ca62…  reserve_buy_now a12d4cf0…  settle_listing_for_payment 38d76cf6…
after rollback:            f4f9a31e…  9600d9c4…  2834a107…  (core dropped)  == md5s on the lead's pre-P1 replay snatchit_pay_rehearsal (verbatim proven)
120 after rollback:        plan=49 ok=8 not_ok=12 psql_err=36 (identical to pre-migration)   110: not_ok=1 (#17)
apply migration ×2:        both OK; md5s identical to fresh replay (diff empty); 120 49/49, 110 18/18
```

## Full-suite results
- `scripts/rehearsal_reset.sh snatchit_p1_rehearsal`: `REPLAY OK: 90/90`; `GATE-2 tables=27 functions=70 policies=37 triggers=24`.
- `scripts/rehearsal_test.sh snatchit_p1_rehearsal`: `TOTAL plan=348 ok=344 not_ok=4` — only the known 060 (2 TODO) and 132 (2 cron db-name) deltas; `RESULT: pgTAP suite matches the expected local baseline.`
- `supabase/ci/assert_public_table_grant_decisions.sql` against the replay: all NOTICEs green ("every public function has a recorded EXECUTE decision", "every recorded function posture matches the catalog"). Note: it must run before pgTAP is installed into `public` on the rehearsal DB (I dropped the extension to run it; harness artifact, not a finding).
- `npx vitest run`: 7 files / 129 tests pass. `npm run typecheck`: clean. `npm run lint`: 0 errors, 44 pre-existing warnings, none in changed files.

## Gate-2 delta
Functions **+1** (`settle_listing_for_payment`); tables/policies/triggers unchanged. CI `EXPECT_*` should move functions 70 → 71. (Local replay shows 69→70 and triggers 24 vs CI 26 — pre-existing harness deltas, not from this package.)

## Compatibility (build 13 / web)
- No signature/argument/return changes on the three RPCs; `p_minutes` still accepted (ignored; effective TTL 10 min). cpi request/response keys, amounts, fees, idempotency-key shape unchanged.
- New refusals are 409 with messages matching `src/lib/payments.ts` regexes: `/already reserved/`, `/reservation expired/`, `/already sold/` (cpi says "is already sold"; DB wrappers say "has already been sold" which web's `includes("sold")` catches). Mobile/web both read `body.error` on any non-2xx.
- Wrapper messages that changed for unpaid callers: 'This listing is not reserved by you.' / 'You are not the auction winner.' / 'Auction is not in ended state.' → 'No verified payment found for this listing. Payment must be confirmed before the sale can complete.' (unpaid) or 'This listing has already been sold.' (unfulfillable). Happy path unchanged: confirm-payment writes `succeeded` before the wrapper.
- `metadata[reserved_until]` is added to the Buy-Now PI body. A pending PI minted pre-deploy is reused (not re-created), so the added param cannot collide with an in-flight idempotency key except in the salted-retry path, which already mints a new key.

## Not done / deviations
- **110 #17 expected message changed.** With the ratified body, `mark_listing_sold` no longer consults `reserved_by`, so 'This listing is not reserved by you.' cannot be raised; the pair still discriminates on identity (holder owns the succeeded payment, impostor owns none — comment updated in place). Outside the "fixture only" scope but unavoidable.
- `payment_intent.canceled` → `release_reservation` in stripe-webhook: **not implemented** (Package 2 file); noted for Agent B.
- The core does NOT check reservations for auction payments (money wins); decision-3 refusal lives only in the client wrapper and cpi, so Package 2's webhook path will settle a paid winner over a live foreign hold — consistent with the plan, flagging for awareness.
- `.github/workflows/ci.yml` untouched (Gate-2 delta above).

## Open questions for the lead
1. Lock order is payments → listings in the core and both wrappers; `reserve_buy_now` also updates the caller's other live holds (cross-listing). Acceptable to rely on deadlock detection + client retry there, or do you want those releases moved to a fixed id order?
2. Sold listing with **no** transfer and a succeeded payment: I return `already_settled` and create the transfer (heals legacy sold-without-transfer); sold with a transfer bound to another payment ⇒ `unfulfillable`. Confirm this matches your reading of "this payment is the listing's succeeded payment".
3. cpi retire path: if Stripe refuses the cancel for any reason other than already-canceled (e.g. PI already succeeded), the row is left `pending` for the webhook/Package 2 compensation rather than marked `failed`. Confirm.
