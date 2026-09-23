# V3 Package 6 — completion: Bids, listing actions, the remaining surfaces

**B → C · 2026-09-22.** Closes every item the gap audit listed as undesigned. Read at release source
`5b255838`.

**Artifacts:** `pkg6-bids-{clean,active,past,empty,refresh_failed}.png` · `pkg6-listing-action-matrix.png` ·
`pkg6-listing-dialogs.png` · `pkg6-settings-surfaces.png` · `pkg6-system-surfaces.png`.

---

## 1 · The Bids tab

**The tab holds bids *and* purchases.** The shipped header comment says why: a buyer with no bids must never
see "No active bids" sitting over a completed purchase.

**Two segments, not six pills** — Active and Past, assigned by `bidGroupOf`, so nothing appears in both.
Sorting is the shipped priority: **Won → Marked sent → Outbid → Winning**.

**Ten row states, each a word plus an action hint** (`bidPresentation`):

| State | Tone | Hint |
|---|---|---|
| Won | brand | Pay to claim |
| Marked sent | warning | Confirm receipt |
| Purchased | warning | — |
| Outbid | danger | Bid again |
| Winning | success | You're leading |
| Received | success | View transfer |
| Disputed | danger | View dispute |
| Sold / Ended | neutral | View listing |
| Cancelled | neutral | Listing was cancelled |

**The hint says what the row will do, never what has happened to money.** Urgency is amber and appears only
inside `ENDING_SOON_MS` (60 minutes); outside that window nothing is drawn.

**States drawn:** active, past, empty, and the **inline failed refresh** using `BIDS_REFRESH_FAILED_COPY` —
the list is never replaced by an error when there is something to keep.

---

## 2 · Listing detail — the role/action matrix

`pkg6-listing-action-matrix.png` shows **all eleven resolution branches in the code's priority order**, with
role, primary, secondary, and **what each action opens or submits**.

**Red marks the buying path — corrected 2026-09-22.** I first wrote *"red marks money… Buy now, Pay now,
Finish checkout and Place bid commit or move money."* **That is false for all four**, and it contradicted the
finding printed below it in this same section. Traced through `runAction`: `place_bid`, `pay_now` and
`continue_reservation` are **pure navigation**; `buy_now` calls `reserve_buy_now` — a real server side-effect
that blocks other buyers — and then navigates. **None of the four charges anything.**

**The rule, restated: red marks the single action that advances this viewer toward paying. It is not a claim
that money moves on tap.** The approved hierarchy is unchanged — the same four stay red, and *Send tickets,
View transfer, Review transfer, View dispute* stay secondary on a truer axis: they manage an order that
**already exists**. A different job, not a weaker one.

**The consequence is carried by labels and confirmations, never by colour.** `Buy now · {all-in}` reads
**"Reserving…"** in flight (shipped `pendingLabel`) — it names the hold, not a purchase, and **must be
preserved**. `/bid/{id}` submits with `Place bid · $104.50 all-in`. `/checkout/{id}` charges with
`Pay $99.00`. Full derivation: `V3_FREEZE_RECONCILIATION_20260922.md` §2.

Two disabled states are real and stay disabled: **"Your listing"** (a seller gets no bid and no Buy Now — the
database refuses both) and **Sold / Cancelled / On hold / Ended**.

**"Place bid" opens `/bid/{id}`; it does not submit.** The submission control lives on the bid screen and
carries the all-in total — already implemented on C's branch. **`detailState.ts` L312 already labels the
listing-screen action plainly `'Place bid'`, with no amount** — the ambiguous `Place bid · $104.50` came from
my mockup, not from the release source.

**All twelve `StatusKind`s** are rendered with their shipped label, detail and tone.

---

## 3 · Listing detail — all 23 dialog call sites (24 copy variants)

**Corrected 2026-09-22. This section first said "all 17 distinct dialogs". 17 was the number I drew, not the
number that exists.** The file has **23 `Alert.alert` call sites** rendering **24 copy variants** (`L871`
renders one of two bodies). Six were missing — not consolidated away, simply absent — and all six are now
drawn. Line-by-line map with a disposition for every one:
`V3_FREEZE_RECONCILIATION_20260922.md` §1.

`pkg6-listing-dialogs.png` now groups them into **five** patterns, and **every card carries its source line** so
the map is checkable against the file rather than against my summary:

| Pattern | Members | Shape |
|---|---|---|
| BLOCKED | 7 | single action; returns you unchanged |
| RACE LOST | 5 | single action; the screen is out of date |
| **CONFIRM** | 4 variants / 3 call sites | **two buttons — the dialog *is* the consent** |
| **MENU** | 1 | `More actions`; Android-only, iOS uses `ActionSheetIOS` |
| OUTCOME | 7 | single action, after the fact |

**A CONFIRM dialog may never be folded into BLOCKED or OUTCOME.** Those report; CONFIRM *is* the
authorisation, and it is the only gate before a delete, a cancel or a block.

The pattern is reusable; the content is not. Two dialogs share the title *"Currently reserved"* and two share
*"Sign in required"*, each pair with different bodies, and each is listed **separately** — merging would lose a
shipped string. Four bodies are server text and the design neither wraps nor rewords them.

**Two recovery claims on the first board were wrong and are corrected:** no failure path refetches
(`fetchData()` runs on mount, focus, Retry, pull-to-refresh and after a *successful* reservation only) — so a
race-lost dialog dismisses to a screen still offering what it just refused, recorded as **F-27**, PROPOSED; and
*Cancelled* navigates back via `router.back()`, it does not refetch.

---

## 4 · The seven settings surfaces — now drawn

Edit profile (with its 2–50 name, ≤200 bio and US-phone rules) · Phone verification (verified state, with the
enter/code states specified) · Your scene (chips, autosave, the rollback notice, the leave-while-saving
dialog) · Blocked users (load-failed, carrying *"This is not a record that you have blocked no one."*) · Terms
of service · Privacy policy · Checkout index (the entry route and its spinner, drawn so the route is not a
blank in the matrix).

**None is described-only any more.**

---

## 5 · System surfaces, and a correction

**Error boundary** — one action, no stack trace, no error code, and no "report this" promise the app cannot
keep. Marked PROPOSED: the shipped boundary's presentation is minimal.

**Listing status banner** — all twelve kinds across five tones; the word carries the meaning, tone supports it.

**Outbid notice — the reconciliation you asked for.** In Packages 1 and 3 I wrote that the app has no toast
anywhere. **That is right about a general system and wrong as an absolute, and both documents are corrected.**

| Question | Answer |
|---|---|
| Existing component, differently named pattern, or proposal? | **An existing component.** `src/components/listing/OutbidToast.tsx`, shipping, imported by exactly one screen (`ListingDetailScreen.tsx`) |
| Source behaviour | Driven by the screen's realtime INSERT callback — where the false-positive protection lives, which the component deliberately does not touch. Sits **below** the header, not over it. `pointerEvents="none"`, so it can never eat a tap on the bid button. Translates 12pt with the brand easing, no overshoot. Under reduce motion it appears and disappears with no translation. Announced once, because the status banner carries the same fact persistently |
| The accurate general statement | **There is no general toast or snackbar system** — no queue, no global API, no reusable `show()`. There is **one** screen-local animated notice. Everything else is a native `Alert` or an inline `Text accessibilityRole="alert"` |

---

## 6 · Implementation criteria

1. Bids keeps two segments and the shipped grouping and sort priority.
2. All ten row states render with their word and hint; urgency only inside 60 minutes.
3. A failed refresh stays inline and keeps the rows.
4. All eleven action branches resolve in the code's order; the two disabled states stay disabled.
5. **Red is reserved for the buying path** (Buy now / Pay now / Finish checkout / Place bid); the order-management primaries stay secondary. `pendingLabel="Reserving…"` is preserved, and no amount is added to the listing screen's `Place bid`.
6. All **23 call sites / 24 variants** keep their exact copy, trigger and recovery; both same-titled pairs stay separate; the three CONFIRM dialogs keep two buttons and are never reduced to a notice.
7. Server-text dialog bodies are passed through unwrapped.
8. The seven settings surfaces keep their shipped fields, limits and copy.
9. `OutbidToast` keeps `pointerEvents="none"`, its below-header position and its reduce-motion behaviour.
10. Verified at the largest text size, narrowest width, with a 66-character name and missing artwork.
11. `typecheck` · `lint` · `test` green; real screenshots beside the boards.
