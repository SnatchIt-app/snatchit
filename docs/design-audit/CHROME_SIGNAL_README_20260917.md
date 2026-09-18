# Chrome Signal — prototype README (B, 2026-09-17)

**File:** `docs/design-audit/prototypes/chrome-signal.html` — one self-contained interactive prototype.
Open it directly; there is no server, no build step and no network request. All artwork is generated in SVG from a
seeded PRNG, so the file carries no images and nothing is fetched.

This is not another audit board. It is the app: a device frame, a real bottom dock, a floating SANDBOX band, generated
event artwork, and flows that actually run — place a bid, mark a transfer sent, confirm receipt, pay.

---

## 1 · What is in it

**Ten connected screens**, reachable by tapping: Home → Listing detail → Bids → Tickets → Send Transfer →
Receive Transfer → Checkout → Profile → Settings → Venue console.

**Three directions**, switchable in the top bar:

| | Home | Money screens | Glass |
|---|---|---|---|
| **Chrome Editorial** | 372 px flyer hero, 66×82 poster thumbnails, date rules | artwork header, 13 px row rhythm | navigation only |
| **Chrome Utility** | 150 px banner, 44 px thumbnails, one continuous list | no artwork, 8 px row rhythm | navigation only |
| **Chrome Signal** (recommended) | 344 px hero + index feed with date rules | no artwork, 10 px rhythm, glass action bar | navigation + overlays |

**Four live flows**, each with a working → success sequence: place a bid (the current bid and bid count update, and the
listing switches to "Raise your bid"); mark as sent (the status rail advances and the action becomes "View payout
status"); confirm receipt (payment releases); pay (the order becomes a receipt).

**Two overlay interactions:** the Filters sheet on Home, and a bid-status detail sheet from any row on Bids.

**Motion:** Reduce Motion is the default, because that is the setting that has to look finished. A visible toggle
switches to full motion — screen rise, sheet translate, image crossfade, one value flash on a changed bid.

---

## 2 · The design decisions, in one page

- **Foundation.** Deep black #08090A; charcoal #0F1114 / #15181C for raised surfaces. Panels lift with a 4% white wash
  instead of a border. Radius stays 0 for content and pill for chips — the approved identity, untouched.
- **Chrome is rationed to five places:** the wordmark, the 1 px top edge on the nav bar / action bar / dock, the
  selected-tab indicator, the inner highlight on the primary button, and the ring on the profile avatar. Nothing else.
- **Glass is navigation only:** top bar, dock, sticky action bar, the floating back and photo controls, and the two
  sheets. Nothing in the content layer is blurred.
- **Red has exactly two roles:** the single filled primary action, and destructive states, which are outlined and never
  filled. Red is now entirely absent from discovery — including the under-fifteen-minute auction pill, which is amber.
- **Live bid, truthfully:** quiet timestamp beyond six hours → soft white dot and remaining time inside six hours →
  amber "Ending in 11m" under fifteen minutes → grey "Ended · won at $52", terminal. Derived from real remaining time
  only, and every treatment disappears at expiry.
- **The status rail** replaced a vertical timeline that cost 200 px. Four nodes with real timestamps in 46 px, and it
  means the fact rows no longer restate the status.
- **Money screens keep everything:** recipient, delivery method, proof, transfer status, payment state and the full
  breakdown, with the total set larger than its line items.

### Three defects the measurements caught, and the fixes

| Found | Fix |
|---|---|
| The primary button's near-black label measured **4.08:1** against the lighter end of the red gradient — it failed AA at 13 px bold | Pure black, now **5.94:1**; the sub-line went from 72% to 82% opacity, now **4.76:1** |
| The dock's bid count was **red**, which is neither a primary action nor a danger — it broke the rule stated one paragraph above it | The badge is chrome. Red now appears on exactly one element per screen, verified by scanning computed styles |
| Two icon buttons were **30 px** tap targets | The ring stays 30 px; a `::after` inset gives a 44 px hit area. Zero controls under 40 px remain |
| The safe-area offset was applied **twice**, pushing every header ~45 px down | The status bar and SANDBOX band float; a header clears them once. The hero now bleeds to the top of the screen, which is what makes it read as an app |

---

## 3 · Verification — measured in the browser

| Check | Result |
|---|---|
| Variant × screen combinations rendered | **30 / 30**, zero JavaScript errors |
| Flows exercised end to end | bid, send, receive, pay, filters, bid detail, blocked delete — **all pass** |
| Contrast, every text role, alpha composited over its real surface | **all ≥ 4.5:1** (small text 4.68, CTA 5.94, CTA sub-line 4.76, dock inactive 5.01) |
| Red elements on Home, Bids, Tickets, Profile, Settings, Console | **zero** |
| Red elements on Listing, Send, Receive, Checkout | **exactly one** — the primary action |
| Tap targets under 40 px | **zero** |
| Animations or transitions with Reduce Motion on | **zero** (the default state) |
| Horizontal overflow inside the frame | **zero** |
| Glass surfaces in the content layer | **zero** |

### Fit, at 390 × 844 with the composition scaled down about 20%

| Screen | Chrome Signal | Chrome Editorial | Chrome Utility |
|---|---|---|---|
| Send Transfer | **fits** | 260 px over | fits |
| Receive Transfer | 22 px over | 47 px over | fits |
| Checkout · Bids · Tickets · Profile · Settings | **fit** | Tickets 67, Settings 2 over | fit |
| Listing | 93 px over | 171 px over | fits |
| Home | 391 px over (a feed) | 602 px over | fits |
| Venue console | 269 px over (a dashboard) | 310 px over | 210 px over |

That table is the argument for the hybrid, measured rather than asserted: **at Editorial spacing the Send Transfer
commitment no longer fits above the action.** Utility fits everything and has no discovery worth browsing. Home and the
console scroll in every direction because a feed and a dashboard are supposed to.

### Not verified

- **No device check.** This is a desktop browser at a phone-shaped frame. No screen here has been rendered on a handset
  by me, and no screenshots were taken (standing preference: text-only verification).
- Type will differ on device: the prototype uses the system stack, and the app's condensed display face is not loaded here.
- Nothing was applied, built, deployed or tagged. No sandbox or production access. C's handset-test files and the
  transfer/proof implementation were not touched.

---

## 4 · What implementing Chrome Signal in React Native would take

**No new dependency is required for the core direction.** It is layout, tokens, copy and one new primitive each for
notices, the sticky bar and the status rail. Three things degrade gracefully without a native build.

### Tokens — two files and a parity test
Add one surface ramp (`surf`, `surf2`, `surfUp`) and the advisory accent to `src/theme/v2.ts`, then mirror them in
`packages/design-tokens/src/brand.ts`. The parity assertion in `tests/product-v2-foundation.test.ts` compares the two
objects with `toStrictEqual`, so a one-sided edit fails the suite — which is the desired behaviour. Radius, red and the
type scale are unchanged, so this is additive.

### New primitives
| Component | Notes |
|---|---|
| `Notice` | three ranks (advisory / warning / success), one blocking notice per screen, assertable. Replaces the hand-rolled boxes in both transfer screens, `settings/index` and `CreateListingScreen` |
| `StickyBar` | safe-area aware via `react-native-safe-area-context`; one filled action, consequence on its own sub-line, disabled reason in the same place and in the accessible label |
| `StatusRail` | four nodes with timestamps. Plain `View`/`Text`, no dependency |
| `PriceTable` | label/value rows with `fontVariant: ['tabular-nums']`; asserts the total's font size exceeds every line item's |
| `LiveState` | renders the output of `liveBid.ts`; never renders past `ends_at` |

### New logic
`src/lib/listing/liveBid.ts` — a pure function from (`ends_at`, `now`, `bid_count`) to exactly one of four states, with
unit tests and a mutant that widens a boundary and must fail. Every live indicator in the app reads from it.

### Artwork
The SVG posters here stand in for `EventMedia`. In the app: `expo-image` with a new **4:5 hero slot** and a **3:2 feed
slot** in `src/lib/media/slots.ts`, `contentFit="cover"` so crops match, and the existing scrim approach
(`experimental_backgroundImage`, already used three times in `EventMedia.tsx`). The image crossfade is `expo-image`'s
own `transition`, gated by `useReducedMotion()`.

### The three things that need a build, and their fallbacks
| Effect | With a build | Without one (what ships today) |
|---|---|---|
| Blurred dock / top bar / sheets | `expo-glass-effect` (first-party since SDK 54, which this app is on) or `expo-blur` | a solid `rgba(12,13,15,0.96)` surface — visually close at these sizes |
| Metallic 1 px edge | `expo-linear-gradient` for the gradient hairline | a flat 1 px `rgba(255,255,255,0.14)` line; the machined look is the thing that degrades |
| Gradient on the primary button | `expo-linear-gradient` | flat `#FF1A1A`; contrast is unaffected (black on flat red is 5.41:1) |

None of these blocks the direction. All three are chrome, which is exactly the layer designed to be rationed.

### Motion
RN `Animated` with the existing `v2.motion` tokens (instant 90 / swift 180 / settle 280, easing
`cubic-bezier(0.22, 1, 0.36, 1)`). **Do not reach for Reanimated:** it is installed, but there is no `babel.config.js`,
so no worklet has ever run in this build — using it is a build change, and nothing in this direction needs one. Every
animation collapses through `useReducedMotion()`; nothing animates on a warning; nothing animates per second.

### Sheets
RN `Modal` with the existing slide presentation, or Expo Router's form-sheet presentation. Either way the sheet is
navigation, so it may carry the translucent material; its content may not.

### Sequence
Stage 0 is not this work: the release-critical state fixes from the first audit — the bid form's `0` floor, the
re-entrant destructive actions, Home's in-flight empty state, the avatar spinner — come first and are **C's**.

1. `liveBid.ts` + tests · 2. `Notice` + `StickyBar` (tokens land here) · 3. `LiveState` into `DiscoveryCard`,
`BidCard`, `TransactionPanel` · 4. Home layout: `SectionList` with date headers, the new media slots · 5. Money screens:
`PriceTable`, `StatusRail`, density, and the measured total assertion · 6. Motion last, because motion on an unfinished
layout hides layout problems.

Every stage is reviewable and reversible on its own, and none of it touches the gated client surface
(`src/lib/payments.ts`, `src/lib/checkout/*`, `src/lib/auth/signOut.ts`) or any payment, auth or transfer rule.

---

## 5 · Still the owner's decision

1. **Red for destructive.** This prototype outlines destructive actions, never fills them, and removes red from
   discovery entirely. That reverses the direction approved on the 14th. D is carrying it as an A-or-B.
2. **Which density wins on Tickets** — drawn here as Editorial; Utility is defensible.
3. **Whether the console follows.** The venue view here is my proposal, not D's design; D verifies operational
   correctness before any of it is treated as agreed.
4. **Whether a build gets authorised** for the blur and gradient layer, or whether the flat fallbacks ship.
