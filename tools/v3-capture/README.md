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
