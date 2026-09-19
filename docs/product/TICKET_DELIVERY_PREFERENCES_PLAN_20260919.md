# Saved ticket-delivery preferences — implementation handoff (B, 2026-09-19, final)

**Status: direction approved by the owner, 2026-09-19.** This is a written handoff only. Nothing in it has been
implemented, and no product code or database file has changed.

**Goal.** The seller has the buyer's confirmed delivery destination the moment a sale creates the transfer, even if
the buyer never opens the app again.

**What the owner approved**
1. Collect and confirm a provider-compatible destination **before bidding or checkout**.
2. Attach that destination **when the sale creates the transfer**.
3. Keep saved defaults separate from existing bids and orders.
4. Prevent destination changes once the seller has marked the transfer sent.
5. Show a different delivery number back for explicit confirmation. **Never** alter the account's verified security
   phone.
6. Stage server enforcement so that older app versions are accounted for.
7. Hide seller access after the support and dispute period. **A verifies the timing and the exceptions.**
8. **Payment, refund and expiry rules stay unchanged in this feature.**

**Evidence base.** Source was read on A's `release/candidate-20260918` @ `7a1502a3`, plus the store-tagged client
`mobile/v1.0-build9-apple-review` (`4740091`) where stated. **This is code, not observed production behaviour.**

---

## 1 · Facts the plan rests on

| # | Fact | Source | Strength |
|---|---|---|---|
| F1 | The destination belongs to the transfer and is written by the buyer after purchase, when they open the transfer. | `011:71-72` · `0550:227` | Source |
| F2 | Settlement creates the transfer with **no destination** and `expires_at = now() + 24h`. | `20260906100000:140-143, :166-169` | **Candidate source only — see the qualification below** |
| F3 | Expiry does not check whether a destination ever arrived: `pending` past `expires_at` → `expired` → refund. The seller's "Mark as sent" is disabled while the destination is missing. | `0551:23` · `send/[id].tsx:148, :243` | **Candidate source only — see the qualification below** |
| F4 | A verified phone is **not guaranteed for buyers**. The phone step exists only on the candidate branch (`92cfe51c`); `origin/main`'s signup has none. Even there, the account is created at step 1 of 4, and nothing routes someone who quits back to verification. Verification gates **listing**, not bidding or buying. | `signupFlow.ts:4-19` · `038:27` · `CreateListingScreen:418` | Source |
| F5 | Email is never verified (`mailer_autoconfirm` on). There is no OAuth sign-in. | `signupFlow.ts:10` | Source (its own claim about the deployed config) |
| F6 | Phone numbers are US-only, 10 digits. | `DeliveryInfoForm:69, :78` | Source |
| F7 | The listing fixes **one** method (`email` or `mobile_transfer`), so the required field is known before anyone bids. Nothing ties the method to the platform — a DICE listing can say `email`. | `DeliveryInfoForm:53-54` · `CreateListingScreen:660-661` vs `:309, :523` | Source |
| F8 | **Auction winners are not charged automatically.** The winner pays on-session through `create-payment-intent` after the auction ends. An offline winner produces no payment and no transfer. | `create-payment-intent:586-606, :834-837` | Source |
| F9 | The buyer can change the destination after the seller has sent. | `0550:237` | Source |
| F10 | The server does not require a destination before `mark_transfer_sent` (reachable by bypass only). | A's `SPRINT_STATUS_20260917` §F-XFER-3 | A's derivation |
| F11 | Bids are a direct insert under RLS. Both the candidate and the store client show the server's error text to the bidder verbatim. | `PlaceBidScreen.tsx:146` · `070:22` · `Alert.alert('Bid failed', error.message)` (candidate, and store tag `:117`) | Source |
| F12 | There is **no app-version signal and no runtime-config table** in this migration chain. `x-client-info` is only an allowed CORS header — the supabase-js library's, not the app's version. | grep across `supabase/functions` and `supabase/migrations` | Source |
| F13 | Transfer states: `pending`, `seller_sent`, `buyer_confirmed`, `disputed`, `expired`, `auto_released`, `reversed`. | `src/types/index.ts:223-230` | Source |

> **Qualification on F2 and F3 (owner's instruction).** The 24-hour expiry and the refund on expiry are read from the
> **candidate branch's** migrations. Whether the deployed database carries this settlement body and this expiry rule
> has **not been reconciled** with deployed behaviour. Until A does that (item A-1), treat the consequence — *"a buyer
> who never reopens the app loses the seller the sale"* — as a property of the candidate code, not a statement about
> production. **This feature changes neither rule either way.**

---

## 2 · Provider requirements — what our app encodes versus what has been verified

Every provider claim in this plan comes from **our own app and our own research**. **None has been independently
re-verified with the providers for this plan.** There are three separate layers, and they must not be conflated:

| Layer | Where it lives | Status |
|---|---|---|
| **A · Encoded in our app** | `src/lib/platformInstructions.ts` — the `transferMethods` per platform and the step copy | What the app does today |
| **B · Our team's research** | `docs/product/TRANSFER_METHOD_RESEARCH.md`, **dated 2026-06-12**. Each claim is marked ✅ (confirmed from an official source, with URL) or ⚠️ (unverified) | Recorded by us, about three months old |
| **C · Independently verified with the provider for this plan** | — | **None.** Required before the §4 wording ships (handoff item C-8) |

**Per provider — app encoding against research**

| Provider | App encodes (A) | Research says (B, 12 Jun) | Agreement |
|---|---|---|---|
| **DICE** | phone | ✅ app-only, to a phone contact; buyer's DICE account on that number; no email or link | Agree |
| **Posh** | phone | ✅ app-only, by recipient phone; accounts are phone-based | Agree |
| **Tixr** | email | ✅ by recipient email; accept with the same email | Agree |
| **Universe** | email | ✅ ownership transfer by email | Agree |
| **See Tickets** | email | ✅ account-to-account share | Agree |
| **Eventbrite** | email | ✅ no account transfer; the purchaser edits the attendee email, which the buyer claims | Agree |
| **Ticketmaster** | either | ✅ email or phone/text; accept with the same email | Agree |
| **AXS** | either | ✅ email or phone, plus name | Agree |
| **SeatGeek** | either | ✅ name, username, email or phone | Agree |
| **MLB Ballpark** | either | ✅ email, phone contacts, **or a share link** | Agree; the link option isn't modelled |
| **Fever** | **phone** | ✅ **shareable link** | **Diverges.** The app asks for a phone, and its seller steps say to share the link "through Snatch It chat" — **the app has no chat** |
| **Shotgun** | **phone** | ✅ **shareable link** ("Send as a gift") | **Diverges**, same as Fever |
| **StubHub · Vivid Seats · Gametime** | either | ✅ re-transfer depends on the **underlying** delivery (Ticketmaster, AXS, DICE, PDF, in-app) | **Diverges.** The real method can't be known from the listing's platform |
| **Other** | either | — | Nothing to compare |

**What that means for this feature**
- **Account-match providers** (DICE, Posh, Tixr, Universe, See Tickets, Eventbrite, and email on Ticketmaster):
  the wording asks for the phone or email **on the buyer's {Provider} account**.
- **Link providers** (Fever, Shotgun): no account needs to match. The destination is simply where the seller sends
  the link. The wording must not claim an account requirement. **Decision O-1.**
- **Resale-sourced listings** (StubHub, Vivid Seats, Gametime): the method depends on how the seller received the
  ticket. **Decision O-2.**

---

## 3 · The flow

**Principle.** The destination is confirmed **at commitment**, stored **against that listing's order**, and
**copied onto the transfer by the same statement that creates it**. A profile default is only ever a pre-fill; a
seller never reads it.

- **First commitment — no saved destination of the type the listing needs.**
  - One step appears before the bid or checkout sheet.
  - Pre-fill: for a phone listing, the SMS-verified number, then the profile phone, else empty. For an email listing,
    the account email.
  - On confirm, the value is saved as the default for that type **and** recorded against the listing.
- **Later commitments.** A **Tickets go to** row with **Change** sits on the bid sheet, checkout and the
  pay-after-win screen. There is no extra step.
- **A different number from the verified one.** It is read back for explicit confirmation (§4). It is stored as a
  delivery destination only. `auth.users.phone` and `phone_confirmed_at` are never touched. The existing OTP path
  (`verify-phone.tsx:88`, `phone_change`) is **not** used for delivery numbers.
- **Missing type** (a phone is saved but the listing needs an email, or the reverse). Ask for the missing type only.
- **Auctions.**
  - The destination is recorded at the first bid on a listing and kept on raises.
  - Each active bid on the Bids screen shows **Delivers to …** with **Change**.
  - An outbid buyer's destination is never shared.
  - Under today's pay-after-win path (F8, unchanged by this feature), the pay screen shows the destination before
    money moves.
- **Settings → Ticket delivery.** Phone and email defaults. An edit never touches an existing bid or order.
- **After purchase.** **Change** is available while the transfer is `pending`, behind a warning. **Frozen from
  `seller_sent`**, enforced by the server. Legacy orders with no destination keep today's form as the fallback.
- **Seller.** Sees the destination in-app only, never in a push notification. Access ends after the retention window
  (§6).

---

## 4 · Exact wording

**First-commitment step — account-match providers**
- Title: **Where should we send your tickets?**
- Body, phone: *The seller will transfer these through {Provider}, which sends tickets to a phone number. Use the
  number on your {Provider} account.*
- Body, email: *The seller will transfer these through {Provider}, which sends tickets to an email address. Use the
  email on your {Provider} account.*
- Label: **Phone number on your {Provider} account** · **Email on your {Provider} account**
- Pre-filled helper, phone: *Your verified Snatch It number. Change it if your {Provider} account uses a different
  one.*
- Pre-filled helper, email: *Your Snatch It email. Change it if your {Provider} account uses a different one.*
- Sharing: *We share this with the seller only if you buy or win, and only so they can transfer your tickets.*
- Toggle, on by default: **Use this for future purchases**
- Button (neutral — not the commitment): **Continue**
- Errors: *Enter a 10-digit US phone number.* · *Enter an email address.*

**First-commitment step — link providers** (subject to O-1)
- Body: *{Provider} tickets are transferred by link. Tell us where the seller should send yours.*
- Label: **Phone number for your transfer link**

**Read-back when the number differs from the verified one**
- Title: **Send tickets to (305) 555-9876?**
- Body: *This isn't your verified number, (305) 555-4417. We'll use it only for ticket delivery — the number you sign
  in with doesn't change.*
- Buttons: **Yes, use this number** · **Edit**

**Commitment row** (bid sheet, checkout, pay-after-win)
- **Tickets go to** — the full value, e.g. *(305) 555-4417*, shown in full so a typo is caught before commitment
- Sub-line: *For your {Provider} account*
- Link: **Change**

**Per-order Change sheet**
- Title: **Change where these tickets go**
- Toggle, off by default: **Also make this my default**
- Button: **Save**

**Bids row** — *Delivers to (305) 555-4417* · **Change**

**Settings → Ticket delivery**
- Intro: *Where sellers send tickets you buy. Most ticket apps use a phone number; some use email. We'll ask for the
  right one when a listing needs it.*
- Rows: **Phone for ticket transfers** · **Email for ticket transfers**, each showing its value or *Not set*
- Footer: *Changing these won't change tickets you've already bought or bids you've already placed. To change one of
  those, open it from Tickets or Bids.*
- Privacy: *We share a destination with a seller only after you buy or win, and only for that order.*

**Buyer order screen**
- While pending: **Sending to** {value} · **Change**
  - Confirmation: *The seller may already be sending to {old}. Change it only if that one is wrong.* —
    **Change destination** / **Keep {old}**
- From `seller_sent`: *The seller sent your tickets to this {phone number | email}. If they haven't arrived, tap
  Something's wrong.* Read-only.

**Seller notice when a pending buyer changes it** (in-app; no personal data in the push) — *The buyer updated where
to send the tickets. Check the new details before you send.*

**Server refusal shown by an older app** (enforcement stages E3 and E4) — *To bid, update Snatch It — we now need to
know where to send your tickets.* An old client displays the server's message verbatim (F11), so these are the exact
words it will show.

---

## 5 · Edge cases

| Case | Behaviour |
|---|---|
| No verified phone, phone listing | Field empty and required. The bid or checkout sheet cannot open until it is filled. |
| Different number from the verified one | Read back for explicit confirmation. The account phone is unchanged. |
| Saved phone only, listing needs email (or the reverse) | Ask for the missing type only. |
| Listing method the platform can't use (DICE + email, F7) | New listings: methods limited to the platform's. Existing mismatches: count them in the sandbox first. **A production count needs owner authorisation.** |
| Default changed after bidding or buying | Existing bids and orders keep their recorded destination. |
| Buyer changes an order while `pending` | Allowed, with the warning; the seller gets the in-app notice. |
| Buyer changes an order from `seller_sent` on | Refused by the server. |
| Seller marks sent with no destination | Refused by the server (closes F10). |
| Outbid bidder | Their destination is never copied or shared. |
| Winner who never pays (F8) | No transfer, nothing shared. **Unchanged by this feature.** |
| Legacy order with no destination | Today's post-purchase form. The seller's clock is **unchanged** (approval 8). |
| Old app version | Stages E0–E2 never refuse it; E3 and E4 refuse it with the update message above. |
| Non-US number | Not accepted (F6). |
| Email typo | Read back in full on the commitment row. Email is not verified anywhere (F5). |
| `disputed`, chargeback or open support case | Seller access stays open until it closes (§6). |

---

## 6 · Seller access retention — proposal; A verifies the timing and exceptions

- **Proposal.** The seller sees the full destination while the transfer is `pending` or `seller_sent`, and for
  **14 days** after it reaches a terminal state (`buyer_confirmed`, `auto_released`, `expired`, `reversed`). After
  that, a masked value: *(•••) •••-4417* or *t•••@example.test*.
- **Exceptions that keep it visible.** The transfer is `disputed`, a chargeback is open on its payment, or a support
  case is open. Ops and admin access is unchanged.
- **Mechanism.** The seller reads the destination through an RPC that masks it after the window. The stored values
  are kept for support and disputes; nothing is deleted.
- **Sequencing constraint.** Old send screens select `delivery_email` and `delivery_phone` directly
  (`send/[id].tsx:81`). Revoking those columns would fail that **whole** query, not just blank two fields. So the
  column revoke ships only after the RPC-reading client is live — the same staging logic as §7.
- **A verifies (A-2):** that 14 days is right, the exact exception list, and how a chargeback is detected.

---

## 7 · Implementation handoff

**Server — A owns merge and numbering; B can draft on request.**

| # | Change | Stage | Owner |
|---|---|---|---|
| S1 | **Two owner-only tables.** `buyer_delivery_defaults` (user_id, phone, email, updated_at). `order_delivery_destinations` (listing_id, buyer_id, method, destination, confirmed_at, source; PK listing_id + buyer_id). RLS allows own rows only; no seller read. RPCs `set_delivery_default` and `confirm_delivery_for_listing` validate method = the listing's `transfer_method`, plus phone and email format. Four files per the repo rule: grant manifest, Gate-2 census, `expected_grants`, rollback. | E0 | B drafts · **A** |
| S2 | **Attach at creation.** `settle_listing_for_payment` sets the transfer's destination from the settled buyer's row **in the same INSERT**. It is the single funnel for `mark_listing_sold`, `complete_auction_payment` and `settle_verified_payment`. | E0 | **A** |
| S3 | `mark_transfer_sent` refuses when no destination is present. Safe on day one: every app version already disables the button in that state (F3), so it only closes the bypass (F10). **A to confirm it changes no payment, refund or expiry rule (A-3).** | E0 | **A** |
| S4 | `set_transfer_delivery_info` refuses from `seller_sent` on (F9). Ships **with or after S3**, so no `seller_sent` transfer can be left without a destination. | E0 | **A** |
| S5 | **App-version signal.** The client sends its version on bid and checkout; the server records it. Needed because none exists (F12). | E1 | **C** client · **A** server |
| S6 | Retention RPC and masking (§6). | E2 | **A** |
| S7 | **Refuse bids without a destination** — a trigger on `bids` insert carrying the §4 update message. | E3 | **A** |
| S8 | **Refuse checkout without a destination** in `create-payment-intent`. **First verify how the store client renders that function's error (A-4).** | E3 | **A** |
| S9 | Revoke direct seller SELECT on the delivery columns. | E4 | **A** |

**Enforcement stages** — each lands as its own migration. None is a flag: there is no audited runtime-config
mechanism in this chain, and CLAUDE.md forbids flipping flags by migration.

- **E0 — accept and attach.** S1–S4. Nothing a normal user does is refused. Old apps keep working; their orders use
  the post-purchase fallback.
- **E1 — measure.** The capturing client ships with the version signal (S5).
- **E2 — retention RPC.** The client switches the seller read to the RPC.
- **E3 — enforce.** Only when the measured share of old versions is below a threshold **the owner sets from E1 data**.
- **E4 — revoke direct column access**, after the RPC client is live.

**Client — C**

| # | Change |
|---|---|
| C-1 | The destination step before `PlaceBidScreen` and `CheckoutNative`. |
| C-2 | **Tickets go to** row and Change sheet on the bid sheet, checkout, Bids and pay-after-win. |
| C-3 | The different-number read-back (§4). It never calls `updateUser({ phone })`. |
| C-4 | **Settings → Ticket delivery** screen and route. |
| C-5 | Receive screen: read-only from `seller_sent`; Change with warning while `pending`. |
| C-6 | Listing form: method chips limited to the platform's `transferMethods` (F7). |
| C-7 | Send the app version on bid and checkout (S5); switch the seller read to the retention RPC (S6). |
| C-8 | **Before any §4 wording ships:** re-verify each provider's account-match rule against its current official help page (§2, layer C). Record the date and URL. |
| C-9 | Fix the Fever and Shotgun seller steps, which point to a Snatch It chat that doesn't exist (per O-1). |

The destination read is authoritative state, so C routes it to A before merge. None of this touches C's
refund/release work, or its gated files (`payments.ts`, `checkout/*`, `signOut.ts`).

**Tests**
- **pgTAP:**
  - RLS: the buyer reads and writes their own rows; a seller and any other bidder are denied.
  - S2 copies **only** the settled buyer's destination, with **one test through each of the three settle paths**.
  - S3 refusal and S4 freeze, each with a negative control.
  - Method mismatch refused.
  - The masked read after the window, and unmasked for `disputed`.
- **Vitest:**
  - Pre-fill precedence.
  - A default change never rewrites an existing destination.
  - The read-back appears exactly when the entered number differs from the verified one.

**Out of scope, by the owner's approval 8:** any change to payment, refund or expiry rules — including pausing the
seller's clock while no destination exists, and off-session winner charging.

---

## 8 · Open items

**For A** — cross-session messaging is unavailable from B's session, so these are written here.

- **A-1.** Reconcile F2 and F3 (24-hour expiry, refund on expiry) with **deployed** behaviour. Until then, the
  qualification in §1 stands.
- **A-2.** Verify the retention timing and exceptions (§6).
- **A-3.** Confirm that S3 (`mark_transfer_sent` refusal) changes no payment, refund or expiry rule.
- **A-4.** Confirm how the store client renders a `create-payment-intent` error before S8 relies on it.
- **A-5.** Confirm that `settle_listing_for_payment` is the only place to attach the destination (S2), and that an
  owner-only table keyed (listing_id, buyer_id) is acceptable instead of `payments` or `bids`.

**For the owner — two decisions now, one later**

- **O-1 · Link providers (Fever, Shotgun).** The app collects a phone and tells sellers to share the link through a
  chat that doesn't exist. **Recommendation:** keep collecting a phone as the channel for the link, relabel it
  honestly (§4), and change the seller step to "text the link to the buyer's number". The alternative is email.
- **O-2 · Resale-sourced listings (StubHub, Vivid Seats, Gametime).** The listing's platform doesn't tell us the real
  method. **Recommendation:** when a seller lists a resale-sourced ticket, ask which platform it was delivered on, and
  derive the method from that. This adds one field to selling.
- **O-3 · later.** The old-version threshold for E3, set from E1's data.

---

## 9 · Record of the prototype copy correction

The false claim that an auction winner's card is *"charged automatically"* was mine. It appeared in five design
prototypes and has been corrected at `c3aa96c4`, as authorised:
- **14 occurrences** replaced with wording taken from the product itself — *"If you win, you'll pay … total"*
  (`bidEntry.ts:111`) and *"Transactions are final once payment is confirmed"* (`legal.tsx:199-200`).
- Verified: zero remain, every inline script parses, and all five files render the corrected line with no errors.
- The six *"payout released … automatically"* lines were left alone deliberately. They describe auto-release, which
  the code does perform.
- One adjacent line was **not** changed, as it was outside the authorisation: *"A bid is a commitment"* is my
  wording, not the product's, and no enforcement of it was found (F8). Flagged so it isn't copied into the product
  unexamined.
