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
| R-1 | **Listing footer, Option B** (2026-09-25). When bidding and Buy Now are both available: Place a bid first, full-width, red, minimum all-in inside; Buy Now second, full-width, outlined, quantity-aware label + price + sub-line. Supersedes the Buy-Now-first hierarchy. Other states keep their own valid actions. Eligibility and behaviour unchanged | `comparisons/footer_arrangements_91062ab1.png` (Option B); map §*SETTLED — listing footer* | pending (C) | Selection render only: `91062ab1` + harness patch · web · `V3_FOOTER_AND_POSTER_91062ab1.md`. **Not** a review of implemented code | Dynamic Type (largest standard + accessibility sizes, no truncation of label, minimum, "Buy … now · $X", sub-line); wrapping; safe area under the stacked footer; Light + Dark | Open |
| R-2 | **Home feature, full 4:5 poster** (2026-09-25). Complete poster in a full-width 4:5 frame, no height cap yet; non-4:5 images fitted without crop or stretch on a deliberate background; name, date, venue, price and listing details in a separate area below the poster; no app text or badges on the poster; overlay gradient removed; header and filter controls unchanged | Owner ruling text; map Home row | pending (C) | pending (B): native renders, Light + Dark, with a text-heavy flyer, a photograph, missing artwork, plus the corner-marker fixtures. Report how much of the next section is visible at 393×852 | Native fonts; safe area; Dynamic Type on the identity block below the poster; System appearance switch | Open |
| R-3 | **Event artwork 4:5 throughout** (2026-09-25, authorised direction). Full poster content preserved; avatars unchanged | Owner direction; E's baseline inventory at `a5c0bfc6` | pending (C) | pending (B), per slot, including the corner-marker fixtures | Picker behaviour on iOS (no crop that discards poster pixels); per-slot rendering | Open |

## Not settled, recorded so it is not assumed
- **Listing hero identity placement** (name and date over the art vs below it): **not ruled.** R-2 covers the Home feature only.
- **Home feature height cap** (~45% of the screen): **explicitly deferred** by the owner. Full 4:5 first.

## Earlier closures (for reference; B's evidence, web class unless stated)
- Avatar: square derivative matches its request (84×84), same source, same visible crop on dock and Profile. B `a624cc58` at `91062ab1`. Account-switch isolation still pending (not authorised).
- Home Light missing-artwork feature text: fixed `55838996`; B `8bda19a1` at `0677c80e` (#141519, 18.24:1). **Superseded in layout by R-2** (text moves below the poster).
