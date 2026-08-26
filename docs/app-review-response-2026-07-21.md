# App Review response — Guideline 2.1 information request

- Submission: c23833b4-3b84-489b-bc1c-ca0bc6874869 · reviewed 2026-07-20 · version 1.0 (7)
- Prepared: 2026-07-21. Status: **DRAFT — do not send until founder approval.**
- Root cause of the Apple Pay question: all demo listings had expired by review day (2026-07-18),
  so the reviewer could not reach checkout, the only surface where Apple Pay appears.
  Fixed by restoring four long-duration demo listings (active through 2026-08-20).

## Message to send in App Store Connect (reply to the 2.1 thread)

```
Hello, thank you for reviewing Snatch It and for the questions. Answers to both items below.

1. GUIDELINE 2.1 — SERVICE PROVIDERS AND RELATIONSHIP

Which companies or institutions provide the services offered in the app?

- Snatch It is a first-party, peer-to-peer ticket marketplace owned and operated by JDT LLC,
  a Florida limited liability company. Individual users list event tickets; other users bid on
  or purchase them. No external company or institution operates the marketplace service.
- Stripe, Inc. is JDT LLC's contracted payment processor. Stripe provides card and Apple Pay
  payment processing, Stripe Connect Express seller onboarding (including identity/KYC
  collection), and seller payouts. All payment credentials — card numbers, Apple Pay payment
  tokens, bank account details — and all seller identity-verification data are collected and
  stored directly by Stripe. Snatch It never receives or stores full card numbers, banking
  credentials, government IDs, SSNs, or Apple Pay credentials; our systems store only Stripe
  account/customer identifiers and order amounts.
- Supabase (database, authentication, backend hosting), Twilio (SMS one-time passcodes,
  delivered via Supabase Auth), Sentry (crash reporting), Expo (push notification delivery),
  and Resend (operational email) provide technical infrastructure only. None of them provides
  or operates the marketplace.
- Snatch It has no partnership, agency relationship, sponsorship, or affiliation with
  Ticketmaster, AXS, DICE, SeatGeek, Eventbrite, or any other ticket issuer or ticketing
  platform. After a sale, the seller transfers the ticket to the buyer using the issuing
  platform's own transfer feature; the app provides step-by-step instructions only and has no
  API integration with those platforms.

What is the relationship between JOSE DAVID TASCON HERRERA and the providers of these services?

- Jose David Tascon Herrera is the owner of JDT LLC, the company that owns and operates
  Snatch It, and is the holder of this Apple Developer account, submitting the app on the
  company's behalf. (Technical identifiers such as the bundle ID "com.jdt-inc.snatchit" refer
  to the same company.)
- JDT LLC's relationship with Stripe and the infrastructure vendors above is that of a
  customer under their standard commercial service agreements. There is no ownership or
  agency relationship in either direction.

2. GUIDELINE 2.1 — APPLE PAY / PASSKIT

Apple Pay is integrated and user-facing. It is offered inside the Stripe PaymentSheet at
checkout, using merchant identifier merchant.com.snatchit. Exact location:

Sign in with the buyer demo account (credentials in the review notes) → Home tab → open an
active listing, e.g. "III Points Saturday GA" → tap "Buy $330 total" → on the Checkout screen
tap "Pay · $330 total" → the Stripe PaymentSheet opens. On devices that support Apple Pay, the
sheet presents Apple Pay; when Apple Pay is unavailable or no eligible Wallet card is
configured, card entry is always available as the fallback. This checkout sheet is the app's
only payment surface.

During the previous review, our demo listings had expired, so checkout — and therefore Apple
Pay — could not be reached. We apologize for the inconvenience. We have restored long-duration
demo listings under the demo seller account (active through late August 2026) and updated the
review notes with the exact navigation steps above.

Thank you — we are happy to provide any further information.
```

## Remediation performed 2026-07-21, revised 2026-07-24 (production DB, service role)

2026-07-24: demo inventory curated to the three strongest listings, cloned fresh under the
demo seller (id 09f1ec06-…) from the best original gnvprod listings (original artwork reused
from the `auction-media` public bucket; originals with payment/transfer history untouched).
All `status=active`, `auction_status=active`, `ends_at=2026-08-23`, `proof_status=approved`:

| Listing | ID | Type | Buy Now (buyer pays) | Start bid | Qty | Event date | Cover |
|---|---|---|---|---|---|---|---|
| III Points Saturday GA | 4afe3557-9c34-4e89-8cac-df69223b551c | Buy Now + auction | $300 ($330) | $250 | 1 | 2026-10-17 | 2b117757…/covers/1783194485065.jpg |
| Space Miami — Mochakk | 7cc333be-9e98-42d5-826b-73529d2a613b | Buy Now + auction | $225 ($247.50) | $150 | 1 | 2026-08-29 | 2b117757…/covers/1783104566889.jpg |
| Quavo E11even | 5f363729-0cda-43f1-9bb0-cf3908dabfb4 | Buy Now + auction | $250 ($275) | $180 | 1 | 2026-08-30 | 2b117757…/covers/1783104504489.jpg |

The four generic listings created 2026-07-21 (Brickell Rooftop Live, Wynwood Saturday Music
Night, South Beach Sunset Sessions, Little Havana Salsa Social) were expired out of the live
feed (`ends_at` moved to the past; the auto-finalize cron ends them through its own path).
Stale expired test listings still appear under the lazy-loaded "Ended" chip — run
`scripts/appreview-hide-stale-listings.sql` in the Supabase SQL editor to clear that chip
(uses the app's own `cancel_listing` RPC; nothing deleted).

2026-07-21: removed a stale `user_blocks` row (demo seller had blocked demo buyer during
Jun 5 beta testing of the block feature). Fresh INSERTs are used instead of reviving sold
listings because `transfers.listing_id` is UNIQUE — re-selling a previously sold listing
would break checkout. No security policy, trigger, or RLS rule was modified.

## Resubmission checklist (after founder approval)

1. Sign in to App Store Connect (session was expired on 2026-07-21).
2. Verify version 1.0 shows the rejection and still has build 7 attached; swap to build 1.0.0 (9)
   (EAS build 2621021b, commit 4740091 — all-in pricing client).
3. Paste the updated review notes (App Review Notes section of docs/product/APP_STORE_METADATA.md).
4. Verify ASC copyright field says "JDT LLC" (only entity reference not yet verified).
5. Send the reply above in the Resolution Center thread.
6. Resubmit version 1.0 for review.
7. Keep demo listings alive until approval (they expire 2026-08-20; extend if review runs long).
