#!/bin/bash
# cap.sh <outfile> [max_seconds] — capture only once the app's sandbox banner is on screen.
#
# WHY IT STAGES THROUGH A LOCAL FILE. `simctl io screenshot` is performed by the CoreSimulator
# service, not by this shell, and that service is denied writes to the external volume:
#
#   An error was encountered processing the command (domain=NSCocoaErrorDomain, code=513):
#   You don't have permission to save the file "_probe.png" in the folder "857e6d93".
#   Underlying error (domain=NSPOSIXErrorDomain, code=1): Operation not permitted
#
# This shell writes to the same directory without trouble, so the capture is taken on the
# internal disk and copied into place afterwards. The first window on the SSD lost every frame
# to this, silently, because the error was sent to /dev/null — so the error is no longer hidden.
D=52282259-961E-4A1A-B32B-CEFA858CFF48
OUT="$1"; MAX="${2:-90}"; n=0
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"
STAGE="${TMPDIR:-/tmp}/cap-$$.png"

while [ $n -lt "$MAX" ]; do
  err="$(xcrun simctl io "$D" screenshot "$STAGE" 2>&1 >/dev/null)"
  if [ ! -s "$STAGE" ]; then
    printf 'SCREENSHOT FAILED — %s\n' "$(printf '%s' "$err" | tr '\n' ' ' | cut -c1-200)" >&2
    exit 2
  fi
  if python3 - "$STAGE" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
# the sandbox banner band, sampled across the width well inside the status bar
px = [im.getpixel((x, 160)) for x in range(100, 1080, 40)]
r = sum(p[0] for p in px)/len(px); g = sum(p[1] for p in px)/len(px); b = sum(p[2] for p in px)/len(px)
# brown: red dominant, green mid, blue low — and not the red splash (which has g,b near 0 and r very high)
sys.exit(0 if (90 < r < 190 and 30 < g < 110 and b < 60) else 1)
PY
  then
    cp "$STAGE" "$OUT" && rm -f "$STAGE"
    echo "banner present after ${n}s"; exit 0
  fi
  sleep 3; n=$((n+3))
done
rm -f "$STAGE"
echo "BANNER NEVER APPEARED after ${MAX}s — frame not accepted"; exit 1
