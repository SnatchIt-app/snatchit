#!/bin/bash
# O-R4 R2b outcome matrix. LOCAL ONLY. Usage: bash run_R2b_outcomes.sh <or4_r2_rehears* database, fresh clone>
set -uo pipefail
DB=${1:?database}
case "$DB" in or4_r2_rehears*) :;; *) echo "refusing database $DB"; exit 2;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
PSQL=(psql -h 127.0.0.1 -U postgres -d "$DB" -X -q -v ON_ERROR_STOP=1 -At -F' | ')
"${PSQL[@]}" -f "$HERE/R2_fixtures.sql" >/dev/null || { echo "fixtures failed"; exit 3; }
PI=pi_3U0XuwGdOzCmGbHw0WVJfW3y
PID=32913315-2bf7-4e58-b837-f6c5c34b722b
FAIL=0

# outcome: name, expected row, then the SQL calls (one per refund object); an optional extra statement runs before the tick
outcome() {
  local name=$1 want=$2 calls=$3 pre=${4:-}
  local got
  got=$("${PSQL[@]}" <<SQL
begin;
\o /dev/null
$calls
$pre
\o
select (select count(*) from public.payment_refund_state where payment_id = '$PID')
    || '/' || (select count(*) from public.payment_refund_state_log where payment_id = '$PID')
    || '/' || (select count(*) from public.payment_refunds where payment_id = '$PID')
    || '; ' || coalesce(p.amount_refunded_cents::text, 'NULL')
    || '; (' || p.refund_requested_cents || ',' || p.refund_succeeded_cents || ',' || p.refund_failed_cents || ')'
    || '; ' || p.status
    || '; refunded_at ' || case when date_trunc('second', p.refunded_at) = '2026-08-04 17:20:05+00' then 'unchanged' else 'CHANGED' end
    || '; transfer ' || (select case when t.status = 'reversed' and t.payout_released_at is null and t.stripe_transfer_id is null
                                     then 'unchanged' else 'CHANGED' end from public.transfers t where t.payment_id = p.id)
    || '; payout rows ' || ((select count(*) from public.payout_decisions d where d.payment_id = p.id)
                            + (select count(*) from public.payout_attempts a join public.transfers t on t.id = a.transfer_id
                                where t.payment_id = p.id))
  from public.payments p where p.id = '$PID';
select 'opened ' || (ops.detect_refunds() ->> 'opened');
-- a separate statement: within one statement the case inserted by detect_refunds() is not yet visible
select 'cases ' || coalesce((select string_agg(c.case_type || ':' || c.priority, ',' order by c.case_type)
          from ops."case" c where c.subject_ref like 're_R2B%'), 'none');
rollback;
SQL
)
  got=$(tr '\n' ' ' <<<"$got" | sed -e 's/ *$//' -e 's/ cases /; cases /')
  if [ "$got" = "$want" ]; then echo "PASS $name: $got"; else echo "FAIL $name"; echo "     want: $want"; echo "     got:  $got"; FAIL=1; fi
}
rs() { echo "select public.record_refund_state('$PI', '$1', '$2', $3, $4, 'dashboard', 'reconcile');"; }

echo "== R2b run $(date -u +%FT%TZ) on $DB; detection: $("${PSQL[@]}" -c "select value from ops.setting where key = 'refund_state_detection_enabled'")"
outcome O1 "1/1/1; 1100; (0,1100,0); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 0; cases none" \
  "$(rs re_R2B000000000001 succeeded 1100 null)"
outcome O2 "1/1/1; 1100; (1100,0,0); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 0; cases none" \
  "$(rs re_R2B000000000002 pending 1100 null)"
outcome O2t "1/1/1; 1100; (1100,0,0); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 1; cases refund_pending:p1" \
  "$(rs re_R2B000000000002 pending 1100 null)" \
  "update public.payment_refund_state set first_observed_at = now() - interval '121 hours' where stripe_refund_id = 're_R2B000000000002';  -- SIMULATION of elapsed time"
outcome O3 "1/1/1; 1100; (1100,0,0); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 0; cases none" \
  "$(rs re_R2B000000000003 requires_action 1100 null)"
outcome O4 "1/1/0; NULL; (0,0,1100); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 1; cases refund_failed:p1" \
  "$(rs re_R2B000000000004 failed 1100 "'insufficient_funds'")"
outcome O5 "1/1/0; NULL; (0,0,1100); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 1; cases refund_failed:p1" \
  "$(rs re_R2B000000000005 canceled 1100 null)"
outcome O6 "2/2/2; 1100; (0,1100,0); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 0; cases none" \
  "$(rs re_R2B000000000061 succeeded 600 null) $(rs re_R2B000000000062 succeeded 500 null)"
outcome O7 "2/2/1; 1100; (0,1100,1100); refunded; refunded_at unchanged; transfer unchanged; payout rows 0 opened 0; cases none" \
  "$(rs re_R2B000000000071 failed 1100 "'expired_or_canceled_card'") $(rs re_R2B000000000072 succeeded 1100 null)"
echo "== after all branches (all rolled back): $("${PSQL[@]}" -c "select count(*) || ' state rows, ' || (select count(*) from ops.\"case\") || ' cases' from public.payment_refund_state")"
echo "== RESULT: $([ $FAIL = 0 ] && echo ALL PASS || echo FAILURES)"
exit $FAIL
