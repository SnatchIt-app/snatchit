# C → B: committed candidate — capture `6d86f437`

**PIN MOVED (second move, 2026-09-24 ~14:5x):** `25b7e1f6` → **`6d86f437`**. Clean detached-worktree
run at the pin: **2779 passed / 2779, exit 0, dirty_files=0** (C scratchpad full-run-15). What it adds:
the dispute-outcome gated read + A's payout-wording rulings (A signed off through b220ec20, then
c19c91eb's sellState display faces); Search + Create to the boards; Tickets to the boards; the V3
Chip (sentence case, primary-ink selected fill); orderPresentation.ts (pure). NEW HARNESS ROUTES for
your review: `/_dev/v3-search-create?screen=search|create&variant=…` and
`/_dev/v3-tickets?screen=tickets&variant=populated|past|empty|error|offline`.
KNOWN WEB ARTIFACT: the focused search field draws the browser focus outline; native draws none.
STILL OUT: the order screen's board work sits frozen in an uncommitted transfer-file diff awaiting
A's classification of its select widening — do not review the Order row against this pin yet.

**PIN MOVED, explicitly (2026-09-24, ~14:2x):** `ba69650c` → **`25b7e1f6`**, one commit ahead.
It carries F-V3-READFAIL-1 (D's finding, verified then fixed): the listing screen's failed-read
view — "Nothing was sent from this screen" — was reachable AFTER a successful reservation via a
non-silent post-write refetch; the refresh is now silent, so the sentence is true wherever it can
render. Verified at the new pin: tsc exit 0 · full vitest **2729 passed / exit 0** (full-run-9).
Nothing visual changes on your captured screens; no capture needs retaking for this one.

---

| | |
|---|---|
| **Candidate** | `ba69650c` on `v3/midnight-app` (worktree `/Users/josetascon/snatchit-refund`; same repo family as this one, so the commit is visible to your worktree without a fetch) |
| **Supersedes** | your `262c908b` review — every finding in it is addressed below or explicitly deferred with a reason |
| **Checks at the candidate** | `tsc --noEmit` exit 0 · full vitest 152 files / 2728 passed / exit 0, complete output preserved (C session scratchpad `full-run-7.txt`) |
| **Workflow split** | your `:8083` harness is THE authenticated capture workflow — point it at `ba69650c`. C's `:8081` serves C's dev loop and the `app/_dev/` fixture routes for states a signed-in session cannot reach. Neither starts the other's Metro |
| **Your two harness-only modifications** | both are now IN the candidate, committed (`b59ddd26`): the `Appearance.setColorScheme` feature-detect and the web `fontFamily()` returning `FAMILY[role]`, plus `app/+html.tsx` declaring the five faces from the bundled .ttfs. Your README's serif-fallback limitation is stale against this candidate; drop your local patches when you move the pin or they will conflict |

## Your findings → what the candidate does

- **Avatar (your measured 56×1176 sliver — the decisive finding, thank you):** `transformUrl` now
  emits **`height`**, and the dock requests the **square box it paints** (42pt sides → `?width=84&height=84&resize=cover`).
  Also: the derivative fell back on error to the untransformed object URL, failures latch per-URL
  in a set, the latch resets on foreground, and every SIGNED_OUT clears the published path.
  **Note your sliver case never fired onError — that is exactly why the box, not the fallback, is
  the fix for it.**
- **H1 header:** SN mark left on the 20pt gutter, search right, one row. (Web-only fix included:
  RNW ignores `aspectRatio` on an Image with one fixed dimension — explicit width now.)
- **H2 chips:** chrome radius.
- **H3/H4 plate:** the fallback plate carries the **SN monogram** filling the slot treatment.
- **Bid entry / Listing / money:** rebuilt to `pkg8-bid-*` and `pkg8-listing-*`; displayed money
  is 2dp via display-only V3 formatters (integer-cent math untouched; A reviewed).

## What the owner wants verified VISIBLY on your authenticated harness

1. **Avatar, before/after:** read the dock element's `naturalWidth/naturalHeight` — must be
   **84 × 84** (was 56 × 1176). "An image appears" is not the test, as you said.
2. **Portrait AND square source photos:** both must land centre-cropped square, matching the
   Profile ring's crop.
3. **Photo update:** repoint the row (timestamped path) → both surfaces change together, no stale
   cache (keys are the full URLs).
4. **Account switch:** sign out / different account → no residue (owner guard + the new
   SIGNED_OUT clear).
   ⚠️ Constraint: verify with READS and the existing DV session per the owner's authorization —
   if a step needs an avatar UPLOAD or a second account's credentials, say so rather than doing
   it; fixture mutations stay paused.

## Deliberate deviations from the boards — need a ruling, not a fix

1. **Listing footer emphasis:** the board draws BID filled / Buy-Now outlined; `detailState`
   rule 1 (owner-reaffirmed 2026-09-22) says Buy Now leads. Painted as the board draws;
   resolver untouched; one `variant` line to revert.
2. **Buy-now sub-line** keeps `all-in, ends the auction` (board: `ends the auction`) — dropping
   "all-in" from a price is a truthfulness regression.
3. **Bid screen payment sentence** keeps the owner's 2026-09-23 ratified copy over the board's
   sample sentence (same meaning).
4. **Home filter strip** remains (boards draw none): removing it deletes the Recently sold /
   Ended datasets and the F-HOME-1 load-state machinery — product surface, not layout.
5. **Listing hero** keeps the From-a-fan badge and the overflow control (moderation / App Store
   1.2); the seller row shows no invented sales count.
6. **Row thumb radius is B's drawn 8** — the boards measure 8; the new scale's `md` mapping was
   C's brief error, corrected.

## Remaining inventory (C, in progress — subagents on disjoint groups)

Search, Sell/Create, My listings, Bids board, Tickets, Orders, both transfer roles, Profile,
Settings, Auth, dialogs, loading/empty/error — both appearances. Checkout renders **signed out
or fixture-only**: on this head, `decideCheckoutSetup` step 3 creates/reuses a real PaymentIntent
for auction mode on mount (verified with D; A concurred).

*Evidence class: everything above is source + web-render evidence. Native acceptance stays open,
as your status doc already records.*
