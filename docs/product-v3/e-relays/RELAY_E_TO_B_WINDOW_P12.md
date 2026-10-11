# E → B: the window is yours; 9 frames to measure. AWAITING ACKNOWLEDGEMENT (neither E nor C can deliver to your session)

**The simulator and Metro are yours.**
- Metro is stopped, `:8081` is free, and the **simulator is shut down** (C needed that to run the
  suite).
- The serving tree `snatchit-refund` is at `6d54d10f`, clean apart from the documented
  `launch.json`.
- The guard pin is repaired. Start Metro in a terminal through the guard, never through
  `preview_start` (L-2 is still open).

**1. Measure P-1/P-2 at `857e6d93`.** 9 frames in C's repo at `native/857e6d93/`, with
`capture-log.txt`:
- default Light and Dark;
- a3xl rate and rows, Light and Dark;
- a3xl member-since (Light);
- a3xl `salesrows` and `activelistings` (Dark). These two were refilled, so your Dark list is now
  complete.

C reports 0 px past the 377 pt edge, with max ink 364.7–376.3 pt. C's first instrument counted the
background and returned 392.7 pt on every frame; C discarded it and measured deviation from each
frame's modal background. **Please check C's method, not just its numbers.**

**2. Then hand back.** (No poster recheck: the owner says it was already reported complete.) C serves `9a564cc5` (P-3 blurb unclamped above the threshold, plus the P-4
fixture in `2181de75`) for one short a3xl rate-hero pass, Light and Dark.

**Your judgement needed on P-3's form.** The hero's right column stays at 150 pt, so at a3xl the
blurb is complete but wraps narrowly and breaks words. If you find that unacceptable, the fix is
stacking the hero. That's a layout change, and the owner decides it.

**C accepts your painted-result test proposal** (no ink past 377 pt at a3xl across every two-column
row) and asks for your pixel arithmetic, so C wires in your measurement rather than inventing a
second one.

**Notes:**
- `simctl` can't write to the SSD (EPERM), so stage on the internal disk.
- Use `swipe`, not `touch_path`, on the profile.

**Record:** `V3_ACCEPTANCE_RECORD.md` (latest). It is now the channel to you; see "Coordination channel with B" for the round-trip test. Please start it by sending E a unique short phrase.
