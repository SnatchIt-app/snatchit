# Day 7 — Beta Tester Onboarding Pack

**Version:** 1.0
**Date:** 2026-04-02
**Audience:** SnatchIt private beta testers

---

## Beta Invite Message

Copy-paste this to testers via iMessage, email, or Discord:

---

> **You're invited to test SnatchIt!**
>
> SnatchIt is a peer-to-peer ticket marketplace where you can buy and sell event tickets with built-in buyer protection. We're running a private beta and we'd love your help finding bugs and giving feedback.
>
> **To get started:**
> 1. iOS — Open this TestFlight link: [INSERT TESTFLIGHT LINK]
> 2. Android — Open this invite link: [INSERT PLAY CONSOLE INTERNAL LINK]
> 3. Create an account using your real email
> 4. If you're testing as a **seller**, you'll need to connect a Stripe account (takes ~2 min) — we'll walk you through it in the app
>
> **What we need from you:**
> - Try buying and selling tickets
> - Report anything broken, confusing, or slow
> - Tell us what you expected vs. what happened
>
> **How to report bugs:** [INSERT BUG CHANNEL LINK — GitHub Issues / Discord / shared doc]
>
> Thanks for helping us build something great.

---

## What Testers Should Focus On

### Priority 1 — Core Flows (Must Test)

These are the flows that move money. Every tester should complete at least one of each:

1. **Buy a ticket (Happy Path):** Find a listing → Buy Now → complete payment → wait for seller to send → confirm receipt
2. **Sell a ticket:** Create a listing with real event details and a cover image → wait for it to sell → mark tickets as sent → confirm payout arrives
3. **Seller ghost scenario:** Buy a ticket from a seller who intentionally does NOT send tickets → verify you get a refund notification after 24 hours
4. **Dispute flow:** Buy a ticket → seller marks as sent → tap "Dispute" before confirming receipt → check that you see the dispute confirmation screen

### Priority 2 — Edge Cases (Power Testers)

5. **Double-sale prevention:** Have two people try to buy the same listing at the exact same time. Only one should succeed.
6. **Auto-release:** Buy a ticket → seller sends → do NOT confirm receipt → wait 72 hours (we may fast-forward this in testing) → verify seller gets paid automatically
7. **Seller without Stripe:** Try to sell without connecting a Stripe account. The app should block or warn you.

### Priority 3 — UX and Polish

8. **Push notifications:** Are they arriving? Do they make sense? Do they arrive at the right time?
9. **Navigation:** Can you always find your way back? Does the tab bar make sense?
10. **Loading states:** Do you see spinners or blank screens? How long do pages take to load?
11. **Error messages:** When something goes wrong, is the error helpful or confusing?

---

## What to Do If You Hit a Dispute or Refund Issue

### If you filed a dispute and nothing happened:

1. Don't panic — disputes are resolved manually by the admin during beta
2. Send a message to the support channel: [INSERT SUPPORT CHANNEL]
3. Include:
   - Your username or email
   - The listing name
   - What happened (e.g., "Seller marked as sent but I never got tickets")
4. The admin will investigate using the Stripe Dashboard and Supabase, and will resolve within 24 hours

### If you expected a refund but didn't get one:

1. Refunds take 5–10 business days to appear on your statement
2. If it's been more than 10 business days, message the support channel with:
   - Your email
   - The listing name
   - Approximate date of purchase
3. The admin will check the Stripe refund status and follow up

### If you got a refund you didn't expect:

1. This may mean the seller didn't transfer tickets within 24 hours (automatic expiry refund)
2. Check your notifications — you should have received a push notification explaining the refund
3. If the notification is missing or unclear, report it as a bug

---

## How to Report Bugs

### Where to report:
[INSERT BUG CHANNEL LINK — GitHub Issues / Discord channel / shared Google Doc]

### What to include in every bug report:

Use this template (also available in `DAY6_BUG_LOG_TEMPLATE.md`):

```
**Device:** (e.g., iPhone 15 Pro, Pixel 8)
**OS Version:** (e.g., iOS 18.2, Android 15)
**App Version:** (check Settings screen in the app)
**What I was doing:** (step by step)
**What I expected:**
**What actually happened:**
**Screenshot or screen recording:** (attach if possible)
**Reproducible?** (Yes / No / Sometimes)
```

### Severity guide for testers:

| Severity | When to use | Example |
|----------|-------------|---------|
| **Critical** | Can't complete a purchase or sale; lost money; app crashes | Payment went through but no transfer row created |
| **High** | Feature doesn't work but there's a workaround | Push notification never arrived but I could see the status in-app |
| **Medium** | Something is confusing or looks wrong | Seller payout message says "released" but Stripe shows "pending" |
| **Low** | Minor UI issue, typo, or suggestion | Button text truncated on small screens |

### What makes a great bug report:

- **Be specific.** "The app is broken" is hard to fix. "Tapping 'Confirm Received' on the transfer screen shows a blank white screen for 3 seconds before completing" is perfect.
- **Include screenshots.** A picture is worth 1000 words. A screen recording is worth 10,000.
- **Note if it happens every time** or only sometimes.
- **Don't worry about duplicates.** If you saw it, report it. We'll deduplicate.

---

## Beta Ground Rules

1. **Use real emails** but you can use test payment methods if we provide them (we'll let you know)
2. **Don't share the TestFlight/Play link** outside the beta group
3. **Don't list real tickets you intend to sell** to real buyers during beta — this is testing only
4. **Expect things to break.** That's the whole point. You're helping us find problems before real users do.
5. **Be honest.** If something is confusing, say so. If you hate the UI, say so. Blunt feedback is the most valuable feedback.

---

## Quick Reference

| Need | Where |
|------|-------|
| Download the app | TestFlight (iOS) / Internal track (Android) |
| Report a bug | [INSERT BUG CHANNEL] |
| Contact support / admin | [INSERT SUPPORT CHANNEL] |
| Dispute / refund help | Message support with your email + listing name |
| Seller Stripe setup help | Message support — we'll walk you through it |

---

*Thank you for being part of the SnatchIt beta. Your feedback directly shapes the product.*
