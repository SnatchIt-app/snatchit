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

## App Review Notes (paste into ASC "Notes" field)
```
Snatch It is a peer-to-peer marketplace for reselling event tickets. Payments are for physical-world services and processed by Stripe, per Guideline 3.1.5(a). No digital goods, no IAP required.

DEMO ACCOUNT (pre-verified, Stripe payout onboarding complete):
Email: review-buyer@snatchitapp.com
Password: Snatch1tDemo!

PHONE VERIFICATION: The demo account is already phone-verified. If you create a fresh account, use test number +1 800 555 0123 with OTP 789012 (a configured Supabase test number, no SMS is sent).

PAYMENTS: Use Stripe test flows on the demo account; a live listing seeded by our team is visible on the Home feed for bidding/Buy Now.

UGC SAFETY: Every listing/user can be reported (listing ⋯ menu) and users blocked (profile → Block). Reports are reviewed within 24 hours. Content filter blocks alcohol/drug/counterfeit listings at creation.

ACCOUNT DELETION: Settings → Delete Account (double confirmation).
```

## URLs for ASC
- Support URL: https://snatchitapp.com (landing page with support email)
- Marketing URL: https://snatchitapp.com
- Privacy Policy URL: https://snatchitapp.com/privacy  ← must be live before submission (see checklist)

## ASC App Privacy questionnaire (must match reality)
Declare: **Contact Info** (email, phone — app functionality, linked to identity), **User Content** (photos, listings — app functionality, linked), **Identifiers** (user ID — app functionality, linked), **Diagnostics** (crash data via Sentry — app functionality, linked). Tracking: **No** (no ATT needed).
