# Policy promises: the current decision list (A with E; rev 2, 2026-09-24 ~23Z)

This is the one current list. Strings are quoted at C's app head `65052bfc`; server and database facts at gate
`037092f0`. Production facts come only from dated records; no new production read was made. **Items decided by the
owner are closed; do not reopen them.**

## 1. Decided by the owner (settled 2026-09-24)

| # | String | Decision | Status |
|---|---|---|---|
| 1 | `app/report/[type]/[id].tsx:78` "…We review reports within 24 hours and act on what we find." | remove "within 24 hours" | routed to C (A, ~22:40Z) |
| 2 | `app/settings/privacy.tsx:144` "Reports are reviewed by the Snatch It team within 24 hours." | remove "within 24 hours" | routed to C |
| 3 | `report :92` "Our team reviews every report and may remove content or suspend accounts…" | keep | — |
| 4 | `report :134` "…False or repeated bad-faith reports may result in your account being suspended." | keep | — |
| 5 | `privacy.tsx:145`, `legal.tsx:187`, `legal.tsx:247`: removal, suspension, ban | keep (reserved rights) | — |
| 6 | `src/lib/transfer/transferState.ts:230` "Our team typically reviews within 24 hours. The seller's payout is frozen…" | remove the first sentence; keep the freeze sentence | routed to C |
| 7 | `app/settings/support.tsx:68` "We aim to respond within 1 to 2 business days." | remove | routed to C |
| 8 | `CreateListingScreen.tsx:905/911` "…will transfer them within 24 hours of sale." | keep (enforced: deadline sale + 24 h, 061:111) | — |
| 12 | App Review purchase-refund promise | leave it out | the review-notes draft is updated |
| — | G10 (D's completed checklist reads) | closed | checklist §9 |

## 2. Truth fixes A routed to C (A's lane, no owner decision needed)

- **Copy rulings §2f and §2g** (wording table), and **fee and payout copy**:
  - the Apple Pay label "Ticket" (whole-listing amount);
  - payout-setup's "Payouts deposit automatically when your listings sell";
  - create-listing's fixed "You get" / "Buyers pay" figures for auctions.
- **Home block bug.** The feed filters with the empty block set from the first render, so blocked sellers show until a
  pull-to-refresh (home.tsx:231–323).
- **Dispute dialog** `transfer/receive/[id].tsx:370`: "…This will freeze the transfer and notify support." Nothing
  notifies anyone (see §4), so it becomes "…This freezes the seller's payout and opens a case for our team."
  - Backing: `ops.detect_disputes` opens a p1 `dispute_open` case (117:420); `detectors_enabled` was true as of
    2026-09-22.

## 3. Still with the owner

**A. Payout and refund terms.** This replaces items 9–11.
- The draft is `PAYOUT_REFUND_TERMS_DRAFT_20260924.md` §B. It separates payment, order release, payout eligibility,
  the actual transfer, and refunds.
- The legal fee sentence (`legal.tsx:94–95`, `:211–213`) should name its base. Proposed: "A service fee of 10% of the
  sale price (the Buy Now price or winning bid, for the whole listing) is added to the buyer's total, and a marketplace
  fee of 10% of that same sale price is deducted from the seller's payout."

**B. Operational choices that are genuinely open.**
- **B1.** Who works the console queues, and how often: `/reports` and `/cases`. Nothing notifies anyone. At the
  2026-09-24 02:29Z record, 3 report cases and 5 disputes were open, and no dispute has ever been resolved.
- **B2.** Turn on email alerts? That means `EMAIL_ENABLED=true` and confirming `ADMIN_EMAIL`. Separately, turn on alert
  delivery (`alert_delivery_enabled` plus a dispatcher schedule)? Each is a production config change needing its own
  authorisation. Reports never raise alerts; only p1 cases such as disputes do.
- **B3.** Blocking scope (§4). Should the client fixes suffice, or should a block also be enforced by the server? The
  server option needs a migration.

**C. Access steps only the owner can take** (exact steps as of 2026-09-24; each read-only).
- **C1. Operator console:** `https://snatchit-admin.vercel.app/login`.
  - This URL was checked on 2026-09-24 at 22:11Z: `/` redirects to login, and `/reports` and `/cases` require it. The
    console was deployed from `ab3e17f` on 2026-09-08.
  - Sign in with email and password, then the authenticator (TOTP) code.
  - Open `/reports`: the filters are plain searches and change nothing. Then open `/cases` and open a case to read
    Details, Notes and Timeline. Then sign out.
  - **Do not click** Add note, Assign, Set status, Set priority or Set due on a case (each writes an audited action).
    Do not confirm anything under `/actions/*`, change anything on `/system`, or resolve any dispute.
- **C2. Support inbox:**
  - `support@snatchitapp.com` is routed by Cloudflare Email Routing (MX route1–3.mx.cloudflare.net, checked
    2026-09-24).
  - In Cloudflare → snatchitapp.com → Email → Email Routing, check which inbox `support@` forwards to. Then send it a
    test email from another account and confirm a person receives it.
- **C3. Admin push token:** only a **production** build can register one.
  - **The only production build that exists is Build 13:** 1.0.0 (13), EAS `cb5646b5`, commit `3c67dfc`, pk_live,
    installed from **TestFlight**. A sandbox preview is also numbered 13 (EAS `aeb89616`): do not use it.
  - **Builds 23/24 and every current V3 preview point at the sandbox project and cannot register a production token.**
  - Install the TestFlight Build 13 on a physical iPhone. Sign in with the admin account, which must be one of the two
    `public.admin_users` accounts; the console's platform role is a different list. Allow notifications.
  - The token registers at sign-in (`usePushToken.ts:69-86`). Production accepts that path (record 2026-09-24 02:25Z).
  - **Condition:** the phone's token must not already belong to another production account. If it does, registration
    fails silently, and moving it needs a production data change for you to decide.
  - **Proof:** only a real notification on that phone. `notify-report` counts any 200 from `send-push` as delivered,
    even `{sent: 0}`.
  - Whether Build 13 is still installable (TestFlight expiry) is unverified.
  - Admin push tokens stood at **0 of 2 as of 2026-09-22** (dated; not current).

## 4. Verification results

**Reports reaching an operator** (source, plus records dated as shown).
- A content report inserts into `public.reports` (`report/[type]/[id].tsx:69`).
- The console's `/reports` page lists `public.reports` directly (`list_reports`, 116:1043; `admin/…/reports/page.tsx:32`).
  `ops.detect_reports` also opens a p3 `report_review` case every 5 minutes (117:502, :1123), and `/cases` lists it.
- The insert trigger calls `notify-report`, which pushes to admins and emails only when `EMAIL_ENABLED`.
- As of the records: no admin has a push token (2026-09-22); email is off (2026-09-22; 2026-09-17 R7); alert delivery is
  off and has no dispatcher (2026-09-23 23:23Z).
- **Result:** a report is visible to anyone who opens the console, and it notifies no one.

**Support contact.**
- The app and snatchitapp.com/support list only `support@snatchitapp.com`.
- Its MX records are Cloudflare Email Routing (route1–3.mx.cloudflare.net, checked today). That proves routing, not
  that anyone reads it (C2).

**Blocking** (source; nothing run).
- A user can block a **seller** only, from the seller's listing or profile. The block is **one-way** and
  **client-side only**: no RLS rule, function or edge function reads `user_blocks` (`074:182–183` says so; functions:
  0 references).
- Effects for the blocker:
  - Explore drops the seller's listings.
  - Home should drop them, but doesn't until a pull-to-refresh (the bug in §2).
  - The seller's profile shows a blocked notice.
- No effect on:
  - listing detail (deep link, push, profile);
  - bid history;
  - "bid received" pushes;
  - checkout, transfers and the Bids tab;
  - the web app.
- The blocked user can still view, bid on, buy from and report the blocker, and never learns of the block.
- The operator console can only stop a user from creating listings (119:103 trigger). There is no account suspension.
- **What can truthfully be said today:** "You can block a seller to hide their listings from your Search results (and
  Home, once fixed) and their profile." **A does not claim Apple 1.2 compliance from this.**

**Fees.**
- Client and server math agree:
  - the buyer pays base + round(base × 10%);
  - the seller gets base − round(base × 10%);
  - base = the Buy Now price, or the winning bid, for the whole listing;
  - Stripe's processing fee is Snatch It's cost (`money.ts`; create-payment-intent :681/:703/:1073).
- **Wrong or ambiguous strings:**
  - the Apple Pay label;
  - create-listing's auction figures;
  - payout-setup (all three are in §2);
  - the legal fee sentence's base (§3A).
- **Correct:** checkout rows, the bid confirmation, and "Price includes the 10% service fee."

**Expiry refund versus the refund executors:** see `PAYOUT_REFUND_TERMS_DRAFT_20260924.md` §A.
