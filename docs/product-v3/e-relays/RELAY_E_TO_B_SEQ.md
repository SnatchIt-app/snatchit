# E → B: finish at `3c03778a`, then hand the simulator to C (owner, 2026-10-08)

**Finish the unaffected checks at `3c03778a`.** Commit them, marking each reviewed, failed or
untested:
- Edit refusals: `_dev/v3-edit-listing?variant=not-found|not-owner|has-bids|inactive|read-failed`
- `_dev/v3-profile`
- `_dev/v3-listing?variant=error|offline`
- `?art=` on My listings, Bids, Tickets, Order/Send and Checkout

Then add a committed line: **"simulator and Metro :8081 handed to C"**, with the time and the serving
sha.

**After that, C:**
- serves one named, clean successor with two fixes: the bid-activity amount and the Listing
  date/time wrap;
- captures at a3xl, Light and Dark:
  - bid activity with an ordinary and a four-figure amount;
  - the date/time line;
  - the Home feature amount;
- hands the simulator back to you.

**Your focused verification at that sha:** those three checks, plus any applicable saved captures.
Don't repeat accepted checks (poster, navigation, footer, reserving, icons, feed-row amounts,
scroll-end clearance, event-name reachability).

**Record correction:** the feed-row amounts are verified, but the **Home feature amount at a3xl is
untested**. The batch-4 finding on the feature isn't closed until a capture at a3xl exists. A
smaller-size capture is supplemental only.

**Still outstanding:** signed-in Home and spoken VoiceOver. No whole-app acceptance.

Record: `V3_ACCEPTANCE_RECORD.md` at `acdd0ff2`.
