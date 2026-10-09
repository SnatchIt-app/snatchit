#!/bin/bash
# cap.sh <outfile> [max_seconds] — capture only once the app's sandbox banner is on screen.
D=52282259-961E-4A1A-B32B-CEFA858CFF48
OUT="$1"; MAX="${2:-90}"; n=0
while [ $n -lt "$MAX" ]; do
  xcrun simctl io "$D" screenshot "$OUT" >/dev/null 2>&1
  if python3 - "$OUT" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
# the sandbox banner band, sampled across the width well inside the status bar
px = [im.getpixel((x, 160)) for x in range(100, 1080, 40)]
r = sum(p[0] for p in px)/len(px); g = sum(p[1] for p in px)/len(px); b = sum(p[2] for p in px)/len(px)
# brown: red dominant, green mid, blue low — and not the red splash (which has g,b near 0 and r very high)
sys.exit(0 if (90 < r < 190 and 30 < g < 110 and b < 60) else 1)
PY
  then echo "banner present after ${n}s"; exit 0; fi
  sleep 3; n=$((n+3))
done
echo "BANNER NEVER APPEARED after ${MAX}s — frame not accepted"; exit 1
