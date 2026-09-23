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

**Red marks money, not navigation.** Buy now, Pay now, Finish checkout and Place bid commit or move money and
stay red. **Send tickets, View transfer, Review transfer and View dispute only open another screen**, so they
are drawn secondary. Spending the money colour on a link is how red stops meaning anything.

Two disabled states are real and stay disabled: **"Your listing"** (a seller gets no bid and no Buy Now — the
database refuses both) and **Sold / Cancelled / On hold / Ended**.

**"Place bid" opens `/bid/{id}`; it does not submit.** The submission control lives on the bid screen and
carries the all-in total — already implemented on C's branch.

**All twelve `StatusKind`s** are rendered with their shipped label, detail and tone.

---

## 3 · Listing detail — all 17 distinct dialogs

`pkg6-listing-dialogs.png` groups them into **three reusable patterns** — BLOCKED, RACE LOST, OUTCOME — and
**every dialog keeps its own exact copy, trigger and recovery path, all three mapped by name.**

The pattern is reusable; the content is not. Two dialogs share the title *"Currently reserved"* with different
bodies and are listed **separately**, because merging them would lose one of the two shipped strings. Four
bodies are server text and the design neither wraps nor rewords them.

**Recovery is the part that matters:** a BLOCKED dialog returns you unchanged; a RACE LOST dialog refetches so
the screen stops offering what it cannot deliver; an OUTCOME dialog either navigates away or refetches.

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
5. **Red is reserved for the four money actions**; the four navigational primaries are secondary.
6. All 17 dialogs keep their exact copy, trigger and recovery; the two same-titled ones stay separate.
7. Server-text dialog bodies are passed through unwrapped.
8. The seven settings surfaces keep their shipped fields, limits and copy.
9. `OutbidToast` keeps `pointerEvents="none"`, its below-header position and its reduce-motion behaviour.
10. Verified at the largest text size, narrowest width, with a 66-character name and missing artwork.
11. `typecheck` · `lint` · `test` green; real screenshots beside the boards.
