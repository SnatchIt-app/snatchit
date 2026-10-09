#!/bin/bash
# B native capture, candidate d5217530.
# Cold start (no stale route params) -> poll until the frame is STABLE and REAL -> save.
# usage: ncap2.sh "<path?query>" <outfile>
U=52282259-961E-4A1A-B32B-CEFA858CFF48
T="$1"; OUT="$2"; TMP=/tmp/_ncap
mkdir -p "$(dirname "$OUT")" "$TMP"
xcrun simctl terminate $U com.jdt-inc.snatchit >/dev/null 2>&1
sleep 2
xcrun simctl openurl $U "snatchit://$T" >/dev/null 2>&1
prev=""
for i in $(seq 1 18); do
  sleep 3
  xcrun simctl io $U screenshot "$TMP/f.png" >/dev/null 2>&1
  read -r state sig <<< "$(python3 - "$TMP/f.png" <<'PY'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); W,H=im.size; px=im.load()
pts=[(x,y) for x in range(60,W-60,90) for y in range(300,H-120,90)]
cols=[px[x,y] for x,y in pts]
red=sum(1 for c in cols if c[0]>200 and c[1]<60 and c[2]<60)
uniq=len(set(cols))
sig='-'.join(f'{c[0]:02x}{c[1]:02x}{c[2]:02x}' for c in cols[::7])
if red > len(cols)*0.5: print('ERRORBOX', sig)
elif uniq < 3:          print('BLANK', sig)
else:                   print('REAL', sig)
PY
)"
  if [ "$state" = "REAL" ] && [ "$sig" = "$prev" ]; then
    cp "$TMP/f.png" "$OUT"
    echo "  $(basename "$OUT")  ready after $((i*3))s"
    exit 0
  fi
  [ "$state" = "ERRORBOX" ] && { echo "  !! ERROR SCREEN for $T"; }
  prev="$sig"
done
cp "$TMP/f.png" "$OUT"
echo "  $(basename "$OUT")  NOT STABLE after 54s (state=$state) — treat with suspicion"
