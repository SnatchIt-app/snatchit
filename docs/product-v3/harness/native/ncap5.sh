#!/bin/bash
U=52282259-961E-4A1A-B32B-CEFA858CFF48
T="$1"; OUT="$2"; mkdir -p "$(dirname "$OUT")"
xcrun simctl openurl $U "snatchit://_dev/foundation" >/dev/null 2>&1; sleep 5
xcrun simctl openurl $U "snatchit://$T" >/dev/null 2>&1
prev=""
for i in $(seq 1 10); do
  sleep 3
  xcrun simctl io $U screenshot "$OUT" >/dev/null 2>&1
  read -r app sig <<< "$(python3 - "$OUT" <<'PY'
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); W,H=im.size; px=im.load()
b=px[600,150]
app='APP' if (abs(b[0]-122)<40 and abs(b[1]-59)<40 and b[2]<50) else 'NOTAPP'
cols=[px[x,y] for x in range(60,W-60,70) for y in range(300,H-200,70)]
print(app, f"{len(set(cols))}:" + '-'.join(f'{c[0]:02x}{c[1]:02x}{c[2]:02x}' for c in cols[::9]))
PY
)"
  n=${sig%%:*}
  if [ "$app" = "APP" ] && [ "$sig" = "$prev" ] && [ "$n" -gt 1 ]; then echo "  $(basename "$OUT") ok"; exit 0; fi
  prev="$sig"
done
echo "  $(basename "$OUT") FAILED(app=$app)"; exit 1
