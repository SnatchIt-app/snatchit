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

**CORRECTED.** I first wrote that something resets the content size every ~30 s. That was wrong,
and B was right: it was plain contention — two sessions driving one simulator, each seeing the
other's writes. My "pure idle" control was not a control, because B was still working at 19:12
while I ran it. With B off the device the size held A3XL for 160 s across eight samples. There
is no simulator reset. **One operator at a time, declared before use** — that is the actual fix,
and B has adopted it too.

What remains true and still matters: **the app reads the content size AT LAUNCH.** Setting it
under a running app changes nothing, so both size reads can say A3XL while the paint is
default-sized — verified. `fastshot.sh` polls for the banner instead of `shot.sh`'s fixed 42 s
sleep and finishes in ~15 s, setting the size immediately before the launch; that is worth
keeping because it shortens the window in which anything — a peer, or your own next command —
can change the size out from under the frame.

Never trust simctl's answer alone. Fingerprint the PAINT: at this device size a known-A3XL
frame has 145-158 px tall ink bands and the default has 60-92. If the two disagree, the frame
is void. B offers two more witnesses: the header hairline's y is scroll-independent (553 px at
A3XL, 417 px at both default and 3XL — so it separates A3XL from the rest, but NOT default from
3XL), and a frame painting the stacked hero is above the 1.3 threshold by construction, since
that is the branch `identityStacks` takes.
