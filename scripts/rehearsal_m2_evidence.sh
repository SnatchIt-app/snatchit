#!/usr/bin/env bash
# scripts/rehearsal_m2_evidence.sh — LOCAL REHEARSAL ONLY.
# Captures REAL `venue.get_door_manifest` output from the local rehearsal
# database into tests/fixtures/m2-rehearsal-evidence.json (the capture
# transaction is ROLLED BACK; the database is left untouched). Never points at
# production: the DSN is the local harness default and must be a localhost URL.
set -euo pipefail
DBNAME="${1:-snatchit_rehearsal}"
DSN="${REHEARSAL_DSN:-postgresql://postgres@127.0.0.1:5432/${DBNAME}}"
case "$DSN" in *127.0.0.1*|*localhost*) ;; *) echo "refusing non-local DSN" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/tests/fixtures/m2-rehearsal-evidence.json"
psql -v ON_ERROR_STOP=1 -q "$DSN" -f "$ROOT/supabase/tests/000_helpers.sql" >/dev/null
psql -v ON_ERROR_STOP=1 -q -At "$DSN" -f "$ROOT/scripts/rehearsal_m2_evidence.sql" > "$OUT"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('captured keys:', sorted(d))" "$OUT"
echo "wrote $OUT"
