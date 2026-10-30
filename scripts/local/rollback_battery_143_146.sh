#!/bin/bash
# LOCAL-ONLY disable/recovery battery for 143-146 (D, 2026-09-21).
#
# The owner's requirement is not "the rollback runs" — it is "preserve case history; provide a
# disable/recovery path after cases exist instead of requiring deletion to recover". So each case
# below asserts the STATE AFTER the rollback, not merely that it exited 0:
#   B1  144 rolled back on a VIRGIN database          -> full reversal, detector gone
#   B2  144 rolled back AFTER cases/events exist      -> DISABLED, every row still there
#   B3  145 rolled back                                -> 143's exact detect_jobs body returns
#   B4  146 rolled back                                -> 117's exact alert_fire body returns, columns gone, alert rows kept
# usage: rollback_battery_143_146.sh <base-db-that-has-the-full-chain>
#
# NOT VACUOUS, and we know because it has been run wrong: A copied this file out of the repo tree,
# ROOT resolved somewhere without supabase/rollbacks, the rollbacks silently never applied, and the
# battery failed 8 of 21 on exactly the state assertions. That is the negative control for the whole
# script — with nothing rolled back, it refuses to report success. The guard below turns that
# particular misuse into an instant, legible refusal instead of eight puzzling failures.
set -u
export LC_ALL=C PGHOST=${PGHOST:-127.0.0.1} PGPORT=${PGPORT:-5432} PGUSER=${PGUSER:-postgres}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; BASE="${1:-}"; RC=0
[ -n "$BASE" ] || { echo "usage: $(basename "$0") <base-db-that-has-the-full-chain>"; exit 2; }
for f in supabase/rollbacks/144_ops_refund_resolution_detector_rollback.sql \
         supabase/rollbacks/145_ops_job_not_running_detection_rollback.sql \
         supabase/rollbacks/146_ops_alert_delivery_and_ack_rollback.sql \
         supabase/migrations/144_ops_refund_resolution_detector.sql; do
  [ -f "$ROOT/$f" ] || { echo "REFUSING: $ROOT/$f not found — run this from inside the repo tree, not a copy."; exit 2; }
done
q() { psql -X -qtA -d "$1" -c "$2" 2>&1; }
ok() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (got [$2] want [$3])"; RC=1; fi; }
fresh() { dropdb --if-exists "$1" >/dev/null 2>&1; createdb -T "$BASE" "$1" || { echo "createdb failed"; exit 1; }; }

echo "== reference bodies measured on the chain itself =="
DJ_146=$(q "$BASE" "select md5(pg_get_functiondef('ops.detect_jobs()'::regprocedure))")
AF_146=$(q "$BASE" "select md5(pg_get_functiondef('ops.alert_fire(text,text,jsonb)'::regprocedure))")
echo "  detect_jobs (with 145) = $DJ_146"
echo "  alert_fire  (with 146) = $AF_146"

# 143's detect_jobs and 117's alert_fire, as the rollbacks claim to restore them: install each into a
# throwaway db built from the chain, straight from the source file, and measure. This is the honest
# reference — not a hash copied from a previous session's notes.
fresh d_rb_ref143
psql -X -q -d d_rb_ref143 -v ON_ERROR_STOP=1 -f "$ROOT/supabase/rollbacks/145_ops_job_not_running_detection_rollback.sql" >/dev/null 2>&1
DJ_143=$(q d_rb_ref143 "select md5(pg_get_functiondef('ops.detect_jobs()'::regprocedure))")
echo "  detect_jobs (143 body, via 145 rollback) = $DJ_143"

echo
echo "== B1: 144 rolled back on a database where nobody has used it =="
fresh d_rb_b1
OUT=$(psql -X -q -d d_rb_b1 -v ON_ERROR_STOP=1 -f "$ROOT/supabase/rollbacks/144_ops_refund_resolution_detector_rollback.sql" 2>&1)
echo "$OUT" | grep -qi "disabled" && MODE=disabled || MODE=reversed
ok "B1.1 it takes the FULL REVERSAL path"                "$MODE" "reversed"
ok "B1.2 the detector function is gone"                  "$(q d_rb_b1 "select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname='detect_refund_resolution'")" "0"
ok "B1.3 the setting row is gone"                        "$(q d_rb_b1 "select count(*)::int from ops.setting where key='refund_resolution_detector_enabled'")" "0"

echo
echo "== B2: 144 rolled back AFTER an operator has classified a case (the owner's requirement) =="
fresh d_rb_b2
# a refund_resolution case with the full human trail: a classification, an obligation, a note
psql -X -q -d d_rb_b2 -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
insert into ops."case" (case_type, subject_kind, subject_id, subject_ref, dedupe_key, title, summary, status, priority, detector)
values ('refund_resolution','transfer','11111111-1111-1111-1111-111111111111','t1',
        'refund_resolution:11111111-1111-1111-1111-111111111111','Refund needs review','summary','open','p2','detect_refund_resolution');
insert into ops.case_event (case_id, actor, kind, data)
select id, null, 'classified', '{"classification":"B","reason":"Stripe shows a partial refund"}'::jsonb from ops."case" where subject_ref='t1';
insert into ops.case_event (case_id, actor, kind, data)
select id, null, 'obligation_changed', '{"kind":"payout_owed","settled":false}'::jsonb from ops."case" where subject_ref='t1';
insert into ops.case_note (case_id, author, body)
select id, null, 'support spoke to the seller' from ops."case" where subject_ref='t1';
SQL
CASES_BEFORE=$(q d_rb_b2 "select count(*)::int from ops.\"case\" where case_type='refund_resolution'")
EVENTS_BEFORE=$(q d_rb_b2 "select count(*)::int from ops.case_event")
NOTES_BEFORE=$(q d_rb_b2 "select count(*)::int from ops.case_note")
OUT=$(psql -X -q -d d_rb_b2 -v ON_ERROR_STOP=1 -f "$ROOT/supabase/rollbacks/144_ops_refund_resolution_detector_rollback.sql" 2>&1)
echo "$OUT" | grep -qi "disabl" && MODE=disabled || MODE=reversed
ok "B2.1 it takes the DISABLE path, not full reversal"   "$MODE" "disabled"
# the structural discriminator, independent of the NOTICE text: full reversal DELETES the setting row
# (B1.3 asserts 0), the disable path KEEPS it at false. Two different end states, not two different logs.
ok "B2.1b …structurally: the setting row is kept (B1.3 shows reversal deletes it)" "$(q d_rb_b2 "select count(*)::int from ops.setting where key='refund_resolution_detector_enabled'")" "1"
ok "B2.2 the case still exists"                          "$(q d_rb_b2 "select count(*)::int from ops.\"case\" where case_type='refund_resolution'")" "$CASES_BEFORE"
ok "B2.3 every case_event survives"                      "$(q d_rb_b2 "select count(*)::int from ops.case_event")" "$EVENTS_BEFORE"
ok "B2.4 the note survives"                              "$(q d_rb_b2 "select count(*)::int from ops.case_note")" "$NOTES_BEFORE"
ok "B2.5 the classification is still readable"           "$(q d_rb_b2 "select data->>'classification' from ops.case_event where kind='classified' limit 1")" "B"
ok "B2.6 the switch is left OFF so nothing detects"      "$(q d_rb_b2 "select value#>>'{}' from ops.setting where key='refund_resolution_detector_enabled'")" "false"
ok "B2.7 the case_type vocabulary is kept (rows stay legal)" "$(q d_rb_b2 "select count(*)::int from pg_constraint where conrelid='ops.\"case\"'::regclass and pg_get_constraintdef(oid) like '%refund_resolution%'")" "1"
# recovery: re-applying 144 after a disable must restore the detector without touching history
psql -X -q -d d_rb_b2 -v ON_ERROR_STOP=1 -f "$ROOT/supabase/migrations/144_ops_refund_resolution_detector.sql" >/dev/null 2>&1
ok "B2.8 RECOVERY: re-applying 144 restores the detector" "$(q d_rb_b2 "select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname='detect_refund_resolution'")" "1"
ok "B2.9 RECOVERY: history is still intact afterwards"    "$(q d_rb_b2 "select count(*)::int from ops.case_event")" "$EVENTS_BEFORE"
ok "B2.10 RECOVERY: the switch is still off"              "$(q d_rb_b2 "select value#>>'{}' from ops.setting where key='refund_resolution_detector_enabled'")" "false"

echo
echo "== B3: 145 rolled back =="
fresh d_rb_b3
psql -X -q -d d_rb_b3 -v ON_ERROR_STOP=1 -f "$ROOT/supabase/rollbacks/145_ops_job_not_running_detection_rollback.sql" >/dev/null 2>&1
ok "B3.1 detect_jobs returns to 143's exact body"        "$(q d_rb_b3 "select md5(pg_get_functiondef('ops.detect_jobs()'::regprocedure))")" "$DJ_143"
ok "B3.2 …which is NOT the 145 body"                     "$([ "$DJ_143" != "$DJ_146" ] && echo differs || echo same)" "differs"
ok "B3.3 the gap helper is gone"                         "$(q d_rb_b3 "select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname='cron_expected_gap_minutes'")" "0"

echo
echo "== B4: 146 rolled back =="
fresh d_rb_b4
psql -X -q -d d_rb_b4 -v ON_ERROR_STOP=1 >/dev/null 2>&1 -c "insert into ops.alert (alert_key, kind, state, payload) values ('rb:keepme','p1_case','firing','{}'::jsonb)"
psql -X -q -d d_rb_b4 -v ON_ERROR_STOP=1 -f "$ROOT/supabase/rollbacks/146_ops_alert_delivery_and_ack_rollback.sql" >/dev/null 2>&1
ok "B4.1 alert_fire returns to 117's body (differs from 146's)" "$([ "$(q d_rb_b4 "select md5(pg_get_functiondef('ops.alert_fire(text,text,jsonb)'::regprocedure))")" != "$AF_146" ] && echo differs || echo same)" "differs"
ok "B4.2 ops.alert is back to 8 columns"                 "$(q d_rb_b4 "select count(*)::int from information_schema.columns where table_schema='ops' and table_name='alert'")" "8"
ok "B4.3 the alert ROW survives the rollback"            "$(q d_rb_b4 "select count(*)::int from ops.alert where alert_key='rb:keepme'")" "1"
ok "B4.4 all four new functions are gone"                "$(q d_rb_b4 "select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname in ('dispatch_alerts','alert_ack','alert_post','alert_response')")" "0"
ok "B4.5 alert_fire still WORKS after the rollback"      "$(q d_rb_b4 "select (ops.alert_fire('rb:after','p1_case','{}'::jsonb)) is not null")" "t"

for d in d_rb_ref143 d_rb_b1 d_rb_b2 d_rb_b3 d_rb_b4; do dropdb --if-exists "$d" >/dev/null 2>&1; done
echo
[ $RC -eq 0 ] && echo "BATTERY: ALL PASS" || echo "BATTERY: FAILURES"
exit $RC
