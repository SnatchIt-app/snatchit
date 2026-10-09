#!/bin/bash
# O-R4 R2 rehearsal runner. LOCAL ONLY: refuses any host but 127.0.0.1 and any database but or4_r2_rehears*.
# Usage: bash run_R2.sh <database>   (a fresh clone of pkg151_rehears, ledger 164)
set -uo pipefail
DB=${1:?database}
case "$DB" in or4_r2_rehears*) :;; *) echo "refusing database $DB"; exit 2;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "$HERE")
GEN="$HERE/out/gen"; mkdir -p "$GEN"
PSQL=(psql -h 127.0.0.1 -U postgres -d "$DB" -X -v ON_ERROR_STOP=1)
q() { "${PSQL[@]}" -At -F' | ' "$@"; }
FAIL=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; FAIL=1; }

RID6=re_R2REHEARSAL0000000006
RID7=re_R2REHEARSAL0000000007
P6="$PKG/R3_proposed_6_32913315.sql"
P7="$PKG/R3_proposed_7_700d469b.sql"
TMPL="$PKG/R3_record_refund.sql.tmpl"

fill() { python3 -I "$PKG/fill_r3.py" "$@" >/dev/null || { fail "fill $1"; return 1; }; }
fill6() { # out, then KEY=VALUE overrides on #6's values (bash 3.2: no associative arrays)
  local out=$1; shift
  local defaults=("LABEL=R2 #6 variant" PAYMENT_ID=32913315-2bf7-4e58-b837-f6c5c34b722b
    PI=pi_3U0XuwGdOzCmGbHw0WVJfW3y TOTAL_CENTS=1100 "REFUNDED_AT=2026-08-04 17:20:05+00"
    REFUND_ID=$RID6 STATUS=succeeded AMOUNT_CENTS=1100 SOURCE=dashboard)
  local args=() d o skip
  for d in "${defaults[@]}"; do
    skip=0; for o in "$@"; do [ "${o%%=*}" = "${d%%=*}" ] && skip=1; done
    [ $skip = 0 ] && args+=("$d")
  done
  args+=("$@")
  fill "$out" "${args[@]}"
}
fixture() { # out, payment id, pi
  fill6 "$1" PAYMENT_ID="$2" PI="$3" REFUND_ID=re_R2CONTROL00000000001 LABEL="R2 control"
}
expect_raise() { # name, file, expected substring
  local err rc
  err=$("${PSQL[@]}" -q -f "$2" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && grep -qF -- "$3" <<<"$err"; then
    pass "$1 refused: $(grep -oE 'R3_[A-Z]+ [^"]*' <<<"$err" | head -1 | cut -c1-140)"
  else fail "$1 rc=$rc: $(head -3 <<<"$err")"; fi
}
expect_notice() { # name, file, expected substring (in a NOTICE); returns the notice
  local out rc
  out=$("${PSQL[@]}" -q -f "$2" 2>&1); rc=$?
  if [ $rc -eq 0 ] && grep -qF -- "$3" <<<"$out"; then pass "$1: $(grep -oE 'R3_OK.*' <<<"$out" | cut -c1-200)"
  else fail "$1 rc=$rc: $(head -3 <<<"$out")"; fi
}
counts() { q -c "select (select count(*) from public.payment_refund_state)||' state, '||(select count(*) from public.payment_refund_state_log)||' log, '||(select count(*) from public.payment_refunds)||' ledger, '||(select count(*) from ops.\"case\")||' cases'"; }

echo "== R2 run $(date -u +%FT%TZ) on $DB (ledger $(q -c 'select count(*) from supabase_migrations.schema_migrations'))"
echo "== proposed files: $(shasum -a 256 "$P6" "$P7" | awk '{printf "%s %s; ", substr($1,1,16), $2}' | sed "s#$PKG/##g")"
"${PSQL[@]}" -q -f "$HERE/R2_fixtures.sql" >/dev/null || { echo "fixtures failed"; exit 3; }
echo "== after fixtures: $(counts)"
echo "== settings: $(q -c "select string_agg(key||'='||value::text, ', ' order by key) from ops.setting where key in ('refund_state_detection_enabled','refund_execute_enabled','refund_resolution_detector_enabled')")"
echo "== R4 read-back BEFORE"; q -f "$PKG/R4_readback.sql"

echo "== refusals"
expect_raise C1 "$P6" "R3_GUARD input: __R1_REFUND_ID__ is not a Stripe refund id"
fill6 "$GEN/c2.sql" REFUND_ID=70000000000000000000001; expect_raise C2 "$GEN/c2.sql" "is not a Stripe refund id"
fill6 "$GEN/c3.sql" STATUS=pending;                    expect_raise C3 "$GEN/c3.sql" "refund status pending is out of scope"
fill6 "$GEN/c4.sql" SOURCE=reconcile;                  expect_raise C4 "$GEN/c4.sql" "source reconcile is not one of the four"
fill6 "$GEN/c5.sql" AMOUNT_CENTS=600;                  expect_raise C5 "$GEN/c5.sql" "refund amount 600 differs from total 1100"
fixture "$GEN/c6.sql" a2000000-0000-4000-8000-000000000001 pi_R2TESTMODE000000000001; expect_raise C6 "$GEN/c6.sql" "stripe_livemode is f"
fixture "$GEN/c7.sql" a2000000-0000-4000-8000-000000000002 pi_R2HAZARDONE00000000001; expect_raise C7 "$GEN/c7.sql" "1 ledger row(s) already exist"
fixture "$GEN/c8.sql" a2000000-0000-4000-8000-000000000003 pi_R2HAZARDTWO00000000001; expect_raise C8 "$GEN/c8.sql" "1 transfer(s) of this payment carry a payout"
fixture "$GEN/c9.sql" a2000000-0000-4000-8000-000000000004 pi_R2REFIDSET000000000001; expect_raise C9 "$GEN/c9.sql" "payments.stripe_refund_id already holds"
c=$(counts); [ "$c" = "0 state, 0 log, 2 ledger, 0 cases" ] && pass "nothing written by C1-C9: $c" || fail "after refusals: $c"

echo "== writes: the committed files with only the three markers replaced"
sed -e "s/__R1_REFUND_ID__/$RID6/" -e "s/__R1_REFUND_STATUS__/succeeded/" -e "s/__OWNER_SOURCE__/dashboard/" "$P6" > "$GEN/w6.sql"
sed -e "s/__R1_REFUND_ID__/$RID7/" -e "s/__R1_REFUND_STATUS__/succeeded/" -e "s/__OWNER_SOURCE__/dashboard/" "$P7" > "$GEN/w7.sql"
for n in 6 7; do
  src=$P6; [ $n = 7 ] && src=$P7
  d=$(diff "$src" "$GEN/w$n.sql" | grep -c '^>')
  [ "$d" = 3 ] && pass "w$n differs from the committed file in exactly 3 lines" || fail "w$n differs in $d lines"
done
before=$(q -c "select ops.detect_refunds()::text")
expect_notice W6 "$GEN/w6.sql" "R3_OK"
expect_notice W7 "$GEN/w7.sql" "R3_OK"
after=$(q -c "select ops.detect_refunds()::text")
echo "   detect_refunds before: $before"
echo "   detect_refunds after:  $after"
[ "$(jq -c '{scanned,opened}' <<<"$before")" = "$(jq -c '{scanned,opened}' <<<"$after")" ] && [ "$(jq .opened <<<"$after")" = 0 ] \
  && pass "detect_refunds unchanged, 0 opened" || fail "detect_refunds changed"
echo "== R4 read-back AFTER"; q -f "$PKG/R4_readback.sql"
c=$(counts); [ "$c" = "2 state, 2 log, 4 ledger, 0 cases" ] && pass "totals after writes: $c" || fail "after writes: $c"
expect_raise W6-again "$GEN/w6.sql" "R3_GUARD prestate:"   # any prestate guard; run 1 showed amount_refunded_cents fires first

echo "== mutants (rolled back)"
mutant() { # name, exact block to remove, fixture id, fixture pi, expected substring, expect ok|raise
  local name=$1 block=$2 id=$3 pi=$4 want=$5 mode=$6 f="$GEN/$1.sql"
  python3 -I - "$TMPL" "$f" "$block" "$id" "$pi" <<'PY' || { fail "$name: mutant not applied"; return; }
import sys
tmpl, out, block, pid, pi = sys.argv[1:6]
t = open(tmpl).read()
if t.count(block) != 1: sys.exit(1)
t = t.replace(block, "")
vals = {"LABEL": "R2 mutant", "PAYMENT_ID": pid, "PI": pi, "TOTAL_CENTS": "1100",
        "REFUNDED_AT": "2026-08-04 17:20:05+00", "REFUND_ID": "re_R2MUTANT000000000001", "STATUS": "succeeded",
        "AMOUNT_CENTS": "1100", "SOURCE": "dashboard"}
for k, v in vals.items(): t = t.replace("{{" + k + "}}", v)
assert "{{" not in t
open(out, "w").write("begin;\n" + t + "\nrollback;\n")
PY
  grep -qF -- "$(head -1 <<<"$block")" "$f" && { fail "$name: block still present"; return; }
  if [ "$mode" = ok ]; then expect_notice "$name" "$f" "$want"; else expect_raise "$name" "$f" "$want"; fi
}
mutant M1 "  if v_pay.stripe_livemode is distinct from true then
    raise exception 'R3_GUARD prestate: stripe_livemode is %; only live payments are reconciled', v_pay.stripe_livemode;
  end if;
" a2000000-0000-4000-8000-000000000001 pi_R2TESTMODE000000000001 "R3_OK" ok
mutant M2 "  if v_n <> 0 then  -- hazard 1: a ledger row under another key would double-count
    raise exception 'R3_GUARD prestate: % ledger row(s) already exist for this payment or refund id', v_n;
  end if;
" a2000000-0000-4000-8000-000000000002 pi_R2HAZARDONE00000000001 "R3_ASSERT ledger rows: 2" raise
mutant M3 "  if v_n <> 0 then  -- hazard 2: a paid transfer would raise REFUNDED_AFTER_PAYOUT
    raise exception 'R3_GUARD prestate: % transfer(s) of this payment carry a payout', v_n;
  end if;
" a2000000-0000-4000-8000-000000000003 pi_R2HAZARDTWO00000000001 "R3_ASSERT payout records changed" raise
c=$(counts); [ "$c" = "2 state, 2 log, 4 ledger, 0 cases" ] && pass "mutants rolled back: $c" || fail "after mutants: $c"

echo "== raw hazard-1 control (no script, rolled back)"
raw=$(q -q <<'SQL'
begin;
select status||' '||amount_refunded_cents from public.payments where id = 'a2000000-0000-4000-8000-000000000005';
select (public.record_refund_state('pi_R2PARTIAL0000000000001', 're_R2DIFFERENTKEY000001', 'succeeded', 600, null,
                                   'admin', 'reconcile') ->> 'recorded');
select status||' '||amount_refunded_cents from public.payments where id = 'a2000000-0000-4000-8000-000000000005';
rollback;
SQL
)
echo "   $(tr '\n' '|' <<<"$raw")"
[ "$(tr '\n' '|' <<<"$raw")" = "succeeded 600|true|refunded 1100|" ] \
  && pass "hazard 1 is real: a second key turns a 600 partial into a full refund" || fail "raw control: $raw"

echo "== positive control for the '0 opened' above (rolled back): a FAILED refund state must open a case here"
pc=$(q -q <<'SQL'
begin;
select (public.record_refund_state('pi_R2REFIDSET000000000001', 're_R2FAILEDCONTROL000001', 'failed', 1100,
                                   'expired_or_canceled_card', 'dashboard', 'reconcile') ->> 'recorded');
select (ops.detect_refunds() ->> 'opened');
select count(*) from ops."case" where case_type = 'refund_failed' and subject_ref = 're_R2FAILEDCONTROL000001';
rollback;
SQL
)
echo "   $(tr '\n' '|' <<<"$pc")"
[ "$(tr '\n' '|' <<<"$pc")" = "true|1|1|" ] && pass "detect_refunds opens a refund_failed case for a failed state, so its 0 for succeeded rows discriminates" \
  || fail "positive control: $pc"
c=$(counts); [ "$c" = "2 state, 2 log, 4 ledger, 0 cases" ] && pass "positive control rolled back: $c" || fail "after positive control: $c"

echo "== RESULT: $([ $FAIL = 0 ] && echo ALL PASS || echo FAILURES)"
exit $FAIL
