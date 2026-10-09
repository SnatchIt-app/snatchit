#!/bin/bash
# B native capture — COLD START per capture so route params cannot be stale.
# usage: ncap.sh "<path?query>" <outfile> [settle]
U=52282259-961E-4A1A-B32B-CEFA858CFF48
xcrun simctl terminate $U com.jdt-inc.snatchit >/dev/null 2>&1
sleep 2
xcrun simctl openurl $U "snatchit://$1" >/dev/null 2>&1
sleep "${3:-22}"
xcrun simctl io $U screenshot "$2" >/dev/null 2>&1
python3 - "$2" <<'PY'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); px=im.load()
cols={px[x,y] for x in (120,400,760,1060) for y in (600,900,1300,1700)}
print(f'  {sys.argv[1].split("/")[-1]}  {im.size[0]}x{im.size[1]}  feature-region distinct colours: {len(cols)}')
PY
