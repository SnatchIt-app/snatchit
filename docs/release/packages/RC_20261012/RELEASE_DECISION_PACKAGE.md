# RC2 consumer release: decision package (A, 2026-10-13)

**Candidate:** `integration/rc-20261012` @ **`e2b9498b71191d308a33d00bce87a0832acc8d55`**, tree `3e981375…`.
**Draft PR:** SnatchIt-app/snatchit#100 → `release/production-gate-20260918`.

This package authorises nothing. Each action in §4 is a separate owner approval.

## 1. What is complete

| Lane | Verdict at `e2b9498b` | Record |
|---|---|---|
| A: integration | `rc_verify` PASS. The tree equals the clean composition; the gated surface is `setupDecision.ts` (F6) only; C4 MISSING 0 | README "RC2 FROZEN" |
| CI | run 38319986862: 5/5 jobs, 68/68 steps. Unit 3,151, parity 108, web 218, admin 117, pgTAP 5,605 PASS | GitHub |
| Gate PR #100 | 6/6 required checks green at head `e2b9498b`; "Supabase Preview" skipping; CLEAN; **draft** | PR #100 |
| C: native build | **Simulator** Release build, adhoc, **unsigned**: EXIT 0, fresh install, sandbox pairing PASS, cold launch OK | private evidence on the SSD |
| B: consumer review | PASS, no blocker. B-D7 meets the criterion: 0 money pixels past the edge at A3XL; default identical | `design/frontend-audit-20260917` @ `967c29e6` |
| D: contracts and schema | no blocking defect. C4 PASS on both roots; every checkout producer enumerated | `review/d-records-20261005` @ `1e6e1e82` |
| E: acceptance | **ACCEPTED on the stated coverage**; delta rows closed; M-1..M-6 carried by an import-closure diff | `design/frontend-audit-20260917` @ `fc257fc6` |

**Evidence class.**
- All native evidence comes from a **simulator Release build** (sandbox profile, adhoc signing).
- **No production-signed device build exists yet.** That is G2, an owner action.
- Nothing was an authenticated or live-payment result.

**Accepted, non-blocking follow-ups (not claimed as fixed):**
- **D-RC2-1:** checkout's no-mode branch sends a failed settled read to the generic error, and the escrow note shows
  while the status is unknown.
- **D-RC2-2:** the restated E9 guard is **weaker** than before in the region between the no-mode read and its throw.
  D and E replayed a mutation that the new pin misses. The shipped code is correct. **Not every guard became
  stronger.**
- **Order header:** the "Your order" title overflows at A3XL (not money).
- **B's probe notes:**
  - In the cold 3-D Secure pre-webhook window, the screen shows "Payment already completed" with "Try again" until the
    webhook lands.
  - Stripe's returnURL matching is evidenced only on a device.
  - The no-mode completed face has no "View transfer".
- **D's residuals:** Sentry noise on mode-less opens; CM12 sees only the object-form push; a possible OTP resend dead
  end after an F3 failure.

**Kept apart, not passed:**
- Owner-waived: signed-in flows, the W-5 picker, the R-3 crop, signed-in wording.
- Source-only: P-4, W-6 (connected), W-5 parity, VoiceOver labels.
- **Spoken VoiceOver:** optional and untested.

## 2. Blocking (migration 152): the decision

**What ships in RC2.**
- A signed-in user can block a seller from the listing or the seller's profile. The blocker then stops seeing that
  seller's listings in Home and Search, and the seller's profile shows a blocked notice.
- The block is **one-way and client-side**. The blocked person can still see, bid on, buy from and report the blocker.
- Operators can stop a user from creating listings (migration 119). **Account suspension is not supported**: the console
  refuses it (115:720).
- The confirmation text says only what happens: "Their listings will be hidden from your feed."

**Apple's requirement.** App Review Guideline 1.2 (official text, read 2026-10-13 at
developer.apple.com/app-store/review/guidelines) requires four things of apps with user-generated content:

| 1.2 requirement | What RC2 has | Risk |
|---|---|---|
| Filter objectionable material from being posted | a banned-lexicon gate on listing text (`sellState.ts`, client side) | moderate: client-side and lexical only |
| Report offensive content, with **timely responses** | report from a listing and from a profile; console queue `/reports`, plus cases every 5 min | **high**: nothing notifies an operator, and who works the queue is undecided (owner B1) |
| **Block abusive users from the service** | a user hide-block (one-way); operator listing ban; no account suspension | **high**: neither level stops an abusive user from acting |
| Published contact information | support@snatchitapp.com (Legal, Privacy, Support) | low |

**Compliance is NOT claimed.** Apple decides it.
- No earlier review round in the records cited 1.2: they cited a 2.1 information request and a checkout failure. That
  is weak evidence, not approval.

**A's recommendation:**
- **Defer 152 for this submission, do not change the release candidate, and close the "timely responses" gap
  operationally:** a named person and a daily review of `/reports` and `/cases` (owner item O-10).
- **Consequence:** a 1.2 rejection citing blocking is plausible. The remedy is already scoped: 152 (BLOCKING_SCOPE_
  RECOMMENDATION §2a–2d: server-enforced two-way refusal of bids and Buy Now), plus operator suspension (§2e), which
  152 does not include. Either one needs new-migration authority and a full re-verification cycle (C, B, D, E),
  measured in days.
- **The alternative:** authorise 152 + §2e now and submit later. That lowers the 1.2 risk and delays submission by the
  same cycle.
- **Either way, the review notes must describe the block exactly as above.** The draft line "users blocked (⋯ → Block)"
  must not be expanded to imply server enforcement.

## 3. Monitoring state (not counted as coverage)

- **Scheduled refund review: no working automation exists.**
  - This machine's scheduled tasks hold three disabled one-shot tasks from September, none of them about refunds.
  - claude.ai routines: none.
  - The run you reported as blocked is not visible to A. Either way it is not coverage.
- **What runs automatically:**
  - Refund-state detection is enabled (O-R2, 2026-10-08). It has **never been observed** opening a case in
    production; the 2026-10-11 16:35Z run scanned 2 and opened 0. Successful-refund reconciliation does not validate
    failed or pending detection.
  - `enforce-transfer-expiry` runs every 2 min.
- **Nothing notifies anyone,** per the last record (2026-09-24). Alert delivery and email were off then, and their
  enabling is owner item B2. A has not re-read production.
- **Human responsibility is therefore the only coverage.** The O-R3 operator (the owner) reviews these daily, until an
  alert path exists:
  - console `/cases` (refund_failed, refund_pending, dispute_open, report_review);
  - `/reports`;
  - the Stripe Dashboard's failed refunds and payouts.

## 4. Release boundaries (four separate actions; none is authorised by this package)

| # | Action | Production effect | Can apply migrations? | Rollback |
|---|---|---|---|---|
| R-1 | Merge PR #100 into `release/production-gate-20260918` (the "merge" method), then A checks the merge tree = `3e981375` | none | no | a revert PR |
| R-2 | G2: production-signed EAS build from `e2b9498b` (or the R-1 merge commit after the tree check), TestFlight upload, the owner's phone session (G1) | a binary in TestFlight only | no | expire the build |
| R-3 | App Store submission with manual release, then the release itself | the app reaches users on release | no | remove from sale; ship a fix |
| R-4 | S7: gate → `main` (independent of R-2/R-3) | **possible**: the Supabase integration runs `db push` on `main` if auto-deploy is on, which would leave the unapplied **121/125/126** pending | **yes, if auto-deploy is on** | revert; any applied file needs its rollback under approval |

## 5. Owner action list for distribution (one list; recommended order)

Status key: VERIFIED = evidence in the records this sprint or earlier; RECORDED-OPEN = the last record shows it open;
UNKNOWN = A cannot check it with authorised access.

| # | Item | Status | Why it matters | A recommends | Exact action |
|---|---|---|---|---|---|
| O-1 | Accept the candidate's coverage | E ACCEPTED on the stated coverage | it replaces the G0 "visual acceptance failed on Build 24" | accept as stated (simulator-native, fixture-class; waivers stand) | Say "accept RC2 coverage" |
| O-2 | Decision 152 (§2) | open | App Review 1.2 risk | defer 152; staff the queue (O-10) | Say "defer 152" or "authorise 152 + §2e" |
| O-3 | R-1: merge PR #100 into the gate | ready (6/6 checks, CLEAN) | it puts RC2 on the release line; no production effect | approve | Mark PR #100 ready, merge with the "merge" method; A then checks the tree |
| O-4 | G4: the live Stripe secret key on the production Supabase is live and from the same account as the app's `pk_live` | **UNKNOWN** (only the sandbox digest method is known) | a wrong key fails every live payment | do it before G2 | The checklist G4 steps: a control on the production SUPABASE_URL row first, then compare the `STRIPE_SECRET_KEY` digest with the live key's SHA-256 on your machine. Never paste the key |
| O-5 | G3: the live webhook endpoint | **VERIFIED** (owner, 2026-10-08: `we_1TCqy5…`, 13/13 events incl. refund.*) | delivery is what settles payments | no repeat | — Live delivery has not been exercised since 2026-08-05 (no live activity). The first live payment exercises it; watch the endpoint's attempts in Stripe |
| O-6 | G5: the Apple Pay certificate for `merchant.com.snatchit` | **UNKNOWN** (status and expiry not recorded) | an expired certificate breaks Apple Pay on device | check before G2 | Apple Developer → Identifiers → Merchant IDs → `merchant.com.snatchit` → certificate status and expiry; Stripe Live → settings/ios_certificates shows it listed |
| O-7 | Signing for G2 | **UNKNOWN** | a production-signed build needs your Apple distribution credentials in EAS | let EAS-managed credentials run | During G2, `eas build --profile production --platform ios` from a clean checkout at `e2b9498b` prompts for or uses your EAS credentials. Verify the build metadata names the commit |
| O-8 | G2 itself (R-2) | open | the first production-signed artifact | after O-4/O-6 | Authorise "G2 from `e2b9498b`". Then TestFlight internal, then G1 |
| O-9 | G1: the phone session on the TestFlight build | open (was paused on G0) | the only device-class evidence | a short session: install, sign in, browse, open checkout without paying, sign out | On your phone with TestFlight. No purchase unless you separately authorise one (checklist V6) |
| O-10 | B1: who works `/reports` and `/cases`, and how often | **RECORDED-OPEN** (09-24) | 1.2 "timely responses"; refund_failed and disputes; the only monitoring (§3) | name yourself, daily | Say "B1: <name>, daily" |
| O-11 | B2: email and alert delivery | RECORDED-OPEN | today nothing notifies anyone | optional before release; the separate config approvals are listed in the policy list | Say whether to enable `EMAIL_ENABLED` / alert delivery (each its own production change) |
| O-12 | G7: reviewer access (both review passwords are burned) | RECORDED-OPEN | App Review must sign in | after G2 | On the TestFlight build: Login → "Use email instead" → Forgot password, for both review accounts; new passwords go into App Store Connect only |
| O-13 | G6: review inventory + the $300 listing `c8d04339…` + P5 (reviewer-purchase refunds) | RECORDED-OPEN | the reviewer needs live listings, and a reviewer purchase must be handled | per REVIEW_INVENTORY_PLAN_V3 | Create the 3 listings in the app as the demo seller after G2. Decide (a) cancel or (b) leave the $300 listing. Decide P5: automatic 24 h expiry refund or manual |
| O-14 | Review notes (APP_STORE_REVIEW_NOTES_V3_DRAFT) | draft | the notes must state only verified behaviour | A updates the placeholders after O-12/O-13 | Approve the final text; the safety line describes the block exactly as §2 says |
| O-15 | Terms and the payout/refund wording (policy list §3A; PAYOUT_REFUND_TERMS_DRAFT §B) | RECORDED-OPEN | the legal fee sentence (`legal.tsx:94-95, 211-213`) does not name its base; G's website reconciliation depends on it | adopt §3A's proposed sentence (10% of the sale price each way) | Say "adopt §3A" or give your wording. G lists any Terms/Guarantee contradictions in G-HANDOFF |
| O-16 | R3: Twilio auto-recharge (signup OTP) | RECORDED-OPEN (OFF at 09-24) | signups fail when the balance runs out | enable | Twilio console → Billing → Enable auto recharge, with an amount and a threshold (minimum $10) |
| O-17 | R-3: submission (manual release) | after O-1..O-16 | — | — | Submit in App Store Connect with the final notes; release manually |
| O-18 | R-4: S7 (independent) | open | `main` behind the gate; 121/125/126 | after release, not before | PR-3 (merge-commit method on `main`) + a fresh visual AUTODEPLOY-off confirmation + D's pre-merge check |

**Not gating (follow-ups):** F8, B-D6, D-RC-3, D-RC2-1/-2, the Order header; the live console and server findings (the
duplicate parked refund/payout rule and relist `expected` need migrations); Next.js 16.3.3 on web and console (bump +
deploy); 153 and CI masking (parked). The marketing PR SnatchIt-app/snatch-it-landing-page#22 is G's track: its merge
deploys marketing, so reconcile it with O-15 first.
