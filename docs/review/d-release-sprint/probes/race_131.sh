#!/bin/bash
# D: two live sessions against a throwaway clone of the 131 certified DB. Committed fixtures; the clone is dropped.
set -u
export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
SRC=${1:-d131_tap_rehears}; DB=d131_race_rehears
dropdb --if-exists $DB 2>/dev/null; createdb -T $SRC $DB || exit 1
q(){ psql -X -qtA -d $DB -v ON_ERROR_STOP=1 -c "$1"; }
V=d1310000-0000-4000-8000-0000000000f1
q "insert into auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values ('$V','00000000-0000-0000-0000-000000000000','authenticated','authenticated','race@test.local','old','{}','{}',now(),now())" >/dev/null
SID=$(q "insert into auth.sessions (id,user_id,created_at,updated_at,aal) values (gen_random_uuid(),'$V',now()-interval '1 hour',now(),'aal1') returning id")
LOGIN="select tap.login('$V'); select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb || jsonb_build_object('session_id','$SID'))::text, true);"
q "begin; $LOGIN select public.register_push_token('ExponentPushToken[race-phone]','ios','race-secret-000000000000','x'); commit;" >/dev/null
ms(){ python3 -c 'import time;print(int(time.time()*1000))'; }

echo "R1 password change holds the lock; old-session registration arrives during it"
( psql -X -qtA -d $DB -c "begin; update auth.users set encrypted_password='new1', updated_at=now() where id='$V'; select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "begin; $LOGIN select public.register_push_token('ExponentPushToken[race-phone-2]','ios','race-secret-000000000000','x'); commit;" 2>&1 | grep -oE 'session predates a credential change|"outcome": "[a-z_]+"' | head -1); t1=$(ms); wait
echo "  waited $((t1-t0)) ms → ${out:-<none>}"
[ "$out" = "session predates a credential change" ] && [ $((t1-t0)) -ge 2000 ] && echo "  PASS R1" || echo "  FAIL R1"

echo "R2 direct-table activation with the old session racing a second password change"
( psql -X -qtA -d $DB -c "begin; update auth.users set encrypted_password='new2', updated_at=now() where id='$V'; select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "begin; $LOGIN update public.push_tokens set is_active=true where token='ExponentPushToken[race-phone]'; commit;" 2>&1 | grep -oE 'session predates a credential change|UPDATE [0-9]+' | head -1); t1=$(ms); wait
echo "  waited $((t1-t0)) ms → ${out:-<no error>}"
[ "$out" = "session predates a credential change" ] && echo "  PASS R2" || echo "  FAIL R2"

echo "R3 a NEW-session registration commits first while holding the lock; the password change waits and then revokes it"
NSID=$(q "insert into auth.sessions (id,user_id,created_at,updated_at,aal) values (gen_random_uuid(),'$V',clock_timestamp()+interval '10 seconds',now(),'aal1') returning id")
NLOGIN="select tap.login('$V'); select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb || jsonb_build_object('session_id','$NSID'))::text, true);"
( psql -X -qtA -d $DB -c "begin; $NLOGIN select public.register_push_token('ExponentPushToken[race-new]','ios','race-new-secret-0000000000','x'); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
psql -X -qtA -d $DB -c "begin; update auth.users set encrypted_password='new3', updated_at=now() where id='$V'; commit;" >/dev/null 2>&1; t1=$(ms); wait
st=$(q "select concat_ws('|', is_active, device_secret_hash is null, revoked_reason) from public.push_tokens where token='ExponentPushToken[race-new]'")
echo "  password change waited $((t1-t0)) ms; new binding after it: $st"
[ "$st" = "f|t|password_changed" ] && [ $((t1-t0)) -ge 2000 ] && echo "  PASS R3" || echo "  FAIL R3"

echo "R4 deadlock attempt: client UPDATE and GoTrue-shaped session delete interleaved in both orders"
S2=$(q "insert into auth.sessions (id,user_id,created_at,updated_at,aal) values (gen_random_uuid(),'$V',clock_timestamp(),now(),'aal1') returning id")
NL2="select tap.login('$V'); select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb || jsonb_build_object('session_id','$S2'))::text, true);"
( psql -X -qtA -d $DB -c "begin; $NL2 update public.push_tokens set device_name='x' where user_id='$V' and is_active is false; select pg_sleep(2); update public.push_tokens set last_used=now() where user_id='$V'; commit;" 2>&1 | grep -E 'deadlock' ) &
sleep 0.3
d=$(psql -X -qtA -d $DB -c "begin; delete from auth.sessions where user_id='$V'; select pg_sleep(1); commit;" 2>&1 | grep -c deadlock); wait
echo "  deadlock errors seen by the session-delete side: $d"
[ "$d" = "0" ] && echo "  PASS R4 (no 40P01 on either side above)" || echo "  FAIL R4"
dropdb $DB
