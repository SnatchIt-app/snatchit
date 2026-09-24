# Policy promises: one decision list (A, 2026-09-24)

For the owner. Every string is quoted from C's app head `91062ab1` (v3/midnight-app). Each item gives **keep / reword
(exact text) / remove**, plus the operational fact that backs it. Source anchors are at the release gate `037092f0`.
Apple guideline 1.2 (checked 2026-09-24) requires, for apps with user-generated content: a filter for objectionable
material, a way to report it with "timely responses to concerns", **the ability to block abusive users**, and published
contact information. It names no number of hours.

**The fact under items 1–4:** nothing notifies anyone when a report arrives. Operator alerts are not delivered, neither
admin has an active push token, and email is off. Any promised response time therefore depends on someone checking the
console by hand.

## Reports and moderation

1. `app/report/[type]/[id].tsx:78`, "Thanks for letting us know. We review reports within 24 hours and act on what we
   find."
   - **Keep only if you will check reports at least daily.** Otherwise reword: "Thanks for letting us know. We review
     reports and act on what we find."
2. `app/settings/privacy.tsx:144`, "Reports are reviewed by the Snatch It team within 24 hours."
   - Same condition as 1. Otherwise reword: "Reports are reviewed by the Snatch It team."
3. `app/report/[type]/[id].tsx:92`, "Our team reviews every report and may remove content or suspend accounts that
   violate our rules."
   - **Keep, on 1's condition.** "May … suspend" is a reserved right.
   - Fact: the product itself can only block an account from creating listings. Account suspension is rejected as not
     supported (115:720). A suspension would be a manual Supabase Auth ban.
4. `app/report/[type]/[id].tsx:134`, "Reports are reviewed by the Snatch It team. False or repeated bad-faith reports
   may result in your account being suspended."
   - **Keep**, on the same terms as 3.
5. `privacy.tsx:145`, "Listings or accounts that violate our rules may be removed, suspended, or permanently banned.";
   `legal.tsx:187`, "Snatch It may suspend or terminate any account at its sole discretion."; `legal.tsx:247`, "violating
   listings are removed and offending accounts may be suspended or banned."
   - **Keep**; these are reserved rights.
   - **Your decision:** is a manual ban your "ability to block abusive users" under Apple 1.2? The in-product
     restriction only stops new listings.
6. `src/lib/transfer/transferState.ts:230` (a buyer's report on an order), "Our team typically reviews within 24 hours.
   The seller's payout is frozen until this is resolved."
   - **Remove the first sentence** unless you commit to resolving order reports within 24 hours.
   - Fact: the freeze is enforced (0550; every payout path). 5 order reports are open, and none has ever been resolved:
     A's authorised read, 20:30:20Z today.
7. `app/settings/support.tsx:68`, "We aim to respond within 1 to 2 business days."
   - **Keep if you answer support@snatchitapp.com on that schedule.** Otherwise reword: "We'll reply by email as soon
     as we can."
   - A cannot see the inbox.

## Seller commitment

8. `src/screens/CreateListingScreen.tsx:911`, "I confirm I own these tickets and will transfer them within 24 hours of
   sale."
   - **Keep.** It is enforced by its consequence: every order gets a send deadline of sale + 24 h (061:111).
   - If the seller hasn't marked the tickets sent by then, the expiry job expires the order and refunds the buyer. That
     code has been live since 2026-09-23; no end-to-end expiry has yet been observed in production.

## Legal: where the money is and when the seller is paid

**The fact under items 9 and 10:**
- The charge lands in Snatch It's Stripe account; there is no destination charge (create-payment-intent :1072).
- The seller's payout is a separate Stripe transfer (`_shared/payouts.ts:182`). It is made only after the order is
  released, which happens in one of four ways:
  - the buyer confirms;
  - no report is made and the order is released, either automatically after the review period (low-risk orders only;
    orders of $200 or more are never released on silence; medium-risk orders are held, high-risk orders are reviewed)
    or by an operator;
  - a report is resolved in the seller's favour.
- A report freezes the payout.
- The current text ("held … until the buyer confirms receipt … or the auto-release window expires, at which point …
  released") leaves out holds, reviews, operator release and seller-wins. It also implies the payout is immediate.

9. `app/settings/legal.tsx:87-91`. **Reword to:**
   "All payments are processed by third-party payment providers (currently Stripe). Snatch It does not store payment
   card details. The buyer's payment is collected into Snatch It's Stripe account. The seller's net payout is sent to
   the seller's connected Stripe account after the order is released: when the buyer confirms receipt; when no problem
   has been reported and Snatch It releases the order, automatically after the review period or after a manual review;
   or when a reported problem is resolved in the seller's favour. Depending on an order's risk and value, a payout may
   be held or reviewed before release. A buyer's report freezes the payout until it is resolved."
10. `app/settings/legal.tsx:213-216` (Terms §6). **Reword to:**
   "Under our protected payment flow, the buyer's payment is collected into Snatch It's Stripe account, and the seller's
   net is transferred to their connected Stripe account only after the order is released: when the buyer confirms
   receipt; when no problem has been reported and Snatch It releases the order, automatically after the review period
   or after a manual review; or when a reported problem is resolved in the seller's favour. A payout may be held or
   reviewed first, depending on the order's risk and value, and a buyer's report freezes it until resolved."

## Refunds

**The fact under items 11 and 12:**
- An unsent order is refunded automatically by the expiry job; this is in the code, but no expiry has yet been observed
  end to end in production.
- An outcome in the buyer's favour records that a refund is due. The refund itself is made by hand in the Stripe
  Dashboard, because the automatic refund executor is switched off.
- Partial refunds are made by hand.
- The current text ("transactions are final … does not guarantee refunds") contradicts the automatic expiry refund.

11. `legal.tsx:83-84`, "Once payment is processed and confirmed, transactions are final."; `legal.tsx:205-206`,
    "Transactions are final once payment is confirmed. Snatch It does not guarantee refunds, returns, or exchanges."
    **Reword to:**
    - At :83-84: "A sale is final once the order is released to the seller, except as described in these terms."
    - At :205-206: "If the seller does not mark the tickets as sent within 24 hours of the sale, the order expires and
      the buyer is refunded. If the buyer reports a problem, Snatch It decides the outcome, which may include a full or
      partial refund. Otherwise Snatch It does not offer refunds, returns or exchanges."
12. App Review purchase refund (the sentence is withheld from the review notes today). **Use:** "If you complete a
    purchase during review, we will refund it in full."
    - **Only if you commit** to refunding it by hand in the Stripe Dashboard. Nothing alerts you to a purchase, so
      during review you would need to check Stripe.
    - Backstop: if the demo seller never marks orders sent, the 24-hour expiry refunds the purchase automatically. That
      path has not yet been observed in production.

## Not verified by A

- The support inbox.
- Whether a report creates an operator case automatically.
- Whether any user-to-user "block" feature exists in the app.
- The 10% fee figures in legal.tsx.
