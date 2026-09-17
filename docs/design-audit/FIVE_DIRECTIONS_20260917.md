# Five visual directions — exploration (B, 2026-09-17, first draft)

**Owner's brief:** the calm pass stayed too close to the existing language. Explore genuinely different directions, informed
by current event/ticketing products and Apple's iOS 26 guidance, without copying anyone's branding or assets.

**Design work only.** No product code, database file, payment/auth/transfer rule or active handset-test file is touched;
no sandbox or production access; no build requested. Branch `design/frontend-audit-20260917`, prototypes local and synthetic.
C's Line 3 pass is live on the transfer screens and nothing here goes near them.

**Prototype:** `docs/design-audit/prototypes/five-directions.html` — one file, a switcher across all five directions, all five
screens (Home, Listing detail, Send transfer, Receive transfer, Checkout), each at normal **and** largest accessibility text,
plus a Reduce Motion toggle and a "Compare all" row. Verified in-browser: **25 of 25** direction/screen combinations render,
both typefaces load, and every direction keeps the delivery blocker, the expiry consequence, the proof requirement, the
payment-state notice and the full price breakdown visible.

**The rule I held across all five:** nothing transactional may be removed to make a screen look calmer. What varies is
discovery density, typography, surface, colour role, navigation and motion — not whether the seller is told why their button
is disabled.

---
## 1 · Gallery — "the flyer does the talking"
**Idea and tone.** One event per screenful. Full-bleed 4:5 art on flat black, then name, bid, date. Quiet sans throughout
(no condensed display anywhere except the wordmark), 28 pt rhythm, no cards, no chrome over art. Tone: a well-made zine —
confident, unhurried, image-first.
**Removed / moved.** From Home: venue, bid count, urgency tag, filter chips (search moves to the bar). Rationale: the flyer
already says what kind of night it is, and the owner's own test — name, bid, date — is the whole card. Everything removed
is one tap away on the listing, which is where a buyer decides.
**Why it feels polished and trustworthy.** Photography at full width with nothing competing; type that never shouts; the
price in tabular figures directly under the name, so the one number a buyer wants is never hunted for.
**Risks.** Scroll cost is real: the prototype's Home is **2179 px for four events** against 810 px of viewport, so browsing
twenty events is a long scroll and search becomes load-bearing. Art quality becomes the product's quality — a weak flyer
has nowhere to hide. Text over art needs a scrim to stay legible, and a scrim is a contrast promise that art can break.
**Largest text / Reduce Motion.** At the largest step the card text grows under a fixed-ratio image, so nothing truncates;
the poster loses relative height but never the price. With Reduce Motion the only casualty is the image crossfade.
**Stack reality.** Entirely buildable today: `expo-image` with the existing `EventMedia` slots, one new full-bleed slot,
no dependency. The scrim is `experimental_backgroundImage`, already used in the app.

## 2 · Index — "an insider's listings schedule"
**Idea and tone.** Home is a typographic index grouped by date: a small 40 pt thumbnail, the event name in condensed Oswald
at *mixed case* (not caps), venue and urgency in one muted line, price right-aligned. Hairline rules, no cards, native iOS
tab bar with labels. Tone: fast, informed, insider — a printed schedule that happens to be an app.
**Removed / moved.** Large imagery (thumbnail only), all-caps eyebrows (dates become the section headers), chips (date
grouping replaces most filtering). Nothing transactional leaves.
**Why it feels polished and trustworthy.** Density read as competence: eight to ten events per screen, one line each, the
price column aligned. Condensed type at small sizes is where Oswald is genuinely good, rather than shouting at 34 pt.
**Risks.** Condensed faces at small sizes and large accessibility sizes both need watching — Oswald's tight apertures lose
legibility faster than Inter under low contrast. Two-line wrapping in a fixed-height row is the classic failure. This is
the direction most likely to feel "web listing" rather than premium.
**Largest text / Reduce Motion.** Rows must become two-line blocks with the price moving under the name; the prototype does
this at the largest step. Reduce Motion costs nothing here — there is almost no motion to remove.
**Stack reality.** Buildable today. The only new work is a `SectionList` on Home, which Tickets already uses.

## 3 · Charcoal — "calm and familiar"
**Idea and tone.** Soft charcoal surfaces (#17191C) on a near-black canvas (#0E0F11), 12 pt corner radius, no borders at
all, generous padding, a 2-column card grid, native tab bar with labels, and a **broader accent system** — red for actions,
a muted blue for advisory notices, green for success. Tone: a bank you trust; safe, quiet, unremarkable in the good sense.
**Removed / moved.** Nothing is removed; density sits between Gallery and Index. The change is surface, not information.
**Why it feels polished and trustworthy.** Borderless cards with real padding read as considered; a second accent colour
means an advisory notice no longer has to borrow the action colour; familiarity itself is trust on a money screen.
**Risks.** **It deviates from an approved token:** `radius` in the design system is 0 or pill only, and "square is the
brand" is stated as identity, not preference. A broader accent palette also risks the same drift the v2 work removed. This
direction is the one that most needs an explicit owner ruling before any of it is built.
**Largest text / Reduce Motion.** The most forgiving of the five: padding absorbs growth, and the grid collapses to one
column cleanly. No motion dependency.
**Stack reality.** Buildable today, but it is the largest token change: radius, a second accent ramp, and surface values,
which means `src/theme/v2.ts` plus the mirrored `packages/design-tokens/src/brand.ts` and the parity test.

## 4 · Liquid — "current iOS, glass chrome, opaque content"
**Idea and tone.** Chrome is glass, content is not: a translucent top bar and dock, frosted price panels over artwork,
sheets for filters and detail actions, 18 pt radii on glass only. Tone: current, premium, native to iOS 26.
**Removed / moved.** Home card text moves *onto* a frosted panel over the art, which buys back vertical space (the grid
fits four events in one screenful where Gallery fits one). Nothing transactional moves.
**Why it feels polished and trustworthy.** It reads as part of the OS rather than a skin on top of it, and the frosted
panel solves the legibility problem that flat text-over-art creates.
**Risks.** The highest of the five. Translucency over user-supplied artwork is a contrast lottery; Apple's own guidance is
to keep glass on chrome and away from dense content, which is exactly the discipline that is easy to lose. Accessibility
settings change it materially — Reduce Transparency and Increase Contrast must produce an opaque fallback, which is
**two visual systems to maintain, not one**.
**Largest text / Reduce Motion.** The frosted panel must grow with its text and can swallow the artwork at the largest
step; the prototype keeps the panel to three lines and lets the art shrink. Reduce Motion removes the panel's crossfade.
**Stack reality — corrected after the research pass (see §11).** My first draft said this direction "cannot be built" and
implied someone would have to write a native module. That was wrong in an important way. **`expo-glass-effect` is
first-party and was introduced in Expo SDK 54 — the SDK this app is on** (`expo ~54.0.33`, resolved 54.0.37). Its
`GlassView` wraps `UIVisualEffectView`, takes `glassEffectStyle: 'regular' | 'clear'`, is iOS 26+ only and falls back to a
plain `View`, with `isLiquidGlassAvailable()` to gate. So the real cost is **one package install plus a new native build**
(it is a native module, so no build means no glass) — not bespoke native work. No build is authorized, so it still cannot
*start*, but the estimate was too pessimistic and the doc now says so.
**A second, more serious correction: this direction as I drew it contradicts Apple's own guidance.** I put frosted panels
over artwork — i.e. glass in the **content layer** — and Apple's HIG says not to: *"Don't use Liquid Glass in the content
layer,"* it is *"best reserved for the navigation layer,"* never glass-on-glass, used *sparingly*, and with no
content/glass intersections in a resting state such as first launch. The compliant version of this direction is glass on
**chrome only** (top bar, dock, sheets), with text-over-media handled by the Clear variant plus Apple's stated 35% dimming
layer, or by an ordinary material — not by a glass panel in the feed.

## 5 · Utility — "a terminal for tickets"
**Idea and tone.** Compact rows, tabular numerals everywhere, no imagery above a 150 pt detail header, thin neutral rules,
14 pt rhythm, Oswald retired entirely. Home shows name, date, venue, bid count, urgency and price per row. Tone: serious,
fast, money-aware.
**Removed / moved.** Imagery is demoted to a thumbnail-free list on Home (it survives on the listing screen). This is the
one direction that **adds** information: 16 text nodes per Home screenful against 12 for the others, measured.
**Why it feels polished and trustworthy.** For a *marketplace*, numbers arranged in aligned columns is the trust signal.
It is also the best of the five for the transaction screens, where density is a virtue.
**Risks.** Discovery suffers most: without art, an event is a string, and the emotional reason to buy a ticket disappears.
It is the least "premium" of the five in the sense the owner means.
**Largest text / Reduce Motion.** Naturally robust — everything is already text in rows, so growth pushes rather than
clips. No motion to lose.
**Stack reality.** Buildable today, and the cheapest of the five: it mostly deletes.

---
## 6 · Comparison matrix
Scores are B's judgement on a 1–5 scale (5 best), with the measured figures that informed them. **Implementation cost is
inverted** — 5 means cheapest.

| | Clarity | Premium feel | Brand fit | Accessibility | Impl. cost (5 = cheapest) | Home | Transactions | Account |
|---|---|---|---|---|---|---|---|---|
| **1 Gallery** | 4 | 5 | 4 | 4 | 5 | **5** | 3 | 3 |
| **2 Index** | 5 | 3 | 4 | 3 | 5 | 4 | 4 | 4 |
| **3 Charcoal** | 4 | 4 | 2 | **5** | 3 | 4 | 4 | **5** |
| **4 Liquid** | 3 | **5** | 3 | 2 | **1** | 4 | 3 | 3 |
| **5 Utility** | **5** | 2 | 3 | **5** | 5 | 2 | **5** | 4 |

Measured inputs: Home content height for four events — Gallery 2179 px, every other direction ≤ 810 px. Home surfaces —
Gallery 4, Utility 4, Index 8, Charcoal 12, Liquid 12 (6 of them blurred). Red-filled blocks on Home, Send and Checkout —
**zero in all five directions**, because in every one the only filled red is an *enabled* primary action and all three
prototype states show it disabled or pending. Home text nodes — Utility 16, all others 12.

**Brand fit** is scored against the approved system, not taste: Charcoal scores 2 because it breaks "radius 0 is identity";
Liquid scores 3 because glass is not in the system at all and the dock's approved 33 pt pill is the only existing exception.

## 7 · Recommendation
**Lead with Gallery for discovery, Utility for transactions, and take exactly one idea from Liquid.** Concretely:

- **Home, listing detail, browse:** **Gallery**. It is the only direction that makes the owner's own instinct real — the
  flyer carries the story, the card carries name, bid and date — and it costs nothing to build. Add one thing from Index:
  a date section header, so a long scroll still has structure.
- **Send, Receive, Checkout, account:** **Utility's density and column discipline**, wearing Gallery's type. These screens
  have no art to lead with, and aligned numbers are what makes a money screen legible.
- **One idea from Liquid, re-grounded after the research (§11):** text that sits over artwork gets a **dimming scrim, not
  a glass panel**. Apple's own rule keeps glass out of the content layer and sets the number for this exact case — a 35%
  dark dimming layer under bright content — so the buildable, guidance-compliant version is the scrim the app already
  renders via `experimental_backgroundImage` (three uses in `EventMedia.tsx`). Zero dependencies, and it is what I should
  have specified in the first place. Everything else glass — translucent dock, glass sheets, 18 pt radii — waits for a
  build, and then belongs on chrome only.
- **Not Charcoal as a whole**, but **keep its second accent**: an advisory notice in a muted non-red so advisory stops
  borrowing the action colour. That is one token, and it is the single highest-value idea in the whole exploration.

**Hybrid name for the record: "Gallery / Ledger".** Image-led discovery, ledger-like transactions, one shared quiet type
scale, red reserved for the single primary action, and a muted advisory accent. Buildable today with no new dependency.

## 8 · Ideas to reject, and why
1. **Glass everywhere** — now rejected on Apple's own words rather than my instinct (§11): glass belongs to the
   navigation layer, *"Don't use Liquid Glass in the content layer,"* never stack glass on glass, use it *sparingly* on
   *"the most important functional elements,"* and avoid content/glass intersections at rest. Over user artwork it is also a
   contrast lottery, and the four accessibility settings (Reduce Transparency, Increase Contrast, Reduce Motion,
   Differentiate Without Color) reshape it — automatically for system materials, and **not at all** for a hand-rolled blur,
   which is the strongest argument against rolling our own.
2. **Rounded corners as a general move (Charcoal's 12 pt)** — the approved system states radius 0 as identity. Worth
   proposing as a deliberate amendment or not at all; it is not mine to slip in as a styling choice.
3. **Retiring Oswald entirely (Utility)** — it is the brand's one loud instrument. Reduce its frequency; do not lose it.
4. **A poster feed with no date grouping** — Gallery's pure version makes twenty events a 10,000 px scroll.
5. **Hiding the price behind a tap on Home** — tested and rejected: the auction price is the reason to open the card.
6. **Collapsing the delivery blocker or the expiry line into an icon** — the owner ruled these must stay legible, and they
   are the two things a seller most needs. Same for the payment-state notice on checkout.
7. **A bottom sheet as the primary checkout surface** — a sheet implies dismissibility; a payment in flight is not
   dismissible, and `Sheet` has no drag-to-dismiss guard.
8. **Animated tab indicators, parallax heroes, shimmer** — decorative, and the skeleton's own comment already rejects
   shimmer for good reason.

## 9 · Motion specification — for Gallery / Ledger
All on RN `Animated` with the existing `v2.motion` tokens (`instant 90 / swift 180 / settle 280`, easing
`cubic-bezier(0.22,1,0.36,1)`), because Reanimated 4.1.6 is installed with **no Babel config** and no worklet has ever run
in this build. Every entry collapses through the existing `useReducedMotion()`.

| Trigger | What it communicates | Motion | Approx. timing | Reduce Motion |
|---|---|---|---|---|
| Poster enters viewport (Home) | that there is more below | opacity 0→1 only, no translate | `swift` 180 ms, staggered 40 ms | no fade; content simply present |
| Image loaded / replaced | the new file replaced the old | crossfade via `expo-image` `transition` | 180 ms | instant swap |
| Notice appears or clears | the screen changed its mind about whether you can act | height + opacity | `settle` 280 ms | instant |
| Primary action submitting | the tap was received; the wait is the server's | existing `loading` + `pendingLabel`, no new motion | — | unchanged (not motion) |
| Success on a task screen | it is done, without a modal | state block fades in while the action row fades out | 280 / 180 ms | both instant; haptic unchanged |
| Pull-to-refresh with changed rows | which rows changed | existing `usePulseOnChange` opacity dip | 350 ms | skipped (the hook already does) |
| Error that keeps the screen | nothing was lost | notice reveal only — **no shake, no bounce** | 280 ms | instant |
| Sheet open/close | where it came from | RN `Modal` slide, existing | system | existing fade |
| Navigation push | continuity | stack default, existing | system | existing `'fade'` |

Nothing in this table needs a new dependency, and nothing delays a tap.

## 10 · What B cannot verify
No device, no simulator, no screenshot of the running app; "largest text" is simulated by scaling the type tokens, with
display capped at 1.3× as the app does. Real Dynamic Type, iOS font metrics, glass behaviour under Reduce Transparency and
the live badge inset all need a device — C's lane. Research notes and their separation from these proposals are in §11,
appended when the research pass completes.

---
## 11 · Research notes — Apple (observations, then what they changed in my proposals)

Everything in 11a is **what Apple's material says**, with a link per claim. 11b is **mine**. The product research (DICE,
Posh and the contrast set) is still running and appends as 11c; where a product was not actually reached it will be
recorded as a stated gap rather than guessed at.

### 11a. Observations from Apple's own material
**Premise shift I did not know when I wrote §1-§10: iOS 27 shipped on 2026-09-14**, three days ago, and it *revised*
Liquid Glass rather than replacing it — lower default transparency, higher contrast, a user-adjustable
"ultra clear → fully tinted" control, a darkened edge with brighter specular highlights, and improvements that existing
apps get "automatically… without even needing to recompile"
([newsroom](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/),
[WWDC26 Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/),
[apple.com/os/ios](https://www.apple.com/os/ios/)).

- **What it is.** A "meta-material" that bends and concentrates light in real time rather than scattering it, with
  layered highlights, content-aware shadow, continuously shifting tint, and an interaction glow under the fingertip
  ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/),
  [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)).
- **Where it may go.** The navigation layer that floats above content. **"Don't use Liquid Glass in the content layer"**;
  never stack glass on glass; "use Liquid Glass effects sparingly… limit these effects to the most important functional
  elements"; and "in steady states, such as when an app first launches, avoid intersections between content and Liquid
  Glass" ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
  [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), WWDC25 219).
- **Two variants, never mixed.** Regular adapts and stays legible in context; Clear does not adapt and is only for
  media-rich content, where bright content needs **a dark dimming layer at 35% opacity** (HIG Materials, WWDC25 219).
- **Accessibility settings reshape it, automatically, only for system materials.** Reduce Transparency makes it
  "frostier"; Increase Contrast makes elements "predominantly black or white… with a contrasting border"; Reduce Motion
  "decreases the intensity of some effects and disables any elastic properties". **Differentiate Without Color has no
  glass-specific guidance at all** — only the general rule not to carry meaning in colour alone (WWDC25 219,
  [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color),
  [accessibilityDifferentiateWithoutColor](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor)).
- **Brand colour defers.** "Apply color sparingly"; reserve it for status or primary actions; tint the **background**, not
  the glyph; with colourful content prefer monochromatic bars or an accent with real differentiation; and to express brand
  through colour, "consider moving it into the content layer"
  ([HIG Branding](https://developer.apple.com/design/human-interface-guidelines/branding), updated 2026-09-09; HIG Color).
- **Typography.** iOS default body 17 pt, **minimum 11 pt**; support enlargement to **at least 200%**; grow meaningful
  icons with text; keep truncation minimal; switch to a stacked layout when horizontally constrained; "maintain a
  consistent information hierarchy regardless of the current font size"
  ([HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
- **Tab bars.** For navigation, not actions; keep it visible; "avoid overflow tabs"; **include labels**, single words where
  possible ([HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)).
- **Sheets.** Medium/large detents, a grabber in resizable sheets, one sheet at a time, always an alternative to Done, and
  **for long or complex flows prefer a full-screen modal over a sheet**
  ([HIG Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)).
- **Motion.** Convey status, give feedback, enrich — but "don't add motion for the sake of adding motion", **"make motion
  optional"**, **"let people cancel motion"**, avoid motion on frequent interactions, and under Reduce Motion tighten
  springs, track gestures, avoid z-axis depth
  ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
  [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).
- **Onboarding** guidance predates Liquid Glass (last updated 2024-06-10) and is flow-level: teach through interactivity,
  prefer contextual tips to one upfront flow, keep tutorials skippable and don't repeat them, **postpone nonessential
  setup**, ask permissions at first use of the dependent feature, and **"avoid displaying licensing details within your
  onboarding flow"** ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)).
  The 2026-06-08 [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles) add:
  make a guided flow "easy to skip or escape".
- **React Native reality.** `expo-glass-effect` (first-party, introduced in **Expo SDK 54**, currently 57.0.3) exposes
  `GlassView`/`GlassContainer` over `UIVisualEffectView`, iOS 26+ with a plain-`View` fallback
  ([Expo SDK 54 changelog](https://expo.dev/changelog/sdk-54),
  [GlassEffect docs](https://docs.expo.dev/versions/latest/sdk/glass-effect/)). Native chrome rendered through
  `react-native-screens` picks the material up automatically. **`expo-blur` is not a substitute** — it scatters light and
  inherits none of the adaptivity or the accessibility behaviour
  ([BlurView docs](https://docs.expo.dev/versions/latest/sdk/blur-view/)). And the opt-out matters for planning:
  `UIDesignRequiresCompatibility` is **ignored when you build against iOS 27 or later**
  ([docs](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)).

### 11b. What the research changed in my own proposals — and three findings that hold whatever direction wins
**Changed** (both corrected in place above): the Liquid direction's cost was overstated as bespoke native work when a
first-party package exists for this app's SDK; and my "one Liquid idea" was glass in the content layer, which Apple's
guidance rules out — it is now specified as a dimming scrim, with Apple's own 35% number, buildable with zero dependencies.

**Findings independent of direction, all verified in our code by B:**
1. **Our `micro` token is 10 pt** (`src/theme/v2.ts:141`), **below Apple's stated 11 pt iOS minimum**. It is used for every
   eyebrow, badge and metadata key in the app. The calm pass already proposed replacing it with an 11 pt `eyebrow`; this
   turns that from taste into a guideline floor.
2. **The dock has no visible labels** — `AdaptiveDock` carries `accessibilityLabel` per item (`:144`) but renders icons
   only, while the HIG says a tab bar should include labels. Worth an owner decision, since the label-less dock is an
   approved visual direction; the point is that it trades against a stated guideline, which should be recorded rather than
   discovered later.
3. **Signup shows the Terms and Privacy disclosure inside onboarding** (`app/(auth)/signup.tsx:288-293`), which Apple's
   onboarding page advises against. This is very likely a deliberate legal/compliance decision that outranks the
   guideline — recorded as a tension for the owner, not as a defect.

**Where Apple's material backs choices I had already made on other grounds:** red reserved for the single primary action
(brand colour defers, tint backgrounds not glyphs); rejecting a sheet as the checkout surface (prefer full-screen modal for
long or complex flows, always an alternative to Done); the motion spec's restraint (make motion optional, let people cancel
it, no motion on frequent interactions); and keeping Reduce Motion support central rather than optional.

**One roadmap fact for A rather than for design:** this app is on Expo SDK 54 / RN 0.81.5. Moving to an SDK that targets the
iOS 27 SDK brings the new design whether or not anyone has audited for it, because the compatibility opt-out is ignored at
that point — and Expo SDK 57 additionally requires the scene-based lifecycle. That is a release-planning input, not a design
decision, and I have sent it to A rather than acting on it.
