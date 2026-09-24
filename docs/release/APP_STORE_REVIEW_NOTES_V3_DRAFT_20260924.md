# App Store metadata and review notes — V3 DRAFT (A, 2026-09-24)

**DRAFT, not for pasting yet.** Built only from claims verified in `APP_STORE_SUBMISSION_CHECKLIST_V3_20260924.md` §4.
Every `⟨…⟩` placeholder is filled from a later owner step (V5 inventory, O4 credentials, O5 phone), and nothing is
pasted into App Store Connect under this draft. Credentials never appear in this file.

## Unchanged fields, reusable from `APP_STORE_METADATA.md`
App name, subtitle, keywords, categories, age rating answers, URLs, and the App Privacy answers. **Re-check** that
`https://snatchitapp.com/privacy` and `/support` are live before submission (not read).

## Promotional text (draft)
```
Live ticket auctions for concerts, festivals, and Miami nightlife. Bid in real time or buy now. Sellers are paid only after you confirm your tickets arrived.
```

## Description (draft)
```
Snatch It is a live auction app for event tickets. Bid on concerts, festivals, and club nights, or list the tickets you can't use.

BID LIVE
Every listing is a real-time auction with a live countdown. Bidding is free; you pay only if you win and complete checkout.

BUY NOW
Skip the auction when you need tickets tonight. Listings with a Buy Now price check out with card⟨ or Apple Pay — only after V4⟩, processed by Stripe.

SELL IN MINUTES
List your tickets with a photo and set a starting bid or a Buy Now price. Sellers verify a phone number before listing and are paid through Stripe Connect once the sale completes.

TRANSFERS DONE RIGHT
You pay at checkout. The seller is paid only after you confirm the tickets arrived, or after a review window with no report. Sellers transfer through the original ticketing platform, with step-by-step guides for 14+ ticketing services. If your tickets don't arrive, report it in the app and the seller's payout is frozen while it is reviewed.

WHY SNATCH IT
• Real-time bidding with live countdowns
• Buy Now when you don't want to wait
• Sellers paid only after you confirm, or after a review window with no report
• Sellers verify a phone number before listing
• Step-by-step transfer guides for 14+ ticketing services
• Report, block, and dispute tools built in
• Free to browse and bid

Snatch It is a peer-to-peer marketplace for users 18 and over. Ticket prices are set by sellers.
```

## App Review notes (draft)
```
Snatch It is a peer-to-peer marketplace where individual users list, bid on, and buy event tickets. It is owned and operated by JDT LLC. Payments are for physical-world services and are processed by Stripe per Guideline 3.1.5(a) — no digital goods, no in-app purchase.

DEMO ACCOUNTS
Buyer — email ⟨O4⟩ / password ⟨O4⟩
Seller — email ⟨O4⟩ / password ⟨O4⟩

HOW TO REACH CHECKOUT (buyer account):
1. Sign in as the buyer.
2. On the Home tab, open ⟨V5: listing name⟩.
3. Tap "Buy now · ⟨V5: all-in amount⟩".
4. On the Checkout screen, tap "Pay ⟨amount⟩". The Stripe payment sheet opens⟨ — after V4: with Apple Pay on supported devices, merchant identifier merchant.com.snatchit⟩; card entry is always available. This is the app's only payment surface.

You can open the payment sheet and inspect it without completing a charge. Payments run on live Stripe keys. ⟨P5: the owner's commitment about purchases completed during review, if any.⟩

PAYMENTS AND DATA: Stripe, Inc. provides payment processing and Stripe Connect Express seller onboarding (identity verification) and seller payouts. Card numbers, bank details and seller identity data are collected and stored by Stripe, never by Snatch It. The buyer pays at checkout; the seller is paid through Stripe Connect only after the buyer confirms receipt, or after a review window with no report. Snatch It is not affiliated with Ticketmaster, AXS, DICE, SeatGeek, Eventbrite, or any other ticketing platform; after a sale, the ticket transfer happens on the issuing platform.

⟨O5, only if confirmed: PHONE VERIFICATION — test number and code.⟩

SAFETY (Guideline 1.2): listings and users can be reported (listing ⋯ menu → Report) and users blocked (⋯ → Block). Users confirm they are 18 or over at signup. ⟨P1/P3: a review-time or removal statement only if the owner adopts one.⟩

ACCOUNT DELETION: Settings → Delete Account.

Contact: support@snatchitapp.com
```

## Deliberately absent (checklist §4 verdict "omit")
Instant outbid alerts; "our team steps in"; "reports reviewed within 24 hours"; "refunded per policy"; "we monitor and
refund"; "payouts go straight to your bank"; Build 13; the $2 / $2.20 August prices; "active through late August";
"one tap".
