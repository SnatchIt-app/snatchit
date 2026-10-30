# Package 2 rev2 — implementation report (agent)

**P2 round-2 revision — `/Users/josetascon/snatchit-pay-p2r`, branch `fix/payments-p2-rev2` (base 7798f5d), 2 commits, not pushed**

- `ab45e56` test(red): pgTAP 121 75→89 (10 not ok), vitest settlement-confirm/-sweep + edge-harness (8 fail)
- `830e9ec` fix: migration 110000 in place (header updated), confirm-payment, enforce-transfer-expiry

Paths below: `M` = `supabase/migrations/20260906110000_settle_verified_payment.sql`, `E` = `supabase/functions/enforce-transfer-expiry/index.ts`, `C` = `supabase/functions/confirm-payment/index.ts`, `T` = `supabase/tests/121_settlement.sql`.

**Per finding**
- MAJOR-1 — M:210-255: refunded row ⇒ `refunded`, no writes; `p_amount_refunded >= total` ⇒ promote first (M:222-232, unique_violation skipped), then `EXECUTE 'SELECT public.record_payment_refund($1,$2,NULL,$3,$4)'` with `least(amount,total)`, source `'dashboard'`, guarded by `to_regprocedure(...)` (M:234-244); else status-only write (M:246-251). Partial refund falls through to settle; no `refunded_at`/`stripe_refund_id` write remains anywhere in the contract. E:211-212 `fullyRefunded()` = `status='refunded' || amount_refunded_cents >= total`; used at Phase 0 E:369, Phase 1 E:524, Phase 1b E:680 (1b's `.is('payments.stripe_refund_id', null)` filter dropped, E:667-671). Phase 0 still refuses when either holds or a transfer exists (E:369-403). Tests: T C6/C7 (payment_refunds row source dashboard, amount_refunded_cents=22000), N1-N3 (partial ⇒ succeeded/sold/settled, no refund fields, nothing ledgered), C5 (webhook after full refund ⇒ refunded); vitest sweep "partially refunded charge … settles", "fully refunded row skipped", "PARTIALLY refunded unfulfillable … remaining refund".
- MINOR-2 — C:224-247: `metadata.buyer_id === caller` OR one `payments.select('buyer_id').eq('stripe_payment_intent_id')`; no row + no metadata ⇒ 403. vitest confirm: legacy owned ⇒ 200 settled; foreign row ⇒ 403; no row ⇒ 403; metadata match never consults payments.
- MINOR-3 — M:175-196: `lower(trim())`, canonical-uuid regex, cast; malformed ⇒ `binding_mismatch`. T O1 (upper/padded binds ⇒ settled), O2/O3 (malformed ⇒ mismatch, row untouched).
- MINOR-4 — E:380-403: transfer present ⇒ `webhook_retries.error_message='unfulfillable:manual_review'` + ONE `captureException('…:phase0-unfulfillable-manual-review')`, counted `reconciled_manual_review`; M:344 excludes the marker from `review_unfulfillable`. `canceled` marks `pending|processing` failed (M:258-263). T J10 (marker not listed), F5 (processing⇒failed); vitest sweep 2-run test: 1 settle, 1 GET, 1 Sentry, second run re-lists nothing.
- MINOR-5 — M:349-372: pending_stale 15 min<age<2 h; NULL-livemode paid_unsettled/pending_stale rows become kind `legacy_unknown_mode` (priority 4); E:280-286 counts them (`reconciled_legacy_unknown_mode`), no Stripe call. T J11-J14; vitest "legacy_unknown_mode rows counted only".
- NOTE-9 — E:220-266 `retireOtherPendingIntents` (local): after `settled` (E:329) selects pending rows on the listing `neq id`, POST `/payment_intents/{id}/cancel` via `stripeFetch`, "already canceled" message treated as canceled, row → failed only on confirmed cancel. vitest: o1 canceled+failed, o2 (succeeded at Stripe) left pending, o3 (no PI) failed; `already_settled` retires nothing.

**Red → green**
- pgTAP 121 before fix: `1..89`, not ok 18,19,20,21,32,42,65,66,67,68 (C6 C7 N1 N2 O1 F5 J10 J11 J12 J13) → after: 89/89.
- vitest before: 8 failed / 18 passed (3 files) → after: 232/232 (13 files).

**Suite totals (all local)**
- `scripts/rehearsal_reset.sh snatchit_p2r_rehearsal` → `REPLAY OK: 92/92`, GATE-2 tables=30 functions=83 policies=37 triggers=28 (unchanged from base).
- `scripts/rehearsal_test.sh snatchit_p2r_rehearsal` → rc 0, `TOTAL plan=574 ok=572 not_ok=2`, only `132_replay_parity.sql not_ok=2` (known db-name deltas); 121 89/89, 122 53/53, 123 51/51, 124 24/24.
- Rollback probe (fresh 92/92): `settle_verified_payment` md5 `0ae2ecf87abab0b98d0452faa428cc51`, `get_unsettled_payments` `c8e66a66…`, `cleanup_expired_reservations` `6b7ba391…` → rb 120000 OK → rb 110000 OK (both P2 fns gone; cleanup md5 `55772dd0…` = 000 body) → reapply 110000 OK → reapply 120000 OK → all three md5 identical to fresh; 121 89/89 and 123 51/51 green after reapply.
- P3-absent branch probe (`REHEARSAL_UPTO=…110000`, 91/92, `record_payment_refund=<none>`, same fn md5): full refund on pending row ⇒ `refunded/reserved/refunded`, row `status=refunded paid_at_set=t refunded_at_set=t stripe_refund_id=<null>`, redelivery ⇒ `refunded`.
- `npx vitest run` 232/232; `npm run typecheck` rc 0; `npm run lint` 0 errors / 44 warnings (identical count with my changes stashed — none in touched files).

**Deviations / disagreements (lead ruling requested)**
1. Both edges now fetch `?expand[]=latest_charge&expand[]=latest_charge.refunds` (C:192, E:293). Under the pinned API `2024-09-30.acacia` a Charge no longer embeds `refunds`, so `p_stripe_refund_id` was always null before — `record_payment_refund` would raise `REFUND_REFERENCE_REQUIRED`. Harness smoke expectation moved accordingly (`tests/edge-harness.test.ts:49`).
2. Full refund with NO refund id (P3 present or absent) ⇒ status-only write, nothing ledgered (M:246-251, documented in header). Alternative would be to raise; I chose not to block settlement facts on a missing reference.
3. Phase 1b: dropped the `.is('payments.stripe_refund_id', null)` query filter and skip in JS via `fullyRefunded` (E:667-680) — one step beyond "the ONE predicate", but leaving it would keep partially-refunded expired transfers unrefunded on the self-heal path.
4. NOTE-9 retire scope is "every other pending payment row on the listing" (`neq id`), a superset of "other buyers" (`neq buyer_id`); the listing is sold, so the settled buyer's own stale pending PI is equally dead.
5. Refunded-row `stripe_refund_id` back-fill (old M step 3) removed per "no other direct write"; P3's `charge.refunded` branch is now the only backfill.

**Open questions**
- E Phase 0/1/1b select `amount_refunded_cents` unconditionally; the integrated `enforce-transfer-expiry` already depends on P3 (`executePayoutAttempt`/`claim_payout_attempt`), so release plan step P2-c (edges before P3-b) is not valid for this tree — 04_RELEASE_PLAN.md needs a note, or the P2/P3 edge deploys collapse into one step after P3-b.
- Stripe endpoint event list still needs `payment_intent.canceled` (P2-d, unchanged).
- `deno check` not run (no Deno locally). Reviewer's `concurrent.sh` not re-run (lock path unchanged).

## Lead rulings on deviations 1–5

All five accepted: (1) `expand[]=latest_charge.refunds` is required under the pinned API `2024-09-30.acacia` to obtain a refund reference; (2) a full refund reported without a refund id records status only rather than blocking the settlement fact — P3's `charge.refunded` branch back-fills the reference; (3) Phase 1b's JS predicate keeps partially-refunded expired transfers on the self-heal path; (4) retiring every other pending row on a sold listing is the correct superset; (5) no direct refund-column writes remain in the contract. Open question 1 (P2 edges depend on P3's schema in the integrated tree) is adopted in `04_RELEASE_PLAN.md`: the three edge deploys happen as one step after all three migrations.
