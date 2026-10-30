# Phase 0 — Foundation stabilization

**Session:** Front End · **Date:** 2026-09-03
**Authority:** `CORE_FRONTEND_HANDOFF.md` (Core Development Session). Where it and
`FRONTEND_SESSION_BASELINE.md` disagreed, the handoff was followed.

No screen was redesigned. No navigation changed. No backend file was touched. Nothing was
committed, pushed, or opened as a PR.

---

## 1. Branch and base

| | |
|---|---|
| Worktree | `/Users/josetascon/snatchit-fe-phase0` (isolated; the Core tree at `/Users/josetascon/snatchit` was not used for this work) |
| Integration branch | `frontend/v2` — created from `origin/feature/venue-native-and-product-v2` |
| Working branch | `frontend/v2-phase0-foundation` |
| HEAD at start | `7d45cbf0edbabd06ca240a5d6386e62c572ff0de` |
| Canonical base named in the handoff | `fc883207e255155033fd2fca3925ac34fbbd8350` |

**The remote had advanced by one commit before work began**, so this is reported rather than
assumed. `origin/feature/venue-native-and-product-v2` now resolves to `7d45cbf`, which is
`fc88320` plus exactly one commit:

```
7d45cbf docs(phase2): final activation-blocker rulings, KMS runbook, activation matrix,
        implementation report
```

It adds a single file, `docs/phase2/_impl/FINAL_ACTIVATION_BLOCKERS_IMPLEMENTATION_REPORT.md`,
446 lines, documentation only, inside a Core-owned directory. **No material conflict with
`CORE_FRONTEND_HANDOFF.md`.** Work proceeded from `7d45cbf` because it contains `fc88320` and
branching from the older SHA would have started the frontend line already behind.

The working tree was clean at branch creation. `npm ci` was run; `@expo-google-fonts/oswald` and
`@expo-google-fonts/inter` are present, so the brand faces are installed in this worktree.

---

## 2. Files changed

18 modified or deleted, 14 added. No file outside the Front End ownership map in
`CORE_FRONTEND_HANDOFF.md` §4 was touched.

**Foundation**
```
src/theme/typography.ts                NEW  React Native type resolver (§3)
src/theme/v2.ts                        untouched — deliberately, see §3
src/lib/media/url.ts                   +270/-24  encoding, host allowlist, shared resolver
src/lib/media/slots.ts                 width contract documented
src/components/media/EventMedia.tsx    children slot, fluid measured width
src/lib/coverImage.ts                  routed through the one media policy
src/lib/avatarImage.ts                 routed through the one media policy; cache control
src/hooks/useImageUpload.ts            cache control
src/hooks/useReducedMotion.ts          NEW  live OS reduce-motion setting
src/types/index.ts                     money-unit comments (§4)
```

**Primitives** — all new, `src/components/ui/`
```
Button.tsx  Input.tsx  Chip.tsx  Badge.tsx  Sheet.tsx  Skeleton.tsx
EmptyState.tsx  StickyBar.tsx  IconButton.tsx  Spinner.tsx  press.ts  index.ts
```

**Correctness fixes**
```
app/profile/[id].tsx           app/settings/preferences.tsx
app/settings/blocked-users.tsx app/settings/notifications.tsx
app/(auth)/signup.tsx
```

**Harness and tests**
```
app/_dev/foundation.tsx                +288  every primitive, every state
tests/product-v2-foundation.test.ts    +188  media encoding, host allowlist, width contract
tests/foundation-typography.test.ts    NEW   the line-box floor and the resolver
```

**Removed** (Task 2)
```
constants/theme.ts  hooks/use-color-scheme.ts  hooks/use-color-scheme.web.ts
hooks/use-theme-color.ts
```

---

## 3. Foundation defects closed

### 3A. Display typography — fixed, but NOT where the task said to fix it

The instruction was to change the display scale in `src/theme/v2.ts`. **That file was deliberately
left alone**, and the reason is a boundary collision worth recording:

- `packages/design-tokens/src/brand.ts` is a byte-identical mirror of `src/theme/v2.ts`, and
  `tests/product-v2-foundation.test.ts` fails on any drift between them.
- `packages/**` is Core-owned and on the do-not-modify list.
- So editing the token alone turns a green guard red, and editing both crosses the boundary.

There is also a design reason the token should not change. The brand's sub-1.0 display leading is
real and correct — the live site computes roughly 0.82 — and the web renders it properly. Only
React Native has the constraint: below `lineHeight = fontSize`, Android clips the tops of glyphs,
and Oswald is a tall condensed face. Forcing React Native's floor onto a token the web consumes
would loosen marketing-true typography on a platform that does not need it.

**What shipped instead:** `src/theme/typography.ts`, a React Native rendering layer.
`textStyle(token)` resolves a token into a React Native `TextStyle` and raises the line box to the
smallest non-clipping value, `ceil(fontSize × 1.02)`:

| Token | Designed | Rendered on RN |
|---|---|---|
| `displayXl` | 44 / 40 | 44 / **45** |
| `displayLg` | 34 / 32 | 34 / **35** |
| `displayMd` | 26 / 26 | 26 / **27** |
| `displaySm` | 20 / 22 | 20 / 22 (already clear) |
| `title`, `body`, `bodySm`, `label`, `micro`, `price` | unchanged | unchanged |

The raise is a floor, not a redesign: the tightest leading React Native can render. Family,
tracking, uppercase and the price tabular figures all travel with the token through the same
resolver, so a screen can no longer forget one. The rule is: **no screen or primitive reads
`v2.type.*` directly.** The harness's own `h1` previously hardcoded `34 / 34` — the clipping case
itself — and now goes through `safeLineHeight`.

**Core decision needed** if you would rather the token itself carried the floor: that is a
coordinated two-file change including `packages/design-tokens/src/brand.ts`, and it would change
what the web renders. See §12.

### 3B. `EventMedia` composition — closed

`children` added. It renders in a `box-none` layer above the scrim, so text can finally sit inside
the frame the scrim exists to serve, and a child never swallows a touch belonging to the row the
artwork sits in. Existing consumers are unaffected — the prop is optional and the layer is not
rendered when it is absent. The component still owns media presentation only; it did not become a
card.

### 3C. Media width contract — closed

`EventMedia` gained a `fluid` mode: the frame measures itself with `onLayout`, requests nothing
until the real width is known, and derives its height from the slot ratio. `slots.ts` now states
in the type that `layoutWidth` is a **reference, not a layout**, with the numbers that make it
dangerous (nominal 390 against a 375pt iPhone SE, 384pt of two-up grid on a 375pt screen).

Consumer audit: the only consumer of the V2 media system in the repository is
`app/_dev/foundation.tsx`, and every call there passes an explicit width or uses `fluid`. **No
production-ready consumer relies on a nominal width.** Nothing hardcodes 375, or any device
dimension, anywhere in this change — `StickyBar`'s stack threshold is derived from the layout
(gutters + narrowest readable price column + a button that still fits its label) and read against
the live window width.

### 3D. Media URL safety — closed, one policy

Both defects fixed in `src/lib/media/url.ts`, and `coverImage.ts` and `avatarImage.ts` now call
into it rather than building URLs of their own. There is one encoder and one host rule.

**Path encoding.** `encodeURI` was replaced with per-segment `encodeURIComponent`. `/` separators
survive; `#`, `?`, `&`, `+`, `=` and spaces do not. An already-encoded segment is detected and left
alone, so a row written by an older encoding path does not become `%2520`; a literal `%` in a
filename still encodes correctly.

**Absolute hosts.** `listings.cover_image_url` and `profiles.avatar_url` are legacy columns holding
whole URLs, and their values are row data. They were rendered verbatim, so a row could choose which
host the app made requests to. Now:

- only `https`, only on an allowlisted host;
- the allowlist is this project's own Supabase storage origin, derived at runtime, plus
  `ADDITIONAL_TRUSTED_MEDIA_HOSTS`, which is **deliberately empty** — adding a host is a decision
  about where the product makes requests on a user's behalf and belongs in review;
- non-`http` schemes (`javascript:`, `data:`) and protocol-relative `//host/x` are refused;
- an untrusted host produces `{ kind: 'fallback', reason: 'unsafe-host' }`, so the branded plate
  renders instead of nothing;
- **a URL pointing at our own storage is rewritten back into a bucket path**, which pulls legacy
  `cover_image_url` rows into the transformation pipeline instead of stranding them on originals.

One defect was found by the new tests rather than by reading: `new URL()` resolves `..` away before
any check can see it, so `/auction-media/../avatars/x.png` arrived looking innocent while pointing
at a different bucket. Fixed two ways — the raw value is checked for traversal (including
`%2e%2e`) before parsing, and a storage URL whose bucket differs from the one the caller asked for
is refused outright.

### 3E. Image transformations — resolver complete; screen adoption deferred

Core verified transformations are enabled and working in production. The resolver now produces them
from the **measured layout width** and the **real `PixelRatio.get()`**, with quality scaling
inversely to density (45 at 2x, 80 at 1x) and density capped at 2, so a 3x phone does not pay for a
3x download. `mediaUrlForStoredValue()` gives the legacy call sites the same ability, and returns
the plain object URL when no width is passed — which preserves today's behaviour exactly, so
adopting transformations stays a decision a call site makes with a width it can justify.

**Deliberately not done:** wiring the existing production screens (home feed, explore, my listings,
listing detail, bids) to request derivatives. Two reasons. This session cannot run the app, and a
transform that failed would break the image on the primary conversion surface; and Home and Listing
Detail are the immediate Phase 1 targets, where they adopt `EventMedia` wholesale and get this for
free. The pipeline is proven in the harness, which prints the exact URL it requests at the device's
real width. See §11.

### 3F. Image cache control — closed

`3600` → `IMMUTABLE_CACHE_CONTROL` (`31536000, immutable`) in `src/hooks/useImageUpload.ts` and
`src/lib/avatarImage.ts`, imported from the media module so the value is stated once. Both upload
paths are timestamp-unique (`<uid>/covers/<Date.now()>.<ext>` and
`<uid>/avatar_<Date.now()>.<ext>`), so the objects are genuinely immutable. No storage policy and no
bucket configuration was touched.

---

## 4. Money contract

No pricing math, no fee logic and no conversion was changed. The only edit is documentation, in
`src/types/index.ts`, as instructed:

```
starting_bid       // WHOLE DOLLARS
current_bid        // WHOLE DOLLARS
buy_now_price      // WHOLE DOLLARS
winning_bid_amount // WHOLE DOLLARS (stamped from bids.amount)   ← was "in cents"
```

A block comment above them states the contract and names the trap: `public.listings` is the only
dollar-denominated surface, `market.listing_unified.price_minor` is cents, and conversion happens
exactly once through `dollarsToCents()` / `centsFromDollars()`. Runtime types are unchanged. The
pricing suite still passes untouched.

---

## 5. Primitives added

Twelve files in `src/components/ui/`, each with a documented reason to exist and every state drawn
in the harness.

| Primitive | States | Notes |
|---|---|---|
| `Button` | default, pressed, disabled, loading | `primary` (red fill, black label), `secondary` (hairline), `destructive` (a **different** red, never a filled block, so a delete cannot look like a purchase), `ghost`. Sizes 52/44/36; `sm` makes up the 44pt minimum with `hitSlop`. The label stays mounted while loading so the button cannot change width under a finger. |
| `Input` | default, focused, disabled, error | Hairline underline, label above in `micro` — never a placeholder as the only label. Focus raises the line to brand red. The helper or error text is also the accessibility hint. |
| `Chip` | selected, unselected, disabled | 32pt with `hitSlop` to 44. Selected fills 10% red with a red border and a **white** label; a red label on a red tint disappears on a phone in a dark room. |
| `Badge` | neutral, success, warning, danger, count | Meaning is always a word. `FromAFanBadge` ships the fixed marketplace provenance string. **No venue-direct variant** — see §10. |
| `Sheet` | open, closed | React Native `Modal`, no new dependency. Dismissible by scrim tap and by the Android back button, both of which the product's current sheets lack. Safe-area padded, square corners. |
| `Skeleton` | pulsing, reduced-motion static | Opacity 0.4→0.7 at 1200ms, no shimmer sweep. Takes width/height/ratio so it mirrors real geometry. Hidden from screen readers. |
| `EmptyState` | with and without action | Display line, one sentence, at most one action. No illustration, no emoji. |
| `StickyBar` | side by side, stacked | Safe-area aware, stacks below a derived width. No device dimension anywhere in the file. |
| `IconButton` | default, pressed, disabled, over-art | Replaces the sixteen hand-rolled back buttons, none of which has an accessibility role or label. The label is a **required** prop. |
| `Spinner` | animating, reduced-motion static | Announces "busy"; the platform indicator does not. |
| `press.ts` | — | The one press animation: scale to 0.98, 90ms, brand easing, no bounce, collapses under reduce motion. |
| `index.ts` | — | The barrel screens import from. |

---

## 6. Legacy files removed

Re-verified unused on this branch before deletion (no import, no call site, no reference in
`app/`, `src/`, `components/`, `packages/`, `tests/`):

```
constants/theme.ts             Expo template palette — teal #0a7ea4, light mode, unused
hooks/use-color-scheme.ts
hooks/use-color-scheme.web.ts
hooks/use-theme-color.ts
```

Both directories are now empty and gone. `app/(tabs)/explore.tsx` was **not** touched: it is
deferred as the future Search surface, per instruction.

---

## 7. Correctness fixes

All four were verified still present on this branch before being changed.

**Seller trust stats** (`app/profile/[id].tsx`). A failed `get_profile_trust_stats` set the stats to
`null`, and the rows then rendered `?? 0` — telling every viewer that an established seller had zero
completed sales, on the screen whose entire job is trust. A `statsUnavailable` state now
distinguishes a failure from a genuine zero and renders a distinct panel: "Seller history
unavailable", the sentence "This is not a record of zero sales", and a 44pt Retry. The raw Postgres
message still goes to the log and never to the screen.

**Preferences save** (`app/settings/preferences.tsx`). The update result was never destructured, so a
failed save stopped the spinner and navigated back exactly like a successful one. The error is now
checked; on failure the user stays on the screen with "We couldn't save your scene. Check your
connection and try again." and the raw message goes to the log. Editing a selection clears the
message. The save button gained a role, a label and busy state.

**Blocked users** (`app/settings/blocked-users.tsx`). A fetch failure called `setRows([])` and
rendered "No one blocked" — a safety feature reporting the opposite of the truth. Loading, empty,
failure and populated are now four distinct states; the failure state says "Couldn't load your block
list", states plainly that it is not a record of having blocked no one, and offers a 44pt Retry.

**Touch targets.** The 18+ signup gate (`app/(auth)/signup.tsx`) was a 22pt checkbox in a row with no
vertical padding: the row now has a 44pt minimum height plus `hitSlop`, and an
`accessibilityLabel` matching the sentence a user reads. The notification-permission recovery link
(`app/settings/notifications.tsx`) was `marginTop: 6` and nothing else — the only route back when
notifications are denied. It now has a 44pt minimum height, `hitSlop`, a button role and a label.

---

## 8. Media security and URL policy, stated

1. There is **one** media URL policy, in `src/lib/media/url.ts`. `coverImage.ts` and
   `avatarImage.ts` call into it. Do not add a second sanitizer.
2. Stored paths are encoded **per segment**. Separators survive; every other reserved character is
   escaped; already-encoded segments are left alone.
3. Absolute URLs are **allowlisted**: https only, this project's own Supabase storage origin only,
   plus an explicitly empty extras list. Everything else renders the branded fallback.
4. A trusted URL pointing at our own storage is **rewritten into a bucket path**, so legacy rows get
   transformed derivatives like everything else.
5. A stored URL may not address a bucket other than the one the caller asked for.
6. Traversal is refused on the raw value, before `new URL()` can normalise it away.
7. A caller that cannot render is **told**, with a reason, rather than handed a string that looks
   like a URL.

## 9. Image transformation behaviour

- Requested width = **measured layout width × real device pixel ratio**, density capped at 2.
- Quality scales inversely with density: 45 at 2x, 80 at 1x, which holds bytes roughly flat.
- The `fit` backdrop is a 32px, quality-30 copy of the same artwork — never a generated image.
- Nothing is requested at all until a fluid frame knows its real width.
- No Supabase configuration was touched.

Measured evidence from Core's inspection, which this pipeline now exploits: the same object is
168,350 bytes untransformed and 26,179 bytes at `width=400&quality=60`.

## 10. Accessibility work

Not deferred, per instruction. Every primitive ships with `accessibilityRole`, label support,
disabled and busy semantics, and a 44pt minimum reached with real height or `hitSlop`.
`IconButton` makes the label a required prop specifically because the product's sixteen existing
back buttons have none. `Skeleton` is hidden from screen readers so the real content is what gets
announced. `Spinner` announces "busy" and holds still under reduce motion. `Sheet`'s scrim is a real
labelled button, not an invisible view, and Android's back button dismisses it. The four correctness
fixes above added roles and labels to the controls they touched.

**Reduce motion** is read live from `AccessibilityInfo` via `src/hooks/useReducedMotion.ts` rather
than through Reanimated's `useReducedMotion`, which snapshots the value once at module load and
never updates — its own documentation says so.

**On the animation library.** No animation library was added. Press feedback and the skeleton pulse
use React Native's own `Animated`, which ships with React Native. Reanimated stays installed and
untouched. The reason for not reaching for it here: nothing in this app has ever executed a
Reanimated worklet (the only reference is a bare side-effect import), the repository carries no
`babel.config.js` of its own, and a foundation primitive that every screen will depend on is the
wrong place to discover whether the worklets plugin is wired. Verifying that on a running build is a
Phase 1 task; gesture-driven work should use Reanimated once it is proven.

## 11. Tests and checks — exact results

Run in the worktree, after `npm ci`.

```
npx tsc --noEmit -p .     → clean, exit 0
npm test  (vitest run)    → Test Files  10 passed (10)
                            Tests      346 passed (346)
npm run lint (expo lint)  → 45 problems (0 errors, 45 warnings)
```

Baseline on the same branch before any change: **9 files / 314 tests passing**, typecheck clean,
lint **45 problems (0 errors, 45 warnings)**. So: **+32 tests, no new lint warnings, no new type
errors.** Every remaining warning is pre-existing (`exhaustive-deps`, unused variables, stale
eslint-disable directives) and none is in a file this phase created.

New coverage:

- **Path encoding** — space, `#`, `?`, `&`, `+`, `=`, nested folders, idempotency on an
  already-encoded segment, a literal `%`, and an assertion that the transformation query string
  survives a hostile filename intact.
- **Host allowlist** — own host trusted; `cdn.example.com`, a lookalike
  (`example.supabase.co.evil.test`) and a host with the real one in its query string all refused;
  plain `http` refused on the right host; `javascript:`, `data:` and protocol-relative refused;
  own-storage URL rewritten to a bucket path; traversal refused raw and percent-encoded;
  cross-bucket URL refused.
- **Transformed URL generation and width handling** — plain URL without a width, derivative with
  one, density cap at 2x, measured width beating the nominal slot width, height derived from the
  measured width.
- **Typography** — no token resolves below its font size; the display tokens designed below the
  floor are actually raised; the body scale is untouched; the raise is the *smallest* safe value;
  uppercase, tracking and tabular figures reach the style; an unregistered face falls back to
  `undefined`; motion collapses under reduce motion.

**One existing expectation was changed, deliberately, and it is flagged in the test file itself.**
`passes absolute legacy URLs through without inventing a transform host` asserted that any absolute
URL renders verbatim. That is the behaviour the allowlist exists to remove, so it is now
`refuses an absolute URL on a host we do not control`. The comment above it records that the
requirement changed rather than the test being weakened to fit a defect. No other expectation was
relaxed.

## 12. Deliberately deferred, and new Core handoffs

**Deferred by this session**

| Item | Why |
|---|---|
| Wiring production screens to request transformed derivatives | The app cannot be run here, and Home and Listing Detail adopt `EventMedia` in Phase 1 anyway. §3E. |
| Migrating any screen onto the primitives | Out of scope for Phase 0 by instruction. The primitives have their harness; screens follow in tier order. |
| Removing or restoring `app/(tabs)/explore.tsx` | Deferred by instruction; it is the Search candidate. |
| Reanimated-based motion | Unproven worklet setup, §10. Verify on a running build before Phase 1 motion work. |
| `EventMedia` focal point under `contain` | Percentage `contentPosition` follows background-position semantics, so under `contain` it positions within the letterbox slack. Visible only on legacy 16:9 assets in portrait slots, and it needs a device to tune. Recorded, not guessed at. |

**New Core handoffs required**

1. **The display line-height decision (§3A).** If Core wants the floor in the token rather than in
   the React Native resolver, that is a coordinated edit to `src/theme/v2.ts` **and**
   `packages/design-tokens/src/brand.ts`, both effectively Core-owned through the parity guard, and
   it changes what the web renders. Front End's recommendation is to keep the split: the token
   records the design, the platform resolver renders it safely.
2. **The design-tokens tarball still does not carry `brand.ts`** (Core's own §2 note). Until it is
   repacked, the web app renders the legacy blue-black palette while mobile renders the brand. The
   parity test guards the two copies that do not ship to web.
3. **Confirmation that `31536000, immutable` is acceptable on `auction-media` and `avatars`.** Both
   upload paths are timestamp-unique so the objects are immutable, but the cache header is now a
   year and a mistakenly reused path would be sticky. No bucket configuration was changed.
4. **A stable error-code vocabulary** remains Class C. The correctness fixes map failures to human
   copy locally and log the raw string; that is a per-screen workaround, not a system.
5. **The `kernel.tickets` SELECT grant** is still outstanding, so a Tickets surface remains blocked.
   Unchanged from the handoff; restated because it gates the cheapest Tier-1 win.

## 13. Is Phase 1 (Listing Detail) safe to begin?

**Yes.**

What Phase 1 needs is in place: brand type that renders safely on both platforms through one
resolver; a media component that measures itself, requests a right-sized derivative, refuses an
untrusted host, composes text inside its frame and draws a branded fallback; a primitive set
covering every control a listing detail screen needs, including the sticky action bar that caused
the July App Review geometry failure; motion and accessibility defaults that come with the
primitives rather than being retrofitted; and a harness that shows all of it in one place.

Three constraints carry into Phase 1 and none of them blocks it:

1. **Marketplace rail only.** All three native feature flags are `false` and 093 is not deployed, so
   `isVenuePrimarySale` must never be passed `true` and no venue-direct badge may ship. The
   provenance badge that exists says "From a fan", which is true of every listing in the product
   today.
2. **Prices stay on the existing helpers.** `finalSoldPrice` → `allInFromDollars` is the live path
   and it is correct. If a Phase 1 screen moves to `allInPrice`, the base must go through
   `centsFromDollars` — the compiler enforces this, and it is the one thing that must not be
   worked around with a cast.
3. **Nothing in Phase 0 has been seen on a device.** Typecheck, lint and 346 unit tests pass, but
   the first Phase 1 task should be to run the app, open `/_dev/foundation` in a development build,
   and confirm the brand faces register and the display scale does not clip on Android. The harness
   prints whether the fonts are active and the exact image URL being requested, which makes both
   answerable in about a minute.
