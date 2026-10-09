#!/bin/bash
# nav.sh <route-query> <outfile> — deep-link (twice; the first can land mid-bundle) and capture
# once the sandbox banner proves the app is on screen. NO relaunch: the content size is already
# applied, and relaunching would cost 40s a frame.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=52282259-961E-4A1A-B32B-CEFA858CFF48
ROUTE="$1"; OUT="$2"
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1
sleep 5
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1
sleep 6
"$HERE/cap.sh" "$OUT" 90 || exit 1
echo "$OUT  size=$(xcrun simctl ui "$D" content_size)  appearance=$(xcrun simctl ui "$D" appearance)"
