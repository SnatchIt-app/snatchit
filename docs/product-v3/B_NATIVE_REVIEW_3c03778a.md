# B — native review at `3c03778a` · batch 6

**Candidate** `3c03778ac55e2c0f33233e4cd90e634805e28e2a` · `v3/midnight-app`. Serving tree HEAD
**matches**, `git status --porcelain` **empty**. Metro `:8081`, cwd `/Users/josetascon/snatchit-refund`.
Device `SN V3 393x852` (`iPhone-16`), UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`, iOS 26.5 (23F77).
**Native development build.** No production call, reservation, payment or fixture write.

C's captures copied to `native/Coperated/3d4d6a4a/`. **Applicability:**
`git diff --name-only 3d4d6a4a..3c03778a` outside `docs/` and `native/` is **empty** — the captures
describe the current candidate exactly.

## Verified independently — the price fix works

I re-measured ink heights from C's frames rather than accepting the figures. **Both headline numbers
reproduce**: a band of **63.7 pt** in the A3XL feed-row frame and **58.0 pt** in the long-amount
frame, matching C's `$132.00 = 63.7` and `$1,716.00 = 58.0`.

| | default | 3XL | A3XL |
|---|---|---|---|
| `$99.00` / `$132.00` | 18.3 pt | 25.0 pt | **63.7 pt** |

The amount was held at **24.3 pt** at `91a5a58c` regardless of size; it is now **2.6× larger** at
A3XL and tracks the requested size. On screen it is the dominant element rather than the
least-magnified one. **The batch-4 finding is closed.**

**Long amounts hold up.** `$1,716.00` renders at 58.0 pt — 91 % of the shorter amount, so
shrink-to-fit engaged — with **every digit, the thousands separator, the cents and `all-in` all
present**. Shrink-to-fit has not silently recreated the readability failure: 58.0 pt is still 2.3×
the old capped size.

## Verified — Listing scroll-end clearance, and the bottom gap accounted for

The slice I reported on `Mobile transfer · DICE` is **fixed**. At the scroll end the last content
clears the footer in both the default and A3XL Light frames.

**The bottom gap is accounted for arithmetically, not estimated.** Measured on the device frame:
CTA top **688.0 pt**, footer running to the screen bottom → **height 176.3 pt**. Both match C's
figures exactly. Last content to footer top = **209.7 pt** at A3XL, **205.7 pt** to the CTA at
default. Clearance is the footer's measured height plus a gap, so ~200 pt of empty space *at the
scroll end* is the intended consequence of clearing a 176.3 pt footer — **not dead space, and not a
defect.** No further spacing change is warranted on this evidence.

*(My Dark scroll-end gap figure of 4.0 pt is an artefact of my own detector reading the black canvas
as ink. Discarded, not reported.)*

## Verified — the event name is reachable and readable

`listing-a3xl-light-eventname-Coperated.png`: **"Neon Choir" renders complete** across two lines at
A3XL, above the CURRENT BID panel. The owner's condition is met — the name need not be above the
fold, and scrolling exposes it in full.

## FAILED — the bid-activity amount is clipped at A3XL

**Commit** `3c03778a` · **screen/state** Listing detail, Bid activity list, A3XL, Light
(`listing-a3xl-light-scrollend-Coperated.png`) · **expected** every digit of a monetary amount
present, never clipped · **observed** the leading bid renders as **`$99.`** — the cents are gone.

**Measured:** ink reaches **x = 387.7 pt** on a 393 pt screen, with **984 px of ink inside the
right 16 pt gutter**. The amount overflows its container and is cut at the screen edge.

**Root cause, located in source.** `src/components/listing/BidActivity.tsx:81` renders the amount as

```
<Text style={[textStyle('price'), styles.amount, isTop && styles.amountTop]}>
```

— **no `maxFontSizeMultiplier`, no `numberOfLines`, and no shrink-to-fit.** Every other money
surface in this batch got the `amountFit` treatment (`HomeFeature`, `FeedRow`, `TransactionPanel`);
**`BidActivity` was missed.** At A3XL `textStyle('price')` scales freely, the row keeps its
horizontal name-left / amount-right form, and the amount runs off the edge.

This is the same class the owner ruled on — *never clip a monetary amount's digits* — on the one
surface the sweep did not reach. **C: apply the same treatment here, and stack the row as the other
surfaces do.** The bidder name also ellipsises to `Y…`, which is cosmetic beside this.

## Untested — named, not guessed

| check | why |
|---|---|
| **Event date and time in full on the Listing detail at A3XL** | the owner's new rule: a list row may shorten the date if the detail screen carries it whole. C's event-name frame is scrolled past the date line, so I have **not seen it** and do not claim it. |
| **The Home FEATURE's own amount at A3XL** | C reports every drag from inside the feature registers as a tap and opens the listing. The feed row exercises the same `amountFit` branch, but that is an inference. |
| **Authenticated consumer Home · spoken VoiceOver** | unchanged; blocking nothing. |

**For one short C-operated window**, two captures close the first two rows:

1. **Listing, A3XL, Light and Dark — scrolled to the identity line above the event name.** Is the
   full event date *and time* present and unclipped?
2. **Home feature amount at A3XL** — if a drag cannot be made inside the feature, a capture at a
   content size just past the stacking threshold, where the feature's amount is still on screen at
   rest, would do instead.

## Carried forward unchanged

Poster geometry and whole-poster rendering, the 4:5 frame, gradient removal, Listing poster
clearance, the vector icon set and the Filters glyph, Option B at rest, and reservation feedback —
all verified at `d5217530` / `91a5a58c`, none of them touched by the commits since.

**Reviewed · Failed · Untested are distinguished above. Not whole-app acceptance.**

---

# Batch 7 — refusal, profile, error/offline groups · simulator handed to C

Same candidate `3c03778a`, device and serving tree; HEAD matched and clean at start and end.
Captures in `native/3c03778a/`.

## FAILED — the public profile prints `null% transfer success`

**Commit** `3c03778a` · **screen/state** public profile, Trust & activity ·
**expected** a real percentage, or no percentage at all when there is no history ·
**observed** the literal string **`null% transfer success`**, beside a "Needs review" chip and an
empty progress bar.

**Reproduced in `profile-default-light.png`, `profile-no-listings-light.png` and
`profile-default-dark.png`** — across variants and both appearances.

**Root cause.** `src/lib/profile/reputation.ts`, the function's **final** return:

```ts
return { tier: 'needs_review', label: 'Needs review', blurb: `${ratePct}% transfer success`, … };
```

`ratePct` is `denom > 0 ? Math.round(rate * 100) : null`. That interpolation is **unguarded**,
while the sibling `needs_review` branch forty lines above guards the same value:
`${ratePct == null ? '' : ` · ${ratePct}% success`}`.

**It is reachable with correctly-shaped real data, not only through the fixture.** `completed_sales`
and `seller_terminal_total` are different columns. A seller with `completed_sales >= 5` and
`seller_terminal_total = 0` gives `rate = 0` and `ratePct = null`, fails all three tier gates
(each needs `rate >= 0.95`), and falls to that final return.

**Secondary, and please do not fix only this one:** the harness fixture is also malformed —
`app/_dev/v3-profile.tsx:41` builds `TRUST` with `completed_sales` / `on_time_rate` / `disputes` /
`cancellations` and casts it `as unknown as ProfileTrustStats`, whose real fields are
`seller_terminal_total`, `seller_terminal_successful` and `disputes_lost`. Correcting the fixture
alone would hide the unguarded branch rather than fix it.

## UNTESTED — the Edit refusal group is unreachable signed out

All five variants — `not-found`, `not-owner`, `has-bids`, `inactive`, `read-failed` — render a
**byte-identical** screen: "Sign in required / You need to be signed in to edit a listing. / Back".
Verified by md5 of the content region across the five Light captures: **all `da44e338a711`**.

The guard itself is correct and is C's intended behaviour. But it short-circuits before the variant
is read, so **this group cannot be reviewed without an authenticated session** — the same blocker as
consumer Home. Recorded as untested, not as a pass.

## REVIEWED and sound

| state | result |
|---|---|
| profile `stats-unavailable` | "Seller history unavailable / We could not load this seller's history. **This is not a record of zero sales.**" + Retry. The read failure is explicitly refused the reading of "zero" — correct, and the product truth stated plainly. |
| profile `not-found` | "Profile unavailable / This profile isn't available." Exit is the header back control. |
| Listing `error` | "We couldn't load this listing / **Nothing was sent from this screen** — we couldn't read the listing…" + Try again. The money reassurance is right. |
| Listing `offline` | "You're offline / Check your internet connection and try again." + Retry. |

Both Listing states verified in Light and Dark.

## Artwork group

Carried forward from batch 1 at `d5217530` and unaffected since: every `?art=` case matched against
its own source with a mismatched-fixture control, the 4:5 frame, containment without crop or
stretch, and the missing-artwork plate. No re-run.

---

## Simulator and Metro handed to C

**Done at `3c03778a`.** `git -C /Users/josetascon/snatchit-refund rev-parse HEAD` unchanged and
`git status --porcelain` empty at start and end — no capture in doubt.

C's two fixes, plus what I still need captured:

1. **Bid activity** — stack the row and keep the whole amount, cents and separators included, using
   the same responsive treatment as the other money surfaces. `BidActivity.tsx:81`.
2. **Listing date/time** — let the complete date and time wrap; the detail screen must carry it in
   full at large text.
3. **Capture both fixes at A3XL, Light and Dark, with an ordinary and a four-figure amount.**
4. **The Home main-event amount at A3XL** — still untested. A smaller-size capture is supplemental,
   not a substitute. If the drag cannot be made, state the exact blocker and leave it untested.
5. **Worth adding to the same window:** the `null%` fix above, in `reputation.ts` *and* the fixture.

**Preserved and not to be changed on the existing evidence:** the poster, navigation placement, the
footer, Listing spacing and reservation behaviour.

**Outstanding, blocking nothing:** authenticated consumer Home, spoken VoiceOver, and the Edit
refusal group — all three gated on a session or an inspector I do not have.
**The app is not fully accepted.**
