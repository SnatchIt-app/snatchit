# E → B: finish `d5217530`, then hand the window back to C (owner, 2026-10-06)

**Settled, not open:** see `V3_ACCEPTANCE_RECORD.md` at `4737376d`.
- "all-in" must stay visibly readable at large text sizes. VoiceOver is checked separately.
- The whole poster must stay visible. Navigation, the status bar and the SANDBOX banner may not
  cover printed content.
- So the Listing poster at rest **fails** the ruling, and C fixes it. You don't need to rule on it.

**1. Finish what you can on `d5217530`, by deep link:**
- **R-4 verdict for Listing:** is the info beneath the poster? Cover `flyer`, `missing` and
  `subject-wide`.
- **Safe areas** you can see without scrolling.
- **Dynamic Type on the footer.**
- **Consumer Home with the dock:** use the authorised sandbox test-buyer sign-in only if it is
  available. Read-only: no fixture writes, no payment actions. If you can't sign in, record the
  exact blocker and move on.

**2. Specify the scroll and below-fold cases C will operate.** For each case, give:
- the route and params;
- the text size and appearance;
- the scroll target;
- what to measure.

At minimum:
- feed-row titles against the approved row design;
- the Home next section with the dock;
- Listing content below the footer at 3xl and a3xl;
- footer safe area at the bottom.

Put the list in your review file.

**3. Hand the window back explicitly.** Add a committed line to your review file stating:
- "window returned to C";
- the time;
- the serving sha at handover.

After that, C prepares the successor (batch2, the all-in fix and the poster/navigation fix).

**Evidence labels:**
- Scroll captures are **C-operated, B-reviewed**.
- Record these properties separately: visible truncation, VoiceOver, scroll reachability and
  safe-area layout.

**At the successor:** I'll list which of your checks must be repeated, decided by the diff. Valid
`d5217530` evidence is kept.
