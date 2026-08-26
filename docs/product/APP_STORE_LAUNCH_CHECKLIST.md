# Snatch It — App Store Launch Checklist

**Status as of 2026-07-12: SUBMITTED — iOS 1.0 (build 7) is Waiting for Review.**
Apple states review can take up to 48 hours; you'll get an email when it completes.

## Submitted configuration
- ✅ Build 1.0.0 (7) — iPhone-only (`supportsTablet: false`), production env, purpose strings fixed
- ✅ Name "Snatch It: Ticket Auctions" · subtitle "Bid, buy & sell event tickets"
- ✅ Promo (155/170), description (1,635), keywords (100/100, no competitor trademarks)
- ✅ 6 normalized screenshots (1284×2778, single Apple badge, one template geometry)
- ✅ App Privacy published · Age rating 18+ (Brazil A18, Korea 15+) · Content Rights declared
- ✅ Pricing Free · availability United States only (no EU → no DSA trader requirements)
- ✅ Review notes: two-account flow (buyer + seller), test phone +1 800 555 0123 / 789012
- ✅ Demo data live: both review accounts phone-verified + Stripe-onboarded; 3 live listings
  (2 auction, 1 Buy Now $300) running through Jul 18 — extend via the bypass-guard SQL if review runs long
- ✅ snatchitapp.com live: /privacy (accurate), /support, /terms, /payout-return, /payout-refresh
- ✅ Release mode: MANUAL — approval does not auto-publish

## After approval (before pressing "Release")
1. **Upgrade Twilio from trial** (~$3.41 balance) — real users' signup OTPs fail until then
2. Confirm Apple Pay merchant ID `merchant.com.snatchit` is registered (card payments work regardless)
3. Extend/refresh demo listings if they expired (same SQL pattern, listing guard bypass GUC)
4. Press "Release This Version" in App Store Connect

## If rejected
- Check Resolution Center in ASC; the review notes + demo accounts cover the usual marketplace asks
  (UGC safety 1.2, physical-goods payments 3.1.5(a), account deletion, seller flow)
