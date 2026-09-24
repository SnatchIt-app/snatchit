# V3 phone-test checklist — one ordered pass

**B + C · 2026-09-24.** The single ordered runbook for the device session. The fixture semantics,
account list and write traces live in `V3_PHONE_TEST_FIXTURE_PLAN.md`; this file is the order to
execute in and the evidence class each step produces. Nothing here authorises a write.

**Build under test:** build number **23**, `65cb7633-0eca-4314-b135-fd9c90db8214`, commit
**`9c6c9bf4`**, iOS `preview` internal, sandbox project `ofaidukbieeekqaboscm`. Artifact recorded,
**not installed** — the owner asked that the phone session not start.

**The branch is one commit ahead of the build.** `24b021a3` is *not* in build 23. The only rendered
difference is the loading spinner's arc in Light — `#D31212` in the build, `#FF1A1A` on the branch;
both clear the 3:1 graphical bar. A screenshot taken from the branch is not evidence about build 23.

---

## How the four sections differ — read this before running anything

| Section | What it touches | Evidence it produces |
|---|---|---|
| **A · Pre-account** | Nothing. No account, no request that writes. Appearance is device-local (`AsyncStorage`), never a backend preference | Appearance, type, layout, chrome — **rendered on device** |
| **B · Signed in, reads only** | **Sign-in itself registers a push token** (DV-611). That is a side effect of ordinary use, not a fixture write. **No section-B check creates a row** | Real screens on **real account data** |
| **C · Synthetic gallery** | Renders the real components from supplied props. Sandbox-gated, read-only | **Rendering only.** Never retrieval, never the mapping from live rows, never the data path |
| **D · Creates records** | Bids, holds, PaymentIntents, `payments` rows | The states no fixture currently reaches. **Blocked — A's revision-2 fixture permissions are pending** |

**Not every step is write-free, and not every step needs a write.** Section A writes nothing at all.
Section B's only side effect is push-token registration at sign-in. Section D is the only section
that creates records, and each step names what it creates. Several checks that have been assumed to
need fixtures do **not** — the three-row bid summary's arithmetic (B3) and every appearance check
(A2–A16) run with no bid, no hold and no account.

**No step confirms a payment sheet. No charge is created by any step in this file.**

---

## A · Before sign-in — nothing is created anywhere

Run this whole section first: it costs nothing, needs no approval, and needs no cleanup.

| # | Step | Pass condition |
|---|---|---|
| **A1** | Install build 23. Confirm the build number on device | Build **23**, commit `9c6c9bf4` |
| **A2** | **Before first launch** set the phone to **Dark**. Cold launch | Midnight. Preference is `system` — nothing is stored yet |
| **A3** | Force-quit. Set the phone to **Light**. Cold launch. **Watch the first frame** | Daylight from the first frame. **This is the startup case that matters:** `resolveScheme` falls back to Midnight when the phone reports `null`, which iOS can do briefly at launch, so a Midnight frame before Daylight settles is a fail |
| **A4** | App foregrounded, switch the phone Light→Dark from Control Centre | Follows **live, no relaunch** |
| **A5** | Settings → Appearance | **Confirm Settings is reachable signed out.** Source shows no auth redirect on the profile tab or the settings route; if the device disagrees, A5–A10 move into section B |
| **A6** | With the phone on Dark, choose **Light** | Daylight, and it **stays** Daylight — an explicit choice overrides the phone |
| **A7** | Move the phone Dark→Light→Dark | The app does not move |
| **A8** | Force-quit, relaunch | Still Daylight. A silent save failure surfaces here: `saveAppearancePreference` never throws, so a failed write keeps the choice for that session only |
| **A9** | Choose **System** | Returns to following the phone immediately |
| **A10** | The selected row itself, in both appearances | Four cues, not colour alone: ✓ glyph, red border, tinted fill, `accessibilityRole="radio"` + checked. Measured — label 19.84:1 / 17.32:1, description 6.21 / 4.67, ✓ 5.12 / 4.81, border vs canvas 5.41 / 3.88. **The tint alone is 1.06:1 / 1.13:1 and carries nothing** — confirm the ✓ and the border are both visible in Light |
| **A11** | Larger Text to the largest non-AX size, then an AX size. Revisit Appearance, Home, Search | No clipping, truncation or overlap |
| **A12** | Dock and navigation in both appearances | Glass, selected capsule, hairline. Signed out the avatar is the **fallback initial** — the photo case is B7 |
| **A13** | Status bar in both | Light glyphs on Midnight, dark on Daylight |
| **A14** | Keyboard appearance in both (open search) | Matches the appearance |
| **A15** | Native alerts in both | Match the appearance |
| **A16** | Airplane Mode, pull to refresh Home | The offline/failed-read state renders correctly in both appearances |

## B · Signed in — reads only, no rows created

> **Disclosed side effect:** signing in registers a push token (DV-611). It is A's read-back, not a
> fixture, and it is the only thing section B causes.

| # | Step | Pass condition / limit |
|---|---|---|
| **B1** | Sign in as the DV buyer | — |
| **B2** | Home, Search, Listing detail, both appearances | D-1 mixed-case leading · D-2 over real artwork **and** the fallback plate |
| **B3** | Open bid entry **without placing a bid** | Three rows — Bid / Fee (10%) / Total — Total visually strongest, **Place bid** directly below, all three updating as the bid is edited, and **exactly one** total: no second total, no "all-in" caption, no explanatory sentence inside the summary. **Limit:** this cannot show "Current bid" against a real underlying bid, or "You're leading" — no sandbox listing has a bid. That is D1 |
| **B4** | Orders list | Read-only |
| **B5** | Transfers — **reversed**, both roles, on the four real rows | **Real-data evidence.** The only transfer state with real rows |
| **B6** | Tickets (D-8) | The real RPC and the empty state. Populated Tickets stay out of scope |
| **B7** | D-6 avatar across an account switch (buyer → seller) | Photo and fallback. Side effect: a second push-token registration |
| **B8** | D-3 enlarged text and D-5 keyboard on the Sell form and bid entry | **The form is not submitted and no bid is placed** |
| **B9** | D-4 narrowest supported width | No overlap or clipping |

## C · Synthetic gallery — rendering evidence only

| # | Step | Evidence class |
|---|---|---|
| **C1** | Settings → **Sandbox** → "Transfer states (sandbox gallery)" | The entry exists **only** on the sandbox build. Confirm it is absent from a non-sandbox build |
| **C2** | Expired and held blocks, both appearances | **Proves:** the real components render these states correctly from supplied props. **Does not prove:** live retrieval, the mapping from real rows, real `payout_hold_until` / `auto_release_at`, or the D-5 / D-6 data paths |
| **C3** | A fixture with a missing date field | Suppresses **only its own date line**; the rest of the status is unchanged |

## D · Creates records — BLOCKED, A's revision-2 fixture permissions pending

Do not run any of these until the owner approves the fixture sheet. Each names what it creates.

| # | Step | Creates | Unlocks | Cleanup |
|---|---|---|---|---|
| **D1** (W1) | One bid by the DV buyer on `58cc00e3` or `b1c3c478` (**never** `c343406e`) | 1 `bids` row · listing counters · 1 `bid_received` inbox row. No push while option (b) holds | "Current bid" against a real bid · "You're leading" · the outbid path | A's traced transaction, and it must run **before `ends_at`** — after that, finalisation adds a winner and an `auction_won` row to undo as well |
| **D2** (W2) | Buy Now hold, then enter checkout | A 10-minute server hold, and **on entering the screen** 1 PaymentIntent + 1 pending `payments` row — **before anything is tapped** | Checkout boards · server-figure rows · "Preparing your total" · hold-lost (~12 min) | **Not automatic.** The owner cancels the intent in the Stripe test dashboard and a fixture update moves the row `pending → failed`; otherwise one residue row is accepted |
| **D3** | Quantity-2 "Buy both now" verb | — | The plural verb | No quantity-2 listing exists; needs D4 or stays source-only |

---

## E · Confirmed defects to look at while running the above

From `V3_REVIEW_OF_C_9c6c9bf4.md`, measured at `24b021a3`. These are **open at the build commit** — expect
to see them, and record whether the phone agrees with the measurement. All are fixture-free.

| Look at | During | What the measurement predicts |
|---|---|---|
| A **sold or ended row** in Home/Search | B2 | The whole row is at 0.55 opacity, text included. The word **Sold**/**Ended** measures 3.45:1 on Midnight and **2.71:1 on Daylight**. The row is still tappable |
| A **cancelled listing** in My listings | B2 | Whole card at 0.55. "Cancelled" appears twice — a Badge (4.12:1 in Daylight) and a `faint` line at **1.49 / 1.54:1** |
| The **Past** section in Tickets | B6 | 0.92 dim. Only Daylight `metaQuiet` is marginal at **4.45:1**; everything else passes |
| **Notifications settings**, the one shipped switch | B-extra | In **Daylight** the thumb is near-black (`#0B0C0E`); the same control on the Sell form has a white thumb. F-33 is half closed |
| **Sell form**, the four unfilled pickers | B8 | "Select area or venue", "Pick a date", "Pick a time", "Select platform" at 15px, **~2.4:1 in both appearances** |
| **Tapping between text fields** on the Sell form | B8 | The focused underline changes hue only — **1.14:1 in Daylight**. The caret and keyboard are the real cues. Judge whether the focused field is identifiable when the keyboard is already up |
| The **6-digit code** field, if a push challenge appears | B-extra | Its only visible name is a `faint` placeholder that vanishes on the first keystroke |

**Not reachable without fixtures, so not in this pass:** the seller risk banners (they require a
`seller_risk_scores` row and appear only *after* tapping publish on a valid form) — including the
confirmed `critical_risk` / `listing_blocked` collapse, which is a source-verified defect, not a device one.
