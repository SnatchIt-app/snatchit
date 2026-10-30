#!/usr/bin/env bash
# Bundle scripts/hermes/session-smoke.entry.ts through the project's own Metro
# (same graph, same transforms as the app) and execute it under the Hermes CLI.
# Requires Metro on $PORT (default 8082). Prints SMOKE_OK or SMOKE_FAIL.
set -uo pipefail
PORT="${PORT:-8082}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERMES="$ROOT/node_modules/react-native/sdks/hermesc/osx-bin/hermes"
OUT="${TMPDIR:-/tmp}/session-smoke.hermes.js"
[ -x "$HERMES" ] || { echo "SMOKE_SKIP no hermes binary at $HERMES"; exit 2; }
curl -sf -o "$OUT" "http://localhost:$PORT/scripts/hermes/session-smoke.entry.bundle?platform=ios&dev=false&minify=false&runModule=true" || { echo "SMOKE_FAIL metro bundle request failed"; exit 1; }
grep -q '"type":"' "$OUT" && head -c 400 "$OUT" && { echo; echo "SMOKE_FAIL metro returned an error payload"; exit 1; }
"$HERMES" -w "$OUT" 2>&1 | tail -20
