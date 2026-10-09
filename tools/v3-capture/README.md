# v3 device-capture helpers (C)

Lifted out of the session scratchpad before the external-drive migration, because they
encode discipline that was learned the hard way and would otherwise be retyped wrong.

| file | what it is for |
|---|---|
| `cap.sh` | capture ONLY once the sandbox banner is on screen. B's first run captured the dev-client launcher three times; this gate is why no frame since can be that. |
| `shot.sh` | size + appearance + relaunch + double deep-link + gated capture. A content-size change only applies on RELAUNCH — two frames were once mislabelled 3XL/A3XL for want of this. The deep link is sent twice because the first can land before the bundle is ready. |
| `nav.sh` | deep-link + gated capture with NO relaunch, for moving between routes at a size already applied. |
| `ink.py`, `ink2.py` | ink-height / ink-extent bands in points (`ink2` handles Dark, where the detector otherwise reads the black canvas as ink). |
| `mut_rep.py` | the mutation harness shape: clean baseline, assert the mutant applied AND differs, run, digest-verified restore. Predict the kill set before running; a surprise is a signal about the method, not a bonus. |

Gesture rules these scripts do not enforce, and which cost a frame each to learn
(`native/9498080a/capture-log.txt` and `method/` hold the controls):

1. At A3XL the Listing footer takes roughly the bottom 300 pt — a drag starting at y=700 pt
   is on the sticky bar and scrolls nothing. Drag inside the content band (y 460 → 170).
2. Two touch paths injected back-to-back: the second is dropped. Leave >= 2 s between them
   and diff the frame to confirm the scroll happened before overwriting a good capture.
3. A fast release flicks with momentum. A damped tail — three samples with <= 2 pt of
   movement at 60/120/150 ms — lands where it is aimed.
4. Device points are 393x852; the screenshots are 1179x2556 (@3x), so divide by 3.

## Paths after the SSD migration (9 October 2026)

`shot.sh` and `nav.sh` called `/tmp/cap.sh`, which the migration record flags as exactly the
assumption not to carry over. They now resolve `cap.sh` beside themselves, so the set works
from wherever this folder lives. `ink.py` / `ink2.py` / `mut_rep.py` take their paths as
arguments and needed no change. Nothing here writes outside the path it is given.

## Two device traps found on 9 October 2026

**`simctl ui … appearance` does not drive this app's theme.** The harness reads
`useAppearancePreference`, so the stored preference wins and a frame can come back Dark while
simctl reports light (B hit this and discarded the frame). Always pass `?appearance=light|dark`
in the route — every script here does.

**The content size is reset by something else on this machine, roughly every 30 s.** Not these
scripts: set / terminate / openurl all preserve it, and it also drops during pure idle. Two
things follow. The app reads the size AT LAUNCH, so setting it under a running app changes
nothing — both size reads can say A3XL while the paint is default-sized. And `shot.sh`'s fixed
42 s sleep loses the race, which is why `fastshot.sh` exists: it polls for the banner instead
and finishes in ~15 s, setting the size immediately before the launch.

Never trust simctl's answer alone. Fingerprint the PAINT: at this device size a known-A3XL
frame has 145-158 px tall ink bands and the default has 60-92. If the two disagree, the frame
is void.
