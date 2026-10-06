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

---

# Handoff acknowledged, and the start conditions (2026-10-05, E's relay + owner clarifications)

**I acknowledge E's handoff.** The target is **C's named successor, not `f3f08930`**. Nothing at
`f3f08930` is carried forward as native evidence.

**I stopped and discarded the `f3f08930` capture run.** Two reasons, both disqualifying:
the target changed; and the last two captures came back as a **full-red error screen**
(`(255,0,0)` across the frame), so they were junk regardless. `docs/product-v3/captures/` is
deleted. The evidence directory is now **`docs/product-v3/native/<sha8>/`**, with captures named
`<surface>-<state>-<fixture>-<appearance>[-<textsize>].png`.

**Metro ownership transferred.** `:8081` is **C's** for this review window; **C is the single
operator**. I started pid 2172 on 2026-09-26 from `/Users/josetascon/snatchit-refund` and I hand it
over now — C may restart or re-point it freely, and should, since the served commit must become the
successor. My `:8083` web harness is mine, is unrelated, and **is not native evidence**.

## The successor is not ready yet — stated precisely

`168e794a` **exists and is the branch head**: *"feat(dev): the reserve-in-flight state can be looked
at without reserving anything"* — the `?reserving=1` seam the review needs.

It is **not yet a clean successor**. The serving tree has **four uncommitted paths**, and they are
exactly the second half of the requirement:

```
 M app/_dev/v3-home.tsx
 M app/_dev/v3-listing.tsx
?? src/lib/media/harnessArt.ts
?? tests/v3-harness-art-selection.test.ts
```

So artwork selection — Listing `?art=`, and the Home feature-selection defect — is in progress, not
committed. **I am not starting on a dirty tree**, and I am not reviewing C's working copy.

## What I need from C before I start

1. The **full 40-character sha** of one clean successor commit containing `168e794a`, Listing
   `?art=`, and the Home feature-selection fix.
2. Confirmation that **Metro `:8081` is serving that commit** from a named directory.
3. A **clean `git status`** in that directory.

On receipt I record `git -C <serving path> rev-parse HEAD` plus `git status --porcelain` **at the
start and again at the end**. If either changes mid-review I pause, say which captures became
uncertain, and keep only those whose provenance is established — I do not void the lot by reflex.

## What I will not accept as proof

**A URL parameter is not a render.** For every artwork case — `flyer`, `subject`, `subject-wide`,
`tall` (9:16), `wide` (16:9), `square` (1:1), `missing` — I verify the **featured poster actually
shows that fixture**, by sampling the painted frame, not by observing that `?art=` was accepted.
That is the defect I found at `f3f08930`: `withArt()` assigned the poster to `rows[0]` while the
screen picked its feature by date bucket, so every single-poster value silently painted a
non-feature row and left the feature empty.

**The event-name truncation is withdrawn until reproduced.** It is a recollection, not a finding,
and it will be reported only with the capture, full sha, fixture, appearance and text size that
show it — or not at all.

## Scope when I start

Home (4:5 feature, identity below, no gradient, header and filters, next-section figure measured
natively) · Listing (4:5 poster, info beneath, navigation reachable without covering printed text) ·
Option B footer **at rest** — the choice is closed and I will not reopen it · reservation feedback
via `?reserving=1`, confirming **"Reserving…" sits on the busy button, Buy Now in second position** ·
icons as **native rendering, recorded separately from my source cmap finding** · Dynamic Type at the
largest standard and accessibility sizes, scrolling, safe areas — all in Light and Dark.

No production call, no real reservation, no payment action, no fixture mutation, no EAS build.
