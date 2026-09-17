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
**Stack reality.** **This is the one direction that cannot be built with what is installed.** `expo-blur` is not in
`package.json`, and a true iOS 26 glass material needs either that or a newer native glass API; a real Liquid Glass
surface implies a native module, a Babel/config change and a new build — and this build has never run a Reanimated
worklet either. Treat it as a direction to *aim at*, not to start.

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
- **One idea from Liquid, and only one:** the **frosted panel behind text that sits over artwork**, used *only* where text
  must overlap an image. It solves a real legibility problem. Everything else glass — the translucent dock, glass sheets,
  18 pt radii — waits for a build that can carry it.
- **Not Charcoal as a whole**, but **keep its second accent**: an advisory notice in a muted non-red so advisory stops
  borrowing the action colour. That is one token, and it is the single highest-value idea in the whole exploration.

**Hybrid name for the record: "Gallery / Ledger".** Image-led discovery, ledger-like transactions, one shared quiet type
scale, red reserved for the single primary action, and a muted advisory accent. Buildable today with no new dependency.

## 8 · Ideas to reject, and why
1. **Glass everywhere** — Apple's own posture is chrome-only, and over user artwork it is a contrast lottery. Needs a
   dependency the app does not have, and an opaque fallback means maintaining two systems.
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
