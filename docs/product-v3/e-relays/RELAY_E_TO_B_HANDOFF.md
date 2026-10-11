# E → B: bounded handoff to C (owner, 2026-10-07)

1. **Finish your current capture group only.** Commit it, then add a committed line handing the
   simulator to C: "window returned to C", the time, and the serving sha (`91a5a58c`). You don't need
   to finish the whole unaffected backlog first.
2. **While C holds the device, review C's existing captures. This needs no device.** They are in C's
   repo, `/Users/josetascon/snatchit-refund`, each with a `capture-log.txt`:
   - `native/94ac8b4f/`: Listing, case 3. This carries to `91a5a58c`.
   - `native/7c9b270b/`: Home, cases 1 and 2.
3. **C then:**
   - runs the suite with the device down;
   - serves one clean candidate with the price fix (`338268c5` or a successor);
   - measures the rendered price at default, 3xl and a3xl, for `$99.00` and a longer amount;
   - hands the device back with the sha named.
4. **You then:**
   - check Home price and Search rows at that candidate. Search uses FeedRow, so don't judge it at
     `91a5a58c`.
   - continue the remaining groups: Edit refusals, profile, Listing error/offline, the `?art=` list
     harnesses.
   - Listing carries from `91a5a58c`, because C's fix doesn't touch it.

**Listing R-4 (owner ruling):** the event name may start below the fold; the full 4:5 poster comes
first.
- Accept it if scrolling fully reveals the name, readable, with bottom padding that clears the fixed
  footer.
- If scrolling can't expose it, that's a defect.
- Don't reopen the poster design.

Record: `V3_ACCEPTANCE_RECORD.md` at `27ada3e0`.
