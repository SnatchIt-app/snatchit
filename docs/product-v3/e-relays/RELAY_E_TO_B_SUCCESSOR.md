# E → B: native review on C's successor (owner, 2026-10-05, corrected)

**Now:** acknowledge this handoff, either directly or in a committed line in your review file.
Also answer the Metro question below.

## Metro: one operator, agreed before any restart
- **The current server:** `:8081` is pid 2172, `expo start`, started 2026-09-26 16:56. Its cwd is
  `/Users/josetascon/snatchit-refund` at `f3f08930`. The owner says you started it.
- **E's proposal:** C operates Metro and the simulator connection for the review window, and you
  operate the app only.
- **What happens next:** confirm or counter-propose. Nobody restarts or repoints it until you and C
  agree.

## Target
C's named successor. It must contain:
- Listing artwork selection (`?art=`);
- the Home feature-selection fix, or a reproduction showing there is no bug;
- the reserving seam (`?reserving=1`).

**Start only after C confirms** the serving directory, the sha, clean status and that the dev client
is connected. Record `git -C <serving dir> rev-parse HEAD` and a clean `git status` at your start
and end.

**If the serving tree changes mid-review:** pause, list which captures became uncertain, and keep
every capture whose provenance is established. Don't discard earlier work wholesale.

**Device:** `SN V3 393x852`: iPhone 16, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`, iOS 26.5
(23F77). Taps are in points. `:8083` is not native evidence.

## Review, Light and Dark (full re-run; no native evidence survives)
- **Home:** 4:5 feature, identity below, no gradient, header and filters, next section measured.
  **For each artwork key, check that the named poster is what appears in the featured frame**, not
  just that the URL was accepted: `flyer`, `subject`, `subject-wide`, `tall`, `wide`, `square`,
  `missing`.
- **Listing:** 4:5 poster, info beneath, navigation reachable without covering printed text. Same
  artwork keys.
- **Footer:** Option B at rest. It's closed, so don't reopen the choice.
- **Reservation feedback:** with `?reserving=1`, "Reserving…" sits on the second-position Buy Now.
- **Icons:** native rendering, recorded separately from your source cmap finding.
- **Native:** Dynamic Type (largest standard and accessibility sizes), scrolling, safe areas.
- **Event-name truncation:** reproduce it before reporting it. Report it with the capture, commit,
  fixture and text size.

## Evidence
- Save each meaningful capture to `docs/product-v3/native/<sha8>/` as you go.
  Name it `<surface>-<state>-<fixture>-<appearance>[-<textsize>].png`.
- Commit findings incrementally. Each one names the full sha, device, runtime and fixture.
- **Shared checkout:** commit by explicit path. E commits only `V3_ACCEPTANCE_RECORD.md`.
- **If one state is blocked:** report the concrete blocker and continue the rest.

**Limits:** no production actions, real reservations or payments, fixture mutations or EAS builds.
