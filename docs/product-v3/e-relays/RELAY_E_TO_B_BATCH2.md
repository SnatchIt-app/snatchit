# E → B: batch 2 recorded; one Listing question for you (2026-10-06)

**Recorded** in `V3_ACCEPTANCE_RECORD.md` at `6a3526fb`:
- R-1 busy state, Option B at rest and F-91-6 are closed natively at `d5217530`.
- The name collapse is withdrawn.
- The 62 pt figure is labelled harness evidence; the consumer figure is unestablished.
- The "all-in" truncation at a3xl is open for C.
- Scrolling is blocked.

**I viewed** `listing-reserving-flyer-light`, `listing-live-flyer-light` and
`home-feature-flyer-light-a3xl`. All three agree with your text.

**Please rule on R-4 and R-3 for Listing.** You captured it but haven't stated a verdict.
- In `listing-live-flyer-light`, at rest, the poster starts at the top of the screen. Its top band
  sits under the status bar and the SANDBOX banner. The TL/TR corners, "SYNTHETIC TEST FLYER",
  "FIXTURE NIGHT" and most of "EXAMPLE.COM/TICKETS" are not visible.
- The back and overflow chips sit over "PLACEHOLDER ONE" and "21:00".
- In source this is deliberate: `ListingHero.tsx:78-90` says the art runs under the status bar on
  purpose, and only the controls get the inset.
- That looks like a conflict with "full poster content preserved" and "navigation reachable without
  covering printed text".
- A production build has no SANDBOX banner, but the status bar and Dynamic Island still cover the
  top of the poster.
- It's your call whether this is a finding. If it is, name the capture, appearance and the printed
  content lost.

**Still open for you:**
- R-4 info-beneath verdict, plus `missing` and `subject-wide` on Listing.
- Safe areas.
- Dynamic Type on the footer.

**Scrolling and below-fold checks:** I'm taking the blocker to the owner. Don't work around it.
