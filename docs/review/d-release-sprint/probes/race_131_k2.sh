#!/bin/bash
# D: A-131-K2 races (131 @ f3963a3 (reason session_ended since F-131-K2a)) — a device's own session deleted (this-device sign-out) racing that device's registration.
# Two live sessions for the user, so the last-live-session path never fires. Throwaway clone; dropped at the end.
set -u
export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
SRC=${1:-snatchit_d_131k2_rehears}; DB=d131k2_race_rehears
dropdb --if-exists $DB 2>/dev/null; createdb -T $SRC $DB || exit 1
q(){ psql -X -qtA -d $DB -v ON_ERROR_STOP=1 -c "$1"; }
ms(){ python3 -c 'import time;print(int(time.time()*1000))'; }
V=d1320000-0000-4000-8000-0000000000f2
q "insert into auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values ('$V','00000000-0000-0000-0000-000000000000','authenticated','authenticated','k2race@test.local','pw','{}','{}',now(),now())" >/dev/null
sess(){ q "insert into auth.sessions (id,user_id,created_at,updated_at,aal) values (gen_random_uuid(),'$V',now()-interval '1 hour',now(),'aal1') returning id"; }
login(){ echo "select tap.login('$V'); select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb || jsonb_build_object('session_id','$1'))::text, true);"; }
KEEP=$(sess)   # another device stays signed in throughout

echo "KR1 registration commits first while holding the per-user lock; its own session's delete waits, then revokes it"
S=$(sess)
( psql -X -qtA -d $DB -c "begin; $(login $S) select public.register_push_token('ExponentPushToken[kr1]','ios','kr1-secret-00000000000000','x'); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
psql -X -qtA -d $DB -c "delete from auth.sessions where id='$S';" >/dev/null 2>&1; t1=$(ms); wait
st=$(q "select concat_ws('|', is_active, device_secret_hash is not null, revoked_reason) from public.push_tokens where token='ExponentPushToken[kr1]'")
echo "  delete waited $((t1-t0)) ms; binding: $st"
[ "$st" = "f|t|session_ended" ] && [ $((t1-t0)) -ge 2000 ] && echo "  PASS KR1" || echo "  FAIL KR1"

echo "KR2 the session delete commits first while holding the lock; that session's registration waits, then is refused"
S=$(sess)
( psql -X -qtA -d $DB -c "begin; delete from auth.sessions where id='$S'; select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "begin; $(login $S) select public.register_push_token('ExponentPushToken[kr2]','ios','kr2-secret-00000000000000','x'); commit;" 2>&1 | grep -oE 'session predates a credential change|"outcome": "[a-z_]+"' | head -1); t1=$(ms); wait
n=$(q "select count(*) from public.push_tokens where token='ExponentPushToken[kr2]'")
echo "  waited $((t1-t0)) ms → ${out:-<none>}; rows for kr2: $n"
[ "$out" = "session predates a credential change" ] && [ "$n" = "0" ] && [ $((t1-t0)) -ge 2000 ] && echo "  PASS KR2" || echo "  FAIL KR2"

echo "KR3 old-client direct INSERT racing its own session's delete (delete first)"
S=$(sess)
( psql -X -qtA -d $DB -c "begin; delete from auth.sessions where id='$S'; select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5
out=$(psql -X -qtA -d $DB -c "begin; $(login $S) insert into public.push_tokens (user_id, token, platform, is_active) values ('$V','ExponentPushToken[kr3]','ios',true); commit;" 2>&1 | grep -oE 'session predates a credential change|INSERT 0 1' | head -1); wait
n=$(q "select count(*) from public.push_tokens where token='ExponentPushToken[kr3]' and is_active")
echo "  → ${out:-<none>}; active rows for kr3: $n"
[ "$n" = "0" ] && echo "  PASS KR3" || echo "  FAIL KR3"

echo "KR4 old-client direct INSERT commits first (holding the lock); its session's delete waits and revokes the stamped row"
S=$(sess)
( psql -X -qtA -d $DB -c "begin; $(login $S) insert into public.push_tokens (user_id, token, platform, is_active) values ('$V','ExponentPushToken[kr4]','ios',true); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5
psql -X -qtA -d $DB -c "delete from auth.sessions where id='$S';" >/dev/null 2>&1; wait
st=$(q "select concat_ws('|', is_active, session_id = '$S', revoked_reason) from public.push_tokens where token='ExponentPushToken[kr4]'")
echo "  binding: $st"
[ "$st" = "f|t|session_ended" ] && echo "  PASS KR4" || echo "  FAIL KR4"

echo "KR5 deadlock attempt: client UPDATE (row lock) and its session's delete interleaved"
S=$(sess)
q "begin; $(login $S) select public.register_push_token('ExponentPushToken[kr5]','ios','kr5-secret-00000000000000','x'); commit;" >/dev/null
( psql -X -qtA -d $DB -c "begin; $(login $S) update public.push_tokens set device_name='y' where token='ExponentPushToken[kr5]'; select pg_sleep(2); update public.push_tokens set last_used=now() where token='ExponentPushToken[kr5]'; commit;" 2>&1 | grep -E 'deadlock' ) &
sleep 0.3
d=$(psql -X -qtA -d $DB -c "begin; delete from auth.sessions where id='$S'; select pg_sleep(1); commit;" 2>&1 | grep -c deadlock); wait
st=$(q "select concat_ws('|', is_active, revoked_reason) from public.push_tokens where token='ExponentPushToken[kr5]'")
echo "  deadlocks on the delete side: $d; binding: $st"
[ "$d" = "0" ] && [ "$st" = "f|session_ended" ] && echo "  PASS KR5" || echo "  FAIL KR5"

k=$(q "select count(*) from auth.sessions where id='$KEEP'")
echo "the other device's session survived: $k"
dropdb $DB
