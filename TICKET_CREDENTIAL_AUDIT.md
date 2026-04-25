# SnatchIt V1 Protocol A — Ticket Credential Architecture Audit

**Date:** March 30, 2026
**Role:** Principal Backend Architect / Mobile Security Architect / Fraud Systems Engineer / Product Infrastructure Auditor
**Scope:** V1 Protocol A (Auction / Marketplace Sale) ONLY — no blockchain, NFC, Protocol B/C, or V2/V3 future systems

---

## SECTION 1 — Executive Verdict

### Is the V1 Protocol A Ticket Credential Architecture actually feasible in the current app?

No. The current app has zero credential infrastructure. There are no rotating QR codes, no nonces, no device binding, no scanner endpoint, no credential issuance pipeline, no revocation system, and no screenshot protection. The entire Ticket Credential Architecture described in the trust document exists only on paper. The app today is a marketplace with Stripe payments, a transfer state machine, and push notifications. That is all.

However — and this is critical — roughly 40% of the Protocol A flow IS built and battle-tested: the auction/buy-now lifecycle, Stripe payment capture, webhook-driven transfer creation, seller payout via Connect, and the transfer state machine (pending → seller_sent → buyer_confirmed). This foundation is solid. The question is not "can we build the credential layer?" but "how much of the credential layer do we actually need for private beta, and what gives us a real anti-scam moat without the full rotating-QR system?"

### What is the biggest lie/risk in the current architecture document?

The document implies SnatchIt issues and controls the ticket credential end-to-end — that SnatchIt generates the QR code the buyer uses to enter the venue. This is false for V1. SnatchIt does not issue tickets. It facilitates the resale of tickets that were originally issued by Ticketmaster, AXS, SeatGeek, or other primary issuers. SnatchIt has no relationship with venues, no scanner hardware, and no ability to generate a credential that a venue scanner would accept. The "rotating QR" architecture would only work at events where SnatchIt IS the primary ticketing provider or has a direct venue integration. For resale — which is the entire V1 use case — the "credential" is actually the transfer of an existing ticket from the seller's account to the buyer's account on the original ticketing platform. SnatchIt's role is to make that transfer trustworthy, not to replace the ticket itself.

### What is the strongest realistic trust moat SnatchIt can deliver in private beta?

An escrow-style payment flow with delayed payout release. This is the single most powerful anti-scam mechanism available without building credential infrastructure:

1. Buyer pays. SnatchIt holds the funds (Stripe does not immediately transfer to seller).
2. Seller transfers the ticket via the original platform (Ticketmaster mobile transfer, AXS email, etc.).
3. Buyer confirms receipt in the app.
4. SnatchIt releases payout to seller only after buyer confirmation (or after a buyer-protection window expires without a dispute).

This is exactly what the current app is 80% of the way toward. The missing piece is that the stripe-webhook currently triggers an immediate Stripe Transfer to the seller on payment success. The fix is to defer that transfer until buyer confirmation or protection window expiry.

---

## SECTION 2 — Protocol A Architecture Explained End-to-End

### The Real-World Flow (What Actually Happens)

**Phase 1: Listing**

The seller has tickets in their Ticketmaster/AXS/other account. They create a listing in SnatchIt specifying event, venue, ticket type, quantity, transfer method (mobile_transfer or email), starting bid, optional buy-now price, and auction duration.

The seller is NOT uploading the ticket itself. They are listing the right to receive a transfer of a ticket from a specific platform. This is a critical distinction.

**Phase 2: Auction / Buy Now**

For auction: bidders place bids with 3-second rate limiting and shill-bid prevention. When the auction ends (auto_finalize_expired_auctions RPC), the winner is determined. For buy-now: the buyer reserves the listing for 10 minutes (reserve_buy_now RPC with FOR UPDATE lock).

**Phase 3: Payment Capture**

The winner/buyer navigates to checkout. The app calls create-payment-intent (edge function) which creates a Stripe PaymentIntent. The buyer completes payment via Stripe PaymentSheet (Apple Pay, Google Pay, or card). Stripe fires payment_intent.succeeded webhook.

**Phase 4: Transfer Creation (Current Implementation)**

The stripe-webhook handler: (a) marks payment as succeeded, (b) calls mark_listing_sold or complete_auction_payment RPC, (c) inserts a transfer row (status: pending, expires in 24h), (d) creates a Stripe Transfer to the seller's Connect account immediately, (e) sends push notifications to both parties.

**Phase 5: Ticket Transfer (Outside SnatchIt)**

The seller goes to Ticketmaster (or AXS, etc.) and initiates a mobile transfer to the buyer's email/phone. This happens entirely outside SnatchIt. SnatchIt cannot verify, automate, or control this step.

The seller then taps "Mark as Sent" in the app (mark_transfer_sent RPC: pending → seller_sent). The buyer receives the ticket in their Ticketmaster account, opens SnatchIt, and taps "Confirm Received" (confirm_transfer_received RPC: seller_sent → buyer_confirmed).

**Phase 6: Payout (Current — Immediate)**

Currently, the seller receives their payout immediately upon payment success (step 4d). This is the biggest gap — the payout happens before the seller even transfers the ticket.

**Phase 6: Payout (What Should Happen)**

The Stripe Transfer should be deferred. The payout should only be released when one of these conditions is met: (a) buyer confirms receipt, (b) buyer-protection window (e.g., 48 hours) expires without a dispute, or (c) an admin manually releases the payout after dispute resolution.

### What "Atomic Credential Swap" Actually Means for V1

In the document, "atomic credential swap" implies that when the sale completes, the seller's credential is revoked and the buyer's credential is issued simultaneously. In reality, for V1, this translates to: the seller transfers the ticket on the original platform, the buyer confirms receipt, and SnatchIt releases the payout. The "atomicity" is not technical (SnatchIt cannot control Ticketmaster's transfer API) — it is financial. SnatchIt holds the money until the transfer is confirmed. That is the only enforcement mechanism available.

---

## SECTION 3 — Resource Requirements

### A. Backend Infrastructure

**Already have:**
- Supabase (PostgreSQL, Auth, RLS, Edge Functions)
- 8 tables with proper constraints, indexes, and RLS
- 6 edge functions (Deno) covering payment, payout, push, auction finalization
- DB-backed rate limiting (check_rate_limit RPC)

**Must add for V1:**

1. **Payout orchestration job** — A scheduled edge function or pg_cron job that checks for transfers where: buyer confirmed OR protection window expired without dispute. When triggered, it executes the Stripe Transfer (currently hardcoded in stripe-webhook). This is the single most important backend addition.

2. **Dispute/refund edge function** — An admin-callable function that: freezes a pending payout, initiates a Stripe refund if warranted, and updates transfer status to disputed. Does not need to be user-facing in V1 — can be admin-only via SQL or a simple admin endpoint.

3. **Transfer expiry enforcement** — A scheduled job (pg_cron or edge function on a timer) that marks transfers as expired when expires_at passes and status is still pending. Currently, expires_at is set but never enforced.

4. **Observability** — Sentry is integrated (SDK in app.json) but not yet wired to edge functions. Add structured logging/alerting for: failed payouts, disputed transfers, expired transfers, webhook failures.

**Nice-to-have but deferrable:**
- Redis/Upstash cache (not needed at beta scale — Supabase handles it)
- Message queue (not needed — webhook + pg_cron sufficient for beta)
- Separate API framework (not needed — Supabase edge functions are sufficient)

### B. Third-Party Services

**Already integrated:**
- Stripe Payments (PaymentIntents, PaymentSheet)
- Stripe Connect Express (seller onboarding, account creation)
- Stripe Transfers (payouts to sellers)
- Stripe Webhooks (payment_intent.succeeded/failed)
- Expo Push Notifications (via send-push edge function)
- Sentry (error tracking SDK in app config)

**Must add for V1:**

1. **Stripe: account.updated webhook handler** — Required to know when a seller's Connect onboarding is complete. Currently, the app creates the account link but never learns the result. Without this, you cannot reliably gate sellers from listing until their payout setup is verified.

2. **Stripe: charge.dispute.created webhook handler** — Required to freeze payouts when a buyer files a chargeback through their bank. Without this, the platform has no awareness of chargebacks.

**Should add but can defer past private beta:**

3. **Identity verification (Persona/Jumio)** — For verified seller/buyer tiers. The profiles table has is_verified_buyer and is_verified_seller flags but no verification flow. Can be manual (admin review) for private beta.

4. **Twilio (SMS/phone verification)** — For phone number verification. The profiles table has a phone column but no verification. Can be deferred — email auth is sufficient for beta.

5. **Device fingerprinting (Fingerprint.js / DeviceCheck)** — For single-device enforcement and burner-account detection. Not needed for private beta — this is a scale-phase anti-fraud measure.

### C. Mobile App Resources

**Already have:**
- React Native 0.81.5 + Expo 54 (New Architecture enabled)
- Expo Router (file-based navigation)
- Stripe React Native SDK 0.50.3 (PaymentSheet integration)
- Expo Notifications (push tokens, registration)
- Expo Image Picker (listing photos)
- AsyncStorage (session persistence)

**Must add for V1:**
- Nothing mandatory for MVP. The current mobile stack is sufficient for the escrow-based trust flow.

**Not feasible in current Expo setup (defer to V2):**

1. **Screenshot detection** — Requires native modules (expo-screen-capture can detect, but reliable blocking requires custom native code). Not available in Expo Go. In a dev build, expo-screen-capture can show a warning but cannot prevent screenshots on Android.

2. **Screen recording protection** — iOS has FLAG_SECURE equivalent via UIScreen.captured observation. Android has FLAG_SECURE on the window. Both require native module work. Not critical for V1 because there are no rotating QR codes to protect.

3. **Secure key storage (Keychain/Keystore)** — expo-secure-store exists and works in dev builds. Not needed until device-binding or credential storage is implemented.

4. **Biometric authentication** — expo-local-authentication exists. Nice for "confirm receipt" flows but not a V1 requirement.

5. **Device binding / hardware attestation** — Requires Apple DeviceCheck / Google Play Integrity APIs. Native module territory. Defer to V2.

### D. Security / Trust Operations

**Must have for private beta:**

1. **Admin SQL access** — Direct Supabase SQL Editor access for: manually releasing/freezing payouts, resolving disputes, banning users, viewing transfer status. No admin UI needed for private beta.

2. **Dispute workflow (manual)** — A documented SOP for: buyer reports non-receipt → admin freezes payout → admin contacts seller → admin resolves (release payout or refund buyer). This is a process, not code.

3. **Support channel** — Email or in-app support link. Already exists (app/settings/support.tsx).

**Can defer:**
- Fraud review dashboard
- Automated fraud scoring
- Chargeback auto-response
- Incident response playbook (write after first incidents)

### E. Human Resources

**What one senior engineer + Claude can realistically do:**
- All of the backend work described above (payout deferral, transfer expiry, dispute RPC, webhook handlers)
- All mobile UI adjustments (showing transfer status, buyer protection countdown, dispute button)
- All Stripe integration work
- Database migrations, RLS policies, edge functions

**What needs real specialists (eventually):**
- Native module development for screenshot/screen recording protection (iOS + Android engineers)
- Identity verification integration (KYC/compliance specialist)
- Device attestation / anti-fraud ML (security engineer)
- Scaling beyond private beta (DevOps/infra engineer)
- Legal review of terms around ticket resale in each jurisdiction (attorney)

**For private beta: one senior engineer + Claude is sufficient.** The work is primarily backend orchestration (Stripe payout timing, transfer enforcement, dispute handling) and none of it requires native module expertise.

---

## SECTION 4 — External Ticket Transfer Into SnatchIt

This is the hardest problem in the architecture and the one most often hand-waved.

### The Fundamental Truth

SnatchIt does not control the ticket. The ticket lives in the seller's Ticketmaster, AXS, SeatGeek, or other account. SnatchIt's job is to make the transfer of that ticket trustworthy — not to replace or proxy the ticket itself.

### Source-by-Source Analysis

#### 1. Ticketmaster / SafeTix (Mobile Transfer)

**How it works:** Ticketmaster SafeTix tickets are app-bound with rotating barcodes. Sellers can initiate a "Transfer" to a recipient's email or phone number. The recipient receives a link, accepts in the Ticketmaster app, and the ticket appears in their account with a new rotating barcode bound to their device.

**Can SnatchIt support this in V1?** Yes — this is the primary supported flow. SnatchIt facilitates the sale, holds the payment, and the seller executes the Ticketmaster transfer outside the app. The buyer confirms receipt in SnatchIt, and payout is released.

**What SnatchIt CANNOT do:**
- Verify the transfer happened (no Ticketmaster API access for resellers)
- Automate the transfer (no API — seller must do it manually in the TM app)
- Guarantee the ticket is valid before the event
- Prevent the seller from recalling the transfer after buyer confirmation (Ticketmaster allows this in some cases)

**V1 policy:** Supported. Seller manually transfers via TM app. Buyer confirms in SnatchIt. Payout released after confirmation. Buyer protection window (48h or until event date, whichever is sooner) covers the gap.

#### 2. AXS (App-Bound Tickets)

**How it works:** AXS tickets are bound to the AXS app with rotating QR codes. Some events allow transfer via the AXS app (to email/phone). Some events have transfer restrictions.

**Can SnatchIt support this in V1?** Partially. Same manual transfer model as Ticketmaster. The risk is higher because AXS transfer availability varies by event and venue.

**V1 policy:** Supported with a warning. Seller must confirm the event allows AXS transfers before listing. SnatchIt should surface transfer_method prominently and warn buyers that some AXS events restrict transfers.

#### 3. PDF / Static QR Tickets

**How it works:** Older events, smaller venues, and some international events still use PDF tickets with static QR codes or barcodes. These can be screenshotted, forwarded, and used by anyone.

**Can SnatchIt support this in V1?** Yes, but this is the highest-fraud category. A PDF ticket can be sold to multiple buyers simultaneously. The QR code does not rotate — first person to scan it gets in.

**What SnatchIt CANNOT do:**
- Prevent the seller from using the ticket themselves after "transferring" the PDF
- Prevent the seller from selling the same PDF to multiple buyers on different platforms
- Verify the PDF is legitimate

**V1 policy:** NOT recommended for V1. If supported, must come with heavy warnings to buyers and a mandatory buyer-protection window. The seller should upload the PDF to SnatchIt (custodied by SnatchIt storage), and SnatchIt should only release it to the buyer after payment — but this does NOT prevent the seller from retaining a copy. Consider deferring PDF tickets entirely from private beta.

#### 4. Apple Wallet / Google Wallet Bound Tickets

**How it works:** Some tickets are added to Apple Wallet or Google Wallet via .pkpass files or deep links. These are generally not transferable through the wallet — the transfer happens on the issuing platform, and the wallet pass updates or is replaced.

**Can SnatchIt support this in V1?** No direct integration. The transfer happens on the issuing platform (same as Ticketmaster/AXS). The wallet pass is a delivery mechanism, not a transfer mechanism.

**V1 policy:** Same as whatever platform issued the ticket. Apple/Google Wallet is not a separate source — it is a display layer.

#### 5. Username/Email Transfer Ecosystems (Eventbrite, Dice, etc.)

**How it works:** Some platforms allow ticket transfer by entering the recipient's email address. The recipient receives a new ticket or a link to claim the ticket.

**Can SnatchIt support this in V1?** Yes — same manual transfer model. Seller enters buyer's email on the platform, buyer receives and confirms.

**V1 policy:** Supported. Same escrow flow. Buyer must provide the email address associated with their account on the relevant platform.

### What "Atomic Credential Swap" Means When SnatchIt Does NOT Control the Issuer

It means nothing technical. SnatchIt cannot atomically swap credentials it does not control. The "atomicity" is purely financial:

- SnatchIt holds payment until transfer is confirmed
- If transfer fails or is disputed, SnatchIt refunds the buyer
- The seller has financial incentive to complete the transfer (their payout depends on it)

This is not "atomic credential swap." This is escrow. Call it what it is.

### Recommended V1 Transfer Policy

| Source | V1 Support | Model | Risk Level |
|--------|-----------|-------|------------|
| Ticketmaster (SafeTix) | YES | Manual transfer → buyer confirms → payout released | Medium |
| AXS | YES (with warnings) | Same as TM, seller confirms transferability | Medium-High |
| SeatGeek | YES | Manual transfer → buyer confirms | Medium |
| Eventbrite / Dice / email | YES | Email transfer → buyer confirms | Medium |
| PDF / Static QR | DEFER | Too high fraud risk without credential control | Very High |
| Apple/Google Wallet | N/A | Follows underlying platform | Varies |

---

## SECTION 5 — Current Build Gap Analysis

### ALREADY BUILT

| Component | Status | Evidence |
|-----------|--------|----------|
| Auction lifecycle (bid, finalize, winner) | Complete | schema.sql triggers, auto_finalize_expired_auctions RPC, validate_and_apply_bid trigger |
| Buy-now reservation system | Complete | reserve_buy_now, release_reservation, cleanup_expired_reservations RPCs |
| Stripe payment capture | Complete | create-payment-intent, confirm-payment edge functions, PaymentSheet UI |
| Stripe webhook handling (idempotent) | Complete | stripe-webhook with signature verification, claim-based UPDATE, duplicate INSERT protection |
| Stripe Connect seller onboarding | Complete | create-connect-account edge function, payout-setup.tsx UI |
| Transfer state machine | Complete | transfers table, mark_transfer_sent, confirm_transfer_received RPCs with FOR UPDATE locks |
| Push notifications | Complete | send-push edge function, usePushToken hook, Expo Push integration |
| RLS policies (all tables) | Complete | Buyer/seller read on transfers, owner-only write on profiles/listings, no client write on payments/transfers |
| DB-backed rate limiting | Complete | check_rate_limit RPC, applied to all 3 payment edge functions |
| Input validation constraints | Complete | CHECK constraints on text lengths and numeric bounds (migration 004) |
| Double-sale prevention | Complete | Unique index on payments (one succeeded per listing), unique constraints on transfers |
| Guard triggers (state column protection) | Complete | guard_listing_state_columns, guard_listing_identity_columns triggers |

### PARTIALLY BUILT

| Component | What Exists | What Is Missing |
|-----------|-------------|-----------------|
| Seller payout | Stripe Transfer executes in webhook | Payout is IMMEDIATE — no deferral until buyer confirms. No payout hold, no release logic, no protection window |
| Transfer expiry | expires_at column is set (24h) | No job enforces it. Expired transfers are never marked as expired. No notification to either party |
| Dispute status | 'disputed' is a valid transfer status | No dispute creation flow, no dispute RPC, no admin tooling, no refund trigger |
| Seller verification | is_verified_seller flag exists on profiles | No verification flow — flag is never set by any code path |
| Buyer verification | is_verified_buyer flag exists on profiles | No verification flow — flag is never set by any code path |
| Wallet balance | wallet_balance numeric column on profiles | Column exists but is never read or written by any code |
| Transfer UI (seller sends) | ListingDetailScreen has "Mark as Sent" button | Works but UX is buried — no dedicated transfer management screen |
| Transfer UI (buyer confirms) | ListingDetailScreen has "Confirm Received" button | Works but same UX issue. Dead transfer screens exist but are unreachable |
| Stripe Connect status | stripe_connect_id saved to profiles | No account.updated webhook — app never knows if onboarding completed |
| Error tracking | Sentry SDK in app.json plugins | Not wired to edge functions. No structured alerting on payment/transfer failures |

### NOT BUILT

| Component | Notes |
|-----------|-------|
| Rotating QR credentials | Zero code. No QR generation, no nonce system, no rotation timer |
| Device binding | Zero code. No device fingerprint, no hardware attestation |
| Screenshot / screen recording protection | Zero code. expo-screen-capture not installed |
| Credential issuance pipeline | Zero code. No credential schema, no signing, no storage |
| Credential revocation | Zero code. No revocation list, no revocation RPC |
| Scanner/validation endpoint | Zero code. No PWA, no validation API, no nonce cache |
| Venue-side integration | Zero code. No venue onboarding, no scanner distribution |
| Buyer protection window | Zero code. No timer, no automation, no UI showing protection status |
| Delayed payout release | Zero code. Stripe Transfer fires immediately in webhook |
| Dispute creation flow | Zero code. No user-facing dispute button, no dispute RPC |
| Refund flow | Zero code. schema has refunded_at column but no refund edge function |
| Fraud detection | Zero code. No fraud signals, no scoring, no anomaly detection |
| Admin dashboard | Zero code. All admin actions require direct SQL |
| Identity verification (KYC) | Zero code. No Persona/Jumio integration |
| Phone verification | Zero code. Phone column exists but unverified |
| Chargeback handling | Zero code. No charge.dispute.created webhook handler |
| Transfer method verification | Zero code. No way to confirm which platform the ticket is actually on |

### SHOULD BE DEFERRED FROM V1

| Component | Why Defer |
|-----------|-----------|
| Rotating QR credentials | Requires venue partnerships, scanner infrastructure, and native secure-display modules. Months of work. Zero value without venue adoption |
| Device binding / attestation | Requires native modules (DeviceCheck, Play Integrity). Anti-fraud value is low at private beta scale |
| Screenshot / screen recording protection | Only valuable when there is a credential to protect. No credential = nothing to protect |
| Scanner PWA / validation endpoint | No venue partnerships. No events where SnatchIt is the primary issuer |
| Automated fraud scoring | Not enough data at beta scale. Manual review is superior for small volumes |
| Identity verification (KYC) | Can be manual (admin reviews ID photos) for private beta. Formal KYC integration is a compliance project |
| Blockchain / NFC / Protocol B / Protocol C | All V2+ |

### BLOCKED BY CURRENT ARCHITECTURE

| Component | What Blocks It |
|-----------|---------------|
| Delayed payout | stripe-webhook fires Stripe Transfer immediately on payment success. Requires refactoring webhook to INSERT a pending payout record instead, and a separate job to execute transfers after buyer confirmation |
| Seller verification gating | No account.updated webhook. Cannot programmatically confirm Connect onboarding is complete. Sellers could list without functional payout setup |
| Automatic transfer expiry | No pg_cron or scheduled edge function. Supabase free/pro tier supports pg_cron but it is not configured |

---

## SECTION 6 — Critical Launch Blockers

### BLOCKER 1 — Immediate Seller Payout (SEVERITY: CRITICAL)

**What:** The stripe-webhook creates a Stripe Transfer to the seller THE MOMENT payment succeeds — before the seller has transferred the ticket. A scam seller receives instant payout and has no financial incentive to complete the transfer.

**Why it matters:** This is the single biggest fraud vector. Without deferred payouts, SnatchIt has no trust moat. The seller can list a fake ticket, receive payment, get paid out instantly, and disappear.

**Fix:** Refactor stripe-webhook to NOT create the Stripe Transfer on payment success. Instead, insert a payout_pending record. Create a separate edge function (release-payout) that creates the Stripe Transfer only when: (a) buyer confirms receipt via confirm_transfer_received, or (b) buyer-protection window expires without dispute.

### BLOCKER 2 — No Buyer Protection Window (SEVERITY: CRITICAL)

**What:** After buyer confirms receipt, there is no protection window. If the ticket turns out to be invalid at the event (wrong seat, already used, recalled by seller), the buyer has no recourse through SnatchIt.

**Why it matters:** Buyer trust is the product. Without a protection window, SnatchIt is no better than Craigslist with a payment form.

**Fix:** Add a protection window (48 hours or until event start, whichever is sooner). Payout is released only after this window expires without a dispute. Add a "Report Problem" button visible to the buyer during the protection window.

### BLOCKER 3 — No Dispute Flow (SEVERITY: HIGH)

**What:** The transfer status includes 'disputed' but there is no way to create a dispute — no RPC, no UI, no admin workflow.

**Why it matters:** When (not if) a buyer does not receive their ticket, there is no path to resolution except direct SQL intervention.

**Fix:** Create a create_dispute RPC that: transitions transfer to 'disputed', freezes the pending payout, and notifies the admin. Add a "Report Problem" button in the buyer's transfer view. Admin resolves via SQL in V1 (no admin UI needed yet).

### BLOCKER 4 — No Transfer Expiry Enforcement (SEVERITY: HIGH)

**What:** Transfers have expires_at set to 24 hours after creation, but no job ever checks this. A seller can leave a transfer in 'pending' forever without consequence.

**Why it matters:** The buyer is stuck waiting indefinitely. Their money is held. The seller faces no penalty.

**Fix:** Create a scheduled job (pg_cron or edge function called by external cron) that: marks expired transfers, auto-refunds the buyer, cancels the pending payout, and notifies both parties.

### BLOCKER 5 — No Refund Mechanism (SEVERITY: HIGH)

**What:** The payments table has refunded_at and status='refunded' but no code path creates a refund. No Stripe refund API call exists anywhere in the codebase.

**Why it matters:** When a dispute is resolved in the buyer's favor or a transfer expires, there is no way to return the buyer's money except manual Stripe Dashboard intervention.

**Fix:** Create a process-refund edge function (admin-callable) that: calls Stripe Refunds API, updates payment.status to 'refunded', sets refunded_at, and cancels any pending payout.

---

## SECTION 7 — Minimum Viable Trust Architecture for Private Beta

This is the leanest system that still gives SnatchIt a real anti-scam moat and makes it meaningfully safer than Facebook Marketplace, Craigslist, or direct peer-to-peer sales.

### The Three Pillars

**Pillar 1: Escrow (Hold money until transfer is confirmed)**

- Payment is captured via Stripe on purchase
- Payout to seller is NOT created immediately
- A pending_payouts record is created instead
- Payout is released only when: buyer confirms receipt, OR protection window expires without dispute

**Pillar 2: Accountability (Both parties have skin in the game)**

- Seller must have completed Stripe Connect onboarding to list
- Seller must mark transfer as sent within 24 hours or the order auto-cancels with full refund
- Buyer must confirm receipt or raise a dispute within the protection window
- All actions are timestamped and tied to authenticated user IDs

**Pillar 3: Recourse (When things go wrong, there is a path)**

- Buyer can raise a dispute via a "Report Problem" button
- Dispute freezes the pending payout
- Admin resolves disputes manually (SQL + Stripe Dashboard) for private beta
- Buyer receives refund if dispute is resolved in their favor

### What This Requires (Net-New Work)

1. **Refactor stripe-webhook** — Remove the Stripe Transfer call. Insert a pending_payouts row instead. (This is a surgical change to one edge function.)

2. **New table: pending_payouts** — listing_id, payment_id, seller_id, amount, status (pending/released/cancelled/refunded), created_at, released_at, protection_expires_at.

3. **New edge function: release-payout** — Called by: (a) confirm_transfer_received RPC (after buyer confirms), or (b) a scheduled job when protection window expires. Creates the Stripe Transfer and updates pending_payouts.status to released.

4. **New RPC: create_dispute** — Transitions transfer to 'disputed', sets pending_payout to 'frozen', notifies admin.

5. **New edge function: process-refund** — Admin-callable. Calls Stripe Refunds API, updates payment and payout records.

6. **Scheduled job: enforce-transfer-expiry** — Marks expired transfers, auto-refunds buyer, cancels payout.

7. **UI additions** — "Report Problem" button on buyer's transfer view. Protection window countdown. Transfer status prominently displayed.

### What This Does NOT Require

- No QR codes
- No scanner infrastructure
- No venue partnerships
- No device binding
- No screenshot protection
- No identity verification
- No native modules
- No new third-party services

### Why This Is a Real Moat

On every other peer-to-peer ticket platform (Facebook Marketplace, Craigslist, OfferUp), the buyer sends money and hopes for the best. On SnatchIt with this architecture, the buyer's money is protected until they confirm they actually received the ticket. The seller cannot get paid without completing the transfer. This is the same trust model that made Airbnb and Uber viable — hold the money, release on fulfillment.

---

## SECTION 8 — Recommended Implementation Order

### Sprint 1 (Week 1): Deferred Payout Foundation

1. Create migration 006_pending_payouts.sql — pending_payouts table, indexes, RLS
2. Refactor stripe-webhook — replace Stripe Transfer call with pending_payouts INSERT
3. Create release-payout edge function — creates Stripe Transfer from pending_payouts
4. Wire confirm_transfer_received to call release-payout after buyer confirms
5. Test end-to-end: payment → pending payout → buyer confirms → payout released

### Sprint 2 (Week 2): Protection Window + Expiry

6. Add protection_expires_at logic (48h or event start, whichever sooner)
7. Create enforce-transfer-expiry scheduled job — marks expired, triggers refund
8. Create process-refund edge function — Stripe Refunds API
9. Wire scheduled job to run every 15 minutes (pg_cron or external trigger)
10. Test: transfer expires → buyer auto-refunded → payout cancelled

### Sprint 3 (Week 3): Dispute Flow + UI

11. Create create_dispute RPC — transfer → disputed, payout → frozen
12. Add "Report Problem" button to buyer transfer view
13. Add protection window countdown UI
14. Add transfer status prominently to listing detail (both buyer and seller views)
15. Add account.updated webhook handler for Stripe Connect
16. Gate listing creation on verified Connect status

### Sprint 4 (Week 4): Hardening + Beta Prep

17. Add charge.dispute.created webhook handler (chargeback awareness)
18. Write admin SOP for dispute resolution (document, not code)
19. Wire Sentry to edge functions for error alerting
20. Delete dead transfer screens (app/transfer/send, app/transfer/receive)
21. Fix .env.production Sentry DSN double-https bug
22. End-to-end testing of all flows (happy path + dispute + expiry + chargeback)

### What Must Never Be Promised Yet

- "Rotating QR code credentials" — no infrastructure, no venue partnerships
- "Screenshot-proof tickets" — no native modules, no credential to protect
- "Single-device enforcement" — no device binding
- "Venue scanner integration" — no venue relationships
- "Automated fraud detection" — no data, no models
- "Identity-verified sellers" — no KYC integration

These are all valid V2/V3 features. They are not V1 features. Promising them before they exist creates liability and erodes trust when they fail to materialize.

---

## Appendix: Note on the Trust & Transfer Infrastructure Document

This audit was requested with reference to an attached "Trust & Transfer Infrastructure document." That document was not found in the uploaded files or project directory. This audit was conducted against the actual codebase, existing audit reports (BACKEND_AUDIT_REPORT.md, PAYMENTS_AUDIT_REPORT.md, STRIPE_AUDIT_REPORT.md), and the architecture described in the user's prompt. If a formal trust architecture document exists separately, it should be audited against the findings in this report to identify any additional gaps between the document's claims and the codebase reality.
