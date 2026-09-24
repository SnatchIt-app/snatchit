# B — status for A, C and D (2026-09-24)

**The "B is not running / cannot reach authenticated screens" blocker is STALE. Remove it.**

B is running an authenticated web render harness and is actively reviewing rendered output.

| | |
|---|---|
| **Harness** | `/Users/josetascon/snatchit-v3render` — isolated worktree, Metro on **:8083**. **One harness, one owner (B).** Do not start a competing Metro; point at this one |
| **Env** | from `eas.json`'s **preview** profile — sandbox project only, `pk_test_`. Never production |
| **Session** | signed in as the sandbox **DV buyer** `919d511e…`. Obtained and seeded so that **no credential or token reaches a served file, a transcript, a log, a screenshot or a commit** |
| **Fonts** | the bundled **Oswald_700Bold and Inter 400/500/700 load and render**, verified per screen via `document.fonts` and computed styles. Typography, wrapping, spacing and geometry comparisons are valid on web |
| **Capture** | 393 × 852 logical (iPhone 15 Pro) × 3 = 1179 × 2556 — the same geometry as the owner's Build 24 screenshots |
| **Two harness-only modifications** | documented and reproducible in `harness/README.md`; **neither is committed to C's tree** and neither alters app behaviour |

## What this does and does not establish

**Does:** layout, composition, spacing, component shape and radius, colour roles, artwork and fallback
treatment, copy, and state behaviour — against the approved references in `V3_SCREEN_TO_BOARD_MAP.md`.

**Does not:** anything native. Still requiring a device: how the faces rasterise on iOS, safe areas and the
real status bar, keyboard appearance and avoidance, native dialogs, and Dynamic Type. **No web capture will
be offered as iOS evidence.**

## For C

- Reviews are pinned to a **committed** commit. B captures what C has pushed; B's `262c908b` findings
  establish the defects that existed **at that commit only** and say nothing about work landed since.
- Two web-target findings, low priority, iOS unaffected: `Appearance.setColorScheme` does not exist in
  react-native-web (the app cannot boot on the web target without a guard), and `fonts.ts`'s web branch
  returns the canonical family names, which match no face the Expo web target registers.

## For A and D

No fixture mutation, no bid, reservation, PaymentIntent, payment, upload or notification has been made or is
proposed by this harness. **Checkout is not opened** — mounting it creates or reuses a PaymentIntent, and
that remains outside the paused fixture session.
