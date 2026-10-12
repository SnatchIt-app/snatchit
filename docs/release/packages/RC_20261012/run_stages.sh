#!/bin/bash
# run_stages.sh: run every independent quality stage of a candidate checkout; never stop at the first failure.
#
# Why this exists: CI's quality job runs its steps in sequence, so its first failing step hides every later step.
# For 17 days the parity suite never loaded while the job reported only the ML7 failure in front of it.
# The ci.yml fix is parked (owner-gated), so this local runner substitutes when CI is red:
# - each stage runs in its own subshell, with its own log and its own exit status;
# - every stage runs whatever happened before it;
# - the overall exit status is 1 if ANY stage failed.
#
# usage: run_stages.sh <candidate-checkout> <log-dir> [stage ...]   (no stage names = all stages)
#        run_stages.sh --selftest                                   (proves the continue/overall-fail rule)
# Stages (the CI job is in brackets):
#   env-pairing, typecheck, lint, unit, parity                       [Typecheck / Lint / Unit tests]
#   web-typecheck, web-lint, web-unit, web-build                     [Web build (Next.js)]
#   admin-typecheck, admin-lint, admin-unit, admin-build             [Admin console (Next.js)]
#   deno                                                             [Deno type-check]; FAILS when deno is absent
#   replay                                                           local LC_ALL=C replay (scripts/local/replay.sh)
# The stages assume dependencies are already installed (npm ci in ., web/ and admin/). The runner never installs
# anything itself, and it never touches a remote database.
set -u

run_all() {  # $1 = log dir; remaining args are "name<TAB>command" lines
  local logdir="$1"; shift
  mkdir -p "$logdir"
  local failed=0 summary="" name cmd rc
  for spec in "$@"; do
    name="${spec%%$'\t'*}"; cmd="${spec#*$'\t'}"
    ( eval "$cmd" ) >"$logdir/$name.log" 2>&1; rc=$?
    if [ "$rc" -eq 0 ]; then summary+="PASS  $name"$'\n'; else summary+="FAIL  $name (exit $rc)"$'\n'; failed=1; fi
  done
  printf '%s' "$summary" | tee "$logdir/SUMMARY.txt"
  if [ "$failed" -eq 0 ]; then echo "OVERALL: PASS" | tee -a "$logdir/SUMMARY.txt"; return 0; fi
  echo "OVERALL: FAIL" | tee -a "$logdir/SUMMARY.txt"; return 1
}

if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"
  out="$(run_all "$d/a" $'s1\ttrue' $'s2\tfalse' $'s3\ttrue')"; rc=$?
  want=$'PASS  s1\nFAIL  s2 (exit 1)\nPASS  s3\nOVERALL: FAIL'
  [ "$out" = "$want" ] && [ "$rc" -eq 1 ] || { echo "SELFTEST FAIL: a later stage was skipped or the overall status was wrong"; printf '%s\n' "$out"; exit 2; }
  out="$(run_all "$d/b" $'s1\ttrue' $'s2\ttrue')"; rc=$?
  [ "$out" = $'PASS  s1\nPASS  s2\nOVERALL: PASS' ] && [ "$rc" -eq 0 ] || { echo "SELFTEST FAIL: an all-pass run did not pass"; exit 2; }
  out="$(run_all "$d/c" $'s1\texit 3' $'s2\ttrue')"; rc=$?
  [ "$out" = $'FAIL  s1 (exit 3)\nPASS  s2\nOVERALL: FAIL' ] && [ "$rc" -eq 1 ] || { echo "SELFTEST FAIL: a stage that exits stopped the runner"; exit 2; }
  rm -rf "$d"; echo "SELFTEST PASS (continue-after-failure, overall-fail, exit inside a stage)"; exit 0
fi

ROOT="${1:?candidate checkout}"; LOGS="${2:?log dir}"; shift 2
declare -a ALL=(
  $'env-pairing\tcd "$ROOT" && node scripts/ci/assert-env-pairing.mjs'
  $'typecheck\tcd "$ROOT" && npm run typecheck'
  $'lint\tcd "$ROOT" && npm run lint'
  $'unit\tcd "$ROOT" && npm run test'
  $'parity\tcd "$ROOT" && npx vitest run -c packages/vitest.config.ts'
  $'web-typecheck\tcd "$ROOT/web" && npm run typecheck'
  $'web-lint\tcd "$ROOT/web" && npm run lint'
  $'web-unit\tcd "$ROOT/web" && npm run test'
  $'web-build\tcd "$ROOT/web" && npm run build'
  $'admin-typecheck\tcd "$ROOT/admin" && npm run typecheck'
  $'admin-lint\tcd "$ROOT/admin" && npm run lint'
  $'admin-unit\tcd "$ROOT/admin" && npm test'
  $'admin-build\tcd "$ROOT/admin" && npm run build'
  $'deno\tcommand -v deno >/dev/null || { echo "deno is not installed: this stage FAILS rather than passing silently"; exit 127; }; cd "$ROOT" && deno check supabase/functions/*/index.ts'
  $'replay\tcd "$ROOT" && PGHOST=${PGHOST:-127.0.0.1} PGUSER=${PGUSER:-postgres} bash scripts/local/replay.sh "${REPLAY_DB:-rc_stage_replay}"'
)
declare -a PICK=()
if [ "$#" -eq 0 ]; then PICK=("${ALL[@]}"); else
  for want in "$@"; do hit=0; for spec in "${ALL[@]}"; do [ "${spec%%$'\t'*}" = "$want" ] && { PICK+=("$spec"); hit=1; }; done
    [ "$hit" -eq 1 ] || { echo "unknown stage: $want"; exit 2; }; done
fi
export ROOT
run_all "$LOGS" "${PICK[@]}"
