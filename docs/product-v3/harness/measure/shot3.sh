#!/bin/bash
# B's size-asserted capture: the size is read back BEFORE the relaunch, AFTER the relaunch and
# AFTER the capture, and any disagreement voids the frame. shot.sh reported
# accessibility-extra-extra-extra-large at the end of a run that asked for
# extra-extra-extra-large, so the readback is now a gate rather than a note.
set -u
HERE=/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund/tools/v3-capture
D=52282259-961E-4A1A-B32B-CEFA858CFF48
SIZE="$1"; ROUTE="$2"; OUT="$3"
chk () { got="$(xcrun simctl ui "$D" content_size)"; echo "  [$1] content_size=$got"
         [ "$got" = "$SIZE" ] || { echo "  VOID: wanted $SIZE"; exit 3; }; }
xcrun simctl ui "$D" content_size "$SIZE" >/dev/null; chk "set"
xcrun simctl terminate "$D" com.jdt-inc.snatchit >/dev/null 2>&1
xcrun simctl openurl "$D" "snatchit://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081" >/dev/null 2>&1
sleep 42; chk "after relaunch"
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1; sleep 8
xcrun simctl openurl "$D" "snatchit://$ROUTE" >/dev/null 2>&1; sleep 9
"$HERE/cap.sh" "$OUT" 120 || exit 1
chk "after capture"; echo "  OK $OUT"
