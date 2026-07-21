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
active listing, e.g. "Brickell Rooftop Live" → tap "Buy $22 total" → on the Checkout screen
tap "Pay · $22 total" → the Stripe PaymentSheet opens. On devices that support Apple Pay, the
sheet presents Apple Pay; when Apple Pay is unavailable or no eligible Wallet card is
configured, card entry is always available as the fallback. This checkout sheet is the app's
only payment surface.

During the previous review, our demo listings had expired, so checkout — and therefore Apple
Pay — could not be reached. We apologize for the inconvenience. We have restored four
long-duration demo listings under the demo seller account (active into late August 2026) and
updated the review notes with the exact navigation steps above.

Thank you — we are happy to provide any further information.
```

## Remediation performed on 2026-07-21 (production DB, service role)

New listings inserted for demo seller `snatchitreview…` (id 09f1ec06-…), all `status=active`,
`auction_status=active`, `ends_at=2026-08-20`, `proof_status=approved`, covers pointing at the
seller's real uploaded images in `auction-media`:

| Listing | ID | Type | Buy Now | Start bid | Qty | Event date |
|---|---|---|---|---|---|---|
| Brickell Rooftop Live | 8a95f533-49ff-4e54-bd96-f41126922884 | Buy Now + auction | $20 (buyer pays $22) | $15 | 1 | 2026-08-28 |
| Wynwood Saturday Music Night | 4cb27aab-86f1-4ae2-9ec0-b6c9ecfee8cb | Buy Now + auction | $18 (buyer pays $19.80) | $12 | 2 | 2026-08-22 |
| South Beach Sunset Sessions | 057a7c8b-310f-47d5-b7ad-ff163c08dff7 | Buy Now + auction | $15 (buyer pays $16.50) | $10 | 1 | 2026-09-04 |
| Little Havana Salsa Social | 3b2aae8d-6777-4564-89c5-08f45863da99 | Auction only | — | $10 | 1 | 2026-08-30 |

Also removed a stale `user_blocks` row (demo seller had blocked demo buyer during Jun 5 beta
testing of the block feature). Fresh INSERTs were used instead of reviving sold listings
because `transfers.listing_id` is UNIQUE — re-selling a previously sold listing would break
checkout. No security policy, trigger, or RLS rule was modified.

## Resubmission checklist (after founder approval)

1. Sign in to App Store Connect (session was expired on 2026-07-21).
2. Verify version 1.0 shows the rejection and still has build 7 attached; swap to build 1.0.0 (9)
   (EAS build 2621021b, commit 4740091 — all-in pricing client).
3. Paste the updated review notes (App Review Notes section of APP_STORE_METADATA.md).
4. Verify ASC copyright field says "JDT LLC" (only entity reference not yet verified).
5. Send the reply above in the Resolution Center thread.
6. Resubmit version 1.0 for review.
7. Keep demo listings alive until approval (they expire 2026-08-20; extend if review runs long).
