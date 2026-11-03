# Admin v2 (#209): signed-in preview acceptance

The owner decided admin v2 replaces the live console after an independent review and a signed-in acceptance. E accepted #121 on quality with three pre-deploy conditions; this is condition **P2**: the owner (and, if possible, the second founder) reads the new console on an SSO-protected Vercel **preview** that reads production, before any production deploy. The walk is read-only (see Rules). It proves reads and designed states only. It does not prove any v2 write on production.

**Nothing here deploys to production.** The preview is a `vercel deploy` without `--prod`, which the Ignored Build Step pin and Branch Tracking do not govern (DEPLOYMENT_RECORD_2026-09-08 addendum 2). It serves on a `*-gnvprod-5449s-projects.vercel.app` URL behind Vercel SSO, so only the owner's Vercel account can open it.

## What the preview is

| Item | Value |
|---|---|
| Source | `admin/console-v2-release` @ `e3e9fb76` (draft PR #209, base `admin/operating-console`). It contains the old head `2fc0c8f4` plus 21 later commits that touch `admin/`. The upload is the tracked `admin/` tree without `admin/docs`: 211 files. Codex's deployment matches this count. |
| Project | `snatchit-admin` (`prj_o17cASVVqqyGKPUtiklJRvAMVgNB`), run from the export root (Root Directory is `admin`), with `admin/.vercelignore` |
| Env | the four `NEXT_PUBLIC_*` values the production console already ships to every browser (Supabase URL, anon key, site URL, label `production`). These are public-class values, not secrets. No Preview-target env is created on the project; they are passed to the one deploy. |
| Data | production, read as the signed-in operator through `ops.*`. This build also calls functions that the live console `dddc8e92` does not call:<br>• `ops.list_operational_config` (registry 197, **applied 2026-11-02**, ledger 190). The panel shows the Operational settings form (see C16).<br>• `ops.list_cases/orders/listings/reports` with `p_include_test` (registry 180, **not applied**). `/system/test-data` shows "Needs registry 180".<br>• `ops.primary_reconciliation` and `ops.record_primary_refund` (migration 189, **applied**). The refund form is live.<br>• `ops.alert_ack` (migration 146, **applied**: read by A on 2026-11-02, read-only). |
| Protection | Vercel SSO, `all_except_custom_domains`: a preview URL always redirects to Vercel sign-in. No bypass link is created. |
| Rollback | delete the preview or let it expire. Production (`dddc8e92`) is untouched. **Deleting the preview does not undo a database write.** That is why the walk is read-only. |

## The deployment to open
- **Preview:** use the preview A names (today `dpl_8N9bkwqsa6JYkMqKfhZBcV9RHAEk`; after the price fix, A names the new one). Do **not** use `dpl_HATGWw1DR83j9GFj233DbxcV8FT9` (old head `2fc0c8f4`). Opening it first shows Vercel's own sign-in (your Vercel account); after that, the console's `/login`.
- Verified at deploy time: target preview (not production, not aliased), Vercel SSO on the URL, the production deployment unchanged (`dpl_9yvL3UZuHay4NqzdDeQ2soNqgVVt` @ `dddc8e92`, read by A on 2026-11-02), no Preview-scope env added to the project (the four public values were per-deploy build env).
- Method note for the next preview: run `vercel deploy` from the **export root** (the project's Root Directory is `admin`, so running inside `admin/` fails with `admin/admin`). `admin/.vercelignore` already excludes `admin/.env.example` (`.env.*`, line 8) and `admin/.env.local.example-harness` (line 22). Open: whether the CLI reads it from the export root. A confirms from the upload list.

## Verified / assumed / open
- **Verified from source:** all quoted copy, button labels, routes, and role gates below. Source citations are `path:line` at `e3e9fb76a966ed6459350af3bdfa5efdbd2cdebc`. `118:` = `supabase/migrations/118_ops_console_corrections.sql`.
- **Verified by A (live, read-only):** 196 applied; 197 and 180 not applied; 189 applied; `refund_execute_enabled` false; sales off; flags false.
- **Update (A, 2026-11-02 late):** **197 is now applied** (sandbox and production, 9/9 read-back; ledger 190). 180 is still not applied. C16 and the stop rule below are updated to match; the line above is kept as the record of the earlier read.
- **Assumed:** the owner walks as `platform_admin` at aal2 on a desktop window.
- **Read by A on 2026-11-02, live, read-only (these were open; they decide refund-resolution cases, alert acknowledge and suspend):** migrations **144** (`ops_refund_resolution_detector`) and **146** (`ops_alert_delivery_and_ack`) are **applied**; `ops.alert_ack` exists. `actions_enabled` = **true**. The current Ignored Build Step pin = `dddc8e92`.
- **Still OPEN: migration 152 (suspend).** No function named like `%suspen%` exists in ops/kernel/public, and there is no suspension migration in the ledger. The "152" suspension dependency is unresolved: F to name the exact object, and A reads it.

## Rules during the check
- Type only into the sign-in fields of step A2 (your own email, password and authenticator code), the top **Search** box and the **Filter rows on this page** boxes. Never type into Reason, Note, New value, Money key, or "Type REFUND to confirm". Most write buttons need a typed Reason. If you see a "Please fill out this field" bubble, you pressed a write button: stop.
- **This walk is read-only.** The preview reads and writes the **production database**. A button that the server refuses still writes an action row and audit rows (`118:124-152`).

  **Safe to press (these only read, or change only your own sign-in):**
  1. **Continue** on the Sign in page (`src/components/auth/LoginForm.tsx:39`).
  2. **Verify** on `/mfa`.
  3. **Sign out**. Note: sign-out is global. It ends all your sessions, including the live console and the app.
  4. Sidebar entries, bottom-bar entries, **More** and **Close**, the account menu.
  5. The `/system` jump links, **Open full order**, **Open full case**, **Close order preview**, **How this works**.
  6. **Filter**, **Apply**, **Apply range**, **Clear**, table **Sort by** headers, page links.

  **`refund_execute_enabled=false` does not make the console money-safe.** It blocks only the old **Execute refund** request. Two newer controls are not covered:
  - **Record this refund** (Money → Ticket orders). It records a refund under your name. A **full** refund also voids the order's voidable tickets, so the door refuses them. A partial refund records money only. It moves no money in Stripe. Migration 189 is live, so this would really happen.
  - **Request change** (System → Money settings). A change that tightens a limit applies **at once**, with one founder.
- **Do not press any of these.** Each one changes production, even when it says it will be refused.

  - **Cases** (list, pane, full page): New manual case → Open case; Change → Assign / Set status / Set priority / Set due; Add note; Record classification; Obligation → Record.
  - **Order page** `/orders/…`: Resolve dispute → Record resolution; Release held payout → Request release; Execute refund → Request refund (will be rejected: disabled); Open a case on this order → Open case; **Open evidence · audited** (writes an audit row with your name).
  - **User page** `/users/…`: Block listing creation; Unblock listing creation; Suspend account; Restore account; Open a case on this user → Open case.
  - **Listing page** `/marketplace/…`: Relist; Mark reviewing / Actioned / Dismiss; Open a case on this listing → Open case; Open evidence · audited.
  - **Reports**: Mark reviewing / Actioned / Dismiss. Nothing can set a report back to pending.
  - **Money → Ticket orders**: every **Record a refund** link (in the table and in "Money facts that disagree"); **Record this refund**.
  - **System**: Run now (jobs); Acknowledge → Record acknowledgement (alerts); Approve and execute / Deny (approvals); Request change, Approve and apply, Deny (Money settings); Apply now (Operational settings; since 197 it appears, and must never be pressed during a walk); **Save setting** (any row; it writes at once, even with the same value).
  - **Action page** `/actions/…`: Approve and execute; Deny; Resume execution.
  - **`/mfa`**: Enrol and verify; Retry.

  One-click writes (no typed Reason needed): **Open evidence · audited**, **Resume execution**, **Record acknowledgement**. Take extra care near them.
- **Stop rules.**
  1. If `/mfa` shows a QR code and the button says **Enrol and verify** (not **Verify**): stop. Do not open "Can't scan? Show the secret". Do not photograph the screen. Press **Sign out**. Tell A. (The console found no verified authenticator. It has already removed unfinished setups; verified ones are never touched: `src/components/auth/MfaFlow.tsx:39-60,162`.)
  2. If `/mfa` shows "MFA could not be started.": do not press Retry. Press **Sign out**. Tell A.
  3. "Re-verify with your authenticator to continue." is expected after some time. **Go to MFA** and **Verify** are safe.
  4. If you press a "Do not press" button by mistake: stop the walk. Write down the page, the button, and the time. Tell A. Do not press another button to undo it.
  5. If an "Actions paused" banner is on every page: note it and continue reading. **Request change** in Money settings is not covered by the pause.
- Tabs: open the preview in a fresh tab; keep the live console closed (same cookie name per host, but different hosts, so they don't collide; this is just to avoid confusion).

## Checklist (tick what you saw; one line per step is enough)

### A. Sign-in and the MFA gate (E's P2)
1. Open `/login` on the preview. Title reads "Sign in · Console · production", red production badge. ⏱
2. Sign in (password). The button is **Continue**, not "Sign in". You land on `/mfa`; your existing TOTP factor is reused, no re-enrolment. Enter the code. ⏱
3. Today renders at aal2. The sidebar shows 8 entries: Today; **Work**: Cases; **Money**: Orders & transfers, Money; **People**: Users, Reports; **Platform**: Marketplace, System. (Width 1024 px or more. On a narrower window the bottom bar shows Today, Cases, Orders, Money, More; More lists all 8.) Source: `src/lib/nav.ts:15-24`.
4. **Non-operator path: taken out of this walk.** Signing in a second, non-operator account writes production Auth for that account. Record gate G2 as still open. If A wants it, A first confirms by a live read that the account has no ops role and is a throwaway.
5. In the browser's cookie view for the preview host: `sb-hqycwntpfoztoinemqns-auth-token` has Domain = the preview host only (no leading dot), Path `/`, SameSite Lax. The cookie can be one `sb-…-auth-token` or two parts, `…auth-token.0` and `.1`. Both are expected.

### B. Reads, one per surface
6. Orders → click a row. An **Order preview** opens. It has no Stripe mode row. Press **Open full order** (safe). The full page's Payment panel shows a Stripe mode row: Live, Test, Unclassified, or "Unclassified (not provided by the server)". No orders: write "none".
7. On that full page, the Actions panel. Note which one you see:
   - "No state-changing action applies to this order right now."
   - "Already requested — …" (both request forms are hidden).
   - "Couldn't check for an earlier request" (both forms are hidden).
   - The **Execute refund** form with "refund_execute_enabled is false…" and the button "Request refund (will be rejected: disabled)". **Do not press it.**
8. Users → a user → the Account suspension panel is present (RC5), with no false "does not exist" copy. No orders or listings: write "none".
9. Marketplace → a listing → the Relist panel: shows only for an active + cancelled listing with a version; otherwise the "only active + cancelled" note. **Do not relist.** No orders or listings: write "none".
10. System → the Alerts panel has the read-only **Delivery channel** block: `alert_delivery_enabled` value (expected false), "Schedule: not shown by the server", "Channel: email to the owner's verified account email — prepared, not active". No email address is shown **in this block**. Your own masked email in the sidebar footer, and masked note authors, are expected.
11. System → Settings lists the switches with their current values; no form is submitted.
12. Money, Reports, Search, Cases: each renders without an error alert.
13. **Listing prices (FAILS on `dpl_8N9b…`, fixed on the follow-up branch):** Marketplace → note a listing's buy-now price and bid. Open the listing. The listing page, its Bids panel ("Highest") and the Recent bids table must show **whole-dollar** amounts that match the app (for example `$291.00 USD`, not `$2.91 USD`). A case or action whose subject is that listing shows the same amounts in "Subject snapshot".

### C. New in this build: read only

**C14. Money → "Ticket orders (primary) and their refunds".** Expected:
- The title "Ticket orders", with a count such as "0 orders" in a small pill **beside** the title.
- Either "No ticket orders in this period." or rows with Paid, Tickets, and "Refunded here / at Stripe". **Both pass.** Note the count.
- A "Money facts that disagree" box may show. Read it. Do not click its **Record a refund** links.
- If the address ends in `?refund=…` and a "Record a manual refund" form shows: do not type, do not press. Leave the page.
- **Fail:** a card titled "Ticket orders couldn't be loaded." or "RPC not available yet".

**C15. System → "Money settings (second founder)".** Expected:
- No failure card in this panel (titles such as "Request failed", "RPC not available yet", "Your account is not allowed to do this.").
- "No money-key requests awaiting a decision." or one card per request. A card shows **Approve and apply** / **Deny**, or one of these notices instead: "You requested this — a different founder must decide.", "This request has expired and can no longer be decided.", "This request cannot be decided by you …". Note which. Press nothing.
- A table "Live values (N money keys)". A's read says the fee keys are unset, so they show "unset". Note any other value.
- Under "Request a change": Money key, New value (JSON), Reason, **Request change**. Do not pick, type or press.

**C16. System → "Operational settings".** (197 applied 2026-11-02.) Pass = a form showing **hold max**, **hold lifetime** and the native **issuance** and **scanning** flags, with **Apply now**. The flags read **off**; hold max and lifetime read **unset**, or the values the owner set (6 holds, 10 minutes). **Do not press Apply now:** it is a single-founder write that applies at once. **Fail, then stop:** the "Needs registry 197" card (the console cannot read 197), or a flag that reads **on**.

**C17. System → jump link "Test records (restricted)".** Pass = title "Test records (restricted view)", a pill "Needs registry 180." beside it, and a card titled **"Needs registry 180 — the readers on this server cannot include test records."** with "No rows are shown and nothing has been classified." No tables. **Fail, then stop:** tables appear.

### D. Look, do not press

**D18. Cases → click a case.** At 1280 px or wider it opens beside the list; narrower, it replaces the list. Both are expected. The address shows `/cases?open=…`. You see the case facts, "Work this case" (Assign, Status, Priority, Due, each with a **Change** toggle) and Notes. A refund-resolution case also shows a "Refund resolution" section and Classify / Obligation rows. Do not open **Change**. No cases: write "none".

**D19. Reports.** An open report shows Mark reviewing (unless already reviewing), Actioned, Dismiss. Press none. No open reports: write "none".

**D20. System → "Approvals (second founder)".** "Nothing awaiting approval." or one card per approval. A card shows **Approve and execute** / **Deny**, or a notice such as "This approval cannot be decided by you (expired or already decided)." A red "denied" or "expired" badge under "Recently decided" is not a failure. Press nothing.

### E. Sign-out
21. Sign out from the preview. You return to `/login`. Note: sign-out is global (also ends your consumer web/app sessions), unchanged from the live console (decision H-11).
22. **No-write check:** write "I pressed nothing on the Do-not-press list", or list each one with page and time.

## Pass / fail
- **Pass:** A1-A3, A5, B6-B13, C14-C17, D18-D20, E21, E22 as expected. "none" is allowed where a step says so.
- **Fail, stop at once:** anything on the Do-not-press list was pressed; `/mfa` offered enrolment; C16 shows the "Needs registry 197" card or a flag reading on; C17 shows tables; C14 or C15 shows a failure card.
- **What a pass proves:** reads and designed states only. No v2 write ran on production. P2's write half stays open until named evidence exists (a local or rehearsal run, or an owner-gated write on a test case after cutover).
- Anything else: write what you saw and stop. F fixes or records it; the check is re-run on a new preview.

## After a pass
The owner's GO, for that exact step, merges #209 into `admin/operating-console` (the console's Vercel production branch); the merge's own build is cancelled by the old pin; then the Ignored Build Step pin moves to the MERGE commit and production builds that commit. Pin move + build is the cutover (A/PACKAGE-ADMIN-V2-P2-PREVIEW-20261102.md). #209 does not target `main`, so AUTODEPLOY-1 (merge to `main` applies migrations) does not apply to it. Production today serves `dddc8e92`, not `07100a35`. Operators reload console tabs after the deploy.
