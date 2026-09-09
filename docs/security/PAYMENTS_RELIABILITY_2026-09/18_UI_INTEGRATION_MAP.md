# Integration map — v2 frontend onto the payments release candidate

Branch `integrate/ui-v2-on-payments-rc`, merge commit `9942a94`, base `a77d368` (PR #54 head).
Investigated read-only first (three parallel agents: local worktrees/stashes, remote branches/PRs, sandbox records).

## 1. Why the device build showed the old UI

The release candidate is based on Phase-2 commit `10ad9e4`, which equals the deployed production state. **Every v2
frontend change lives on ONE local-only branch** — `frontend/auth-verification-paths-fix` @ `6af9629` (2026-09-07) —
that was **never pushed**: 111 remote refs, zero match `frontend`, and `git branch -r --contains` is empty for all 29
frontend commits. No PR contains the v2 UI. So the RC legitimately had the old screens (14 components vs 46).

## 2. The map

| Change | Location | Pushed? | Already in the RC? | Action |
|---|---|---|---|---|
| **v2 design system** (`src/components/ui/*`, `src/theme/typography.ts`, 30 rewritten screens, 25 test files) | `frontend/auth-verification-paths-fix` @ `6af9629` | **local only** | no (RC had 14 of 46 components) | **merged** |
| **Buy-Now hold released on leaving the listing** (`src/lib/listing/reservationExit.ts`, `ListingDetailScreen` `beforeRemove`, `tests/reservation-exit.test.ts`) | commit `41c1583` (2026-09-05), same branch | local only | **no** — RC had no client release at all | **merged**, then completed (§4) |
| **Auth logo pinned above the keyboard** (`src/components/auth/AuthScreen.tsx`, `AuthBrandMark.tsx`) | commit `cc0b3e7` (+ `dddb3eb`) | local only | no | **merged** |
| **Duplicate-PaymentSheet latch** (`src/lib/checkout/paymentGuard.ts`) | commit `a7eeea5` | local only | no | **merged** |
| **Smart-quote publishable-key fix** (`src/config/envValue.ts`) | commit `268be21` | local only | no | **merged** (complements, does not duplicate, `envGuard.ts`) |
| Payment reliability P1–P3, deletion option B, env guard, sandbox profiles | RC `a77d368` | pushed (PR #54) | yes | **preserved — wins every conflict** |
| `feature/venue-native-and-product-v2` (PR #52) | pushed | n/a | 34 supabase files, +3231, **zero UI** | **left out** — unrelated backend feature, not deployed |
| `admin/operating-console` (PR #55) | pushed | n/a | 60 files, +11860, zero UI | **left out** — unrelated |
| `mobile/profile-rpc-compat` | pushed | n/a | stale pre-Phase-2 `stripe-webhook` | **left out** — would regress the webhook |
| `core/ios-dev-build` | pushed | n/a | already an RC ancestor | nothing to bring |

Competing designs: **none.** The chosen branch is a strict superset of all 19 other frontend branches
(`branch-unique = 0` for every one). `feature/venue-native-and-product-v2` is newer by date but its `src/` + `app/`
diff is literally empty. So there was one clearly identifiable intended UI and no need to ask.

Non-frontend baggage of the merge: **zero** — `git diff --stat RC...tip -- supabase/ packages/ web/` is empty.

## 3. Conflicts and how each was resolved (exactly three, as predicted)

| File | Resolution |
|---|---|
| `src/screens/checkout/CheckoutNative.tsx` | v2 presentation, `payLatchRef`, `paymentSheetErrorCopy` from the frontend; `finalizePurchase`, the `completed`/`pending`/`failed` settlement state and `SETTLEMENT_COPY` from the RC. The frontend side still carried the **old auction handler with the unconditional "Payment Received … contact support" alert** — deliberately NOT reinstated. |
| `app/_layout.tsx` | union of imports; env-guard blocker and SANDBOX badge kept. |
| `app/settings/index.tsx` | RC deletion-obligation messaging kept verbatim; v2 design taken. One duplicate `alertWeb` (identical bodies) removed. |

`src/lib/payments.ts`, `src/lib/supabase.ts`, `src/config/envGuard.ts`, `eas.json` were untouched by the frontend
stack — no conflict, RC versions stand.

## 4. The reservation defect — confirmed cause and the completion of the old fix

Confirmed from the sandbox records, not inferred:

- **Successful purchase = `Phone P3`** — settled cleanly, one payment row, one distinct PaymentIntent, exactly one
  transfer, zero duplicates, fee split `amount 10000 / buyer_fee 1000 / seller_fee 1000 / total 11000` (10% + 10%, no
  fixed fee).
- **"Disappeared" listing = `Phone P2`** — left `status='reserved'` with a 10-minute server-owned hold. Home filters
  `status='active'`, so a reserved row is hidden. (It was still visible in Explore, which filters `auction_status`.)
- **Why nothing released it:** dismissing the PaymentSheet does not cancel the Stripe PaymentIntent (it stays
  `requires_payment_method`), so Stripe fires no webhook, so the webhook's `release_reservation` branch never runs — and
  the RC had no client-side release at all.
- **What cleared it:** `cleanup_expired_reservations()`, reached from the **active** `auto-finalize-auctions` cron
  (`*/2`). Observed empirically: reserved at 04:23:56 → active at 04:24:07, matching cron run 5837. Total ~11 min 57 s.
- **The sandbox's disabled `enforce-transfer-expiry` is NOT implicated** — reservation cleanup does not depend on it.
  (It does mean abandoned `pending` payment rows are not reconciled in the sandbox: a money-return gap, not an
  inventory gap.)

The existing fix (`41c1583`) releases only on **navigation exit** from the listing; it deliberately does not release on
sheet cancel. That is why the symptom survived it. **Completion added here:** on an explicit PaymentSheet cancel the
client now asks the backend for the authoritative state via `confirmPaymentSuccess`, and

- `reachable && verified` (Stripe says the money is there) → **no release**; the normal settlement path runs;
- `reachable && !verified` → the payment did not happen and cannot complete without a fresh sheet → `release_reservation`;
- `!reachable` → **no release, no alarm**; the 10-minute server TTL remains the backstop.

That is "release promptly only when the backend establishes the payment cannot still complete", with an accurate
pending state whenever the outcome is uncertain.

**Late-completion race:** cannot double-sell. Four independent guards — `create-payment-intent`'s sold/reserved
refusals (which also retire the stale intent), the one-success-per-listing unique index, `settle_listing_for_payment`'s
transfer-binding check plus the transfers unique keys, and `mark_listing_sold`'s bound-succeeded-payment requirement.

## 5. Deliberately left out

The three pushed branches in §2 (venue-native, admin console, profile-rpc-compat) — each is a real feature but
unrelated to this change, and one would regress the deployed webhook. Nothing was merged merely for sharing a branch.
