# E → B: review the final successor `91a5a58c` once C hands the window back

**Candidate:** `91a5a58c1d54a0c98ef353a6d5f7b53dfb68861c` on `v3/midnight-app`.
- Its code is identical to `7c9b270b`.
- It is pushed to origin, clean, and served from `/Users/josetascon/snatchit-refund`.
- No native changes.
- C's handoff: `docs/product-v3/V3_BATCH2_HANDOFF.md`.
- **C holds the device and Metro. Start only after C hands them back explicitly.**

**Review C's captures** (C-operated, B-reviewed), in C's repo with `capture-log.txt`:
- **Home cases 1 and 2** at `native/7c9b270b/`.
- **Listing case 3** at `native/94ac8b4f/`. It carries: `94ac8b4f..7c9b270b` changes only FeedRow,
  HomeFeature and their test, which E verified.

**Things for you to judge:**
1. **Feed-row clamps (case 1).** Titles stop at 2 lines, and the date and bid count are cut. C left
   this for your comparison with the approved row design.
2. **Price numeral capped at 1.3×** (`MAX_DISPLAY_FONT_SCALE`) in FeedRow and HomeFeature.
   - It stops "$132.0" / "0" splitting mid-number.
   - But at a3xl each price now renders **smaller than its own caption and the meta text** (see
     `case2-home-a3xl-light-identity`).
   - Is a complete but least-prominent amount acceptable under the readability rule?
3. **Case 4 (signed-in Home)** is blocked: it needs an authenticated simulator session from someone
   permitted to handle the credential. **Case 5:** the exposed label is verified in source only;
   spoken output isn't established, because no accessibility inspector is attached.

**Repeat at `91a5a58c`, deep link:**
- **Listing at rest:** poster clear of the banner, navigation outside the artwork, R-4 info beneath.
  Cover `flyer`, `missing`, `subject-wide` and `tall`, in both appearances.
- The footer.
- `?reserving=1`.
- Home identity at default size.
- Search rows at large text (FeedRow changed).

**These carry from `d5217530`; don't repeat them:**
- Home artwork per fixture, frame, no gradient, nothing on the poster.
- Filters glyph.

**New screens, after the priority checks:**
- `_dev/v3-edit-listing?variant=not-found|not-owner|has-bids|inactive|read-failed`
- `_dev/v3-profile`
- `_dev/v3-listing?variant=error|offline`
- the `?art=` list harnesses

**C's operating notes:**
- A content-size change needs an app relaunch.
- A scroll needs a dwell before the drag.
- Don't run the full test suite while the simulator is booted.

Record: `V3_ACCEPTANCE_RECORD.md` at `2b5795cd`.
