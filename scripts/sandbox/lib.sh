#!/bin/bash
# shared helpers for the sandbox harness — sourced by 10_provision.sh / 20_matrix.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
[ -f "$HERE/sandbox.env" ] || { echo "missing $HERE/sandbox.env (copy sandbox.env.example)"; exit 2; }
set -a; . "$HERE/sandbox.env"; set +a
PROD_REF=hqycwntpfoztoinemqns
[ -n "${TEST_REF:-}" ] || { echo "TEST_REF empty"; exit 2; }
[ "$TEST_REF" != "$PROD_REF" ] || { echo "REFUSING: TEST_REF is the production project"; exit 3; }
case "${TEST_DB_URL:-}" in *"$PROD_REF"*) echo "REFUSING: TEST_DB_URL points at production"; exit 3;; esac
FN="https://$TEST_REF.supabase.co/functions/v1"; REST="https://$TEST_REF.supabase.co/rest/v1"; AUTH="https://$TEST_REF.supabase.co/auth/v1"
OUT="${SANDBOX_OUT:-./sandbox_out}"; mkdir -p "$OUT"; RESULTS="$OUT/RESULTS_$(date +%Y%m%d_%H%M%S).md"
PASS=0; FAILN=0
ok()  { PASS=$((PASS+1));  echo "PASS  $1"; echo "| PASS | $1 | REAL |" >> "$RESULTS"; }
bad() { FAILN=$((FAILN+1)); echo "FAIL  $1  [$2]"; echo "| FAIL | $1 | $2 |" >> "$RESULTS"; }
note(){ echo "NOTE  $1"; echo "| NOTE | $1 |  |" >> "$RESULTS"; }
sql() { psql "$TEST_DB_URL" -X -qtA -v ON_ERROR_STOP=1 -c "$1" 2>&1; }
check(){ local name="$1" q="$2" want="$3"; local got; got=$(sql "$q" | tr -d '[:space:]'); [ "$got" = "$want" ] && ok "$name" || bad "$name" "want=$want got=$(printf '%s' "$got" | head -c 160)"; }
jwt() { curl -s -X POST "$AUTH/token?grant_type=password" -H "apikey: $TEST_ANON_KEY" -H 'content-type: application/json' -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '.access_token // empty'; }
uid() { curl -s "$AUTH/user" -H "apikey: $TEST_ANON_KEY" -H "Authorization: Bearer $1" | jq -r '.id // empty'; }
edge(){ local fn="$1" tok="$2" body="$3"; curl -s -w '\n%{http_code}' -X POST "$FN/$fn" -H "Authorization: Bearer $tok" -H "apikey: $TEST_ANON_KEY" -H 'content-type: application/json' -d "$body"; }
rpc() { local name="$1" tok="$2" body="$3"; curl -s -w '\n%{http_code}' -X POST "$REST/rpc/$name" -H "Authorization: Bearer $tok" -H "apikey: $TEST_ANON_KEY" -H 'content-type: application/json' -d "$body"; }
need(){ for c in "$@"; do command -v "$c" >/dev/null || { echo "missing tool: $c"; exit 4; }; done; }
# The Stripe CLI prints a "Running in <sandbox>" banner before JSON when a sandbox
# context is active; strip everything before the first JSON token so jq can parse.
sjson(){ stripe "$@" 2>/dev/null | sed -n '/^[[{]/,$p'; }
# assert a shell variable is non-empty before it is used in an assertion, so a
# missing id can never make a later check pass vacuously
req(){ local name="$1" val="$2"; [ -n "$val" ] && return 0; bad "$name" "required value is empty — dependent checks skipped"; return 1; }
stripe_mode_guard(){ local lm acct; lm=$(stripe get /v1/balance 2>/dev/null | jq -r 'if .livemode == false then "false" elif .livemode == true then "true" else "unknown" end'); acct=$(stripe get /v1/account 2>/dev/null | jq -r '.id // "?"'); [ "$lm" = "false" ] || { echo "REFUSING: stripe CLI is not in test mode (livemode=$lm)"; exit 3; }; [ "$acct" != "acct_1T6FarGdOzCmGbHw" ] || { echo "REFUSING: stripe CLI context is the LIVE platform account"; exit 3; }; note "stripe context $acct livemode=false"; }
wait_for(){ local name="$1" q="$2" want="$3" secs="${4:-60}"; local i=0; while [ $i -lt "$secs" ]; do [ "$(sql "$q" | tr -d '[:space:]')" = "$want" ] && { ok "$name"; return 0; }; sleep 2; i=$((i+2)); done; bad "$name" "timeout ${secs}s want=$want got=$(sql "$q" | tr -d '[:space:]' | head -c 120)"; return 1; }
echo "# Sandbox run $(date -u +%FT%TZ) — project $TEST_REF (Stripe test mode)" > "$RESULTS"; echo "" >> "$RESULTS"; echo "| result | step | evidence class |" >> "$RESULTS"; echo "|---|---|---|" >> "$RESULTS"
