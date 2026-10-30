#!/bin/bash
# LOCAL-ONLY pgTAP runner without pg_prove: 000_helpers commits, every other file
# runs BEGIN…ROLLBACK; TAP lines are parsed from psql -tA output. Known
# local-only differences from CI: 060's two pinned TODOs report as not_ok, 131
# needs the `authenticator` role, 132 needs real pg_cron (cron.database_name).
# usage: runtests.sh <dbname> [files...]
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; T="$ROOT/supabase/tests"; DB="$1"; shift
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$T/000_helpers.sql" >/dev/null 2>&1 || { echo "HELPERS FAILED"; exit 1; }
files=${@:-$(ls $T/*.sql | grep -v 000_helpers)}
tot_ok=0; tot_nok=0; tot_plan=0; rc=0
for f in $files; do
  out=$(psql -q -tA -d "$DB" -v ON_ERROR_STOP=0 -f "$f" 2>&1)
  plan=$(printf '%s\n' "$out" | grep -m1 -oE '^1\.\.[0-9]+' | cut -d. -f3)
  ok=$(printf '%s\n' "$out" | grep -cE '^ok [0-9]+'); nok=$(printf '%s\n' "$out" | grep -cE '^not ok [0-9]+'); err=$(printf '%s\n' "$out" | grep -cE '^psql:.*ERROR')
  status=PASS; if [ "$nok" -gt 0 ] || [ "$err" -gt 0 ] || [ "${plan:-0}" -ne $((ok+nok)) ]; then status=FAIL; rc=1; fi
  printf '%-52s plan=%-4s ok=%-4s not_ok=%-3s psql_err=%-2s %s\n' "$(basename $f)" "${plan:-?}" "$ok" "$nok" "$err" "$status"
  printf '%s\n' "$out" | grep -E '^not ok|^psql:.*ERROR|^#' | grep -v "^# Subtest\|^#\s*$" | head -40
  tot_ok=$((tot_ok+ok)); tot_nok=$((tot_nok+nok)); tot_plan=$((tot_plan+${plan:-0}))
done
echo "TOTAL plan=$tot_plan ok=$tot_ok not_ok=$tot_nok $([ $rc -eq 0 ] && echo ALL-PASS || echo FAILURES)"; exit $rc
