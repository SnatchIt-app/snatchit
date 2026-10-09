#!/bin/bash
# B's V3 render harness. Captures the REAL app at iPhone 15 Pro logical size (393x852 @3x).
# Usage: ./capture.sh <out-dir> <route-path> <name>   e.g. ./capture.sh out "/" login
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="${1:?out dir}"; ROUTE="${2:?route}"; NAME="${3:?name}"; PORT="${PORT:-8083}"
mkdir -p "$OUT"
"$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --window-size=393,852 --force-device-scale-factor=3 \
  --screenshot="$OUT/$NAME.png" --virtual-time-budget="${BUDGET:-20000}" \
  "http://localhost:$PORT$ROUTE" >/dev/null 2>&1
python3 - "$OUT/$NAME.png" <<'PY'
import sys
from PIL import Image
im=Image.open(sys.argv[1]); print(f"{sys.argv[1]}  {im.size[0]}x{im.size[1]}")
PY
