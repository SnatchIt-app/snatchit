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

## Native acceptance loop — restarted 2026-10-05 on C's named successor (owner)
The owner restarted the loop on C's named successor. Completing `f3f08930` first is **not** required.

**Status of `f3f08930` (accurate wording):** B reported starting a native review of `f3f08930`. The
only record of that start is C's commit message at `168e794a`, which says B's review "could not
render" the reserve-in-flight state. **No durable B review evidence survives.** As of 2026-10-05
there was no B document, no committed capture and no file in any session scratchpad. C's two Home
captures (`home-flyer-{light,dark}.png`) were in a temp scratchpad and are gone. Only E's written
description of the Light capture remains (below). **Acceptance remains pending.**

**Successor:** not yet named. Expected: a clean commit containing `168e794a` (the `fix/reserving-seam`
`?reserving=1` harness seam, which seeds the screen's own `reserving` state) **plus corrected
artwork selection on the Listing harness**. At `168e794a`, `app/_dev/v3-listing.tsx` has no `?art=`
and the cover is always null (`:100-101`), so Listing can show only the missing-artwork plate. Home
already has `?art=` (`missing flyer photo markers tall wide square all subject subject-wide`). E
asked C on 2026-10-05.

**Metro ownership (explicit):** C owns `:8081`. On 2026-10-05 it served
`/Users/josetascon/snatchit-refund` at `f3f08930` (clean). C hands over to the successor and states
the serving path, sha and clean status. Nobody else restarts or edits that tree until B reports
done. B's web harness on `:8083` (`/Users/josetascon/snatchit-v3render`) is never native evidence.

**Ownership of files:** B owns the review documents and captures. E owns this record and edits
nothing else. Captures go to `docs/product-v3/native/<successor-sha8>/` during the review, named
`<surface>-<state>-<fixture>-<appearance>[-<textsize>].png`. Each review document names the full
sha, the device (`SN V3 393x852`, iPhone 16, UDID `52282259-…48`), iOS 26.5 23F77, and the fixture.
E commits only `V3_ACCEPTANCE_RECORD.md`, by explicit path, after `git status` shows no staged
B files.

**Carry-forward rule (per check, by diff, never wholesale):** native evidence taken at an earlier
commit carries to the successor only when `git diff <old>..<successor>` touches no file in that
surface's render path. E states the result for each surface. `f3f08930..168e794a` touches only
`app/_dev/v3-listing.tsx`, `tests/v3-reserve-feedback.test.ts` and `ListingDetailScreen.tsx`. In
that file the only runtime change is `useState(fixture?.reserving ?? false)`, which is `false` in
the product. So for that diff: Home, icons and the footer at rest would carry; reservation
feedback must be taken at the successor. (No B native evidence exists to carry yet. The rule
applies from now on.)

| Check (both appearances) | Implementation (C) | B independent review | Native evidence (sim) | Repeat at successor? |
|---|---|---|---|---|
| Home: 4:5 feature, identity below, no gradient, next section measured; `flyer`, `subject`, `subject-wide`, `tall`, `wide`, `square`, `missing` | `e902f59a`, `ec61bfa7` | pending | pending (C's `f3f08930` captures lost) | yes, nothing survives |
| Listing: 4:5 poster, info beneath (R-4), navigation reachable; same artwork cases | `f3f08930` (`ListingHero`) | pending | pending | yes; **blocked** until Listing `?art=` lands |
| Footer Option B at rest | `12be25d6` | pending | pending | yes |
| Reservation feedback (`?reserving=1`, second-position `Reserving…`) | `f3f08930` + seam `168e794a` | pending | pending | at successor only |
| Icons (native rendering, separate from B's source cmap finding) | `f3f08930` (IconSymbol) | pending | pending | yes |
| Dynamic Type (largest standard + accessibility sizes), scrolling, safe areas | n/a | pending | pending | yes |
| Event-name truncation (B's recollection) | — | B to reproduce before reporting | — | finding only if reproduced |

**After this priority review:** E reconciles the remaining consumer-screen coverage (Search,
Create/Edit, My listings, Bids, Tickets, Order, Send/Receive, Profile/Settings/Appearance/Auth,
checkout presentation states) against `V3_COVERAGE_MATRIX.md` and `V3_RECONCILED_COVERAGE_20260924.md`.
Passing Home, Listing and the footer is **not** whole-app acceptance.

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
