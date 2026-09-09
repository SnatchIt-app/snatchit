# Phase 9 — Global adaptive navigation

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase9-adaptive-navigation` (from the Phase 8 checkpoint).
Not committed — awaiting physical-device review. No push, no PR, no Core-owned file touched.

## 1. Phase 8 checkpoint SHA

`c50eaf943e95f789aae9b398141012bb7d06121a` — `feat(frontend-v2): redesign account settings`.
Verified at checkpoint: 523 tests / 20 files, tsc clean, 28 lint warnings / 0 errors.

## 2. Branch / base

`frontend/v2-phase9-adaptive-navigation`, branched from `c50eaf9`. No rebase, no force-push.

## 3. Old navigation architecture

`app/(tabs)/_layout.tsx` used expo-router `Tabs` with the DEFAULT full-width bottom bar attached to the
screen edge: four tabs (home/create/bids/profile) with `HapticTab` buttons and SF-Symbol icons
(`IconSymbol`), a dark `tabBarStyle`, `accent` active tint, and the legacy `index`/`explore` routes
hidden. The bar defined the app's bottom-edge visual identity.

## 4. New architecture

Same expo-router `Tabs` and the same four routes — routing, lazy mounting, route names and therefore
analytics/deep-links are unchanged — but the default bar is replaced via the `tabBar` render prop with
the Snatch It **AdaptiveDock**, a floating, compact, black, sharp, icon-only dock. A `NavDockProvider`
wraps the navigator and holds the Home-only collapse state; the collapse decision is a pure, tested
state machine. New modules:

```
src/lib/nav/navItems.ts        destinations config (4 now; 5-item Tickets-ready)
src/lib/nav/dockMachine.ts     pure scroll-direction collapse machine
src/lib/nav/navInsets.ts       dock geometry + shared content clearance
src/components/nav/dockContext.tsx   collapse state + Home scroll handler
src/components/nav/AdaptiveDock.tsx  the floating dock (custom tabBar)
```

## 5. Files changed

```
M  app/(tabs)/_layout.tsx              default bar → NavDockProvider + AdaptiveDock tabBar
M  app/(tabs)/home.tsx                 +13: onScroll → machine, expand-on-focus, dock clearance
M  app/(tabs)/bids.tsx                 +3: bottom dock clearance
M  app/(tabs)/profile.tsx              +3: bottom dock clearance
M  src/screens/CreateListingScreen.tsx +3: StickyBar sits above the dock
M  components/ui/icon-symbol.tsx       +2: reserved ticket.fill → confirmation-number mapping
A  src/lib/nav/*  src/components/nav/*  tests/adaptive-nav.test.ts
A  docs/product-v2/PHASE_9_ADAPTIVE_NAVIGATION_REPORT.md
```

Approved screens are untouched beyond this nav integration (scroll hook + bottom clearance); no content,
card, price, search, logo or data change.

## 6. Route matrix

| Route | Dock |
| --- | --- |
| `(tabs)/home` | Full dock, **collapses** on scroll-down |
| `(tabs)/create` | Full dock (stable); StickyBar CTA sits above it |
| `(tabs)/bids` | Full dock (stable) |
| `(tabs)/profile` | Full dock (stable) |
| `(tabs)/index`, `(tabs)/explore` | Hidden (href:null), unchanged |
| Stack routes (Listing Detail, Checkout, Place Bid, Settings, Transfer, My Listings, Edit, Auth) | **No dock** — they live outside the `(tabs)` navigator, so the tab bar never renders there (existing behaviour preserved) |

## 7. Dock layout

A centred floating row (`DOCK_HEIGHT` 56) with `DOCK_SIDE_MARGIN` 16 horizontal insets, floating
`DOCK_GAP` 12 above the safe-area inset. Elevated black surface (`surface.elevated` #111) on the #000
canvas, a red-tinted hairline border, **radius 0** (sharp stays on-brand; the elevated surface + border +
float separate it from the canvas — no soft pill). Four 64pt icon cells. Icon-only — no visible labels —
with full `accessibilityLabel`s.

## 8. Active-state treatment

Active = white icon (`text.primary`) + a 2pt red marker bar above it; inactive = muted icon
(`text.muted`). Selection is never colour-only: the marker's presence plus the white/muted contrast plus
`accessibilityState.selected` all carry it. No giant red fill, no glow, no neon, no heavy shadow.

## 9. Home collapse state machine

`src/lib/nav/dockMachine.ts` — pure. It folds each scroll offset into `{ y, collapsed, downAcc, upAcc }`,
accumulating sustained travel in the current direction: enough downward travel collapses, enough upward
travel expands, and a direction reversal resets the opposite accumulator. The dock reads `collapsed` and
cross-fades. The component only touches React state on an actual transition (accumulators live in a ref),
so a 60fps scroll does not re-render per event.

## 10. Collapse threshold

`COLLAPSE_AFTER` = 90pt (must be scrolled at least this far before a collapse is allowed),
`COLLAPSE_TRAVEL` = 40pt sustained-down to collapse, `EXPAND_TRAVEL` = 28pt sustained-up to expand,
`TOP_THRESHOLD` = 24pt (within this of the top → always expanded). These are the initial values; the
brief's ~70–100pt window is honored and they are the first candidates for on-device tuning.

## 11. Direction / hysteresis handling

Direction is the sign of the per-event delta; the two independent travel accumulators mean small jitter
(a few px back-and-forth) never crosses a threshold, so the dock does not flicker. Collapse and expand
use different travel distances (40 vs 28) — real hysteresis. Negative offsets (iOS bounce at the top)
resolve to "near top → expanded" and never collapse. Tests cover down-collapse, up-expand, near-top
restore, jitter-stability, and the overscroll case.

## 12. Animation

RN `Animated` (consistent with the app's existing press animations), a single value 0→1 cross-fading the
full dock (opacity 1→0, translateY 0→56) and the compact control (opacity 0→1, scale 0.9→1), native
driver, duration `motion.settle` (280ms — within the fast/mechanical intent; tunable toward 180–240 on
device). No spring, no bounce, no rotation, no rubber-band.

## 13. Reduced-motion behavior

`AccessibilityInfo.isReduceMotionEnabled()` (plus a change listener) sets the timing duration to **0** —
an instant state swap — when reduce-motion is on. No sequence, no motion.

## 14. Safe-area handling

The dock wrapper pads `insets.bottom + DOCK_GAP` from `useSafeAreaInsets()`, so it floats above the Home
indicator on any device — no hardcoded inset. The compact control shares the same bottom anchor.

## 15. Content inset handling

`src/lib/nav/navInsets.ts` exports `DOCK_CLEARANCE` and a `useDockClearance()` hook
(`insets.bottom + DOCK_CLEARANCE + DOCK_GAP`). Home, Bids and Profile apply it as their list/scroll
`paddingBottom`; Create's StickyBar adds `insets.bottom + DOCK_CLEARANCE` so its CTA sits above the dock.
One shared value, not per-screen magic numbers.

## 16. Keyboard behavior

Create is the only tab with a text-entry form. Its `KeyboardAvoidingView` lifts the StickyBar CTA above
the keyboard when typing; the floating dock (absolute, in the tab navigator, outside Create's
KeyboardAvoidingView) stays at the bottom behind the keyboard — so the focused field and the CTA are
never covered. At rest the CTA sits above the dock via the clearance. This is a primary on-device check.

## 17. Nested-route behavior

Unchanged and correct by construction: every transactional/utility screen (Listing Detail, Checkout,
Place Bid, Settings, Transfer, My Listings, Edit Listing, Auth) is a route OUTSIDE `app/(tabs)`, reached
by `router.push`, so the `(tabs)` tab bar simply does not render there — they keep their own full-screen
chrome. No global "force dock everywhere", and no screen had to opt out.

## 18. Search decision

Search stays inside Home/discovery (the `HomeHeader` search entry → `/(tabs)/explore`). It is **not** a
primary destination; a test asserts `navItems()` never contains a search key or label.

## 19. Tickets architectural slot

`navItems({ tickets: true })` returns `[home, create, bids, tickets, profile]` — the approved five-item
order — with **no layout change** (the dock maps whatever the config returns). The `ticket.fill` icon is
reserved (mapped to Material `confirmation-number`, an ownership glyph, never a scanner/QR). But
`navItems()` (no arg) omits Tickets, no `tickets` tab route is registered, and there is no disabled icon,
"coming soon", or route to purchases/transfers. Tests pin both the four-item default and the five-item
readiness.

## 20. Ticket contract current status

**Still blocked.** No change in the Core handoff: `kernel.tickets` has no app-accessible authenticated
SELECT; 093 remains undeployed; native venue flags remain off. This session did not query
`kernel.tickets`.

## 21. Accessibility

Each destination is `accessibilityRole="tab"` with an `accessibilityLabel` and
`accessibilityState.selected`; targets are 64×56 (≥44pt) with hitSlop. The compact Home control is a
button labelled "Home. Navigation hidden. Double tap to show navigation." Selection is not colour-only
(marker + contrast + state). Reduced motion is honored.

## 22. Performance strategy

Scroll is handled on the JS thread at `scrollEventThrottle={16}`, but the reducer only calls `setState`
on a real collapse/expand transition (accumulators in a ref), so steady scrolling causes no re-renders —
transitions are rare. The animation uses the native driver (transform/opacity). No per-event React state
churn, no heavy bridge work, no premature Reanimated-worklet complexity.

## 23. Tests added

18 tests in `tests/adaptive-nav.test.ts`. Suite total **541 / 21 files** (was 523 / 20). No existing
test weakened.

## 24. Exact tests

Machine: starts expanded; collapses after sustained down past the floor; does not collapse before the
floor; expands on sustained up; always expands near top; no flip on jitter; never collapses on negative
overscroll; hysteresis thresholds positive; compact-tap expands. Config: four-item default in order; the
five-item Tickets-between-Bids-and-Profile model; Search never present; Tickets icon is ownership not
scanning; only Home collapses. Source guards: layout keeps the four routes + replaces only the tab bar
and registers no `tickets` route; the dock renders `navItems()` with no "coming soon"/`kernel.tickets`;
collapse is Home-only via the pure machine (no inline `y > 80`); Home wiring is scroll + clearance only
with discovery untouched.

## 25. Typecheck

`tsc --noEmit` clean.

## 26. Lint

`expo lint`: 28 problems, **0 errors, 28 warnings** — equal to baseline, **no new warnings**.

## 27. Native iOS bundle

`platform=ios` metro bundle builds **HTTP 200**, 14.6 MB, no real errors (only a Reanimated worklet log
string matches a naive grep). `AdaptiveDock`, `NavDockProvider`, `reduceDockScroll`, `isCollapsingRoute`
and `DOCK_CLEARANCE` are present; no `name="tickets"` route exists in the bundle.

## 28. Physical-device verification

**Not performed by this session — and this phase specifically needs it.** The local simulator remains
blocked (SDK 26.5 present, only a 26.2 runtime → 0 eligible destinations); no simulator claim is made.
Prepared for one device pass: Home (full dock at top → scroll down collapses → content unobstructed →
scroll up expands → near top expands → tap compact control expands → pull-to-refresh not disturbed →
rapid direction changes → long scroll), Create (dock stable, keyboard, bottom fields/CTA not covered),
Bids + Profile (dock stable, last cards not covered, Settings nav works), and the nested screens (Listing
Detail, Place Bid, Checkout, Settings, My Listings, Transfer) show no dock.

## 29. Issues requiring owner tuning

- **Collapse thresholds** (`COLLAPSE_AFTER`/`COLLAPSE_TRAVEL`/`EXPAND_TRAVEL`) — feel is best judged on
  device; current values are conservative.
- **Animation duration** — 280ms now; may want 180–240ms after seeing it on hardware.
- **Icon-only vs compact labels** — the dock is icon-only per the approved "mostly iconographic"
  direction; if any destination reads ambiguously on device, compact labels can be added (the layout
  already reserves vertical room).
- **Dock radius** — currently 0 (sharpest, on-brand); a hair of radius is a one-line change if the float
  needs more visual separation.

## 30. Whether Tickets product work can begin

**No.** Tickets stays blocked on the Core contract. The navigation is now ready to host it the moment Core
ships: (1) an owner-scoped authenticated read of `kernel.tickets` reachable from the client; (2) a
documented event-first ticket row shape (event ref, type, quantity, ownership/fulfillment state,
upcoming-vs-past); (3) a stable status/error vocabulary. When those exist, a Phase 10 Tickets batch flips
`navItems({ tickets: true })`, registers the `tickets` tab route, and builds the surface — no navigation
redesign required.

---

## OWNER DEVICE REVISION (2026-09-03)

Jose reviewed the first dock on the physical iPhone and **rejected it**. Still uncommitted; this is a
targeted revision of the same Phase 9 branch, not a new phase.

### Old (rejected) version

- Radius 0 rectangular dock — read as a boxed footer, not a floating object.
- A thin **red rectangular border** around the dock and the collapsed control — looked like a debug frame.
- A **red top-line active marker** — read like a web browser tab indicator.
- **Center cross-fade collapse**: the full bar faded out and a lone Home square faded in at the horizontal
  **center** — no spatial continuity ("the bar just disappears").
- **Home-only** adaptive behavior.
- Create's **List ticket** CTA sat directly on the dock's padded surface and read as one combined
  navigation/action object.

### New version

- **Rounded dark-glass dock.** `DOCK_RADIUS` **26** (navigation is the explicit exception to radius 0);
  dark translucent material `rgba(18,18,20,0.72)`; a single subtle **neutral** hairline
  (`rgba(255,255,255,0.10)`) for depth — **no red frame anywhere**.
- **Selected inner capsule** as the active state: a lighter inner region (`rgba(255,255,255,0.12)`,
  radius 18) behind a **white** icon; inactive icons muted. Reads clearly even in a screenshot; no red
  fill, no glow, no top marker. `accessibilityState.selected` retained.
- **Spatial side-anchored contraction**, not a cross-fade: the pill's **width** interpolates
  `FULL_W → COMPACT_W` while the row translates so the **active icon slides to the left** and the
  secondary icons fade — the dock visibly shrinks into the active control at **bottom-left** (never the
  center). Container is pinned to the left anchor (`DOCK_SIDE_MARGIN` 16) and translated to centre when
  expanded, so contraction finishes bottom-left with the same side margin.
- **Home, Bids and Profile** collapse on downward scroll, each with its **own** route-scoped state (the
  pure `dockMachine` is reused; the context is now keyed by route so one tab's scroll never affects
  another). Restore on upward scroll, near-top, tab focus, and compact-control tap.
- **Create never auto-collapses** — it wires no scroll handler.
- The **compact control shows the ACTIVE tab's icon** (Home on Home, Bids on Bids, Profile on Profile);
  tapping it **only expands** (no navigation). Switching tabs always arrives expanded.
- **List ticket CTA is a separate surface.** Create's StickyBar now sits above the dock via
  `useCtaDockOffset()` (`marginBottom = insets.bottom + DOCK_GAP + DOCK_HEIGHT + CTA_DOCK_GAP`), with its
  own background and a **`CTA_DOCK_GAP` = 14pt** clear gap — its border never touches the dock, and it is
  never a navigation row.
- **Animation** re-authored to the contraction above and retimed to **220ms** (fast, mechanical, no
  spring/bounce); **instant** under reduce-motion.

### Exact values

- Dock radius: **26**  · Dock height: **56**  · Item width: **56**  · Horizontal pad: **6**
- Full width: `4 × 56 + 12 = 236`; Compact width: `56 + 12 = 68`
- Outer material: `rgba(18,18,20,0.72)` + hairline `rgba(255,255,255,0.10)` (no expo-blur — see below)
- Selected cell: `rgba(255,255,255,0.12)`, radius 18, inset 8/6
- Animation: RN `Animated`, one 0→1 value driving width + row translateX + secondary opacity, **220ms**,
  reduce-motion → 0ms
- Collapse anchor: **bottom-left** (`DOCK_SIDE_MARGIN` 16 from the screen edge)
- CTA-to-dock gap: **14pt** (`CTA_DOCK_GAP`)
- Collapse-enabled routes: **home, bids, profile** (`COLLAPSING_ROUTES`); Create excluded

### Material / dependency note

`expo-blur` is **not installed**, and per the brief it was **not added casually**. True frosted BlurView
would need it; the dark translucent surface is the closest premium approximation with the current
dependencies (Reanimated 4.1 is present but the one-shot width contraction runs fine on RN `Animated`, so
no new library and no runtime-Reanimated risk was introduced). **If Jose wants real backdrop blur, adding
`expo-blur` is a small, owner-approved follow-up** — the dock is structured so the glass surface becomes a
`BlurView` with the same overlay + hairline.

### Verification (revision)

Tests 548 / 21 files (nav suite 25); tsc clean; lint 28 warnings / 0 errors (no new); iOS bundle HTTP 200.
**Not device-verified** — the local simulator is still blocked; this revision exists to be re-checked on
Jose's iPhone (collapse feel, glass depth, active-cell clarity, and the Create CTA/dock separation are the
key things to judge on hardware).
