#!/bin/bash
# fastshot.sh <content_size> <appearance> <route-query> <outfile>
# A relaunch that POLLS instead of sleeping, because something on this machine resets the
# simulator's content size roughly every 30 s and the app only reads that size AT LAUNCH.
# shot.sh's fixed 42 s sleep loses that race; this finishes inside it. Every frame is still
# gated on the sandbox banner, and the size is read immediately before and after the capture —
# a frame whose two reads disagree is void.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=52282259-961E-4A1A-B32B-CEFA858CFF48
SIZE="$1"; APPEAR="$2"; ROUTE="$3"; OUT="$4"
xcrun simctl ui "$D" appearance "$APPEAR" >/dev/null
xcrun simctl terminate "$D" com.jdt-inc.snatchit >/dev/null 2>&1
xcrun simctl ui "$D" content_size "$SIZE" >/dev/null     # set LAST, immediately before launch
START="$(xcrun simctl ui "$D" content_size)"
xcrun simctl openurl "$D" "snatchit://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081" >/dev/null 2>&1
"$HERE/cap.sh" "${TMPDIR:-/tmp}/fastshot-wait.png" 90 >/dev/null || { echo "app never came up"; exit 1; }
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1
sleep 2
PRE="$(xcrun simctl ui "$D" content_size)"
"$HERE/cap.sh" "$OUT" 30 >/dev/null || { echo "no banner for the route frame"; exit 1; }
POST="$(xcrun simctl ui "$D" content_size)"
echo "set=$START pre=$PRE post=$POST appearance=$(xcrun simctl ui "$D" appearance) at $(date +%H:%M:%S)"
[ "$PRE" = "$SIZE" ] && [ "$POST" = "$SIZE" ] || { echo "VOID — the device changed size around this capture"; exit 2; }
echo "frame accepted: $OUT"
