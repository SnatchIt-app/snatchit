# Day 7 — Legal / Trust Messaging Pack

**Version:** 1.0
**Date:** 2026-04-02
**Purpose:** Pre-approved copy for buyer protection, seller payouts, and legal-safe language throughout the SnatchIt app and communications.

---

## SECTION 1 — Buyer Protection Language (Checkout Flow)

Use these strings in the checkout UI, confirmation screens, and purchase-related push notifications.

### Checkout Screen (Before Payment)

> **Your payment is held securely until you confirm delivery.**
> When you receive your tickets and confirm in the app, the seller gets paid. If the seller doesn't send tickets within 24 hours, you get a full refund — no questions asked.

### Payment Confirmation Screen (After Successful Payment)

> **Payment received — your tickets are on the way.**
> Your payment is being held while the seller transfers your tickets. You'll get a notification when the seller marks them as sent. Once you confirm receipt, the transaction is complete.

### Transfer Status: Pending (Buyer's View)

> **Waiting for seller to send tickets.**
> The seller has 24 hours to transfer your tickets. If they don't, your payment will be automatically refunded.

### Transfer Status: Seller Sent (Buyer's View)

> **The seller has sent your tickets.**
> Please check your email or ticket account for the transfer. Once you've confirmed you received them, tap "Confirm Received" to complete the transaction.

### Transfer Status: Auto-Released (Buyer's View)

> **Transaction completed automatically.**
> The confirmation window has closed and the seller has been paid. If you have any issues with your tickets, please contact support.

### Dispute Filed (Buyer's View)

> **Your report has been received.**
> Our team is reviewing your case. Your payment remains on hold while we investigate. We'll reach out within 24 hours with an update.

### Refund Issued (Buyer's View)

> **Your refund has been processed.**
> A full refund has been issued to your original payment method. It may take 5–10 business days to appear on your statement.

---

## SECTION 2 — Seller Payout Language

Use these strings in the seller dashboard, payout screens, and seller-facing push notifications.

### Listing Sold (Seller's View)

> **Your listing has been sold!**
> Please transfer the tickets to the buyer as soon as possible. You have 24 hours to mark the transfer as sent, or the sale will be canceled and the buyer refunded.

### Transfer Marked as Sent (Seller's View)

> **Transfer marked as sent.**
> The buyer now has 72 hours to confirm receipt. Once they confirm (or the confirmation window closes), your payout will be released to your connected Stripe account.

### Payout Released (Seller's View)

> **Payout released!**
> Your earnings have been sent to your connected bank account via Stripe. Funds typically arrive within 2–5 business days, depending on your bank.

### Dispute Filed (Seller's View)

> **A buyer has reported an issue with this transaction.**
> Your payout is on hold while our team reviews the case. We may reach out for additional information. No action is needed from you right now.

### Transfer Expired (Seller's View)

> **This sale has been canceled.**
> The 24-hour transfer window expired before the tickets were marked as sent. The buyer has been refunded. The listing is available to relist if you still have the tickets.

---

## SECTION 3 — Words and Phrases to AVOID

These terms carry legal or regulatory implications that SnatchIt is not licensed to claim. Never use them in the app UI, marketing, support messages, push notifications, or documentation.

| DO NOT USE | WHY |
|------------|-----|
| **Escrow** | Implies SnatchIt is a licensed escrow agent. SnatchIt is not an escrow service — it holds payments via Stripe's standard PaymentIntent flow. |
| **Money-back guarantee** | Creates an enforceable warranty. SnatchIt provides refunds under specific conditions, not a blanket guarantee. |
| **Guaranteed delivery** | Implies SnatchIt guarantees the seller will perform. SnatchIt cannot guarantee third-party behavior. |
| **Insurance** / **Insured** | Implies SnatchIt carries insurance policies on transactions. It does not. |
| **100% safe** / **Risk-free** | No transaction is 100% safe. This creates misleading consumer expectations. |
| **Bank-level security** | Unless SnatchIt has SOC 2 or equivalent certification, this is misleading. |
| **Certified** / **Verified seller** | Unless SnatchIt runs identity verification (KYC) beyond Stripe Connect onboarding, these terms overstate the vetting process. |
| **Fiduciary** | Implies a legal fiduciary duty to buyers or sellers. SnatchIt does not have one. |
| **Funds are protected** | Implies a protection mechanism beyond what Stripe provides. |
| **We guarantee** | Any sentence starting with "We guarantee" creates potential liability. |
| **Instant refund** | Refunds take 5–10 business days. "Instant" is inaccurate. |
| **No fees** / **Free** | Unless the specific context is truly fee-free, this is misleading if service fees exist. |

---

## SECTION 4 — Safer Wording to Use Instead

| INSTEAD OF | USE |
|------------|-----|
| "Your money is in escrow" | "Your payment is held securely until delivery is confirmed" |
| "Money-back guarantee" | "Full refund if the seller doesn't deliver within 24 hours" |
| "Guaranteed delivery" | "Sellers have 24 hours to transfer tickets or the sale is automatically canceled" |
| "100% safe" | "Built with buyer protection in mind" |
| "Verified seller" | "Seller with connected payout account" |
| "Funds are protected" | "Your payment is held until you confirm receipt" |
| "We guarantee your tickets" | "We hold payment until delivery is confirmed, and issue refunds when sellers don't deliver" |
| "Instant refund" | "Refund issued — typically arrives in 5–10 business days" |
| "Risk-free purchase" | "Buy with confidence — payment held until tickets confirmed" |
| "Bank-level security" | "Payments processed securely via Stripe" |
| "Insured transaction" | "Transaction includes automatic refund protection for non-delivery" |

---

## SECTION 5 — Recommended Disclaimer (Settings / About / Terms)

Place a version of this disclaimer in the app's Terms screen, About section, or footer:

> **SnatchIt is a peer-to-peer marketplace for event tickets.** SnatchIt is not an escrow service, insurance provider, or financial institution. Payments are processed by Stripe, Inc. SnatchIt holds buyer payments via Stripe until delivery is confirmed by the buyer or the confirmation window closes. Refunds are issued automatically when sellers fail to deliver within the stated timeframe. SnatchIt does not guarantee the authenticity, validity, or delivery of tickets listed by third-party sellers. By using SnatchIt, you agree to our Terms of Service.

---

## SECTION 6 — Push Notification Copy (Complete Set)

| Event | Recipient | Message |
|-------|-----------|---------|
| Purchase successful | Buyer | "Payment received — your tickets are on the way." |
| Listing sold | Seller | "Your listing has been sold! Transfer the tickets within 24 hours." |
| Seller marked sent | Buyer | "The seller has sent your tickets. Check and confirm receipt." |
| Buyer confirmed | Seller | "Buyer confirmed receipt — your payout has been released!" |
| Transfer expired | Buyer | "The seller didn't deliver. Your refund has been processed." |
| Transfer expired | Seller | "Transfer expired — the sale has been canceled." |
| Auto-release triggered | Seller | "Confirmation window closed — your payout has been released." |
| Auto-release triggered | Buyer | "Transaction completed automatically." |
| Dispute filed | Buyer | "Your report has been received. We're reviewing your case." |
| Dispute filed | Seller | "A buyer reported an issue. Your payout is on hold pending review." |
| Dispute resolved (buyer wins) | Buyer | "Your refund has been processed." |
| Dispute resolved (seller wins) | Seller | "Case resolved — your payout has been released." |

---

*Review this messaging pack with legal counsel before going beyond private beta.*
