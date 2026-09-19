# Saved ticket-delivery preferences — plan (B, 2026-09-19)

**Goal.** The seller has the buyer's confirmed delivery destination the moment a sale settles, even if the buyer
never opens the app again.

**Scope.** Planning only. No product code or database changes. Independent of C's refund and release fixes.

**Evidence.** Everything below was read in source on A's `release/candidate-20260918` @ `7a1502a3`. It describes
the code, **not observed production behaviour** (the owner's standing restriction).

---

## 1 · What the code does today — the facts that shape the plan

| # | Fact | Source |
|---|---|---|
| F1 | **The destination belongs to the transfer and arrives after purchase.** `transfers.delivery_email` and `delivery_phone` are written by the buyer through `set_transfer_delivery_info`, and only when they open the transfer. | `011:71-72` · `0550:227` · receive screen form |
| F2 | **The seller's clock starts before any destination exists.** Settlement inserts the transfer with `expires_at = now() + 24h` and no delivery fields. | `20260906100000:140-143, :166-169` |
| F3 | **Expiry does not check for a destination.** Every `pending` transfer past `expires_at` expires and is refunded. Meanwhile "Mark as sent" is disabled while the destination is missing. So a buyer who never opens the app loses the seller the sale. | `0551:23` · `send/[id].tsx:148, :243` |
| F4 | **A verified phone is not guaranteed for buyers.** The phone-verification signup step exists **only on the candidate branch** (added `92cfe51c`, 8 Sep); `origin/main`'s signup has no phone step. Even in the new flow, the account is created at step 1 of 4, and nothing routes someone who quits back to verification. A verified phone is required to **list** — not to bid or buy. | `signupFlow.ts:4-19` · main's `signup.tsx` · `038:27` · `CreateListingScreen:418` |
| F5 | **Email is not verified anywhere.** `mailer_autoconfirm` is on. There is no OAuth sign-in, so there are no relay addresses. | `signupFlow.ts:10` |
| F6 | **Phone numbers are US-only, 10 digits.** | `DeliveryInfoForm:69, :78` |
| F7 | **The provider decides the destination type, and the listing fixes one method.** The form shows email only for `email` listings and phone only for `mobile_transfer` listings. The required field is therefore known **before anyone bids**. | `platformInstructions.ts` `transferMethods` · `DeliveryInfoForm:53-54` |
| F8 | **The destination must match the buyer's account on the provider, not on Snatch It.** DICE and Posh must "exactly match" the number on the buyer's account; Tixr must match the email. | `platformInstructions.ts:86, :99, :354` |
| F9 | **Nothing ties the method to the platform.** A DICE listing can be saved as `email`, and DICE cannot transfer by email. | `CreateListingScreen:660-661` vs `:309, :523` · no DB constraint |
| F10 | **Auction wins are not charged automatically.** The winner pays through `create-payment-intent` (`mode='auction'`, winner only, after the end), `on_session`. The code says off-session charges are something "we don't do". So an offline winner currently produces **no payment and no transfer**. | `create-payment-intent:586-606, :834-837` |
| F11 | **The buyer can change the destination after the seller has sent.** | `0550:237` |
| F12 | **The server does not require a destination before `mark_transfer_sent`.** This is A's F-XFER-3, reachable only by bypass. | A's `SPRINT_STATUS_20260917` §F-XFER-3 |
| F13 | **Bids are a direct insert under RLS, not an RPC.** Enforcing "captured before bidding" is therefore a policy or trigger check. | `PlaceBidScreen.tsx:146` · `070:22` |

**Provider matrix (F7):**
- **Phone only:** DICE, Posh, Fever, Shotgun
- **Email only:** Eventbrite, Tixr, Universe, See Tickets
- **Either:** AXS, Ticketmaster, SeatGeek, MLB Ballpark, StubHub, Vivid Seats, Gametime, Other

### Two corrections to the brief this plan was given

1. **"Email as an alternative" cannot apply per order.** The seller fixes one method on the listing, so a DICE
   buyer cannot choose email. The alternative lives at the level of the defaults: Settings holds both a phone and an
   email, and each order uses the one its listing needs.
2. **Capturing before bidding does not, by itself, complete an offline auction win.** Today the winner still has to
   open the app and pay (F10). It is still the right design: the payment step no longer depends on a form, and the
   destination is already in place if off-session charging is ever built. But it does not complete a win while the
   winner is offline.

---

## 2 · Recommended flow

**The principle:** confirm the destination **at commitment**, store it **with that listing's order**, and **copy it
onto the transfer in the same statement that settles the sale**. The seller's clock and the destination then start
together. A profile default is only ever a pre-fill; a seller never reads it.

**A · First commitment** — no saved destination of the type this listing needs:
1. The buyer taps **Place bid** or **Buy now**.
2. Before the bid or checkout sheet opens, one step asks: **Where should we send your tickets?**
   - If the listing needs a phone, pre-fill the SMS-verified number, then the profile phone, else leave it empty.
   - If the listing needs an email, pre-fill the account email.
3. The buyer confirms or edits. The value is saved as their default for that type **and** recorded against this
   listing.
4. The bid or checkout sheet opens with the destination shown on it.

**B · Later commitments.** The bid or checkout sheet shows a **Tickets go to** row above the action, with a
**Change** option. There is no extra step.

**C · Missing type.** If the buyer has only a phone saved and the listing needs an email (or the reverse), run step A
for the missing type only.

**D · Auctions.**
- The destination is recorded at the first bid on a listing. Raising the bid keeps it.
- Every active bid on the Bids screen shows **Delivers to …** with a **Change** option.
- On a win, the pay screen shows the destination with **Change**, before any money moves.
- Settlement copies it onto the transfer.
- An outbid buyer's destination is never shared.

**E · Settings → Ticket delivery.** A phone and an email default. Editing them never touches an existing bid or
order.

**F · After purchase.**
- The buyer's order screen shows the destination read-only, with **Change** while the transfer is `pending`, behind
  a warning.
- It is **frozen once the seller has sent** — enforced on the server.
- Legacy orders with no destination keep today's form as the fallback.

**G · Seller.** The send screen shows the destination from the first moment, as it already does once one exists.
**No phone number or email ever goes into a push notification** — in-app only.

---

## 3 · Exact proposed wording

**First-commitment step**
- Title: **Where should we send your tickets?**
- Body, phone listing: *The seller will transfer these through {Provider}, which sends tickets to a phone number. Use
  the number on your {Provider} account.*
- Body, email listing: *The seller will transfer these through {Provider}, which sends tickets to an email address.
  Use the email on your {Provider} account.*
- Field label: **Phone number on your {Provider} account** · **Email on your {Provider} account**
- Helper under a pre-filled verified phone: *Your verified Snatch It number. Change it if your {Provider} account uses
  a different one.*
- Helper under a pre-filled email: *Your Snatch It email. Change it if your {Provider} account uses a different one.*
- Sharing notice: *We share this with the seller only if you buy or win, and only so they can transfer your tickets.*
- Toggle, on by default: **Use this for future purchases**
- Button (neutral, not red — this is not the commitment): **Continue**
- Errors: *Enter a 10-digit US phone number.* · *Enter an email address.*

**Bid sheet, checkout and pay-after-win row**
- Label **Tickets go to**, then the full value — *(305) 555-4417* — shown in full so a typo is caught before commitment.
- Sub-line: *For your {Provider} account*
- Link: **Change**

**Per-order Change sheet**
- Title: **Change where these tickets go**
- Toggle, off by default: **Also make this my default**
- Button: **Save**

**Bids row**
- *Delivers to (305) 555-4417* · **Change**

**Settings → Ticket delivery**
- Intro: *Where sellers send tickets you buy. Most ticket apps use a phone number; some use email. We'll ask for the
  right one when a listing needs it.*
- Rows: **Phone for ticket transfers** · **Email for ticket transfers** — each shows its value or *Not set*
- Footer: *Changing these won't change tickets you've already bought or bids you've already placed. To change one of
  those, open it from Tickets or Bids.*
- Privacy line: *We share a destination with a seller only after you buy or win, and only for that order.*

**Order screen, buyer**
- While pending: **Sending to** {value} · **Change**
  - Confirmation: *The seller may already be sending to {old value}. Change it only if that one is wrong.* —
    **Change destination** / **Keep {old value}**
- After the seller sends: *The seller sent your tickets to this {phone number | email}. If they haven't arrived, tap
  Something's wrong.* The field is read-only.

**Seller, when a pending buyer changes it** — in-app only, no personal data in the push: *The buyer updated where to
send the tickets. Check the new details before you send.*

---

## 4 · Edge cases

| Case | Behaviour |
|---|---|
| No verified phone, phone listing | The field is empty and required. The bid or checkout sheet cannot open until it is filled. |
| Verified phone ≠ provider account number | The helper text invites a change. DICE and Posh copy states the numbers must match exactly (F8). |
| Saved phone only, listing needs email (or the reverse) | Ask for the missing type only. |
| Listing method the platform can't use (e.g. DICE + email, F9) | New listings: the form offers only the platform's methods. Existing mismatches need a count before anyone decides what to do with them — **a production count needs your authorisation**. |
| Default changed after bidding | Existing bids keep their recorded destination; the Bids row shows it. Nothing changes silently. |
| Default changed after purchase | The order is unchanged. |
| Buyer changes an order while `pending` | Allowed, with the warning. The seller gets the in-app notice. |
| Buyer changes an order after `seller_sent` | Refused by the server (closes F11). |
| Seller marks sent with no destination | Refused by the server (closes F12 for new orders). |
| Outbid bidder | Their destination is never copied or shared. |
| Auction winner who never pays (F10) | No transfer is created and nothing is shared. |
| Reservation lapses or the payment fails | The recorded destination stays with that (listing, buyer) pair, is never shared, and is purged under the retention rule. |
| Non-US number | Not accepted (F6). |
| Email typo | Read back in full on the commitment row. Email is not verified anywhere in the product (F5). |
| Legacy order with no destination | Today's post-purchase form remains. What happens to the seller's clock is Q3, for A. |
| Account deletion with open orders | Already blocked until transfers finish. |
| Old store client, after server enforcement | It cannot capture a destination, so its bids and checkouts would be refused. Enforcement ships only after the capturing client is live (§5, S3). |

---

## 5 · Implementation handoff

**Server — A owns merge and numbering. B can draft on request.**

| # | Change | Owner |
|---|---|---|
| S1 | **Two owner-only tables.** `buyer_delivery_defaults` (user_id, phone, email, updated_at). `order_delivery_destinations` (listing_id, buyer_id, method, destination, confirmed_at, source; PK listing_id + buyer_id). RLS allows own rows only; sellers get no read. Write RPCs `set_delivery_default` and `confirm_delivery_for_listing`, which validate method = the listing's `transfer_method` plus US-phone and email format. Four files per the repo rule: grant manifest, Gate-2 census, `expected_grants`, rollback. | B drafts · **A** |
| S2 | **Settlement copies the destination.** `settle_listing_for_payment` sets `delivery_email` or `delivery_phone` from the settled buyer's row in the same INSERT. It is the single funnel for `mark_listing_sold`, `complete_auction_payment` and `settle_verified_payment`. | **A** |
| S3 | **Enforce capture at commitment.** Bids through the INSERT policy or a trigger (F13); checkout in `create-payment-intent`. **Ships last**, after the capturing client is live. | **A** |
| S4 | `set_transfer_delivery_info` freezes at `seller_sent` (F11). | **A** |
| S5 | `mark_transfer_sent` refuses when no destination is present (F12). | **A** |
| S6 | Seller clock when no destination exists — Q3. | **A → owner** |

**Client — C.**

| # | Change |
|---|---|
| C1 | The destination step before the bid sheet (`PlaceBidScreen`) and checkout (`CheckoutNative`). |
| C2 | The **Tickets go to** row and Change sheet on the bid sheet, checkout, Bids and pay-after-win. |
| C3 | **Settings → Ticket delivery** screen and route. |
| C4 | Receive screen: read-only destination, Change while `pending`, frozen after. |
| C5 | Listing form: method chips limited to the platform's `transferMethods` (F9). |
| C6 | Keep `DeliveryInfoForm` as the legacy fallback only. |
| C7 | The wording in §3. The destination read is authoritative state, so it goes to A before merge. |

**Tests**
- **pgTAP:**
  - RLS: the buyer can read and write their own rows; a seller and another bidder are denied.
  - Settlement copies **only the settled buyer's** destination.
  - The freeze at `seller_sent` and the `mark_transfer_sent` refusal.
  - A method mismatch is refused.
  - Each with a negative control, and **one test through each of the three settle paths**.
- **Vitest:** the pre-fill precedence (verified phone → profile phone → empty) and "changing a default never
  rewrites an existing destination".

**Sequence:** C's stage-0 fixes → S1 + S2 → C1–C5 → S4 + S5 → S3 last. This plan does not depend on C's refund or
release work, and C's work does not depend on it.

---

## 6 · Questions for A — pending

I could not reach A from this session (cross-session messaging is unavailable in it), so these are written here for
A to answer.

- **Q1.** Is `settle_listing_for_payment` the right and only place to copy the destination?
- **Q2.** Is an owner-only table keyed (listing_id, buyer_id) acceptable for the pre-settlement destination, rather
  than `payments` (gated) or `bids`?
- **Q3.** For an order with no destination, should the seller's 24-hour window pause until one exists, or run as it
  does today? This is a money rule, for the owner to decide on A's framing.
- **Q4.** Is off-session winner charging planned? The plan is written against today's pay-after-win path.
- **Q5.** Should S4 and S5 ship together with S2, or separately?

---

## 7 · Decisions needed from the owner

1. **Server enforcement at bid and checkout (S3).** I recommend enforcing, but only after the capturing client ships,
   because older clients would otherwise be refused.
2. **A number other than the verified one.** Should it be SMS-verified, or accepted with a full read-back? I
   recommend read-back only for now. The existing OTP path (`verify-phone.tsx:88`, `phone_change`) changes the
   *account's* phone, so verifying a delivery-only number would be new SMS infrastructure.
3. **Retention.** Does the seller keep seeing the buyer's phone or email after the payout releases? I recommend
   masking it once the dispute window closes.
4. **Q3, once A frames it:** does the seller's clock pause while no destination exists?

**Separately, my own error.** Five of my design prototypes say an auction winner is *"charged automatically"*. The
code does not do that (F10). The app's real copy, *"Only charged if you win"*, is accurate. I've left the prototypes
untouched because this task excludes HTML; say the word and I'll correct them, so the line can't be copied into the
product.
