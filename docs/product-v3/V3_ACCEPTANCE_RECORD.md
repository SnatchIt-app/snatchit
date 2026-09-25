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

## Candidate `1e4d47d6` (C, clean tree, 2898 tests)
- Carries R-1 (`12be25d6`), R-2 (`e902f59a`), R-3 (groups 1–4) and bundled synthetic poster fixtures (`assets/qa-posters/`, six PNGs, ~132 KB in the binary; gate: `__DEV__` + a `dev-bundled:` cover prefix; flyer uses EXAMPLE.COM and a fictional address).
- **Implementation-owner evidence (C, web, 393×852, 14 captures Light+Dark), not B's review:** feature frame 391×489 (0.800); poster `contain`, not upscaled; zero app-element rects intersecting the image rect; zero gradient inside the frame; the two-sided corner probe shows no crop for 4:5, fitted 9:16/16:9. **Next section:** poster 106–595, identity 608–683, next heading 683–740, **first row fully visible 740–822**, second row cut at 845.
- **Known fixture defect:** in `flyer-dense-4x5.png`, "TENTH CLOSER" overprints "EXAMPLE.COM/TICKETS", and the text never reaches the right edge or corners. Regeneration requested.
- **Native: BLOCKED.** The build on `SN V3 393x852` fails compiling `@stripe/stripe-react-native` 0.50.3 under Xcode 26.6 (`STPPaymentStatus` enum redeclared: `SWIFT_ENUM_FWD_DECL(NSInteger…)` vs `NS_ENUM(NSUInteger…)`). The fix touches the payments SDK, so the owner and A decide. **No native evidence is recorded until a build succeeds.**
- B review at this commit: pending.

## Not settled, recorded so it is not assumed
- **Listing hero identity placement** (name and date over the art vs below it): **not ruled.** R-2 covers the Home feature only. At `99dd6f36` the hero is 4:5 with the identity still overlaid on the poster's bottom band. B's `poster_45_direction_91062ab1.png` panel 3 shows that overlay covering a flyer's printed venue and lineup.
- **Home feature height cap** (~45% of the screen): **explicitly deferred** by the owner. Full 4:5 first.

## Earlier closures (for reference; B's evidence, web class unless stated)
- Avatar: square derivative matches its request (84×84), same source, same visible crop on dock and Profile. B `a624cc58` at `91062ab1`. Account-switch isolation still pending (not authorised).
- Home Light missing-artwork feature text: fixed `55838996`; B `8bda19a1` at `0677c80e` (#141519, 18.24:1). **Superseded in layout by R-2** (text moves below the poster).
