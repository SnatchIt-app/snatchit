# Physical-iPhone test procedure — sandbox build (EAS cloud, ad-hoc)

Build profile `preview`, pointed at Supabase sandbox `ofaidukbieeekqaboscm` and Stripe Sandbox
`acct_1T6Fb1GlD5aqtxIw`. **No real money can move**: the app carries only the sandbox test publishable key, and every
money-out gate in the sandbox refuses live-mode rows.

## 0. Before you start

- The app shows a persistent **`SANDBOX — TEST MONEY ONLY`** badge at the top. If you do not see it, stop and tell me:
  it means the environment guard did not resolve a sandbox pair.
- If the build is misconfigured the app shows a full-screen **"Build misconfigured"** blocker instead of the UI. That is
  the guard working; send me the code it prints (F1…F8).
- Sign in with the synthetic buyer `sandbox-buyer@snatchit.test`. The password is in your local
  `scripts/sandbox/sandbox.env`; never paste it into chat.
- Test cards (Stripe test mode only): success `4242 4242 4242 4242` · 3-D Secure `4000 0025 0000 3155` ·
  decline `4000 0000 0000 0002`. Any future expiry, any CVC, any postcode.
- Eight `$100` buy-now listings are staged (`Device D1…D5`, `Phone P1…P3`). Total at checkout must read **$110.00**
  (10% buyer fee). If you ever see $110.90 or a fixed fee, stop — the fee model must stay 10% / 10%.

## 1. Test cases (run in this order; each says what I verify server-side afterwards)

| # | Case | What you do | Expected on screen |
|---|---|---|---|
| D1 | Sign-in | Launch, sign in as the buyer | Home loads; SANDBOX badge visible |
| D2 | Checkout + fee total | Open `Device D1` → Buy Now | Total **$110.00**, service fee shown as 10% |
| D3 | PaymentSheet cancellation | Start payment, then swipe the sheet away | Returns to the listing, **no charge**, listing still buyable |
| D4 | Retry after cancellation | Immediately buy the same listing with `4242…` | Success screen "Purchase complete!" |
| D5 | 3-D Secure completion | `Device D2` → Buy Now → `4000 0025 0000 3155` → **Complete** the challenge | Returns into the app, then success |
| D6 | 3-D Secure cancellation | `Device D3` → Buy Now → same card → **Cancel** the challenge | Returns into the app, no charge, no scary alert |
| D7 | Order + listing state | After D4/D5, open the listing and your orders | Listing shows sold; the order appears |
| D8 | Pending-payment recovery | `Device D4` → pay with `4242…`, then **force-quit the app the moment the sheet closes** | Reopen: no duplicate charge; order appears (webhook settles it) |
| D9 | Connection loss | `Phone P1` → turn on Airplane Mode right after the sheet closes → wait 15 s → turn it off | **No "contact support"** alert; a calm "payment received / your payment is safe — don't pay again"; the order appears shortly |
| D10 | Deletion messaging with obligations | With an unsettled order present: Settings → Delete Account → confirm | Request is **accepted**; message lists what must settle first; you are signed out |
| D11 | Withdraw deletion | Sign back in → Settings → Withdraw deletion request | Account returns to active |

After each case, tell me the case number and what you saw. I check the sandbox database (payments, transfers, listings,
deletion state, duplicate-payment count) and report the server-side truth next to your observation.

## 2. Cases that still require a physical device beyond the above

| Case | Why it cannot be simulated |
|---|---|
| Apple Pay | `isPlatformPaySupported()` is false on a simulator; the merchant entitlement is device-bound |
| Push routing | the app skips token registration unless it is a real device |
| Real network handoff | Wi-Fi ↔ cellular transitions do not exist on a simulator |

D9 above is the *interruption* half of the network case (Airplane Mode); a true Wi-Fi/cellular handoff needs you to walk
out of Wi-Fi range mid-payment, which is optional.

## 3. What is NOT being retested here (already proven server-side, 49/49 real Stripe test-mode)

Settlement, webhook duplicate/out-of-order delivery, abandonment, partial and full refunds, dispute chargeback, the
whole payout leg including a real Connect transfer with idempotent repeat and reversal, deletion state machine, rate
limiting, and the live/test mode boundary. Do not spend device time on these.

---

# Results — physical iPhone, build `d9b7c85b` (source `9942a94`)

Recorded 2026-09-09. Device observation on the left, sandbox server-side truth on the right. Only cases run on the
**new** build count; the 2026-09-08 04:0x session ran the old-UI build and its rows are treated as pre-existing state,
not as evidence.

| # | Case | Listing | Device observation | Server-side verification | Verdict |
|---|---|---|---|---|---|
| D3 | PaymentSheet cancellation | `Phone P2` | Sheet dismissed; app returned to Home; listing still buyable | No new payment row, no charge, `reserved_by`/`reserved_until` both NULL — no hold left behind | **PASS (device)** |
| D4 | Retry after cancellation | `Phone P2` | Reopened checkout, paid, "Purchase complete!" | Exactly one payment row `2e1a1cf6` `succeeded`, one PaymentIntent `pi_3UDGN3…` `succeeded`, one charge `ch_3UDGN3…` captured; listing `sold` | **PASS (device)** |
| UI | Auth logo position | — | Logo stays near the top with the keyboard open and closed | n/a (client-only) | **PASS (device)** |

## Settlement detail for `Phone P2` (`cfd4e7b9-7aa1-4b9a-a98e-186b0630314b`)

| Field | Value | Check |
|---|---|---|
| Buyer | `contact@snatchitapp.com` (`1fcd0c69…`) | matches the signed-in device account |
| Seller | `sandbox-seller@snatchit.test` (`2f5844b4…`) | matches the staged listing owner |
| Item | $100.00 | as staged |
| Buyer fee | $10.00 | 10% — fee model intact |
| Seller fee | $10.00 | 10% — fee model intact |
| Charged total | $110.00 | no fixed fee; $110.90 would have failed the check |
| `stripe_livemode` | `false` | test money only |
| Payment rows for the listing | 1 | **no duplicate payment** |
| PaymentIntents in Stripe for the listing | 1 (`succeeded`) | **no duplicate PaymentIntent** |
| Charges | 1, captured, `amount_refunded=0`, not disputed | clean |
| Transfer rows | 1, `status=pending`, `stripe_transfer_id` NULL | **no duplicate transfer**; payout correctly withheld until delivery is confirmed |
| Stripe transfers referencing this payment | 0 | no money left the platform balance |
| Listing state | `sold`, `sold_at` set, holds released | stays sold |

Note on the payment row: it was created 2026-09-08 04:10:58 by the *old* build's abandoned attempt and settled
2026-09-09 02:55:59 by this test. The new build reused that pending row instead of opening a second one — which is the
behaviour the reservation-cancellation fix intends, and it is why the duplicate counts above are 1 and not 2.

## Pre-existing sandbox residue (not caused by this session)

Five payment rows remain `pending` from the 2026-09-08 old-build session (`Diag`, `Device D1`, `Device D2`,
`Sandbox L4`, `Phone P1`). Every one of their PaymentIntents is `requires_payment_method`: no payment method attached,
nothing capturable, no charge. Their listings are `active` with no reservation hold, so browse is unaffected. Left in
place deliberately as abandonment evidence; the sandbox expiry cron is disabled by design.

**Clean listings for the remaining cases** (no payment row of any kind): `Device D3`, `Device D4`, `Device D5`.
