# V3 phone-test checklist — one ordered pass

**B + C · 2026-09-24 · reconciled against A's fixture approval sheet, revision 2, `7dae4815`**
(`docs/release/SANDBOX_V3_FIXTURE_APPROVAL_SHEET_20260924.md` on `release/candidate-20260918`).
Where this file and A's sheet differ, **A's sheet governs**. It owns the fixture identities, the exact
values, the dependency rules and the cleanup. This file owns only the order to execute in and the
evidence class each step produces. **Nothing here authorises a write.**

**Build under test:** build number **23**, `65cb7633-0eca-4314-b135-fd9c90db8214`, commit **`9c6c9bf4`**,
iOS `preview` internal, sandbox project `ofaidukbieeekqaboscm`. **A diagnostic artifact, not a release
candidate.** Artifact recorded, not installed.

**The branch is eight commits ahead of the build.** Build 23 is `9c6c9bf4`. What it does NOT contain,
so that a tester does not re-report any of it, and so that no screenshot from the branch is mistaken
for evidence about the build:

| Commit | Absent from build 23 |
|---|---|
| `24b021a3` | the Light loading-spinner arc is `#D31212` in the build, `#FF1A1A` on the branch (both clear 3:1) |
| `d981727e` | the past ticket card still dims its own text (date and venue at 4.44:1 in Light) · the risk banners still carry ungraded tints (edges 1.32–1.75:1 Light, fills 1.03–1.07:1 apart) · nine `text.faint` values still faint · the bio counter's over-state still unreachable |
| `2ffb10a8` | **FeedRow, SellerListingCard and DiscoveryCard still dim their own text** — "Sold"/"Ended" 2.71:1, "Cancelled" 2.11:1, the DiscoveryCard badge 4.12:1, all in Light · the **auth brand mark is still untinted**, i.e. a white monogram on Daylight's white canvas on all three auth screens · the push-challenge code field still has no visible label · signup's "At least 6 characters" still vanishes on the first keystroke · the sell form's unfilled pickers still at 2.4:1 · the notifications switch thumb still near-black in Light · **a transient eligibility failure still says "We've noticed some recent issues"** · "Contact support" still offers no route |

| `ca27d282`, `aee15697`, `404bce38` | **the whole dispute-copy set** (all three A-reviewed PASS). Build 23 tells a buyer who lost a dispute "You confirmed receipt. Enjoy the event.", tells the seller "The buyer confirmed they received the tickets.", and badges that row a green **"Received"** on the receive screen, the send screen AND the Bids board. It also says "Your payout is being processed" under a hold, and promises a notification the phone cannot keep |

These are presentation defects the tester WILL see on build 23. Expect them; do not re-report them.
**No replacement build is authorised.** A preview recut is **not** gate G2 — G2 is the *production*
build, and whatever commit that pins will carry these fixes anyway (A, 2026-09-24). The recut is its
own owner item, **S1** in §8 of A's submission checklist; A's G1 applies either way.

### C's assessment of the artifact, since this is where it gets called

**One item has crossed from "dated" into "reads as broken", and it is the FIRST thing a signed-out
tester sees.** Stage 1 deliberately runs before sign-in, and on build 23 in **Light** the auth
screens' brand mark is an untinted white monogram on a white canvas — i.e. the login, signup and
reset screens show an empty space where the logo belongs. A tester meeting that at PT-06/PT-07 has no
way to read it as a known, fixed-on-branch defect rather than a broken build, which is exactly the
line I said I would flag.

Everything else in this table is legibly "dated": a dim that is too strong, a prompt that is too
faint, copy that is wrong on a path the sandbox cannot even reach (no dispute has ever been resolved
in production, and no fixture creates one).

**So: the appearance and rendering pass is still worth running on build 23** — the migration itself,
which is what the pass is for, is entirely present at `9c6c9bf4`. My recommendation is to run Stages
1–3 on it and accept the two conspicuous items above as known, **or** recut once if the owner would
rather the first screen of the session look right. The decision is the owner's, as item S1; I am
recording the input, not requesting the build. Note what this is NOT: because the production build
will pin a commit that already carries the fix, the untinted mark is a defect of **this sandbox
artifact**, never of a release candidate.

---

## Step IDs — deliberately distinct from every other ID in this programme

| Prefix | Belongs to | Do not confuse with |
|---|---|---|
| **`PT-nn`** | **this file** — the order of the device pass | — |
| `D1, D3, D4, D5, D6` (no hyphen) | **A's sheet** — a *permission* to make one named write | the checklist steps |
| `D-1 … D-9` (hyphenated) | `V3_PHONE_TEST_FIXTURE_PLAN.md` — the *device checks* | A's permissions |
| `W1, W2` | A's sheet — the two handset-initiated writes | — |

The earlier revision of this file numbered its own steps `D1–D3`, which collided with A's permission IDs.
Those IDs are withdrawn; nothing in this file uses a bare `D` number for a step any more.

## What each step touches — four classes, not two

| Class | Meaning |
|---|---|
| **none** | No write of any kind, on the phone or the sandbox |
| **local** | Writes only to the phone's own storage — the appearance preference in `AsyncStorage`. Never leaves the device, is not a backend preference, needs no cleanup |
| **session** | Sign-in or an account switch. **Registers a push token on the sandbox** under the DV-611 rule. A real write, not a fixture; A's closing read expects it as known residue |
| **fixture** | Requires one of A's approved writes. Each step names the sheet's permission ID |

**There is no step of which "nothing is created anywhere" is true once sign-in has happened.** Stage 1 is
the only stage with no sandbox effect at all, and even there the appearance preference is written locally.

**No step confirms a payment sheet. No card is ever entered. No charge is created by any step in this file.**

---

## Stage 0 · Preconditions — A's sheet §0, all four before any write

| | |
|---|---|
| **PT-01** | Install build 23 on the owner's iPhone. Confirm build number **23** on device |
| **PT-02** | C's pre-build gates pass at the pinned commit and the build is FINISHED — already true at `9c6c9bf4` |
| **PT-03** | Sign in as the **DV buyer** `919d511e…`. **Class: session** — this registers a push token |
| **PT-04** | The owner says "go" for the session in chat |
| **PT-05** | A's T0 capture has run and matches §4 of the sheet |

**Variant gate:** if the session starts before **2026-09-25 02:01:44Z**, L-BID and L-CHK are still live
(A's variant A). After that they have ended with no bids (variant B) and the extension needs the bypass.

## Stage 1 · Appearance and layout — class: none / local

Run before sign-in where possible: the **first-launch state is unrepeatable** once a preference is stored.
If the owner prefers to sign in first (PT-03), PT-06 and PT-07 are lost for this session — record that.

| | Step | Class | Pass condition |
|---|---|---|---|
| **PT-06** | **Before first launch** set the phone to **Dark**. Cold launch | none | Midnight. Preference is `system`; nothing is stored yet |
| **PT-07** | Force-quit. Set the phone to **Light**. Cold launch. **Watch the first frame** | none | Daylight from the first frame. **The startup case that matters:** `resolveScheme` falls back to Midnight when the phone reports `null`, which iOS can do briefly at launch, so a Midnight frame before Daylight settles is a fail |
| **PT-08** | App foregrounded, switch the phone Light→Dark from Control Centre | none | Follows **live, no relaunch** |
| **PT-09** | Settings → Appearance | none | **Confirm Settings is reachable signed out.** Source shows no auth redirect on the profile tab or the settings route; if the device disagrees, PT-09…PT-13 move after PT-03 |
| **PT-10** | With the phone on Dark, choose **Light** | **local** | Daylight, and it **stays** — an explicit choice overrides the phone |
| **PT-11** | Move the phone Dark→Light→Dark | none | The app does not move |
| **PT-12** | Force-quit, relaunch | none | Still Daylight. A silent save failure surfaces here: `saveAppearancePreference` never throws, so a failed write keeps the choice for that session only |
| **PT-13** | Choose **System** | **local** | Returns to following the phone immediately |
| **PT-14** | The selected row itself, both appearances | none | Four cues, not colour alone: ✓ glyph, red border, tinted fill, `accessibilityRole="radio"` + checked. Measured — label 19.84 / 17.32:1, description 6.21 / 4.67, ✓ 5.12 / 4.81, border vs canvas 5.41 / 3.88. **The tint alone is 1.06 / 1.13:1 and carries nothing** |
| **PT-15** | Larger Text to the largest non-AX size, then an AX size. Revisit Appearance, Home, Search | none | No clipping, truncation or overlap |
| **PT-16** | Dock and navigation, both appearances | none | Glass, selected capsule, hairline. Signed out the avatar is the **fallback initial**; the photo case is PT-30 |
| **PT-17** | Status bar, both appearances | none | Light glyphs on Midnight, dark on Daylight |
| **PT-18** | Keyboard appearance, both (open search) | none | Matches the appearance |
| **PT-19** | Native alerts, both | none | Match the appearance |
| **PT-20** | Airplane Mode, pull to refresh Home | none | The offline / failed-read state renders correctly in both appearances |

## Stage 2 · Signed in, reads only — class: none (the session write already happened at PT-03)

| | Step | Pass condition / limit |
|---|---|---|
| **PT-21** | Home, Search, Listing detail, both appearances | D-1 mixed-case leading · D-2 over real artwork **and** the fallback plate. L-BID and L-CHK are both image-400 listings, so the fallback is covered here |
| **PT-22** | Open bid entry on a live listing **without placing a bid** | Three rows — Bid / Fee (10%) / Total — Total visually strongest, **Place bid** directly below, all three updating as the bid is edited, and **exactly one** total: no second total, no "all-in" caption, no explanatory sentence inside the summary |
| **PT-23** | Orders list | Read-only |
| **PT-24** | Transfers — **reversed**, both roles, on A's four real rows | **Real-data evidence.** The only transfer state with real rows and no write |
| **PT-25** | Deadline cells `8f59d37e` (seller_sent) and `92ee5156` (pending) | Read-only, used as they are |
| **PT-26** | Tickets — the real `get_my_tickets()` RPC | **The empty state only.** See the coverage limit below |
| **PT-27** | Sell form — D-3 enlarged text, D-5 keyboard | **The form is not submitted** |
| **PT-28** | D-4 narrowest supported width | No overlap or clipping |

> **Tickets coverage limit — record it, do not imply otherwise.** `kernel.tickets` is **0** on this sandbox
> (A's read). PT-26 therefore demonstrates the RPC, its column contract and the **empty state**, and nothing
> else. **Populated Tickets, the Upcoming card, the Past section and the ticket status badges are NOT
> covered by this pass.** This matters beyond coverage: the measured `TicketEventGroup` item in Stage 5 —
> Daylight `metaQuiet` at 4.45:1 inside the 0.92 "Past" dim — **cannot be observed on device in this
> session at all.** It stays source-and-computed evidence only. No fixture is proposed for it.

## Stage 3 · Synthetic gallery — rendering evidence only

| | Step | Evidence class |
|---|---|---|
| **PT-29** | Settings → **Sandbox** → "Transfer states (sandbox gallery)"; expired and held blocks, both appearances; a fixture with a missing date field | **Proves:** the real components render these states correctly from supplied props, and that a missing date suppresses **only its own line**. **Does not prove:** live retrieval, the mapping from real rows, real `payout_hold_until` / `auto_release_at`, or the D5 / D6 data paths — those are PT-33 and PT-34 |

> **The gallery cannot establish its own absence from a production build, and this step must not be read as
> doing so.** Seeing the entry on a sandbox build says nothing about a production one. The route file
> **ships in every bundle** — Expo Router registers everything under `app/` — so the correct claim is
> "production redirects it", never "production does not contain it". The evidence for that claim is
> separate, and none of it is a device check:
> 1. **Build configuration** — `eas.json`'s `production` profile sets `EXPO_PUBLIC_APP_ENV: "production"`
>    and the production Supabase host, so `IS_SANDBOX_BUILD` (`src/config/envGuard.ts:146`) is false.
> 2. **Platform fact** — `__DEV__` is false in a release build, so the second disjunct fails too.
> 3. **Source + harness** — `app/_dev/transfer-states.tsx` redirects at render when neither holds;
>    `tests/v3-gallery-entry.test.ts` and `tests/v3-transfer-gallery.test.ts` assert the redirect and the
>    gated Settings entry.
> 4. **Not available** — the only direct evidence would be a production-profile build with a deep link
>    tried against it. No such build exists and none is authorised. **The assertion rests on 1–3.**

## Stage 4 · Fixture-backed checks — class: fixture. A's dependency order, not ours

**Pre-session SQL by A, before the handset does anything here:** **D1** (extend L-BID and L-CHK by 24 h)
then **D4** (L-CHK quantity 1 → 2). A's rule: D1 before W1 and W2; D4 before W2.

| | Step | A's permission | What it creates |
|---|---|---|---|
| **PT-30** | **W1 — exactly one bid: $105, DV buyer, on L-BID `58cc00e3` ONLY.** $105 is the screen's preselected minimum ($100 + `MIN_BID_INCREMENT` 5). Then: "Current bid" against a real underlying bid, and "You're leading" | **D2 (W1)** | 1 `bids` row · L-BID counters (`current_bid 105`, `bid_count 1`, `highest_bidder_id`) · **1 `public.notifications` row** for the DV seller, dedupe `bid_received:<bid id>`. **No push, no outbound request** — Vault holds `project_url` only and both `app.settings` values are unset |
| **PT-31** | **W2 — the one Buy Now of the session, on L-CHK `b1c3c478` ONLY, after D4.** Open by deep link → "Buy both now" → capture the ready boards in **both appearances within the 10 minutes** → **do not tap Pay** → stay on screen; at 10:00 the hold-lost board appears → leave with Back | **D3 (W2)**, needs **D4** | A 10-minute server hold, and **on mounting checkout** exactly 1 Stripe **test-mode** PaymentIntent + 1 `pending` `payments` row (total 11000, mode `buy_now`) + a transient `checkout_group_claim` + `rate_limits` upserts + L-CHK set `reserved`. Remount, retry and **switching appearance** take the REUSE path — no second intent |
| **PT-32** | On L-CHK, confirm the quantity-2 presentation: the verb **"Buy both now"**, the all-in figure **$110**, checkout showing **2 tickets** and a **$110** total, "2 × <type>", "· sold together" on the bid screen | **D4** (already applied for PT-31) | No additional write — this is the same listing PT-31 uses. `buy_now_price` is charged **once for the whole listing** (A-01, owner ruling 2026-09-22); the check verifies labels against the server figure and changes no pricing |
| **PT-33** | Buyer's receive screen on **F-EXP `19be875b`** — the expired state, with a succeeded payment and **no refund recorded** | **D5** | `status pending → expired`, `expired_at → now()`. State-inbox trigger has no `expired` branch: **0 rows** |
| **PT-34** | Seller's send screen on **F-HELD `83b83858`** — the held branch with its dated line, countdown lines suppressed | **D6** | Four payout columns set. **0 notification rows** |
| **PT-35** | **LAST — the buyer→seller account switch**, then D-6 avatar (photo and fallback) | — | **Class: session.** Registers the **seller's** push token (DV-611). A's rule: it **must not interrupt W2**, which is why it is last |

### Limits inside Stage 4 — state them, do not let the pass imply otherwise

- **The outbid path is UNTESTED and stays untested.** W1 is the session's only bid, and it is the *first*
  bid on L-BID, so there is no previous leader: `trg_notify_bid_inbox` writes a `bid_received` row and **no
  `outbid` row**, and `notify_outbid` has nothing to act on. **One first bid cannot establish outbid
  behaviour** — not the outbid notice, not the outbid inbox row, not the outbid push. A second bid is
  explicitly outside A's sheet ("exactly one bid"; a second creates an outbid-class state and more
  cleanup). Record the outbid path as **not covered by this session**.
- **Price change is not covered.** No write is proposed for it; it stays test-only.
- **L-P1 `c343406e` is read-only and must not be opened for checkout** — a Buy Now there would reuse the
  DV buyer's old pending intent and release W2's hold.
- **The risk banners are not reachable.** They need a `seller_risk_scores` row and appear only *after*
  tapping publish on an otherwise-valid form. No fixture is proposed. The confirmed `critical_risk` /
  `listing_blocked` collapse is source-verified, not a device finding.

### Cleanup — A's four tracks. Reproduced in order because the order is the safety property.

A executes every SQL step; **the owner executes only the Stripe cancellation.** Tracks run independently
except where stated.

- **Track W1** (the bid) — starts when the bid-screen check is done, deadline **bid time + 60 min** and in
  any case before L-BID's extended end. **Never waits for Stripe.** Delete the seller's `bid_received`
  notification → delete the bid → restore L-BID's counters under the listing bypass → verify against T0.
- **Track T** (the transfer fixtures) — starts when PT-33/PT-34 are done, deadline **T0 + 2 h 30 min**.
  **Never waits for Stripe.** F-EXP back to `pending` / `expired_at NULL` (verify md5 `a4c234da…`);
  F-HELD's four columns back to NULL (verify md5 `d1b36045…`).
- **Track C** (L-CHK and its intent) — **ordered around confirmed cancellation, and the order is
  conditional. Do not summarise it as "a fixture update moves the row pending → failed".**
  1. **Hold** lapses on its own at 10 minutes; job 1 clears it within ~2 more. A verifies `reserved_by`
     NULL by reservation + 15 min. Nothing forces it.
  2. **Identify** (A) — the one DV-buyer `payments` row created on L-CHK after T0; record its id and
     `pi_…`; send the `pi_…` to the owner at session end.
  3. **Cancel** (**owner**, in the Stripe test dashboard) — §6 of the sheet.
  4. **Confirm** (A) — poll the row for up to 10 minutes. The deployed `stripe-webhook` moves it
     `pending → failed` on `payment_intent.canceled`, and only from `pending`/`processing`. **If it moves,
     cancellation is confirmed by two routes and no SQL runs at all.** Whether this sandbox's webhook
     endpoint subscribes to `payment_intent.canceled` is **not established**, so A expects step 5 to be
     the normal path.
  5. **Only if step 4 does not move it** — the guarded update, run only if **all** hold: the owner
     confirmed "Canceled" for exactly that id; the row still carries that id and is `pending`; L-CHK has
     no `succeeded` payment; L-CHK is not reserved. Record the missing webhook delivery as a finding, with
     cancellation confirmed by one route.
  6. **Then, and only then:** D4 restore (quantity 2 → 1), followed by track E for L-CHK.
  **Why the row is never marked failed first:** marking it failed does not stop a charge — a live intent
  can still be confirmed and the webhook would move `failed → succeeded`. Only cancellation is terminal.
- **Track E** (end-time restore) — L-BID after track W1; L-CHK after track C step 6. Refuses unless
  `bid_count = 0`, `winner_user_id IS NULL` and the listing is not reserved.
- **If the owner is unavailable:** tracks W1 and T complete regardless. **Track C stops at step 2** — the
  intent stays open and the row stays `pending`. **A never marks the row failed as a substitute for
  cancelling the intent**, however long the owner is away.
- **Known residue at the closing read:** the W2 row (now `failed`), `rate_limits` rows, and any push token
  PT-03 / PT-35 registered.

---

## Stage 5 · Confirmed defects to look at while running the above

From `V3_REVIEW_OF_C_9c6c9bf4.md`, measured at `24b021a3`. **Open at the build commit** — expect to see
them, and record whether the phone agrees with the measurement. All are class **none**.

**C is fixing these in source now. Before running, re-read `V3_REVIEW_OF_C_9c6c9bf4.md` §6 for which fixes
landed after `9c6c9bf4` and are therefore NOT in build 23.**

| Look at | During | What the measurement predicts |
|---|---|---|
| A **sold or ended row** in Home/Search | PT-21 | Whole row at 0.55 opacity, text included. The word **Sold**/**Ended** measures 3.45:1 Midnight, **2.71:1 Daylight**. The row is still tappable |
| A **cancelled listing** in My listings | PT-21 | Whole card at 0.55. "Cancelled" appears **twice** — a Badge (4.12:1 Daylight) and a `faint` line at **1.49 / 1.54:1** |
| **Notifications settings**, the one shipped switch | PT-21 | In **Daylight** the thumb is near-black; the same control on the Sell form has a white thumb. F-33 is half closed |
| **Sell form**, the four unfilled pickers | PT-27 | "Select area or venue", "Pick a date", "Pick a time", "Select platform" at 15px, **~2.4:1 in both appearances** |
| **Tapping between text fields** on the Sell form | PT-27 | The focused underline changes hue only — **1.14:1 in Daylight**. The caret and keyboard are the real cues |
| The **6-digit code** field, if a push challenge appears | PT-21 | Its only visible name is a `faint` placeholder that vanishes on the first keystroke |
| **Tickets "Past" section** | — | **Not observable this session** — the table is empty. Source-and-computed evidence only |
