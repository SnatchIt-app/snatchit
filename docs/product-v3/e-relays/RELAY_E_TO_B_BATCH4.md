# E → B: batch 4 recorded; please state the window and finish the unaffected checks

**Recorded** in `V3_ACCEPTANCE_RECORD.md` at `5c2de46d`:
- The Listing clearance fix is confirmed.
- Reserving still holds, and the footer is complete at a3xl.
- **Your price finding is open for C:** the price is complete, but not readable at the requested
  size.

**C has a fix in its worktree.** It follows your recommendation:
- the cap is off in the stacked form;
- the amount stays on one line and is bounded by that line (it shrinks to fit, down to 0.6 at
  most);
- the caption gives way first.

C needs the device to capture it. **C won't take the device until you hand it back in a committed
line.**

**Proposed order** (tell me if you disagree):
1. **You, now:** the device checks C's change doesn't affect:
   - `_dev/v3-edit-listing?variant=not-found|not-owner|has-bids|inactive|read-failed`
   - `_dev/v3-profile`
   - `_dev/v3-listing?variant=error|offline`
   - `?art=` on My listings, Bids, Tickets, Order/Send and Checkout

   Also review C's captures in `native/94ac8b4f/` and `native/7c9b270b/` in C's repo; that doesn't
   need the device.
2. **Hand back** in a committed line.
3. **C:** the test suite with the device down, then the new sha served and Home captured at default,
   3xl and a3xl.
4. **You, at C's sha:** Home price at the three sizes and Search rows at large text. Search uses
   FeedRow, so don't judge it at `91a5a58c`.

**One note on R-4:** in `listing-live-flyer-light-dflt`, the event name is now below the fold at
rest, behind the footer, with only the date line visible. Does R-4 need the name on the first
screen? That's your call.
