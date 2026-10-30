# Home header + filter bar revision

**Session:** Front End · **Date:** 2026-09-04
**Status: OWNER-APPROVED on physical iPhone (2026-09-04) and checkpointed.** No push, no PR, no backend work.

## Branch
`frontend/home-header-scroll-revision`, in an **isolated worktree**
(`/Users/josetascon/snatchit-fe-home`).

## Base SHA
`085e2984cc89b1bf03cdf11c93f0ba182c3f17a4` — the owner-approved Phase 12 checkpoint.
**Not** branched from the pending Stripe work.

## Screenshot / current-state interpretation
The screenshot showed: SN mark top-left, `MIAMI` directly beneath it, search icon right, and a
horizontal category row (`ALL · YOUR SCENE · BUY NOW · AUCTION …`) below, over an empty feed
("NOTHING LIVE RIGHT NOW"). Inspecting the code confirmed the cause of the owner's scroll complaint:
the header **and** the chip row both lived inside the FlatList's `ListHeaderComponent`, so the filter
controls only came back if the user scrolled all the way to the very top.

## Previous header structure
`HomeHeader` was one flex row: a left `brand` column (SN mark stacked over the text "Miami", both
left-aligned) and the search `IconButton` pushed right by `justifyContent: 'space-between'`. The city
string was a hardcoded literal in the component.

## New header structure
```
                SN            <- line 1: mark, centred to the screen
MIAMI                Search   <- line 2: market label left, search right
```
Line 1 is a full-width, `alignItems: 'center'` row whose only child is the mark. Line 2 is the
`space-between` row carrying the market label and the search control.

## Exact logo centering implementation
The mark is the **sole child of its own full-width centred row**, so it is centred on the screen by
construction — there is no sibling in that row that could push it, which is exactly the failure mode an
absolute overlay would have been needed to defeat. No absolute positioning, no magic offsets, and
`paddingHorizontal` is symmetric, so the centre is the screen centre. Safe area is unchanged
(`paddingTop: insets.top + space.sm` on the header container).

## MIAMI / current-market architecture
New `src/lib/market/currentMarket.ts` exports `Market`, `MIAMI`, `CURRENT_MARKET` and
`useCurrentMarket()`. `HomeHeader` renders `{market.label}` through the **unchanged** `micro` token in
brand red — same size, same colour, same 4pt offset under the mark (the token uppercases, so it still
reads `MIAMI`). There is exactly **one** city label on Home; no literal "Miami" string remains in the
header or the feed screen (a test asserts this).

**Future hook point (documented only, not built):** when city switching becomes real, replace
`CURRENT_MARKET` with state (context/store hydrated from the user's choice or location) and let
`useCurrentMarket()` read it — the header and any other consumer need no change. No city-selection UI,
persistence, or backend was added.

## Filter/category collapse behaviour
The chip row moved **out of** `ListHeaderComponent` into a collapsible bar rendered between the header
and the feed. Its height animates between the measured natural height and `0` (`overflow: hidden`), so
the feed genuinely reclaims the space rather than leaving a phantom gap. When collapsed it is
`pointerEvents="none"` and `accessibilityElementsHidden` / `no-hide-descendants`, so nothing invisible
stays tappable or focusable. `ListHeaderComponent` now carries only the loading skeleton.

**Filter functionality preserved — nothing removed.** The chips are real one-tap filters:
`all`, `your_scene` (neighbourhood prefs), `ga`/`vip` (ticket type), `buy_now`/`auction`, `ended`,
`recently_sold` (separate datasets), plus the existing `Filters` chip that opens the advanced
`FilterSheet` (neighbourhoods, categories, price) and a conditional `Clear`. **Tradeoff considered and
declined:** collapsing the row to only a `FILTERS` entry would have removed one-tap access to eight
categories and hidden the active-filter state behind a sheet. The owner's stated problem was
persistence while scrolling, which the collapse solves without losing functionality. If the owner still
wants the row reduced to a single `FILTERS` action, that is a deliberate follow-up, not a silent change.

## Thresholds / hysteresis
Reuses the existing pure machine `src/lib/nav/dockMachine` (`reduceDockScroll`) with **its own
independent state instance** — same tested hysteresis, no second competing scroll system, and the
bottom dock's own state is untouched. Behaviour: expanded within `TOP_THRESHOLD` (24px) of the top;
collapse requires `COLLAPSE_TRAVEL` (40px) of sustained downward travel past `COLLAPSE_AFTER` (90px);
return requires `EXPAND_TRAVEL` (28px) of sustained upward travel — so the row comes back mid-feed
without scrolling to the top, and finger jitter or iOS bounce never toggles it.

## Reduced-motion behaviour
`useReducedMotion()` drives the timing: `duration: reduceMotion ? 0 : 180`. With Reduce Motion on, the
state change is instant (no translation/height animation) while the collapse/return still happens, so
comprehension is preserved. No animation library added — RN `Animated` only.

## Accessibility
- SN mark: **decorative** (`accessibilityElementsHidden` + `importantForAccessibility="no"`) — it is a
  brand mark with no interaction, and announcing it on every Home visit was noise.
- Market label: non-interactive, announced as `Current market: Miami`.
- Search: unchanged `IconButton` with `accessibilityLabel="Search events"` and button semantics.
- Chips: selected state unchanged; when the bar is collapsed the whole subtree is removed from the a11y
  tree and cannot be tapped. Touch targets unchanged (Chip keeps its `minHeight`/hitSlop from Phase 12).

## Safe-area behaviour
The header still pads by `insets.top`, so the centred mark clears the Dynamic Island; the market label
keeps its spacing beneath it; the search control stays in the top-right and reachable. Collapsing the
filter bar changes only that bar's height — the header and the centred mark never move, and the feed
gets `useDockClearance()` at the bottom as before.

## Empty-feed behaviour
With a short or empty feed there is no meaningful scroll, so `y` stays at/near 0 and the machine holds
`collapsed: false` — the bar stays visible, with no flicker, no broken collapsed state and no animation
loop. Negative overscroll (pull-to-refresh bounce) also resolves to expanded. Covered by a test.

## Files changed
- `src/components/discovery/HomeHeader.tsx` — centred mark, market label + search row, a11y.
- `app/(tabs)/home.tsx` — header/chips lifted out of the list; collapsible animated filter bar; composite
  scroll handler (dock + filter bar); `filterBar` style.
- `src/lib/market/currentMarket.ts` — new market abstraction.
- `tests/home-header.test.ts` — new.
- `docs/product-v2/HOME_HEADER_SCROLL_REVISION_REPORT.md` — this report.

## Tests
**609 passed / 26 files** (base 595 / 25 + 14 new). New tests cover: the market value and single label;
visible near top; collapse on sustained down-scroll; return on up-scroll **without** returning to the
top; fully visible at the top; jitter hysteresis; empty/short-feed stability incl. negative overscroll;
SN centred to the screen; exactly one city label from the abstraction; label size/treatment unchanged;
search preserved on Home and absent from primary nav; collapsed bar not focusable/tappable; reduced
motion honoured and no animation library; bottom dock still fed and its five-item order unchanged.

## Typecheck
`tsc --noEmit` clean (exit 0).

## Lint
`expo lint`: 27 problems, **0 errors, 27 warnings** — identical to baseline. No new warnings.

## iOS bundle
`platform=ios` on an isolated metro (port 8082, so the hotfix worktree's server was untouched):
**HTTP 200, ~14.6 MB**, contains the collapsing bar and the market module, no error banner.

## AdaptiveDock changed
**NO.** Geometry, vertical position, glass, width, capsule, icons, thresholds, safe-area spacing and
contraction behaviour are untouched; Home still feeds `useDockScroll('home')` exactly as before. The
filter bar uses a separate state instance of the shared pure machine.

## Backend changed
**NO.** No Supabase, schema, RPC, query, ranking, or filter-semantics change. No Core-owned file touched.

## Stripe hotfix touched
**NO.** The hotfix remains uncommitted and intact on `frontend/checkout-stripe-hotfix` in a separate
worktree (verified after this work: same modified/untracked set, latch still present). This revision was
branched from `085e298`, not from the hotfix, and shares no files with it.

## Physical-device status
Superseded by the owner-feedback revision below.

---

# Revision 2 — owner device feedback (2026-09-04)

The centred SN mark and the MIAMI direction were confirmed correct. Two problems remained, both
addressed here. Still **UNCOMMITTED**; a second device pass is required.

## Physical-device feedback
1. **Too many filters.** The quick row (`All · Your scene · Buy now · Auction · GA · VIP · Ended ·
   Sold · Filters · Clear`) read as a dense taxonomy and undercut the premium Home feel.
2. **Collapse behaviour broken.** Starting a downward collapse and reversing before it settled could
   leave the bar stuck or juddering; it did not recover naturally and felt non-native.

## Why the original row was too dense
Ten controls in a horizontally scrolling strip put a taxonomy above the content it filters. Most of
those options are refinements, not primary intents: the feed's default state already means "All", and
`Clear` only matters once something is set — both were permanent chrome for an empty-state case.

## New three-control architecture
The quick row is now exactly **`Your scene · Price · Filters`**, built from the existing `Chip`
primitive and V2 spacing (no new pill aesthetic), laid out as a static row rather than a scrolling strip.
- **Your scene** — unchanged behaviour: one tap toggles `chip = 'your_scene'` (tap again clears to the
  unfiltered feed). Same personalization query; nothing invented. Selected state via the existing Chip
  treatment.
- **Price** — opens the **existing** `FilterSheet`, which already owns the price min/max fields and the
  shared filter state. No second price implementation, no duplicated state, no fee math. It shows the
  existing selected treatment whenever a price bound is set (`hasPriceFilter`).
- **Filters** — opens the same sheet for the full set, and carries a count of what the sheet owns.

## How PRICE works
It reuses `FilterSheet` and the one `Filters` object; the sheet's price inputs and apply/clear semantics
are untouched. Price is deliberately **excluded** from the FILTERS count so an active price filter is
signalled once, by its own control, rather than being double-counted.

## How full FILTERS preserves every option
`FilterValues` gained `chip`, and the sheet now renders the whole taxonomy it used to lack, grouped:
**Sale type** (Buy now / Auction), **Ticket type** (GA / VIP), **Status** (Ended / Sold), alongside the
existing Category, Area and Price sections. Selecting the active option again returns to the unfiltered
feed — which is what `All` meant. The lazy-load for the Ended and Sold datasets moved with it, so those
still fetch on first selection. **No filter capability was removed and no query semantics changed.**

## Removal of visible ALL / CLEAR / etc.
`All` is gone: the default feed is "all". `Clear` is gone from the row and lives in the sheet, which
already had a Clear button (it now also resets `chip`). GA, VIP, Buy now, Auction, Ended and Sold are no
longer permanent chrome; they are one tap deeper, inside Filters.

## Exact scroll root cause
The previous implementation animated the bar's **layout height** (measured → 0) on a `View` sitting
above the `FlatList`, with `useNativeDriver: false`. Two consequences compounded:
1. **Layout feedback loop.** Shrinking the bar re-laid out the scroll container mid-gesture, which
   changed the list's viewport and produced further scroll events. Those events fed straight back into
   the same state machine that had just triggered the collapse — the animation was generating the input
   that drove it. A reversal part-way through therefore raced against offsets the animation itself had
   caused, which is what read as "stuck" and "does not recover".
2. **JS-thread animation.** `useNativeDriver: false` meant a layout pass every frame while the finger
   was down, so the list's content height was literally fighting the gesture.
A secondary factor: the controller was the **dock's** machine, tuned for an overlay whose collapse
changes no geometry, with no jitter deadband and a return threshold (28) close to the hide threshold (40).

## Old vs new implementation
| | Old | New |
| --- | --- | --- |
| Bar position | layout row above the list | absolute **overlay** on the feed |
| Motion | animated `height` → relayout | `translateY` + `opacity` |
| Driver | `useNativeDriver: false` (JS thread) | `useNativeDriver: true` (UI thread) |
| Feed layout during scroll | changes every frame | **constant** (fixed `paddingTop` = bar height) |
| Controller | shared `dockMachine` | purpose-built `filterBarMachine` |

The feed keeps a constant top inset equal to the bar, so the list's geometry never changes while
scrolling; the bar simply slides up under the header (clipped by the feed container's `overflow:
hidden`). There is no phantom gap: the inset is only ever visible at the top of the feed, exactly where
the bar is always shown.

## Interruption / reversal behaviour
Because motion is a transform on the native driver, a reversal just retargets the running animation from
its current value — `Animated.timing` interrupts cleanly, so there is no waiting for the previous
animation, no snap to the wrong endpoint, and no dead zone. Because the feed's layout no longer changes,
a reversal cannot produce feedback offsets. State and visuals cannot disagree: `hidden` is the only
input to the animation's target.

## Thresholds (tuned, documented)
`TOP_RESET 16` (always shown within 16px of top, and on negative overscroll) · `HIDE_AFTER 72` (must be
this far down before hiding is allowed) · `HIDE_TRAVEL 48` sustained downward px to hide ·
`SHOW_TRAVEL 20` sustained upward px to show · `JITTER 2` (smaller deltas are ignored entirely and never
accumulate). Returning costs **less than half** the travel of hiding, so controls come back quickly.
On any direction change the **opposing accumulator is reset immediately**, so stale downward travel can
never force a longer reverse scroll — the specific failure the owner reported.

## Tests for partial-scroll reversal
`tests/home-header.test.ts` (24) drives the real controller: shown near top; sustained down hides;
up shows mid-feed; **partial down then reverse up** (never sticks, downward accumulator dropped, and a
later genuine down-scroll still hides — proving no corruption); collapsed + small up stays hidden;
collapsed + intentional up returns; **rapid down/up/down/up** ends valid with clean accumulators; top
reset; negative overscroll; empty/short-feed stability; jitter deadband; show-cheaper-than-hide. Plus
guards: exactly three quick controls (`Your scene`, `Price`, `Filters`), `All`/`Clear`/`GA`/`VIP`/`Buy
now`/`Auction` absent from Home but present in the sheet, hidden bar not tappable/focusable, transform
overlay (no animated height, no `useNativeDriver: false`), own controller (no `reduceDockScroll`), SN
centred, one market label, search preserved, reduced motion, and the dock unchanged.

## Accessibility
Each quick control is a `Chip` (button semantics + selected state): Your scene when personalized, Price
when a bound is set, Filters when the sheet owns something. While hidden the overlay is
`pointerEvents="none"` with `accessibilityElementsHidden` / `no-hide-descendants`, so VoiceOver skips it
and it cannot be tapped invisibly.

## Reduced motion
`duration: reduceMotion ? 0 : 200` — the transition becomes immediate while the state machine and every
threshold stay identical, so Reduce Motion cannot take a different code path.

## Verification (revision 2)
Tests **619 passed / 26 files**; `tsc --noEmit` clean; `expo lint` 27 problems / **0 errors / 27
warnings** (no new — the now-unused `ScrollView` import and `clearAllFilters` were removed); iOS bundle
**HTTP 200, ~14.6 MB** on the isolated metro (port 8082), containing the new controller and quick row.

## AdaptiveDock changed
**NO.** Untouched, and it keeps its own independent state — Home still calls `useDockScroll('home')`
and forwards the raw event. The top bar deliberately uses a separate controller rather than bending the
dock's machine to a different UI pattern.

## Stripe hotfix untouched
**NO files touched.** Verified before and after: `frontend/checkout-stripe-hotfix` still has its
uncommitted set intact (latch present in `CheckoutNative.tsx`). This branch changes **zero** checkout
files.

## Backend changed
**NO.** No query, ranking, or filter semantics changed; no Core-owned file touched.

## PRICE opens directly on the price section (final owner request)
`FilterSheet` gained an optional `focus?: 'price'`. Home's PRICE control sets it and opens the SAME
sheet with the SAME state; the sheet measures the Price label's offset and scrolls to it on open.
FILTERS opens the same sheet unfocused. There is still exactly one `FilterSheet` instance and one
filter model — no second price implementation, no duplicated state, no fee math.

## Physical iPhone verified: YES — Owner approval: APPROVED — Status: APPROVED
Verified on device: centred SN, MIAMI market label, Your scene / Price / Filters, full filters behind
FILTERS, smooth collapse on scroll down, smooth return on scroll up, partial-down-then-reverse fixed,
no stuck state, no phantom gap, AdaptiveDock unchanged. Final verification at checkpoint: 620 tests /
26 files, tsc clean, lint 27 problems / 0 errors / 27 warnings (no new), iOS bundle HTTP 200.

## Original device-review checklist (now satisfied)
Owner should check on device: the three-control row reads sparse and premium; Your scene / Price /
Filters each show their active state; the row leaves on a clear downward browse and returns quickly on
an upward flick **without** reaching the top; **start a collapse then reverse mid-way — it should follow
the finger and never stick**; rapid direction changes stay stable; no gap or jump under the header; the
empty feed keeps the row visible; Reduce Motion behaves.
