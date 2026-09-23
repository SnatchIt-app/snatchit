# V3 freeze reconciliation — the dialog count, and what red means

**B · 2026-09-22.** Two reconciliations required before the design package is frozen as the
implementation reference. Both are answered against **release source
`5b255838dea3d39561714554a547a6121ab2c8ff`** (`release/production-gate-20260918`), read in this session.

---

## 1 · The dialog count: 23 → 17 was not a consolidation. It was six omissions.

### 1.1 · Where each number came from

| Number | Where I first wrote it | What it actually counted |
|---|---|---|
| **23** | `V3_COVERAGE_MATRIX.md` line 120 and `V3_PACKAGE_2` line 123 | `Alert.alert` **call sites** in `src/screens/ListingDetailScreen.tsx`. Verified again now: `grep -c 'Alert.alert'` = **23** at `5b255838` |
| **17** | `V3_PACKAGE_6` §3 and `pkg6-listing-dialogs.png` | The number of cards I actually drew |

**I presented 17 as the complete distinct set. It was not.** The board silently narrowed to
*single-action alerts* and the count followed the board instead of the source. The right answer is that the
file has **23 call sites** which render **24 distinct copy variants** — one call site (`L871`) renders one of
two bodies depending on `bid_count`.

**No dialog was lost to pattern consolidation.** The three patterns (BLOCKED / RACE LOST / OUTCOME) each kept
every member. The six that vanished were never placed in a pattern at all.

### 1.2 · Complete map — all 23 call sites, with disposition

Source lines are `ListingDetailScreen.tsx` @ `5b255838`.

| # | Line | Title | In the 17? | Disposition |
|---|---|---|---|---|
| 1 | 761 | Sign in required — *"Please log in to buy tickets."* | ✅ | BLOCKED, unchanged |
| 2 | 763 | Not allowed | ✅ | BLOCKED, unchanged |
| 3 | 766 | Buy Now unavailable | ✅ | BLOCKED, unchanged |
| 4 | 768 | Not available | ✅ | RACE LOST, **recovery corrected** (see 1.4) |
| 5 | 770 | Currently reserved — *"…a few minutes."* | ✅ | RACE LOST, **recovery corrected** |
| 6 | 781 | Currently reserved — *"…soon."* | ✅ | RACE LOST, kept separate, **recovery corrected** |
| 7 | 782 | Already sold | ✅ | RACE LOST, **recovery corrected** |
| 8 | 783 | Reservation failed — `{server reason}` | ✅ | OUTCOME, unchanged |
| 9 | 813 | Cannot edit | ✅ | BLOCKED, unchanged |
| 10 | **824** | **Cannot delete** — *"…activity already exists. Cancel it instead."* | ❌ | **RESTORED.** Straight omission — it is a single-action alert and fitted the pattern I had already built. It is also the only blocked dialog that names the route out (*Cancel*) |
| 11 | **830** | **Delete listing?** — `Delete "{event}" permanently? This cannot be undone.` | ❌ | **RESTORED** as new pattern **CONFIRM**. Two buttons, destructive. Out of the board's implicit single-action scope |
| 12 | 845 | Delete failed — `{server reason}` | ✅ | OUTCOME, unchanged |
| 13 | 852 | Deleted | ✅ | OUTCOME, unchanged |
| 14 | 864 | Cannot cancel | ✅ | BLOCKED, unchanged |
| 15 | 868 | Already cancelled | ✅ | RACE LOST, **recovery corrected** |
| 16 | **871a** | **Cancel listing?** — *"…will void all bids. Continue?"* (`bid_count > 0`) | ❌ | **RESTORED** as CONFIRM |
| 17 | **871b** | **Cancel listing?** — *"Cancel this listing? Buyers will no longer see it."* (`bid_count = 0`) | ❌ | **RESTORED.** Same call site, second body — this is the 24th variant |
| 18 | 887 | Cancel failed — `{server reason}` | ✅ | OUTCOME, unchanged |
| 19 | 890 | Cancelled | ✅ | OUTCOME, **recovery corrected** — it is `router.back()`, not a refetch |
| 20 | **951** | **More actions** | ❌ | **RESTORED** as new pattern **MENU**. Android-only; iOS renders the same entries through `ActionSheetIOS`, which is not an `Alert` |
| 21 | 968 | Sign in required — *"You need to be signed in to block users."* | ✅ | BLOCKED, kept separate from #1 |
| 22 | **976** | **Block {seller name}?** | ❌ | **RESTORED** as CONFIRM |
| 23 | 991 | Could not block — `{server reason}` | ✅ | OUTCOME, unchanged |
| 24 | **994** | **Blocked** — *"{name} is hidden from your feed. Unblock anytime in Settings."* | ❌ | **RESTORED.** Straight omission, like #10 — a single-action alert that simply was not drawn |

**Totals: 23 call sites · 24 copy variants · 24 cards drawn.** Six restored, two of which (#10, #24) were plain
omissions and four of which (#11, #16/17, #20, #22) fell outside a scope I had narrowed without saying so.

### 1.3 · The corrected artifact

`pkg6-listing-dialogs.png` is re-rendered with **five** patterns. Every card carries its **source line**, so the
map above is checkable against the file rather than against my summary.

| Pattern | Members | Shape |
|---|---|---|
| BLOCKED | 7 | single action; returns you unchanged |
| RACE LOST | 5 | single action; the screen is out of date |
| **CONFIRM** | 4 variants / 3 call sites | **two buttons — the dialog *is* the consent** |
| **MENU** | 1 | one control, two menus, and a platform split |
| OUTCOME | 7 | single action, after the fact |

**A CONFIRM dialog may never be folded into BLOCKED or OUTCOME.** In BLOCKED and OUTCOME the dialog reports;
in CONFIRM the dialog *is* the authorisation, and it is the only gate before a delete, a cancel or a block.

### 1.4 · Two behaviour claims on the old board were wrong, and are corrected

Found while doing this mapping, both verified in source:

- **"OK → the screen refetches"** on every RACE LOST dialog. **False.** `fetchData()` is called on mount
  (L420), on focus (L426), on Retry (L1055), on pull-to-refresh (L1235) and after a **successful** reservation
  (L786). **No failure path calls it.** Every race-lost dialog dismisses to a screen still showing the stale
  state that produced it, still offering the action it just refused. Recorded as **F-27**, drawn as
  **PROPOSED**, not as existing behaviour.
- **"Cancelled → refetch; status becomes Listing cancelled"**. **False.** L890 is
  `[{ text: 'OK', onPress: () => router.back() }]` — it navigates back, exactly like *Deleted* (L852).

### 1.5 · A third finding this mapping exposed

**F-25 — two screens, two divergent copies of the same three destructive dialogs.** `my-listings.tsx` (5
alerts) and `ListingDetailScreen.tsx` (23) both delete and cancel listings, with different strings:

| | `my-listings.tsx` | `ListingDetailScreen.tsx` |
|---|---|---|
| Cannot delete | *"This listing has bids and cannot be deleted."* | *"This listing can't be deleted because activity already exists. Cancel it instead."* |
| Delete title/body | `Delete listing` · *"Are you sure you want to delete "X"? This cannot be undone."* | `Delete listing?` · *"Delete "X" permanently? This cannot be undone."* |
| Cancel title | `Cancel listing` | `Cancel listing?` |
| Safe button | `Keep listing` | `Keep Listing` |
| Structure | **one control** branches: bids + active → offer Cancel, else → offer Delete | **two separate menu entries**, each with its own guard |

`V3_PACKAGE_3` drew the `my-listings` set accurately; it is **not** the listing-detail set. Both are now drawn,
separately. **This is a finding for C to rule on, not something the redesign silently unifies** — unifying the
copy is a behaviour change, and the structural difference (one branching control vs two guarded entries) is a
product decision.

---

## 2 · Action colour vs actual behaviour

### 2.1 · What I wrote, and why it was wrong

> *"Red marks money, not navigation. Buy now, Pay now, Finish checkout and Place bid **commit or move
> money** and stay red."* — `V3_PACKAGE_6` §2, and the caption on the action-matrix board.

**That sentence is false for all four actions, and it contradicted a finding printed two paragraphs below it in
the same document** (*"'Place bid' opens `/bid/{id}`; it does not submit"*). Traced through `runAction`
(L1161-1185):

| Primary | What the tap actually does | Charges? |
|---|---|---|
| `place_bid` | `router.push('/bid/{id}')` | **Pure navigation** |
| `pay_now` | `navigateToWinnerCheckout()` → `router.push('/checkout/[id]')` | **Pure navigation** |
| `continue_reservation` ("Finish checkout") | `handleBuyNow()`; with a hold already held it short-circuits to `navigateToCheckout()` | **Pure navigation** |
| `buy_now` | `reserve_buy_now` RPC — **a real server side-effect that blocks other buyers** — then `router.push('/checkout/[id]')` | **Takes a reservation. Does not charge** |

**Not one of the four moves money.** Three navigate; one takes a hold and then navigates.

### 2.2 · The corrected rule — the approved hierarchy is unchanged

> **Red marks the buying path: the single action that advances *this viewer* toward paying.
> It is not a claim that money moves when you tap it.**

Nothing moves on the board. The same four actions stay red, for the reason the hierarchy was approved —
one primary per screen, and on a live listing the primary is the way to buy. What changes is the **stated
meaning**, which now matches the code.

The secondary treatment of *Send tickets · View transfer · Review transfer · View dispute* also keeps its
place, on a **truer axis**: those manage an order that **already exists**. That is a different job, not a
weaker one. Red is reserved for the buying path so that it still means something when it appears.

### 2.3 · Labels and confirmations carry the consequence — colour never does

Three commit points, each named by its own control, all already in the source:

| Where | Control | What it commits |
|---|---|---|
| Listing detail | **`Buy now · {all-in}`**, and in flight the shipped `pendingLabel` reads **"Reserving…"** | A **reservation**. The label names the hold, not a purchase — this is shipped behaviour and **must be preserved** |
| `/bid/{id}` | **`Place bid · $104.50 all-in`** | The **bid**. Already implemented on C's branch |
| `/checkout/{id}` | **`Pay $99.00`** (`payControl` `paymentReady`) | The **charge**. The only control in the app that moves the buyer's money |

**`detailState.ts` L312 already labels the listing-screen action plainly `'Place bid'`, with no amount.** The
ambiguous `Place bid · $104.50` the owner flagged came from **my mockup**, not from the release source; the
shipped label was never ambiguous. The amount belongs on the bid screen's submit control, where it is what
gets submitted. `buy_now` keeps its amount (`Buy now · {all-in}`, L318) because Buy Now has one fixed price.

### 2.4 · What C must not do when restyling

1. Do not drop `pendingLabel="Reserving…"`. It is the only place the buyer is told a hold was taken.
2. Do not add an amount to the listing screen's `Place bid`.
3. Do not promote a navigational primary to red to "balance" a screen.
4. Do not rely on colour for consequence anywhere: every destructive action keeps its **CONFIRM dialog**, and
   `status.error` stays outline-only, never a filled block.

---

## 3 · Status of this reconciliation

**Both items are design corrections made against the source and are ready for implementation.** Neither
changes payment, reservation, refund, payout, transfer, security or ownership rules; both make the design
describe the existing rules accurately instead of inaccurately.

**Nothing here is device-verified.** F-25 and F-27 are findings for C to validate and rule on, not fixes.
