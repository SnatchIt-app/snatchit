#!/bin/bash
# O-R4: rehearse the EXACT filled R3 files on a local clone. LOCAL ONLY.
# Usage: bash run_R3_filled.sh <or4_r3_filled* database, fresh clone of pkg151_rehears> <sha256 #6> <sha256 #7>
set -uo pipefail
DB=${1:?database}; WANT6=${2:?sha256 of #6}; WANT7=${3:?sha256 of #7}
case "$DB" in or4_r3_filled*) :;; *) echo "refusing database $DB"; exit 2;; esac
HERE=$(cd "$(dirname "$0")" && pwd); PKG=$(dirname "$HERE")
P6="$PKG/R3_proposed_6_32913315.sql"; P7="$PKG/R3_proposed_7_700d469b.sql"
PSQL=(psql -h 127.0.0.1 -U postgres -d "$DB" -X -v ON_ERROR_STOP=1)
q() { "${PSQL[@]}" -At -F' | ' "$@"; }
FAIL=0; pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; FAIL=1; }

h6=$(shasum -a 256 "$P6" | cut -c1-64); h7=$(shasum -a 256 "$P7" | cut -c1-64)
[ "$h6" = "$WANT6" ] && pass "#6 file is $h6" || { fail "#6 sha $h6 != $WANT6"; exit 3; }
[ "$h7" = "$WANT7" ] && pass "#7 file is $h7" || { fail "#7 sha $h7 != $WANT7"; exit 3; }
grep -q "__R1_\|__OWNER_" "$P6" "$P7" && { fail "a marker remains"; exit 3; } || pass "no marker remains in either file"

echo "== R3 filled run $(date -u +%FT%TZ) on $DB (ledger $(q -c 'select count(*) from supabase_migrations.schema_migrations'))"
"${PSQL[@]}" -q -f "$HERE/R2_fixtures.sql" >/dev/null || { echo "fixtures failed"; exit 3; }
echo "== R4 read-back BEFORE"; q -f "$PKG/R4_readback.sql"
before=$(q -c "select ops.detect_refunds()::text")
for n in 6 7; do
  f=$P6; [ $n = 7 ] && f=$P7
  out=$("${PSQL[@]}" -q -f "$f" 2>&1); rc=$?
  [ $rc -eq 0 ] && grep -q "R3_OK" <<<"$out" && pass "#$n: $(grep -oE 'R3_OK.*' <<<"$out" | cut -c1-160)" || fail "#$n rc=$rc: $(head -3 <<<"$out")"
done
after=$(q -c "select ops.detect_refunds()::text")
echo "== R4 read-back AFTER"; q -f "$PKG/R4_readback.sql"
got=$(q -c "select string_agg(p.total || ':' || p.amount_refunded_cents || ':' || p.refund_requested_cents || ',' || p.refund_succeeded_cents || ',' || p.refund_failed_cents
                         || ':' || p.stripe_refund_id || ':' || p.status || ':' || to_char(p.refunded_at at time zone 'UTC','HH24:MI:SS'), ' ' order by p.total desc)
            from public.payments p where p.id in ('32913315-2bf7-4e58-b837-f6c5c34b722b','700d469b-045c-430f-8d16-351d9ff3b838')")
want="1100:1100:0,1100,0:re_3U0XuwGdOzCmGbHw0bL9UYzT:refunded:17:20:05 220:220:0,220,0:re_3U0YzcGdOzCmGbHw0Av5k7ZH:refunded:17:20:19"
[ "$got" = "$want" ] && pass "payments after: $got" || fail "payments after: $got (want $want)"
st=$(q -c "select string_agg(s.stripe_refund_id || ':' || s.status || ':' || s.amount_cents || ':' || s.source || ':' || s.last_observed_via, ' ' order by s.amount_cents desc) from public.payment_refund_state s")
[ "$st" = "re_3U0XuwGdOzCmGbHw0bL9UYzT:succeeded:1100:dashboard:reconcile re_3U0YzcGdOzCmGbHw0Av5k7ZH:succeeded:220:dashboard:reconcile" ] && pass "state rows: $st" || fail "state rows: $st"
c=$(q -c "select (select count(*) from public.payment_refund_state_log) || ' log, ' || (select count(*) from public.payment_refunds where payment_id in ('32913315-2bf7-4e58-b837-f6c5c34b722b','700d469b-045c-430f-8d16-351d9ff3b838')) || ' ledger, ' || (select count(*) from ops.\"case\") || ' cases'")
[ "$c" = "2 log, 2 ledger, 0 cases" ] && pass "rows: $c" || fail "rows: $c"
echo "   detect_refunds before: $before"; echo "   detect_refunds after:  $after"
[ "$(jq .opened <<<"$after")" = 0 ] && [ "$(jq -c '{scanned,opened}' <<<"$before")" = "$(jq -c '{scanned,opened}' <<<"$after")" ] && pass "detect_refunds opened 0, unchanged" || fail "detect_refunds changed"
err=$("${PSQL[@]}" -q -f "$P6" 2>&1 >/dev/null); rc=$?
[ $rc -ne 0 ] && grep -q "R3_GUARD prestate:" <<<"$err" && pass "re-running #6 is refused: $(grep -oE 'R3_GUARD[^"]*' <<<"$err" | head -1 | cut -c1-100)" || fail "re-run #6 rc=$rc"
echo "== RESULT: $([ $FAIL = 0 ] && echo ALL PASS || echo FAILURES)"
exit $FAIL
