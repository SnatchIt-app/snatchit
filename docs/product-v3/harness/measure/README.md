# B's measurement instruments

Lifted out of the session scratchpad, which is session-scoped and disappears. B's 2026-09-26
native captures were lost exactly that way, and E recorded that these instruments lived only in a
scratchpad while the numbers they produced were being used as evidence. The method is also stated
in full in each `B_NATIVE_REVIEW_*.md`, so a reader can reproduce or contradict the numbers without
running these.

| file | what it does |
|---|---|
| `gutter.py` | the two measurements B commits to: content ink inside the right 16 pt gutter, and max ink x against the 377 pt content edge. Reports at four thresholds so a result can be seen to be threshold-robust rather than threshold-chosen |
| `hairline.py` | resolves gutter ink per row, which is how the 144 px signal was identified as the full-bleed header hairline (1179/1179 columns, contiguous) rather than clipped text |
| `sweep.py` | the frame gate plus the gutter sweep over a whole capture set: sandbox-banner check, size witness from the header hairline's y, ink and edge |
| `shot3.sh` | a size-asserted capture. `shot.sh` reads `content_size` back only AFTER the capture, so a frame can be written under the wrong label; this reads it after setting, after the relaunch and after the capture, and voids the frame without writing it if they disagree |

## Rules these encode, each learned by getting it wrong
1. **Ink is deviation from the frame's own modal background**, computed per frame. A fixed
   threshold reads the black canvas as ink in Dark; that produced a "4.0 pt gap" and a "0 px
   gutter" that were discarded, and it produced C's identical 101,568 px / 392.7 pt across nine
   different screens.
2. **Prove the instrument on the failing frames first.** An instrument that cannot reproduce the
   defect cannot certify the fix. P-1 is `ratewrap` at 2,597 px / 392.7 pt; P-2 is `trustrows` at
   8,315 px / 392.7 pt.
3. **Exclude by shape, never by raising a threshold** until the signal disappears.
4. **md5 for identity.** A float32 sum over a cropped band saturates and collides; B once called
   two distinct frames "byte-identical" on exactly that mistake.
5. **Read size and appearance off the paint.** `simctl ui appearance` does not drive this app at
   all — the harness reads the app's stored preference, so the route must carry
   `?appearance=light|dark`. And a `content_size` readback is corroboration, not the record.
6. **A diff is only evidence if the two inputs differ.** B "re-ran" a default-size diff and got
   zero across the whole frame including the clock — it was a file compared with itself.
