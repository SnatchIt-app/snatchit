# Snatch It — App Store Metadata (production-ready)

Copy-paste ready for App Store Connect. Character counts verified.

## App Name (26/30)
```
Snatch It: Ticket Auctions
```

## Subtitle (29/30)
```
Bid, buy & sell event tickets
```

## Promotional Text (155/170)
```
Live ticket auctions for concerts, festivals, and Miami nightlife. Bid in real time or buy instantly. Your payment stays on hold until your tickets arrive.
```

## Description
```
Snatch It is a live auction app for event tickets. Bid on concerts, festivals, and club nights, or list the tickets you can't use and get paid.

BID LIVE
Every listing is a real-time auction. Watch the clock, place your bid, and get outbid alerts the second it happens. You're only charged if you win.

BUY NOW
Skip the auction when you need tickets tonight. Listings with a Buy Now price are yours in one tap with Apple Pay or card, processed by Stripe.

SELL IN MINUTES
List your tickets with a photo, set a starting bid or a Buy Now price, and reach buyers who actually want them. Payouts go straight to your bank through Stripe. No business account needed.

TRANSFERS DONE RIGHT
Your payment stays on hold until your tickets arrive. Sellers transfer through the original ticketing platform (Ticketmaster, AXS, DICE, Eventbrite, and more) with step-by-step instructions for each. Confirm receipt and the sale completes. If something goes wrong, open a dispute and our team steps in.

BUILT FOR THE SCENE
Born in Miami. Festivals in Wynwood, club nights on the Beach, arena shows downtown. Follow your scene, filter by neighborhood, and never miss the drop.

WHY SNATCH IT
• Real-time bidding with live countdowns and instant outbid alerts
• Buy Now when you don't want to wait
• Payment held until you confirm your tickets arrived
• Verified phone numbers on every seller account
• Step-by-step transfer guides for 14+ ticketing services
• Report, block, and dispute tools built in
• Free to browse and bid. You pay only when you win.

Snatch It is a peer-to-peer marketplace for users 18 and over. Ticket prices are set by sellers.
```

## Keywords (100/100)
No duplicates of App Name / Subtitle words (those already index):
```
miami,concert,festival,nightlife,rave,club,edm,resale,marketplace,music,vip,show,presale,pass,dj,gig
```

## Categories
- **Primary: Entertainment** (where Ticketmaster, SeatGeek, Dice live — strongest browse intent)
- **Secondary: Shopping** (marketplace behavior; better than Lifestyle for purchase intent)

## Age Rating
17+ (unrestricted web-adjacent marketplace, nightlife context; app itself enforces 18+ at signup). Answer the ASC questionnaire honestly — no alcohol/drug content is allowed in listings (moderation regex enforces this).

## App Review Notes (as saved in ASC "Notes" field)
Sign-in fields in ASC hold the buyer demo account: `snatchitreviewbuyer@gmail.com` / `Snatchitreview` (contact phone 7862017279).

Updated 2026-08-04: notes aligned to Build 13's exact UI labels ("Buy · $X" / "Pay · $X"), live payment environment verified end-to-end, Build 13 called out as the current binary. 2026-07-24: demo inventory curated to the three strongest listings (III Points Saturday GA $300, Space Miami — Mochakk $225, Quavo E11even $250 — active through 2026-08-23). Original 2026-07-21 update added operator/provider identification, exact Apple Pay navigation, and removed the outdated "escrow-style, 72h auto-release" wording (risk-based release shipped 2026-07-15).
```
Snatch It is a peer-to-peer marketplace where individual users list, bid on, and buy event tickets. It is owned and operated by JDT LLC. Payments are for physical-world services and are processed by Stripe per Guideline 3.1.5(a) — no digital goods, no IAP.

DEMO ACCOUNTS (both preloaded with demo data for App Review)

BUYER ACCOUNT
Email: snatchitreviewbuyer@gmail.com
Password: Snatchitreview

SELLER ACCOUNT
Email: snatchitreviewseller@gmail.com
Password: Snatchitreview

HOW TO REACH CHECKOUT AND APPLE PAY (use the buyer account):
1. Sign in as the buyer.
2. On the Home tab, open an active listing — "III Points Saturday GA", "Space Miami — Mochakk", or "Quavo E11even".
3. Tap the "Buy · $330" button (the label shows each listing's all-in total; $330 is the III Points example).
4. On the Checkout screen the PAYMENT card reads "Apple Pay or card". Tap "Pay · $330".
5. The Stripe PaymentSheet opens. APPLE PAY IS INTEGRATED HERE, via Stripe PaymentSheet with merchant identifier merchant.com.snatchit, one step after the "Pay · $X" button. On devices that support Apple Pay the sheet offers Apple Pay; card entry is always available as the fallback. This checkout sheet is the app's only payment surface.

Build 13 is the current binary and includes the latest production payment and UI updates; the live checkout above has been verified end to end in this exact environment.

All three listings also accept auction bids. The seller account demonstrates listing creation and the transfer workflow. Demo listings remain active through late August 2026 and will not expire during review.

Note: payments run on live Stripe keys. You can open the payment sheet and fully inspect Apple Pay and card entry without completing a charge; if a purchase is completed, we monitor and refund App Review transactions.

PAYMENTS AND DATA: Stripe, Inc. provides payment processing, Apple Pay processing, Stripe Connect Express seller onboarding (identity/KYC), and seller payouts. Card numbers, Apple Pay credentials, bank details, and seller identity data are collected and stored by Stripe only — never by Snatch It. After a purchase, funds are held by the platform through Stripe and released to the seller after the buyer confirms receipt of the ticket transfer, on a risk-based release schedule; unresolved or disputed orders are refunded per policy. Snatch It is not affiliated with Ticketmaster, AXS, DICE, SeatGeek, Eventbrite, or any other ticketing platform — after a sale, users complete the ticket transfer on the issuing platform.

PHONE VERIFICATION: if you create a fresh account, use test number +1 800 555 0123 with code 789012 (a configured Supabase test number, no SMS is sent).

UGC SAFETY (Guideline 1.2): every listing/user can be reported (listing ⋯ menu → Report) and users blocked (⋯ → Block). Reports are reviewed within 24 hours. A content filter blocks alcohol/drug/counterfeit listings at creation.

ACCOUNT DELETION: Settings → Delete Account (double confirmation).

If additional assistance is needed during review, please contact:
support@snatchitapp.com
```

## URLs for ASC
- Support URL: https://snatchitapp.com (landing page with support email)
- Marketing URL: https://snatchitapp.com
- Privacy Policy URL: https://snatchitapp.com/privacy  ← must be live before submission (see checklist)

## ASC App Privacy questionnaire (must match reality)
Declare: **Contact Info** (email, phone — app functionality, linked to identity), **User Content** (photos, listings — app functionality, linked), **Identifiers** (user ID — app functionality, linked), **Diagnostics** (crash data via Sentry — app functionality, linked). Tracking: **No** (no ATT needed).
