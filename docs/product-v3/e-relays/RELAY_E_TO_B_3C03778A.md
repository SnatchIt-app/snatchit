# E → B: review `3c03778a` (owner, 2026-10-07). The simulator is yours

**Candidate:** `3c03778ac55e2c0f33233e4cd90e634805e28e2a`.
- Pushed, served and clean; E verified this.
- C has handed back the device and Metro `:8081`.
- Batch 5's assignment at `91a5a58c` is historical; don't repeat it.

**Order:**
1. **C's durable captures:** `native/3d4d6a4a/` in C's repo, with `capture-log.txt`. These are
   C-operated; you review them.
   - Price ink: 18.3 / 25.0 / 63.7 pt, and `$1,716.00` at 58.0 pt.
   - Listing scroll-end, Light and Dark.
   - Event name revealed by scrolling, Light and Dark.
2. **Home and Search price layouts** at default, 3xl and a3xl, including `?amounts=long`.
3. **Listing scroll-end clearance and event-name reachability.**
   - **Bottom gap:** account for the ~206 pt using the actual footer bounds and scroll layout.
   - The owner says no further spacing change on a screenshot estimate alone.
4. **The remaining groups:**
   - Edit refusals: `_dev/v3-edit-listing?variant=not-found|not-owner|has-bids|inactive|read-failed`
   - `_dev/v3-profile`
   - `_dev/v3-listing?variant=error|offline`
   - `?art=` on My listings, Bids, Tickets, Order/Send and Checkout

**Carry; don't repeat:** Listing poster clearance (`ListingHero` layout unchanged since `91a5a58c`),
Home artwork per fixture, frame, and the Filters glyph.

**If you can't reach the Home feature price at a3xl without touch,** name that exact check. C does
one short C-operated capture, and you review it. Don't let it stall the rest.

**Shortening rule (owner): judge by content.**
- **List titles may shorten.** They link to full details. So the feed-row title, date and bid count
  shortening is acceptable, as long as Listing shows them in full.
- **The event's date and time must be available in full on the detail screen at large text.**
  - At `3c03778a`, the only place Listing shows them is the hero line (`ListingHero.tsx:120-121`,
    `numberOfLines={1}`).
  - So "Sat 24 Oct · 1…" at a3xl is a defect under this rule. E has recorded it and C is preparing a
    fix.
  - Please confirm it on the device.

**Report incrementally.** Mark each item **reviewed**, **failed** or **untested**. No whole-app
claim.

Record: `V3_ACCEPTANCE_RECORD.md` (latest).
