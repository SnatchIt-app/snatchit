# V3 acceptance record (maintained by E)

One row per owner-settled item. Each row pairs the **implementation commit** (C, `v3/midnight-app`)
with the **independent review** (B) **at the same commit**, and lists the native checks still owed.
A row closes only when implementation, B's review and the required native evidence all name the
same commit. "Pending" means not yet evidenced. It does not mean failed.

Evidence classes: **web** = B's web render (development evidence) · **sim** = native simulator
capture on `SN V3 393x852` (iPhone 16, 393×852 pt @3×, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`,
iOS 26.5 23F77, Xcode 26.6 17F113) · **device** = owner's phone. Neither web nor sim is device
acceptance.

| # | Owner ruling (date) | Governs | Implementation commit | B review (commit · evidence class · file) | Native checks owed | Status |
|---|---|---|---|---|---|---|
| R-1 | **Listing footer, Option B** (2026-09-25). When bidding and Buy Now are both available: Place a bid first, full-width, red, minimum all-in inside; Buy Now second, full-width, outlined, quantity-aware label + price + sub-line. Supersedes the Buy-Now-first hierarchy. Other states keep their own valid actions. Eligibility and behaviour unchanged | `comparisons/footer_arrangements_91062ab1.png` (Option B); map §*SETTLED — listing footer* | `12be25d6`: the resolver (`detailState`) selects the bid as primary when both are available; `ListingDetailScreen.tsx` changes are comments only; per-state tests in `listing-detail-state.test.ts` | Selection render only: `91062ab1` + harness patch · web · `V3_FOOTER_AND_POSTER_91062ab1.md`. **Not** a review of implemented code | Dynamic Type (largest standard + accessibility sizes, no truncation of label, minimum, "Buy … now · $X", sub-line); wrapping; safe area under the stacked footer; Light + Dark | Open |
| R-2 | **Home feature, full 4:5 poster** (2026-09-25). Complete poster in a full-width 4:5 frame, no height cap yet; non-4:5 images fitted without crop or stretch on a deliberate background; name, date, venue, price and listing details in a separate area below the poster; no app text or badges on the poster; overlay gradient removed; header and filter controls unchanged | Owner ruling text; map Home row | `e902f59a`: the poster renders with no children (nothing drawn on it), the slot scrim is `none`, and the identity block is below the poster in canvas inks (E source check). Earlier `ec61bfa7`–`cbb2df6b` still overlaid | pending (B): native renders, Light + Dark, with a text-heavy flyer, a photograph, missing artwork, plus the corner-marker fixtures. Report how much of the next section is visible at 393×852 | Native fonts; safe area; Dynamic Type on the identity block below the poster; System appearance switch | Open |
| R-3 | **Event artwork 4:5 throughout** (2026-09-25, authorised direction). Full poster content preserved; avatars unchanged | Owner direction; E's baseline inventory at `a5c0bfc6` | Group 1 of 4: `ec61bfa7` (media contract: 10 slots at 4:5 + `fit`; requests carry width+height with `resize=contain`; Home and Search frames). Group 2: `99dd6f36` (Create picker no longer crops: `aspect: null`, so no `allowsEditing`; helper "JPG or PNG, 4:5 portrait — any other shape is fitted whole, never cropped."; listing hero frame 4:5 at ~491pt with the identity still overlaid; My listings card). Group 3: `59658b1a` (Bids and Tickets; the past-ticket 64×64 clipping wrapper removed). Group 4: `cbb2df6b` (Send, receive, checkout OrderIdentity, public profile). All four landed; the tree is clean at `cbb2df6b` | pending (B), per slot, including the corner-marker fixtures | Picker behaviour on iOS (no crop that discards poster pixels); per-slot rendering | Open |
| R-4 | **Listing identity beneath the poster** (2026-09-25). The listing's date line, name and provenance label sit below the 4:5 poster; no app text or badges on the poster's printed content; back/overflow navigation stays reachable | Owner ruling; B `V3_FOOTER_AND_POSTER_91062ab1.md` Part 2 | `f3f08930` (`ListingHero`, E source check) | pending (B); native Listing artwork cases blocked until the Listing harness gets `?art=` (see restarted loop) | Scrolling; safe area under navigation chips; Dynamic Type on the moved block; Light + Dark | Open |

## Status index (E, 2026-10-06 23:25). Three tracks, kept separate

### Track 1: B's completed native evidence (`d5217530`; window closed `17c7e670` and released to C)
| Check | Result | Evidence |
|---|---|---|
| Home artwork per fixture (7 cases), 4:5 frame, no gradient, nothing on the poster | **pass** | B `c9d6f0d7`, 14 sim captures |
| Option B footer at rest | **pass** | B `f235ddb7` |
| Reservation feedback (R-1 busy state) | **pass** | B `f235ddb7`, `listing-reserving-*` |
| Filters glyph (F-91-6) | **pass** | B `f235ddb7` |
| Remembered name collapse | **not reproduced, withdrawn** | B `f235ddb7` |
| Home identity at 3xl / a3xl | **fail** ("Ends…", "current bid, al…") | B `f235ddb7` |
| Listing poster at rest | **fail**: complete 4:5, but covered by the banner (79 pt) and the nav chips | B `17c7e670`, measured |
| Listing panel at a3xl | **fail** (clipped amount "$95.0"; C found it in a C-operated capture) | C `d301ccb4` message; B's a3xl capture superseded |
| VoiceOver, scrolling, signed-in Home | **not established** (no a11y inspection or touch in B's session; B does not type credentials) | B `17c7e670` |

### Track 2: Successor, affected checks (final `91a5a58c`; code = `7c9b270b`)
- **Carry from `d5217530`:** Home artwork per fixture, frame, no gradient, nothing on the poster;
  Filters glyph.
- **Repeat:** Home identity block (default, 3xl, a3xl); harness next-section figure; all of Listing
  (poster clear of the banner, nav outside printed artwork, R-4, artwork cases, footer,
  `?reserving=1`, panel at large text, safe areas).
- **New (C-operated, B-reviewed):** B's five cases: feed-row title at 3xl/a3xl; below-fold identity
  at a3xl; Listing breakdown and activity; signed-in consumer Home at rest and scrolled one section;
  price-caption accessibility exposure. Visible text and spoken text are recorded separately.
- **New (C owner evidence, then B):** Edit refusals; Listing failure/offline; public profile;
  Send/Receive not-found; the six harness-art screens.
- **The poster fix completes the existing artwork requirement (R-3 "full poster content preserved",
  2026-09-25). It is not a new design decision.** B's diagnosis applies: fix layout and safe-area
  positioning, not cropping or image scaling. Navigation sits outside the printed artwork.

### Track 3: Remaining whole-app coverage
See **Remaining consumer screens** below. No screen outside Home and Listing is accepted, and no
blanket whole-app acceptance applies.

## Candidate under native review: `d52175303f22a575b80f005f38c0e8555be0dbdc` (named 2026-10-05; E verified 2026-10-06)
- **Implementation (C), checked by E.** `v3/midnight-app` in `/Users/josetascon/snatchit-refund`
  is at `d5217530`, and `git status` is clean.
  - Range `168e794a..d5217530`: `6100dee1` (the Home feature fix, Listing `?art=`, the shared
    `src/lib/media/harnessArt.ts`, and integration of the reserving seam), then `d5217530`.
  - `d5217530` adds only `docs/product-v3/V3_SUCCESSOR_HANDOFF.md`.
  - `git diff f3f08930..d5217530` touches no native or install file (`ios/`, `android/`,
    `app.json`, `package*.json`, `patches/`, `scripts/`). So reloading the existing dev client
    serves this candidate, and no rebuild is needed.
  - C reports 172 files / 2921 tests passing and a clean typecheck. That is C's report; E did not
    re-run them.
- **Metro.** C operates it. It is pid 2172, started 2026-09-26 16:56, cwd
  `/Users/josetascon/snatchit-refund`. It was not restarted, because it serves the tree whose
  contents advanced.
- **Push: not done.** `origin/v3/midnight-app` is still `404bce38`. C reports the authorised push
  was blocked by C's session permission guard. **This is an owner action.**
- **C's evidence is WEB evidence from the implementation owner, not native and not B.** The archive
  is `/Users/josetascon/snatchit-v3-evidence/6100dee1/`, outside the repo. E reconciled it with the
  final commit:
  - **Code is identical to the final commit.** `6100dee1` is an ancestor of `d5217530`, and
    `git diff 6100dee1 d5217530` is that one docs file. Every code-dependent web result at
    `6100dee1` therefore describes `d5217530`'s code.
  - **The archive does not record its own sha or clean status.** Its tie to `6100dee1` rests on
    the folder name and timestamps: files written 23:04–23:05, after the `6100dee1` commit (22:27)
    and before `d5217530` (23:06). That is attributable but not self-proving.
  - **The probe** loaded `localhost:8081/_dev/v3-home?...&appearance=dark` from Metro's web
    target.
  - **Proven per fixture (Home, Dark only, 393×491 frame):** `flyer`, `markers`, `tall`, `wide`,
    `square`, `subject`, `subject-wide` and `missing` each **MATCH**
    (`logs/feature-fixture-proof.txt`). Not covered: `photo`, `all` and Light.
  - **Listing** (`flyer`, `tall`, `subject-wide`, `missing`): claimed in the handoff only. The
    archive holds the probe script (`probe-listing.js`) but **no output log**, so it is not cited
    as evidence.
- **The earlier native captures, Xcode build log and `npm ci` log at `f3f08930` are lost.** They are
  not cited.
- **B's native review: pending.** No B commit after `ca00a250`. `docs/product-v3/native/` is
  empty at E's check (2026-10-06).
- **Routes:** `V3_SUCCESSOR_HANDOFF.md` at `d5217530`. Listing needs `screen=listing`.

**B native batch 1 (`c9d6f0d7`, 2026-10-06): Home at `d5217530`**
- **B's own start check:** HEAD `d5217530`, clean, contains `168e794a`.
- **Device:** `SN V3 393x852`, iOS 26.5 23F77. Metro pid 2172 (C).
- **The f3f08930 feature-selection defect is fixed.** Each of the 7 required `?art=` cases paints
  the feature itself. B matched each against its own source file with a mismatched-fixture
  control: diffs 0.5–4.1 against controls 8.4–84.4.
- **Geometry:** frame 490.3–491.0 pt at 393 pt (w/h 0.8004–0.8015). No crop, no stretch. 9:16 is
  pillarboxed; 1:1 and 16:9 are letterboxed.
- **No gradient:** the poster's bottom third differs least from its source.
- **No app text or badge on the poster.** The identity sits below it, in canvas inks.
- **Next section (native):** the rule is at 790.0 pt, with 62.0 pt of the following row visible,
  in both appearances.
- **Appearance:** System appearance switching works, verified by B. `?appearance=` persists as a
  stored preference, so B pins it per capture.
- **Device signed out:** B typed no credential. The `_dev` harness renders without auth.
- **E check:** all 14 PNGs are 1179×2556. E viewed `home-feature-wide-light.png` and
  `home-feature-flyer-dark.png`; they agree with B's description. The serving tree was still
  `d5217530` and clean after the batch.
- **Letterbox position: resolved as deliberate (C, 2026-10-06; E verified in source at `d5217530`).**
  Letterboxed art is positioned by the focal point, default y=0.40 (`src/lib/media/url.ts:76`
  `DEFAULT_FOCAL`, passed as `contentPosition` for both contain and cover at
  `EventMedia.tsx:265-273`). So 40% of the vertical slack sits above the art. A source taller than
  4:5 has no vertical slack and reads as centred. Stored art can carry its own focal point. Not a
  defect.
- **E observation passed to B, not a finding:** in both viewed captures, the first "This week"
  row's event name ("Midnight Arcade presents The Foundry Warehouse S…") is clamped at two lines
  with an ellipsis, at default text size. This may be the remembered truncation. B decides whether
  it reproduces and whether it is a defect; the design may intend a two-line clamp.
- **Still owed for Home:** Dynamic Type (largest standard and accessibility sizes) and safe areas.

## C's window: served `3d4d6a4a5bbcd50448dfdaa56d58e892aa774ed3` (2026-10-07 22:43; supersedes `453a1c82`; not yet handed back)
- **`3d4d6a4a`** (C, measured at a3xl): the footer is 176.3 pt tall, but the old clearance was a 96 pt `scrollTail` plus 64 pt (about 160 pt), a 16 pt shortfall. Clearance is now only the measured footer height plus a gap; the spacer and the constant are removed, and a test pins their absence. C reports that its first attempt left about 300 pt of dead scroll. `ListingDetailScreen.tsx` only, plus a test. Not pushed yet (origin is still `91a5a58c`).
- **Contents:** `338268c5` (price fix) + `453a1c82`.
- **Footer slice: confirmed a padding defect and fixed** (C).
  - Cause: the scroll ended its content with a constant padding, while the fixed footer grows with
    text size.
  - Fix: `StickyBar` reports its measured height through a new optional `onLayout`, and
    `ListingDetailScreen` pads by that height plus a gap.
- **`?amounts=long` added to the Home harness** (×13 on bid and Buy Now amounts) for the owner's
  longer-amount check.
- **Relevant diff from `91a5a58c` (E):**
  - **Listing no longer carries.** `ListingDetailScreen.tsx` changed (scroll padding), so the
    Listing scroll and footer checks repeat. The poster clearance itself is unchanged, since
    `ListingHero` is untouched.
  - `StickyBar` change is additive (a new optional prop, no deletions besides the signature line).
    Its other users (Create, Edit listing, settings) don't pass it.
  - The `v3-home.tsx` change is inert unless `amounts=long`, and the art path is unchanged, so Home
    artwork evidence still carries.
- **Awaiting:** C's measurements and captures, then a committed handback naming one sha.

## B batch 5 at `91a5a58c` (`cb242fd8`, 2026-10-07): C-operated captures reviewed; **simulator handed to C**
- **Applicability (B, checked by dependency):** the `7c9b270b` Home set carries exactly (no source
  delta to `91a5a58c`). The `94ac8b4f` Listing set carries, because the Listing screen reaches
  neither `FeedRow` nor `HomeFeature`. The files are copied to `docs/product-v3/native/Coperated/`,
  so the review doesn't depend on C's worktree.
- **Case 1, feed row at 3xl: PASS** (C-operated, B-reviewed). Price, "all-in" and the end time are
  each complete on their own line.
- **Case 2, a3xl:** the amounts and "all-in" survive, and the "al…" clip is fixed. The title, venue
  and bid count are cut with "…". B records that as **degradation, not a defect**, because the row
  stays identifiable. It corroborates the batch-4 price-size finding.
- **Case 3, Listing scrolled:** default is complete. At a3xl, the stacked values are complete, but
  **"Mobile transfer · DICE" is sliced by the fixed footer** (CTA top edge at 688.0 pt).
  **Candidate defect:** B can't tell insufficient bottom padding from a mid-scroll frame. One
  scroll-end capture settles it.
- **Listing event name at a3xl:** not established, and not claimed.
- **Handoff:** B's capture group is complete at `91a5a58c` (serving tree matched and clean at start
  and end). **The device and Metro `:8081` belong to C** from `cb242fd8`.
- **Captures B asked C for:**
  1. Listing at a3xl, Light, scrolled to the end: does the last fact clear the footer?
  2. Listing at a3xl, Light, scrolled to the event name.
  3. The same two in Dark.
  4. Home and feed row at the three sizes after the price fix, plus a longer amount (`$1,234.56`).

## B native batch 4 at `91a5a58c` (`a4e546d0`, 2026-10-07 22:03; `B_NATIVE_REVIEW_91a5a58c.md`)
- **B's start check:** HEAD `91a5a58c`, clean, contains `d5217530`. B discarded three launcher
  frames (the dev client had fallen back to `:8083`). Every capture helper now asserts that the
  sandbox banner is present.
- **Listing poster clearance: CONFIRMED FIXED (sim).**
  - Banner 0–78.7 pt.
  - Navigation strip on plain canvas 79.0–139.0 pt.
  - Poster 139.3–629.3 pt (w/h 0.8020); whole-poster contain diff 2.8.
  - The "From a fan" chip moved below the poster. Nothing covers printed content.
  - E viewed `listing-live-flyer-light-dflt`: agrees. **E note for B:** at rest, the event *name*
    now sits below the fold, hidden behind the footer; only the date line is visible. B should say
    whether R-4 needs the name on the first screen.
- **Footer and `?reserving=1`: still correct (sim)**, both appearances. The footer is complete and
  unsplit at a3xl. No reservation made.
- **Price at large text: complete, but NOT readable at the requested size (B finding).**
  - Ink height: 18.7 pt at default, 24.3 pt at 3xl (×1.30), and capped at 24.3 pt at a3xl. The name
    reaches 88.0 pt there, so the price is about 28% of the title's height.
  - B recommends removing the cap in the stacked form and letting the layout bound it. If space runs
    out, wrap the caption, never the digits.
  - This confirms E's earlier observation. **Open, for C.**
- **Still open in B's review:**
  - Review of C-operated captures (located, not reviewed).
  - Search at large text.
  - The new refusal, error and profile fixtures.
  - Remaining artwork fixtures.
  - Signed-in Home (pending a session).
  - Spoken VoiceOver (no inspector).
- **Window:** B has **not** handed back after batch 4.
- **C's fix for the price finding** exists only in C's worktree, uncommitted. It removes the cap in
  the stacked form only, keeps the amount on one line with `adjustsFontSizeToFit` (minimum 0.6), and
  lets the caption give way first. It needs a device window, which B has not released.
- **C's price fix committed:** `338268c5311a6722c8f37a3908b22ae9261a1e07` (`v3/consumer-batch2`,
  descends from `91a5a58c`). It is **not served**; the serving tree stays at `91a5a58c`.
  - E verified the diff: code files are `HomeFeature.tsx`, `FeedRow.tsx` and `typography.ts`
    (numstat 9/0, additions only); the rest are tests (typography mock lines and the home-components
    test).
  - **Carry from `91a5a58c` to `338268c5`:** all Listing confirmations (poster clearance, footer,
    reserving, panel and fact rows), because none of their files changed and the shared typography
    file only gained lines.
  - **Repeat at `338268c5`:** the Home feature identity price at default, 3xl and a3xl, and the
    feed rows, including Search, which renders `FeedRow` (`explore.tsx`).
  - **Order, owner-confirmed 2026-10-07 (bounded handoff; no further owner approval needed):**
    1. B finishes its **current** capture group, commits it and hands the simulator to C in a
       committed line. The rest of the unaffected-screen backlog does not have to finish first.
       While C holds the device, B reviews the existing C-operated captures.
    2. C runs the suite with the device down, then serves one clean candidate. C measures the
       **rendered price size** at default, largest standard and largest accessibility, for `$99.00`
       **and representative longer amounts**. Every digit and "all-in" must be kept, and
       shrink-to-fit must not silently recreate the readability failure. C should give the price
       layout space before shrinking it. C then hands the simulator back.
    3. B reviews Home and Search at that candidate, then continues the remaining groups.
  - **Listing, R-4 (owner, 2026-10-07):** the event name does not have to be above the fold at the
    expense of the full 4:5 poster. **Acceptance test:** the name is fully reachable and readable
    by scrolling, and the bottom padding clears the fixed footer. If scrolling cannot expose it,
    that is a defect. The poster design is not reopened.

## Successor final: `91a5a58c1d54a0c98ef353a6d5f7b53dfb68861c` (C, 2026-10-07 00:12; E verified)
- **Code** is identical to `7c9b270b`. `91a5a58c` adds only the handoff update and captures. The
  serving tree is clean.
- **Pushed.** `origin/v3/midnight-app` and `origin/v3/consumer-batch2` = `91a5a58c`, verified with
  `git ls-remote`. The earlier push gap is closed.
- **C-operated captures, not yet B-reviewed:**
  - Home cases 1 and 2 were retaken at `7c9b270b` (`native/7c9b270b/`).
  - Listing case 3 stays at `native/94ac8b4f/`. E verified that
    `git diff --name-only 94ac8b4f 7c9b270b` lists only `FeedRow.tsx`, `HomeFeature.tsx` and their
    test, so the Listing surfaces did not change and case 3 carries.
  - The superseded `94ac8b4f` Home captures were removed from the tree. They are preserved in git
    history at `c75b1c68` and are not evidence for this candidate.
- **E observation on `case2-home-a3xl-light-identity` (for B; not a verdict).**
  - Amounts are complete: "$99.00", and "$132.00" with "all-in".
  - Because the numeral is capped at 1.3× while the caption and meta lines scale fully, **at a3xl
    each price renders smaller than its own caption and the surrounding text**. The amount becomes
    the least prominent line in its block.
  - The feed row also still cuts "2 × GA · 11…" (bid count), the date ("Thu 8 Oct ·…") and the title
    ("Arcade pr…").
  - B judges whether the inverted hierarchy meets the readability rule. The alternative is a layout
    that lets the numeral scale on its own line without splitting.
- **Cases 4 and 5:** unchanged (blocked, and partly established in source).
- **Tests (C's report, not re-run by E):** 174 files / 2976 tests, exit 0, at `91a5a58c`, with the
  simulator shut down. C notes that runs with the simulator booted fail in differing sets on 5 s
  timeouts, so captures and the full suite can't be trusted at the same time on this machine.
- **Window: C has released the device and Metro for B's review** (C message, 2026-10-07). It is
  booted at large/light with the app launched, serving `91a5a58c`, clean. **B's review at
  `91a5a58c` is pending** until B starts and commits.

## Successor now `7c9b270b7e2c098ba352ee11ee9560b362669ffc` (served 2026-10-07 00:06; supersedes `22835964`)
- **What changed.** `7c9b270b` stops stacked price numerals wrapping mid-number ("$132.0" / "0").
  The price numeral in `FeedRow` and in `HomeFeature` now takes
  `maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}`, which is 1.3 (`src/theme/typography.ts:125`).
  The surrounding text still scales fully, and the spoken label carries the full amount. Serving
  tree clean.
- **For B to judge (E note, not a verdict):** this caps the **price numeral's** growth at 1.3× of
  the user's text size. C cites it as the app's existing treatment for display type. The owner's
  instruction was "wrap or adjust its layout", and C's own earlier note said capping refuses a
  request for larger text. B decides whether a capped but complete numeral meets the readability
  rule at 3xl and a3xl.
- **Carry/repeat:** unchanged from `22835964`. The Home feature identity and feed rows already
  repeat. The feature artwork checks still carry, because the numeral sits below the poster.

## Successor now `22835964997f31acd73d49b96ead6eccea84f01d` (served 2026-10-07 00:00; supersedes `c75b1c68`)
- **What changed.** `22835964` changes only `FeedRow.tsx` (plus a test). Above
  `IDENTITY_STACK_SCALE`, a row's text and price share one column, and the price block is not
  capped. This fixes the a3xl "$132.0…" / "all-i…" clip E saw in C's case 2 capture. The title and
  date clamps are deliberately left for B and the owner to judge (case 1). Serving tree clean.
- **Relevant diff from `c75b1c68`.** `FeedRow` renders the Home feed rows and the Search results
  (`app/(tabs)/home.tsx`, `explore.tsx`). `HomeFeature` mentions `FeedRow` only in comments.
- **Carry/repeat effects:**
  - The Home feature checks are unaffected and still carry.
  - **C-operated cases 1 and 2 at `94ac8b4f` are superseded for the feed rows.** Their feature
    identity content still describes the feature, but the rows must be re-captured at `22835964`.
  - Case 3 (Listing) is unaffected.
  - The harness next-section figure was already a repeat.
  - Search results now also need a row check at large text.

## Successor named: `c75b1c687e9f9b607c039fc07e9a91e70ede6b88` (C, `docs/product-v3/V3_BATCH2_HANDOFF.md`; E verified 2026-10-07)
**Implementation (C).**
- `v3/midnight-app` and `v3/consumer-batch2` both point at `c75b1c68`. The serving tree is clean.
- `c75b1c68` adds only the handoff doc and `native/94ac8b4f/` captures to `94ac8b4f`; no code
  changes. So code evidence at `94ac8b4f` describes `c75b1c68`.
- No native file has changed since the installed build.
- C reports `tsc` exit 0, lint 0 errors, and 174 files / 2974 tests passing. C voided three earlier
  runs because the booted simulator starved the 5 s timeouts. E has not re-run them.

**Push.** `origin/v3/midnight-app` = `d5217530` and `origin/fix/reserving-seam` = `168e794a`.
`v3/consumer-batch2` and the successor are **not on the remote**.

**C-operated captures, not yet B-reviewed.** In C's repo at `native/94ac8b4f/` (outside
`docs/product-v3/native/`), with `capture-log.txt`. The log records content size and appearance as
read back from the device.
| Case | Files | E viewed | E observation (for B; not a verdict) |
|---|---|---|---|
| 1 feed-row title, 3xl | `case1-home-3xl-light-{atrest,feedrow}` | feedrow | Titles clamp at 2 lines ("presents The Fo…", "Late Set with…"). Date/time lines are cut ("22:00…", "21:…", "01:…"). "no bids…" is cut. Prices and "all-in" are complete. C has deliberately left this for B and the owner to judge against the approved row design |
| 2 below-fold identity, a3xl | `case2-home-a3xl-light-{atrest,identity}` | identity | Feature identity is fixed: "Ends Wed 01:43" is complete and "current bid, all-in" wraps. **However, the first "This week" feed row's price runs off the right edge ("$132.0…") and its "all-in" is cut ("all-i…").** This is a clipped amount, the same class as the `d301ccb4` "$95.0". It is likely a defect under the settled all-in rule. FeedRow was not changed in this successor |
| 3 Listing breakdown/activity | `case3-listing-{default,a3xl}-{light,dark}-scrolled` | a3xl light | Panel rows stack; "Service fee (10%)" $9.50 and Delivery wrap fully; the footer is intact |
| 4 signed-in consumer Home | none | — | **Blocked.** Needs an authenticated session on the simulator, established by someone permitted to handle the test-buyer credential. B and C both decline to type it. No harness substitute was used |
| 5 price-caption accessibility | none (source) | — | **Partly established.** The exposed label includes "all-in" (`HomeFeature.tsx`, test LT5). Spoken output is **not** established: the missing capability is an accessibility inspector or VoiceOver attached to the simulator |

**Not yet captured at the successor:** Listing at rest after the poster fix (poster clear of the
banner, navigation outside the artwork, R-4). It belongs to B's repeat set.

### Previously served: `94ac8b4fc40af2642515685929ef5f9ea04472cf`
### Previously served: `c90003ee4ea37795dcf3177f76c947cb0af566b5`
`c90003ee`: Listing's Delivery row lost its value at large text, and that is fixed
(`ListingDetailScreen.tsx`, plus a test). Carry/repeat is unchanged, because Listing already repeats
in full.

### Previously served: `9ea534ffdc9cd07dee0fea31b363824e46ed42a3`
`9ea534ff`: when stacked, the line caps in `HomeFeature.tsx` and `TransactionPanel.tsx` are removed,
because two lines was not enough either. It also adds a test. Carry/repeat is unchanged: both files
are already on the repeat list. C is still iterating from its own captures, so E waits for the
formally named sha before B starts.

### Previously served: `d301ccb4f1ae6e6eeacc6c44ba6933a4418b8288`
`d301ccb4` changes `TransactionPanel.tsx` and adds a test. C found this in a C-operated a3xl capture:
at a3xl, Listing's panel clipped the quantity ("2 × GA ti…"), the "all-in · 6 bids…" sub-line and a
breakdown **amount**, shown as "$95.0" instead of "$95.00". A clipped amount states a different
number. The rows now stack above `IDENTITY_STACK_SCALE`, and nothing is capped at one line. C reports
no change to price semantics. Carry/repeat is unchanged, because all of Listing already repeats.
**This is evidence the a3xl Listing panel was wrong at `d5217530` too.** B's batch 2 a3xl Listing
capture is now superseded by the fix and is not acceptance.

### Previously served: `0dfea8b21496390cc66ad470ba9ad1bc42e2211a`
`0dfea8b2` changes one line in `HomeFeature.tsx`: the time · venue meta line goes from
`numberOfLines` 1→2, because at a3xl it clipped to "19:30 · Lanter…". C found this in a C-operated
capture. It also adds a test. The carry/repeat list below is unchanged: the edit is inside the Home
identity block, which already repeats. The serving tree is clean.

### As first served: `7d0ae5655d7b308c118d7f1154abe95c73f2233c`
- **Implementation (C).** `v3/midnight-app` in `/Users/josetascon/snatchit-refund` is at
  `7d0ae565`, clean.
  - Range from `d5217530`: batch2 (`6c562dcf` … `8f6bed1e`), then `750a9c4f` (Edit refusal exit),
    `40922d27` (Send not-found exit), `70ae3b94` (Listing failure faces and a profile harness),
    `07de08ad` (all-in caption) and `7d0ae565` (poster no longer covered).
  - No native or install file changed, so no rebuild is needed.
  - Test results: C's report is pending.
- **Relevant-diff review (E), per check, from `d5217530`:**
  - **Home artwork per fixture, 4:5 frame, no gradient, nothing on the poster (batch 1): CARRY.**
    `HomeFeature.tsx` changed only in the identity block below the poster: a stacked layout above
    font scale 1.3 (`featureMetrics.ts` `IDENTITY_STACK_SCALE`) and `numberOfLines` 1→2 on two
    lines. `EventMedia`, slots, `url.ts`, `home.tsx`, `FeedRow` and `v3-home.tsx` are untouched, and
    `harnessArt.ts` changed by additions only.
  - **Home identity block, at default, 3xl and a3xl: REPEAT.** It changed, including at default size
    (`numberOfLines` 2). So does the harness next-section figure, which depends on the block's
    height.
  - **Filters glyph, F-91-6 (Home header): CARRY.** `IconButton` and `IconSymbol` are untouched, and
    so is the Home header.
  - **Listing: REPEAT everything.** That covers the poster, artwork cases, R-4, navigation chips,
    safe area, footer at rest, reservation feedback and Dynamic Type. `ListingHero.tsx`,
    `ListingDetailScreen.tsx` and `v3-listing.tsx` changed.
  - **New:** B's five C-operated cases; VoiceOver; consumer Home signed in (or its blocker); Edit
    refusals (`v3-edit-listing`); Listing failure and offline states; public profile
    (`v3-profile`); Send/Receive not-found; the six harness-art screens. C's owner evidence comes
    first, then B.

**B native batch 3 (`17c7e670`, 2026-10-06) and window handback**
- **Listing poster: complete but covered.** It is 4:5 and complete (0–490.7 pt). The status bar and
  banner cover its top 79 pt: masked diff 4.1 for cover-fit at 79 pt hidden, against 16.6 for
  contain. This refines E's earlier wording, "top band not visible": the content is under the chrome,
  not cut by the frame. Navigation chips sit at y 80–160 pt on printed lines. **This fails the
  settled requirement at `d5217530`. Fix: positional (start the poster below the banner, controls in
  their own area). No re-crop.** Home clears the banner (its feature starts at 164 pt).
- **R-4 (info beneath the poster):** the captures show the date line, name and provenance below the
  poster for `flyer`, `subject-wide` and `missing`. B states no explicit R-4 verdict. **R-4 stays
  open** and is decided at the successor, because the navigation fix changes the same layout.
- **Not done at `d5217530`:** footer Dynamic Type; VoiceOver (no accessibility inspection in B's
  session); scrolling (no touch input).
- **Five cases B specified, which C operates and B reviews.** Files are named
  `…-Coperated.png`.
  1. Feed-row title at 3xl and a3xl.
  2. Home identity block below the fold at a3xl.
  3. Listing bid breakdown and activity at default and a3xl, both appearances.
  4. Consumer Home signed in, at rest and one section scrolled, relative to the dock top at
     704.0 pt.
  5. VoiceOver spoken value of the a3xl price caption. This records the gap; it does not close it.
- **Window returned to C** (`17c7e670`). The serving tree was `d5217530` and clean at both the
  start and end of B's review, so every capture's provenance is established.
- **B's scope statement:** not whole-app acceptance. The batches cover Home, Listing, the footer,
  reservation feedback, icons and Dynamic Type, on a native development build, at one commit.

## Owner direction 2026-10-06 (completes existing rulings R-3 and pricing; not new design decisions)
- **"all-in" must stay visibly readable at the supported large text sizes.** Let it wrap or adjust
  the layout; price semantics are unchanged. VoiceOver is checked **separately**: complete spoken
  text does not excuse clipped visible text.
- **The entire poster is preserved.** Navigation controls, the status bar and the SANDBOX banner
  must not cover printed content. This follows the existing artwork ruling. Navigation may move to a
  separate area, in the existing visual language. This settles E's observation and supersedes C's
  narrower framing. Both questions (overlay, and top-band loss) are answered: neither is allowed.
- **Scrolling and below-fold checks: C operates the simulator, B specifies the cases and reviews
  the saved captures.** These are labelled **C-operated, B-reviewed**. The device window is agreed
  before use.
- **Consumer Home next-section figure:** the harness value is insufficient because the harness has
  no dock. Use the authorised sandbox test-buyer sign-in if it is available: no fixture writes, no
  payment actions. If it is unavailable, record that blocker specifically and continue the other
  checks.
- **No blanket whole-app acceptance.**

### Results recorded per property (separate columns; one never stands in for another)
| Surface · case | Visible truncation | VoiceOver | Scrolling reachability | Safe-area layout |
|---|---|---|---|---|
| Home feature identity, default size | none (B `c9d6f0d7`) | not checked | n/a (above the fold) | harness only (no dock) |
| Home feature identity, largest standard | **"Ends…" cut** (B `f235ddb7`) | not checked | — | — |
| Home feature identity, a3xl | **"current bid, al…": "all-in" lost** (B `f235ddb7`), fix required | not checked | — | — |
| Listing poster at rest | — | — | — | **fails the 2026-10-06 ruling (B `17c7e670`, measured)**: the hero spans 0–490.7 pt, w/h 0.8009, **complete, not cropped**; the banner covers its first 79 pt (0–78.7); the back chip (5,80)–(79.7,159.7) and the overflow chip (310,80)–(389.7,159.7) sit on printed lines; the fix is positional |
| Listing footer, default | none (B `f235ddb7`) | not checked | case 3 (C-operated) | not stated |
| Feed rows / below fold | pending | pending | **blocked for B; C-operated next** | pending |
| Consumer Home (with dock) | pending | case 5 (Home a3xl caption; records the gap only) | case 4 (C-operated) | dock band 704.0–769.7 pt and 82.0 pt below, signed out (B). **Signed-in figure blocked for B**: B will not type the test-buyer password into the app; C or an attended session must sign in |

### Successor plan: which checks repeat (E; to be confirmed by diff at C's named sha)
Expected changes: batch2 (`8f6bed1e`), the "all-in" layout (`feedRowState.ts:111-113` caption and
its Home renderer) and the listing navigation/poster layout (`ListingHero.tsx`,
`ListingDetailScreen.tsx`).
- **Repeat, if those files change as expected:**
  - **Listing:** all poster/artwork cases, the footer at rest, reservation feedback, safe areas.
    The navigation change sits in the same screen and scroll layout as the footer.
  - **Home feature:** identity block at default, largest standard and a3xl. Frame geometry and the
    per-fixture artwork checks repeat **only if** `HomeFeature`, `EventMedia`, `slots` or the
    harness art rule change.
- **Retained at `d5217530`, re-used if their render path is untouched:**
  - Home artwork selection and frame (batch 1);
  - icons (F-91-6);
  - the withdrawn name-collapse result.
- **New at the successor:**
  - the scroll and below-fold set (C-operated, B-reviewed);
  - consumer Home with the dock (sign-in, or a recorded blocker);
  - VoiceOver on the "all-in" caption;
  - batch2's six harness-art screens, Edit refusals, Listing read-failure/offline and public profile
    (C's owner evidence first, then B).

**B native batch 2 (`f235ddb7`, 2026-10-06): footer, reservation, icons, Dynamic Type at `d5217530`**
- **Closed natively:**
  - R-1 busy state: "Reserving…" with a spinner sits on the second-position outlined Buy Now, and
    the dimmed bid pill carries no pending label.
  - Option B at rest.
  - F-91-6, the Filters glyph.
  - The remembered name collapse: withdrawn, not reproduced.
- **Next-section figure (re-labelled by B):** 790 pt / 62 pt is **harness** evidence. The `_dev`
  route has no dock, because the dock comes from `(tabs)/_layout`. On consumer Home signed out, the
  dock band is 704.0–769.7 pt. **The consumer figure is unestablished:** it needs feed content,
  which needs auth.
- **Open finding for C:** at the largest accessibility size, the Home price caption truncates to
  "current bid, al…", so "all-in" is lost. At the largest standard size, "Ends…" is cut. Whether
  assistive technology still exposes the full string is unverified. Fix: wrap, or shorten so
  "all-in" survives.
- **Blocked:** scrolling and everything below the fold at large sizes, including the feed-row
  title. `simctl` injects no touch, and B's session has no simulator input tool. Next step: an
  attended session or C's simulator tool runs these checks.
- **E check:** viewed `listing-reserving-flyer-light`, `listing-live-flyer-light` and
  `home-feature-flyer-light-a3xl`; all agree with B. The serving tree was `d5217530` and clean
  after the batch.
- **E observation on R-3/R-4, for B to rule on, not yet a finding.** In `listing-live-flyer-light`
  and `listing-reserving-flyer-light`, at rest (deep-linked, unscrolled), the 4:5 listing poster
  starts at the top of the screen.
  - The top band of the poster sits under the status bar and the SANDBOX banner (≈79 pt, per B's
    batch 2 measurement): TL/TR corner labels, "SYNTHETIC TEST FLYER", "FIXTURE NIGHT" and most of
    "EXAMPLE.COM/TICKETS" are not visible.
  - The back and overflow chips sit over the printed lines "PLACEHOLDER ONE" and "21:00".
  - Source: `ListingHero.tsx:78-90` says the artwork runs under the status bar on purpose. Only the
    controls get the top inset, and they are drawn inside the poster frame.
  - This conflicts with R-3 ("full poster content preserved") and with the R-4 review scope
    ("navigation reachable without covering printed text").
  - A production build has no SANDBOX banner, but the status bar and Dynamic Island still cover the
    top of the poster.
  - B has not yet stated R-4. **R-4 stays open** until B rules on this. If B confirms, it is a
    concrete design conflict between full-bleed-under-the-status-bar and full-poster-visible, and
    may need an owner ruling.
  - C's input (2026-10-06): the chip overlay and the art running under the status bar come from one
    decision. When R-4 moved the identity text off the poster, the navigation stayed on it. E notes
    these are **two questions**, not one: (a) may navigation overlay printed content? (b) may the
    status bar and banner hide the top band of the poster at rest? (b) is content loss whatever the
    answer to (a).
  - **Scroll-check capability:** C's session has working simulator touch input (device points
    393×852; swipes must start more than 4 pt inboard of an edge). B's does not. **The owner
    chooses who runs the scroll and below-fold checks.**

**Carry-forward from `f3f08930` to `d5217530`.** No durable B or native evidence exists at
`f3f08930`, so nothing carries. The full native review is owed at `d5217530`.

**Queued successor work (C, not in the candidate under review).** Branch `v3/consumer-batch2`
(`/Users/josetascon/snatchit-v3batch`) is at `8f6bed1e54604c897a322514f542ffaea17e9fea`; it was
`52a4bd29` earlier on 2026-10-06. Everything below is unreviewed by B or E:
- `6c562dcf`: F-1, Edit listing stops spinning on its refusal paths.
- `8b437942`: F-4, Publish says "Sign in required".
- `a587d2a1`: `?art=` on My listings, Bids, Tickets, Search, Checkout and Send/Order
  (`v3-tickets?screen=send|order`). Every row takes the selected poster, and `all` cycles the
  shapes.
- `8f6bed1e`: the focal-point note in C's inventory doc.

C corrected its own record: `v3-tickets` mounts the real Send and Order screens (`:32-33`), while
`transfer-states` is a component gallery.

**Carry-forward check at `8f6bed1e` (E, by diff; it applies only if C names this sha).**
- No Home or Listing-detail render-path file changed: `EventMedia`, `slots`, `url.ts`,
  `HomeFeature`, `ListingHero`, `ListingDetailScreen`, `home.tsx`, `FeedRow`, `v3-home.tsx`,
  `v3-listing.tsx`, the theme, `IconSymbol` and `BarAction` are all absent.
- The shared `src/lib/media/harnessArt.ts` changed, but additions only (numstat `27 0`, zero
  deleted lines; C says the additions are `ART_SHAPES` and `listArt`).
- Verdict (corrected 2026-10-06): **only evidence that exists carries.** Home's completed checks
  (B batch 1, `c9d6f0d7`) would carry to `8f6bed1e`, because none of their render path changed and
  the only shared file changed by additions alone. **Listing and every other check have no
  committed B or native evidence, so nothing about them carries; they stay pending.** E re-checks
  at the final sha C names.

## Native acceptance loop — restarted 2026-10-05 on C's named successor (owner)
The owner restarted the loop on C's named successor. Completing `f3f08930` first is **not** required.

**Status of `f3f08930` (accurate wording):** B reported starting a native review of `f3f08930`. The
only record of that start is C's commit message at `168e794a`, which says B's review "could not
render" the reserve-in-flight state. **No durable B review evidence survives.** As of 2026-10-05
there was no B document, no committed capture and no file in any session scratchpad. C's two Home
captures (`home-flyer-{light,dark}.png`) were in a temp scratchpad and are gone. Only E's written
description of the Light capture remains (below). **Acceptance remains pending.**

**Successor (now named `d5217530`, above):** it had to contain all three of the following (owner, 2026-10-05):
1. **Listing artwork selection.** At `168e794a`, `app/_dev/v3-listing.tsx` has no `?art=` and the
   cover is always null (`:100-101`), so Listing shows only the missing-artwork plate.
2. **Home feature selection.** A bug has been *reported*, but E has not reproduced it. C reproduces
   it and corrects it if present. Home's harness accepts `?art=`; accepting the parameter is not
   the acceptance test. For each key (`flyer subject subject-wide tall wide square missing`), the
   named poster must visibly appear in the **featured** frame. Source note, not a diagnosis:
   `withArt` assigns the art to `rows[0]`, while `app/(tabs)/home.tsx:635` features `flat[0]`
   after `groupByEventDate` and any filtering. Wherever those two differ, the art lands on a
   plain row.
3. **The reserving seam** (`168e794a`).

C delivers one clean commit (full sha) and completes the owner-authorised feature-branch push.
Native code is rebuilt only if a native file changed.

**Metro: one operator for the review window, agreed between B and C before any restart.**
`:8081` is pid 2172 (`expo start --port 8081`), started 2026-09-26 16:56. Its cwd is
`/Users/josetascon/snatchit-refund`, at `f3f08930` and clean on 2026-10-05. The owner reports that
B started it. The process itself does not show who started it. Nobody restarts or repoints it until
B and C agree on the operator. E's proposal: C operates Metro and the simulator connection, and B
operates the app only. After the repoint, C confirms the serving directory, the sha, clean status
and that the dev client on `SN V3 393x852` is connected to that server. If the serving tree changes
during the review, B pauses, lists which captures became uncertain, and keeps every capture whose
provenance (sha, start/end check) is established. B's `:8083` web harness
(`/Users/josetascon/snatchit-v3render`) is never native evidence.

**Ownership of files:** B owns the review documents and captures. E owns this record and edits
nothing else. Captures go to `docs/product-v3/native/<successor-sha8>/` during the review, named
`<surface>-<state>-<fixture>-<appearance>[-<textsize>].png`. Each review document names the full
sha, the device (`SN V3 393x852`, iPhone 16, UDID `52282259-…48`), iOS 26.5 23F77, and the fixture.
E commits only `V3_ACCEPTANCE_RECORD.md`, by explicit path, after `git status` shows no staged
B files.

**Carry-forward rule:** no surviving native evidence closes any check below, so the full native
review is re-run at the successor and every capture is preserved. Later, evidence carries to a new
commit only if both of the following hold:
- **It is durable and attributable.** The file is committed under `docs/product-v3/native/<sha8>/`
  and states its sha, device, runtime, fixture, appearance and capturer.
- **Nothing in its render path changed** between the two commits. That covers the screen file,
  every shared component, layout or metric it uses (for example `HomeFeature`, `FeedRow`,
  `EventMedia`, `slots.ts`, `url.ts`, `featureMetrics`, `sections.ts`, the theme tokens,
  `IconSymbol` and the footer `BarAction`), and the harness and fixture files that select its
  data (`app/_dev/*`, `assets/qa-posters/*`, `devPosters.ts`).

E checks the diff per check and records the result. An unchanged screen file alone is not
sufficient.

| Check (both appearances) | Implementation (C) | B independent review | Native evidence (sim) | Repeat at successor? |
|---|---|---|---|---|
| Home: 4:5 feature, identity below, no gradient, next section measured; **each** of `flyer`, `subject`, `subject-wide`, `tall`, `wide`, `square`, `missing` visibly in the featured frame | `e902f59a`, `ec61bfa7`; feature-selection fix `6100dee1` (in `d5217530`) | **B `c9d6f0d7` at `d5217530`: verified** (`B_NATIVE_REVIEW_d5217530.md` batch 1) | **sim, 14 captures** `native/d5217530/home-feature-<art>-{light,dark}.png` (1179×2556) | done at `d5217530` except Dynamic Type and safe areas (still to come) |
| Listing: 4:5 poster, info beneath (R-4), navigation reachable; same artwork cases | `f3f08930` (`ListingHero`); `?art=` in `6100dee1` | pending: captures committed in `f235ddb7` (`listing-live-{flyer,missing,subject-wide}-{light,dark}`), but B has stated no R-4 verdict | captured, not assessed | open; see E's poster-under-status-bar observation |
| Footer Option B at rest | `12be25d6` | **B `f235ddb7` at `d5217530`: matches the approval** (bid first, filled, minimum inside; Buy Now second, outlined, price and sub-line) | sim `listing-live-flyer-{light,dark}.png` | done at `d5217530` (Light/Dark at default size; Dynamic Type on the footer not yet reported) |
| Reservation feedback (`?reserving=1`, second-position `Reserving…`) | `f3f08930` + seam `168e794a` | **B `f235ddb7`: verified; R-1 busy state closes natively** | sim `listing-reserving-flyer-{light,dark}.png`; no reservation made | done at `d5217530` |
| Icons (native rendering, separate from B's source cmap finding) | `f3f08930` (IconSymbol) | **B `f235ddb7`: F-91-6 closes** (Filters = tapering bars 58/46/34 device px, against equal 41 px at `91062ab1`); magnifier is drawn | sim Home captures | done at `d5217530` |
| Dynamic Type (largest standard + accessibility sizes), scrolling, safe areas | n/a | **B `f235ddb7`: Dynamic Type on the Home identity reproduced** (default complete; largest standard cuts "Ends…"; a3xl cuts "current bid, al…", losing "all-in": **open finding for C**, a11y value unverified). **Scrolling: blocked** (no touch injection in B's session) | sim `home-feature-flyer-light-{3xl,a3xl}.png`, `listing-live-flyer-light-{3xl,a3xl}.png` | open: all-in caption fix; scrolling and below-fold checks need an attended or touch-capable session |
| Event-name truncation (B's recollection) | — | **B `f235ddb7`: one-character collapse NOT reproduced; withdrawn.** Feed-row title comparison blocked (below the fold) | — | closed as not reproduced; row title pending scroll access |

**After this priority review:** E reconciles the remaining consumer-screen coverage (Search,
Create/Edit, My listings, Bids, Tickets, Order, Send/Receive, Profile/Settings/Appearance/Auth,
checkout presentation states) against `V3_COVERAGE_MATRIX.md` and `V3_RECONCILED_COVERAGE_20260924.md`.
Passing Home, Listing and the footer is **not** whole-app acceptance.

**State at 2026-10-05 22:25 (E checked):**
- B acknowledged in `bee31c88` and `ca00a250` (`B_NATIVE_LOOP.md`). B states that its 2026-09-26
  native pass produced no durable evidence.
- **Metro operator: C, agreed by B (`ca00a250`).**
- `v3/midnight-app` in the serving tree is now at `168e794a`, with C's uncommitted artwork work
  (`v3-home.tsx`, `v3-listing.tsx`, `harnessArt.ts` and two tests).
- B correctly waits for a clean, named commit.
- `native/` exists and is empty.

## Remaining consumer screens: coverage at `168e794a` (E, 2026-10-05)
Read-only reconciliation by three bounded subagents. E spot-checked the consequential claims in
source: F-1, F-4, F-91-2 (0 `auto_released` cases), Send not-found with no retry, the Bids status
filter, payControl's 11 outcomes, the `✎` glyph and the fee label.

**Headline (corrected 2026-10-06 against older records).** No screen below is accepted. No V3-form
screen has native or device evidence from B. Every V3-era B render is web class. B's earliest
record for every group except Appearance is `docs/design-audit/FRONTEND_DESIGN_AUDIT_20260917.md`
(2026-09-17, pin `6561d1f`, V2, source only). "V3-pre" means V3 tokens before the redesign commits.

| Group | Latest B evidence (class, version) | Status wording |
|---|---|---|
| Search | V2 source, 09-17 and the 09-21 baseline. `404bce38` does not touch it | never reviewed in V3 form; V2 reviewed at `6561d1f` |
| Create | `404bce38`, source + computed contrast, V3-pre | never reviewed in V3 form; V3-pre source at `404bce38` |
| Edit listing | V2 source, 09-17. Only a colour-access count at `2619b9e1` | never reviewed in V3 form; V2 at `6561d1f` |
| My listings | `404bce38`, computed contrast, V3-pre | never reviewed in V3 form |
| Bids | `404bce38`, source, V3-pre | no rendered B review |
| Tickets | `d981727e`, computed contrast, V3-pre | no rendered B review |
| Order / Receive | buyer transfer cards via the synthetic gallery, web, Light, `91062ab1`. Those captures are **cited, file missing**. The Order screen itself was never rendered | gallery cards: unknown (evidence missing); Order screen: never reviewed in V3 form |
| Send + gallery | web, Light, `91062ab1`. `comparisons/send_light_91062ab1.png` is present; the full-gallery captures are **missing** | reviewed (web, Light) at `91062ab1`, stale since `a5c0bfc6` / `cbb2df6b` |
| Checkout | web, 5 states × Light and Dark, `d374bd3f` (`comparisons/checkout_states.png` present). At `91062ab1`, B corrected its own fixture count in source | reviewed (web) at `d374bd3f`, stale since `65052bfc` |
| Profile (own) | web, avatar only, `91062ab1` (`avatar_closure_91062ab1.png` present). Also B's analysis of the owner's Build 24 phone screenshots; those originals are not in the repo | avatar reviewed (web) at `91062ab1`; the rest never reviewed in V3 form |
| Public profile | V2 source only | never reviewed in V3 form |
| Settings | `404bce38`, source, V3-pre | never reviewed in V3 form |
| Appearance | none of the screen; only B's pkg8 boards and Light/Dark resolution checks in web renders | no B review found in any record checked |
| Auth | `404bce38`, source (brand-mark tint), V3-pre | never reviewed in V3 form |

**What changed from E's 2026-10-05 wording:**
- Search and Edit were last reviewed in V2, not at `404bce38`.
- Own Profile has a web render (avatar only).
- Appearance has no B review in any class.
- Receive gallery captures are cited but missing, so their coverage is unknown.
- Checkout's render covered both appearances.

| Group | Harness reach (`app/_dev`) | Open findings present at `168e794a` | Owed |
|---|---|---|---|
| Search | results, empty-with-filters. **Unreachable:** hint, loading, no-match, error/offline, inline failure | — | variants; B render L/D; sim |
| Create | form, `invalid`, `risk=*`. **Unreachable:** pickers, photo added, publishing/gate alerts | F-4 signed-out publish silent (`CreateListingScreen.tsx:510-511`); F-5 picker no-results; F-7 two banned-content wordings; F-8 no offline detection | fixes; variants; iOS picker no-crop test (R-3) |
| Edit listing | **no harness, no board** | F-1 permanent spinner (`edit/[id].tsx` "Not allowed" / "Cannot edit" return without `setLoading(false)`); F-2 6 vs 16 platforms; raw `error.message` | fix; board or ruling; harness |
| My listings | populated, empty, error/offline. **Unreachable:** loading, Ended/Reserved rows, dialogs | F-25 dialogs differ from Listing detail's | render all filters; sim |
| Bids | default/past/all, empty/failed/error/offline. **Unreachable:** loading | 404 §4.5 query excludes expired/reversed (`bids.tsx:247`), depends on A/D; no Light design | B Light design; render; sim |
| Tickets | populated/past, empty/error/offline. **Unreachable:** loading, refresh failure | D-8 and the populated real-data path depend on A/D | render; sim |
| Order / Receive | one fixed `seller_sent` case only | F-20 failed proof URL silent; F-21 raw RPC error in an alert | variants for pending/confirmed/auto_released/disputed/expired/reversed |
| Send | `seller_sent` plus the gallery's 7 seller cases. **Unreachable:** pending, delivery gate, mark-sent outcomes, loading/error | Not-found has no retry (`send/[id].tsx:349`); F-91-2 (no `auto_released` gallery case) | Dark render; variants |
| Refund wording | gallery only | "initiated" wording (`90235b74`) never rendered by B; gallery label "both figures" stale | B re-render |
| Checkout | 13 fixtures cover all 11 `payControl` outcomes plus 5 extra states | Fee label "Service fee" vs "Service fee (10%)" (`CheckoutView.tsx:172` vs `ListingDetailScreen.tsx:1231`); uppercase `label` token (TOTAL / HELD FOR YOU) vs the mixed-case ruling, needs a ruling; hairlines need B's call | C names the final commit; B render of every state × L/D; sim; Dynamic Type |
| Profile / public profile | own profile avatar/noavatar. **Unreachable:** loading/error, public profile | `✎` edit badge (`profile.tsx:315`) absent from Inter, falls back to another face; F-10 sign-out unconfirmed; F-11 unblock unconfirmed | B review; sim glyph |
| Settings / Appearance | hub variants, appearance system/light/dark | Header split (hub inline vs `SettingsHeader` uppercase); F-12, F-14; selection cue is red only, needs B | ruling; B review; sim live appearance switch |
| Auth | **not in `_dev`**; signup 2–4 and reset need a real session or recovery link (forbidden) | F-13 bare-title alerts; F-9 is A/D's | fixture route; B review |

**Across all groups:** the 4:5 artwork commits (`ec61bfa7`, `99dd6f36`, `59658b1a`, `cbb2df6b`)
are not visible in any of these harnesses, because every fixture's cover is null. Each needs the
same `?art=` selection C is adding to Home and Listing. Account-switch avatar isolation is **not
authorised**; it is recorded as excluded, not as a gap.

**Order of work after the priority surfaces:**
1. C extends artwork selection to these harnesses and adds the missing state variants.
2. C fixes F-1 and F-4 (behaviour defects).
3. Rulings for B/owner: checkout fee label, uppercase `label` token, Settings header, Edit
   platforms.
4. B renders each group in Light and Dark at one named sha, with native captures under
   `native/<sha8>/`.

## Installed candidate `f3f08930` (C, clean tree; = `e7af5242` Stripe patch + one UI commit) — historical, preserved
- **Implementation:** R-1 busy state keyed by action kind (`ListingDetailScreen.tsx:1465-1480`, both slots carry `Reserving…`/`loading`); vector icons via IconSymbol (filter = three decreasing lines); listing identity below the poster (R-4, `ListingHero`); 8 fixtures, 282,812 B within the 409,600 B budget (not raised). Stripe patch `e7af5242`: A PASS (fresh install + upstream hashes).
- **Build and install:** Debug dev client, `XCODEBUILD_EXIT=0`, bundle `com.jdt-inc.snatchit` on `SN V3 393x852` (iPhone 16, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`, iOS 26.5 23F77, Xcode 26.6 17F113). **Limit:** there is no embedded `main.jsbundle`; the JS is served by Metro (`localhost:8081`) from C's main worktree, clean at `f3f08930`. Captures prove that serving tree, not an embedded artifact. A Release build was not used because `__DEV__`-gated fixtures resolve to nothing there. Detached copy for diffing: `/Users/josetascon/snatchit-review-f3f08930`.
- **Native evidence (C, implementation-owner, not B's review):** `home-flyer-{dark,light}.png`. E viewed the Light capture: all four corner words and both edge rules present; the identity block below the poster in dark ink on the light canvas; the poster's bottom text band legible (no gradient); filter icon = three decreasing lines beside a magnifier; the "This week" heading and the **top part of the first row** visible (in this capture the row's third line is cut at the bottom edge, so B should measure "fully visible" rather than take it from web). Dock absent (the `_dev` route sits outside the tab navigator).
- **B native review:** B reported starting it. No durable evidence survives, so it is pending. The loop moved to the successor on 2026-10-05 (above). The captures above no longer exist on disk.

## Open corrections at `3c6f15a4`
- **Filters glyph (B F-91-6): still the hamburger** — `IconButton.tsx:35` `filter: '≡'`. Correction open with C.
- **Footer (R-1): selection closed; implementation has a behavioural REGRESSION at `12be25d6`–`3c6f15a4`** (B `4882cd6a` §3, verified by E at LDS:1275-1276/1458-1470): `Reserving…`/`loading` stay on the primary slot, which is now the bid, so Buy Now's reserve call shows no feedback (CFT-203). Fix: key busy on the action kind; add a `reserving` harness seam. B rendered review and native checks still owed.
- **Icon glyphs:** per B's cmap measurement (not re-verified by E), `≡ ⌕ ✕ ⋯` are absent from the bundled Inter/Oswald and render in an iOS fallback face. B recommends drawn marks.
- **Fixtures:** B's `fx-*` set withdrawn; two synthetic subject photos proposed (`fixtures-proposed/`) for C to move into `assets/qa-posters/`.
- **Evidence columns are tracked separately:** implementation (C) · independent rendered review (B) · native results (simulator `SN V3 393x852`, actual device and runtime recorded per capture). None of the three substitutes for another.

## Candidate `3c6f15a4` (supersedes `882b0e8d` and `1e4d47d6`; C, clean tree, 2898 tests)
- `3c6f15a4` changes only `assets/qa-posters/flyer-dense-4x5.png`, replacing three missing-glyph boxes (header separator, two footer separators) with ASCII. E viewed the file: no box glyph remains. The generator's ASCII gate is not in the repo, so it is not reviewable here.

### Recorded at `882b0e8d`
- `882b0e8d` regenerates the flyer fixture (no self-overprint; printed words in all four corners and on both side edges, verified by E viewing the file) and adds a behavioural gate test (markers resolve to null with `__DEV__` unset, with a gate-forced-open control). Fixtures now 172 KB (a test pins a 400 KB budget). C re-measured: frame 391×489 (0.800), `contain`, not upscaled, zero intersections, zero gradients.

### As first recorded at `1e4d47d6`
- Carries R-1 (`12be25d6`), R-2 (`e902f59a`), R-3 (groups 1–4) and bundled synthetic poster fixtures (`assets/qa-posters/`, six PNGs, ~132 KB in the binary; gate: `__DEV__` + a `dev-bundled:` cover prefix; flyer uses EXAMPLE.COM and a fictional address).
- **Implementation-owner evidence (C, web, 393×852, 14 captures Light+Dark), not B's review:** feature frame 391×489 (0.800); poster `contain`, not upscaled; zero app-element rects intersecting the image rect; zero gradient inside the frame; the two-sided corner probe shows no crop for 4:5, fitted 9:16/16:9. **Next section:** poster 106–595, identity 608–683, next heading 683–740, **first row fully visible 740–822**, second row cut at 845.
- ~~Known fixture defect~~ fixed at `882b0e8d`. Its missing-glyph boxes were fixed at `3c6f15a4`.
- **Native: BLOCKED.** The build on `SN V3 393x852` fails compiling `@stripe/stripe-react-native` 0.50.3 under Xcode 26.6 (`STPPaymentStatus` enum redeclared: `SWIFT_ENUM_FWD_DECL(NSInteger…)` vs `NS_ENUM(NSUInteger…)`). The fix touches the payments SDK, so the owner and A decide. **No native evidence is recorded until a build succeeds.**
- B review: pending, **at `3c6f15a4`**.


## Not settled, recorded so it is not assumed
- ~~Listing hero identity placement~~: **ruled 2026-09-25 → R-4 (beneath the poster).** At `99dd6f36` the hero is 4:5 with the identity still overlaid on the poster's bottom band. B's `poster_45_direction_91062ab1.png` panel 3 shows that overlay covering a flyer's printed venue and lineup.
- **Home feature height cap** (~45% of the screen): **explicitly deferred** by the owner. Full 4:5 first.

## Earlier closures (for reference; B's evidence, web class unless stated)
- Avatar: square derivative matches its request (84×84), same source, same visible crop on dock and Profile. B `a624cc58` at `91062ab1`. Account-switch isolation still pending (not authorised).
- Home Light missing-artwork feature text: fixed `55838996`; B `8bda19a1` at `0677c80e` (#141519, 18.24:1). **Superseded in layout by R-2** (text moves below the poster).
