# V3 phone-test checklist

**B + C · updated in place 2026-09-24 for the new artifact.** Supersedes the Build 23 version entirely.

**Artifact under test:** the sandbox `preview` build from commit **`404bce38969780f1db057e96dec71609c6795ed4`**
(`v3/midnight-app`). C is authorised to create this one build; **build id and number to be filled in on
creation**. Build 23 / `9c6c9bf4` is **retired as a test artifact** — the defects it was kept to demonstrate
are fixed in this commit.

**A's fixture sheet at `7dae4815` governs every fixture action and cleanup.** D1–D6 are **approved by the
owner**, conditional on: the build installed, the owner's explicit session **"go"**, and **A's preflight**.
This file does not restate, re-decide or broaden any of that — it gives the order only. Where this file and
A's sheet differ, **A's sheet governs**.

## Three kinds of evidence, recorded separately — never merged into one verdict

| | What it is | Where it lives |
|---|---|---|
| **Source review** | Reading the code at `404bce38` | `V3_REVIEW_OF_C_404bce38.md` |
| **Computed contrast** | Palette values composited and measured. Preliminary — not a device observation | same document, marked as computed |
| **Device observation** | What the phone actually renders | **this file only**, filled in during the pass |

## What each step touches

**none** · no write anywhere — **local** · the phone's own `AsyncStorage` appearance preference, never
leaves the device — **session** · sign-in or account switch, which **registers a push token** (DV-611); a
real effect, not a fixture — **fixture** · needs one of A's approved writes, named by its sheet ID.

**No step confirms a payment sheet. No card is entered. No charge is created.**

---

## Stage 0 · The build under test, and the preconditions

| | |
|---|---|
| **Build** | number **24** · id **`c5b3a615-ff97-4a88-a4ce-2dae24558478`** |
| **Commit** | **`404bce38969780f1db057e96dec71609c6795ed4`** — the pin the owner authorised, unchanged |
| **Install page** (open on the iPhone) | `https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/c5b3a615-ff97-4a88-a4ce-2dae24558478` |
| **Artifact** | `https://expo.dev/artifacts/eas/7J2ZIJ0uG7LaS85lnoMUwVF9Nc0OpdOJvePZ69GgHo0.ipa` |
| Profile | `preview`, iOS internal · SDK 54.0.0 · version 1.0.0 · fingerprint `1fa6c258…` |
| Sandbox | `ofaidukbieeekqaboscm` only · `pk_test_` Stripe key · built 11:43→11:50, 2026-09-24 |
| Gates at that commit | 149 files **2704/2704** · `tsc` 0 · lint 0 errors / 29 warnings · gated payment surface `signOut.ts +5` only vs `e079fcc1` |

**PT-01** Install build 24 and confirm the number **on device** · **PT-02** sign in as the **DV buyer**
(*session*: registers one push token) · **PT-03** the owner's explicit **"go"** · **PT-04** A's preflight and
T0 capture.

**Only PT-01 gates Stage 1. PT-02 gates Stage 1b onward. PT-03 and PT-04 gate Stage 4 only** — no
appearance, navigation, type or read-only check waits on the owner's "go" or on A's preflight.

### Recording the starting state, instead of claiming the first launch is unrepeatable

It **is** repeatable, through a controlled reset, so record what is actually stored rather than treating
the first launch as a one-shot:

| State | Where it lives | Before Stage 1, record |
|---|---|---|
| Appearance preference | `AsyncStorage` key **`snatchit.appearance.v1`** (`src/lib/appearance/appearanceStore.ts:14`); absent = System | absent, or `system` / `light` / `dark` |
| Session | `LargeSecureStore` — an AES-256 blob in AsyncStorage (`src/lib/supabase.ts:10`) | signed out, or which account |

**Controlled reset, when a first-launch check needs re-running:** delete the app from the home screen and
reinstall from the install page above. That clears the app container, so both the stored preference and the
session go with it, and PT-05…PT-07 can be repeated as often as needed. Deleting the app is the reset; there
is no in-app control for it, and none is needed.

## Stage 1a · Signed OUT — cold launch and live following. Class: none

These are the only checks that run before sign-in, because **Settings is not reachable while signed out**:
`rootRouteDecision` (`src/lib/auth/rootRoute.ts:72`) sends a `signed_out` phase to `/(auth)/login`, and the
auth screens offer no route into Settings. What these three exercise is System resolution and the first
painted frame — no stored preference is involved yet.

| | Step | Pass |
|---|---|---|
| **PT-05** | Phone **Dark**, cold launch with nothing stored | Midnight. The login screen's SN monogram is visible (white on the dark canvas) |
| **PT-06** | Force-quit. Phone **Light**. Cold launch and **watch the first frame** | Daylight from frame one — `resolveScheme` falls back to Midnight when the phone reports `null`, which iOS can do briefly at launch, so any Midnight frame is a fail. **And the login screen's SN monogram must be visible as dark-on-white**: build 23 drew that asset untinted, so this is the check for `2ffb10a8` |
| **PT-07** | Foregrounded on the login screen, switch the phone Light↔Dark | Follows live, no relaunch |

## Stage 1b · Signed IN — the stored preference. Class: none / local

Runs after **PT-02**. Every step here needs Settings, which needs a session.

| | Step | Pass |
|---|---|---|
| **PT-08** | Settings → Appearance → **Light**, with the phone on Dark *(local)* | Daylight, and it stays — an explicit choice overrides the phone |
| **PT-09** | Move the phone Dark→Light→Dark | The app does not move |
| **PT-10** | Force-quit, relaunch | Still Daylight. `saveAppearancePreference` never throws, so a silent save failure shows only here |
| **PT-11** | Choose **System** *(local)* | Returns to following the phone immediately |
| **PT-11b** | The selected row itself, both appearances | Four cues, not colour alone: ✓ glyph, red border, tinted fill, `accessibilityRole="radio"` + checked. The tint alone is 1.06 / 1.13:1 and carries nothing |

## Stage 1c · Type, chrome and offline — signed in. Class: none

| | Step | Pass |
|---|---|---|
| **PT-12** | Larger Text — largest non-AX, then an AX size — on Appearance, Home, Search, Sell | No clipping, truncation or overlap |
| **PT-13** | Status bar, keyboard appearance, native alerts, both appearances | Each matches the appearance |
| **PT-14** | Airplane Mode → pull to refresh Home | The offline / failed-read state is correct in both appearances |

## Stage 2 · Signed in, reads only — no rows created

| | Step | Pass / limit |
|---|---|---|
| **PT-15** | Home, Search, Listing detail, both appearances | Mixed-case leading; **artwork** — text over real uploads **and** the fallback plate. L-BID and L-CHK are both image-400 listings, so the fallback is covered here |
| **PT-16** | **Sold / ended rows** and a **cancelled listing** | The artwork recedes; **the words do not**. "Sold" / "Ended" and "Cancelled" at full strength on rows that stay tappable |
| **PT-17** | Dock, navigation, avatar | Glass, selected capsule, hairline; avatar photo and fallback initial |
| **PT-18** | Auth screens, both appearances | The brand mark legible on both canvases |
| **PT-19** | **Bid entry, without placing a bid** | Exactly three rows — Bid / Fee (10%) / Total — Total strongest, **Place bid** directly below, all updating live. **One total only:** no second total, no "all-in" caption, no explanatory sentence inside the summary |
| **PT-20** | **Selling** — Sell form in both appearances; the four unfilled prompts (*Select area or venue · Pick a date · Pick a time · Select platform*); focus moving between fields; keyboard | Prompts legible; **not submitted** |
| **PT-21** | Orders; deadline cells `8f59d37e`, `92ee5156` | Read-only |
| **PT-22** | **Transfers — reversed**, both roles, on A's four real rows | **Real data.** The only transfer state with real rows and no write |
| **PT-23** | Tickets — the real RPC | **Empty state only.** See the limit below |
| **PT-24** | Narrowest supported width | No overlap or clipping |

> **Tickets — state the limit, do not imply otherwise.** `kernel.tickets` is **0**. PT-23 demonstrates the
> RPC, its column contract and the empty state. **Populated Tickets, the Upcoming card, the Past section
> and the ticket status badges are NOT covered.** No fixture is proposed for them.

## Stage 3 · Synthetic gallery — rendering evidence only

**PT-25** Settings → Sandbox → "Transfer states (sandbox gallery)": expired and held blocks in both
appearances, and a fixture with a missing date field.

**Proves** the real components render these states from supplied props, and that a missing date suppresses
only its own line. **Does not prove** live retrieval, the mapping from real rows, real
`payout_hold_until` / `auto_release_at`, or the D5 / D6 data paths — those are PT-28 and PT-29.

> **This step cannot establish the gallery's absence from a production build.** The route ships in every
> bundle — Expo Router registers all of `app/` — so the claim is "production redirects it", never
> "production does not contain it". That evidence is separate and none of it is a device check:
> `eas.json`'s production profile (`EXPO_PUBLIC_APP_ENV: "production"`, production host, so
> `IS_SANDBOX_BUILD` is false); `__DEV__` false in a release build; the render-time redirect and its tests.
> No production build exists.

## Stage 4 · Fixture-backed — A's order. D1–D6 approved; conditions in the header.

Pre-session SQL by A: **D1** (extend L-BID and L-CHK) then **D4** (L-CHK quantity → 2).

| | Step | A's ID | Notes |
|---|---|---|---|
| **PT-26** | **One bid — $105, DV buyer, L-BID `58cc00e3` only** | **D2 / W1** | Then "Current bid" against a real bid, and "You're leading" |
| **PT-27** | **The session's one Buy Now — L-CHK `b1c3c478` only, after D4.** Deep link → "Buy both now" → capture the ready boards **in both appearances inside the 10 minutes** → **do not tap Pay** → stay for the hold-lost board at 10:00 → Back. Confirm "Buy both now", **$110** all-in, 2 tickets, "2 × «type»", "· sold together" | **D3 / W2**, needs **D4** | Entering checkout creates the intent **before anything is tapped**. Remount, retry and **switching appearance** reuse it |
| **PT-28** | Buyer's receive screen — **expired** on F-EXP `19be875b` | **D5** | Succeeded payment, **no refund recorded** |
| **PT-29** | Seller's send screen — **held** on F-HELD `83b83858` | **D6** | The dated hold line; countdown lines suppressed |
| **PT-30** | **LAST — buyer→seller account switch**, then the avatar across accounts *(session)* | — | A's rule: it must not interrupt PT-27 |

### Coverage limits — record them as limits, not as results

- **Outbid is NOT covered.** PT-26 is the session's only bid and the **first** bid on L-BID, so there is no
  previous leader: no `outbid` row exists to observe. One first bid cannot establish outbid behaviour —
  not the notice, not the inbox row, not the push. A second bid is outside A's sheet.
- **Populated Tickets is NOT covered** — the table is empty.
- **Price change is NOT covered.** No write is proposed; it stays test-only.
- **L-P1 `c343406e` is read-only** — a Buy Now there would reuse an old pending intent and release PT-27's hold.
- **Seller risk banners are not reachable** — they need a `seller_risk_scores` row and appear only after
  tapping publish. Source-verified only.

### Cleanup — A's sheet §5 governs. Ordering reproduced because the order is the safety property.

Tracks **W1** (bid, deadline bid+60 min) and **T** (transfer fixtures, T0+2h30) run independently and
**never wait for Stripe**. Track **C** is conditional: the hold lapses on its own → A identifies the row and
`pi_…` → **the owner cancels in Stripe** → A polls up to 10 min for the webhook to move it
`pending → failed` → **only if it does not**, the guarded SQL, under all four of A's conditions → **then**
the D4 restore → then end-time restore. **A never marks the row failed as a substitute for cancelling.**
If the owner is unavailable, track C stops after identifying the row.

---

## Device observations — filled in during the pass, empty until then

| Step | Appearance | Observed | Matches source/computed? |
|---|---|---|---|
| | | | |
