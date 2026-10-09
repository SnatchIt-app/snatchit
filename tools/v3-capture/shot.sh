#!/bin/bash
# shot.sh <content_size> <appearance> <route-query> <outfile>
# Sets the text size and appearance, relaunches (a size change only applies on relaunch),
# deep-links twice (the first often lands before the bundle is ready), and captures only once
# the sandbox banner proves the app — not the dev-client launcher — is on screen.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=52282259-961E-4A1A-B32B-CEFA858CFF48
SIZE="$1"; APPEAR="$2"; ROUTE="$3"; OUT="$4"
xcrun simctl ui "$D" content_size "$SIZE" >/dev/null
xcrun simctl ui "$D" appearance "$APPEAR" >/dev/null
xcrun simctl terminate "$D" com.jdt-inc.snatchit >/dev/null 2>&1
xcrun simctl openurl "$D" "snatchit://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081" >/dev/null 2>&1
sleep 42
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1
sleep 8
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1
sleep 9
"$HERE/cap.sh" "$OUT" 120 || exit 1
echo "captured $OUT  size=$(xcrun simctl ui "$D" content_size) appearance=$(xcrun simctl ui "$D" appearance)"
