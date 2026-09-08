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
