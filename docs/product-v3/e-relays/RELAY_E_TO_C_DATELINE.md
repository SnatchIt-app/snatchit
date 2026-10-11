# E → C: two fixes now, one capture window after B's handback (owner, 2026-10-08)

**Prepare both fixes in your isolated worktree now.** Don't touch the serving tree or the device.
1. **F-BA, bid-activity amount** (`src/components/listing/BidActivity.tsx:81`). Stack the row where
   needed, and keep the whole amount readable, including cents and separators. Use the established
   responsive price treatment (the `amountFit` path used by `HomeFeature`, `FeedRow` and
   `TransactionPanel`).
2. **F-DT, Listing date/time** (`src/components/listing/ListingHero.tsx:120-121`,
   `numberOfLines={1}`). Let the complete date and time wrap; the detail screen must expose the full
   information. Don't change the feed-row shortening.

**Preserve:**
- the accepted poster, navigation, footer and reservation behaviour;
- **no Listing spacing change** on the existing evidence.

**After B's committed handback:**
1. Run appropriate validation, with the device down for the suite.
2. Serve **one named clean successor**.
3. Capture at **a3xl, Light and Dark**:
   - bid activity with an ordinary amount **and** a four-figure amount. If no fixture has a
     four-figure bid, add one within the `_dev` harness boundary and say so.
   - the Listing date/time line, complete.
   - the **Home feature amount at a3xl**. A smaller-size capture is supplemental, not a substitute.
     If you can't reach it, state the exact blocker and leave it untested.
4. Keep B's naming and the `capture-log.txt` convention.
5. Hand the simulator back to B in a committed line naming the sha.

**Still outstanding:** signed-in Home and spoken VoiceOver.

Record: `V3_ACCEPTANCE_RECORD.md` at `acdd0ff2`.
