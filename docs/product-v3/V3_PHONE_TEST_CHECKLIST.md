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

## Stage 0 · Preconditions

**PT-01** Install the new build; confirm its number on device · **PT-02** sign in as the **DV buyer**
(*session*) · **PT-03** the owner's explicit **"go"** · **PT-04** A's preflight and T0 capture.

Steps PT-05…PT-19 need none of these except the install.

## Stage 1 · Appearance, startup, type — class none / local

Run before sign-in: **first-launch state is unrepeatable** once a preference is stored.

| | Step | Pass |
|---|---|---|
| **PT-05** | Phone **Dark**, cold launch (nothing stored yet) | Midnight |
| **PT-06** | Phone **Light**, cold launch. **Watch the first frame** | Daylight from frame one. `resolveScheme` falls back to Midnight when the phone reports `null`, which iOS can do at launch — any Midnight frame is a fail |
| **PT-07** | Foregrounded, switch the phone Light↔Dark | Follows live, no relaunch |
| **PT-08** | Settings → Appearance → **Light**, phone on Dark *(local)* | Daylight, and it stays — the choice overrides the phone |
| **PT-09** | Move the phone Dark→Light→Dark | The app does not move |
| **PT-10** | Force-quit, relaunch | Still Daylight. Saves never throw, so a silent save failure only shows here |
| **PT-11** | Choose **System** *(local)* | Returns to following the phone |
| **PT-12** | Larger Text — largest non-AX, then an AX size — on Appearance, Home, Search, Sell | No clipping, truncation or overlap |
| **PT-13** | Status bar, keyboard appearance, native alerts, both appearances | Each matches the appearance |
| **PT-14** | Airplane Mode → pull to refresh Home | Offline / failed-read state correct in both |

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
