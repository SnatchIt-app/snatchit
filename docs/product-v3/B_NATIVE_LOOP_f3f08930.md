# B — native acceptance loop, restarted

## Handoff acknowledged (2026-10-05)

I acknowledge the handoff. **My 2026-09-26 native pass produced no durable evidence**: the captures
lived in a session scratchpad that no longer exists and were never copied into the repository. The
measurements I recalled are **not** evidence and are not carried forward. Anything below is
re-derived in this run, and every capture is written into
`docs/product-v3/captures/<commit>/` **as it is taken**.

## Blocker, reported and worked around

**C has named no successor.** `v3/midnight-app` is at **`f3f08930470269272e394c8d4bdedd1ed876f817`**,
working tree clean, **zero commits after it** (`git log f3f08930..HEAD` is empty). So the two things
the restart depends on are **not in the tree**:

* the **`reserving` harness seam** — without it the Option B footer's reservation feedback cannot be
  rendered at all, and I will not produce it with a real reserve call;
* the **corrected artwork selection** — at `f3f08930` `withArt()` in `app/_dev/v3-home.tsx` assigns
  the poster to `rows[0]` on the comment "The first row is the feature", but the screen picks its
  feature by date bucket, so every single-poster variant paints a non-feature row.

**Blocked:** reservation feedback (R-1 native); non-4:5 fitting and subject framing through the
single-poster `?art=` values.
**Proceeding anyway at `f3f08930`:** Home 4:5 geometry and the identity block, Listing, the Option B
footer's *paint*, icons, both appearances, Dynamic Type, scrolling and safe areas — none of which
depend on either missing piece.

## Environment, pinned

| | |
|---|---|
| candidate | `f3f08930470269272e394c8d4bdedd1ed876f817`, tree clean |
| device | `SN V3 393x852` — device type `iPhone-16`, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48` |
| runtime | iOS 26.5 (23F77) |
| logical size | 393 × 852 pt; captures measure 1179 × 2556 px (@3×) |
| app | `com.jdt-inc.snatchit`, Debug dev client |
| JS source | **Metro on :8081, cwd `/Users/josetascon/snatchit-refund`** |

**Metro ownership — explicit.** The :8081 Metro (pid 2172 at the time of writing) is **mine**; I
started it on 2026-09-26 from C's worktree and it still serves that tree. **C: do not restart or
re-point it without telling me** — it is the only thing that decides which commit these captures
prove. My web harness on :8083 is separate and is not used for anything in this document.

**No production call, no real reservation, no payment action is made in this loop.**
